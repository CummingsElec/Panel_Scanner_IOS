import Foundation
import Combine

class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isProcessing: Bool = false
    @Published var loadingMessage: String = ""
    
    private let chatEngine: ChatEngineProtocol
    private let sessionManager: SessionManager
    private let chatHistoryPath: URL
    
    init(chatEngine: ChatEngineProtocol, sessionManager: SessionManager) {
        self.chatEngine = chatEngine
        self.sessionManager = sessionManager
        
        // Chat history path
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.chatHistoryPath = docs.appendingPathComponent("chat_history.json")
        
        loadHistory()
    }
    
    // MARK: - Message Handling
    
    func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let userText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let userMessage = ChatMessage(role: .user, content: userText)
        messages.append(userMessage)
        inputText = ""
        isProcessing = true
        loadingMessage = "Thinking..."
        
        Task {
            // Build context from current session
            let context = buildSessionContext()
            
            let result = await chatEngine.generateResponse(prompt: userText, context: context)
            
            await MainActor.run {
                switch result {
                case .success(let response):
                    let botMessage = ChatMessage(role: .assistant, content: response)
                    messages.append(botMessage)
                    
                case .failure(let error):
                    print("❌ [CHAT] Error: \(error)")
                    
                    let errorText: String
                    if let nsError = error as NSError? {
                        errorText = """
⚠️ Error Code \(nsError.code)

\(nsError.localizedDescription)

Domain: \(nsError.domain)

Check console logs for details.
"""
                    } else {
                        errorText = "⚠️ Error: \(error.localizedDescription)"
                    }
                    
                    let errorMessage = ChatMessage(
                        role: .assistant,
                        content: errorText
                    )
                    messages.append(errorMessage)
                }
                
                isProcessing = false
                loadingMessage = ""
                saveHistory()
            }
        }
    }
    
    func clearChat() {
        messages = [ChatMessage(
            role: .assistant,
            content: "👋 Hi! I'm your Electrical Guru. Ask me about panels, breakers, or electrical codes!"
        )]
        saveHistory()
    }
    
    // MARK: - Context Building
    
    private func buildSessionContext() -> String {
        var context = "Current session:\n"
        
        if let panel = sessionManager.panelPartNumber {
            context += "Panel: \(panel)\n"
        } else {
            context += "Panel: Not yet detected\n"
        }
        
        context += "Breakers detected: \(sessionManager.capturedBreakers.count)\n"
        
        if !sessionManager.capturedBreakers.isEmpty {
            context += "\nRecent breakers:\n"
            let recent = sessionManager.capturedBreakers.suffix(5)
            for breaker in recent {
                context += "  • #\(breaker.index): \(breaker.partNumber) (conf: \(Int(breaker.confidence * 100))%)\n"
            }
        }
        
        return context
    }
    
    // MARK: - Persistence
    
    private func loadHistory() {
        guard let data = try? Data(contentsOf: chatHistoryPath),
              let decoded = try? JSONDecoder().decode([ChatMessage].self, from: data) else {
            // Welcome message
            messages = [ChatMessage(
                role: .assistant,
                content: "👋 Hi! I'm your Electrical Guru. Ask me about panels, breakers, or electrical codes!"
            )]
            return
        }
        
        messages = decoded
        print("💬 Loaded \(messages.count) chat messages from history")
    }
    
    private func saveHistory() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        if let encoded = try? encoder.encode(messages) {
            try? encoded.write(to: chatHistoryPath)
            print("💾 Saved \(messages.count) chat messages")
        }
    }
}

