import SwiftUI

struct GameBoardView: View {
    @ObservedObject var viewModel: GameViewModel
    @State private var flashTrigger = false
    
    private let cellSize: CGFloat = 16
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Panel background
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                LinearGradient(
                                    colors: [.orange.opacity(0.5), .gray.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 3
                            )
                    )
                    .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 5)
                
                // Grid lines (subtle)
                Path { path in
                    // Vertical lines
                    for col in 0...viewModel.cols {
                        let x = CGFloat(col) * cellSize + 5
                        path.move(to: CGPoint(x: x, y: 5))
                        path.addLine(to: CGPoint(x: x, y: CGFloat(viewModel.rows) * cellSize + 5))
                    }
                    
                    // Horizontal lines
                    for row in 0...viewModel.rows {
                        let y = CGFloat(row) * cellSize + 5
                        path.move(to: CGPoint(x: 5, y: y))
                        path.addLine(to: CGPoint(x: CGFloat(viewModel.cols) * cellSize + 5, y: y))
                    }
                }
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                
                // Locked pieces on board
                ForEach(0..<viewModel.rows, id: \.self) { row in
                    ForEach(0..<viewModel.cols, id: \.self) { col in
                        if case .filled(let color) = viewModel.board[row][col] {
                            CellView(color: color)
                                .frame(width: cellSize - 1, height: cellSize - 1)
                                .position(
                                    x: CGFloat(col) * cellSize + cellSize / 2 + 5,
                                    y: CGFloat(row) * cellSize + cellSize / 2 + 5
                                )
                        }
                    }
                }
                
                // Ghost piece (landing preview)
                if let piece = viewModel.currentPiece {
                    ForEach(Array(viewModel.ghostPiecePositions().enumerated()), id: \.offset) { index, position in
                        let (row, col) = position
                        if row >= 0 && row < viewModel.rows && col >= 0 && col < viewModel.cols {
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(piece.color.opacity(0.4), lineWidth: 2)
                                .frame(width: cellSize - 1, height: cellSize - 1)
                                .position(
                                    x: CGFloat(col) * cellSize + cellSize / 2 + 5,
                                    y: CGFloat(row) * cellSize + cellSize / 2 + 5
                                )
                        }
                    }
                }
                
                // Current piece with glow
                if let piece = viewModel.currentPiece {
                    ForEach(Array(piece.filledPositions().enumerated()), id: \.offset) { index, position in
                        let (row, col) = position
                        if row >= 0 && row < viewModel.rows && col >= 0 && col < viewModel.cols {
                            CellView(color: piece.color)
                                .glowEffect(color: piece.color, radius: 3)
                                .frame(width: cellSize - 1, height: cellSize - 1)
                                .position(
                                    x: CGFloat(col) * cellSize + cellSize / 2 + 5,
                                    y: CGFloat(row) * cellSize + cellSize / 2 + 5
                                )
                        }
                    }
                }
                
                // Pause overlay
                if viewModel.isPaused {
                    ZStack {
                        Color.black.opacity(0.7)
                        
                        VStack(spacing: 15) {
                            Image(systemName: "pause.circle.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.orange)
                            
                            Text("PAUSED")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                    }
                    .cornerRadius(10)
                }
            }
        }
        .frame(
            width: CGFloat(viewModel.cols) * cellSize + 10,
            height: CGFloat(viewModel.rows) * cellSize + 10
        )
        .flashEffect(trigger: flashTrigger)
        .onChange(of: viewModel.linesCleared) { oldValue, newValue in
            // Flash effect when lines are cleared
            if newValue > oldValue {
                flashTrigger.toggle()
            }
        }
    }
}

// MARK: - Cell View

struct CellView: View {
    let color: Color
    
    var body: some View {
        ZStack {
            // Main cell
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Inner highlight for 3D effect
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.3), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                )
                .padding(2)
            
            // Border
            RoundedRectangle(cornerRadius: 2)
                .stroke(color.opacity(0.5), lineWidth: 1)
        }
    }
}

