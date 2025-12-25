import SwiftUI

// Live debug console showing recent log messages
struct DebugConsoleView: View {
    @ObservedObject var logger = DebugLogger.shared
    @State private var messageSnapshot: [LogMessage] = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Debug Console (\(messageSnapshot.count))")
                    .font(.headline)
                Spacer()
                Button("Clear") {
                    logger.clear()
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .padding()
            .background(Color(.systemGray6))
            
            // Log messages - use snapshot to avoid concurrent mutation crashes
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(0..<messageSnapshot.count, id: \.self) { index in
                        HStack(alignment: .top, spacing: 8) {
                            Text(messageSnapshot[index].timestamp)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 60, alignment: .leading)
                            
                            Text(messageSnapshot[index].icon)
                                .font(.system(size: 12))
                            
                            Text(messageSnapshot[index].text)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(messageSnapshot[index].color)
                                .lineLimit(3)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                    }
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.black)
        }
        .onAppear {
            updateSnapshot()
        }
        .onChange(of: logger.messages.count) { _ in
            updateSnapshot()
        }
    }
    
    private func updateSnapshot() {
        // Create immutable snapshot to avoid concurrent modification
        messageSnapshot = Array(logger.messages)
    }
}

// Global debug logger singleton - thread-safe with snapshot pattern
class DebugLogger: ObservableObject {
    static let shared = DebugLogger()
    
    @Published private(set) var messages: [LogMessage] = []
    private let maxMessages = 50  // Further reduced to avoid rendering issues
    private var allMessages: [LogMessage] = []  // Keep full history for export
    private let lock = NSLock()
    
    private init() {}
    
    func log(_ message: String, level: LogLevel = .info) {
        // Always print to Xcode console immediately
        print("\(level.icon) \(message)")
        
        // Thread-safe update
        lock.lock()
        defer { lock.unlock() }
        
        let logMessage = LogMessage(text: message, level: level)
        
        // Keep full history for export
        allMessages.append(logMessage)
        
        // Update on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.lock.lock()
            self.messages.append(logMessage)
            
            // Keep only last N messages for display
            if self.messages.count > self.maxMessages {
                self.messages.removeFirst(self.messages.count - self.maxMessages)
            }
            self.lock.unlock()
        }
    }
    
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        
        DispatchQueue.main.async { [weak self] in
            self?.lock.lock()
            self?.messages.removeAll()
            self?.lock.unlock()
        }
        
        // Don't clear allMessages - keep full history for export
    }
    
    func getLogMessages() -> [LogMessage] {
        lock.lock()
        defer { lock.unlock() }
        return allMessages
    }
}

struct LogMessage: Identifiable {
    let id = UUID()
    let text: String
    let level: LogLevel
    let timestamp: String
    
    var icon: String {
        level.icon
    }
    
    var color: Color {
        level.color
    }
    
    init(text: String, level: LogLevel) {
        self.text = text
        self.level = level
        
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        self.timestamp = formatter.string(from: Date())
    }
}

enum LogLevel: String {
    case debug
    case info
    case warning
    case error
    case success
    
    var icon: String {
        switch self {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        case .success: return "✅"
        }
    }
    
    var color: Color {
        switch self {
        case .debug: return .gray
        case .info: return .white
        case .warning: return .orange
        case .error: return .red
        case .success: return .green
        }
    }
}

// Usage: DebugLogger.shared.log("Message", level: .info)

