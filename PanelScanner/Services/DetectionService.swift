import CoreML
import Vision
import CoreImage
import Combine

class DetectionService: ObservableObject {
    private var model: VNCoreMLModel?
    private var lastInferenceTime: Date = Date()
    private(set) var currentFPS: Double = 0
    
    // Throttling to avoid overwhelming the device
    private var isProcessing = false
    private var isPaused = false  // Manual pause (e.g., during chat)
    private var minTimeBetweenInferences: TimeInterval = 0.1  // Max 10 FPS
    
    // Background queue for inference
    private let inferenceQueue = DispatchQueue(label: "com.panelscanner.inference", qos: .userInitiated)
    
    // Confidence thresholds (adjustable via settings)
    private var confidenceThresholds: [String: Float] = [
        "panel": 0.3,
        "breaker_face": 0.4,
        "text_roi": 0.35,
        "panel_label": 0.4
    ]
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        loadModel()
        
        // Subscribe to settings changes
        SettingsStore.shared.objectWillChange
            .sink { [weak self] _ in
                self?.updateThresholdsFromSettings()
            }
            .store(in: &cancellables)
        
        updateThresholdsFromSettings()
    }
    
    private func updateThresholdsFromSettings() {
        let settings = SettingsStore.shared
        confidenceThresholds = [
            "panel": Float(settings.panelThreshold),
            "breaker_face": Float(settings.breakerThreshold),
            "text_roi": Float(settings.textROIThreshold),
            "panel_label": Float(settings.panelLabelThreshold)
        ]
        minTimeBetweenInferences = 1.0 / settings.maxFPS
        
        print("🎯 DETECTION THRESHOLDS UPDATED:")
        print("  Panel: \(Int(settings.panelThreshold * 100))% | Breaker: \(Int(settings.breakerThreshold * 100))%")
        print("  TextROI: \(Int(settings.textROIThreshold * 100))% | PanelLabel: \(Int(settings.panelLabelThreshold * 100))%")
        print("  Max FPS: \(Int(settings.maxFPS)) (min interval: \(String(format: "%.3f", minTimeBetweenInferences))s)")
    }
    
    private func loadModel() {
        do {
            // Load the CoreML model
            // Xcode automatically generates a Swift class from the .mlpackage file
            let config = MLModelConfiguration()
            config.computeUnits = .all  // Use Neural Engine + GPU + CPU
            
            // Use the auto-generated "best" class
            let mlModel = try best(configuration: config)
            let visionModel = try VNCoreMLModel(for: mlModel.model)
            
            self.model = visionModel
            print("✅ YOLO model loaded successfully")
        } catch {
            print("❌ Failed to load YOLO model: \(error)")
            print("   Make sure best.mlpackage is added to the Xcode project")
        }
    }
    
    func detect(frame: CIImage, completion: @escaping ([Detection]) -> Void) {
        // Skip if paused (e.g., during chat) or already processing
        guard !isPaused, !isProcessing else {
            return
        }
        
        let now = Date()
        let elapsed = now.timeIntervalSince(lastInferenceTime)
        guard elapsed >= minTimeBetweenInferences else {
            return
        }
        
        // Calculate FPS
        currentFPS = 1.0 / elapsed
        lastInferenceTime = now
        
        guard let model = model else {
            // Return empty detections if model not loaded (no more mocks)
            DispatchQueue.main.async {
                completion([])
            }
            return
        }
        
        isProcessing = true
        
        // Run inference on background queue
        inferenceQueue.async { [weak self] in
            guard let self = self else { return }
            
            let request = VNCoreMLRequest(model: model) { [weak self] request, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("⚠️ Detection error: \(error.localizedDescription)")
                    self.isProcessing = false
                    DispatchQueue.main.async {
                        completion([])
                    }
                    return
                }
                
                guard let results = request.results as? [VNRecognizedObjectObservation] else {
                    self.isProcessing = false
                    DispatchQueue.main.async {
                        completion([])
                    }
                    return
                }
                
                let detections = self.processResults(results)
                self.isProcessing = false
                
                DispatchQueue.main.async {
                    completion(detections)
                }
            }
            
            request.imageCropAndScaleOption = .scaleFill
            
            // DON'T set orientation - let Vision process in sensor orientation (landscape)
            // The preview layer will handle rotation, and layerRectConverted will map coordinates
            let handler = VNImageRequestHandler(ciImage: frame, options: [:])
            do {
                try handler.perform([request])
            } catch {
                print("⚠️ Vision request failed: \(error)")
                self.isProcessing = false
                DispatchQueue.main.async {
                    completion([])
                }
            }
        }
    }
    
    private func processResults(_ results: [VNRecognizedObjectObservation]) -> [Detection] {
        return results.compactMap { observation in
            guard let label = observation.labels.first else { return nil }
            
            // Apply confidence threshold
            let threshold = confidenceThresholds[label.identifier] ?? 0.5
            guard label.confidence >= threshold else {
                return nil
            }
            
            // Keep Vision coordinates as-is (normalized 0-1, bottom-left origin)
            // layerRectConverted in overlay will handle the transformation
            let box = observation.boundingBox
            
            return Detection(
                className: label.identifier,
                confidence: label.confidence,
                boundingBox: box,
                text: nil  // OCR added via TrackingService during recording
            )
        }
    }
    
    // Update thresholds dynamically from settings (kept for backwards compatibility)
    func updateThresholds(panel: Float, breaker: Float, textROI: Float, panelLabel: Float, maxFPS: Double) {
        let settings = SettingsStore.shared
        settings.panelThreshold = Double(panel)
        settings.breakerThreshold = Double(breaker)
        settings.textROIThreshold = Double(textROI)
        settings.panelLabelThreshold = Double(panelLabel)
        settings.maxFPS = maxFPS
        #if DEBUG
        print("⚙️ Updated thresholds - Panel: \(panel), Breaker: \(breaker), FPS: \(maxFPS)")
        #endif
    }
    
    // Pause/Resume for freeing resources (e.g., during chat)
    func pauseDetection() {
        isPaused = true
        print("⏸️ [DETECTION] Paused")
    }
    
    func resumeDetection() {
        isPaused = false
        print("▶️ [DETECTION] Resumed")
    }
}

