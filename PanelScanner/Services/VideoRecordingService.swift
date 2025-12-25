import AVFoundation
import CoreImage
import UIKit

class VideoRecordingService {
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    
    private var isRecording = false
    private var isFinalizing = false  // FIX: Prevent starting new recording while finalizing
    private var isPaused = false  // V3 FIX: Track pause state for background handling
    private var startTime: CMTime?
    private var outputURL: URL?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    
    private let videoQueue = DispatchQueue(label: "com.panelscanner.videorecording", qos: .userInitiated)
    
    // V3 FIX: Callback for when background finalization completes
    private var backgroundFinalizationCallback: ((URL?) -> Void)?
    
    // V3 FIX: Background/foreground observers
    init() {
        setupBackgroundObservers()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        endBackgroundTask()
    }
    
    private func setupBackgroundObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    @objc private func handleAppDidEnterBackground() {
        guard isRecording && !isFinalizing else { return }
        
        print("📱 [V3-VIDEO] App backgrounded - finalizing video to prevent data loss")
        
        // V3 FIX: Start background task to finalize video safely
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            // If we run out of time, end the task
            self?.endBackgroundTask()
        }
        
        // Finalize the recording in background
        stopRecording { [weak self] url in
            print("📱 [V3-VIDEO] Background finalization complete: \(url != nil ? "✅" : "❌")")
            self?.backgroundFinalizationCallback?(url)
            self?.endBackgroundTask()
        }
    }
    
    @objc private func handleAppWillEnterForeground() {
        // Recording was already finalized on background
        // User will need to start a new recording if they want to continue
        print("📱 [V3-VIDEO] App foregrounded - recording was finalized on background")
    }
    
    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
    
    func startRecording(outputURL: URL, frameSize: CGSize) -> Bool {
        // FIX: Guard against starting while previous recording is finalizing
        guard !isFinalizing else {
            print("⚠️ VIDEO: Cannot start - previous recording still finalizing")
            return false
        }
        
        self.outputURL = outputURL
        
        // Remove existing file if any
        try? FileManager.default.removeItem(at: outputURL)
        
        do {
            assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
            
            // CRITICAL: Swap dimensions for portrait video
            // Camera gives landscape (1920x1080), we want portrait (1080x1920)
            let portraitWidth = frameSize.height
            let portraitHeight = frameSize.width
            
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: portraitWidth,   // Swapped
                AVVideoHeightKey: portraitHeight,  // Swapped
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 6_000_000, // 6 Mbps for good quality
                    AVVideoMaxKeyFrameIntervalKey: 30
                ]
            ]
            
            videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput?.expectsMediaDataInRealTime = true
            
            // NO rotation transform needed - dimension swap handles it
            // videoInput?.transform = .identity (default)
            
            // Source pixel buffers are still in landscape from camera
            let sourcePixelBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: frameSize.width,   // Keep landscape for source
                kCVPixelBufferHeightKey as String: frameSize.height  // Transform rotates it
            ]
            
            pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: videoInput!,
                sourcePixelBufferAttributes: sourcePixelBufferAttributes
            )
            
            if let videoInput = videoInput, assetWriter?.canAdd(videoInput) == true {
                assetWriter?.add(videoInput)
            } else {
                print("❌ VIDEO: Cannot add video input to asset writer")
                return false
            }
            
            if assetWriter?.startWriting() == true {
                assetWriter?.startSession(atSourceTime: .zero)
                isRecording = true
                isPaused = false  // V3 FIX: Reset pause state
                startTime = nil
                print("""
                🎥 [VIDEO] Recording Started:
                  File: \(outputURL.lastPathComponent)
                  Source: \(frameSize.width)×\(frameSize.height) (landscape)
                  Output: \(portraitWidth)×\(portraitHeight) (portrait - rotated 90°)
                  Codec: H.264
                  Bitrate: 6 Mbps
                """)
                return true
            } else {
                print("❌ VIDEO: Failed to start writing: \(assetWriter?.error?.localizedDescription ?? "unknown")")
                return false
            }
            
        } catch {
            print("❌ VIDEO: Failed to create asset writer: \(error)")
            return false
        }
    }
    
    func recordFrame(sampleBuffer: CMSampleBuffer) {
        // V3 FIX: Don't record frames when paused (backgrounded)
        guard isRecording,
              !isPaused,
              let videoInput = videoInput,
              let pixelBufferAdaptor = pixelBufferAdaptor,
              videoInput.isReadyForMoreMediaData else {
            return
        }
        
        videoQueue.async { [weak self] in
            guard let self = self else { return }
            
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            
            if self.startTime == nil {
                self.startTime = presentationTime
            }
            
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                return
            }
            
            let adjustedTime = CMTimeSubtract(presentationTime, self.startTime ?? .zero)
            
            if !pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: adjustedTime) {
                if let error = self.assetWriter?.error {
                    print("❌ VIDEO: Failed to append frame: \(error)")
                }
            }
        }
    }
    
    func stopRecording(completion: @escaping (URL?) -> Void) {
        guard isRecording else {
            completion(nil)
            return
        }
        
        isRecording = false
        isFinalizing = true  // FIX: Block new recordings until finalized
        print("🎬 [VIDEO] Finalizing... (blocking new recordings)")
        
        videoQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            self.videoInput?.markAsFinished()
            
            self.assetWriter?.finishWriting { [weak self] in
                guard let self = self else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                
                if self.assetWriter?.status == .completed {
                    let fileSize = (try? FileManager.default.attributesOfItem(atPath: self.outputURL?.path ?? ""))?[.size] as? Int64 ?? 0
                    let sizeMB = Double(fileSize) / 1_048_576.0
                    
                    print("✅ VIDEO RECORDING SAVED:")
                    print("  File: \(self.outputURL?.lastPathComponent ?? "unknown")")
                    print("  Size: \(String(format: "%.2f", sizeMB)) MB")
                    print("  Location: \(self.outputURL?.deletingLastPathComponent().path ?? "unknown")")
                    
                    self.isFinalizing = false  // FIX: Unblock new recordings
                    DispatchQueue.main.async {
                        completion(self.outputURL)
                    }
                } else {
                    print("❌ VIDEO: Recording failed with status: \(self.assetWriter?.status.rawValue ?? -1)")
                    if let error = self.assetWriter?.error {
                        print("  Error: \(error)")
                    }
                    self.isFinalizing = false  // FIX: Unblock even on error
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                }
                
                self.assetWriter = nil
                self.videoInput = nil
                self.pixelBufferAdaptor = nil
                self.startTime = nil
            }
        }
    }
}

