import ARKit
import RealityKit
import SwiftUI
import Combine

/// Manages AR session and anchors for floating breaker labels
class AROverlayService: NSObject, ObservableObject {
    @Published var isARActive = false
    @Published var arSession = ARSession()
    @Published var currentDetections: [Detection] = []  // Latest YOLO detections from AR frames
    
    // Store anchors for each tracked detection
    private var detectionAnchors: [UUID: ARAnchor] = [:]
    private var anchorToDetection: [UUID: Detection] = [:]
    
    // AR configuration
    private var arConfig = ARWorldTrackingConfiguration()
    
    // Reference to detection service to get latest detections
    weak var detectionService: DetectionService?
    
    override init() {
        super.init()
        arSession.delegate = self
        setupARConfiguration()
    }
    
    private func setupARConfiguration() {
        arConfig.planeDetection = [.vertical] // Detect walls where panels are
        arConfig.environmentTexturing = .automatic
        
        // Enable people occlusion if supported (for cool effect)
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            arConfig.frameSemantics.insert(.personSegmentationWithDepth)
        }
    }
    
    // MARK: - AR Session Control
    
    func startAR() {
        guard !isARActive else { 
            print("🥽 [AR] Already active")
            return 
        }
        
        print("🥽 [AR] Starting AR session...")
        print("🥽 [AR] Config: Plane detection: \(arConfig.planeDetection), Frame semantics: \(arConfig.frameSemantics)")
        arSession.run(arConfig, options: [.resetTracking, .removeExistingAnchors])
        isARActive = true
        print("✅ [AR] Session started")
    }
    
    func pauseAR() {
        guard isARActive else { return }
        
        print("🥽 [AR] Pausing AR session...")
        arSession.pause()
        isARActive = false
        
        // Clear all anchors
        clearAllAnchors()
    }
    
    // MARK: - Anchor Management
    
    /// Update AR anchors based on current detections
    func updateAnchors(for detections: [Detection], in frame: ARFrame) {
        guard isARActive else { 
            if !detections.isEmpty {
                print("⚠️ [AR] Skipping \(detections.count) detections - AR not active")
            }
            return 
        }
        
        if !detections.isEmpty && detectionAnchors.isEmpty {
            print("✨ [AR] Processing \(detections.count) detections for anchors...")
        }
        
        // Get camera transform
        let cameraTransform = frame.camera.transform
        
        for detection in detections {
            // Skip if we already have an anchor for this detection
            // (we identify by bbox center position stability)
            if shouldUpdateAnchor(for: detection) {
                createOrUpdateAnchor(for: detection, cameraTransform: cameraTransform)
            }
        }
        
        // Clean up old anchors for detections that disappeared
        cleanupStaleAnchors(currentDetections: detections)
    }
    
    private func shouldUpdateAnchor(for detection: Detection) -> Bool {
        // If no existing anchor for this ID, we should create one
        if detectionAnchors[detection.id] == nil {
            return true
        }
        
        // Otherwise, anchor is stable - don't recreate
        return false
    }
    
    private func createOrUpdateAnchor(for detection: Detection, cameraTransform: simd_float4x4) {
        // CODEX FIX: Better anchor placement to ensure in frustum
        // Convert 2D detection to 3D position
        // Clamp offsets to ±0.4 to keep in view at 1.2m distance
        let normalizedX = (detection.boundingBox.midX / UIScreen.main.bounds.width) - 0.5
        let normalizedY = (detection.boundingBox.midY / UIScreen.main.bounds.height) - 0.5
        
        // Clamp to frustum bounds (Codex recommendation)
        let clampedX = max(-0.4, min(0.4, normalizedX * 0.8))
        let clampedY = max(-0.4, min(0.4, -normalizedY * 0.8))  // Flip Y
        
        // Create translation relative to camera
        var translation = matrix_identity_float4x4
        translation.columns.3.x = Float(clampedX)
        translation.columns.3.y = Float(clampedY)
        translation.columns.3.z = -1.2 // 1.2 meters forward
        
        // Combine with camera transform
        let anchorTransform = matrix_multiply(cameraTransform, translation)
        
        // Create anchor with world transform
        let anchor = ARAnchor(name: detection.id.uuidString, transform: anchorTransform)
        
        // Remove old anchor if exists
        if let oldAnchor = detectionAnchors[detection.id] {
            arSession.remove(anchor: oldAnchor)
        }
        
        // Add new anchor
        arSession.add(anchor: anchor)
        detectionAnchors[detection.id] = anchor
        anchorToDetection[anchor.identifier] = detection
        
        print("🥽 [AR] Anchor created for \(detection.className) at (\(clampedX), \(clampedY), -1.2)")
    }
    
    private func cleanupStaleAnchors(currentDetections: [Detection]) {
        let currentIDs = Set(currentDetections.map { $0.id })
        
        // Find anchors for detections that no longer exist
        let staleIDs = detectionAnchors.keys.filter { !currentIDs.contains($0) }
        
        for id in staleIDs {
            if let anchor = detectionAnchors[id] {
                arSession.remove(anchor: anchor)
                detectionAnchors.removeValue(forKey: id)
                anchorToDetection.removeValue(forKey: anchor.identifier)
            }
        }
    }
    
    private func clearAllAnchors() {
        for anchor in detectionAnchors.values {
            arSession.remove(anchor: anchor)
        }
        detectionAnchors.removeAll()
        anchorToDetection.removeAll()
    }
    
    // MARK: - Public Getters
    
    func getDetection(for anchor: ARAnchor) -> Detection? {
        return anchorToDetection[anchor.identifier]
    }
    
    func getAllTrackedDetections() -> [(anchor: ARAnchor, detection: Detection)] {
        return detectionAnchors.compactMap { (id, anchor) in
            guard let detection = anchorToDetection[anchor.identifier] else { return nil }
            return (anchor, detection)
        }
    }
    
    deinit {
        arSession.pause()
        print("🥽 [AR] AROverlayService deallocated")
    }
}

// MARK: - ARSessionDelegate

extension AROverlayService: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Feed AR camera frames to YOLO detection
        guard isARActive else { return }
        
        // CODEX CHECK: Log tracking state for debugging
        let trackingState = frame.camera.trackingState
        switch trackingState {
        case .normal:
            break // All good
        case .limited(let reason):
            print("⚠️ [AR] Limited tracking: \(reason)")
        case .notAvailable:
            print("❌ [AR] Tracking not available")
        }
        
        // Extract CIImage from AR frame
        let pixelBuffer = frame.capturedImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // Send to detection service if available
        detectionService?.detect(frame: ciImage) { [weak self] detections in
            guard let self = self else { return }
            
            // Publish detections on main thread
            DispatchQueue.main.async {
                self.currentDetections = detections
            }
            
            // Update anchors with new detections
            self.updateAnchors(for: detections, in: frame)
        }
    }
    
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        print("🥽 [AR] Added \(anchors.count) anchors")
    }
    
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        // Anchors updated by ARKit tracking
    }
    
    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        print("🥽 [AR] Removed \(anchors.count) anchors")
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        print("❌ [AR] Session failed: \(error.localizedDescription)")
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        print("⚠️ [AR] Session interrupted")
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        print("✅ [AR] Session interruption ended")
    }
}

