import Vapor
import Foundation

struct PaymentController: RouteCollection {
    private let paymentService: PaymentService
    
    init(paymentService: PaymentService) {
        self.paymentService = paymentService
    }
    
    func boot(routes: any RoutesBuilder) throws {
        let payments = routes.grouped("payments")
        
        payments.post("", use: createPayment)
        
        routes.get("payments-summary", use: getPaymentsSummary)
    }
    
    func createPayment(req: Request) async throws -> Response {
        let paymentRequest = try req.content.decode(PaymentRequest.self)
        
        // Validate required fields
        guard paymentRequest.amount > 0 else {
            throw Abort(.badRequest, reason: "Amount must be greater than 0")
        }
        
        // Process payment asynchronously - always returns .accepted
        let status = try await paymentService.processPayment(request: paymentRequest)
        
        let response = Response(status: status)
        try response.content.encode(["message": "Payment accepted for processing"])
        return response
    }
    
    func getPaymentsSummary(req: Request) async throws -> PaymentSummaryResponse {
        let from = req.query["from"].flatMap { dateFromString($0) }
        let to = req.query["to"].flatMap { dateFromString($0) }
        
        return await paymentService.getPaymentsSummary(from: from, to: to)
    }
    
    // PHASE 3B: Removed old paymentsSummary method to avoid conflicts
    // Only using getPaymentsSummary for k6 compatibility
    
    private func dateFromString(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        return formatter.date(from: string)
    }
} 