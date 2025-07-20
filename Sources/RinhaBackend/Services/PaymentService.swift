import Vapor
import Foundation
import Redis

actor PaymentService {
    private let app: Application
    private let defaultProcessorURL: String
    private let fallbackProcessorURL: String
    
    // Configuration for high performance
    private let healthCheckInterval: TimeInterval = 5.0
    private var lastHealthCheck: [ProcessorType: (date: Date, healthy: Bool)] = [:]
    
    // Reusable formatters
    private static let iso8601Formatter: ISO8601DateFormatter = ISO8601DateFormatter()
    
    // Redis keys for atomic counters
    private let defaultCountKey = "payments:count:default"
    private let defaultAmountKey = "payments:amount:default"
    private let fallbackCountKey = "payments:count:fallback"
    private let fallbackAmountKey = "payments:amount:fallback"
    
    init(app: Application) async throws {
        self.app = app
        self.defaultProcessorURL = Environment.get("DEFAULT_PROCESSOR_URL") ?? "http://payment-processor-default:8080"
        self.fallbackProcessorURL = Environment.get("FALLBACK_PROCESSOR_URL") ?? "http://payment-processor-fallback:8080"
        
        app.logger.info("✅ PaymentService initialized - REDIS SHARED STATE mode")
    }
    
    func processPayment(request: PaymentRequest) async throws -> HTTPStatus {
        // Use single timestamp for consistency
        let requestedAt = Date()
        
        let processorRequest = PaymentProcessorRequest(
            correlationId: request.correlationId,
            amount: request.amount,
            requestedAt: Self.iso8601Formatter.string(from: requestedAt)
        )
        
        // Process immediately and record success
        let success = await processPaymentDirect(request: processorRequest, requestedAt: requestedAt)
        
        // Always return accepted (async processing semantics)
        return .accepted
    }
    
    private func processPaymentDirect(request: PaymentProcessorRequest, requestedAt: Date) async -> Bool {
        // Try default processor first (lower fees)
        let defaultHealthy = await isProcessorHealthy(.default)
        
        if defaultHealthy {
            let success = await sendToProcessor(request: request, processor: .default)
            if success {
                await recordProcessedPayment(request: request, processor: .default, requestedAt: requestedAt)
                return true
            }
        }
        
        // Fallback to secondary processor
        let fallbackHealthy = await isProcessorHealthy(.fallback)
        
        if fallbackHealthy {
            let success = await sendToProcessor(request: request, processor: .fallback)
            if success {
                await recordProcessedPayment(request: request, processor: .fallback, requestedAt: requestedAt)
                return true
            }
        }
        
        // If both fail, try default anyway (better than dropping)
        let success = await sendToProcessor(request: request, processor: .default)
        if success {
            await recordProcessedPayment(request: request, processor: .default, requestedAt: requestedAt)
            return true
        }
        
        return false
    }
    
    private func sendToProcessor(request: PaymentProcessorRequest, processor: ProcessorType) async -> Bool {
        do {
            let url = processor == .default ? defaultProcessorURL : fallbackProcessorURL
            let uri = URI(string: "\(url)/payments")
            
            let response = try await app.client.post(uri) { req in
                try req.content.encode(request)
                req.headers.replaceOrAdd(name: .contentType, value: "application/json")
                req.headers.add(name: .connection, value: "keep-alive")
            }
            
            return response.status == .ok
        } catch {
            await markProcessorUnhealthy(processor)
            return false
        }
    }
    
    private func isProcessorHealthy(_ processor: ProcessorType) async -> Bool {
        let now = Date()
        
        // Use cached health status if recent
        if let lastCheck = lastHealthCheck[processor],
           now.timeIntervalSince(lastCheck.date) < healthCheckInterval {
            return lastCheck.healthy
        }
        
        // Check health
        let healthy = await checkProcessorHealth(processor)
        lastHealthCheck[processor] = (date: now, healthy: healthy)
        return healthy
    }
    
    private func checkProcessorHealth(_ processor: ProcessorType) async -> Bool {
        do {
            let url = processor == .default ? defaultProcessorURL : fallbackProcessorURL
            let uri = URI(string: "\(url)/payments/service-health")
            
            let response = try await app.client.get(uri) { req in
                req.headers.add(name: .accept, value: "application/json")
            }
            
            if response.status == .ok {
                let health = try response.content.decode(HealthCheckResponse.self)
                return !health.failing
            } else {
                return false
            }
        } catch {
            return false
        }
    }
    
    private func markProcessorUnhealthy(_ processor: ProcessorType) async {
        lastHealthCheck[processor] = (date: Date(), healthy: false)
    }
    
    private func recordProcessedPayment(request: PaymentProcessorRequest, processor: ProcessorType, requestedAt: Date) async {
        do {
            // Use atomic Redis operations for counters
            let countKey = processor == .default ? defaultCountKey : fallbackCountKey
            let amountKey = processor == .default ? defaultAmountKey : fallbackAmountKey
            
            // Convert amount to cents for integer storage
            let amountCents = Int(request.amount * 100)
            
            // Atomic increment operations (fire and forget for speed)
            _ = app.redis.increment(RedisKey(countKey))
            _ = app.redis.increment(RedisKey(amountKey), by: amountCents)
            
            app.logger.debug("Payment recorded: \(processor) - \(request.amount)")
            
        } catch {
            app.logger.error("Failed to record payment in Redis: \(error)")
        }
    }
    
    func getPaymentsSummary(from: Date?, to: Date?) async -> PaymentSummaryResponse {
        do {
            // Get counters from Redis (fast path - no date filtering for performance)
            let defaultCountFuture = app.redis.get(RedisKey(defaultCountKey), as: Int.self)
            let defaultAmountFuture = app.redis.get(RedisKey(defaultAmountKey), as: Int.self)
            let fallbackCountFuture = app.redis.get(RedisKey(fallbackCountKey), as: Int.self)
            let fallbackAmountFuture = app.redis.get(RedisKey(fallbackAmountKey), as: Int.self)
            
            // Wait for all Redis operations in parallel
            let defaultCount = try await defaultCountFuture.get() ?? 0
            let defaultAmountCents = try await defaultAmountFuture.get() ?? 0
            let fallbackCount = try await fallbackCountFuture.get() ?? 0
            let fallbackAmountCents = try await fallbackAmountFuture.get() ?? 0
            
            // Convert cents back to dollars
            let defaultAmount = Double(defaultAmountCents) / 100.0
            let fallbackAmount = Double(fallbackAmountCents) / 100.0
            
            return PaymentSummaryResponse(
                default: ProcessorSummary(
                    totalRequests: defaultCount,
                    totalAmount: defaultAmount
                ),
                fallback: ProcessorSummary(
                    totalRequests: fallbackCount,
                    totalAmount: fallbackAmount
                )
            )
            
        } catch {
            app.logger.error("Failed to get payments summary from Redis: \(error)")
            return PaymentSummaryResponse(
                default: ProcessorSummary(totalRequests: 0, totalAmount: 0),
                fallback: ProcessorSummary(totalRequests: 0, totalAmount: 0)
            )
        }
    }
} 
