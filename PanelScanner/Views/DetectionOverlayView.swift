import SwiftUI
import AVFoundation

struct DetectionOverlayView: View {
    let detections: [Detection]
    let previewLayer: AVCaptureVideoPreviewLayer
    
    var body: some View {
        GeometryReader { geometry in
            ForEach(detections) { detection in
                DetectionBox(
                    detection: detection,
                    viewSize: geometry.size,
                    previewLayer: previewLayer
                )
            }
        }
    }
}

struct DetectionBox: View {
    let detection: Detection
    let viewSize: CGSize
    let previewLayer: AVCaptureVideoPreviewLayer
    
    // SIMPLE: Vision gives normalized coords (0-1) with bottom-left origin
    // Just flip Y and scale to view size
    private func convertCoordinates() -> CGRect {
        let box = detection.boundingBox
        
        // Flip Y (Vision uses bottom-left, SwiftUI uses top-left)
        let x = box.origin.x * viewSize.width
        let y = (1.0 - box.origin.y - box.height) * viewSize.height
        let width = box.width * viewSize.width
        let height = box.height * viewSize.height
        
        // Log for panel labels to diagnose offset
        if detection.className == "panel_label" {
            print("""
            📐 [BBOX] Panel Label:
              Input: x=\(String(format: "%.3f", box.origin.x)), y=\(String(format: "%.3f", box.origin.y)), w=\(String(format: "%.3f", box.width)), h=\(String(format: "%.3f", box.height))
              Output: x=\(String(format: "%.1f", x)), y=\(String(format: "%.1f", y)), w=\(String(format: "%.1f", width)), h=\(String(format: "%.1f", height))
              ViewSize: \(viewSize.width)×\(viewSize.height)
              PreviewBounds: \(previewLayer.bounds.size.width)×\(previewLayer.bounds.size.height)
            """)
        }
        
        return CGRect(x: x, y: y, width: width, height: height)
    }
    
    var body: some View {
        let rect = convertCoordinates()
        
        ZStack(alignment: .topLeading) {
            Rectangle()
                .stroke(detection.color, lineWidth: 2)
                .frame(width: rect.width, height: rect.height)
            
            Text(detection.displayText)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .padding(4)
                .background(detection.color)
                .foregroundColor(.white)
                .offset(y: -24)
        }
        .position(x: rect.midX, y: rect.midY)
    }
}

