import SwiftUI

struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    @EnvironmentObject var settingsStore: SettingsStore
    
    // Cloud-only: OpenAI or xAI
    init(sessionManager: SessionManager) {
        let settings = SettingsStore.shared
        
        // Get API key from APIKeyManager (checks Settings then plist)
        let apiKey = APIKeyManager.shared.getKey(for: settings.aiProvider) ?? ""
        
        let engine = CloudChatEngine(
            apiKey: apiKey,
            provider: settings.aiProvider
        )
        
        _viewModel = StateObject(wrappedValue: ChatViewModel(
            chatEngine: engine,
            sessionManager: sessionManager
        ))
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // API Key warning if not set (check both Settings and plist)
                if APIKeyManager.shared.getKey(for: settingsStore.aiProvider) == nil {
                    apiKeyWarningBanner
                }
                
                // Messages list
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                            
                            // Processing indicator
                            if viewModel.isProcessing {
                                HStack(spacing: 12) {
                                    ProgressView()
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(viewModel.loadingMessage)
                                            .font(.subheadline)
                                            .foregroundColor(.primary)
                                        Text("Powered by \(settingsStore.aiProvider == "xai" ? "xAI Grok" : "OpenAI GPT-3.5")")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding()
                                .background(Color.cyan.opacity(0.1))
                                .cornerRadius(12)
                                .padding(.horizontal)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.messages.count) { oldValue, newValue in
                        if let lastMessage = viewModel.messages.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
                
                Divider()
                
                // Input bar
                HStack(spacing: 12) {
                    TextField("Ask about panels, breakers, NEC codes...", text: $viewModel.inputText, axis: .vertical)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .lineLimit(1...4)
                        .disabled(viewModel.isProcessing || hasNoAPIKey)
                        .onSubmit {
                            if !hasNoAPIKey {
                                viewModel.sendMessage()
                            }
                        }
                    
                    Button(action: { viewModel.sendMessage() }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundColor(canSend ? .cyan : .gray)
                    }
                    .disabled(!canSend)
                }
                .padding()
                .background(Color(.systemBackground))
            }
            .navigationTitle("⚡ Electrical Guru")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { viewModel.clearChat() }) {
                            Label("Clear Chat", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }
    
    private var hasNoAPIKey: Bool {
        APIKeyManager.shared.getKey(for: settingsStore.aiProvider) == nil
    }
    
    private var canSend: Bool {
        !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !viewModel.isProcessing &&
        !hasNoAPIKey
    }
    
    private var apiKeyWarningBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("API Key Required")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("Add your \(settingsStore.aiProvider == "xai" ? "xAI" : "OpenAI") API key in Settings")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(Color.orange.opacity(0.1))
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user {
                Spacer()
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                // Message content
                Text(parseMarkdown(message.content))
                    .padding(12)
                    .background(bubbleBackground)
                    .foregroundColor(bubbleTextColor)
                    .cornerRadius(16)
                
                // Timestamp
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: 280, alignment: message.role == .user ? .trailing : .leading)
            
            if message.role == .assistant || message.role == .system {
                Spacer()
            }
        }
    }
    
    private var bubbleBackground: Color {
        switch message.role {
        case .user: return Color.cyan
        case .assistant: return Color(.systemGray5)
        case .system: return Color.orange.opacity(0.2)
        }
    }
    
    private var bubbleTextColor: Color {
        switch message.role {
        case .user: return .white
        case .assistant: return .primary
        case .system: return .orange
        }
    }
    
    // Simple markdown parser for **bold**
    private func parseMarkdown(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        
        // Find **bold** patterns
        let pattern = "\\*\\*([^*]+)\\*\\*"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let nsString = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
            
            for match in matches.reversed() {
                if let range = Range(match.range, in: text) {
                    let boldText = text[range].replacingOccurrences(of: "**", with: "")
                    
                    if let attrRange = AttributedString(text).range(of: String(text[range])) {
                        attributed[attrRange].inlinePresentationIntent = .stronglyEmphasized
                    }
                }
            }
        }
        
        return attributed
    }
}

#Preview {
    ChatView(sessionManager: SessionManager())
}
