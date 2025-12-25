import Foundation
import CoreGraphics
import UIKit

class SessionManager: ObservableObject {
    @Published var panelPartNumber: String?
    @Published var capturedBreakers: [CapturedItem] = []
    @Published var sessionStartTime: Date = Date()
    @Published var isRecording: Bool = false
    
    private var eventLog: [String] = []
    private var autosaveTimer: Timer?
    
    init() {
        startAutosave()
    }
    
    // V3 FIX: Clean up timer on deallocation to prevent leaks
    deinit {
        autosaveTimer?.invalidate()
        autosaveTimer = nil
        print("🔄 [V3] SessionManager deallocated - timer cleaned up")
    }
    
    func addEvent(_ event: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        eventLog.append("[\(timestamp)] \(event)")
    }
    
    func capturePanel(partNumber: String, confidence: Float, image: UIImage?) {
        panelPartNumber = partNumber
        addEvent("Panel captured: \(partNumber) (conf: \(confidence))")
        
        if let image = image {
            saveFrameCrop(image: image, filename: "panel_\(partNumber)")
        }
    }
    
    func captureBreaker(partNumber: String, confidence: Float, ocrConfidence: Float, isValid: Bool, bbox: CGRect, image: UIImage?) {
        let item = CapturedItem(
            index: capturedBreakers.count + 1,
            partNumber: partNumber,
            confidence: confidence,
            ocrConfidence: ocrConfidence,
            isValid: isValid,
            bbox: bbox,
            timestamp: Date()
        )
        
        capturedBreakers.append(item)
        addEvent("Breaker #\(item.index) captured: \(partNumber) (valid: \(isValid), conf: \(confidence), ocr: \(ocrConfidence))")
        
        if let image = image {
            saveFrameCrop(image: image, filename: "breaker_\(item.index)_\(partNumber)")
        }
    }
    
    func updateBreaker(at index: Int, partNumber: String) {
        guard index < capturedBreakers.count else { return }
        capturedBreakers[index].partNumber = partNumber
        capturedBreakers[index].isManuallyEdited = true
        addEvent("Breaker #\(index + 1) edited: \(partNumber)")
    }
    
    func deleteBreaker(at index: Int) {
        guard index < capturedBreakers.count else { return }
        let item = capturedBreakers.remove(at: index)
        addEvent("Breaker #\(index + 1) deleted: \(item.partNumber)")
        
        // Reindex
        for i in 0..<capturedBreakers.count {
            capturedBreakers[i].index = i + 1
        }
    }
    
    func resetSession() {
        // CRITICAL: Must be called on main thread (these are @Published)
        if Thread.isMainThread {
            panelPartNumber = nil
            capturedBreakers = []
            eventLog = []
            sessionStartTime = Date()
            addEvent("Session reset")
            print("🔄 Session reset complete")
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.resetSession()
            }
        }
    }
    
    private func startAutosave() {
        // V3 FIX: Invalidate existing timer before creating new one
        autosaveTimer?.invalidate()
        autosaveTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.autosave()
        }
    }
    
    // V3 FIX: Public method to stop autosave (called when recording stops)
    func stopAutosave() {
        autosaveTimer?.invalidate()
        autosaveTimer = nil
    }
    
    private func autosave() {
        guard !capturedBreakers.isEmpty || panelPartNumber != nil else { return }
        
        let filename = "draft_\(Int(Date().timeIntervalSince1970)).json"
        if let url = getDocumentsURL()?.appendingPathComponent(filename),
           let data = try? JSONEncoder().encode(exportData()) {
            try? data.write(to: url)
            print("📝 Autosaved: \(filename)")
        }
    }
    
    func exportSession() -> URL? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        
        let panelName = panelPartNumber?.replacingOccurrences(of: "/", with: "-") ?? "UNSET"
        let baseFilename = "\(panelName)__\(timestamp)"
        
        guard let documentsURL = getDocumentsURL() else { return nil }
        
        // Export JSON
        let jsonURL = documentsURL.appendingPathComponent("\(baseFilename).json")
        let exportData = self.exportData()
        
        if let jsonData = try? JSONEncoder().encode(exportData) {
            try? jsonData.write(to: jsonURL)
            addEvent("Exported to \(baseFilename).json")
        }
        
        // Export CSV
        let csvURL = documentsURL.appendingPathComponent("\(baseFilename).csv")
        let csvData = generateCSV()
        try? csvData.write(to: csvURL, atomically: true, encoding: .utf8)
        
        return jsonURL
    }
    
    private func exportData() -> SessionExport {
        return SessionExport(
            sessionStart: sessionStartTime,
            sessionEnd: Date(),
            panelPartNumber: panelPartNumber,
            breakers: capturedBreakers.map { BreakerExport(
                index: $0.index,
                partNumber: $0.partNumber,
                confidence: $0.confidence,
                ocrConfidence: $0.ocrConfidence,
                isValid: $0.isValid,
                isManuallyEdited: $0.isManuallyEdited,
                bbox: ["x": $0.bbox.origin.x, "y": $0.bbox.origin.y, "w": $0.bbox.width, "h": $0.bbox.height],
                timestamp: $0.timestamp
            )},
            eventLog: eventLog
        )
    }
    
    private func generateCSV() -> String {
        var csv = "Index,Part Number,Confidence,OCR Confidence,Valid,Manually Edited,X,Y,Width,Height\n"
        
        for item in capturedBreakers {
            csv += "\(item.index),\(item.partNumber),\(item.confidence),\(item.ocrConfidence),\(item.isValid),\(item.isManuallyEdited),\(item.bbox.origin.x),\(item.bbox.origin.y),\(item.bbox.width),\(item.bbox.height)\n"
        }
        
        return csv
    }
    
    private func saveFrameCrop(image: UIImage, filename: String) {
        guard let documentsURL = getDocumentsURL() else { return }
        let framesDir = documentsURL.appendingPathComponent("frames")
        
        try? FileManager.default.createDirectory(at: framesDir, withIntermediateDirectories: true)
        
        let imageURL = framesDir.appendingPathComponent("\(filename).jpg")
        if let data = image.jpegData(compressionQuality: 0.8) {
            try? data.write(to: imageURL)
        }
    }
    
    private func getDocumentsURL() -> URL? {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }
}

struct CapturedItem: Identifiable, Codable {
    let id = UUID()
    var index: Int
    var partNumber: String
    var confidence: Float
    var ocrConfidence: Float
    var isValid: Bool
    var bbox: CGRect
    var timestamp: Date
    var isManuallyEdited: Bool = false
    
    enum CodingKeys: String, CodingKey {
        case index, partNumber, confidence, ocrConfidence, isValid, timestamp, isManuallyEdited
        case x, y, width, height
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(index, forKey: .index)
        try container.encode(partNumber, forKey: .partNumber)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(ocrConfidence, forKey: .ocrConfidence)
        try container.encode(isValid, forKey: .isValid)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(isManuallyEdited, forKey: .isManuallyEdited)
        try container.encode(bbox.origin.x, forKey: .x)
        try container.encode(bbox.origin.y, forKey: .y)
        try container.encode(bbox.width, forKey: .width)
        try container.encode(bbox.height, forKey: .height)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = try container.decode(Int.self, forKey: .index)
        partNumber = try container.decode(String.self, forKey: .partNumber)
        confidence = try container.decode(Float.self, forKey: .confidence)
        ocrConfidence = try container.decode(Float.self, forKey: .ocrConfidence)
        isValid = try container.decode(Bool.self, forKey: .isValid)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        isManuallyEdited = try container.decode(Bool.self, forKey: .isManuallyEdited)
        
        let x = try container.decode(CGFloat.self, forKey: .x)
        let y = try container.decode(CGFloat.self, forKey: .y)
        let width = try container.decode(CGFloat.self, forKey: .width)
        let height = try container.decode(CGFloat.self, forKey: .height)
        bbox = CGRect(x: x, y: y, width: width, height: height)
    }
    
    init(index: Int, partNumber: String, confidence: Float, ocrConfidence: Float, isValid: Bool, bbox: CGRect, timestamp: Date) {
        self.index = index
        self.partNumber = partNumber
        self.confidence = confidence
        self.ocrConfidence = ocrConfidence
        self.isValid = isValid
        self.bbox = bbox
        self.timestamp = timestamp
    }
}

struct SessionExport: Codable {
    let sessionStart: Date
    let sessionEnd: Date
    let panelPartNumber: String?
    let breakers: [BreakerExport]
    let eventLog: [String]
}

struct BreakerExport: Codable {
    let index: Int
    let partNumber: String
    let confidence: Float
    let ocrConfidence: Float
    let isValid: Bool
    let isManuallyEdited: Bool
    let bbox: [String: CGFloat]
    let timestamp: Date
}

