import Vapor
import Redis

public func configure(_ app: Application) async throws {
    // Server configuration
    // Porta 8080 interna - NGINX irá expor na 9999 conforme especificação da Rinha
    app.http.server.configuration.port = 8080
    // Aceitar conexões de qualquer IP para funcionar dentro do Docker
    app.http.server.configuration.hostname = "0.0.0.0"
    // Desabilitar compressão para economizar CPU
    app.http.server.configuration.responseCompression = .disabled
    // Desabilitar descompressão para economizar CPU
    app.http.server.configuration.requestDecompression = .disabled
    
    // Redis configuration for high-performance shared state
    let redisURL = Environment.get("REDIS_URL") ?? "redis://localhost:6379"
    try app.redis.configuration = RedisConfiguration(url: redisURL)
    
    // HTTP client configuration
    app.clients.use(.http)
    
    // Timeouts balanceados para 2 APIs (0.6 CPU + 130M cada)
    app.http.client.configuration.timeout = HTTPClient.Configuration.Timeout(
        connect: .seconds(3),
        read: .seconds(8)
    )
    
    // Pool balanceado para 2 APIs (130MB cada)
    app.http.client.configuration.connectionPool = HTTPClient.Configuration.ConnectionPool(
        idleTimeout: .seconds(60),
        concurrentHTTP1ConnectionsPerHostSoftLimit: 25
    )
    
    // Desabilitar descompressão para economizar CPU e memória
    app.http.client.configuration.decompression = .disabled
    
    // Log para monitoramento de threads do EventLoop
    app.logger.info("EventLoop group: \(app.eventLoopGroup)")
    
    // JSON configuration for ISO 8601 dates
    // Configuração ISO 8601 necessária para compatibilidade com payment processors
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    encoder.dateEncodingStrategy = .iso8601
    decoder.dateDecodingStrategy = .iso8601
    
    ContentConfiguration.global.use(encoder: encoder, for: .json)
    ContentConfiguration.global.use(decoder: decoder, for: .json)
    
    // Initialize services and routes
    // PaymentService gerencia conexões com ambos os payment processors
    let paymentService = try await PaymentService(app: app)
    try routes(app, paymentService: paymentService)
}
