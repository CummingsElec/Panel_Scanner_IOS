import SwiftUI

struct CircuitBreakerGameView: View {
    @StateObject private var viewModel = GameViewModel()
    @State private var showingInstructions = true
    @State private var showScorePopup = false
    @State private var scorePopupOffset: CGFloat = 0
    @State private var scorePopupOpacity: Double = 0
    
    var body: some View {
        ZStack {
            // Industrial background
            LinearGradient(
                colors: [Color(white: 0.15), Color(white: 0.1)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CIRCUIT BREAKER")
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundColor(.orange)
                        Text("Panel Puzzle Challenge")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        showingInstructions = true
                    }) {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.orange)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 50)
                
                // Score & Stats
                ZStack {
                    HStack(spacing: 30) {
                        StatBox(title: "SCORE", value: "\(viewModel.score)", color: .cyan)
                        StatBox(title: "LEVEL", value: "\(viewModel.level)", color: .orange)
                        StatBox(title: "LINES", value: "\(viewModel.linesCleared)", color: .green)
                    }
                    
                    // Floating score popup
                    if showScorePopup && viewModel.lastScoreIncrease > 0 {
                        Text("+\(viewModel.lastScoreIncrease)")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundColor(.yellow)
                            .glowEffect(color: .yellow, radius: 10)
                            .offset(y: scorePopupOffset)
                            .opacity(scorePopupOpacity)
                    }
                    
                    // Combo indicator
                    if viewModel.combo > 1 {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Text("COMBO x\(viewModel.combo)")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundColor(.orange)
                                    .padding(8)
                                    .background(
                                        Capsule()
                                            .fill(Color.black.opacity(0.7))
                                            .overlay(
                                                Capsule()
                                                    .stroke(Color.orange, lineWidth: 2)
                                            )
                                    )
                                    .pulseEffect(color: .orange)
                            }
                        }
                    }
                }
                .padding(.horizontal)
                
                HStack(alignment: .top, spacing: 15) {
                    // Main game board with swipe gestures
                    GameBoardView(viewModel: viewModel)
                        .gesture(
                            DragGesture(minimumDistance: 20)
                                .onEnded { gesture in
                                    handleSwipe(gesture)
                                }
                        )
                        .simultaneousGesture(
                            TapGesture()
                                .onEnded { _ in
                                    viewModel.rotate()
                                    hapticFeedback(.medium)
                                }
                        )
                    
                    // Side panel
                    VStack(spacing: 15) {
                        // High Score
                        VStack(spacing: 4) {
                            Text("HIGH")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.gray)
                            Text("\(viewModel.highScore)")
                                .font(.system(size: 16, weight: .heavy, design: .rounded))
                                .foregroundColor(.yellow)
                        }
                        .padding()
                        .frame(width: 80)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(0.5))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.yellow.opacity(0.3), lineWidth: 2)
                                )
                        )
                        
                        // Next piece preview
                        VStack(spacing: 8) {
                            Text("NEXT")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.gray)
                            
                            NextPiecePreview(piece: viewModel.nextPiece)
                                .frame(width: 70, height: 70)
                        }
                        .padding()
                        .frame(width: 80)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(0.5))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.cyan.opacity(0.3), lineWidth: 2)
                                )
                        )
                        
                        Spacer()
                    }
                }
                .padding(.horizontal)
                
                // Controls
                GameControlsView(viewModel: viewModel)
                    .padding(.horizontal)
                    .padding(.bottom, 20)
            }
            
            // Game Over Overlay
            if viewModel.isGameOver {
                GameOverView(
                    score: viewModel.score,
                    highScore: viewModel.highScore,
                    onRestart: {
                        viewModel.startGame()
                    }
                )
                .transition(.scale.combined(with: .opacity))
            }
            
            // Instructions Overlay
            if showingInstructions && !viewModel.isGameOver {
                GameInstructionsView(
                    onStart: {
                        showingInstructions = false
                        viewModel.startGame()
                    },
                    onDismiss: {
                        showingInstructions = false
                    }
                )
                .transition(.opacity)
            }
        }
        .onAppear {
            if !viewModel.isGameOver && viewModel.currentPiece != nil {
                // Game was already running, don't show instructions
                showingInstructions = false
            }
        }
        .onChange(of: viewModel.lastScoreIncrease) { oldValue, newValue in
            if newValue > 0 {
                showScoreAnimation()
            }
        }
    }
    
    // Animate floating score
    private func showScoreAnimation() {
        showScorePopup = true
        scorePopupOffset = 0
        scorePopupOpacity = 1.0
        
        withAnimation(.easeOut(duration: 1.0)) {
            scorePopupOffset = -50
            scorePopupOpacity = 0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            showScorePopup = false
        }
    }
    
    // Handle swipe gestures
    private func handleSwipe(_ gesture: DragGesture.Value) {
        let horizontalMovement = gesture.translation.width
        let verticalMovement = gesture.translation.height
        
        // Determine direction based on larger movement
        if abs(horizontalMovement) > abs(verticalMovement) {
            // Horizontal swipe
            if horizontalMovement > 0 {
                viewModel.moveRight()
            } else {
                viewModel.moveLeft()
            }
            hapticFeedback(.light)
        } else {
            // Vertical swipe
            if verticalMovement > 0 {
                viewModel.hardDrop()
                hapticFeedback(.heavy)
            }
        }
    }
    
    private func hapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
}

// MARK: - Stat Box

struct StatBox: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.gray)
            Text(value)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(color.opacity(0.3), lineWidth: 2)
                )
        )
    }
}

// MARK: - Next Piece Preview

struct NextPiecePreview: View {
    let piece: GamePiece?
    
    var body: some View {
        GeometryReader { geometry in
            if let piece = piece {
                let maxDim = max(piece.shape.count, piece.shape[0].count)
                let cellSize = min(geometry.size.width, geometry.size.height) / CGFloat(maxDim + 1)
                let pieceWidth = CGFloat(piece.shape[0].count) * cellSize
                let pieceHeight = CGFloat(piece.shape.count) * cellSize
                let offsetX = (geometry.size.width - pieceWidth) / 2
                let offsetY = (geometry.size.height - pieceHeight) / 2
                
                ForEach(0..<piece.shape.count, id: \.self) { row in
                    ForEach(0..<piece.shape[row].count, id: \.self) { col in
                        if piece.shape[row][col] {
                            PreviewCell(
                                color: piece.color,
                                cellSize: cellSize,
                                x: CGFloat(col) * cellSize + cellSize / 2 + offsetX,
                                y: CGFloat(row) * cellSize + cellSize / 2 + offsetY
                            )
                        }
                    }
                }
            }
        }
    }
}

struct PreviewCell: View {
    let color: Color
    let cellSize: CGFloat
    let x: CGFloat
    let y: CGFloat
    
    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )
            .frame(width: cellSize - 2, height: cellSize - 2)
            .position(x: x, y: y)
    }
}

// MARK: - Game Over View

struct GameOverView: View {
    let score: Int
    let highScore: Int
    let onRestart: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.9)
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                Image(systemName: "bolt.trianglebadge.exclamationmark.fill")
                    .font(.system(size: 70))
                    .foregroundColor(.orange)
                
                Text("CIRCUIT OVERLOAD")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundColor(.red)
                
                VStack(spacing: 15) {
                    HStack(spacing: 40) {
                        VStack {
                            Text("SCORE")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundColor(.gray)
                            Text("\(score)")
                                .font(.system(size: 36, weight: .heavy, design: .rounded))
                                .foregroundColor(.cyan)
                        }
                        
                        VStack {
                            Text("HIGH SCORE")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundColor(.gray)
                            Text("\(highScore)")
                                .font(.system(size: 36, weight: .heavy, design: .rounded))
                                .foregroundColor(.yellow)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 15)
                            .fill(Color.black.opacity(0.7))
                            .overlay(
                                RoundedRectangle(cornerRadius: 15)
                                    .stroke(
                                        LinearGradient(
                                            colors: [.orange, .red],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ),
                                        lineWidth: 3
                                    )
                            )
                    )
                }
                
                Button(action: onRestart) {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.clockwise")
                            .font(.title2)
                        Text("RESTART")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 15)
                    .background(
                        LinearGradient(
                            colors: [.orange, .red],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(25)
                    .shadow(color: .orange.opacity(0.5), radius: 10, x: 0, y: 5)
                }
            }
            .padding(40)
        }
    }
}

// MARK: - Game Instructions View

struct GameInstructionsView: View {
    let onStart: () -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.95)
                .ignoresSafeArea()
            
            VStack(spacing: 25) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.orange)
                
                Text("HOW TO PLAY")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 15) {
                    InstructionRow(icon: "arrow.left.arrow.right", text: "Swipe or tap buttons to move")
                    InstructionRow(icon: "arrow.clockwise", text: "Tap board to rotate")
                    InstructionRow(icon: "arrow.down.to.line", text: "Swipe down for hard drop")
                    InstructionRow(icon: "checkmark.square.fill", text: "Clear full rows to score")
                    InstructionRow(icon: "speedometer", text: "Level up every 10 lines")
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 15)
                        .fill(Color.black.opacity(0.5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 15)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 2)
                        )
                )
                
                Button(action: onStart) {
                    HStack(spacing: 10) {
                        Image(systemName: "play.fill")
                            .font(.title2)
                        Text("START GAME")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 15)
                    .background(
                        LinearGradient(
                            colors: [.green, .cyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(25)
                    .shadow(color: .green.opacity(0.5), radius: 10, x: 0, y: 5)
                }
            }
            .padding(40)
        }
    }
}

struct InstructionRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.cyan)
                .frame(width: 30)
            
            Text(text)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(.white)
            
            Spacer()
        }
    }
}

