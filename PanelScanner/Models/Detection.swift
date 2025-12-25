import SwiftUI

struct Detection: Identifiable, Equatable {
    let id = UUID()
    let className: String
    let confidence: Float
    let boundingBox: CGRect  // Normalized 0-1, UIKit coords (top-left origin)
    var text: String?  // OCR result for text_roi or breaker_face
    
    static func == (lhs: Detection, rhs: Detection) -> Bool {
        return lhs.id == rhs.id
    }
    
    var displayText: String {
        if let text = text {
            return "\(className) \(text) (\(Int(confidence * 100))%)"
        }
        return "\(className) (\(Int(confidence * 100))%)"
    }
    
    var color: Color {
        switch className {
        case "panel": return .blue
        case "breaker_face": return .green
        case "text_roi": return .yellow
        case "panel_label": return .red
        default: return .white
        }
    }
}

struct PanelScan: Codable {
    let timestamp: Date
    let panelLabel: String
    let breakers: [BreakerInfo]
    let totalBreakers: Int
}

struct BreakerInfo: Codable {
    let position: CGRect
    let partNumber: String?
    let confidence: Float
}

