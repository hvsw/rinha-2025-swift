import Vapor

func routes(_ app: Application) throws {
    // Health check endpoint
    app.get("health") { req async in
        return ["status": "ok"]
    }
}
