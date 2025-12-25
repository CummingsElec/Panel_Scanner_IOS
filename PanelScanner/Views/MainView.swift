import SwiftUI
import UIKit

struct MainView: View {
    @StateObject private var viewModel = ScannerViewModel()
    @EnvironmentObject var authCoordinator: AuthCoordinator
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var selectedTab = 0
    @State private var wasDetectionRunning = false
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Scanner View
            ScannerView(viewModel: viewModel)
                .tabItem {
                    Label("Scan", systemImage: "camera.viewfinder")
                }
                .tag(0)
            
            // History View
            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .tag(1)
            
            // Settings View
            SettingsView(detectionService: viewModel.detectionService)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(2)
            
            // Circuit Breaker Game
            CircuitBreakerGameView()
                .tabItem {
                    Label("Play", systemImage: "bolt.fill")
                }
                .tag(3)
            
            // Electrical Guru Chat (promoted to main tabs)
            ChatView(sessionManager: viewModel.trackingService.sessionManager)
                .tabItem {
                    Label("Guru", systemImage: "brain.head.profile")
                }
                .tag(4)
        }
        .accentColor(.blue)  // Ensure tab selection color is visible
        .onChange(of: selectedTab) { oldTab, newTab in
            // Camera/detection should ONLY run on Scanner tab (tab 0)
            // Pause on ALL other tabs to prevent resource conflicts and crashes
            
            if newTab == 0 {
                // Entering Scanner tab - RESUME camera & detection
                if oldTab != 0 {
                    print("📷 [TAB] Entering Scanner - resuming camera & detection")
                    viewModel.cameraService.startSession()
                    viewModel.detectionService.resumeDetection()
                }
            } else if oldTab == 0 {
                // Leaving Scanner tab - PAUSE everything
                print("⏸️ [TAB] Leaving Scanner (going to tab \(newTab)) - pausing camera & detection")
                viewModel.cameraService.stopSession()
                viewModel.detectionService.pauseDetection()
            }
            
            // Extra safety: Log which tab we're on
            let tabNames = ["Scanner", "History", "Settings", "Play", "Guru"]
            print("📱 [TAB] Now on: \(tabNames[newTab]) (tab \(newTab))")
        }
        .onAppear {
            // Improve tab bar visibility
            let appearance = UITabBarAppearance()
            appearance.configureWithDefaultBackground()
            
            // Selected item color
            appearance.stackedLayoutAppearance.selected.iconColor = UIColor.systemBlue
            appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.systemBlue]
            
            // Normal item color
            appearance.stackedLayoutAppearance.normal.iconColor = UIColor.systemGray
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.systemGray]
            
            UITabBar.appearance().standardAppearance = appearance
            if #available(iOS 15.0, *) {
                UITabBar.appearance().scrollEdgeAppearance = appearance
            }
        }
    }
}

// Separate Scanner View (formerly ContentView)
struct ScannerView: View {
    @ObservedObject var viewModel: ScannerViewModel
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var showingShareSheet = false
    @State private var shareURL: URL?
    @State private var showingStopAlert = false
    @State private var showDebugOverlay = false
    
    var body: some View {
        ZStack {
            // Normal Camera Mode (AR disabled - never worked reliably)
            CameraView(viewModel: viewModel)
                .edgesIgnoringSafeArea(.all)
            
            // Detection overlays
            DetectionOverlayView(
                detections: viewModel.detections,
                previewLayer: viewModel.cameraService.previewLayer
            )
            
            // OCR Confirmation Overlay
            // Show in panel mode ONLY for panel labels
            // Show in full mode for both panel labels and breakers
            if let pending = viewModel.trackingService.pendingConfirmation {
                let shouldShow = viewModel.isPanelLabelMode ? 
                    (pending.className == "panel_label") :  // Panel mode: only panel labels
                    true                                     // Full mode: everything
                
                if shouldShow {
                    OCRConfirmationOverlay(
                        confirmation: pending,
                        onConfirm: {
                            viewModel.trackingService.confirmOCR(pending)
                        },
                        onIgnore: {
                            viewModel.trackingService.ignoreOCR(pending)
                        }
                    )
                    .transition(.opacity)
                    .zIndex(1000)
                }
            }
            
            // UI Controls
            VStack {
            // Mode toggle at very top
            HStack {
                Spacer()
                
                // Panel/Full Mode Toggle
                    Button(action: {
                        viewModel.isPanelLabelMode.toggle()
                        
                        // Sync mode to tracking service immediately
                        viewModel.trackingService.isPanelLabelMode = viewModel.isPanelLabelMode
                        
                        if viewModel.isPanelLabelMode {
                            print("🔄 [MODE TOGGLE] → PANEL MODE (panel labels only)")
                        } else {
                            print("🔄 [MODE TOGGLE] → FULL MODE (all detections)")
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: viewModel.isPanelLabelMode ? "tag.fill" : "viewfinder")
                            Text(viewModel.isPanelLabelMode ? "PANEL MODE" : "FULL MODE")
                                .font(.system(.caption, design: .monospaced))
                                .fontWeight(.bold)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(viewModel.isPanelLabelMode ? Color.orange : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(20)
                    }
                
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 8)
                
            // Top bar - stats
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                            Text("FPS: \(viewModel.fps, specifier: "%.0f")")
                                .font(.system(.caption, design: .monospaced))
                            Text("Breakers: \(viewModel.breakerCount)")
                                .font(.system(.caption, design: .monospaced))
                            Text("Panel: \(viewModel.panelLabel)")
                                .font(.system(.caption, design: .monospaced))
                            if viewModel.cumulativeBreakerCount > 0 {
                                Text("Total Captured: \(viewModel.cumulativeBreakerCount)")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.green)
                            }
                            if viewModel.isRecording {
                                Text("Frames: \(viewModel.recordedFrameCount)")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.red)
                            }
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(10)
                        .onLongPressGesture(minimumDuration: 2.0) {
                            // Hidden debug gesture
                            #if DEBUG
                            settingsStore.showDebugOverlay.toggle()
                            #else
                            if settingsStore.isLocalModeEnabled {
                                settingsStore.showDebugOverlay.toggle()
                            }
                            #endif
                    }
                    
                    Spacer()
                    
                    // Debug overlay (if enabled)
                    if settingsStore.showDebugOverlay {
                            VStack {
                                DebugOverlayView(settingsStore: settingsStore, viewModel: viewModel)
                                
                                // Only show console if not recording (to avoid Metal rendering issues)
                                if !viewModel.isRecording {
                                    DebugConsoleView()
                                        .frame(height: 200)
                                        .cornerRadius(10)
                                        .padding()
                                } else {
                                    Text("Debug console hidden during recording")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                        .padding()
                                }
                        }
                        .transition(.opacity)
                    }
                    
                    Spacer()
                    
                    // Recording indicator
                    if viewModel.isRecording {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 12, height: 12)
                                Text("REC")
                                    .font(.system(.caption, design: .monospaced))
                                    .fontWeight(.bold)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .cornerRadius(20)
                    }
                }
                .padding()
            
            Spacer()
            
            // Bottom controls
            VStack(spacing: 12) {
                    // Record/stop button
                    Button(action: {
                        if viewModel.isRecording {
                            showingStopAlert = true
                        } else {
                            viewModel.toggleRecording()
                        }
                    }) {
                        Image(systemName: viewModel.isRecording ? "stop.circle.fill" : "record.circle")
                            .font(.system(size: 70))
                            .foregroundColor(viewModel.isRecording ? .red : .white)
                            .opacity(viewModel.isBusy ? 0.3 : 1.0)  // Visual feedback
                    }
                    .disabled(viewModel.isBusy)  // Block recording when busy
            }
            .padding(.bottom, 40)
            }
        }
        .statusBar(hidden: true)
        .sheet(isPresented: Binding(
            get: { showingShareSheet && shareURL != nil },
            set: { showingShareSheet = $0 }
        ), onDismiss: {
            // FIX: Reset session AFTER share sheet dismisses (ZIP/upload complete)
            print("📤 Share sheet dismissed - resetting session")
            viewModel.trackingService.resetSession()
            viewModel.trackingService.resetSessionManager()
            viewModel.isBusy = false  // Unblock UI
            
            // Clear share URL
            shareURL = nil
            
            // RESUME CAMERA after save/upload completes
            print("▶️ Resuming camera after save complete")
            viewModel.cameraService.startSession()
        }) {
            if let jsonURL = shareURL {
                shareView(for: jsonURL)
            } else {
                // This should never show now due to binding check above
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .padding()
                    Text("Preparing share...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .alert("Stop Recording?", isPresented: $showingStopAlert) {
            Button("Keep Recording", role: .cancel) { }
            Button("Stop & Save") {
                print("🛑 USER TAPPED STOP & SAVE")
                
                // PAUSE CAMERA to free resources during save/upload
                print("⏸️ Pausing camera during save process...")
                viewModel.cameraService.stopSession()
                
                // Stop recording first
                viewModel.toggleRecording()
                
                // Wait for video to finish writing (check callback instead of fixed delay)
                print("⏳ Waiting for video to finalize...")
                
                // Poll for video completion (max 5 seconds)
                var attempts = 0
                func checkAndSave() {
                    attempts += 1
                    
                    // Check if video exists and is finalized (size > 0)
                    if let videoURL = viewModel.currentVideoURL,
                       FileManager.default.fileExists(atPath: videoURL.path),
                       let attrs = try? FileManager.default.attributesOfItem(atPath: videoURL.path),
                       let size = attrs[FileAttributeKey.size] as? Int,
                       size > 0 {
                        
                        print("✅ Video ready (\(size) bytes), saving now...")
                        viewModel.saveAndShare { url in
                            if let url = url {
                                print("✅ Save completed: \(url.lastPathComponent)")
                                // Set URL first, then show sheet after a brief delay to ensure state propagates
                                shareURL = url
                                
                                // Delay sheet presentation to ensure shareURL is set in SwiftUI's state
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    showingShareSheet = true
                                }
                                
                                // DON'T reset here - wait until share sheet dismisses
                            } else {
                                print("❌ Save failed")
                                viewModel.isBusy = false  // Unblock on failure
                            }
                        }
                    } else if attempts < 10 {
                        print("⏳ Video not ready yet (attempt \(attempts)/10)...")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            checkAndSave()
                        }
                    } else {
                        print("⚠️ Video timeout - saving anyway")
                        viewModel.saveAndShare { url in
                            if let url = url {
                                print("✅ Save completed after timeout: \(url.lastPathComponent)")
                                shareURL = url
                                
                                // Delay sheet presentation to ensure shareURL is set
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    showingShareSheet = true
                                }
                                // DON'T reset here - wait until share sheet dismisses
                            } else {
                                print("❌ Save failed after timeout")
                                viewModel.isBusy = false  // Unblock on failure
                            }
                        }
                    }
                }
                
                // Start checking after brief delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    checkAndSave()
                }
            }
            Button("Discard", role: .destructive) {
                print("🗑️ USER CHOSE TO DISCARD")
                
                // Stop recording
                viewModel.isRecording = false
                viewModel.trackingService.sessionManager.isRecording = false
                
                // Delete video file if it exists
                if let videoURL = viewModel.currentVideoURL {
                    try? FileManager.default.removeItem(at: videoURL)
                    print("🗑️ Deleted video file: \(videoURL.lastPathComponent)")
                }
                
                // Clear video URL and reset session completely
                viewModel.currentVideoURL = nil
                viewModel.trackingService.resetSession()
                viewModel.trackingService.resetSessionManager()
                
                print("✅ Recording discarded, session reset")
            }
        } message: {
            Text("Recorded \(viewModel.recordedFrameCount) frames. Save, discard, or keep recording?")
        }
    }
    
    @ViewBuilder
    private func shareView(for url: URL) -> some View {
        // Check if OneDriveService returned a ZIP file
        if url.pathExtension.lowercased() == "zip" {
            let _ = print("📦 Sharing ZIP: \(url.lastPathComponent)")
            ShareSheet(items: [url])
        } else {
            // Fallback: ZIP creation failed, share individual files
            let folderURL = url.deletingLastPathComponent()
            let _ = print("📤 ZIP not available, sharing files from: \(folderURL.lastPathComponent)")
            
            let files = (try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)) ?? []
            let shareableFiles = files.filter { file in
                let ext = file.pathExtension.lowercased()
                return ext == "json" || ext == "csv" || ext == "mp4"
            }
            
            if !shareableFiles.isEmpty {
                let _ = print("📤 Sharing \(shareableFiles.count) individual files")
                ShareSheet(items: shareableFiles)
            } else {
                let _ = print("⚠️ No files found, sharing JSON only")
                ShareSheet(items: [url])
            }
        }
    }
}
