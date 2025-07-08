import Vapor
import Foundation
import NIOCore

actor PaymentService {
    private let app: Application
    private let defaultProcessorURL: String
    private let fallbackProcessorURL: String
    
    // In-memory storage for processed payments
    private var processedPayments: [PaymentRecord] = []
    private var lastHealthCheck: [ProcessorType: (date: Date, health: HealthCheckResponse)] = [:]
    private let healthCheckInterval: TimeInterval = 5.0 // 5 seconds limit
    
    // Async processing queue and state tracking
    private var pendingPayments: [PaymentProcessorRequest] = []
    private var processingPayments: Set<UUID> = []
    private var isProcessingQueue: Bool = false
    
    init(app: Application) {
        self.app = app
        self.defaultProcessorURL = Environment.get("PAYMENT_PROCESSOR_URL_DEFAULT") ?? "http://payment-processor-default:8080"
        self.fallbackProcessorURL = Environment.get("PAYMENT_PROCESSOR_URL_FALLBACK") ?? "http://payment-processor-fallback:8080"
        
        // Start background queue processor
        Task {
            await startQueueProcessor()
        }
    }
    
    func processPayment(request: PaymentRequest) async throws -> HTTPStatus {
        let processorRequest = PaymentProcessorRequest(
            correlationId: request.correlationId,
            amount: request.amount,
            requestedAt: Date()
        )
        
        // Add to queue and return immediately
        await enqueuePayment(processorRequest)
        
        // Return 202 Accepted for async processing
        return .accepted
    }
    
    private func enqueuePayment(_ request: PaymentProcessorRequest) async {
        pendingPayments.append(request)
        
        // Start processing if not already running
        if !isProcessingQueue {
            Task {
                await processQueue()
            }
        }
    }
    
    private func startQueueProcessor() async {
        // Background task that continuously processes the queue
        while true {
            if !pendingPayments.isEmpty && !isProcessingQueue {
                await processQueue()
            }
            
            // Small delay to prevent busy loop
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
    }
    
    private func processQueue() async {
        guard !isProcessingQueue else { return }
        isProcessingQueue = true
        
        defer { isProcessingQueue = false }
        
        let maxBatchSize = 10 // Process up to 10 payments at once
        let batchSize = min(pendingPayments.count, maxBatchSize)
        
        guard batchSize > 0 else { return }
        
        let batch = Array(pendingPayments.prefix(batchSize))
        pendingPayments.removeFirst(batchSize)
        
        // Process batch concurrently
        await withTaskGroup(of: Void.self) { group in
            for payment in batch {
                group.addTask {
                    await self.processPaymentAsync(payment)
                }
            }
        }
    }
    
    private func processPaymentAsync(_ request: PaymentProcessorRequest) async {
        // Prevent duplicate processing
        guard !processingPayments.contains(request.correlationId) else { return }
        processingPayments.insert(request.correlationId)
        
        defer { processingPayments.remove(request.correlationId) }
        
        // Try default processor first
        if await tryProcessWithProcessor(.default, request: request) != nil {
            await recordPayment(request: request, processor: .default)
            return
        }
        
        // Fallback to fallback processor
        if await tryProcessWithProcessor(.fallback, request: request) != nil {
            await recordPayment(request: request, processor: .fallback)
            return
        }
        
        // If both fail, re-queue with exponential backoff
        await requeueWithBackoff(request)
    }
    
    private func requeueWithBackoff(_ request: PaymentProcessorRequest) async {
        // Simple exponential backoff: wait and re-add to queue
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms delay
        pendingPayments.append(request)
    }
    
    private func tryProcessWithProcessor(_ processor: ProcessorType, request: PaymentProcessorRequest) async -> PaymentProcessorResponse? {
        let url = processor == .default ? defaultProcessorURL : fallbackProcessorURL
        
        do {
            let uri = URI(string: "\(url)/payments")
            let response = try await app.client.post(uri) { req in
                try req.content.encode(request)
                // Set shorter timeout for async processing
                req.timeout = .seconds(5)
            }
            
            if response.status.code >= 200 && response.status.code < 300 {
                return try response.content.decode(PaymentProcessorResponse.self)
            }
        } catch {
            app.logger.error("Failed to process payment with \(processor.rawValue): \(error)")
        }
        
        return nil
    }
    
    private func recordPayment(request: PaymentProcessorRequest, processor: ProcessorType) async {
        let record = PaymentRecord(
            correlationId: request.correlationId,
            amount: request.amount,
            requestedAt: request.requestedAt,
            processor: processor,
            processedAt: Date()
        )
        processedPayments.append(record)
    }
    
    func getPaymentsSummary(from: Date?, to: Date?) async -> PaymentSummaryResponse {
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
    
    private func checkProcessorHealth(_ processor: ProcessorType) async -> HealthCheckResponse? {
        let now = Date()
        
        // Check if we have a recent health check
        if let lastCheck = lastHealthCheck[processor],
           now.timeIntervalSince(lastCheck.date) < healthCheckInterval {
            return lastCheck.health
        }
        
        let url = processor == .default ? defaultProcessorURL : fallbackProcessorURL
        
        do {
            let uri = URI(string: "\(url)/payments/service-health")
            let response = try await app.client.get(uri)
            
            if response.status == .ok {
                let health = try response.content.decode(HealthCheckResponse.self)
                lastHealthCheck[processor] = (date: now, health: health)
                return health
            }
        } catch {
            app.logger.error("Failed to check health for \(processor.rawValue): \(error)")
        }
        
        return nil
    }
    
    // Debug methods for monitoring queue state
    func getQueueStats() async -> (pending: Int, processing: Int, processed: Int) {
        return (
            pending: pendingPayments.count,
            processing: processingPayments.count,
            processed: processedPayments.count
        )
    }
} 