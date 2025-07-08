# Rinha de Backend 2025 - Swift/Vapor Implementation

This is a Swift implementation using the Vapor framework for the Rinha de Backend 2025 challenge.

## Architecture

The solution consists of:

- **2 Backend Instances**: Swift/Vapor applications running on separate containers
- **Load Balancer**: Nginx distributing requests between the two backend instances
- **Payment Integration**: Async integration with default and fallback payment processors
- **In-Memory Storage**: Fast in-memory storage for payment records

## Technologies Used

- **Language**: Swift 6.0
- **Framework**: Vapor 4.115.0
- **Load Balancer**: Nginx
- **Containerization**: Docker
- **Networking**: Docker Compose with external networks

## Features

- **Smart Payment Processing**: Tries default processor first, falls back to fallback processor
- **Health Check Integration**: Monitors payment processor health (with rate limiting)
- **Async Processing**: Non-blocking payment processing with proper error handling
- **Resource Optimized**: Configured to run within the specified resource limits

## API Endpoints

### POST /payments
Processes a payment request.

**Request:**
```json
{
    "correlationId": "uuid",
    "amount": 19.90
}
```

**Response:** HTTP 200/201/202 with optional message

### GET /payments-summary
Returns payment processing summary.

**Query Parameters:**
- `from`: ISO timestamp (optional)
- `to`: ISO timestamp (optional)

**Response:**
```json
{
    "default": {
        "totalRequests": 100,
        "totalAmount": 1500.50
    },
    "fallback": {
        "totalRequests": 50,
        "totalAmount": 750.25
    }
}
```

## Setup and Running

### Prerequisites
- Docker and Docker Compose
- Payment processor network must be created first

### Build and Run

1. **Start the payment processors first:**
```bash
# From the root directory
cd payment-processor
docker-compose up -d
```

2. **Build and start the backend:**
```bash
cd swift/RinhaBackend
docker-compose build
docker-compose up
```

The API will be available at `http://localhost:9999`

## Resource Allocation

- **Total CPU**: 1.5 units
- **Total Memory**: 350MB
- **Distribution**:
  - Nginx: 0.2 CPU, 50MB
  - App1: 0.65 CPU, 150MB  
  - App2: 0.65 CPU, 150MB

## Payment Processing Strategy

1. **Default First**: Always try the default processor first (lower fees)
2. **Fallback on Failure**: Use fallback processor if default fails
3. **Health Monitoring**: Check processor health before sending requests (rate-limited)
4. **Async Processing**: Process payments asynchronously to handle high loads
5. **Error Handling**: Graceful degradation when processors are unavailable

## Development

### Local Development
```bash
# Install dependencies
swift package resolve

# Run locally
swift run
```

### Testing
```bash
# Run tests
swift test
```

## Docker Configuration

The solution uses Docker Compose with:
- **Bridge networking** (as required)
- **External payment-processor network** for integration
- **Resource limits** as specified
- **No privileged mode** (compliant with restrictions)
- **No replicated services** (uses multiple named services instead)

## Performance Optimizations

- **Actor-based concurrency** for thread-safe payment processing
- **Connection pooling** for HTTP clients
- **Efficient in-memory storage** with filtering
- **Nginx load balancing** for request distribution
- **Async/await** throughout for non-blocking operations

### See more

- [Vapor Website](https://vapor.codes)
- [Vapor Documentation](https://docs.vapor.codes)
- [Vapor GitHub](https://github.com/vapor)
- [Vapor Community](https://github.com/vapor-community)
