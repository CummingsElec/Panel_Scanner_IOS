import Foundation

class CloudChatEngine: ChatEngineProtocol {
    private let apiKey: String
    private let apiProvider: String  // "openai" or "xai"
    private var baseURL: String {
        switch apiProvider {
        case "xai":
            return "https://api.x.ai/v1/chat/completions"
        default:  // "openai"
            return "https://api.openai.com/v1/chat/completions"
        }
    }
    
    private var modelName: String {
        switch apiProvider {
        case "xai":
            return "grok-2-1212"  // xAI's Grok 2 (cheaper, faster)
        default:
            return "gpt-3.5-turbo"  // OpenAI
        }
    }
    
    init(apiKey: String, provider: String = "openai") {
        self.apiKey = apiKey
        self.apiProvider = provider
    }
    
    func generateResponse(prompt: String, context: String) async -> Result<String, Error> {
        // Build electrical expert system prompt
        let systemMessage: [String: String] = [
            "role": "system",
            "content": """
You are an expert electrician and NEC code specialist. Answer questions about electrical panels, breakers, amperage ratings, and code requirements clearly and concisely.

Use this context from the current scan session:
\(context)

Provide accurate, helpful answers. If you're not certain, say so.
"""
        ]
        
        let userMessage: [String: String] = [
            "role": "user",
            "content": prompt
        ]
        
        let requestBody: [String: Any] = [
            "model": modelName,
            "messages": [systemMessage, userMessage],
            "temperature": 0.7,
            "max_tokens": 300
        ]
        
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 30
        
        print("🌐 [GURU] Calling \(apiProvider == "xai" ? "Grok" : "GPT-3.5")...")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ [API] Invalid HTTP response")
                return .failure(ChatError.invalidResponse)
            }
            
            // Handle errors
            if httpResponse.statusCode != 200 {
                print("❌ [GURU] API error (status \(httpResponse.statusCode))")
                
                // Log response for debugging
                if let responseString = String(data: data, encoding: .utf8) {
                    print("   Response: \(responseString.prefix(200))")
                }
                
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    return .failure(NSError(domain: "CloudChat", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: message]))
                }
                
                return .failure(ChatError.serverError)
            }
            
            // Parse response
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                print("❌ [GURU] Failed to parse response")
                return .failure(ChatError.invalidResponse)
            }
            
            let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
            print("✅ [GURU] Response received (\(trimmedContent.count) chars)")
            
            return .success(trimmedContent)
            
        } catch {
            print("❌ [GURU] Network error: \(error.localizedDescription)")
            return .failure(error)
        }
    }
}

