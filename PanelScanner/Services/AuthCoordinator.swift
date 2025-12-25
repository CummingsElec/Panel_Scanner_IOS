import Foundation
import AuthenticationServices
import Combine

class AuthCoordinator: NSObject, ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: UserInfo?
    @Published var authError: String?
    @Published var isLocalMode = false
    
    private let config = AuthConfiguration.default
    private var presentationContext: ASWebAuthenticationPresentationContextProviding?
    private var currentProvider: IdentityProvider = .microsoftEntraID
    
    // Token expiry tracking
    private var tokenExpiryDate: Date?
    private var refreshTimer: Timer?
    
    override init() {
        super.init()
        checkExistingAuth()
        setupRefreshTimer()
    }
    
    // MARK: - Public Methods
    
    func signIn(provider: IdentityProvider, presentationContext: ASWebAuthenticationPresentationContextProviding) {
        self.currentProvider = provider
        self.presentationContext = presentationContext
        
        let authURL: URL
        let callbackScheme: String
        
        // Only Microsoft Entra ID supported now
        authURL = buildEntraAuthURL()
        callbackScheme = URL(string: config.entraRedirectURI)?.scheme ?? "msauth.com.cummingselectrical.panelscanner"
        
        let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: callbackScheme) { [weak self] callbackURL, error in
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async {
                    self.authError = error.localizedDescription
                }
                return
            }
            
            guard let callbackURL = callbackURL else {
                DispatchQueue.main.async {
                    self.authError = "No callback URL received"
                }
                return
            }
            
            self.handleCallback(url: callbackURL, provider: provider)
        }
        
        session.presentationContextProvider = presentationContext as? ASWebAuthenticationPresentationContextProviding
        session.prefersEphemeralWebBrowserSession = false
        session.start()
    }
    
    func signOut() {
        KeychainHelper.shared.clearAll()
        isAuthenticated = false
        currentUser = nil
        tokenExpiryDate = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    func refreshTokenIfNeeded() async {
        guard let refreshToken = KeychainHelper.shared.readRefreshToken() else {
            signOut()
            return
        }
        
        // Check if token needs refresh (refresh 5 min before expiry)
        if let expiryDate = tokenExpiryDate, Date().addingTimeInterval(300) < expiryDate {
            return
        }
        
        await refreshAccessToken(refreshToken: refreshToken)
    }
    
    func bypassAuthForTesting() {
        #if DEBUG
        // Debug only: bypass auth entirely
        _ = KeychainHelper.shared.saveAccessToken("DEBUG_TOKEN")
        isAuthenticated = true
        currentUser = UserInfo(sub: "debug_user", email: "debug@localhost", name: "Debug User", groups: nil)
        print("🔧 Debug: Auth bypassed for local testing")
        #endif
    }
    
    func checkLicense() async -> Bool {
        // If local mode, skip remote license check
        if isLocalMode {
            #if DEBUG
            print("🔧 Local mode: Skipping license check")
            #endif
            return true
        }
        
        guard let endpoint = config.licenseEndpoint,
              let url = URL(string: endpoint),
              let accessToken = KeychainHelper.shared.readAccessToken() else {
            // No license endpoint configured, allow for now
            return true
        }
        
        var request = URLRequest(url: url)
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
            return false
        } catch {
            #if DEBUG
            print("⚠️ License check failed: \(error)")
            #endif
            return false
        }
    }
    
    // MARK: - Private Methods
    
    private func checkExistingAuth() {
        guard let accessToken = KeychainHelper.shared.readAccessToken() else {
            isAuthenticated = false
            return
        }
        
        // Validate token (basic check)
        if !accessToken.isEmpty {
            isAuthenticated = true
            // TODO: Decode JWT to get user info and expiry
            loadUserInfo()
        }
    }
    
    private func buildEntraAuthURL() -> URL {
        var components = URLComponents(string: "https://login.microsoftonline.com/\(config.entraTenantId)/oauth2/v2.0/authorize")!
        
        let state = UUID().uuidString
        let codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)
        
        // Store verifier for token exchange
        UserDefaults.standard.set(codeVerifier, forKey: "pkce_verifier")
        
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.entraClientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: config.entraRedirectURI),
            URLQueryItem(name: "response_mode", value: "query"),
            URLQueryItem(name: "scope", value: config.entraScopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        
        return components.url!
    }
    
    
    private func handleCallback(url: URL, provider: IdentityProvider) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            DispatchQueue.main.async {
                self.authError = "Invalid callback URL"
            }
            return
        }
        
        // Extract authorization code
        guard let code = queryItems.first(where: { $0.name == "code" })?.value else {
            DispatchQueue.main.async {
                self.authError = "No authorization code received"
            }
            return
        }
        
        // Exchange code for token
        Task {
            await exchangeCodeForToken(code: code, provider: provider)
        }
    }
    
    private func exchangeCodeForToken(code: String, provider: IdentityProvider) async {
        guard let codeVerifier = UserDefaults.standard.string(forKey: "pkce_verifier") else {
            DispatchQueue.main.async {
                self.authError = "PKCE verifier not found"
            }
            return
        }
        
        // Only Microsoft Entra ID supported
        let tokenURL = URL(string: "https://login.microsoftonline.com/\(config.entraTenantId)/oauth2/v2.0/token")!
        let clientId = config.entraClientId
        let redirectURI = config.entraRedirectURI
        
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyParams = [
            "grant_type": "authorization_code",
            "client_id": clientId,
            "code": code,
            "redirect_uri": redirectURI,
            "code_verifier": codeVerifier
        ]
        
        request.httpBody = bodyParams.map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
            
            // Save tokens to Keychain
            _ = KeychainHelper.shared.saveAccessToken(tokenResponse.accessToken)
            if let refreshToken = tokenResponse.refreshToken {
                _ = KeychainHelper.shared.saveRefreshToken(refreshToken)
            }
            
            // Calculate expiry
            tokenExpiryDate = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
            
            // Clean up
            UserDefaults.standard.removeObject(forKey: "pkce_verifier")
            
            // Load user info and update state
            await loadUserInfo()
            
            DispatchQueue.main.async {
                self.isAuthenticated = true
            }
            
        } catch {
            DispatchQueue.main.async {
                self.authError = "Token exchange failed: \(error.localizedDescription)"
            }
        }
    }
    
    private func loadUserInfo() async {
        guard let accessToken = KeychainHelper.shared.readAccessToken() else { return }
        
        // Decode JWT to get basic user info (simplified)
        if let payload = decodeJWT(accessToken) {
            DispatchQueue.main.async {
                self.currentUser = payload
            }
        }
    }
    
    private func loadUserInfo() {
        guard let accessToken = KeychainHelper.shared.readAccessToken() else { return }
        
        if let payload = decodeJWT(accessToken) {
            currentUser = payload
        }
    }
    
    private func refreshAccessToken(refreshToken: String) async {
        // Only Microsoft Entra ID supported
        let tokenURL = URL(string: "https://login.microsoftonline.com/\(config.entraTenantId)/oauth2/v2.0/token")!
        let clientId = config.entraClientId
        
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyParams = [
            "grant_type": "refresh_token",
            "client_id": clientId,
            "refresh_token": refreshToken
        ]
        
        request.httpBody = bodyParams.map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
            
            _ = KeychainHelper.shared.saveAccessToken(tokenResponse.accessToken)
            if let newRefreshToken = tokenResponse.refreshToken {
                _ = KeychainHelper.shared.saveRefreshToken(newRefreshToken)
            }
            
            tokenExpiryDate = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
            
        } catch {
            #if DEBUG
            print("⚠️ Token refresh failed: \(error)")
            #endif
            signOut()
        }
    }
    
    private func setupRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task {
                await self?.refreshTokenIfNeeded()
            }
        }
    }
    
    // MARK: - PKCE Helpers
    
    private func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
    
    private func generateCodeChallenge(from verifier: String) -> String {
        guard let data = verifier.data(using: .utf8) else { return "" }
        var buffer = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &buffer)
        }
        return Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
    
    // Simple JWT decoder (for basic claims only)
    private func decodeJWT(_ token: String) -> UserInfo? {
        let segments = token.components(separatedBy: ".")
        guard segments.count > 1 else { return nil }
        
        let base64String = segments[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padded = base64String.padding(toLength: ((base64String.count + 3) / 4) * 4, withPad: "=", startingAt: 0)
        
        guard let data = Data(base64Encoded: padded) else { return nil }
        
        return try? JSONDecoder().decode(UserInfo.self, from: data)
    }
}

// Import CommonCrypto for SHA256
import CommonCrypto

