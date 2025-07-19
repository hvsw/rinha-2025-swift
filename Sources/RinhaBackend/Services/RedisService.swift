import Vapor
import Foundation

actor SharedStateService {
    private let app: Application
    private let stateFilePath: String
    
    // In-memory state for performance
    private var acceptedPayments: [PaymentRecord] = []
    private var processedPayments: [PaymentRecord] = []
    private var pendingPayments: [PaymentProcessorRequest] = []
    private var retryAttempts: [UUID: Int] = [:]
    private var healthChecks: [ProcessorType: ProcessorHealthCheck] = [:]
    
    // State sync timing
    private var lastStateLoad: Date = Date()
    private var lastStateSave: Date = Date()
    private let syncInterval: TimeInterval = 0.1 // 100ms
    
    init(app: Application) async throws {
        self.app = app
        self.stateFilePath = "/tmp/rinha_shared_state.json"
        
        // Load existing state
        await loadSharedState()
        app.logger.info("✅ Shared state service initialized with file: \(stateFilePath)")
        
        // Start periodic sync task
        Task {
            await periodicStateSync()
        }
    }
    
    private func periodicStateSync() async {
        while true {
            try? await Task.sleep(nanoseconds: UInt64(syncInterval * 1_000_000_000))
            await syncState()
        }
    }
    
    private func syncState() async {
        let now = Date()
        
        // Load updates from other instances
        if now.timeIntervalSince(lastStateLoad) > syncInterval {
            await loadSharedState()
            lastStateLoad = now
        }
        
        // Save our updates
        if now.timeIntervalSince(lastStateSave) > syncInterval {
            await saveSharedState()
            lastStateSave = now
        }
    }
    
    // MARK: - Payment Operations
    
    func addAcceptedPayment(_ payment: PaymentRecord) async throws {
        acceptedPayments.append(payment)
        await saveSharedState()
    }
    
    func addProcessedPayment(_ payment: PaymentRecord) async throws {
        processedPayments.append(payment)
        await saveSharedState()
    }
    
    func getProcessedPayments() async throws -> [PaymentRecord] {
        await loadSharedState()
        return processedPayments
    }
    
    // MARK: - Queue Operations
    
    func enqueuePendingPayment(_ request: PaymentProcessorRequest) async throws {
        pendingPayments.append(request)
        await saveSharedState()
    }
    
    func dequeuePendingPayments(count: Int) async throws -> [PaymentProcessorRequest] {
        await loadSharedState()
        
        let result = Array(pendingPayments.prefix(count))
        pendingPayments.removeFirst(min(count, pendingPayments.count))
        
        if !result.isEmpty {
            await saveSharedState()
        }
        
        return result
    }
    
    func getPendingQueueSize() async throws -> Int {
        await loadSharedState()
        return pendingPayments.count
    }
    
    // MARK: - Retry Attempts
    
    func setRetryAttempts(for correlationId: UUID, attempts: Int) async throws {
        retryAttempts[correlationId] = attempts
        await saveSharedState()
    }
    
    func getRetryAttempts(for correlationId: UUID) async throws -> Int {
        await loadSharedState()
        return retryAttempts[correlationId] ?? 0
    }
    
    func removeRetryAttempts(for correlationId: UUID) async throws {
        retryAttempts.removeValue(forKey: correlationId)
        await saveSharedState()
    }
    
    // MARK: - Health Checks
    
    func setProcessorHealth(_ processor: ProcessorType, health: HealthCheckResponse) async throws {
        healthChecks[processor] = ProcessorHealthCheck(date: Date(), health: health)
        await saveSharedState()
    }
    
    func getProcessorHealth(_ processor: ProcessorType) async throws -> ProcessorHealthCheck? {
        await loadSharedState()
        return healthChecks[processor]
    }
    
    // MARK: - Statistics
    
    func getQueueStats() async throws -> QueueStats {
        await loadSharedState()
        
        return QueueStats(
            pending: pendingPayments.count,
            processing: 0, // This would require additional coordination
            accepted: acceptedPayments.count,
            processed: processedPayments.count
        )
    }
    
    // MARK: - State Persistence
    
    private func loadSharedState() async {
        do {
            guard FileManager.default.fileExists(atPath: stateFilePath) else { return }
            
            let data = try Data(contentsOf: URL(fileURLWithPath: stateFilePath))
            let sharedState = try JSONDecoder().decode(SharedState.self, from: data)
            
            // Convert and merge state from file with local state
            let remoteAccepted = sharedState.acceptedPayments.map { $0.toPaymentRecord() }
            let remoteProcessed = sharedState.processedPayments.map { $0.toPaymentRecord() }
            
            self.acceptedPayments = mergePayments(local: acceptedPayments, remote: remoteAccepted)
            self.processedPayments = mergePayments(local: processedPayments, remote: remoteProcessed)
            self.pendingPayments = mergePendingPayments(local: pendingPayments, remote: sharedState.pendingPayments)
            
            // Convert retry attempts from String keys to UUID keys
            self.retryAttempts = sharedState.retryAttempts.reduce(into: [:]) { result, pair in
                if let uuid = UUID(uuidString: pair.key) {
                    result[uuid] = pair.value
                }
            }
            
            // Convert health checks from String keys to ProcessorType keys
            self.healthChecks = sharedState.healthChecks.reduce(into: [:]) { result, pair in
                if let processor = ProcessorType(rawValue: pair.key) {
                    result[processor] = pair.value
                }
            }
        } catch {
            // Ignore load errors - file might be corrupted or not exist yet
        }
    }
    
    private func saveSharedState() async {
        do {
            let sharedState = SharedState(
                acceptedPayments: acceptedPayments,
                processedPayments: processedPayments,
                pendingPayments: pendingPayments,
                retryAttempts: retryAttempts,
                healthChecks: healthChecks
            )
            
            let data = try JSONEncoder().encode(sharedState)
            try data.write(to: URL(fileURLWithPath: stateFilePath))
        } catch {
            app.logger.error("Failed to save shared state: \(error)")
        }
    }
    
    private func mergePayments(local: [PaymentRecord], remote: [PaymentRecord]) -> [PaymentRecord] {
        var merged = local
        let localIds = Set(local.map { $0.correlationId })
        
        for payment in remote {
            if !localIds.contains(payment.correlationId) {
                merged.append(payment)
            }
        }
        
        return merged
    }
    
    private func mergePendingPayments(local: [PaymentProcessorRequest], remote: [PaymentProcessorRequest]) -> [PaymentProcessorRequest] {
        var merged = local
        let localIds = Set(local.map { $0.correlationId })
        
        for payment in remote {
            if !localIds.contains(payment.correlationId) {
                merged.append(payment)
            }
        }
        
        return merged
    }
}

// MARK: - Shared State Model

private struct SharedState: Codable {
    let acceptedPayments: [PaymentJSON]
    let processedPayments: [PaymentJSON]
    let pendingPayments: [PaymentProcessorRequest]
    let retryAttempts: [String: Int]
    let healthChecks: [String: ProcessorHealthCheck]
    
    init(acceptedPayments: [PaymentRecord],
         processedPayments: [PaymentRecord],
         pendingPayments: [PaymentProcessorRequest],
         retryAttempts: [UUID: Int],
         healthChecks: [ProcessorType: ProcessorHealthCheck]) {
        
        self.acceptedPayments = acceptedPayments.map { $0.toJSON() }
        self.processedPayments = processedPayments.map { $0.toJSON() }
        self.pendingPayments = pendingPayments
        self.retryAttempts = retryAttempts.reduce(into: [:]) { result, pair in
            result[pair.key.uuidString] = pair.value
        }
        self.healthChecks = healthChecks.reduce(into: [:]) { result, pair in
            result[pair.key.rawValue] = pair.value
        }
    }
}

// MARK: - Helper Models

struct PaymentJSON: Codable {
    let correlationId: String
    let amount: Double
    let requestedAt: String
    let processor: String
    let processedAt: String?
    
    func toPaymentRecord() -> PaymentRecord {
        let iso8601Formatter = ISO8601DateFormatter()
        
        return PaymentRecord(
            correlationId: UUID(uuidString: correlationId) ?? UUID(),
            amount: amount,
            requestedAt: iso8601Formatter.date(from: requestedAt) ?? Date(),
            processor: ProcessorType(rawValue: processor) ?? .default,
            processedAt: processedAt.flatMap { iso8601Formatter.date(from: $0) }
        )
    }
}

struct ProcessorHealthCheck: Codable {
    let date: Date
    let health: HealthCheckResponse
}

extension PaymentRecord {
    func toJSON() -> PaymentJSON {
        let iso8601Formatter = ISO8601DateFormatter()
        
        return PaymentJSON(
            correlationId: correlationId.uuidString,
            amount: amount,
            requestedAt: iso8601Formatter.string(from: requestedAt),
            processor: processor.rawValue,
            processedAt: processedAt.map { iso8601Formatter.string(from: $0) }
        )
    }
}

// MARK: - Type alias for compatibility

typealias RedisService = SharedStateService 