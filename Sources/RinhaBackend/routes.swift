import Vapor

func routes(_ app: Application) throws {
    // Health check endpoint
    app.get("health") { req async in
        return ["status": "ok"]
    }
    
    // PHASE 2D: Register payment routes using RouteCollection
    let paymentService = PaymentService(app: app)
    let paymentController = PaymentController(paymentService: paymentService)
    
    // Register the payment controller routes
    try app.register(collection: paymentController)
    
    // PHASE 3B: Use correct summary endpoint for k6 compatibility
    // Note: PaymentController already registers "payments-summary" via getPaymentsSummary
}
