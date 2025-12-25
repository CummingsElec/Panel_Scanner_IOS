import Foundation
import Combine

class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    
    // Detection thresholds
    @Published var panelThreshold: Double {
        didSet { save() }
    }
    @Published var breakerThreshold: Double {
        didSet { save() }
    }
    @Published var textROIThreshold: Double {
        didSet { save() }
    }
    @Published var panelLabelThreshold: Double {
        didSet { save() }
    }
    @Published var ocrThreshold: Double {
        didSet { save() }
    }
    
    // Tracking parameters
    @Published var dwellFrames: Int {
        didSet { save() }
    }
    @Published var iouTrackThreshold: Double {
        didSet { save() }
    }
    @Published var cooldownFrames: Int {
        didSet { save() }
    }
    
    // Performance
    @Published var maxFPS: Double {
        didSet { save() }
    }
    
    // Build mode flags
    @Published var isLocalModeEnabled: Bool {
        didSet { save() }
    }
    @Published var showDebugOverlay: Bool {
        didSet { save() }
    }
    
    // Video recording
    @Published var enableVideoRecording: Bool {
        didSet { save() }
    }
    
    // Electrical Guru AI (Cloud only - OpenAI or xAI)
    @Published var aiAPIKey: String {
        didSet { save() }
    }
    @Published var aiProvider: String {
        didSet { save() }
    }
    
    private let defaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()
    
    // Keys
    private enum Keys {
        static let panelThreshold = "panelThreshold"
        static let breakerThreshold = "breakerThreshold"
        static let textROIThreshold = "textROIThreshold"
        static let panelLabelThreshold = "panelLabelThreshold"
        static let ocrThreshold = "ocrThreshold"
        static let dwellFrames = "dwellFrames"
        static let iouTrackThreshold = "iouTrackThreshold"
        static let cooldownFrames = "cooldownFrames"
        static let maxFPS = "maxFPS"
        static let isLocalModeEnabled = "isLocalModeEnabled"
        static let showDebugOverlay = "showDebugOverlay"
        static let enableVideoRecording = "enableVideoRecording"
        static let hasLoadedDefaults = "hasLoadedDefaults"
        static let aiAPIKey = "aiAPIKey"
        static let aiProvider = "aiProvider"
    }
    
    private init() {
        // Load saved values or defaults
        if !defaults.bool(forKey: Keys.hasLoadedDefaults) {
            // First launch - load from bundled JSON or use AppConfig defaults
            self.panelThreshold = AppConfig.Detection.defaultPanelThreshold
            self.breakerThreshold = AppConfig.Detection.defaultBreakerThreshold
            self.textROIThreshold = AppConfig.Detection.defaultTextROIThreshold
            self.panelLabelThreshold = AppConfig.Detection.defaultPanelLabelThreshold
            self.ocrThreshold = AppConfig.Detection.defaultOCRThreshold
            self.dwellFrames = AppConfig.Detection.defaultDwellFrames
            self.iouTrackThreshold = AppConfig.Detection.defaultIOUThreshold
            self.cooldownFrames = AppConfig.Detection.defaultCooldownFrames
            self.maxFPS = AppConfig.Detection.defaultMaxFPS
            self.isLocalModeEnabled = AppConfig.Build.localModeDefault
            self.showDebugOverlay = false
            self.enableVideoRecording = true
            self.aiAPIKey = ""
            self.aiProvider = "openai"  // or "xai" for Grok
            
            loadDefaultsFromBundle()
            defaults.set(true, forKey: Keys.hasLoadedDefaults)
            save()
            print("🆕 FIRST LAUNCH - Loaded default settings")
        } else {
            // Load from UserDefaults
            self.panelThreshold = defaults.double(forKey: Keys.panelThreshold)
            self.breakerThreshold = defaults.double(forKey: Keys.breakerThreshold)
            self.textROIThreshold = defaults.double(forKey: Keys.textROIThreshold)
            self.panelLabelThreshold = defaults.double(forKey: Keys.panelLabelThreshold)
            self.ocrThreshold = defaults.double(forKey: Keys.ocrThreshold)
            self.dwellFrames = defaults.integer(forKey: Keys.dwellFrames)
            self.iouTrackThreshold = defaults.double(forKey: Keys.iouTrackThreshold)
            self.cooldownFrames = defaults.integer(forKey: Keys.cooldownFrames)
            self.maxFPS = defaults.double(forKey: Keys.maxFPS)
            self.isLocalModeEnabled = defaults.bool(forKey: Keys.isLocalModeEnabled)
            self.showDebugOverlay = defaults.bool(forKey: Keys.showDebugOverlay)
            self.enableVideoRecording = defaults.bool(forKey: Keys.enableVideoRecording)
            // Clear old corrupt API keys - use plist instead
            self.aiAPIKey = ""  // Force using plist for now
            self.aiProvider = defaults.string(forKey: Keys.aiProvider) ?? "xai"
            
            print("📂 LOADED SAVED SETTINGS:")
            print("  Panel: \(Int(panelThreshold * 100))% | Breaker: \(Int(breakerThreshold * 100))% | OCR: \(Int(ocrThreshold * 100))%")
            print("  Dwell: \(dwellFrames)f | IOU: \(Int(iouTrackThreshold * 100))% | Cooldown: \(cooldownFrames)f | FPS: \(Int(maxFPS))")
        }
    }
    
    private func save() {
        defaults.set(panelThreshold, forKey: Keys.panelThreshold)
        defaults.set(breakerThreshold, forKey: Keys.breakerThreshold)
        defaults.set(textROIThreshold, forKey: Keys.textROIThreshold)
        defaults.set(panelLabelThreshold, forKey: Keys.panelLabelThreshold)
        defaults.set(ocrThreshold, forKey: Keys.ocrThreshold)
        defaults.set(dwellFrames, forKey: Keys.dwellFrames)
        defaults.set(iouTrackThreshold, forKey: Keys.iouTrackThreshold)
        defaults.set(cooldownFrames, forKey: Keys.cooldownFrames)
        defaults.set(maxFPS, forKey: Keys.maxFPS)
        defaults.set(isLocalModeEnabled, forKey: Keys.isLocalModeEnabled)
        defaults.set(showDebugOverlay, forKey: Keys.showDebugOverlay)
        defaults.set(enableVideoRecording, forKey: Keys.enableVideoRecording)
        defaults.set(aiAPIKey, forKey: Keys.aiAPIKey)
        defaults.set(aiProvider, forKey: Keys.aiProvider)
        
        print("💾 SETTINGS SAVED:")
        print("  Panel: \(Int(panelThreshold * 100))% | Breaker: \(Int(breakerThreshold * 100))% | OCR: \(Int(ocrThreshold * 100))%")
        print("  Dwell: \(dwellFrames)f | IOU: \(Int(iouTrackThreshold * 100))% | Cooldown: \(cooldownFrames)f | FPS: \(Int(maxFPS))")
    }
    
    private func loadDefaultsFromBundle() {
        guard let url = Bundle.main.url(forResource: "DefaultSettings", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(DefaultSettingsConfig.self, from: data) else {
            #if DEBUG
            print("⚠️ Could not load DefaultSettings.json, using hardcoded defaults")
            #endif
            return
        }
        
        self.panelThreshold = settings.panelThreshold
        self.breakerThreshold = settings.breakerThreshold
        self.textROIThreshold = settings.textROIThreshold
        self.panelLabelThreshold = settings.panelLabelThreshold
        self.ocrThreshold = settings.ocrThreshold
        self.dwellFrames = settings.dwellFrames
        self.iouTrackThreshold = settings.iouTrackThreshold
        self.cooldownFrames = settings.cooldownFrames
        self.maxFPS = settings.maxFPS
    }
    
    func resetToDefaults() {
        defaults.set(false, forKey: Keys.hasLoadedDefaults)
        
        // Reload defaults from AppConfig
        panelThreshold = AppConfig.Detection.defaultPanelThreshold
        breakerThreshold = AppConfig.Detection.defaultBreakerThreshold
        textROIThreshold = AppConfig.Detection.defaultTextROIThreshold
        panelLabelThreshold = AppConfig.Detection.defaultPanelLabelThreshold
        ocrThreshold = AppConfig.Detection.defaultOCRThreshold
        dwellFrames = AppConfig.Detection.defaultDwellFrames
        iouTrackThreshold = AppConfig.Detection.defaultIOUThreshold
        cooldownFrames = AppConfig.Detection.defaultCooldownFrames
        maxFPS = AppConfig.Detection.defaultMaxFPS
        
        loadDefaultsFromBundle()
        defaults.set(true, forKey: Keys.hasLoadedDefaults)
        save()
    }
    
    var currentEffectiveValues: String {
        """
        Panel: \(Int(panelThreshold * 100))% | Breaker: \(Int(breakerThreshold * 100))%
        OCR: \(Int(ocrThreshold * 100))% | Dwell: \(dwellFrames)f | FPS: \(Int(maxFPS))
        """
    }
}

struct DefaultSettingsConfig: Codable {
    let panelThreshold: Double
    let breakerThreshold: Double
    let textROIThreshold: Double
    let panelLabelThreshold: Double
    let ocrThreshold: Double
    let dwellFrames: Int
    let iouTrackThreshold: Double
    let cooldownFrames: Int
    let maxFPS: Double
}

