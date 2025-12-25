import SwiftUI

struct HistoryView: View {
    @State private var savedScans: [SavedScan] = []
    @State private var shareURL: URL?
    @State private var showingShareSheet = false
    
    var body: some View {
        NavigationView {
            List {
                if savedScans.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "tray")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("No saved scans")
                            .font(.headline)
                            .foregroundColor(.gray)
                        Text("Press record while scanning to save")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                } else {
                    ForEach(savedScans) { scan in
                        ScanRow(scan: scan, onShare: { url in
                            shareURL = url
                            showingShareSheet = true
                        })
                    }
                    .onDelete(perform: deleteScans)
                }
            }
            .navigationTitle("Scan History")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: loadScans) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onAppear(perform: loadScans)
            .sheet(isPresented: $showingShareSheet) {
                if let folderURL = shareURL {
                    ShareSheetWrapper(folderURL: folderURL, onDismiss: {
                        showingShareSheet = false
                    })
                } else {
                    Text("Error: No folder selected")
                        .padding()
                }
            }
        }
    }
    
    private func getFilesFromFolder(_ folderURL: URL) -> [URL] {
        print("📦 Getting files from: \(folderURL.lastPathComponent)")
        
        // Verify folder exists
        guard FileManager.default.fileExists(atPath: folderURL.path) else {
            print("❌ Folder doesn't exist: \(folderURL.path)")
            return []
        }
        
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
            
            print("  Found \(files.count) total files")
            
            // Return JSON, CSV, logs, and video files
            let shareableFiles = files.filter { file in
                let ext = file.pathExtension.lowercased()
                return ext == "json" || ext == "csv" || ext == "mp4"
            }
            
            print("  Shareable files (\(shareableFiles.count)):")
            for file in shareableFiles {
                let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
                print("    - \(file.lastPathComponent) (\(size) bytes)")
            }
            
            if shareableFiles.isEmpty {
                print("⚠️ No shareable files found!")
            }
            
            return shareableFiles
        } catch {
            print("❌ Failed to read folder: \(error.localizedDescription)")
            return []
        }
    }
    
    private func loadScans() {
        print("📂 Loading scans from history...")
        
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("❌ No documents directory")
            savedScans = []
            return
        }
        
        // Look in Documents/Scans/ where we actually save files
        let scansDir = documentsDir.appendingPathComponent("Scans")
        print("📂 Scans directory: \(scansDir.path)")
        
        guard FileManager.default.fileExists(atPath: scansDir.path) else {
            print("⚠️ Scans directory doesn't exist - will be created on first save")
            savedScans = []
            return
        }
        
        do {
            // Get all subdirectories in Scans/
            let folders = try FileManager.default.contentsOfDirectory(
                at: scansDir,
                includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey],
                options: .skipsHiddenFiles
            )
            
            print("📂 Found \(folders.count) items in Scans directory")
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601  // Match encoder strategy
            
            var allScans: [SavedScan] = []
            
            // Look inside each folder for JSON files
            for folder in folders {
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else {
                    print("⏭️ Skipping non-directory: \(folder.lastPathComponent)")
                    continue
                }
                
                print("📁 Checking folder: \(folder.lastPathComponent)")
                
                // Get JSON files inside this folder
                guard let filesInFolder = try? FileManager.default.contentsOfDirectory(
                    at: folder,
                    includingPropertiesForKeys: [.creationDateKey],
                    options: .skipsHiddenFiles
                ) else {
                    print("⚠️ Can't read folder: \(folder.lastPathComponent)")
                    continue
                }
                
                print("  Found \(filesInFolder.count) files in folder")
                
                if let jsonFile = filesInFolder.first(where: { $0.pathExtension == "json" && !$0.lastPathComponent.contains("_logs") }) {
                    print("  📄 Loading JSON: \(jsonFile.lastPathComponent)")
                    if let data = try? Data(contentsOf: jsonFile),
                       let scan = try? decoder.decode(PanelScan.self, from: data) {
                        // Store the folder URL, not the JSON file URL
                        allScans.append(SavedScan(url: folder, jsonURL: jsonFile, scan: scan))
                        print("  ✅ Loaded scan: \(scan.panelLabel)")
                    } else {
                        print("  ❌ Failed to decode: \(jsonFile.lastPathComponent)")
                    }
                } else {
                    print("  ⚠️ No JSON file found in folder")
                }
            }
            
            savedScans = allScans.sorted { $0.scan.timestamp > $1.scan.timestamp }
            
            print("✅ Successfully loaded \(savedScans.count) scans")
        } catch {
            print("❌ Failed to load scans: \(error)")
            savedScans = []
        }
    }
    
    private func deleteScans(at offsets: IndexSet) {
        for index in offsets {
            let scan = savedScans[index]
            let folderURL = scan.url
            
            // Delete entire folder
            do {
                try FileManager.default.removeItem(at: folderURL)
                print("🗑️ Deleted scan folder: \(folderURL.lastPathComponent)")
            } catch {
                print("❌ Failed to delete folder: \(error)")
            }
        }
        savedScans.remove(atOffsets: offsets)
    }
}

struct ScanRow: View {
    let scan: SavedScan
    let onShare: (URL) -> Void
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }
    
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(scan.scan.panelLabel.isEmpty ? "Unknown Panel" : scan.scan.panelLabel)
                    .font(.headline)
                
                Text("\(scan.scan.totalBreakers) breakers detected")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text(dateFormatter.string(from: scan.scan.timestamp))
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Button(action: {
                onShare(scan.url)
            }) {
                Image(systemName: "square.and.arrow.up")
                    .font(.title3)
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

struct SavedScan: Identifiable {
    let id = UUID()
    let url: URL  // Folder URL
    let jsonURL: URL  // JSON file URL for decoding
    let scan: PanelScan
}

// Wrapper to handle file loading in sheet
struct ShareSheetWrapper: View {
    let folderURL: URL
    let onDismiss: () -> Void
    
    var body: some View {
        let files = getFiles(from: folderURL)
        
        if files.isEmpty {
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 60))
                    .foregroundColor(.orange)
                Text("No files found")
                    .font(.headline)
                Text(folderURL.lastPathComponent)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("Close") {
                    onDismiss()
                }
                .padding()
            }
            .padding()
        } else {
            // Copy files to temp directory for sharing (iOS requirement)
            let tempFiles = copyToTempDirectory(files: files)
            if tempFiles.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 60))
                        .foregroundColor(.red)
                    Text("Share Error")
                        .font(.headline)
                    Text("Could not prepare files for sharing")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Close") {
                        onDismiss()
                    }
                    .padding()
                }
            } else {
                ShareSheet(items: tempFiles, onDismiss: {
                    // Cleanup temp files
                    for file in tempFiles {
                        try? FileManager.default.removeItem(at: file)
                    }
                    onDismiss()
                })
            }
        }
    }
    
    private func getFiles(from folderURL: URL) -> [URL] {
        guard FileManager.default.fileExists(atPath: folderURL.path),
              let files = try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) else {
            return []
        }
        
        return files.filter { file in
            let ext = file.pathExtension.lowercased()
            return ext == "json" || ext == "csv" || ext == "mp4"
        }
    }
    
    private func copyToTempDirectory(files: [URL]) -> [URL] {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("PanelShare_\(UUID().uuidString)")
        
        // Create temp directory
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            print("❌ [SHARE] Failed to create temp dir: \(error)")
            return []
        }
        
        var tempFiles: [URL] = []
        
        for file in files {
            let tempFile = tempDir.appendingPathComponent(file.lastPathComponent)
            do {
                try FileManager.default.copyItem(at: file, to: tempFile)
                tempFiles.append(tempFile)
                print("✅ [SHARE] Copied to temp: \(tempFile.lastPathComponent)")
            } catch {
                print("❌ [SHARE] Failed to copy \(file.lastPathComponent): \(error)")
            }
        }
        
        return tempFiles
    }
}

// Native iOS Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onDismiss: (() -> Void)? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            onDismiss?()
        }
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

