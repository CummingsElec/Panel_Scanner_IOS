import Foundation

enum IdentityProvider: String, Codable, CaseIterable {
    case microsoftEntraID = "Microsoft Entra ID"
    
    var displayName: String { rawValue }
}

struct AuthConfiguration: Codable {
    // Microsoft Entra ID config
    let entraClientId: String
    let entraTenantId: String
    let entraRedirectURI: String
    let entraScopes: [String]
    let entraAllowedGroup: String?  // Optional group/claim requirement
    
    // License/validation endpoint (stub for now)
    let licenseEndpoint: String?
    
    static var `default`: AuthConfiguration {
        return AuthConfiguration(
            // TODO: Configure these values in Xcode build settings or environment
            entraClientId: "YOUR_ENTRA_CLIENT_ID",
            entraTenantId: "YOUR_ENTRA_TENANT_ID",
            entraRedirectURI: "msauth.com.cummingselectrical.panelscanner://auth",
            entraScopes: ["openid", "profile", "email", "offline_access"],
            entraAllowedGroup: nil, // Set to specific group ID if required
            
            licenseEndpoint: nil  // Set to your internal license validation endpoint
        )
    }
}

struct TokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let idToken: String?
    let expiresIn: Int
    let tokenType: String
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

struct UserInfo: Codable {
    let sub: String
    let email: String?
    let name: String?
    let groups: [String]?
}

