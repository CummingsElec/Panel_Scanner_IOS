import SwiftUI

struct SettingsView: View {
    @ObservedObject var detectionService: DetectionService
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var authCoordinator: AuthCoordinator
    @State private var showingDiagnostics = false
    @State private var showingSignOutAlert = false
    
    // V3: Data management alerts
    @State private var showingFirstDeleteAlert = false
    @State private var showingSecondDeleteAlert = false
    @State private var storageSize: String = "Calculating..."
    @State private var showingDeleteSuccess = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Detection Speed")) {
                    VStack(alignment: .leading) {
                        Text("Max FPS: \(Int(settingsStore.maxFPS))")
                            .font(.headline)
                        Slider(value: $settingsStore.maxFPS, in: 1...20, step: 1)
                        Text("Lower = less CPU usage, smoother UI")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                
                Section(header: Text("Confidence Thresholds")) {
                    VStack(alignment: .leading, spacing: 16) {
                        // Panel
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Panel")
                                Spacer()
                                Text("\(Int(settingsStore.panelThreshold * 100))%")
                                    .foregroundColor(.blue)
                            }
                            Slider(value: $settingsStore.panelThreshold, in: 0.1...0.9, step: 0.05)
                        }
                        
                        // Breaker Face
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Breaker Face")
                                Spacer()
                                Text("\(Int(settingsStore.breakerThreshold * 100))%")
                                    .foregroundColor(.green)
                            }
                            Slider(value: $settingsStore.breakerThreshold, in: 0.1...0.9, step: 0.05)
                        }
                        
                        // Text ROI
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Text ROI")
                                Spacer()
                                Text("\(Int(settingsStore.textROIThreshold * 100))%")
                                    .foregroundColor(.yellow)
                            }
                            Slider(value: $settingsStore.textROIThreshold, in: 0.1...0.9, step: 0.05)
                        }
                        
                        // Panel Label
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Panel Label")
                                Spacer()
                                Text("\(Int(settingsStore.panelLabelThreshold * 100))%")
                                    .foregroundColor(.red)
                            }
                            Slider(value: $settingsStore.panelLabelThreshold, in: 0.1...0.9, step: 0.05)
                        }
                        
                        // OCR Threshold
                        VStack(alignment: .leading) {
                            HStack {
                                Text("OCR Confidence")
                                Spacer()
                                Text("\(Int(settingsStore.ocrThreshold * 100))%")
                                    .foregroundColor(.orange)
                            }
                            Slider(value: $settingsStore.ocrThreshold, in: 0.5...0.95, step: 0.05)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    Text("Higher = fewer detections but more accurate")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section(header: Text("Tracking Parameters")) {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Dwell Frames")
                            Spacer()
                            Text("\(settingsStore.dwellFrames)")
                                .foregroundColor(.secondary)
                        }
                        Stepper("", value: $settingsStore.dwellFrames, in: 1...20)
                            .labelsHidden()
                        Text("Frames required before locking detection")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading) {
                        HStack {
                            Text("IOU Track Threshold")
                            Spacer()
                            Text("\(Int(settingsStore.iouTrackThreshold * 100))%")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $settingsStore.iouTrackThreshold, in: 0.3...0.9, step: 0.05)
                        Text("Overlap needed to track same object")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Cooldown Frames")
                            Spacer()
                            Text("\(settingsStore.cooldownFrames)")
                                .foregroundColor(.secondary)
                        }
                        Stepper("", value: $settingsStore.cooldownFrames, in: 10...60)
                            .labelsHidden()
                        Text("Frames to wait before re-detecting same position")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("Current Values"),
                       footer: Text(settingsStore.currentEffectiveValues)
                        .font(.caption)
                        .foregroundColor(.secondary)) {
                    Button("Reset to Recommended") {
                        settingsStore.resetToDefaults()
                    }
                    .foregroundColor(.orange)
                }
                
                Section(header: Text("Help & Diagnostics")) {
                    NavigationLink(destination: InstructionsView()) {
                        HStack {
                            Image(systemName: "questionmark.circle")
                            Text("App Instructions")
                        }
                    }
                    
                    Button("Export Diagnostics") {
                        showingDiagnostics = true
                    }
                    
                    HStack {
                        Text("Model")
                        Spacer()
                        Text("YOLOv8")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Current FPS")
                        Spacer()
                        Text("\(detectionService.currentFPS, specifier: "%.1f")")
                            .foregroundColor(.secondary)
                    }
                }
                
                // V3: Data Management Section
                Section(header: Text("Data Management"),
                       footer: Text("Delete all saved scans, videos, and export files from this device. This cannot be undone.")
                        .font(.caption)
                        .foregroundColor(.secondary)) {
                    
                    HStack {
                        Text("Storage Used")
                        Spacer()
                        Text(storageSize)
                            .foregroundColor(.secondary)
                    }
                    
                    Button(action: {
                        calculateStorageSize()
                        showingFirstDeleteAlert = true
                    }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Clear All Saved Data")
                        }
                        .foregroundColor(.red)
                    }
                }
                
                Section(header: Text("Account")) {
                    if let user = authCoordinator.currentUser {
                        HStack {
                            Text("Signed in as")
                            Spacer()
                            Text(user.email ?? user.sub)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    Button("Sign Out") {
                        showingSignOutAlert = true
                    }
                    .foregroundColor(.red)
                }
                
                Section(header: Text("Export Options")) {
                    Toggle("Record Video", isOn: $settingsStore.enableVideoRecording)
                    
                    Text("When enabled, records raw camera feed as MP4 alongside JSON/CSV. May use significant storage.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section(header: Text("⚡ Electrical Guru AI"),
                       footer: Text("Powered by AI. Requires API key from OpenAI or xAI (Grok). ~$0.002 per question.")
                        .font(.caption)
                        .foregroundColor(.secondary)) {
                    
                    Picker("AI Provider", selection: $settingsStore.aiProvider) {
                        Text("OpenAI (GPT-3.5)").tag("openai")
                        Text("xAI (Grok)").tag("xai")
                    }
                    .pickerStyle(.segmented)
                    
                    SecureField(settingsStore.aiProvider == "xai" ? "xAI API Key" : "OpenAI API Key", 
                               text: $settingsStore.aiAPIKey)
                        .font(.system(.caption, design: .monospaced))
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                    
                    if !settingsStore.aiAPIKey.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("API Key Configured")
                                .font(.caption)
                            Spacer()
                            Text(settingsStore.aiProvider == "xai" ? "Grok" : "GPT-3.5")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.orange)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Get API Key:")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Text(settingsStore.aiProvider == "xai" ? "console.x.ai" : "platform.openai.com/api-keys")
                                    .font(.caption2)
                                    .foregroundColor(.cyan)
                            }
                        }
                    }
                }
                
                #if DEBUG
                Section(header: Text("Debug")) {
                    Toggle("Show Debug Overlay", isOn: $settingsStore.showDebugOverlay)
                    Toggle("Local Mode", isOn: $settingsStore.isLocalModeEnabled)
                }
                #endif
            }
            .navigationTitle("Settings")
            .onAppear {
                calculateStorageSize()
            }
            .alert("Sign Out?", isPresented: $showingSignOutAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Sign Out", role: .destructive) {
                    authCoordinator.signOut()
                }
            }
            // V3: First deletion confirmation
            .alert("⚠️ Delete All Saved Data?", isPresented: $showingFirstDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Continue", role: .destructive) {
                    showingSecondDeleteAlert = true
                }
            } message: {
                Text("This will delete all saved scans, videos, and export files (\(storageSize)). You will be asked to confirm again.")
            }
            // V3: Second (final) deletion confirmation
            .alert("🛑 FINAL WARNING", isPresented: $showingSecondDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("DELETE EVERYTHING", role: .destructive) {
                    deleteAllData()
                }
            } message: {
                Text("Are you absolutely sure? This will permanently delete \(storageSize) of data and CANNOT be undone.")
            }
            // V3: Success confirmation
            .alert("✅ Data Deleted", isPresented: $showingDeleteSuccess) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("All saved scans and videos have been permanently deleted from this device.")
            }
            .sheet(isPresented: $showingDiagnostics) {
                DiagnosticsView()
            }
        }
    }
    
    
    // V3: Calculate storage used by app data
    private func calculateStorageSize() {
        DispatchQueue.global(qos: .utility).async {
            guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                DispatchQueue.main.async {
                    storageSize = "Unknown"
                }
                return
            }
            
            let scansDir = documentsDir.appendingPathComponent("Scans")
            let framesDir = documentsDir.appendingPathComponent("frames")
            
            var totalSize: Int64 = 0
            
            // Calculate Scans folder size
            if let enumerator = FileManager.default.enumerator(at: scansDir, includingPropertiesForKeys: [.fileSizeKey]) {
                for case let fileURL as URL in enumerator {
                    if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        totalSize += Int64(fileSize)
                    }
                }
            }
            
            // Calculate frames folder size
            if let enumerator = FileManager.default.enumerator(at: framesDir, includingPropertiesForKeys: [.fileSizeKey]) {
                for case let fileURL as URL in enumerator {
                    if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        totalSize += Int64(fileSize)
                    }
                }
            }
            
            // Count draft files
            if let draftFiles = try? FileManager.default.contentsOfDirectory(at: documentsDir, includingPropertiesForKeys: [.fileSizeKey]) {
                for file in draftFiles where file.lastPathComponent.hasPrefix("draft_") {
                    if let fileSize = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        totalSize += Int64(fileSize)
                    }
                }
            }
            
            DispatchQueue.main.async {
                storageSize = formatBytes(totalSize)
            }
        }
    }
    
    // V3: Delete all app data
    private func deleteAllData() {
        DispatchQueue.global(qos: .utility).async {
            guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                print("❌ [V3-DELETE] Could not access documents directory")
                return
            }
            
            let fileManager = FileManager.default
            var deletedItems = 0
            var errors: [String] = []
            
            // Delete Scans folder
            let scansDir = documentsDir.appendingPathComponent("Scans")
            if fileManager.fileExists(atPath: scansDir.path) {
                do {
                    try fileManager.removeItem(at: scansDir)
                    deletedItems += 1
                    print("✅ [V3-DELETE] Deleted Scans folder")
                } catch {
                    errors.append("Scans: \(error.localizedDescription)")
                    print("❌ [V3-DELETE] Failed to delete Scans: \(error)")
                }
            }
            
            // Delete frames folder
            let framesDir = documentsDir.appendingPathComponent("frames")
            if fileManager.fileExists(atPath: framesDir.path) {
                do {
                    try fileManager.removeItem(at: framesDir)
                    deletedItems += 1
                    print("✅ [V3-DELETE] Deleted frames folder")
                } catch {
                    errors.append("Frames: \(error.localizedDescription)")
                    print("❌ [V3-DELETE] Failed to delete frames: \(error)")
                }
            }
            
            // Delete draft autosave files
            if let contents = try? fileManager.contentsOfDirectory(at: documentsDir, includingPropertiesForKeys: nil) {
                for file in contents where file.lastPathComponent.hasPrefix("draft_") {
                    do {
                        try fileManager.removeItem(at: file)
                        deletedItems += 1
                        print("✅ [V3-DELETE] Deleted draft: \(file.lastPathComponent)")
                    } catch {
                        errors.append("Draft: \(error.localizedDescription)")
                    }
                }
            }
            
            DispatchQueue.main.async {
                if errors.isEmpty {
                    print("✅ [V3-DELETE] Successfully deleted \(deletedItems) items")
                    showingDeleteSuccess = true
                    storageSize = "0 bytes"
                } else {
                    print("⚠️ [V3-DELETE] Completed with \(errors.count) errors: \(errors.joined(separator: ", "))")
                    // Still show success but log errors
                    showingDeleteSuccess = true
                    storageSize = "Unknown"
                }
            }
        }
    }
    
    // Helper to format bytes
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }
}

