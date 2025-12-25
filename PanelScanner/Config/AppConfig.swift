import Foundation

enum AppConfig {
    // OCR Configuration
    enum OCR {
        static let allowedCharacters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-/"
        
        static let partNumberPatterns = [
            "^[A-Z]{3}[0-9]{5,6}$",              // BJA260201, BDA36050
            "^[A-Z]{3}[0-9]{5}[A-Z][0-9]{2}[A-Z]$", // LJA36400U31X
            "^[A-Z]{3}[0-9]{5,6}[A-Z][0-9]$",    // BGA24060Y2
            "^[A-Z]{3}[0-9]{5}[A-Z]$",           // BGA3450Y
            "^[A-Z]{3}-[0-9][A-Z]{2}$",          // HLW-1BL, HNM-4BL
            "^[A-Z]{3}-[0-9]{2}$",               // QOB-20, QOB-40
            "^[0-9]{5}[A-Z]$",                   // 22000A
            "^[A-Z]{6}$",                        // PKDGWG
            "^[A-Z]{2,3}[0-9]{2,5}$",            // Generic: BJA36020, QJA32225
        ]
    }
    
    // Detection Configuration
    enum Detection {
        static let defaultPanelThreshold: Double = 0.3
        static let defaultBreakerThreshold: Double = 0.4
        static let defaultTextROIThreshold: Double = 0.35
        static let defaultPanelLabelThreshold: Double = 0.4
        static let defaultOCRThreshold: Double = 0.7
        
        static let defaultDwellFrames: Int = 5
        static let defaultIOUThreshold: Double = 0.5
        static let defaultCooldownFrames: Int = 30
        static let defaultMaxFPS: Double = 10.0
    }
    
    // Export Configuration
    enum Export {
        static let autosaveInterval: TimeInterval = 30.0
        static let dateFormat = "yyyyMMdd-HHmmss"
        static let unsetPanelName = "UNSET"
    }
    
    // Logging
    enum Logging {
        #if DEBUG
        static let isVerbose = true
        #else
        static let isVerbose = false
        #endif
    }
    
    // Build Configuration
    enum Build {
        #if DEBUG
        static let isDebug = true
        static let showDebugMenu = true
        #else
        static let isDebug = false
        static let showDebugMenu = false
        #endif
        
        // Can be overridden by build settings
        static var localModeDefault: Bool {
            #if DEBUG
            return true
            #else
            return false
            #endif
        }
    }
}

