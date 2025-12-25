import Foundation
import UIKit
import Combine

class AutosaveManager: ObservableObject {
    static let shared = AutosaveManager()
    
    private var autosaveTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupBackgroundObserver()
    }
    
    func startAutosave(interval: TimeInterval = 30.0, saveAction: @escaping () -> Void) {
        stopAutosave()
        
        autosaveTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            saveAction()
        }
    }
    
    func stopAutosave() {
        autosaveTimer?.invalidate()
        autosaveTimer = nil
    }
    
    private func setupBackgroundObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }
    
    @objc private func handleAppDidEnterBackground() {
        // Trigger any pending saves before backgrounding
        NotificationCenter.default.post(name: .autosaveRequested, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        stopAutosave()
    }
}

extension Notification.Name {
    static let autosaveRequested = Notification.Name("autosaveRequested")
}

