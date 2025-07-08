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
    
    init(app: Application) {
        self.app = app
        self.defaultProcessorURL = Environment.get("PAYMENT_PROCESSOR_URL_DEFAULT") ?? "http://payment-processor-default:8080"
        self.fallbackProcessorURL = Environment.get("PAYMENT_PROCESSOR_URL_FALLBACK") ?? "http://payment-processor-fallback:8080"
    }
    
    func processPayment(request: PaymentRequest) async throws -> HTTPStatus {
        let processorRequest = PaymentProcessorRequest(
            correlationId: request.correlationId,
            amount: request.amount,
            requestedAt: Date()
        )
        
        // Try default processor first
        if await tryProcessWithProcessor(.default, request: processorRequest) != nil {
            await recordPayment(request: processorRequest, processor: .default)
            return .ok
        }
        
        // Fallback to fallback processor
        if await tryProcessWithProcessor(.fallback, request: processorRequest) != nil {
            await recordPayment(request: processorRequest, processor: .fallback)
            return .ok
        }
        
        // If both fail, return accepted (we'll process asynchronously)
        return .accepted
    }
    
    private func tryProcessWithProcessor(_ processor: ProcessorType, request: PaymentProcessorRequest) async -> PaymentProcessorResponse? {
        let url = processor == .default ? defaultProcessorURL : fallbackProcessorURL
        
        do {
            let uri = URI(string: "\(url)/payments")
            let response = try await app.client.post(uri) { req in
                try req.content.encode(request)
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
} 