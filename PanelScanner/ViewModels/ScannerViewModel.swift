import SwiftUI
import Combine
import CoreMedia

class ScannerViewModel: ObservableObject {
    @Published var detections: [Detection] = []
    @Published var fps: Double = 0
    @Published var breakerCount: Int = 0
    @Published var panelLabel: String = "---"
    @Published var isRecording: Bool = false
    @Published var hasDetections: Bool = false
    @Published var recordedFrameCount: Int = 0
    @Published var uniqueBreakerCount: Int = 0
    @Published var cumulativeBreakerCount: Int = 0  // Total breakers captured across all recordings
    @Published var isPanelLabelMode: Bool = true  // Panel label only mode for production (DEFAULT)
    @Published var isBusy: Bool = false  // Block recording during save/ZIP creation
    @Published var isARMode: Bool = false  // AR overlay mode toggle
    
    let cameraService: CameraService
    let detectionService: DetectionService
    let trackingService: TrackingService
    let oneDriveService: OneDriveService
    let arService: AROverlayService  // AR overlay service
    private let autosaveManager = AutosaveManager.shared
    private let videoRecordingService = VideoRecordingService()
    
    private var cancellables = Set<AnyCancellable>()
    private var recordedDetections: [[Detection]] = []
    private var uniqueBreakers: Set<String> = []  // Track unique breakers per recording
    private var cumulativeBreakers: Set<String> = []  // Track all unique breakers across session
    var currentVideoURL: URL?  // Not private - needed for video polling in MainView
    
    // V3 FIX: Store observer tokens for proper cleanup
    private var autosaveObserver: NSObjectProtocol?
    private var videoFrameObserver: NSObjectProtocol?
    
    init() {
        self.cameraService = CameraService()
        self.detectionService = DetectionService()
        self.trackingService = TrackingService()
        self.oneDriveService = OneDriveService()
        self.arService = AROverlayService()
        
        // Default to panel mode
        self.trackingService.isPanelLabelMode = true
        
        // Link AR service to detection service
        self.arService.detectionService = self.detectionService
        
        setupBindings()
        setupAutosave()
        setupBackgroundHandling()
    }
    
    // V3 FIX: Handle video finalization on background
    private func setupBackgroundHandling() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.isRecording else { return }
            print("📱 [V3-VM] App backgrounded while recording - video will auto-finalize")
            // VideoRecordingService will finalize automatically
            // Update our state to reflect recording stopped
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if self.isRecording {
                    print("📱 [V3-VM] Updating UI state - recording stopped by background")
                    self.isRecording = false
                    self.cameraService.shouldPostVideoFrames = false
                }
            }
        }
    }
    
    deinit {
        // V3 FIX: Properly clean up all resources
        autosaveManager.stopAutosave()
        
        // V3 FIX: Ensure video frame notifications are disabled
        cameraService.shouldPostVideoFrames = false
        
        // Remove NotificationCenter observers
        if let observer = autosaveObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = videoFrameObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        
        // Cancel all Combine subscriptions
        cancellables.removeAll()
        
        print("🔄 [V3] ScannerViewModel deallocated - all observers cleaned up")
    }
    
    private func setupBindings() {
        // Camera frames -> Detection
        cameraService.$currentFrame
            .compactMap { $0 }
            .sink { [weak self] frame in
                self?.processFrame(frame)
            }
            .store(in: &cancellables)
        
        // Subscribe to enriched detections from tracking service (includes OCR)
        trackingService.$enrichedDetections
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enriched in
                guard let self = self else { return }
                
                // Update display with OCR-enriched detections
                self.detections = enriched
                
                // If recording, capture these enriched detections
                if self.isRecording {
                    self.recordedDetections.append(enriched)
                    self.recordedFrameCount = self.recordedDetections.count
                    self.trackUniqueBreakers(enriched)
                }
            }
            .store(in: &cancellables)
        
        // Update stats from detections
        $detections
            .sink { [weak self] detections in
                self?.updateStats(detections)
            }
            .store(in: &cancellables)
        
        // Subscribe to SessionManager's captured breakers for cumulative count
        trackingService.sessionManager.$capturedBreakers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] breakers in
                self?.cumulativeBreakerCount = breakers.count
            }
            .store(in: &cancellables)
        
        // CRITICAL: Subscribe to panel label changes from SessionManager
        // This ensures panelLabel updates IMMEDIATELY when user confirms
        trackingService.sessionManager.$panelPartNumber
            .receive(on: DispatchQueue.main)
            .sink { [weak self] confirmedLabel in
                // CODEX FIX: Clear panelLabel when sessionManager resets (panelPartNumber = nil)
                if let label = confirmedLabel, !label.isEmpty {
                    self?.panelLabel = label
                    print("🏷️ [VM] Panel label updated: \(label)")
                } else {
                    // SessionManager was reset - clear our copy too
                    self?.panelLabel = "---"
                    print("🏷️ [VM] Panel label cleared (session reset)")
                }
            }
            .store(in: &cancellables)
    }
    
    private func processFrame(_ frame: CIImage) {
        detectionService.detect(frame: frame) { [weak self] rawDetections in
            guard let self = self else { return }
            
            // ALWAYS run through tracking pipeline (async OCR, dwell, dedup)
            self.trackingService.processDetections(rawDetections, frame: frame) {
                // Completion callback (if needed for future work)
            }
        }
    }
    
    private func updateStats(_ detections: [Detection]) {
        // Count breakers
        breakerCount = detections.filter { $0.className == "breaker_face" }.count
        
        // Get panel label from SessionManager (more authoritative than detections)
        if let confirmedLabel = trackingService.sessionManager.panelPartNumber {
            panelLabel = confirmedLabel
        } else if let panel = detections.first(where: { $0.className == "panel_label" }) {
            panelLabel = panel.text ?? "Detected"
        } else {
            panelLabel = "---"
        }
        
        hasDetections = !detections.isEmpty
        
        // Update FPS
        fps = detectionService.currentFPS
    }
    
    func toggleRecording() {
        isRecording.toggle()
        
        // Sync mode flag to TrackingService for hands-free panel operation
        trackingService.isPanelLabelMode = isPanelLabelMode
        
        // Set sessionManager.isRecording for full mode prompts
        trackingService.sessionManager.isRecording = isRecording
        
        if isPanelLabelMode {
            print("🏷️ [PANEL MODE] Recording: \(isRecording ? "STARTED" : "STOPPED") - prompts for panel labels only")
        } else {
            print("🔍 [FULL MODE] Recording: \(isRecording ? "STARTED" : "STOPPED") - prompts for all detections")
        }
        
        if isRecording {
            recordedDetections = []
            uniqueBreakers = []
            recordedFrameCount = 0
            uniqueBreakerCount = 0
            
            // V3 FIX: Enable video frame notifications only when recording
            cameraService.shouldPostVideoFrames = true
            
            // Clear any previously auto-captured panel labels so they prompt again
            if isPanelLabelMode {
                print("🏷️ PANEL LABEL MODE - RECORDING STARTED - clearing previous captures")
                trackingService.resetSession()  // Clear tracks and spatial registry
            } else {
                print("🔴 FULL MODE - RECORDING STARTED")
            }
            
            // Start video recording (always in panel label mode, or if enabled in settings)
            if isPanelLabelMode || SettingsStore.shared.enableVideoRecording {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyyMMdd-HHmmss"
                let timestamp = dateFormatter.string(from: Date())
                
                // Sanitize panel label for filename
                let rawLabel = panelLabel.isEmpty ? "UNSET" : panelLabel
                let sanitizedLabel = sanitizeFilename(rawLabel)
                let filename = "\(sanitizedLabel)__\(timestamp).mp4"
                
                if let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    let scansDir = documentsDir.appendingPathComponent("Scans")
                    try? FileManager.default.createDirectory(at: scansDir, withIntermediateDirectories: true)
                    currentVideoURL = scansDir.appendingPathComponent(filename)
                    
                    // Use actual camera dimensions for proper video aspect ratio
                    let frameSize = cameraService.videoDimensions
                    if let videoURL = currentVideoURL {
                        print("""
                        🎥 [START] Initiating video recording:
                          Camera dimensions: \(frameSize.width)×\(frameSize.height)
                          Output: \(videoURL.lastPathComponent)
                          Mode: \(isPanelLabelMode ? "Panel" : "Full")
                        """)
                        let success = videoRecordingService.startRecording(outputURL: videoURL, frameSize: frameSize)
                        
                        // V3 FIX: Handle recording start failure
                        if !success {
                            print("❌ [V3] Video recording failed to start - reverting UI state")
                            // Revert recording state
                            isRecording = false
                            cameraService.shouldPostVideoFrames = false
                            currentVideoURL = nil
                            
                            // TODO: Show error alert to user
                            // For now, just log the error
                            print("⚠️ [V3] Recording disabled - video writer initialization failed")
                            return
                        }
                        print("✅ [V3] Video recording started successfully")
                    }
                }
            } else {
                print("ℹ️ Video recording disabled in settings")
            }
            
            // Start autosave
            autosaveManager.startAutosave { [weak self] in
                self?.performAutosave()
            }
        } else {
            print("⏹️ RECORDING STOPPED - Total frames: \(recordedFrameCount), Unique breakers: \(uniqueBreakerCount)")
            
            // V3 FIX: Disable video frame notifications when not recording
            cameraService.shouldPostVideoFrames = false
            
            // Stop video recording if it was started
            // DON'T clear currentVideoURL here - it's needed for export
            if currentVideoURL != nil {
                videoRecordingService.stopRecording { [weak self] url in
                    if url != nil {
                        print("✅ Video recording finalized")
                    } else {
                        print("⚠️ Video recording failed to finalize")
                        // Clear the URL if video failed
                        DispatchQueue.main.async {
                            self?.currentVideoURL = nil
                        }
                    }
                }
            }
            
            // Stop autosave and perform final save
            autosaveManager.stopAutosave()
            performAutosave()
            
            // DON'T reset session here - it wipes data before save!
            // Reset will happen after successful save
        }
    }
    
    private func setupAutosave() {
        // V3 FIX: Store observer tokens for proper cleanup in deinit
        autosaveObserver = NotificationCenter.default.addObserver(
            forName: .autosaveRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.performAutosave()
        }
        
        // Subscribe to video frames for recording
        videoFrameObserver = NotificationCenter.default.addObserver(
            forName: .videoFrameCaptured,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            // Extract CMSampleBuffer from NSValue wrapper
            guard let nsValue = notification.userInfo?["sampleBuffer"] as? NSValue else { 
                print("⚠️ Failed to extract NSValue from notification")
                return 
            }
            
            guard let pointer = nsValue.pointerValue else {
                print("⚠️ NSValue pointerValue was nil")
                return
            }
            
            // Take retained value and balance the passRetained from CameraService
            let sampleBuffer = Unmanaged<CMSampleBuffer>.fromOpaque(pointer).takeRetainedValue()
            
            // FIX: Only record if we're actually recording (prevents processing frames when stopped)
            if self?.isRecording == true {
                self?.videoRecordingService.recordFrame(sampleBuffer: sampleBuffer)
            }
            // Buffer is released here automatically via takeRetainedValue
        }
    }
    
    private func performAutosave() {
        guard isRecording, !recordedDetections.isEmpty else { return }
        
        // CODEX FIX #2: Use sessionManager value at autosave time
        let confirmedLabel = trackingService.sessionManager.panelPartNumber ?? panelLabel
        print("💾 AUTOSAVE TRIGGERED - Saving \(recordedDetections.count) frames, panel: '\(confirmedLabel)'")
        oneDriveService.saveCurrentSession(detections: recordedDetections, panelLabel: confirmedLabel)
    }
    
    func saveAndShare(completion: @escaping (URL?) -> Void) {
        print("💾 SAVE & SHARE - Video URL: \(currentVideoURL?.lastPathComponent ?? "none")")
        
        // V3 FIX: Ensure video frames aren't posting during save
        cameraService.shouldPostVideoFrames = false
        
        // Block new recordings during save/ZIP
        isBusy = true
        
        // Determine what data to save
        // If we have recorded data, use that even if recording just stopped
        let dataToSave: [[Detection]]
        if !recordedDetections.isEmpty {
            dataToSave = recordedDetections
            print("ℹ️ Saving recorded session: \(recordedDetections.count) frames")
        } else if !detections.isEmpty {
            // Fallback: Use current frame if recording was stopped too quickly
            dataToSave = [detections]
            print("⚠️ Recording stopped before frames captured - using current frame (\(detections.count) detections)")
        } else {
            // CRITICAL: Check SessionManager for confirmed panel at least
            // Even if no detections, save the confirmed panel label
            if let confirmedPanel = trackingService.sessionManager.panelPartNumber, !confirmedPanel.isEmpty {
                print("ℹ️ No frames but have confirmed panel label '\(confirmedPanel)' - saving anyway")
                dataToSave = []  // Empty but will save panel label
            } else {
                print("⚠️ No data to save (no frames, no panel label)")
                completion(nil)
                isBusy = false
                return
            }
        }
        
        // CODEX FIX #2: Use sessionManager.panelPartNumber directly at save time (not stale panelLabel)
        let confirmedLabel = trackingService.sessionManager.panelPartNumber ?? panelLabel
        print("💾 [SAVE] Using panel label: '\(confirmedLabel)' (from SessionManager: \(trackingService.sessionManager.panelPartNumber ?? "nil"))")
        
        // Save and wait for completion before returning URL
        oneDriveService.uploadScan(
            detections: dataToSave,
            panelLabel: confirmedLabel,  // Use fresh value, not reactive copy
            videoURL: currentVideoURL,
            sessionManager: trackingService.sessionManager  // Use confirmed captures, not raw detections
        ) { [weak self] url in
            guard let self = self else { return }
            
            // Clear video URL after save completes (success or failure)
            DispatchQueue.main.async {
                self.currentVideoURL = nil
            }
            
            guard let url = url else {
                print("❌ Save failed - no URL returned")
                DispatchQueue.main.async {
                    self.isBusy = false  // Unblock UI
                }
                completion(nil)
                return
            }
            
            // Verify file exists and is accessible
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: url.path) {
                print("✅ File exists at: \(url.path)")
                
                // Check if readable
                if fileManager.isReadableFile(atPath: url.path) {
                    print("✅ File is readable")
                } else {
                    print("⚠️ File exists but is not readable")
                }
            } else {
                print("❌ File does not exist at path: \(url.path)")
            }
            
            print("✅ Saved and ready to share: \(url.lastPathComponent)")
            
            // DON'T reset session here - wait until AFTER share sheet completes
            // isBusy will be cleared after share sheet dismisses
            completion(url)
        }
    }
    
    private func trackUniqueBreakers(_ detections: [Detection]) {
        for detection in detections where detection.className == "breaker_face" {
            // Create a unique ID based on position (rounded to avoid duplicates from slight movement)
            let x = Int(detection.boundingBox.origin.x * 100)
            let y = Int(detection.boundingBox.origin.y * 100)
            let id = "\(x),\(y)"
            uniqueBreakers.insert(id)
            cumulativeBreakers.insert(id)
        }
        uniqueBreakerCount = uniqueBreakers.count
        cumulativeBreakerCount = cumulativeBreakers.count
    }
    
    func resetCumulativeCount() {
        cumulativeBreakers.removeAll()
        cumulativeBreakerCount = 0
    }
    
    private func sanitizeFilename(_ name: String) -> String {
        var sanitized = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "*", with: "-")
            .replacingOccurrences(of: "?", with: "-")
            .replacingOccurrences(of: "\"", with: "-")
            .replacingOccurrences(of: "<", with: "-")
            .replacingOccurrences(of: ">", with: "-")
            .replacingOccurrences(of: "|", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        if sanitized.count > 50 {
            sanitized = String(sanitized.prefix(50))
        }
        
        return sanitized.isEmpty ? "UNSET" : sanitized
    }
}

