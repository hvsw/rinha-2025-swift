import Vapor
import Foundation

// MARK: - Request Models
struct PaymentRequest: Content {
    let correlationId: UUID
    let amount: Double
}

struct PaymentProcessorRequest: Content {
    let correlationId: UUID
    let amount: Double
    let requestedAt: Date
}

// MARK: - Response Models
struct PaymentProcessorResponse: Content {
    let message: String
}

struct PaymentSummaryResponse: Content {
    let `default`: ProcessorSummary
    let fallback: ProcessorSummary
}

struct ProcessorSummary: Content {
    let totalRequests: Int
    let totalAmount: Double
}

struct HealthCheckResponse: Content {
    let failing: Bool
    let minResponseTime: Int
}

// MARK: - Internal Models
struct PaymentRecord {
    let correlationId: UUID
    let amount: Double
    let requestedAt: Date
    var processor: ProcessorType
    var processedAt: Date?
}

enum ProcessorType: String, CaseIterable {
    case `default` = "default"
    case fallback = "fallback"
}

// MARK: - Queue Statistics
struct QueueStats: Equatable {
    let pending: Int       // Payments in queue waiting to be processed
    let processing: Int    // Currently being processed (0 or 1)
    let accepted: Int      // Total payments accepted (HTTP 202)
    let processed: Int     // Total payments processed by processors
} 