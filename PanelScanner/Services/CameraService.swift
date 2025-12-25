import AVFoundation
import UIKit
import Combine

class CameraService: NSObject, ObservableObject {
    @Published var currentFrame: CIImage?
    @Published var isRunning: Bool = false
    @Published var videoDimensions: CGSize = CGSize(width: 1920, height: 1080)  // Default, updated on setup
    
    let previewLayer: AVCaptureVideoPreviewLayer
    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session")
    
    private var isConfigured = false
    
    // V3 FIX: Only post sample buffer notifications when actually needed
    var shouldPostVideoFrames: Bool = false
    
    override init() {
        self.previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init()
        
        // Setup notifications for app lifecycle
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
        
        sessionQueue.async { [weak self] in
            self?.setupCamera()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleAppDidEnterBackground() {
        print("📱 APP → BACKGROUND - Stopping camera")
        stopSession()
    }
    
    @objc private func handleAppWillEnterForeground() {
        print("📱 APP → FOREGROUND - Starting camera")
        startSession()
    }
    
    private func setupCamera() {
        guard !isConfigured else { return }
        
        session.beginConfiguration()
        session.sessionPreset = .hd1920x1080  // High quality for YOLO
        
        // Check camera permission
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureCameraInput()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.sessionQueue.async {
                        self?.configureCameraInput()
                    }
                }
            }
        default:
            #if DEBUG
            print("❌ Camera permission denied")
            #endif
            session.commitConfiguration()
            return
        }
        
        session.commitConfiguration()
        isConfigured = true
    }
    
    private func configureCameraInput() {
        // Add camera input
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            #if DEBUG
            print("❌ Camera setup failed")
            #endif
            return
        }
        
        if session.canAddInput(input) {
            session.addInput(input)
        }
        
        // Get actual video dimensions from camera format
        let dimensions = CMVideoFormatDescriptionGetDimensions(camera.activeFormat.formatDescription)
        let videoSize = CGSize(width: CGFloat(dimensions.width), height: CGFloat(dimensions.height))
        DispatchQueue.main.async {
            self.videoDimensions = videoSize
            print("""
            📹 [CAMERA] Setup Complete:
              Sensor dimensions: \(videoSize.width)×\(videoSize.height)
              Device: \(camera.localizedName)
              Format: \(camera.activeFormat)
              Note: Dimensions are SENSOR orientation (typically landscape)
            """)
        }
        
        // Configure video output
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
        
        // Set video orientation
        if let connection = videoOutput.connection(with: .video) {
            connection.videoOrientation = .portrait
        }
    }
    
    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self = self, !self.session.isRunning else { return }
            print("📷 CAMERA SESSION STARTING")
            self.session.startRunning()
            DispatchQueue.main.async {
                self.isRunning = true
                print("📷 CAMERA SESSION RUNNING")
            }
        }
    }
    
    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self = self, self.session.isRunning else { return }
            print("📷 CAMERA SESSION STOPPING")
            self.session.stopRunning()
            DispatchQueue.main.async {
                self.isRunning = false
                print("📷 CAMERA SESSION STOPPED")
            }
        }
    }
    
    func pauseSession() {
        stopSession()
    }
    
    func resumeSession() {
        startSession()
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        DispatchQueue.main.async {
            self.currentFrame = ciImage
        }
        
        // V3 FIX: Only post video frames when recording to prevent buffer leak
        // Previously this was posted EVERY frame regardless of listeners
        // Now we gate it behind shouldPostVideoFrames flag set by ViewModel
        guard shouldPostVideoFrames else { return }
        
        // Post notification with sample buffer for video recording
        // Wrap in Unmanaged and pass as NSValue to work with NSNotification
        let retained = Unmanaged.passRetained(sampleBuffer)
        let pointer = retained.toOpaque()
        let nsValue = NSValue(pointer: pointer)
        
        NotificationCenter.default.post(
            name: .videoFrameCaptured,
            object: nil,
            userInfo: ["sampleBuffer": nsValue]
        )
    }
}

extension Notification.Name {
    static let videoFrameCaptured = Notification.Name("videoFrameCaptured")
}

