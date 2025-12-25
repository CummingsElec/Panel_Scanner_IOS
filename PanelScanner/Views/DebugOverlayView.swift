import SwiftUI

struct DebugOverlayView: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var viewModel: ScannerViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DEBUG")
                .font(.system(.caption2, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(.yellow)
            
            Divider()
                .background(Color.yellow)
            
            Group {
                debugRow(label: "Panel", value: "\(Int(settingsStore.panelThreshold * 100))%")
                debugRow(label: "Breaker", value: "\(Int(settingsStore.breakerThreshold * 100))%")
                debugRow(label: "OCR", value: "\(Int(settingsStore.ocrThreshold * 100))%")
                debugRow(label: "Dwell", value: "\(settingsStore.dwellFrames)f")
                debugRow(label: "FPS", value: String(format: "%.1f", viewModel.fps))
                debugRow(label: "IOU", value: "\(Int(settingsStore.iouTrackThreshold * 100))%")
                debugRow(label: "Cool", value: "\(settingsStore.cooldownFrames)f")
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.7))
        .cornerRadius(8)
        .font(.system(.caption2, design: .monospaced))
    }
    
    private func debugRow(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label + ":")
                .foregroundColor(.gray)
            Text(value)
                .foregroundColor(.white)
        }
    }
}

