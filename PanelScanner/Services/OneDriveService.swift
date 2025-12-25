import Foundation
import ZIPFoundation

class OneDriveService {
    private let oneDriveAppId = "YOUR_APP_ID_HERE"  // Get from Azure portal
    
    // V3 NOTE: OneDrive cloud upload is NOT YET IMPLEMENTED
    // Currently saves all data locally to Documents/Scans/
    // This is intentional for V3 - cloud sync will be added in a future update
    
    func uploadScan(detections: [[Detection]], panelLabel: String, videoURL: URL? = nil, sessionManager: SessionManager? = nil, completion: @escaping (URL?) -> Void) {
        // Use SessionManager's confirmed captures instead of raw detections
        let scan: PanelScan
        if let sessionManager = sessionManager {
            scan = createPanelScanFromSession(sessionManager: sessionManager)
            print("📦 [V3-SAVE] Using SessionManager - \(scan.breakers.count) confirmed breakers")
        } else {
            scan = createPanelScan(from: detections, label: panelLabel)
            print("📦 [V3-SAVE] Using detections fallback - \(scan.breakers.count) breakers")
        }
        
        DebugLogger.shared.log("V3: Saving scan locally (OneDrive sync not yet implemented): \(detections.count) frames, panel: \(panelLabel.isEmpty ? "UNSET" : panelLabel)", level: .info)
        
        // Run on background thread to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // V3 TODO: Implement OneDrive cloud upload in future version
            // For now, save locally to Documents/Scans/
            // Steps for future implementation:
            // 1. Authenticate with Microsoft Graph API
            // 2. Create JSON from scan data
            // 3. Upload to OneDrive/PanelScans/
            // 4. Handle upload errors and retry logic
            // 5. Add offline queue for failed uploads
            
            print("⚠️ [V3-INFO] OneDrive cloud sync not implemented - saving locally only")
            self?.saveLocally(scan: scan, videoURL: videoURL, completion: completion)
        }
    }
    
    func saveCurrentSession(detections: [[Detection]], panelLabel: String) {
        // V3: Autosave during recording - local only
        print("💾 [V3-AUTOSAVE] Saving session checkpoint locally")
        let scan = createPanelScan(from: detections, label: panelLabel)
        saveLocally(scan: scan) { url in
            if url != nil {
                print("✅ [V3-AUTOSAVE] Session checkpoint saved")
            } else {
                print("❌ [V3-AUTOSAVE] Session checkpoint failed")
            }
        }
    }
    
    private func createPanelScan(from detections: [[Detection]], label: String) -> PanelScan {
        // Use SessionManager's captured breakers instead of raw detections
        // This ensures we only save confirmed breakers
        print("📦 [SAVE] Creating scan from detections - using SessionManager breakers")
        
        // This is a fallback - ideally we should use SessionManager directly
        // For now, deduplicate breakers by spatial position
        var uniqueBreakers: [String: BreakerInfo] = [:]
        
        for frameDetections in detections {
            for detection in frameDetections where detection.className == "breaker_face" {
                // Create spatial key (rounded to avoid floating point duplicates)
                let x = Int(detection.boundingBox.midX * 10)  // Less granular - 10% blocks
                let y = Int(detection.boundingBox.midY * 10)
                let spatialKey = "\(x),\(y)"
                
                // Only keep if new OR has part number (prefer ones with OCR)
                if uniqueBreakers[spatialKey] == nil || 
                   (detection.text != nil && uniqueBreakers[spatialKey]?.partNumber == nil) {
                    uniqueBreakers[spatialKey] = BreakerInfo(
                        position: detection.boundingBox,
                        partNumber: detection.text,
                        confidence: detection.confidence
                    )
                }
            }
        }
        
        let breakerArray = Array(uniqueBreakers.values)
        print("📦 [SAVE] Deduplicated to \(breakerArray.count) unique breakers")
        
        return PanelScan(
            timestamp: Date(),
            panelLabel: label,
            breakers: breakerArray,
            totalBreakers: breakerArray.count
        )
    }
    
    private func saveLocally(scan: PanelScan, videoURL: URL? = nil, completion: @escaping (URL?) -> Void) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        guard let data = try? encoder.encode(scan) else {
            completion(nil)
            return
        }
        
        // Save to Documents directory with proper naming format
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd-HHmmss"
        let dateString = dateFormatter.string(from: Date())
        
        // Sanitize label: remove illegal characters, limit length
        let rawLabel = scan.panelLabel.isEmpty ? "UNSET" : scan.panelLabel
        let sanitizedLabel = sanitizeFilename(rawLabel)
        let baseName = "\(sanitizedLabel)__\(dateString)"
        
        if let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let scansDir = documentsDir.appendingPathComponent("Scans")
            
            // Create folder for this scan: Scans/C169-P2__20251110-132519/
            let scanFolder = scansDir.appendingPathComponent(baseName)
            
            do {
                // Create scan folder
                try FileManager.default.createDirectory(at: scanFolder, withIntermediateDirectories: true)
                
                // Save scan JSON
                let scanURL = scanFolder.appendingPathComponent("\(baseName).json")
                try data.write(to: scanURL, options: [.atomic])
                try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: scanURL.path)
                
                // Save CSV
                print("💾 Saving CSV...")
                saveCSV(scan: scan, to: scanFolder, baseName: baseName)
                
                // Save operation logs
                print("💾 Saving logs...")
                saveOperationLogs(to: scanFolder, baseName: baseName)
                
                // Copy video if provided
                if let videoURL = videoURL {
                    print("🎥 Video URL provided: \(videoURL.lastPathComponent)")
                    if FileManager.default.fileExists(atPath: videoURL.path) {
                        let videoDestination = scanFolder.appendingPathComponent("\(baseName).mp4")
                        print("🎥 Copying video to: \(videoDestination.lastPathComponent)")
                        do {
                            try FileManager.default.copyItem(at: videoURL, to: videoDestination)
                            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: videoDestination.path)
                            print("✅ Video copied successfully")
                        } catch {
                            print("❌ Video copy failed: \(error)")
                        }
                    } else {
                        print("⚠️ Video file doesn't exist at path: \(videoURL.path)")
                    }
                } else {
                    print("⚠️ No video URL provided to save")
                }
                
                // Verify what was actually saved and ensure all files are readable
                let savedFiles = (try? FileManager.default.contentsOfDirectory(at: scanFolder, includingPropertiesForKeys: nil)) ?? []
                
                // Set world-readable permissions on all files
                for file in savedFiles {
                    do {
                        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
                    } catch {
                        print("⚠️ Failed to set permissions on \(file.lastPathComponent): \(error)")
                    }
                }
                
                print("✅ SCAN SAVED TO FOLDER:")
                print("  Folder: \(baseName)/")
                print("  Location: \(scanFolder.path)")
                print("  Breakers: \(scan.totalBreakers)")
                print("  Files saved (\(savedFiles.count)):")
                for file in savedFiles {
                    let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[FileAttributeKey.size] as? Int) ?? 0
                    let perms = (try? FileManager.default.attributesOfItem(atPath: file.path)[FileAttributeKey.posixPermissions] as? NSNumber)?.intValue ?? 0
                    print("    - \(file.lastPathComponent) (\(size) bytes, perms: \(String(format: "%o", perms)))")
                }
                
                DebugLogger.shared.log("Scan saved: \(baseName) (\(scan.totalBreakers) breakers)", level: .success)
                
                // Create ZIP on background queue (per Codex recommendation)
                // Capture scanURL strongly to ensure callback fires
                let savedScanURL = scanURL
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    guard let self = self else {
                        // If self is nil, still return the JSON URL
                        print("⚠️ OneDriveService deallocated during ZIP - returning JSON")
                        DispatchQueue.main.async {
                            completion(savedScanURL)
                        }
                        return
                    }
                    
                    self.createZipArchive(for: scanFolder, baseName: baseName) { zipURL in
                        if let zipURL = zipURL {
                            print("✅ ZIP created successfully: \(zipURL.lastPathComponent)")
                            DispatchQueue.main.async {
                                completion(zipURL)
                            }
                        } else {
                            print("⚠️ ZIP creation failed - returning JSON URL for fallback")
                            DispatchQueue.main.async {
                                completion(savedScanURL)
                            }
                        }
                    }
                }
            
            } catch {
                print("❌ SAVE FAILED: \(error)")
                DebugLogger.shared.log("Save failed: \(error.localizedDescription)", level: .error)
                
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        } else {
            DebugLogger.shared.log("Save failed: No documents directory", level: .error)
            DispatchQueue.main.async {
                completion(nil)
            }
        }
    }
    
    private func createZipArchive(for folder: URL, baseName: String, completion: @escaping (URL?) -> Void) {
        // Create ZIP OUTSIDE the folder in parent Scans directory
        let parentFolder = folder.deletingLastPathComponent()
        let zipURL = parentFolder.appendingPathComponent("\(baseName).zip")
        
        // Remove existing ZIP if present
        try? FileManager.default.removeItem(at: zipURL)
        
        print("📦 [ZIP] Compressing folder: \(folder.lastPathComponent)")
        print("📦 [ZIP] Destination: \(zipURL.path)")
        
        // Track if completion was called
        var hasCompleted = false
        let completionLock = NSLock()
        
        // Safe completion wrapper (only calls once)
        let safeCompletion: (URL?) -> Void = { url in
            completionLock.lock()
            defer { completionLock.unlock() }
            
            guard !hasCompleted else {
                print("⚠️ [ZIP] Completion already called, ignoring duplicate")
                return
            }
            hasCompleted = true
            completion(url)
        }
        
        // Add timeout fallback (10 seconds max for ZIP creation)
        DispatchQueue.global().asyncAfter(deadline: .now() + 10.0) {
            completionLock.lock()
            let timedOut = !hasCompleted
            completionLock.unlock()
            
            if timedOut {
                print("⚠️ [ZIP] Timeout after 10s - checking if ZIP exists anyway")
                // Check if ZIP was created despite timeout
                if FileManager.default.fileExists(atPath: zipURL.path) {
                    print("✅ [ZIP] Found completed ZIP after timeout")
                    safeCompletion(zipURL)
                } else {
                    print("❌ [ZIP] Timeout and no ZIP file found")
                    safeCompletion(nil)
                }
            }
        }
        
        do {
            // Create ZIP using ZIPFoundation (streams data, doesn't load into RAM)
            // shouldKeepParent: true creates ZIP with folder structure inside
            try FileManager.default.zipItem(at: folder, to: zipURL, shouldKeepParent: true, compressionMethod: .deflate)
            
            // Verify ZIP was created
            if FileManager.default.fileExists(atPath: zipURL.path) {
                let size = (try? FileManager.default.attributesOfItem(atPath: zipURL.path)[FileAttributeKey.size] as? Int) ?? 0
                print("📦 [ZIP] Created: \(zipURL.lastPathComponent) (\(size) bytes)")
                safeCompletion(zipURL)
            } else {
                print("❌ [ZIP] File doesn't exist after creation")
                safeCompletion(nil)
            }
        } catch {
            print("❌ [ZIP] Creation failed: \(error.localizedDescription)")
            safeCompletion(nil)
        }
    }
    
    private func createPanelScanFromSession(sessionManager: SessionManager) -> PanelScan {
        // Use SessionManager's confirmed captures (not raw detections)
        let breakers = sessionManager.capturedBreakers.map { captured in
            BreakerInfo(
                position: captured.bbox,
                partNumber: captured.partNumber,
                confidence: captured.confidence
            )
        }
        
        let panelLabel = sessionManager.panelPartNumber ?? "UNSET"
        
        print("📦 [SESSION] Panel: \(panelLabel), Breakers: \(breakers.count)")
        
        return PanelScan(
            timestamp: Date(),
            panelLabel: panelLabel,
            breakers: breakers,
            totalBreakers: breakers.count
        )
    }
    
    private func sanitizeFilename(_ name: String) -> String {
        // Remove/replace illegal filename characters
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
        
        // Limit length
        if sanitized.count > 50 {
            sanitized = String(sanitized.prefix(50))
        }
        
        return sanitized.isEmpty ? "UNSET" : sanitized
    }
    
    private func saveCSV(scan: PanelScan, to directory: URL, baseName: String) {
        var csvContent: String
        
        // Simple CSV for panel-only scans (no breakers)
        if scan.breakers.isEmpty {
            csvContent = "Panel Label,Timestamp\n"
            let timestamp = ISO8601DateFormatter().string(from: scan.timestamp)
            let row = [
                scan.panelLabel.replacingOccurrences(of: ",", with: ";"),
                timestamp
            ].joined(separator: ",")
            csvContent += row + "\n"
        } else {
            // Full CSV with breaker details
            csvContent = "Panel Label,Timestamp,Breaker Position X,Breaker Position Y,Part Number,Confidence\n"
            
            for breaker in scan.breakers {
                // Safely format position values (clamp to valid range)
                let posX = max(0, min(1, breaker.position.origin.x))
                let posY = max(0, min(1, breaker.position.origin.y))
                
                let row = [
                    scan.panelLabel.replacingOccurrences(of: ",", with: ";"), // Escape commas
                    "\(scan.timestamp.timeIntervalSince1970)",
                    String(format: "%.6f", posX),
                    String(format: "%.6f", posY),
                    (breaker.partNumber ?? "").replacingOccurrences(of: ",", with: ";"),
                    String(format: "%.4f", breaker.confidence)
                ].joined(separator: ",")
                csvContent += row + "\n"
            }
        }
        
        let csvURL = directory.appendingPathComponent(baseName + ".csv")
        do {
            try csvContent.write(to: csvURL, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: csvURL.path)
        } catch {
            print("❌ CSV save failed: \(error)")
        }
    }
    
    private func saveOperationLogs(to directory: URL, baseName: String) {
        // Collect all operation logs from DebugLogger
        let logs = DebugLogger.shared.getLogMessages()
        
        let logsData: [String: Any] = [
            "session_name": baseName,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "total_logs": logs.count,
            "logs": logs.map { [
                "timestamp": $0.timestamp,
                "level": $0.level.rawValue,
                "message": $0.text
            ]}
        ]
        
        let logsURL = directory.appendingPathComponent("\(baseName)_logs.json")
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: logsData, options: [.prettyPrinted, .sortedKeys])
            try jsonData.write(to: logsURL, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: logsURL.path)
            print("✅ Operation logs saved: \(logs.count) entries")
        } catch {
            print("❌ Logs save failed: \(error)")
        }
    }
}

