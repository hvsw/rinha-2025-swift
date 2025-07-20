import Vapor

func routes(_ app: Application, paymentService: PaymentService) throws {
    // Health check endpoint
    app.get("health") { req async in
        return ["status": "ok"]
    }
    
    let paymentController = PaymentController(paymentService: paymentService)
    try app.register(collection: paymentController)
}
