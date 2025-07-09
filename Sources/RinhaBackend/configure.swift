import Vapor

// configures your application
public func configure(_ app: Application) async throws {
    // Configure server to run on port 9999
    app.http.server.configuration.port = 9999
    app.http.server.configuration.hostname = "0.0.0.0"
    
    // Configure HTTP client for external requests
    app.clients.use(.http)
    
    // Create payment service
    let paymentService = PaymentService(app: app)
    
    // register routes (PaymentController will be created inside routes function)
    try routes(app)
}
