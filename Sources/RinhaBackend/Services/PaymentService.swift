import Vapor
import Foundation
import NIOCore

actor PaymentService {
    private let app: Application
    private let defaultProcessorURL: String
    private let fallbackProcessorURL: String
    
    // PHASE 2: Separate tracking for accepted vs processed payments
    private var acceptedPayments: [PaymentRecord] = []  // All payments we accepted (HTTP 202)
    private var processedPayments: [PaymentRecord] = []  // Only payments successfully sent to processors
    private var lastHealthCheck: [ProcessorType: (date: Date, health: HealthCheckResponse)] = [:]
    private let healthCheckInterval: TimeInterval = 5.0 // 5 seconds limit
    
    // PHASE 2: Enhanced queue management with optimized performance
    private var pendingPayments: [PaymentProcessorRequest] = []
    private var processingPayments: Set<UUID> = []
    private var isProcessingQueue: Bool = false
    
    init(app: Application) {
        self.app = app
        self.defaultProcessorURL = Environment.get("PAYMENT_PROCESSOR_URL_DEFAULT") ?? "http://payment-processor-default:8080"
        self.fallbackProcessorURL = Environment.get("PAYMENT_PROCESSOR_URL_FALLBACK") ?? "http://payment-processor-fallback:8080"
        
        // Start background queue processor with optimized performance
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
        
        // PHASE 2: Track as accepted immediately when we return HTTP 202
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
        
        // Start processing if not already running
        if !isProcessingQueue {
            Task {
                await processQueue()
            }
        }
    }
    
    // PHASE 2: Optimized queue processor - restored performance focus
    private func startQueueProcessor() async {
        while true {
            if !pendingPayments.isEmpty && !isProcessingQueue {
                await processQueue()
            }
            
            // PHASE 2: Optimized delay for maximum throughput
            try? await Task.sleep(nanoseconds: 2_000_000) // 2ms - fast but not cpu-intensive
        }
    }
    
    // PHASE 2: Optimized queue processing with consistent batch sizes
    private func processQueue() async {
        guard !isProcessingQueue else { return }
        isProcessingQueue = true
        
        defer { isProcessingQueue = false }
        
        // PHASE 2: Consistent batch size optimized for throughput
        let maxBatchSize = 20  // Optimal batch size for performance
        let batchSize = min(pendingPayments.count, maxBatchSize)
        
        guard batchSize > 0 else { return }
        
        let batch = Array(pendingPayments.prefix(batchSize))
        pendingPayments.removeFirst(batchSize)
        
        // Process batch concurrently with high concurrency
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
            await recordProcessedPayment(request: request, processor: .default)
            return
        }
        
        // Fallback to fallback processor
        if await tryProcessWithProcessor(.fallback, request: request) != nil {
            await recordProcessedPayment(request: request, processor: .fallback)
            return
        }
        
        // If both fail, re-queue with quick retry
        await requeueWithBackoff(request)
    }
    
    private func requeueWithBackoff(_ request: PaymentProcessorRequest) async {
        // PHASE 2: Quick retry for better throughput
        try? await Task.sleep(nanoseconds: 25_000_000) // 25ms delay
        pendingPayments.append(request)
    }
    
    // PHASE 2: Optimized HTTP client with balanced timeout
    private func tryProcessWithProcessor(_ processor: ProcessorType, request: PaymentProcessorRequest) async -> PaymentProcessorResponse? {
        let url = processor == .default ? defaultProcessorURL : fallbackProcessorURL
        
        do {
            let uri = URI(string: "\(url)/payments")
            let response = try await app.client.post(uri) { req in
                try req.content.encode(request)
                // PHASE 2: Balanced timeout for reliability and performance
                req.timeout = .seconds(4)  // Balanced between 3s and 5s
            }
            
            if response.status.code >= 200 && response.status.code < 300 {
                return try response.content.decode(PaymentProcessorResponse.self)
            }
        } catch {
            app.logger.error("Failed to process payment with \(processor.rawValue): \(error)")
        }
        
        return nil
    }
    
    // PHASE 2: Separate method for recording actually processed payments
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
    }
    
    // PHASE 2: Lightweight summary without aggressive queue flushing
    func getPaymentsSummary(from: Date?, to: Date?) async -> PaymentSummaryResponse {
        // PHASE 2: Use PROCESSED payments only for consistency (no blocking flush)
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
} 