import Vapor
import Foundation
import NIOCore

actor PaymentService {
    private let app: Application
    private let defaultProcessorURL: String
    private let fallbackProcessorURL: String
    
    // PHASE 2D: Final consistency push - zero inconsistency target
    private var acceptedPayments: [PaymentRecord] = []  // All payments we accepted (HTTP 202)
    private var processedPayments: [PaymentRecord] = []  // Only payments successfully sent to processors
    private var lastHealthCheck: [ProcessorType: (date: Date, health: HealthCheckResponse)] = [:]
    private var isProcessingQueue = false
    private var retryAttempts: [UUID: Int] = [:]
    
    // PHASE 2D: Queue management
    private var pendingPayments: [PaymentProcessorRequest] = []
    private var processingPayments: Set<UUID> = []
    
    // PHASE 2C: Proven optimal settings - revert to best performing configuration
    private let maxRetryAttempts = 10        // Phase 2C proven setting
    private let batchSize = 20               // Phase 2C proven setting  
    private let processingDelay: UInt64 = 2_000_000  // 2ms - Phase 2C setting
    private let timeoutDuration: TimeInterval = 4.0  // 4s - Phase 2C setting
    private let healthCheckInterval: TimeInterval = 10.0  // 10s - Phase 2C setting
    
    init(app: Application) {
        self.app = app
        self.defaultProcessorURL = "http://payment-processor:3001"
        self.fallbackProcessorURL = "http://payment-processor:3002"
        
        // Start Phase 2C proven processor
        Task {
            await startProvenProcessor()
        }
    }
    
    func processPayment(request: PaymentRequest) async throws -> HTTPStatus {
        let processorRequest = PaymentProcessorRequest(
            correlationId: request.correlationId,
            amount: request.amount,
            requestedAt: Date()
        )
        
        // PHASE 2B: Track as accepted immediately when we return HTTP 202
        let acceptedRecord = PaymentRecord(
            correlationId: request.correlationId,
            amount: request.amount,
            requestedAt: Date(),
            processor: .default,  // Will be updated when actually processed
            processedAt: nil  // Will be set when actually processed
        )
        acceptedPayments.append(acceptedRecord)
        
        // Add to queue for processing
        await enqueuePayment(processorRequest)
        
        // Return 202 Accepted for async processing
        return .accepted
    }
    
    private func enqueuePayment(_ request: PaymentProcessorRequest) async {
        pendingPayments.append(request)
        retryAttempts[request.correlationId] = 0  // Initialize retry count
        
        // PHASE 2D: The ultra-aggressive processor is already running in background
        // No need to start additional processing - it will pick up the new payment
    }
    
    // PHASE 2C: Proven queue processor - optimal performance
    private func startProvenProcessor() async {
        while true {
            if !pendingPayments.isEmpty && !isProcessingQueue {
                await processQueueProven()
            }
            
            // Phase 2C proven polling interval
            try? await Task.sleep(nanoseconds: processingDelay)
        }
    }
    
    // PHASE 2C: Process queue with proven settings
    private func processQueueProven() async {
        guard !isProcessingQueue else { return }
        isProcessingQueue = true
        defer { isProcessingQueue = false }
        
        // Process in Phase 2C proven batch size
        let batch = Array(pendingPayments.prefix(batchSize))
        
        await withTaskGroup(of: Void.self) { group in
            for request in batch {
                group.addTask {
                    await self.processPaymentProven(request: request)
                }
            }
        }
    }
    
    // PHASE 2C: Proven payment processing
    private func processPaymentProven(request: PaymentProcessorRequest) async {
        let attempts = retryAttempts[request.correlationId] ?? 0
        
        // Try both processors with health-based preference
        let processors: [ProcessorType] = await getOptimalProcessorOrder()
        
        for processor in processors {
            let success = await sendToProcessorProven(request: request, processor: processor)
            if success {
                await recordProcessedPayment(request: request, processor: processor)
                pendingPayments.removeAll { $0.correlationId == request.correlationId }
                retryAttempts.removeValue(forKey: request.correlationId)
                return
            }
        }
        
        // Phase 2C proven retry logic
        if attempts < maxRetryAttempts {
            retryAttempts[request.correlationId] = attempts + 1
            // Phase 2C proven exponential backoff
            let delay = min(UInt64(pow(2.0, Double(attempts))) * 2_000_000, 100_000_000) // Max 100ms
            try? await Task.sleep(nanoseconds: delay)
        } else {
            // Final attempt - force to fallback
            let success = await sendToProcessorProven(request: request, processor: .fallback)
            if success {
                await recordProcessedPayment(request: request, processor: .fallback)
            }
            pendingPayments.removeAll { $0.correlationId == request.correlationId }
            retryAttempts.removeValue(forKey: request.correlationId)
        }
    }
    
    // PHASE 2C: Proven processor communication
    private func sendToProcessorProven(request: PaymentProcessorRequest, processor: ProcessorType) async -> Bool {
        do {
            let url = processor == .default ? defaultProcessorURL : fallbackProcessorURL
            let uri = URI(string: "\(url)/payments")
            
            let response = try await app.client.post(uri) { req in
                try req.content.encode(request)
                req.headers.add(name: .contentType, value: "application/json")
            }
            
            return response.status == .ok
        } catch {
            // Phase 2C proven failure detection
            await markProcessorUnhealthy(processor)
            return false
        }
    }
    
    // PHASE 2D: Optimized processor order based on health
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
    
    // PHASE 2D: Fast health checking
    private func isProcessorHealthy(_ processor: ProcessorType) async -> Bool {
        let now = Date()
        
        if let lastCheck = lastHealthCheck[processor],
           now.timeIntervalSince(lastCheck.date) < healthCheckInterval {
            return !lastCheck.health.failing
        }
        
        // Quick health check
        let health = await checkProcessorHealthFast(processor)
        lastHealthCheck[processor] = (date: now, health: health)
        return !health.failing
    }
    
    // PHASE 2D: Ultra-fast health check
    private func checkProcessorHealthFast(_ processor: ProcessorType) async -> HealthCheckResponse {
        do {
            let url = processor == .default ? defaultProcessorURL : fallbackProcessorURL
            let uri = URI(string: "\(url)/health")
            
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

    // PHASE 2D: Enhanced payment recording with consistency tracking
    private func recordProcessedPayment(request: PaymentProcessorRequest, processor: ProcessorType) async {
        let record = PaymentRecord(
            correlationId: request.correlationId,
            amount: request.amount,
            requestedAt: request.requestedAt,
            processor: processor,
            processedAt: Date()
        )
        processedPayments.append(record)
        
        // Update the accepted payment record with actual processor used
        if let index = acceptedPayments.firstIndex(where: { $0.correlationId == request.correlationId }) {
            acceptedPayments[index].processor = processor
            acceptedPayments[index].processedAt = Date()
        }
        
        // Clean up retry tracking
        retryAttempts.removeValue(forKey: request.correlationId)
    }

    // PHASE 2C: Summary with TRUE consistency - report only SENT payments
    func getPaymentsSummary(from: Date?, to: Date?) async -> PaymentSummaryResponse {
        // CRITICAL FIX: Use PROCESSED payments (actually sent to processors)
        // This matches exactly what payment processors received
        // Accepter ≠ Enviado - só reportamos o que realmente enviamos
        
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

    // PHASE 2C: Final queue flush for zero inconsistency
    func flushQueueCompletely() async {
        var attempts = 0
        let maxFlushAttempts = 100
        
        while !pendingPayments.isEmpty && attempts < maxFlushAttempts {
            await processQueueProven()
            try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
            attempts += 1
        }
    }

    // PHASE 2D: Get processed payments for summary
    func getProcessedPayments() async -> [PaymentRecord] {
        return processedPayments
    }

    // MARK: - Queue Statistics (for testing and debugging)
    
    func getQueueStats() async -> QueueStats {
        return QueueStats(
            pending: pendingPayments.count,
            processing: isProcessingQueue ? 1 : 0,
            accepted: acceptedPayments.count,
            processed: processedPayments.count
        )
    }
    
    // Get queue status for health monitoring
    func getQueueStatus() async -> String {
        let stats = await getQueueStats()
        return "Pending: \(stats.pending), Processed: \(stats.processed), Processing: \(stats.processing > 0 ? "YES" : "NO")"
    }
    
    // PHASE 2C: Force queue flush for final consistency (emergency use)
    func forceCompleteQueueProcessing() async {
        var attempts = 0
        while !pendingPayments.isEmpty && attempts < 100 { // Max 10 seconds
            await processQueueProven()
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            attempts += 1
        }
    }
} 