import Vapor
import Foundation

// The configure function is called before your application
// initializes.
public func configure(_ app: Application) throws {
    // Phase 3B: Swift/Vapor optimizations for increased resources
    
    // EventLoop optimization - use more threads with increased CPU
    if let eventLoopGroup = app.eventLoopGroup as? MultiThreadedEventLoopGroup {
        // With 0.675 CPU, we can handle more concurrent operations
        app.logger.info("EventLoop threads: \(eventLoopGroup.configuration.threadCount)")
    }
    
    // HTTP client optimization for payment processor connections
    app.http.client.configuration.timeout = HTTPClient.Configuration.Timeout(
        connect: .seconds(3),    // Faster connect timeout
        read: .seconds(4)        // Keep read timeout
    )
    
    // Connection pool optimization for increased throughput
    app.http.client.configuration.connectionPool = HTTPClient.Configuration.ConnectionPool(
        idleTimeout: .seconds(30),           // Keep connections alive longer
        concurrentHTTP1ConnectionsPerHost: 15 // Increased from default (8)
    )
    
    // Memory management optimization
    app.http.client.configuration.decompression = .disabled  // Save CPU/memory
    
    // Register routes - import from the routes module
    try RinhaBackend.routes(app)
} 