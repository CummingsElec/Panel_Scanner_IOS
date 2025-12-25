import SwiftUI
import AVFoundation

struct CameraView: UIViewRepresentable {
    @ObservedObject var viewModel: ScannerViewModel
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        
        // Setup camera preview layer
        let previewLayer = viewModel.cameraService.previewLayer
        // Use .resizeAspect to show full frame without cropping (matches detection coordinates)
        previewLayer.videoGravity = .resizeAspect
        view.layer.addSublayer(previewLayer)
        
        // Start camera
        viewModel.cameraService.startSession()
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Update preview layer frame
        DispatchQueue.main.async {
            if let previewLayer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
                previewLayer.frame = uiView.bounds
            }
        }
    }
}

