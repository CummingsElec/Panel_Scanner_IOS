import CoreGraphics
import CoreImage

class TrackState {
    var id: String
    var bbox: CGRect
    var className: String
    var confidence: Float
    var smoothedConfidence: Float
    var dwellCount: Int = 0
    var cooldownFrames: Int = 0
    var text: String?
    var ocrConfidence: Float = 0
    var isCaptured: Bool = false
    var lastSeenFrame: Int = 0
    var pendingFrame: CIImage?  // Store frame for confirmation
    var lastOCRStartTime: Date?  // Track OCR timing for diagnostics
    
    init(id: String, bbox: CGRect, className: String, confidence: Float) {
        self.id = id
        self.bbox = bbox
        self.className = className
        self.confidence = confidence
        self.smoothedConfidence = confidence
    }
    
    func update(bbox: CGRect, confidence: Float, frameNumber: Int) {
        self.bbox = bbox
        self.confidence = confidence
        // EMA smoothing (alpha = 0.3)
        self.smoothedConfidence = 0.3 * confidence + 0.7 * smoothedConfidence
        self.lastSeenFrame = frameNumber
    }
    
    func incrementDwell() {
        dwellCount += 1
    }
    
    func resetDwell() {
        dwellCount = 0
    }
    
    func startCooldown(_ frames: Int) {
        cooldownFrames = frames
        isCaptured = true
    }
    
    func decrementCooldown() {
        if cooldownFrames > 0 {
            cooldownFrames -= 1
        }
    }
    
    // Calculate IOU with another track
    func iou(with other: TrackState) -> Float {
        return calculateIOU(bbox, other.bbox)
    }
    
    // Calculate center distance
    func centerDistance(to other: TrackState) -> Float {
        let center1 = CGPoint(x: bbox.midX, y: bbox.midY)
        let center2 = CGPoint(x: other.bbox.midX, y: other.bbox.midY)
        let dx = center1.x - center2.x
        let dy = center1.y - center2.y
        return sqrt(Float(dx * dx + dy * dy))
    }
}

// Helper function
func calculateIOU(_ box1: CGRect, _ box2: CGRect) -> Float {
    let intersection = box1.intersection(box2)
    if intersection.isNull { return 0.0 }
    
    let intersectionArea = intersection.width * intersection.height
    let union = box1.width * box1.height + box2.width * box2.height - intersectionArea
    
    return Float(intersectionArea / union)
}

