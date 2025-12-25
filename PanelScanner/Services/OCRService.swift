import Vision
import CoreImage

class OCRService {
    private let recognitionLevel: VNRequestTextRecognitionLevel = .accurate
    private let allowedCharacters = AppConfig.OCR.allowedCharacters
    private let partNumberPatterns = AppConfig.OCR.partNumberPatterns
    
    // Blacklist: Manufacturer names and common words to reject
    private let blacklistedWords: [String] = [
        "POWERPACT", "SCHNEIDER", "SQUARE", "EATON", "SIEMENS", 
        "GENERAL", "ELECTRIC", "CUTLER", "HAMMER",
        "PRINCIPAL", "PRINCIPAI", "BREAKER", "PANEL",
        "MAIN", "SQUARED"
    ]
    
    // Known breaker part numbers (helps Vision framework accuracy)
    private let knownPartNumbers: [String] = [
        "22000A",
        "BJA260201", "BJA260202", "BJA260204",
        "BJA260401", "BJA260402", "BJA260404",
        "BJA260501", "BJA260502", "BJA260504",
        "BJA260601", "BJA260602", "BJA260604",
        "BJA260801", "BJA260802", "BJA260804",
        "BJA261001", "BJA261002", "BJA261004",
        "BJA36020", "BJA36030", "BJA36040", "BJA36050", "BJA36060", "BJA36080", "BJA36100",
        "HJA36150", "JJA36225",
        "LJA36400U31X", "LJA36600U31X",
        "QJA221501", "QJA32225",
        "BDA36050", "BDA36080",
        "BGA24060Y2", "BGA260401", "BGA3450Y", "BGA36020", "BGA36050", "BGA36080",
        "BJA26040",
        "HLW-1BL", "HLW-4BL",
        "HNM-1BL", "HNM-4BL",
        "PKDGWG",
        "QOB-20", "QOB-40"
    ]
    
    func recognizeText(in image: CIImage, completion: @escaping (OCRResult?) -> Void) {
        let request = VNRecognizeTextRequest { request, error in
            guard error == nil,
                  let observations = request.results as? [VNRecognizedTextObservation],
                  let topCandidate = observations.first?.topCandidates(1).first else {
                completion(nil)
                return
            }
            
            let normalized = self.normalizeText(topCandidate.string)
            
            // Try exact match first
            if self.knownPartNumbers.contains(normalized) {
                completion(OCRResult(
                    text: normalized,
                    confidence: topCandidate.confidence,
                    isValid: true
                ))
                return
            }
            
            // Try fuzzy match against known parts (handles OCR errors)
            if let bestMatch = self.findBestMatch(for: normalized) {
                completion(OCRResult(
                    text: bestMatch,
                    confidence: topCandidate.confidence * 0.95,  // Slight penalty for fuzzy match
                    isValid: true
                ))
                return
            }
            
            // Fall back to pattern validation
            let isValid = self.validatePartNumber(normalized)
            
            completion(OCRResult(
                text: normalized,
                confidence: topCandidate.confidence,
                isValid: isValid
            ))
        }
        
        request.recognitionLevel = recognitionLevel
        request.usesLanguageCorrection = false
        request.customWords = knownPartNumbers  // Hint to Vision framework
        
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        try? handler.perform([request])
    }
    
    private func findBestMatch(for text: String) -> String? {
        var bestMatch: String?
        var bestDistance = 3  // Max 3 character difference
        
        for known in knownPartNumbers {
            let distance = fuzzyDistance(text, known)
            if distance < bestDistance {
                bestDistance = distance
                bestMatch = known
            }
        }
        
        return bestMatch
    }
    
    private func normalizeText(_ text: String) -> String {
        // Uppercase, trim, collapse dashes
        var normalized = text.uppercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
        
        // Collapse multiple dashes
        while normalized.contains("--") {
            normalized = normalized.replacingOccurrences(of: "--", with: "-")
        }
        
        // Filter to allowed characters
        normalized = String(normalized.filter { allowedCharacters.contains($0) })
        
        return normalized
    }
    
    private func validatePartNumber(_ text: String) -> Bool {
        guard text.count >= 3 && text.count <= 20 else { return false }
        
        // Reject blacklisted manufacturer names
        if blacklistedWords.contains(text) {
            return false
        }
        
        // Check against patterns
        for pattern in partNumberPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                return true
            }
        }
        
        return false
    }
    
    // Levenshtein distance for fuzzy matching
    func fuzzyDistance(_ s1: String, _ s2: String) -> Int {
        // Safety check for empty strings
        guard !s1.isEmpty && !s2.isEmpty else {
            return max(s1.count, s2.count)
        }
        
        let m = s1.count, n = s2.count
        
        // Safety check for array bounds
        guard m > 0 && n > 0 else {
            return max(m, n)
        }
        
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        
        for i in 0...m { dp[i][0] = i }
        for j in 0...n { dp[0][j] = j }
        
        let chars1 = Array(s1)
        let chars2 = Array(s2)
        
        for i in 1...m {
            for j in 1...n {
                // Safe array access with bounds check
                guard i <= chars1.count && j <= chars2.count else {
                    print("⚠️ [FUZZY] Out of bounds: i=\(i) (max \(chars1.count)), j=\(j) (max \(chars2.count))")
                    continue
                }
                
                let cost = chars1[i-1] == chars2[j-1] ? 0 : 1
                dp[i][j] = min(
                    dp[i-1][j] + 1,      // deletion
                    dp[i][j-1] + 1,      // insertion
                    dp[i-1][j-1] + cost  // substitution
                )
            }
        }
        
        return dp[m][n]
    }
}

struct OCRResult {
    let text: String
    let confidence: Float
    let isValid: Bool
}

