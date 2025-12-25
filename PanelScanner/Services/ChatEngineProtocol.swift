import Foundation

enum ChatError: Error {
    case invalidResponse
    case serverError
    case networkError
    case noAPIKey
}

protocol ChatEngineProtocol {
    func generateResponse(prompt: String, context: String) async -> Result<String, Error>
}
