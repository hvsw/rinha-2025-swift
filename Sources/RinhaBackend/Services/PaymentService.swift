import Vapor
import Foundation
import NIOCore

actor PaymentService {
    private let app: Application
    private let defaultProcessorURL: String
    private let fallbackProcessorURL: String
    
    // Payment tracking
    private var acceptedPayments: [PaymentRecord] = []
    private var processedPayments: [PaymentRecord] = []
    private var lastHealthCheck: [ProcessorType: (date: Date, health: HealthCheckResponse)] = [:]
    private var isProcessingQueue = false
    private var retryAttempts: [UUID: Int] = [:]
    private var pendingPayments: [PaymentProcessorRequest] = []
    
    // Configuration
    private let maxRetryAttempts = 8
    private let batchSize = 50
    private let processingDelay: UInt64 = 500_000  // 0.5ms
    private let healthCheckInterval: TimeInterval = 5.0
    
    // Reusable formatters to avoid expensive instantiation
    private static let iso8601Formatter: ISO8601DateFormatter = ISO8601DateFormatter()
    
    init(app: Application) {
        self.app = app
        self.defaultProcessorURL = Environment.get("DEFAULT_PROCESSOR_URL") ?? "http://payment-processor-default:8080"
        self.fallbackProcessorURL = Environment.get("FALLBACK_PROCESSOR_URL") ?? "http://payment-processor-fallback:8080"
        
        // Start concurrent workers for high volume processing
        for workerID in 0..<8 {
            Task {
                await startWorker(workerID: workerID)
            }
        }
    }
    
    func processPayment(request: PaymentRequest) async throws -> HTTPStatus {
        // Use single timestamp for consistency between backend and processor
        let requestedAt = Date()
        
        let processorRequest = PaymentProcessorRequest(
            correlationId: request.correlationId,
            amount: request.amount,
            requestedAt: Self.iso8601Formatter.string(from: requestedAt)
        )
        
        // Track as accepted immediately when we return HTTP 202
        let acceptedRecord = PaymentRecord(
            correlationId: request.correlationId,
            amount: request.amount,
            requestedAt: requestedAt,
            processor: .default,
            processedAt: nil
        )
        acceptedPayments.append(acceptedRecord)
        
        await enqueuePayment(processorRequest)
        return .accepted
    }
    
    private func enqueuePayment(_ request: PaymentProcessorRequest) async {
        pendingPayments.append(request)
        retryAttempts[request.correlationId] = 0
        print("💰 Payment enqueued: \(request.correlationId), total in queue: \(pendingPayments.count)")
    }
    
    private func startWorker(workerID: Int) async {
        print("🚀 Worker \(workerID) started")
        while true {
            if !pendingPayments.isEmpty && !isProcessingQueue {
                print("📦 Worker \(workerID) processing \(pendingPayments.count) payments")
                await processQueue()
            }
            
            try? await Task.sleep(nanoseconds: processingDelay)
        }
    }
    
    private func processQueue() async {
        guard !isProcessingQueue else { return }
        isProcessingQueue = true
        defer { isProcessingQueue = false }
        
        let batch = Array(pendingPayments.prefix(batchSize))
        
        // Remove processed payments from queue immediately to prevent race conditions
        if !batch.isEmpty {
            let batchIds = Set(batch.map { $0.correlationId })
            pendingPayments.removeAll { batchIds.contains($0.correlationId) }
        }
        
        await withTaskGroup(of: Void.self) { group in
            for request in batch {
                group.addTask {
                    await self.processPayment(request: request)
                }
            }
        }
    }
    
    private func processPayment(request: PaymentProcessorRequest) async {
        let attempts = retryAttempts[request.correlationId] ?? 0
        let processors = await getOptimalProcessorOrder()
        
        for processor in processors {
            let success = await sendToProcessor(request: request, processor: processor)
            if success {
                await recordProcessedPayment(request: request, processor: processor)
                retryAttempts.removeValue(forKey: request.correlationId)
                return
            }
        }
        
        // Retry logic
        if attempts < maxRetryAttempts {
            retryAttempts[request.correlationId] = attempts + 1
            let delay = min(UInt64(pow(2.0, Double(attempts))) * 500_000, 50_000_000) // Max 50ms
            try? await Task.sleep(nanoseconds: delay)
            
            // Re-add to queue for retry
            pendingPayments.append(request)
        } else {
            // Final attempt - force to fallback
            let success = await sendToProcessor(request: request, processor: .fallback)
            if success {
                await recordProcessedPayment(request: request, processor: .fallback)
            }
            retryAttempts.removeValue(forKey: request.correlationId)
        }
    }
    
    private func sendToProcessor(request: PaymentProcessorRequest, processor: ProcessorType) async -> Bool {
        do {
            let url = processor == .default ? defaultProcessorURL : fallbackProcessorURL
            let uri = URI(string: "\(url)/payments")
            
            print("🚀 Sending payment \(request.correlationId) to \(processor) at \(url)")
            print("📦 Request data: correlationId=\(request.correlationId), amount=\(request.amount)")
            
            let response = try await app.client.post(uri) { req in
                try req.content.encode(request)
                req.headers.replaceOrAdd(name: .contentType, value: "application/json; charset=utf-8")
                req.headers.add(name: .connection, value: "keep-alive")
                req.headers.add(name: .accept, value: "application/json")
                req.headers.add(name: .userAgent, value: "Swift-Vapor-Client")
                print("📋 Content-Type: \(req.headers[.contentType])")
            }
            
            let success = response.status == .ok
            print("📡 Payment \(request.correlationId) response: \(response.status) -> \(success ? "SUCCESS" : "FAILED")")
            return success
        } catch {
            print("❌ Payment \(request.correlationId) to \(processor) failed: \(error)")
            await markProcessorUnhealthy(processor)
            return false
        }
    }
    
    private func getOptimalProcessorOrder() async -> [ProcessorType] {
        let defaultHealthy = await isProcessorHealthy(.default)
        let fallbackHealthy = await isProcessorHealthy(.fallback)
        
        switch (defaultHealthy, fallbackHealthy) {
        case (true, true):
            return [.default, .fallback]  // Prefer default for lower fees
        case (true, false):
            return [.default]
        case (false, true):
            return [.fallback]
        case (false, false):
            return [.default, .fallback]  // Try both anyway
        }
    }
    
    private func isProcessorHealthy(_ processor: ProcessorType) async -> Bool {
        let now = Date()
        
        if let lastCheck = lastHealthCheck[processor],
           now.timeIntervalSince(lastCheck.date) < healthCheckInterval {
            return !lastCheck.health.failing
        }
        
        let health = await checkProcessorHealth(processor)
        lastHealthCheck[processor] = (date: now, health: health)
        return !health.failing
    }
    
    private func checkProcessorHealth(_ processor: ProcessorType) async -> HealthCheckResponse {
        do {
            let url = processor == .default ? defaultProcessorURL : fallbackProcessorURL
            let uri = URI(string: "\(url)/payments/service-health")
            
            let response = try await app.client.get(uri) { req in
                req.headers.add(name: .accept, value: "application/json")
            }
            
            if response.status == .ok {
                return try response.content.decode(HealthCheckResponse.self)
            } else {
                return HealthCheckResponse(failing: true, minResponseTime: 9999)
            }
        } catch {
            return HealthCheckResponse(failing: true, minResponseTime: 9999)
        }
    }
    
    private func markProcessorUnhealthy(_ processor: ProcessorType) async {
        lastHealthCheck[processor] = (
            date: Date(),
            health: HealthCheckResponse(failing: true, minResponseTime: 9999)
        )
    }
        
    private func recordProcessedPayment(request: PaymentProcessorRequest, processor: ProcessorType) async {
        let processedAt = Date()
        
        // Use original requestedAt timestamp from accepted payment record
        let originalRequestedAt: Date
        if let acceptedRecord = acceptedPayments.first(where: { $0.correlationId == request.correlationId }) {
            originalRequestedAt = acceptedRecord.requestedAt
        } else {
            // Fallback - shouldn't happen in normal flow
            originalRequestedAt = processedAt
        }
        
        let record = PaymentRecord(
            correlationId: request.correlationId,
            amount: request.amount,
            requestedAt: originalRequestedAt,
            processor: processor,
            processedAt: processedAt
        )
        processedPayments.append(record)
        
        // Update the accepted payment record with actual processor used
        if let index = acceptedPayments.firstIndex(where: { $0.correlationId == request.correlationId }) {
            acceptedPayments[index].processor = processor
            acceptedPayments[index].processedAt = processedAt
        }
        
        retryAttempts.removeValue(forKey: request.correlationId)
    }

    func getPaymentsSummary(from: Date?, to: Date?) async -> PaymentSummaryResponse {
        // Use PROCESSED payments (actually sent to processors)
        let filteredPayments = processedPayments.filter { payment in
            if let from = from, payment.requestedAt < from {
                return false
            }
            if let to = to, payment.requestedAt > to {
                return false
            }
            return true
        }
        
        let defaultPayments = filteredPayments.filter { $0.processor == .default }
        let fallbackPayments = filteredPayments.filter { $0.processor == .fallback }
        
        let defaultSummary = ProcessorSummary(
            totalRequests: defaultPayments.count,
            totalAmount: defaultPayments.reduce(0) { $0 + $1.amount }
        )
        
        let fallbackSummary = ProcessorSummary(
            totalRequests: fallbackPayments.count,
            totalAmount: fallbackPayments.reduce(0) { $0 + $1.amount }
        )
        
        return PaymentSummaryResponse(
            default: defaultSummary,
            fallback: fallbackSummary
        )
    }
    
    func flushQueueCompletely() async {
        var attempts = 0
        let maxFlushAttempts = 100
        
        while !pendingPayments.isEmpty && attempts < maxFlushAttempts {
            await processQueue()
            try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
            attempts += 1
        }
    }

    func getProcessedPayments() async -> [PaymentRecord] {
        return processedPayments
    }

    // MARK: - Queue Statistics
    
    func getQueueStats() async -> QueueStats {
        return QueueStats(
            pending: pendingPayments.count,
            processing: isProcessingQueue ? 1 : 0,
            accepted: acceptedPayments.count,
            processed: processedPayments.count
        )
    }
    
    func getQueueStatus() async -> String {
        let stats = await getQueueStats()
        return "Pending: \(stats.pending), Processed: \(stats.processed), Processing: \(stats.processing > 0 ? "YES" : "NO")"
    }
    
    func forceCompleteQueueProcessing() async {
        var attempts = 0
        while !pendingPayments.isEmpty && attempts < 100 {
            await processQueue()
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            attempts += 1
        }
    }
} 
