import SwiftUI
import CoreGraphics

/// Represents a pending OCR result that requires user confirmation
struct PendingOCRConfirmation: Identifiable {
    let id = UUID()
    let trackID: String
    let text: String
    let confidence: Float
    let boundingBox: CGRect  // Normalized coordinates
    let className: String  // "breaker_face" or "panel_label"
    let timestamp: Date
    
    var displayColor: Color {
        className == "panel_label" ? .red : .green
    }
    
    var displayTitle: String {
        className == "panel_label" ? "Panel Label" : "Breaker"
    }
}

