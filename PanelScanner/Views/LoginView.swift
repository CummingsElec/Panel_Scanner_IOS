import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @ObservedObject var authCoordinator: AuthCoordinator
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.1, blue: 0.2),
                    Color(red: 0.1, green: 0.15, blue: 0.3),
                    Color(red: 0.15, green: 0.2, blue: 0.35)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                // Logo/Branding
                VStack(spacing: 20) {
                    // App icon if available
                    Image(systemName: "viewfinder.rectangular")
                        .font(.system(size: 80))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.cyan, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("Cummings Electrical")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("Panel Scanner V3")
                        .font(.title2)
                        .foregroundColor(.cyan.opacity(0.8))
                }
                
                Spacer()
                
                // Auth buttons
                VStack(spacing: 20) {
                    // Sign in button
                    Button(action: {
                        authCoordinator.signIn(provider: .microsoftEntraID, presentationContext: PresentationContextProvider())
                    }) {
                        HStack {
                            Image(systemName: "person.badge.key.fill")
                            Text("Sign In with Microsoft")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [.cyan, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .shadow(color: .cyan.opacity(0.3), radius: 10, x: 0, y: 5)
                    }
                    .padding(.horizontal)
                    
                    // Error message
                    if let error = authCoordinator.authError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding()
                            .background(Color.white.opacity(0.9))
                            .cornerRadius(8)
                            .padding(.horizontal)
                    }
                    
                    #if DEBUG
                    // Debug skip button
                    Button("Skip Login (Debug Only)") {
                        // Bypass auth for local testing
                        authCoordinator.bypassAuthForTesting()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .fontWeight(.semibold)
                    .padding(.horizontal)
                    #endif
                }
                
                Spacer()
                
                // Footer
                Text("Internal Use Only")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.bottom, 20)
            }
        }
    }
}

// Presentation context provider for ASWebAuthenticationSession
class PresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return UIApplication.shared.windows.first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

