import Vapor
import Foundation
import NIOCore

actor PaymentService {
    private let app: Application
    private let defaultProcessorURL: String
    private let fallbackProcessorURL: String
    
    // PHASE 2B: Enhanced tracking for zero inconsistency
    private var acceptedPayments: [PaymentRecord] = []  // All payments we accepted (HTTP 202)
    private var processedPayments: [PaymentRecord] = []  // Only payments successfully sent to processors
    private var lastHealthCheck: [ProcessorType: (date: Date, health: HealthCheckResponse)] = [:]
    private let healthCheckInterval: TimeInterval = 10.0  // PHASE 2B: More frequent health checks
    
    // PHASE 2B: Optimized queue management for zero inconsistency
    private var pendingPayments: [PaymentProcessorRequest] = []
    private var processingPayments: Set<UUID> = []
    private var isProcessingQueue: Bool = false
    private var retryAttempts: [UUID: Int] = [:]  // Track retry counts per payment
    private let maxRetryAttempts = 10  // PHASE 2B: More aggressive retries
    
    init(app: Application) {
        self.app = app
        
        // Read from environment variables
        self.defaultProcessorURL = Environment.get("DEFAULT_PROCESSOR_URL") ?? "http://payment-processor-default:8080"
        self.fallbackProcessorURL = Environment.get("FALLBACK_PROCESSOR_URL") ?? "http://payment-processor-fallback:8080"
        
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
        
        // Start processing if not already running
        if !isProcessingQueue {
            Task {
                await processQueue()
            }
        }
    }
    
    // PHASE 2B: Ultra-aggressive queue processor for zero inconsistency
    private func startQueueProcessor() async {
        while true {
            if !pendingPayments.isEmpty && !isProcessingQueue {
                await processQueue()
            }
            
            // PHASE 2B: Very fast processing to eliminate queue buildup
            try? await Task.sleep(nanoseconds: 1_000_000) // 1ms - maximum speed
        }
    }
    
    // PHASE 2B: High-performance queue processing with intelligent routing
    private func processQueue() async {
        guard !isProcessingQueue else { return }
        isProcessingQueue = true
        
        defer { isProcessingQueue = false }
        
        // PHASE 2B: Larger batch size for higher throughput
        let maxBatchSize = 30  // Increased from 20
        let batchSize = min(pendingPayments.count, maxBatchSize)
        
        guard batchSize > 0 else { return }
        
        let batch = Array(pendingPayments.prefix(batchSize))
        pendingPayments.removeFirst(batchSize)
        
        // Process batch with very high concurrency
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
        
        // PHASE 2B: Health-based intelligent routing
        let preferredProcessor = await determinePreferredProcessor()
        
        // Try preferred processor first
        if await tryProcessWithProcessor(preferredProcessor, request: request) != nil {
            await recordProcessedPayment(request: request, processor: preferredProcessor)
            return
        }
        
        // Try other processor as fallback
        let fallbackProcessor: ProcessorType = preferredProcessor == .default ? .fallback : .default
        if await tryProcessWithProcessor(fallbackProcessor, request: request) != nil {
            await recordProcessedPayment(request: request, processor: fallbackProcessor)
            return
        }
        
        // PHASE 2B: Enhanced retry logic
        await handleFailedPayment(request)
    }
    
    // PHASE 2B: Intelligent processor selection based on health
    private func determinePreferredProcessor() async -> ProcessorType {
        let defaultHealth = await checkProcessorHealth(.default)
        let fallbackHealth = await checkProcessorHealth(.fallback)
        
        // Prefer default if both are healthy (for cost optimization)
        if defaultHealth != nil && fallbackHealth != nil {
            return .default
        }
        
        // Use whichever is healthy
        if defaultHealth != nil {
            return .default
        }
        
        if fallbackHealth != nil {
            return .fallback
        }
        
        // Both unhealthy - still prefer default for consistency
        return .default
    }
    
    // PHASE 2B: Enhanced retry logic with exponential backoff
    private func handleFailedPayment(_ request: PaymentProcessorRequest) async {
        let currentAttempts = retryAttempts[request.correlationId] ?? 0
        
        if currentAttempts < maxRetryAttempts {
            retryAttempts[request.correlationId] = currentAttempts + 1
            
            // PHASE 2B: Faster exponential backoff for quicker processing
            let backoffMs = min(10 * (1 << currentAttempts), 500)  // Max 500ms
            try? await Task.sleep(nanoseconds: UInt64(backoffMs) * 1_000_000)
            
            // Re-queue for retry
            pendingPayments.append(request)
        } else {
            // PHASE 2B: Even max retries exhausted, log and continue
            app.logger.error("Payment \(request.correlationId) exhausted all retries")
            // Note: We don't give up completely to maintain consistency tracking
        }
    }
    
    // PHASE 2B: Optimized HTTP client with aggressive timeouts
    private func tryProcessWithProcessor(_ processor: ProcessorType, request: PaymentProcessorRequest) async -> PaymentProcessorResponse? {
        let url = processor == .default ? defaultProcessorURL : fallbackProcessorURL
        
        do {
            let uri = URI(string: "\(url)/payments")
            let response = try await app.client.post(uri) { req in
                try req.content.encode(request)
                // PHASE 2B: Faster timeout for quicker failure detection and retry
                req.timeout = .seconds(2)  // Reduced from 4s to 2s
            }
            
            if response.status.code >= 200 && response.status.code < 300 {
                return try response.content.decode(PaymentProcessorResponse.self)
            }
        } catch {
            app.logger.error("Failed to process payment with \(processor.rawValue): \(error)")
        }
        
        return nil
    }
    
    // PHASE 2B: Enhanced payment recording with consistency tracking
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
    
    // PHASE 2B: Quick queue flush to reduce inconsistency
    private func attemptQuickQueueFlush() async {
        // Only attempt if queue is small to avoid blocking
        if pendingPayments.count <= 10 && !isProcessingQueue {
            await processQueue()
            // Give a tiny bit of time for processing
            try? await Task.sleep(nanoseconds: 5_000_000) // 5ms
        }
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
            let response = try await app.client.get(uri) { req in
                // PHASE 2B: Fast health check timeout
                req.timeout = .seconds(1)
            }
            
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
    
    // PHASE 2B: Force queue flush for final consistency (emergency use)
    func forceCompleteQueueProcessing() async {
        var attempts = 0
        while !pendingPayments.isEmpty && attempts < 100 { // Max 10 seconds
            await processQueue()
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            attempts += 1
        }
    }
} 