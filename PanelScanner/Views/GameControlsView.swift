import SwiftUI

struct GameControlsView: View {
    @ObservedObject var viewModel: GameViewModel
    
    var body: some View {
        VStack(spacing: 15) {
            // Top row: Rotate & Hard Drop
            HStack(spacing: 15) {
                // Rotate button
                ControlButton(
                    icon: "arrow.clockwise",
                    color: .purple,
                    size: .medium
                ) {
                    viewModel.rotate()
                    hapticFeedback(.medium)
                }
                
                Spacer()
                
                // Hard Drop button
                ControlButton(
                    icon: "arrow.down.to.line",
                    color: .red,
                    size: .medium
                ) {
                    viewModel.hardDrop()
                    hapticFeedback(.heavy)
                }
            }
            
            // Bottom row: Movement & Pause
            HStack(spacing: 15) {
                // Left button
                ControlButton(
                    icon: "arrow.left",
                    color: .cyan,
                    size: .large
                ) {
                    viewModel.moveLeft()
                    hapticFeedback(.light)
                }
                
                // Down button
                ControlButton(
                    icon: "arrow.down",
                    color: .green,
                    size: .large
                ) {
                    viewModel.moveDown()
                    hapticFeedback(.light)
                }
                
                // Right button
                ControlButton(
                    icon: "arrow.right",
                    color: .cyan,
                    size: .large
                ) {
                    viewModel.moveRight()
                    hapticFeedback(.light)
                }
                
                Spacer()
                
                // Pause/Resume button
                ControlButton(
                    icon: viewModel.isPaused ? "play.fill" : "pause.fill",
                    color: .orange,
                    size: .medium
                ) {
                    viewModel.pauseGame()
                    hapticFeedback(.medium)
                }
            }
        }
    }
    
    private func hapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
}

// MARK: - Control Button

struct ControlButton: View {
    let icon: String
    let color: Color
    let size: ButtonSize
    let action: () -> Void
    
    enum ButtonSize {
        case large, medium
        
        var dimension: CGFloat {
            switch self {
            case .large: return 70
            case .medium: return 60
            }
        }
        
        var iconSize: CGFloat {
            switch self {
            case .large: return 30
            case .medium: return 24
            }
        }
    }
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // Outer glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [color.opacity(0.3), Color.clear],
                            center: .center,
                            startRadius: 5,
                            endRadius: size.dimension / 2
                        )
                    )
                
                // Button body
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.8), color.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size.dimension * 0.85, height: size.dimension * 0.85)
                
                // Border
                Circle()
                    .stroke(color, lineWidth: 2)
                    .frame(width: size.dimension * 0.85, height: size.dimension * 0.85)
                
                // Icon
                Image(systemName: icon)
                    .font(.system(size: size.iconSize, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .frame(width: size.dimension, height: size.dimension)
        .shadow(color: color.opacity(0.5), radius: 5, x: 0, y: 3)
    }
}

// MARK: - Preview

#if DEBUG
struct GameControlsView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            GameControlsView(viewModel: GameViewModel())
                .padding()
        }
    }
}
#endif

