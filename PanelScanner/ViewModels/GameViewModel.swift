import SwiftUI
import Combine
import UIKit

// MARK: - Game Models

enum CellState: Equatable {
    case empty
    case filled(Color)
}

enum PieceType: CaseIterable {
    case iBeam      // I-piece (long breaker)
    case square     // O-piece (panel box)
    case tShape     // T-piece (T-connector)
    case lShape     // L-piece (angle connector)
    case jShape     // J-piece (reverse angle)
    case sShape     // S-piece (offset connector)
    case zShape     // Z-piece (reverse offset)
    
    var color: Color {
        switch self {
        case .iBeam: return Color.cyan
        case .square: return Color.yellow
        case .tShape: return Color.purple
        case .lShape: return Color.orange
        case .jShape: return Color.blue
        case .sShape: return Color.green
        case .zShape: return Color.red
        }
    }
    
    var shape: [[Bool]] {
        switch self {
        case .iBeam:
            return [
                [true, true, true, true]
            ]
        case .square:
            return [
                [true, true],
                [true, true]
            ]
        case .tShape:
            return [
                [false, true, false],
                [true, true, true]
            ]
        case .lShape:
            return [
                [true, false],
                [true, false],
                [true, true]
            ]
        case .jShape:
            return [
                [false, true],
                [false, true],
                [true, true]
            ]
        case .sShape:
            return [
                [false, true, true],
                [true, true, false]
            ]
        case .zShape:
            return [
                [true, true, false],
                [false, true, true]
            ]
        }
    }
}

struct GamePiece {
    var type: PieceType
    var position: CGPoint  // Top-left position on grid
    var shape: [[Bool]]
    
    init(type: PieceType) {
        self.type = type
        self.position = CGPoint(x: 3, y: 0)  // Start at top center
        self.shape = type.shape
    }
    
    var color: Color {
        type.color
    }
    
    // Rotate piece 90 degrees clockwise
    mutating func rotate() {
        let rows = shape.count
        let cols = shape[0].count
        var rotated = Array(repeating: Array(repeating: false, count: rows), count: cols)
        
        for r in 0..<rows {
            for c in 0..<cols {
                rotated[c][rows - 1 - r] = shape[r][c]
            }
        }
        
        shape = rotated
    }
    
    // Get all filled positions in grid coordinates
    func filledPositions() -> [(Int, Int)] {
        var positions: [(Int, Int)] = []
        for (r, row) in shape.enumerated() {
            for (c, cell) in row.enumerated() {
                if cell {
                    positions.append((Int(position.y) + r, Int(position.x) + c))
                }
            }
        }
        return positions
    }
}

// MARK: - Game ViewModel

class GameViewModel: ObservableObject {
    // Board dimensions
    let rows = 20
    let cols = 10
    
    // Game state
    @Published var board: [[CellState]] = []
    @Published var currentPiece: GamePiece?
    @Published var nextPiece: GamePiece?
    @Published var score: Int = 0
    @Published var level: Int = 1
    @Published var linesCleared: Int = 0
    @Published var isGameOver: Bool = false
    @Published var isPaused: Bool = false
    @Published var highScore: Int = 0
    @Published var lastScoreIncrease: Int = 0  // For animated score display
    @Published var combo: Int = 0  // Track consecutive line clears
    
    // Game loop
    private var gameTimer: AnyCancellable?
    private var fallSpeed: TimeInterval {
        // Gentler exponential curve: starts at 1.0s, gets faster but never below 0.05s
        max(0.05, pow(0.8, Double(level - 1)))
    }
    
    init() {
        setupBoard()
        loadHighScore()
    }
    
    private func setupBoard() {
        board = Array(repeating: Array(repeating: .empty, count: cols), count: rows)
    }
    
    // MARK: - Game Control
    
    func startGame() {
        setupBoard()
        score = 0
        level = 1
        linesCleared = 0
        isGameOver = false
        isPaused = false
        combo = 0
        lastScoreIncrease = 0
        
        // Clear next piece for fresh start
        nextPiece = nil
        
        spawnPiece()
        startGameLoop()
    }
    
    func pauseGame() {
        isPaused.toggle()
        if isPaused {
            stopGameLoop()
        } else {
            startGameLoop()
        }
    }
    
    func stopGame() {
        stopGameLoop()
        currentPiece = nil
        nextPiece = nil
        isGameOver = true
    }
    
    private func startGameLoop() {
        gameTimer = Timer.publish(every: fallSpeed, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.gameStep()
            }
    }
    
    private func stopGameLoop() {
        gameTimer?.cancel()
        gameTimer = nil
    }
    
    // MARK: - Game Logic
    
    private func gameStep() {
        guard !isPaused, !isGameOver else { return }
        
        if !moveDown() {
            lockPiece()
            clearLines()
            spawnPiece()
            
            // Check for game over
            if let piece = currentPiece, !canPlace(piece: piece) {
                gameOver()
            }
        }
    }
    
    private func spawnPiece() {
        if nextPiece == nil {
            nextPiece = GamePiece(type: PieceType.allCases.randomElement()!)
        }
        
        currentPiece = nextPiece
        nextPiece = GamePiece(type: PieceType.allCases.randomElement()!)
    }
    
    private func lockPiece() {
        guard let piece = currentPiece else { return }
        
        for (r, c) in piece.filledPositions() {
            if r >= 0 && r < rows && c >= 0 && c < cols {
                board[r][c] = .filled(piece.color)
            }
        }
        
        currentPiece = nil
    }
    
    private func clearLines() {
        var rowsToClear: [Int] = []
        
        // Find full rows
        for r in 0..<rows {
            if board[r].allSatisfy({ cell in
                if case .filled = cell { return true }
                return false
            }) {
                rowsToClear.append(r)
            }
        }
        
        if rowsToClear.isEmpty {
            combo = 0  // Reset combo if no lines cleared
            return
        }
        
        // Clear rows and update score
        let clearedCount = rowsToClear.count
        linesCleared += clearedCount
        combo += 1
        
        // Scoring: 100, 300, 500, 800 for 1,2,3,4 lines
        let basePoints = [0, 100, 300, 500, 800][min(clearedCount, 4)]
        let comboBonus = combo > 1 ? (combo - 1) * 50 : 0
        let points = (basePoints + comboBonus) * level
        
        lastScoreIncrease = points
        score += points
        
        // Haptic feedback - stronger for more lines
        DispatchQueue.main.async {
            let generator = UIImpactFeedbackGenerator(style: clearedCount >= 4 ? .heavy : .medium)
            generator.impactOccurred()
        }
        
        // Update high score
        if score > highScore {
            highScore = score
            saveHighScore()
        }
        
        // Level up every 10 lines
        let newLevel = (linesCleared / 10) + 1
        if newLevel > level {
            level = newLevel
            stopGameLoop()
            startGameLoop()  // Restart with new speed
        }
        
        // Remove cleared rows and add new empty rows at top
        for row in rowsToClear.sorted().reversed() {
            board.remove(at: row)
            board.insert(Array(repeating: .empty, count: cols), at: 0)
        }
    }
    
    private func gameOver() {
        isGameOver = true
        stopGameLoop()
        
        if score > highScore {
            highScore = score
            saveHighScore()
        }
    }
    
    // MARK: - Movement
    
    func moveLeft() {
        guard !isPaused, !isGameOver else { return }
        guard var piece = currentPiece else { return }
        piece.position.x -= 1
        
        if canPlace(piece: piece) {
            currentPiece = piece
        }
    }
    
    func moveRight() {
        guard !isPaused, !isGameOver else { return }
        guard var piece = currentPiece else { return }
        piece.position.x += 1
        
        if canPlace(piece: piece) {
            currentPiece = piece
        }
    }
    
    @discardableResult
    func moveDown() -> Bool {
        guard var piece = currentPiece else { return false }
        piece.position.y += 1
        
        if canPlace(piece: piece) {
            currentPiece = piece
            return true
        }
        
        return false
    }
    
    func rotate() {
        guard !isPaused, !isGameOver else { return }
        guard var piece = currentPiece else { return }
        piece.rotate()
        
        // Try basic wall kicks
        if canPlace(piece: piece) {
            currentPiece = piece
            return
        }
        
        // Try kick right
        piece.position.x += 1
        if canPlace(piece: piece) {
            currentPiece = piece
            return
        }
        
        // Try kick left
        piece.position.x -= 2
        if canPlace(piece: piece) {
            currentPiece = piece
            return
        }
        
        // Try kick up
        piece.position.x += 1
        piece.position.y -= 1
        if canPlace(piece: piece) {
            currentPiece = piece
            return
        }
        
        // All kicks failed, revert rotation
        piece.position.y += 1
        piece.rotate()
        piece.rotate()
        piece.rotate()
    }
    
    func hardDrop() {
        guard !isPaused, !isGameOver else { return }
        
        var dropDistance = 0
        while moveDown() {
            dropDistance += 1
        }
        
        lockPiece()
        
        // Show hard drop bonus first, then line clear bonus
        if dropDistance > 0 {
            let dropBonus = dropDistance * 2
            lastScoreIncrease = dropBonus
            score += dropBonus
        }
        
        clearLines()
        spawnPiece()
        
        if let piece = currentPiece, !canPlace(piece: piece) {
            gameOver()
        }
    }
    
    // MARK: - Collision Detection
    
    private func canPlace(piece: GamePiece) -> Bool {
        for (r, c) in piece.filledPositions() {
            // Check bounds
            if c < 0 || c >= cols || r >= rows {
                return false
            }
            
            // Allow piece to be above board during spawn
            if r < 0 {
                continue
            }
            
            // Check collision with existing pieces
            if case .filled = board[r][c] {
                return false
            }
        }
        
        return true
    }
    
    // Get ghost piece position (where it would land)
    func ghostPiecePositions() -> [(Int, Int)] {
        guard var ghost = currentPiece else { return [] }
        
        // Drop until collision
        while canPlace(piece: ghost) {
            ghost.position.y += 1
        }
        
        // Move back up one
        ghost.position.y -= 1
        
        return ghost.filledPositions()
    }
    
    // MARK: - Persistence
    
    private func loadHighScore() {
        highScore = UserDefaults.standard.integer(forKey: "CircuitBreakerHighScore")
    }
    
    private func saveHighScore() {
        UserDefaults.standard.set(highScore, forKey: "CircuitBreakerHighScore")
    }
}

