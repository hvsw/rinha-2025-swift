import Vapor

// configures your application
public func configure(_ app: Application) async throws {
    // Configure server to run on port 9999
    app.http.server.configuration.port = 9999
    app.http.server.configuration.hostname = "0.0.0.0"
    
    // PHASE 3C: Configure HTTP client with connection pooling for maximum performance
    app.clients.use(.http)
    
    // Configure HTTP client timeouts for faster processing
    app.http.client.configuration.timeout = HTTPClient.Configuration.Timeout(
        connect: .seconds(3),
        read: .seconds(3)
    )
    
    // Configure JSON encoder/decoder for ISO 8601 date format
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    encoder.dateEncodingStrategy = .iso8601
    decoder.dateDecodingStrategy = .iso8601
    
    ContentConfiguration.global.use(encoder: encoder, for: .json)
    ContentConfiguration.global.use(decoder: decoder, for: .json)
    
    // Create payment service
    let paymentService = PaymentService(app: app)
    
    // register routes (PaymentController will be created inside routes function)
    try routes(app)
}
