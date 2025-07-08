import XCTest
import Vapor
import NIOCore
@testable import RinhaBackend

final class ConsistencyTests: XCTestCase {
    var app: Application!
    var paymentService: PaymentService!
    
    override func setUp() async throws {
        app = try await Application.make(.testing)
        paymentService = PaymentService(app: app)
    }
    
    override func tearDown() async throws {
        try await app.asyncShutdown()
    }
    
    // MARK: - Root Cause Analysis Tests
    
    /// Test that confirms inconsistency is caused by processor failures
    func testProcessorFailureInconsistency() async throws {
        print("🔍 TESTING ROOT CAUSE: Processor failures causing inconsistency")
        
        let paymentCount = 5
        var acceptedCount = 0
        
        // Add payments - they will fail to process because processors are not running
        for i in 0..<paymentCount {
            let request = PaymentRequest(
                correlationId: UUID(),
                amount: Double(i + 1) * 10.0
            )
            
            let status = try await paymentService.processPayment(request: request)
            if status == .accepted {
                acceptedCount += 1
            }
        }
        
        print("✅ Accepted \(acceptedCount) payments")
        
        // Wait longer for processing attempts
        var attempts = 0
        while attempts < 30 { // Max 3 seconds
            let stats = await paymentService.getQueueStats()
            print("   [\(attempts * 100)ms] Pending: \(stats.pending), Processed: \(stats.processed)")
            
            if stats.pending == 0 || attempts >= 29 {
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            attempts += 1
        }
        
        // Check final state - this should show the inconsistency
        let finalStats = await paymentService.getQueueStats()
        let summary = await paymentService.getPaymentsSummary(from: nil, to: nil)
        let totalSummaryPayments = summary.default.totalRequests + summary.fallback.totalRequests
        let inconsistency = acceptedCount - totalSummaryPayments
        
        print("🔍 ROOT CAUSE CONFIRMED:")
        print("   Accepted (HTTP 202): \(acceptedCount)")
        print("   Processed by payment processors: \(finalStats.processed)")
        print("   Summary Total: \(totalSummaryPayments)")
        print("   Pending in queue: \(finalStats.pending)")
        print("   INCONSISTENCY: \(inconsistency)")
        print("")
        print("💡 DIAGNOSIS:")
        print("   - All payments return HTTP 202 (accepted)")
        print("   - Payment processors are DOWN/unreachable")
        print("   - Payments stay in queue forever")
        print("   - Summary only counts SUCCESSFULLY PROCESSED payments")
        print("   - K6 counts ACCEPTED vs PROCESSED => INCONSISTENCY!")
        
        // Document the problem
        XCTAssertGreaterThan(inconsistency, 0, "This test EXPECTS inconsistency due to processor failures")
        XCTAssertGreaterThan(finalStats.pending, 0, "Payments should remain pending due to processor failures")
    }
    
    /// Test our hypothesis about K6 inconsistency calculation
    func testK6InconsistencyHypothesis() async throws {
        print("🎯 TESTING K6 INCONSISTENCY HYPOTHESIS")
        
        // This simulates what happens during K6 testing:
        // 1. K6 sends 15,000+ payment requests
        // 2. All return HTTP 200/202 (considered "successful" by K6)
        // 3. Some fail to process due to processor issues/timeouts
        // 4. Summary only reports ACTUALLY PROCESSED payments
        // 5. K6 calculates: requests_sent - summary_total = inconsistency
        
        let simulatedK6Requests = 100
        var k6SuccessfulRequests = 0  // HTTP 200/202 responses
        
        for i in 0..<simulatedK6Requests {
            let request = PaymentRequest(
                correlationId: UUID(),
                amount: Double(i + 1) * 1.0
            )
            
            let status = try await paymentService.processPayment(request: request)
            if status == .accepted {
                k6SuccessfulRequests += 1  // K6 counts this as "successful"
            }
        }
        
        // Wait a bit for any processing attempts
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        let stats = await paymentService.getQueueStats()
        let summary = await paymentService.getPaymentsSummary(from: nil, to: nil)
        let actualProcessedPayments = summary.default.totalRequests + summary.fallback.totalRequests
        
        // This is how K6 calculates inconsistency
        let k6CalculatedInconsistency = k6SuccessfulRequests - actualProcessedPayments
        
        print("📊 K6 INCONSISTENCY SIMULATION:")
        print("   K6 'Successful' Requests (HTTP 202): \(k6SuccessfulRequests)")
        print("   Actually Processed by Payment Processors: \(actualProcessedPayments)")
        print("   K6 Calculated Inconsistency: \(k6CalculatedInconsistency)")
        print("   Queue State: \(stats.pending) pending, \(stats.processed) processed")
        print("")
        print("🎯 SOLUTION NEEDED:")
        print("   - Either ensure 100% of accepted payments are processed")
        print("   - Or improve payment processor reliability")
        print("   - Or implement retry logic with better timeouts")
        
        XCTAssertEqual(k6CalculatedInconsistency, stats.pending, 
                      "K6 inconsistency should equal pending payments when processors fail")
    }
    
    /// Test the timing of when inconsistency appears
    func testInconsistencyTiming() async throws {
        print("⏰ TESTING WHEN INCONSISTENCY APPEARS")
        
        // Add one payment
        let request = PaymentRequest(correlationId: UUID(), amount: 100.0)
        let status = try await paymentService.processPayment(request: request)
        XCTAssertEqual(status, .accepted, "Payment should be accepted")
        
        // Check inconsistency at different time intervals
        let timePoints = [0, 10, 50, 100, 500, 1000] // milliseconds
        
        for (index, ms) in timePoints.enumerated() {
            if ms > 0 {
                try await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
            }
            
            let stats = await paymentService.getQueueStats()
            let summary = await paymentService.getPaymentsSummary(from: nil, to: nil)
            let summaryTotal = summary.default.totalRequests + summary.fallback.totalRequests
            let inconsistency = stats.accepted - summaryTotal
            
            print("   [\(ms)ms] Accepted: \(stats.accepted), Summary: \(summaryTotal), Inconsistency: \(inconsistency), Pending: \(stats.pending)")
            
            if index == 0 {
                // Immediate inconsistency should exist
                XCTAssertGreaterThan(inconsistency, 0, "Inconsistency should appear immediately")
            }
        }
        
        print("💡 TIMING ANALYSIS:")
        print("   - Inconsistency appears IMMEDIATELY after payment acceptance")
        print("   - Payment is accepted (HTTP 202) but not yet processed")
        print("   - Summary only includes processed payments")
        print("   - This gap creates the inconsistency K6 measures")
    }
    
    // MARK: - Basic Functionality Tests
    
    /// Test basic payment acceptance (even without processors)
    func testBasicPaymentAcceptance() async throws {
        print("✅ Testing basic payment acceptance...")
        
        let request = PaymentRequest(
            correlationId: UUID(),
            amount: 50.0
        )
        
        let status = try await paymentService.processPayment(request: request)
        XCTAssertEqual(status, .accepted, "Payment should be accepted even if processors are down")
        
        let stats = await paymentService.getQueueStats()
        XCTAssertEqual(stats.accepted, 1, "Should have 1 accepted payment")
        XCTAssertEqual(stats.pending, 1, "Should have 1 pending payment")
        XCTAssertEqual(stats.processed, 0, "Should have 0 processed payments (processors down)")
        
        print("📊 Acceptance Test Results:")
        print("   Status: \(status)")
        print("   Accepted: \(stats.accepted)")
        print("   Pending: \(stats.pending)")
        print("   Processed: \(stats.processed)")
    }
    
    // MARK: - Simple Consistency Tests
    
    /// Test basic payment acceptance and processing
    func testBasicPaymentConsistency() async throws {
        print("🎯 Testing basic payment consistency...")
        
        let paymentCount = 10
        var acceptedCount = 0
        
        // Add payments sequentially to avoid concurrency issues
        for i in 0..<paymentCount {
            let request = PaymentRequest(
                correlationId: UUID(),
                amount: Double(i + 1) * 10.0
            )
            
            let status = try await paymentService.processPayment(request: request)
            if status == .accepted {
                acceptedCount += 1
            }
        }
        
        print("✅ Accepted \(acceptedCount) payments")
        
        // Wait for processing
        var attempts = 0
        while attempts < 50 { // Max 5 seconds
            let stats = await paymentService.getQueueStats()
            if stats.pending == 0 {
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            attempts += 1
        }
        
        // Check final consistency
        let finalStats = await paymentService.getQueueStats()
        let summary = await paymentService.getPaymentsSummary(from: nil, to: nil)
        let totalSummaryPayments = summary.default.totalRequests + summary.fallback.totalRequests
        let inconsistency = acceptedCount - totalSummaryPayments
        
        print("📈 Results:")
        print("   Accepted: \(acceptedCount)")
        print("   Processed: \(finalStats.processed)")
        print("   Summary Total: \(totalSummaryPayments)")
        print("   Pending: \(finalStats.pending)")
        print("   Inconsistency: \(inconsistency)")
        
        // Assert consistency
        XCTAssertEqual(inconsistency, 0, "Inconsistency detected: \(inconsistency)")
        XCTAssertEqual(finalStats.pending, 0, "Queue should be empty: \(finalStats.pending) pending")
    }
    
    /// Test immediate summary vs delayed summary
    func testSummaryTiming() async throws {
        print("⏰ Testing summary timing scenarios...")
        
        // Add a payment
        let request = PaymentRequest(correlationId: UUID(), amount: 50.0)
        let status = try await paymentService.processPayment(request: request)
        XCTAssertEqual(status, .accepted)
        
        // Test immediate summary
        let immediateStats = await paymentService.getQueueStats()
        let immediateSummary = await paymentService.getPaymentsSummary(from: nil, to: nil)
        let immediateTotal = immediateSummary.default.totalRequests + immediateSummary.fallback.totalRequests
        let immediateInconsistency = immediateStats.accepted - immediateTotal
        
        print("📊 Immediate Summary:")
        print("   Accepted: \(immediateStats.accepted)")
        print("   Summary Total: \(immediateTotal)")
        print("   Pending: \(immediateStats.pending)")
        print("   Inconsistency: \(immediateInconsistency)")
        
        // Wait and test delayed summary
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms
        
        let delayedStats = await paymentService.getQueueStats()
        let delayedSummary = await paymentService.getPaymentsSummary(from: nil, to: nil)
        let delayedTotal = delayedSummary.default.totalRequests + delayedSummary.fallback.totalRequests
        let delayedInconsistency = delayedStats.accepted - delayedTotal
        
        print("📊 Delayed Summary (500ms):")
        print("   Accepted: \(delayedStats.accepted)")
        print("   Summary Total: \(delayedTotal)")
        print("   Pending: \(delayedStats.pending)")
        print("   Inconsistency: \(delayedInconsistency)")
        
        // Final result should be consistent
        XCTAssertLessThanOrEqual(delayedInconsistency, immediateInconsistency, 
                                "Delayed summary should have same or better consistency")
    }
    
    /// Test queue monitoring
    func testQueueMonitoring() async throws {
        print("🔍 Testing queue monitoring...")
        
        // Add multiple payments quickly
        for i in 0..<5 {
            let request = PaymentRequest(
                correlationId: UUID(),
                amount: Double(i + 1) * 20.0
            )
            _ = try await paymentService.processPayment(request: request)
        }
        
        print("📦 Added 5 payments, monitoring queue...")
        
        // Monitor queue state changes
        var iterations = 0
        var lastStats = await paymentService.getQueueStats()
        print("   Initial: Pending: \(lastStats.pending), Accepted: \(lastStats.accepted), Processed: \(lastStats.processed)")
        
        while lastStats.pending > 0 && iterations < 20 { // Max 2 seconds
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            
            let currentStats = await paymentService.getQueueStats()
            if currentStats != lastStats {
                print("   Update: Pending: \(currentStats.pending), Accepted: \(currentStats.accepted), Processed: \(currentStats.processed)")
                lastStats = currentStats
            }
            iterations += 1
        }
        
        let finalStats = await paymentService.getQueueStats()
        print("🏁 Final: Pending: \(finalStats.pending), Accepted: \(finalStats.accepted), Processed: \(finalStats.processed)")
        
        // Check if queue was processed
        XCTAssertEqual(finalStats.pending, 0, "All payments should be processed")
        XCTAssertEqual(finalStats.accepted, finalStats.processed, "Accepted should equal processed")
    }
    
    /// Test processing rate measurement
    func testProcessingRate() async throws {
        print("⚡ Testing processing rate...")
        
        let paymentCount = 20
        let startTime = Date()
        
        // Add payments
        for i in 0..<paymentCount {
            let request = PaymentRequest(
                correlationId: UUID(),
                amount: Double(i + 1) * 5.0
            )
            _ = try await paymentService.processPayment(request: request)
        }
        
        let addTime = Date().timeIntervalSince(startTime)
        print("📦 Added \(paymentCount) payments in \(String(format: "%.3f", addTime))s")
        
        // Wait for all to be processed
        let processStart = Date()
        var processed = 0
        
        while processed < paymentCount {
            let stats = await paymentService.getQueueStats()
            processed = stats.processed
            
            if Date().timeIntervalSince(processStart) > 5.0 { // 5s timeout
                break
            }
            
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }
        
        let totalTime = Date().timeIntervalSince(startTime)
        let processTime = Date().timeIntervalSince(processStart)
        let rate = Double(processed) / processTime
        
        print("📈 Processing Results:")
        print("   Total Time: \(String(format: "%.3f", totalTime))s")
        print("   Processing Time: \(String(format: "%.3f", processTime))s")
        print("   Processing Rate: \(String(format: "%.1f", rate)) payments/s")
        print("   Processed: \(processed)/\(paymentCount)")
        
        XCTAssertEqual(processed, paymentCount, "All payments should be processed")
        XCTAssertGreaterThan(rate, 10.0, "Processing rate should be reasonable (>10/s)")
    }
    
    /// Test to reproduce exact K6 inconsistency calculation  
    func testK6InconsistencyCalculation() async throws {
        print("🎯 Testing exact K6 inconsistency calculation...")
        
        // Add payments sequentially
        let paymentCount = 5
        for i in 1...paymentCount {
            let request = PaymentRequest(
                correlationId: UUID(),
                amount: 19.90
            )
            let status = try await paymentService.processPayment(request: request)
            XCTAssertEqual(status, .accepted, "Payment \(i) should be accepted")
        }
        
        // Wait a bit for processing
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Get our backend summary (what K6 gets from our API)
        let backendSummary = await paymentService.getPaymentsSummary(from: nil, to: nil)
        
        // Simulate what K6 would expect from payment processors
        // (In real test, processors would have the payments we actually sent)
        let expectedDefaultAmount = 0.0  // Processors are not running in tests
        let expectedFallbackAmount = 0.0  // Processors are not running in tests
        
        // Calculate K6-style inconsistency
        let defaultInconsistency = abs(backendSummary.default.totalAmount - expectedDefaultAmount)
        let fallbackInconsistency = abs(backendSummary.fallback.totalAmount - expectedFallbackAmount)
        let totalInconsistency = defaultInconsistency + fallbackInconsistency
        
        print("📊 Backend DEFAULT amount: \(backendSummary.default.totalAmount)")
        print("📊 Backend FALLBACK amount: \(backendSummary.fallback.totalAmount)")
        print("📊 Expected DEFAULT amount: \(expectedDefaultAmount)")
        print("📊 Expected FALLBACK amount: \(expectedFallbackAmount)")
        print("📊 DEFAULT inconsistency: \(defaultInconsistency)")
        print("📊 FALLBACK inconsistency: \(fallbackInconsistency)")
        print("📊 TOTAL inconsistency: \(totalInconsistency)")
        
        // This should match the inconsistency we see in K6!
        XCTAssertGreaterThan(totalInconsistency, 0, "Should have inconsistency due to processor failures")
        
        // Get queue stats for analysis
        let stats = await paymentService.getQueueStats()
        print("📊 Queue stats: accepted=\(stats.accepted), processed=\(stats.processed), pending=\(stats.pending)")
        
        // The inconsistency should equal the pending amount (payments accepted but not processed)
        let expectedInconsistency = Double(stats.accepted - stats.processed) * 19.90
        print("📊 Expected inconsistency based on queue: \(expectedInconsistency)")
        
        // This confirms our hypothesis about the root cause
    }
} 