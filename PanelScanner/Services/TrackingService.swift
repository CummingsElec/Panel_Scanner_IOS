import CoreImage
import UIKit
import Combine

class TrackingService: ObservableObject {
    @Published var activeTracks: [TrackState] = []
    @Published var debugInfo: DebugInfo = DebugInfo()
    @Published var pendingConfirmation: PendingOCRConfirmation?
    
    // FIX: Panel mode flag for hands-free operation
    var isPanelLabelMode: Bool = false
    
    private var tracks: [String: TrackState] = [:]
    private var capturedItems: [String: [CGPoint]] = [:]  // FIX: Spatial registry
    private var currentlyPrompting: Set<String> = []  // FIX: Track texts currently showing prompts
    private var frameNumber: Int = 0
    
    private let ocrService = OCRService()
    let sessionManager: SessionManager  // Made internal for access from ViewModel
    private let trackingQueue = DispatchQueue(label: "com.panelscanner.tracking", qos: .userInitiated)  // FIX: Serial queue
    private let ocrQueue: OperationQueue = {  // FIX: Limit OCR concurrency
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 2
        queue.qualityOfService = .userInitiated
        return queue
    }()
    
    // V3 FIX: Timer to cleanup expired confirmations even when frames stop
    private var timeoutTimer: Timer?
    
    // Published enriched detections for live display
    @Published public private(set) var enrichedDetections: [Detection] = []
    
    // Settings (loaded from UserDefaults)
    var detectorThreshold: Float = 0.85
    var ocrThreshold: Float = 0.90
    var dwellFrames: Int = 5
    var iouTrackThreshold: Float = 0.5
    var cooldownFrames: Int = 30
    var fuzzyThreshold: Int = 2  // Levenshtein distance
    var confirmationTimeoutSeconds: TimeInterval = 30.0  // Auto-expire pending confirmations after 30s
    
    init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
        loadSettings()
        startTimeoutTimer()
    }
    
    // Convenience init for use without SessionManager
    convenience init() {
        self.init(sessionManager: SessionManager())
    }
    
    deinit {
        stopTimeoutTimer()
    }
    
    // V3 FIX: Start timer to check for expired confirmations every 5 seconds
    private func startTimeoutTimer() {
        stopTimeoutTimer()
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkTimeoutOnTimer()
        }
    }
    
    private func stopTimeoutTimer() {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
    }
    
    // V3 FIX: Check timeout even when frames aren't flowing
    private func checkTimeoutOnTimer() {
        trackingQueue.async { [weak self] in
            self?.checkForExpiredConfirmations()
        }
    }
    
    func processDetections(_ detections: [Detection], frame: CIImage, completion: @escaping () -> Void) {
        // FIX: All state mutations on serial queue
        trackingQueue.async { [weak self] in
            guard let self = self else { return }
            
            // First, spatially associate text_roi with breakers and publish for display
            let spatiallyEnriched = self.associateTextWithBreakers(detections, frame: frame)
            DispatchQueue.main.async {
                self.enrichedDetections = spatiallyEnriched
            }
            
            self.frameNumber += 1
            let currentFrame = self.frameNumber
            
            // Match detections to existing tracks
            var matchedTrackIDs: Set<String> = []
            
            for detection in detections {
                // Skip if low confidence
                let threshold = detection.className == "panel_label" ? 0.85 : self.detectorThreshold
                guard detection.confidence >= threshold else { continue }
                
                // Find matching track
                if let matchedTrack = self.findMatchingTrack(for: detection) {
                    matchedTrack.update(bbox: detection.boundingBox, confidence: detection.confidence, frameNumber: currentFrame)
                    matchedTrackIDs.insert(matchedTrack.id)
                    
                    // Check if should process OCR
                    // Only run OCR on text_roi and panel_label (not breaker_face)
                    let shouldRunOCR = (detection.className == "text_roi" || detection.className == "panel_label")
                    
                    // FIX: Don't run OCR if already awaiting user confirmation
                    // CRITICAL: Use 'continue' instead of 'return' to avoid dropping other detections
                    if matchedTrack.pendingFrame != nil {
                        // Track is waiting for user to confirm/ignore - don't create duplicate prompts
                        // (Prevents multiple confirmations for same detection)
                        continue  // Skip THIS track only, process other detections
                    }
                    
                    if !matchedTrack.isCaptured && matchedTrack.cooldownFrames == 0 && shouldRunOCR {
                        // Panel labels get faster OCR (2 frame dwell)
                        let isPanelLabel = detection.className == "panel_label"
                        
                        if isPanelLabel {
                            // Panel labels need SOME dwell for stable OCR (not instant!)
                            matchedTrack.incrementDwell()
                            
                            // Short dwell for panel labels (2 frames instead of 5)
                            if matchedTrack.dwellCount >= 2 {
                                let timestamp = Date()
                                matchedTrack.lastOCRStartTime = timestamp
                                self.processOCR(for: matchedTrack, detection: detection, frame: frame)
                            }
                        } else {
                            // Breakers require dwell time
                            matchedTrack.incrementDwell()
                            
                            if matchedTrack.dwellCount >= self.dwellFrames {
                                self.processOCR(for: matchedTrack, detection: detection, frame: frame)
                            }
                        }
                    }
                } else {
                    // Create new track
                    let trackID = UUID().uuidString
                    let newTrack = TrackState(
                        id: trackID,
                        bbox: detection.boundingBox,
                        className: detection.className,
                        confidence: detection.confidence
                    )
                    newTrack.lastSeenFrame = currentFrame
                    self.tracks[trackID] = newTrack
                    matchedTrackIDs.insert(trackID)
                }
            }
            
            // V3 FIX: Remove stale tracks (including those with expired pending frames)
            let staleThreshold = 30
            self.tracks = self.tracks.filter { _, track in
                let isRecentlySeen = (currentFrame - track.lastSeenFrame) < staleThreshold
                
                // If track has pending frame, check if it's expired
                if let _ = track.pendingFrame {
                    // Check if there's a matching pending confirmation
                    if let pending = self.pendingConfirmation, pending.trackID == track.id {
                        let age = Date().timeIntervalSince(pending.timestamp)
                        // Keep track only if confirmation hasn't expired
                        return isRecentlySeen || age < self.confirmationTimeoutSeconds
                    } else {
                        // No matching confirmation but has pending frame - clean it up
                        track.pendingFrame = nil
                        return isRecentlySeen
                    }
                }
                
                return isRecentlySeen
            }
            
            // Decrement cooldowns
            for track in self.tracks.values {
                track.decrementCooldown()
            }
            
            // Temporal NMS
            self.performTemporalNMS()
            
            // V3 FIX: Check for expired pending confirmations and auto-cleanup
            self.checkForExpiredConfirmations()
            
            // FIX: Update published properties on main thread
            DispatchQueue.main.async {
                self.activeTracks = Array(self.tracks.values)
                self.debugInfo.frameNumber = currentFrame
                self.debugInfo.activeTrackCount = self.tracks.count
                completion()
            }
        }
    }
    
    private func findMatchingTrack(for detection: Detection) -> TrackState? {
        var bestMatch: TrackState?
        var bestIOU: Float = iouTrackThreshold
        
        // Panel labels: Use center-based matching to handle bbox shifts
        // YOLO bbox can drift left/right when distance changes, but center stays stable
        if detection.className == "panel_label" {
            let detectionCenter = CGPoint(
                x: detection.boundingBox.midX,
                y: detection.boundingBox.midY
            )
            
            var bestDistance: CGFloat = 0.15  // 15% of frame
            
            for track in tracks.values {
                guard track.className == "panel_label" else { continue }
                
                let trackCenter = CGPoint(x: track.bbox.midX, y: track.bbox.midY)
                let dx = detectionCenter.x - trackCenter.x
                let dy = detectionCenter.y - trackCenter.y
                let distance = sqrt(dx * dx + dy * dy)
                
                if distance < bestDistance {
                    bestDistance = distance
                    bestMatch = track
                }
            }
            
            return bestMatch
        }
        
        // Breakers/text_roi: Use standard IOU matching
        for track in tracks.values {
            guard track.className == detection.className else { continue }
            
            let iou = calculateIOU(track.bbox, detection.boundingBox)
            if iou > bestIOU {
                bestIOU = iou
                bestMatch = track
            }
        }
        
        return bestMatch
    }
    
    private func calculateIOU(_ rect1: CGRect, _ rect2: CGRect) -> Float {
        let intersection = rect1.intersection(rect2)
        
        guard !intersection.isNull else { return 0.0 }
        
        let intersectionArea = intersection.width * intersection.height
        let unionArea = (rect1.width * rect1.height) + (rect2.width * rect2.height) - intersectionArea
        
        return Float(intersectionArea / unionArea)
    }
    
    private func processOCR(for track: TrackState, detection: Detection, frame: CIImage) {
        // FIX: Convert UIKit coords back to Vision coords for cropping
        let visionBBox = CGRect(
            x: detection.boundingBox.origin.x,
            y: 1 - detection.boundingBox.origin.y - detection.boundingBox.height,
            width: detection.boundingBox.width,
            height: detection.boundingBox.height
        )
        
        // EXPAND bounding box for better OCR
        // Reduced expansion to avoid catching nearby text/labels
        let isPanelLabel = detection.className == "panel_label"
        let expandPercent = isPanelLabel ? 0.15 : 0.10  // 15% for labels, 10% for breakers
        let expandX = visionBBox.width * expandPercent
        let expandY = visionBBox.height * expandPercent
        
        print("📏 [OCR CROP] Expanding bbox by \(Int(expandPercent * 100))% for \(detection.className)")
        let expandedBBox = CGRect(
            x: max(0, visionBBox.origin.x - expandX),
            y: max(0, visionBBox.origin.y - expandY),
            width: min(1, visionBBox.width + expandX * 2),
            height: min(1, visionBBox.height + expandY * 2)
        )
        
        // FIX: Clamp to frame extent to avoid edge failures
        let imageRect = CGRect(
            x: max(0, expandedBBox.origin.x * frame.extent.width),
            y: max(0, expandedBBox.origin.y * frame.extent.height),
            width: min(expandedBBox.width * frame.extent.width, frame.extent.width - expandedBBox.origin.x * frame.extent.width),
            height: min(expandedBBox.height * frame.extent.height, frame.extent.height - expandedBBox.origin.y * frame.extent.height)
        )
        
        guard imageRect.width > 10 && imageRect.height > 10 else {
            return
        }
        
        let croppedImage = frame.cropped(to: imageRect).transformed(by: .identity)
        
        // FIX: Queue OCR with limited concurrency
        ocrQueue.addOperation { [weak self] in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.debugInfo.ocrCallsPerSecond += 1
            }
            
            self.ocrService.recognizeText(in: croppedImage) { [weak self] result in
                guard let self = self else { return }
                
                // Log OCR completion time
                if let ocrStartTime = track.lastOCRStartTime {
                    let ocrTime = Date().timeIntervalSince(ocrStartTime)
                    print("⏱️ [TIMING] OCR processing took: \(String(format: "%.3f", ocrTime))s")
                }
                
                // FIX: Mutations back on tracking queue
                self.trackingQueue.async {
                    guard let result = result else {
                        print("⚠️ [OCR] No text recognized")
                        track.resetDwell()
                        return
                    }
                    
                    track.text = result.text
                    track.ocrConfidence = result.confidence
                    
                    let isPanelLabel = track.className == "panel_label"
                    
                    // Filter garbage OCR - require at least some valid characters
                    let hasValidChars = result.text.rangeOfCharacter(from: CharacterSet.alphanumerics) != nil
                    let hasDigits = result.text.rangeOfCharacter(from: CharacterSet.decimalDigits) != nil
                    let hasHyphen = result.text.contains("-")
                    
                    if !hasValidChars || result.text.count < 2 {
                        print("⚠️ [OCR] Rejecting garbage text: '\(result.text)' (too short or no valid chars)")
                        track.resetDwell()
                        track.startCooldown(self.cooldownFrames)
                        return
                    }
                    
                    print("📝 [OCR] Text read: '\(result.text)' (confidence: \(String(format: "%.2f", result.confidence)), valid chars: \(hasValidChars), digits: \(hasDigits), hyphen: \(hasHyphen))")
                    
                    // Panel labels: light validation to filter obvious garbage
                    // (User can manually decline bad reads via the confirmation prompt)
                    if isPanelLabel {
                        // Reject ONLY obviously bad reads (too short OR no meaningful content)
                        let hasLetters = result.text.rangeOfCharacter(from: CharacterSet.letters) != nil
                        let tooShort = result.text.count < 3  // Relaxed from 5 to 3
                        let noLettersOrDigits = !hasLetters && !hasDigits
                        
                        if tooShort {
                            print("⚠️ [PANEL] Auto-rejecting '\(result.text)' - too short (< 3 chars)")
                            track.resetDwell()
                            track.startCooldown(self.cooldownFrames)
                            return
                        }
                        
                        if noLettersOrDigits {
                            print("⚠️ [PANEL] Auto-rejecting '\(result.text)' - no letters or digits")
                            track.resetDwell()
                            track.startCooldown(self.cooldownFrames)
                            return
                        }
                        
                        // VALIDATION: Panel labels should look like panel labels
                        // Most formats: Letters + numbers (e.g., "FC043-P5", "C169")
                        // But some panels are just letters ("MAIN") or just numbers ("120")
                        // So we require EITHER letters OR digits (not neither)
                        
                        if !hasLetters && !hasDigits {
                            print("⚠️ [PANEL] Rejecting '\(result.text)' - no letters or digits")
                            track.resetDwell()
                            track.startCooldown(self.cooldownFrames)
                            return
                        }
                        
                        // Must be reasonable length (3-12 chars) - panel labels aren't huge
                        if result.text.count > 12 {
                            print("⚠️ [PANEL] Rejecting '\(result.text)' - too long (> 12 chars), likely garbage")
                            track.resetDwell()
                            track.startCooldown(self.cooldownFrames)
                            return
                        }
                        
                        // Reject if mostly non-alphanumeric (garbage like "---" or "...")
                        let alphanumericCount = result.text.filter { $0.isLetter || $0.isNumber }.count
                        let alphanumericRatio = Double(alphanumericCount) / Double(result.text.count)
                        if alphanumericRatio < 0.6 {
                            print("⚠️ [PANEL] Rejecting '\(result.text)' - too many symbols (\(Int(alphanumericRatio * 100))% alphanumeric)")
                            track.resetDwell()
                            track.startCooldown(self.cooldownFrames)
                            return
                        }
                        
                        // All other reads (including 3-4 char labels, numbers-only, etc) 
                        // will be shown to user for manual confirmation
                        print("🏷️ [PANEL] Showing prompt: '\(result.text)' (\(result.text.count) chars, letters: \(hasLetters), digits: \(hasDigits), conf: \(String(format: "%.2f", result.confidence)))")
                    } else {
                        // Breakers must meet confidence threshold
                        guard result.confidence >= self.ocrThreshold else {
                            track.resetDwell()
                            self.sessionManager.addEvent("OCR failed threshold: \(result.text) (\(result.confidence))")
                            return
                        }
                        
                        // Breakers must pass full validation
                        if !result.isValid {
                            track.resetDwell()
                            track.startCooldown(self.cooldownFrames)
                            self.sessionManager.addEvent("OCR invalid format: \(result.text)")
                            return
                        }
                    }
                    
                    // Only update enriched detections if confidence passed
                    self.updateEnrichedDetectionsWithOCR(trackID: track.id, text: result.text)
                    
                    let trackCenter = CGPoint(x: track.bbox.midX, y: track.bbox.midY)
                    
            // Confirmation prompt logic:
            // ONLY SHOW CONFIRMATIONS WHEN RECORDING IS ACTIVE
            // - Panel mode + recording: ONLY prompt for panel labels (skip breakers)
            // - Full mode + recording: Prompt for everything
            // - Not recording: Auto-capture (no prompts)
            
            // isPanelLabel already declared above for validation
            let isBreaker = track.className == "breaker_face" || track.className == "text_roi"
            
            if !self.sessionManager.isRecording {
                // NOT RECORDING - just skip, don't auto-capture
                // This prevents poisoning capturedItems registry before user starts recording
                print("⏭️ [NOT REC] Skipping OCR result '\(result.text)' - not recording yet")
                track.resetDwell()
                // No cooldown - let it try again when recording starts
                return
            }
            
            // RECORDING IS ACTIVE - check mode
            if self.isPanelLabelMode && isBreaker {
                // Panel mode + breaker → skip entirely to prevent memory leak
                print("⏭️ [SKIP] Breaker '\(result.text)' in panel mode - not prompting")
                track.resetDwell()
                track.startCooldown(self.cooldownFrames)
                return
            }
            
            // CRITICAL: Check if we're ALREADY PROMPTING for this exact text
            // This catches parallel OCR completions for the same text
            if self.currentlyPrompting.contains(result.text) {
                print("⚠️ [SKIP] Already prompting for '\(result.text)' - blocking duplicate")
                track.resetDwell()
                return
            }
            
            // Also check if ANY prompt is showing (different text)
            if let existing = self.pendingConfirmation {
                print("⚠️ [SKIP] Already have pending confirmation for '\(existing.text)' (trackID: \(existing.trackID)) - skipping new OCR result '\(result.text)' (trackID: \(track.id))")
                print("   Pending at: (\(Int(existing.boundingBox.midX * 100)), \(Int(existing.boundingBox.midY * 100)))")
                print("   New at: (\(Int(trackCenter.x * 100)), \(Int(trackCenter.y * 100)))")
                track.resetDwell()
                // Don't start cooldown - let this track retry after user responds
                return
            }
            
            // Check spatial duplicates (already captured or currently prompting)
            // This runs AFTER pendingConfirmation check, so it catches confirmed items
            if self.isDuplicateAtLocation(result.text, center: trackCenter, isPanelLabel: isPanelLabel) {
                print("⏭️ [SKIP] Duplicate at this location: \(result.text) at (\(Int(trackCenter.x * 100)), \(Int(trackCenter.y * 100)))")
                print("   Existing entries in registry: \(self.capturedItems[result.text]?.count ?? 0)")
                track.resetDwell()
                track.startCooldown(self.cooldownFrames)
                self.sessionManager.addEvent("Duplicate rejected: \(result.text) at (\(trackCenter.x), \(trackCenter.y))")
                return
            }
            
            // Mark as currently prompting (ATOMIC - prevents duplicates)
            // DON'T add to capturedItems yet - only add on confirm, not on prompt!
            self.currentlyPrompting.insert(result.text)
            print("🔒 [PROMPT] Locked '\(result.text)' in prompting set - will block duplicates")
            
            // Show confirmation prompt (recording is active)
            print("📋 [PROMPT] Showing confirmation for: \(result.text) (class: \(track.className))")
            
            let pending = PendingOCRConfirmation(
                trackID: track.id,
                text: result.text,
                confidence: result.confidence,
                boundingBox: track.bbox,
                className: track.className,
                timestamp: Date()
            )
            
            DispatchQueue.main.async {
                if let ocrStartTime = track.lastOCRStartTime {
                    let delay = Date().timeIntervalSince(ocrStartTime)
                    print("⏱️ [TIMING] OCR→Prompt delay: \(String(format: "%.3f", delay))s for \(result.text)")
                }
                self.pendingConfirmation = pending
            }
            
            // Store reference for capture if confirmed
            track.pendingFrame = frame
                }
            }
        }
    }
    
    // FIX: Spatial-aware duplicate detection
    private func isDuplicateAtLocation(_ text: String, center: CGPoint, isPanelLabel: Bool = false) -> Bool {
        print("🔍 [DUPLICATE] Checking: \(text) at (\(Int(center.x * 100)), \(Int(center.y * 100)))")
        
        // Check if we have captures of this text
        guard let existingCenters = capturedItems[text] else {
            print("✅ [DUPLICATE] New text, not a duplicate")
            return false
        }
        
        // FIX: Panel labels use larger radius (camera movement tolerance)
        // Breakers: 15% of screen, Panel labels: 25% of screen
        let minDistance: CGFloat = isPanelLabel ? 0.25 : 0.15
        for (index, existingCenter) in existingCenters.enumerated() {
            let dx = center.x - existingCenter.x
            let dy = center.y - existingCenter.y
            let distance = sqrt(dx * dx + dy * dy)
            
            if distance < minDistance {
                print("❌ [DUPLICATE] Too close to existing capture #\(index): distance=\(distance)")
                return true  // Too close to existing capture
            }
        }
        
        // Also check fuzzy matches (OCR variants)
        print("🔍 [DUPLICATE] Checking fuzzy matches against \(capturedItems.count) captured items...")
        for (existingText, centers) in capturedItems {
            guard existingText != text else { continue }
            
            print("🔍 [DUPLICATE] Comparing '\(text)' vs '\(existingText)'")
            let textDistance = ocrService.fuzzyDistance(text, existingText)
            print("📏 [DUPLICATE] Fuzzy distance: \(textDistance) (threshold: \(fuzzyThreshold))")
            
            if textDistance <= fuzzyThreshold {
                print("⚠️ [DUPLICATE] Fuzzy match found, checking spatial distance...")
                // Check spatial distance for fuzzy matches too
                for existingCenter in centers {
                    let dx = center.x - existingCenter.x
                    let dy = center.y - existingCenter.y
                    let distance = sqrt(dx * dx + dy * dy)
                    
                    if distance < minDistance {
                        print("❌ [DUPLICATE] Fuzzy match too close: distance=\(distance)")
                        return true
                    }
                }
            }
        }
        
        print("✅ [DUPLICATE] Not a duplicate")
        return false
    }
    
    private func captureTrack(_ track: TrackState, ocrResult: OCRResult, frame: CIImage) {
        print("📸 [CAPTURE] Starting capture for: \(ocrResult.text), class: \(track.className)")
        
        track.isCaptured = true
        track.startCooldown(cooldownFrames)
        
        // CODEX FIX #2: Add to capturedItems ONLY on actual capture (not on prompt)
        // This prevents ignore/timeout from marking bad reads as "captured"
        let trackCenter = CGPoint(x: track.bbox.midX, y: track.bbox.midY)
        if capturedItems[ocrResult.text] != nil {
            capturedItems[ocrResult.text]?.append(trackCenter)
            print("📍 [CAPTURE] Added to registry: \(ocrResult.text), total locations: \(capturedItems[ocrResult.text]?.count ?? 0)")
        } else {
            capturedItems[ocrResult.text] = [trackCenter]
            print("📍 [CAPTURE] NEW registry entry: \(ocrResult.text) at (\(Int(trackCenter.x * 100)), \(Int(trackCenter.y * 100)))")
        }
        
        // Capture image crop
        print("🖼️ [CAPTURE] Converting to UIImage...")
        let uiImage = convertToUIImage(frame, bbox: track.bbox)
        
        // CRITICAL: Update SessionManager on main thread (it has @Published properties)
        DispatchQueue.main.async {
            if track.className == "panel_label" {
                print("🏷️ [CAPTURE] Capturing panel label: \(ocrResult.text)")
                self.sessionManager.capturePanel(
                    partNumber: ocrResult.text,
                    confidence: track.smoothedConfidence,
                    image: uiImage
                )
                print("✅ [CAPTURE] Panel label captured")
            } else if track.className == "breaker_face" || track.className == "text_roi" {
                print("⚡ [CAPTURE] Capturing breaker (from \(track.className)): \(ocrResult.text)")
                self.sessionManager.captureBreaker(
                    partNumber: ocrResult.text,
                    confidence: track.smoothedConfidence,
                    ocrConfidence: ocrResult.confidence,
                    isValid: ocrResult.isValid,
                    bbox: track.bbox,
                    image: uiImage
                )
                print("✅ [CAPTURE] Breaker captured")
            } else {
                print("⚠️ [CAPTURE] Unknown class: \(track.className)")
            }
        }
        
        DispatchQueue.main.async {
            self.debugInfo.captureCount += 1
        }
        
        print("✅ [CAPTURE] Complete for: \(ocrResult.text)")
    }
    
    private func performTemporalNMS() {
        let trackArray = Array(tracks.values)
        
        for i in 0..<trackArray.count {
            for j in (i+1)..<trackArray.count {
                let track1 = trackArray[i]
                let track2 = trackArray[j]
                
                guard track1.className == track2.className,
                      let text1 = track1.text,
                      let text2 = track2.text else { continue }
                
                let iou = track1.iou(with: track2)
                let distance = ocrService.fuzzyDistance(text1, text2)
                
                if iou > 0.3 && distance <= fuzzyThreshold {
                    // Merge tracks - keep the one with higher confidence
                    if track1.smoothedConfidence > track2.smoothedConfidence {
                        tracks.removeValue(forKey: track2.id)
                    } else {
                        tracks.removeValue(forKey: track1.id)
                    }
                }
            }
        }
    }
    
    // SHARED CI CONTEXT for performance (avoid creating new one each time)
    private let ciContext = CIContext(options: nil)
    
    private func convertToUIImage(_ ciImage: CIImage, bbox: CGRect) -> UIImage? {
        // FIX: Convert back to Vision coords and clamp
        let visionBBox = CGRect(
            x: bbox.origin.x,
            y: 1 - bbox.origin.y - bbox.height,
            width: bbox.width,
            height: bbox.height
        )
        
        let imageRect = CGRect(
            x: max(0, visionBBox.origin.x * ciImage.extent.width),
            y: max(0, visionBBox.origin.y * ciImage.extent.height),
            width: min(visionBBox.width * ciImage.extent.width, ciImage.extent.width - visionBBox.origin.x * ciImage.extent.width),
            height: min(visionBBox.height * ciImage.extent.height, ciImage.extent.height - visionBBox.origin.y * ciImage.extent.height)
        )
        
        guard imageRect.width > 10 && imageRect.height > 10 else {
            return nil
        }
        
        let croppedImage = ciImage.cropped(to: imageRect).transformed(by: .identity)
        
        // Use shared CIContext for performance (instead of creating new one each time)
        guard let cgImage = ciContext.createCGImage(croppedImage, from: croppedImage.extent) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    // FIX: Proper validation and clamping
    func loadSettings() {
        let defaults = UserDefaults.standard
        
        // Check if key exists, use default if not
        if let value = defaults.object(forKey: "detectorThreshold") as? Float {
            detectorThreshold = max(0.1, min(0.99, value))
        } else {
            detectorThreshold = 0.85
        }
        
        if let value = defaults.object(forKey: "ocrThreshold") as? Float {
            ocrThreshold = max(0.1, min(0.99, value))
        } else {
            ocrThreshold = 0.90
        }
        
        if let value = defaults.object(forKey: "dwellFrames") as? Int {
            dwellFrames = max(1, min(20, value))
        } else {
            dwellFrames = 5
        }
        
        if let value = defaults.object(forKey: "iouTrackThreshold") as? Float {
            iouTrackThreshold = max(0.1, min(0.9, value))
        } else {
            iouTrackThreshold = 0.5
        }
        
        if let value = defaults.object(forKey: "cooldownFrames") as? Int {
            cooldownFrames = max(5, min(120, value))
        } else {
            cooldownFrames = 30
        }
    }
    
    // Add reset method
    func resetSession() {
        print("🔄 [RESET] Resetting tracking session (NOT wiping UI data)")
        trackingQueue.async { [weak self] in
            guard let self = self else { return }
            
            // V3 FIX: Clean up any pending frames before clearing tracks
            for track in self.tracks.values {
                track.pendingFrame = nil
            }
            
            self.tracks.removeAll()
            self.capturedItems.removeAll()  // Clear spatial dedup
            self.currentlyPrompting.removeAll()  // Clear prompting locks
            self.frameNumber = 0
            DebugLogger.shared.log("Tracking reset - cleared tracks, dedup registry, and prompting locks", level: .info)
            
            DispatchQueue.main.async {
                self.activeTracks = []
                self.debugInfo = DebugInfo()
                self.pendingConfirmation = nil
            }
            
            // DON'T call sessionManager.resetSession() here
            // That wipes panel label + breakers from UI before user can review
        }
    }
    
    func resetSessionManager() {
        print("🔄 [RESET] Wiping session manager (clears UI data)")
        DispatchQueue.main.async { [weak self] in
            self?.sessionManager.resetSession()
        }
    }
    
    func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(detectorThreshold, forKey: "detectorThreshold")
        defaults.set(ocrThreshold, forKey: "ocrThreshold")
        defaults.set(dwellFrames, forKey: "dwellFrames")
        defaults.set(iouTrackThreshold, forKey: "iouTrackThreshold")
        defaults.set(cooldownFrames, forKey: "cooldownFrames")
    }
    
    // Update enriched detections when OCR completes
    private func updateEnrichedDetectionsWithOCR(trackID: String, text: String) {
        // Get the track's bbox to match against current detections
        guard let track = tracks[trackID] else {
            return
        }
        let bbox = track.bbox
        
        DispatchQueue.main.async {
            var updated = self.enrichedDetections
            
            // Find detection by spatial matching (track bbox vs detection bbox)
            for i in 0..<updated.count {
                let detection = updated[i]
                
                // Match text_roi or panel_label by bbox overlap
                if (detection.className == "text_roi" || detection.className == "panel_label") {
                    let iou = self.calculateIOU(bbox, detection.boundingBox)
                    if iou > 0.5 {
                        updated[i] = Detection(
                            className: detection.className,
                            confidence: detection.confidence,
                            boundingBox: detection.boundingBox,
                            text: text
                        )
                        
                        // Also associate with nearest breaker
                        if detection.className == "text_roi" {
                            if let nearestBreaker = self.findNearestBreaker(to: detection, in: updated) {
                                if let breakerIndex = updated.firstIndex(where: { $0.id == nearestBreaker.id }) {
                                    updated[breakerIndex] = Detection(
                                        className: nearestBreaker.className,
                                        confidence: nearestBreaker.confidence,
                                        boundingBox: nearestBreaker.boundingBox,
                                        text: text
                                    )
                                }
                            }
                        }
                        break
                    }
                }
            }
            
            self.enrichedDetections = updated
        }
    }
    
    // Helper to find nearest breaker to a detection
    private func findNearestBreaker(to detection: Detection, in detections: [Detection]) -> Detection? {
        let center = CGPoint(x: detection.boundingBox.midX, y: detection.boundingBox.midY)
        
        var nearestBreaker: Detection?
        var minDistance: CGFloat = 0.15
        
        for d in detections where d.className == "breaker_face" {
            let breakerCenter = CGPoint(x: d.boundingBox.midX, y: d.boundingBox.midY)
            let distance = hypot(center.x - breakerCenter.x, center.y - breakerCenter.y)
            
            if distance < minDistance {
                minDistance = distance
                nearestBreaker = d
            }
        }
        
        return nearestBreaker
    }
    
    // V3 FIX: Check for expired pending confirmations and auto-cleanup
    private func checkForExpiredConfirmations() {
        // Must be called on trackingQueue
        guard let pending = pendingConfirmation else { return }
        
        let age = Date().timeIntervalSince(pending.timestamp)
        if age > confirmationTimeoutSeconds {
            print("⏱️ [TIMEOUT] Pending confirmation expired after \(Int(age))s: '\(pending.text)' - auto-cleaning up")
            
            // Clean up the track's pending frame to release CIImage
            if let track = tracks[pending.trackID] {
                track.pendingFrame = nil
                track.resetDwell()
                // Don't start cooldown - let it try again if still visible
                print("⏱️ [TIMEOUT] Released CIImage for track \(pending.trackID)")
            }
            
            // CRITICAL: Remove from currentlyPrompting (CODEX FIX #1)
            self.currentlyPrompting.remove(pending.text)
            print("🔓 [TIMEOUT] Unlocked '\(pending.text)' from prompting set")
            
            // DON'T add to capturedItems - user didn't see/confirm this
            
            // Clear the confirmation on main thread
            DispatchQueue.main.async { [weak self] in
                self?.pendingConfirmation = nil
                print("⏱️ [TIMEOUT] Cleared expired confirmation from UI")
            }
        }
    }
    
    // Public methods for confirming/ignoring OCR results
    func confirmOCR(_ confirmation: PendingOCRConfirmation) {
        print("🟢 [CONFIRM] Starting confirmation for: \(confirmation.text) (ID: \(confirmation.trackID))")
        trackingQueue.async { [weak self] in
            guard let self = self else {
                print("⚠️ [CONFIRM] Self is nil")
                return
            }
            
            guard let track = self.tracks[confirmation.trackID] else {
                print("⚠️ [CONFIRM] Track not found: \(confirmation.trackID) - clearing stuck overlay")
                
                // CODEX FIX #1: Remove from prompting set to prevent permanent lock
                self.currentlyPrompting.remove(confirmation.text)
                print("🔓 [CONFIRM ERROR] Unlocked '\(confirmation.text)' from prompting set")
                
                // Track disappeared - clear the stuck confirmation so user can continue
                DispatchQueue.main.async {
                    self.pendingConfirmation = nil
                }
                return
            }
            
            guard let frame = track.pendingFrame else {
                print("⚠️ [CONFIRM] No pending frame for track: \(confirmation.trackID) - clearing stuck overlay")
                
                // CODEX FIX #1: Remove from prompting set to prevent permanent lock
                self.currentlyPrompting.remove(confirmation.text)
                print("🔓 [CONFIRM ERROR] Unlocked '\(confirmation.text)' from prompting set")
                
                // Frame was cleaned up - clear the stuck confirmation so user can continue
                track.resetDwell()
                track.startCooldown(self.cooldownFrames)
                DispatchQueue.main.async {
                    self.pendingConfirmation = nil
                }
                return
            }
            
            print("✅ [CONFIRM] All checks passed, capturing: \(confirmation.text)")
            
            // Mark track as captured BEFORE calling captureTrack to prevent re-detection
            track.isCaptured = true
            track.startCooldown(self.cooldownFrames)
            print("🔒 [CONFIRM] Track marked as captured with \(self.cooldownFrames) frame cooldown - won't prompt again this session")
            
            let ocrResult = OCRResult(
                text: confirmation.text,
                confidence: confirmation.confidence,
                isValid: true
            )
            
            let trackCenter = CGPoint(x: track.bbox.midX, y: track.bbox.midY)
            DebugLogger.shared.log("✅ USER CONFIRMED: \(confirmation.text) at (\(Int(trackCenter.x * 100)), \(Int(trackCenter.y * 100)))", level: .success)
            
            self.captureTrack(track, ocrResult: ocrResult, frame: frame)
            
            // CRITICAL: Clear pendingFrame to release CIImage and allow track cleanup
            track.pendingFrame = nil
            
            print("✅ [CONFIRM] Capture complete for '\(confirmation.text)' - clearing pending confirmation")
            
            // Remove from prompting set (allow new prompts for this text if detected again far away)
            self.currentlyPrompting.remove(confirmation.text)
            print("🔓 [CONFIRM] Unlocked '\(confirmation.text)' from prompting set")
            
            DispatchQueue.main.async {
                print("🧹 [CONFIRM] Cleared pendingConfirmation on main thread")
                self.pendingConfirmation = nil
            }
        }
    }
    
    func ignoreOCR(_ confirmation: PendingOCRConfirmation) {
        print("🔴 [IGNORE] Starting ignore for: \(confirmation.text) (ID: \(confirmation.trackID))")
        trackingQueue.async { [weak self] in
            guard let self = self else {
                print("⚠️ [IGNORE] Self is nil")
                return
            }
            
            guard let track = self.tracks[confirmation.trackID] else {
                print("⚠️ [IGNORE] Track not found: \(confirmation.trackID)")
                
                // CODEX CRITICAL FIX: Unlock currentlyPrompting even when track is gone
                self.currentlyPrompting.remove(confirmation.text)
                print("🔓 [IGNORE ERROR] Unlocked '\(confirmation.text)' from prompting set")
                
                DispatchQueue.main.async { [weak self] in
                    self?.pendingConfirmation = nil
                }
                return
            }
            
            print("🔴 [IGNORE] Track found, resetting for retry")
            DebugLogger.shared.log("❌ USER IGNORED: \(confirmation.text)", level: .info)
            
            // FIX: Don't start cooldown on ignore - let it try OCR again immediately
            // User wants to reject bad OCR and get a new prompt quickly
            track.resetDwell()
            track.pendingFrame = nil
            // NO cooldown - track can run OCR again on next frame
            
            print("✅ [IGNORE] Complete for '\(confirmation.text)' - clearing locks")
            
            // Remove from prompting set (allow retry on next frame)
            self.currentlyPrompting.remove(confirmation.text)
            print("🔓 [IGNORE] Unlocked '\(confirmation.text)' - can prompt again if detected")
            
            // DON'T add to capturedItems - user rejected this read
            // Let it try OCR again for a better read
            
            DispatchQueue.main.async {
                print("🧹 [IGNORE] Cleared pendingConfirmation on main thread")
                self.pendingConfirmation = nil
            }
        }
    }
    
    // Associate existing track OCR text with current frame detections spatially
    private func associateTextWithBreakers(_ detections: [Detection], frame: CIImage) -> [Detection] {
        var enriched = detections
        
        // Build map of track bboxes to their OCR text (only for tracks that passed dwell + confidence)
        var trackTextMap: [CGRect: String] = [:]
        for (_, track) in tracks {
            if let text = track.text, !text.isEmpty, track.ocrConfidence >= Float(ocrThreshold) {
                trackTextMap[track.bbox] = text
            }
        }
        
        // Associate track text with current detections by spatial overlap
        for i in 0..<enriched.count {
            let detection = enriched[i]
            
            // For text_roi and panel_label, match to track by IOU
            if detection.className == "text_roi" || detection.className == "panel_label" {
                if let matchedText = findMatchingTrackText(for: detection.boundingBox, in: trackTextMap) {
                    enriched[i] = Detection(
                        className: detection.className,
                        confidence: detection.confidence,
                        boundingBox: detection.boundingBox,
                        text: matchedText
                    )
                }
            }
            
            // For breaker_face, find nearest text_roi with OCR
            if detection.className == "breaker_face" {
                let textROIs = enriched.filter { $0.className == "text_roi" }
                if let nearestText = findNearestTextROI(to: detection, in: textROIs), let text = nearestText.text {
                    enriched[i] = Detection(
                        className: detection.className,
                        confidence: detection.confidence,
                        boundingBox: detection.boundingBox,
                        text: text
                    )
                }
            }
        }
        
        return enriched
    }
    
    // Find matching track text by bbox IOU
    private func findMatchingTrackText(for bbox: CGRect, in trackTextMap: [CGRect: String]) -> String? {
        var bestMatch: String?
        var maxIOU: Float = 0.5  // Require at least 50% overlap
        
        for (trackBBox, text) in trackTextMap {
            let iou = calculateIOU(bbox, trackBBox)
            if iou > maxIOU {
                maxIOU = iou
                bestMatch = text
            }
        }
        
        return bestMatch
    }
    
    // Find nearest text_roi to a breaker_face
    private func findNearestTextROI(to breaker: Detection, in textROIs: [Detection]) -> Detection? {
        let breakerCenter = CGPoint(
            x: breaker.boundingBox.midX,
            y: breaker.boundingBox.midY
        )
        
        var nearestText: Detection?
        var minDistance: CGFloat = 0.15  // Max 15% of screen distance
        
        for textROI in textROIs {
            let textCenter = CGPoint(
                x: textROI.boundingBox.midX,
                y: textROI.boundingBox.midY
            )
            
            let dx = breakerCenter.x - textCenter.x
            let dy = breakerCenter.y - textCenter.y
            let distance = sqrt(dx * dx + dy * dy)
            
            if distance < minDistance {
                minDistance = distance
                nearestText = textROI
            }
        }
        
        return nearestText
    }
}

struct DebugInfo {
    var frameNumber: Int = 0
    var activeTrackCount: Int = 0
    var ocrCallsPerSecond: Int = 0
    var captureCount: Int = 0
}

