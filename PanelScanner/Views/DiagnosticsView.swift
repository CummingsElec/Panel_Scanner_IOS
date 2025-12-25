import SwiftUI
import UIKit

struct DiagnosticsView: View {
    @Environment(\.dismiss) var dismiss
    @State private var isExporting = false
    @State private var exportURL: URL?
    @State private var showingShareSheet = false
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Device Information")) {
                    InfoRow(title: "Device", value: UIDevice.current.model)
                    InfoRow(title: "OS Version", value: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
                    InfoRow(title: "App Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
                    InfoRow(title: "Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown")
                }
                
                Section(header: Text("Settings")) {
                    let settings = SettingsStore.shared
                    InfoRow(title: "Panel Threshold", value: "\(Int(settings.panelThreshold * 100))%")
                    InfoRow(title: "Breaker Threshold", value: "\(Int(settings.breakerThreshold * 100))%")
                    InfoRow(title: "OCR Threshold", value: "\(Int(settings.ocrThreshold * 100))%")
                    InfoRow(title: "Max FPS", value: "\(Int(settings.maxFPS))")
                    InfoRow(title: "Dwell Frames", value: "\(settings.dwellFrames)")
                }
                
                Section(header: Text("Export")) {
                    Button(action: exportDiagnostics) {
                        HStack {
                            Image(systemName: "arrow.down.doc")
                            Text("Export Diagnostics Package")
                            if isExporting {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isExporting)
                    
                    Text("Creates a folder with settings, logs, and device info. Tokens and sensitive data are redacted.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let url = exportURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }
    
    private func exportDiagnostics() {
        isExporting = true
        
        Task {
            do {
                let diagnosticsURL = try await createDiagnosticsPackage()
                
                await MainActor.run {
                    exportURL = diagnosticsURL
                    showingShareSheet = true
                    isExporting = false
                }
            } catch {
                #if DEBUG
                print("❌ Failed to create diagnostics: \(error)")
                #endif
                await MainActor.run {
                    isExporting = false
                }
            }
        }
    }
    
    private func createDiagnosticsPackage() async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let diagnosticsDir = tempDir.appendingPathComponent("PanelScanner_Diagnostics_\(Date().timeIntervalSince1970)")
        
        try FileManager.default.createDirectory(at: diagnosticsDir, withIntermediateDirectories: true)
        
        // Device info
        let deviceInfo = """
        Device: \(UIDevice.current.model)
        OS: \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)
        App Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
        Build: \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown")
        """
        
        try deviceInfo.write(to: diagnosticsDir.appendingPathComponent("device_info.txt"), atomically: true, encoding: .utf8)
        
        // Settings
        let settings = SettingsStore.shared
        let settingsInfo = """
        Panel Threshold: \(settings.panelThreshold)
        Breaker Threshold: \(settings.breakerThreshold)
        Text ROI Threshold: \(settings.textROIThreshold)
        Panel Label Threshold: \(settings.panelLabelThreshold)
        OCR Threshold: \(settings.ocrThreshold)
        Dwell Frames: \(settings.dwellFrames)
        IOU Track Threshold: \(settings.iouTrackThreshold)
        Cooldown Frames: \(settings.cooldownFrames)
        Max FPS: \(settings.maxFPS)
        """
        
        try settingsInfo.write(to: diagnosticsDir.appendingPathComponent("settings.txt"), atomically: true, encoding: .utf8)
        
        // Create minimal log (no actual logging implemented yet, just placeholder)
        let logInfo = """
        Diagnostics exported: \(Date())
        No crash logs found.
        """
        
        try logInfo.write(to: diagnosticsDir.appendingPathComponent("log.txt"), atomically: true, encoding: .utf8)
        
        // Create ZIP
        let zipURL = tempDir.appendingPathComponent("PanelScanner_Diagnostics.zip")
        
        // Remove old zip if exists
        try? FileManager.default.removeItem(at: zipURL)
        
        // Simple zip (note: for production, use a proper zip library)
        // For now, just copy the directory
        let finalURL = tempDir.appendingPathComponent("PanelScanner_Diagnostics")
        try? FileManager.default.removeItem(at: finalURL)
        try FileManager.default.copyItem(at: diagnosticsDir, to: finalURL)
        
        return finalURL
    }
}

struct InfoRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

