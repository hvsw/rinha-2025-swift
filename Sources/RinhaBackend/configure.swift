import Vapor

// configures your application
public func configure(_ app: Application) async throws {
    // Configure server to run on port 9999
    app.http.server.configuration.port = 9999
    app.http.server.configuration.hostname = "0.0.0.0"
    
    // Create payment service
    let paymentService = PaymentService(app: app)
    
    // Create and register payment controller
    let paymentController = PaymentController(paymentService: paymentService)
    
    // register routes
    try app.register(collection: paymentController)
    try routes(app)
}
