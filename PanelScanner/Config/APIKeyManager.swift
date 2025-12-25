import Foundation

class APIKeyManager {
    static let shared = APIKeyManager()
    
    private var cachedKeys: [String: String] = [:]
    
    private init() {
        loadKeysFromPlist()
    }
    
    func getKey(for provider: String) -> String? {
        let settingsKey = SettingsStore.shared.aiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if Settings has a real key
        if !settingsKey.isEmpty && !settingsKey.contains("YOUR_") && settingsKey.count > 20 {
            return settingsKey
        }
        
        // Fall back to plist (hardcoded key for this device)
        let plistKey = provider == "xai" ? "xAI_API_Key" : "OpenAI_API_Key"
        if let key = cachedKeys[plistKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !key.isEmpty && !key.contains("YOUR_") && key.count > 20 {
            return key
        }
        
        return nil
    }
    
    private func loadKeysFromPlist() {
        guard let plistPath = Bundle.main.path(forResource: "APIKeys", ofType: "plist"),
              let plistData = FileManager.default.contents(atPath: plistPath),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: String] else {
            print("⚠️ [API] APIKeys.plist not found - using Settings only")
            return
        }
        
        cachedKeys = plist
        
        // Don't log actual keys!
        let hasOpenAI = plist["OpenAI_API_Key"]?.isEmpty == false && plist["OpenAI_API_Key"] != "YOUR_OPENAI_KEY_HERE"
        let hasXAI = plist["xAI_API_Key"]?.isEmpty == false && plist["xAI_API_Key"] != "YOUR_XAI_KEY_HERE"
        
        if hasOpenAI || hasXAI {
            print("✅ [API] Keys loaded from plist (OpenAI: \(hasOpenAI), xAI: \(hasXAI))")
        }
    }
}

