import SwiftUI
import ARKit
import RealityKit

/// AR view that displays floating 3D labels for detected breakers
struct AROverlayView: View {
    @ObservedObject var arService: AROverlayService
    @ObservedObject var viewModel: ScannerViewModel
    @State private var showInstructions = true
    
    var body: some View {
        ZStack {
            // AR camera view
            ARViewContainer(arService: arService, viewModel: viewModel)
                .edgesIgnoringSafeArea(.all)
            
            // AR coaching overlay for user guidance
            ARCoachingOverlay(arService: arService)
            
            // Cool instructions overlay
            if showInstructions {
                VStack {
                    Spacer()
                    
                    ARInstructionsCard(
                        detectionCount: arService.currentDetections.count,
                        isTracking: arService.isARActive
                    )
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    
                    Button(action: {
                        withAnimation {
                            showInstructions = false
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(0.7))
                            .padding()
                    }
                }
            }
            
            // AR Status HUD
            VStack {
                HStack {
                    ARStatusBadge(
                        isTracking: arService.isARActive,
                        detectionCount: arService.currentDetections.count,
                        anchorCount: arService.getAllTrackedDetections().count
                    )
                    Spacer()
                }
                .padding()
                Spacer()
            }
        }
        .onAppear {
            // Auto-hide instructions after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                withAnimation {
                    showInstructions = false
                }
            }
        }
    }
}

// MARK: - AR View Container

struct ARViewContainer: UIViewRepresentable {
    let arService: AROverlayService
    let viewModel: ScannerViewModel
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        
        // Configure AR view
        arView.session = arService.arSession
        arView.automaticallyConfigureSession = false
        
        // Enable debug options in debug builds
        #if DEBUG
        arView.debugOptions = [.showFeaturePoints]
        #endif
        
        // Store coordinator for updates
        context.coordinator.arView = arView
        context.coordinator.setupAnchorUpdates()
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        // Update anchors when detections change
        context.coordinator.updateLabels()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(arService: arService, viewModel: viewModel)
    }
    
    // MARK: - Coordinator
    
    class Coordinator {
        let arService: AROverlayService
        let viewModel: ScannerViewModel
        weak var arView: ARView?
        
        // Store entity for each anchor
        private var anchorEntities: [UUID: AnchorEntity] = [:]
        
        init(arService: AROverlayService, viewModel: ScannerViewModel) {
            self.arService = arService
            self.viewModel = viewModel
        }
        
        func setupAnchorUpdates() {
            // Update anchors periodically based on detections
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.updateAnchorsFromDetections()
            }
        }
        
        func updateAnchorsFromDetections() {
            guard let currentFrame = arService.arSession.currentFrame else { return }
            
            // Update AR anchors based on current detections
            arService.updateAnchors(for: viewModel.detections, in: currentFrame)
        }
        
        func updateLabels() {
            guard let arView = arView else { return }
            
            // Get all tracked detections with their anchors
            let trackedItems = arService.getAllTrackedDetections()
            
            // CODEX DEBUG: Log scene state before modification
            let sceneAnchorsBefore = arView.scene.anchors.count
            
            // Update or create entities for each anchor
            for (anchor, detection) in trackedItems {
                if anchorEntities[anchor.identifier] == nil {
                    // Create new label entity
                    print("✨ [AR] Creating textured billboard for: \(detection.className) - '\(detection.text ?? "no text")'")
                    let anchorEntity = createLabelEntity(for: detection, anchor: anchor)
                    arView.scene.addAnchor(anchorEntity)
                    anchorEntities[anchor.identifier] = anchorEntity
                    
                    // CODEX VERIFY: Check anchor was actually added
                    let sceneAnchorsAfter = arView.scene.anchors.count
                    print("✅ [AR] Label added - Scene anchors: \(sceneAnchorsBefore) → \(sceneAnchorsAfter), Total labels: \(anchorEntities.count)")
                    
                    // Verify entity is enabled
                    if let entity = anchorEntity.children.first as? ModelEntity {
                        print("   Entity enabled: \(entity.isEnabled), opacity: \(entity.components[OpacityComponent.self]?.opacity ?? 1.0)")
                    }
                } else {
                    // Update existing entity
                    updateLabelEntity(anchorEntities[anchor.identifier]!, with: detection)
                }
            }
            
            // Clean up entities for removed anchors
            let currentAnchorIDs = Set(trackedItems.map { $0.anchor.identifier })
            let staleEntityIDs = anchorEntities.keys.filter { !currentAnchorIDs.contains($0) }
            
            for id in staleEntityIDs {
                if let entity = anchorEntities[id] {
                    arView.scene.removeAnchor(entity)
                    anchorEntities.removeValue(forKey: id)
                }
            }
        }
        
        private func createLabelEntity(for detection: Detection, anchor: ARAnchor) -> AnchorEntity {
            // Create anchor entity at the AR anchor's position
            let anchorEntity = AnchorEntity(anchor: anchor)
            
            // Create label mesh
            let labelEntity = createFloatingLabel(for: detection)
            anchorEntity.addChild(labelEntity)
            
            return anchorEntity
        }
        
        private func createFloatingLabel(for detection: Detection) -> ModelEntity {
            // CODEX FIX: Use textured billboard instead of 3D text (more reliable!)
            let labelText = getLabelText(for: detection)
            let color = getColorForClass(detection.className)
            
            // Render text to 2D image
            let font = UIFont.boldSystemFont(ofSize: 40)
            let size = CGSize(width: 512, height: 128)
            let renderer = UIGraphicsImageRenderer(size: size)
            
            let image = renderer.image { context in
                // Background with glow
                color.withAlphaComponent(0.8).setFill()
                let bgPath = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 20)
                bgPath.fill()
                
                // Border
                color.setStroke()
                bgPath.lineWidth = 4
                bgPath.stroke()
                
                // Text
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: UIColor.white
                ]
                let textSize = labelText.size(withAttributes: attrs)
                let origin = CGPoint(
                    x: (size.width - textSize.width) / 2,
                    y: (size.height - textSize.height) / 2
                )
                labelText.draw(at: origin, withAttributes: attrs)
            }
            
            // Create texture from image
            guard let texture = try? TextureResource.generate(from: image.cgImage!, options: .init(semantic: .color)) else {
                print("❌ [AR] Failed to create texture")
                return ModelEntity()
            }
            
            // Create material with texture
            var material = UnlitMaterial()
            material.color = .init(texture: .init(texture))
            
            // Create plane mesh
            let plane = MeshResource.generatePlane(width: 0.25, height: 0.08)
            let entity = ModelEntity(mesh: plane, materials: [material])
            
            // Add billboard component (always faces camera)
            entity.components.set(BillboardComponent())
            
            // Ensure visible
            entity.isEnabled = true
            
            print("✨ [AR] Created textured billboard label: \(labelText)")
            
            return entity
        }
        
        
        private func updateLabelEntity(_ anchorEntity: AnchorEntity, with detection: Detection) {
            // Update label if detection info changed (e.g., OCR text updated)
            // For now, we'll keep labels static once created
            // Could add animation or text updates here
        }
        
        // MARK: - Helpers
        
        private func getLabelText(for detection: Detection) -> String {
            if let text = detection.text, !text.isEmpty {
                return "\(detection.className.uppercased())\n\(text)"
            } else {
                return detection.className.uppercased()
            }
        }
        
        private func getColorForClass(_ className: String) -> UIColor {
            switch className {
            case "panel_label", "panel":
                return UIColor(red: 0.0, green: 1.0, blue: 1.0, alpha: 1.0)  // Bright cyan
            case "breaker", "breaker_face":
                return UIColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 1.0)  // Bright orange
            case "text_roi":
                return UIColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 1.0)  // Bright yellow
            default:
                return UIColor(red: 0.3, green: 0.7, blue: 1.0, alpha: 1.0)  // Bright blue (all other detections)
            }
        }
    }
}

// MARK: - AR Coaching Overlay

struct ARCoachingOverlay: UIViewRepresentable {
    let arService: AROverlayService
    
    func makeUIView(context: Context) -> ARCoachingOverlayView {
        let coachingOverlay = ARCoachingOverlayView()
        coachingOverlay.session = arService.arSession
        coachingOverlay.goal = .tracking
        coachingOverlay.activatesAutomatically = true
        return coachingOverlay
    }
    
    func updateUIView(_ uiView: ARCoachingOverlayView, context: Context) {
        // No updates needed
    }
}

// MARK: - Cool AR UI Components

struct ARInstructionsCard: View {
    let detectionCount: Int
    let isTracking: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            // Icon
            Image(systemName: "arkit")
                .font(.system(size: 40))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.cyan, .blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Title
            Text("AR Mode Active")
                .font(.headline)
                .foregroundColor(.white)
            
            // Instructions
            VStack(alignment: .leading, spacing: 8) {
                ARInstructionRow(icon: "camera.viewfinder", text: "Point at electrical panels")
                ARInstructionRow(icon: "cube.transparent", text: "3D labels will appear on detected items")
                ARInstructionRow(icon: "hand.point.up", text: "Move slowly for best tracking")
                
                if detectionCount > 0 {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("\(detectionCount) detection\(detectionCount == 1 ? "" : "s") found!")
                            .foregroundColor(.green)
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                }
            }
            .padding(.top, 4)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                colors: [.cyan.opacity(0.5), .purple.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
        )
        .shadow(color: .purple.opacity(0.3), radius: 20, x: 0, y: 10)
    }
}

struct ARInstructionRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.cyan)
                .frame(width: 20)
            Text(text)
                .font(.caption)
                .foregroundColor(.white.opacity(0.9))
        }
    }
}

struct ARStatusBadge: View {
    let isTracking: Bool
    let detectionCount: Int
    let anchorCount: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isTracking ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(isTracking ? "AR Tracking" : "Initializing...")
                    .font(.caption2)
                    .fontWeight(.semibold)
            }
            
            if detectionCount > 0 || anchorCount > 0 {
                HStack(spacing: 12) {
                    Label("\(detectionCount)", systemImage: "eye")
                    Label("\(anchorCount)", systemImage: "cube")
                }
                .font(.caption2)
            }
        }
        .foregroundColor(.white)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
        )
        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
    }
}

#Preview {
    AROverlayView(
        arService: AROverlayService(),
        viewModel: ScannerViewModel()
    )
}

