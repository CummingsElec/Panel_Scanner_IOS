import Foundation

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: Role
    let content: String
    let timestamp: Date
    var linkedItemId: UUID?  // Optional link to detection/panel
    
    enum Role: String, Codable {
        case user, assistant, system
    }
    
    init(role: Role, content: String, linkedItemId: UUID? = nil) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.linkedItemId = linkedItemId
    }
}

