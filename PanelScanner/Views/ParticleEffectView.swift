import SwiftUI

// MARK: - Particle Effect for Row Clears

struct ParticleEffectView: View {
    let row: Int
    @State private var particles: [Particle] = []
    @State private var isAnimating = false
    
    struct Particle: Identifiable {
        let id = UUID()
        var position: CGPoint
        var velocity: CGVector
        var color: Color
        var opacity: Double
        var scale: CGFloat
    }
    
    var body: some View {
        ZStack {
            ForEach(particles) { particle in
                Circle()
                    .fill(particle.color)
                    .frame(width: 4, height: 4)
                    .scaleEffect(particle.scale)
                    .opacity(particle.opacity)
                    .position(particle.position)
            }
        }
        .onAppear {
            createParticles()
            animateParticles()
        }
    }
    
    private func createParticles() {
        for i in 0..<30 {
            let angle = Double(i) * (2 * .pi / 30)
            let velocity = CGVector(
                dx: cos(angle) * Double.random(in: 50...100),
                dy: sin(angle) * Double.random(in: 50...100)
            )
            
            let particle = Particle(
                position: CGPoint(x: 100, y: CGFloat(row) * 16),
                velocity: velocity,
                color: [Color.orange, .cyan, .green, .yellow, .purple].randomElement()!,
                opacity: 1.0,
                scale: 1.0
            )
            
            particles.append(particle)
        }
    }
    
    private func animateParticles() {
        withAnimation(.easeOut(duration: 0.6)) {
            isAnimating = true
        }
        
        Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { timer in
            for i in particles.indices {
                particles[i].position.x += particles[i].velocity.dx * 0.016
                particles[i].position.y += particles[i].velocity.dy * 0.016
                particles[i].velocity.dy += 200 * 0.016  // Gravity
                particles[i].opacity -= 0.016 / 0.6
                particles[i].scale -= 0.016 / 0.6
            }
            
            if particles.first?.opacity ?? 0 <= 0 {
                timer.invalidate()
            }
        }
    }
}

// MARK: - Flash Effect

struct FlashEffect: ViewModifier {
    let trigger: Bool
    @State private var opacity: Double = 0
    @State private var animationID: UUID = UUID()
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            Color.white
                .opacity(opacity)
                .allowsHitTesting(false)
                .id(animationID)
        }
        .onChange(of: trigger) { oldValue, newValue in
            // Trigger flash animation
            animationID = UUID()
            opacity = 0.6
            
            withAnimation(.easeOut(duration: 0.2)) {
                opacity = 0
            }
        }
    }
}

extension View {
    func flashEffect(trigger: Bool) -> some View {
        modifier(FlashEffect(trigger: trigger))
    }
}

// MARK: - Glow Effect

struct GlowEffect: ViewModifier {
    let color: Color
    let radius: CGFloat
    
    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.8), radius: radius, x: 0, y: 0)
            .shadow(color: color.opacity(0.6), radius: radius * 0.7, x: 0, y: 0)
            .shadow(color: color.opacity(0.4), radius: radius * 0.5, x: 0, y: 0)
    }
}

extension View {
    func glowEffect(color: Color, radius: CGFloat = 10) -> some View {
        modifier(GlowEffect(color: color, radius: radius))
    }
}

// MARK: - Pulse Animation

struct PulseEffect: ViewModifier {
    @State private var isPulsing = false
    let color: Color
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.05 : 1.0)
            .shadow(color: color.opacity(isPulsing ? 0.8 : 0.4), radius: isPulsing ? 15 : 5)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}

extension View {
    func pulseEffect(color: Color) -> some View {
        modifier(PulseEffect(color: color))
    }
}

