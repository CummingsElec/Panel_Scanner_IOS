import SwiftUI

@main
struct PanelScannerApp: App {
    @StateObject private var authCoordinator = AuthCoordinator()
    @StateObject private var settingsStore = SettingsStore.shared
    @State private var showSplash = true
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                // Main content
                if authCoordinator.isAuthenticated {
                    MainView()
                        .environmentObject(authCoordinator)
                        .environmentObject(settingsStore)
                } else {
                    LoginView(authCoordinator: authCoordinator)
                        .environmentObject(settingsStore)
                }
                
                // Splash screen overlay
                if showSplash {
                    SplashScreenView {
                        showSplash = false
                    }
                    .transition(.opacity)
                    .zIndex(999)
                }
            }
        }
    }
}
