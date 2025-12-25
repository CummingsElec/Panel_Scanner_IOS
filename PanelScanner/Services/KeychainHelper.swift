import Foundation
import Security

class KeychainHelper {
    static let shared = KeychainHelper()
    
    private let serviceName = "com.cummingselectrical.panelscanner"
    
    private init() {}
    
    func save(_ data: Data, forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    func read(forKey key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }
    
    func delete(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess
    }
    
    // Convenience methods for tokens
    func saveAccessToken(_ token: String) -> Bool {
        guard let data = token.data(using: .utf8) else { return false }
        return save(data, forKey: "accessToken")
    }
    
    func readAccessToken() -> String? {
        guard let data = read(forKey: "accessToken") else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    func deleteAccessToken() -> Bool {
        return delete(forKey: "accessToken")
    }
    
    func saveRefreshToken(_ token: String) -> Bool {
        guard let data = token.data(using: .utf8) else { return false }
        return save(data, forKey: "refreshToken")
    }
    
    func readRefreshToken() -> String? {
        guard let data = read(forKey: "refreshToken") else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    func deleteRefreshToken() -> Bool {
        return delete(forKey: "refreshToken")
    }
    
    func clearAll() {
        _ = deleteAccessToken()
        _ = deleteRefreshToken()
    }
}

