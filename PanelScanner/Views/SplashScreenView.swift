import SwiftUI

struct SplashScreenView: View {
    @State private var scale: CGFloat = 0.7
    @State private var opacity: Double = 0
    @State private var glowIntensity: Double = 0
    @State private var scanLineOffset: CGFloat = -200
    @State private var rotationAngle: Double = 0
    @State private var showLightning: Bool = false
    @State private var lightningOpacity: Double = 0
    
    var onComplete: () -> Void
    
    var body: some View {
        ZStack {
            // Dark gradient background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.1, blue: 0.2),
                    Color(red: 0.1, green: 0.15, blue: 0.3),
                    Color(red: 0.15, green: 0.2, blue: 0.35)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // SICK LIGHTNING EFFECT
            if showLightning {
                ZStack {
                    // Full screen flash
                    Color.white
                        .opacity(lightningOpacity * 0.3)
                        .ignoresSafeArea()
                    
                    // Electric arcs from center
                    ForEach(0..<8) { i in
                        ElectricArc(angle: Double(i) * 45, length: 400, branches: 3, seed: i)
                            .stroke(
                                LinearGradient(
                                    colors: [.white, .cyan, .clear],
                                    startPoint: .center,
                                    endPoint: .bottom
                                ),
                                lineWidth: 3
                            )
                            .opacity(lightningOpacity)
                            .shadow(color: .cyan, radius: 20)
                            .blendMode(.screen)
                    }
                    
                    // Bright core
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.white, .cyan, .blue, .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 200
                            )
                        )
                        .frame(width: 400, height: 400)
                        .opacity(lightningOpacity * 0.8)
                        .blendMode(.screen)
                }
                .position(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2)
            }
            
            // Animated grid pattern in background
            GeometryReader { geometry in
                ZStack {
                    // Vertical lines
                    ForEach(0..<5) { i in
                        Rectangle()
                            .fill(Color.cyan.opacity(0.1))
                            .frame(width: 1)
                            .offset(x: CGFloat(i) * geometry.size.width / 4)
                            .opacity(opacity * 0.3)
                    }
                    
                    // Horizontal lines
                    ForEach(0..<8) { i in
                        Rectangle()
                            .fill(Color.cyan.opacity(0.1))
                            .frame(height: 1)
                            .offset(y: CGFloat(i) * geometry.size.height / 7)
                            .opacity(opacity * 0.3)
                    }
                }
            }
            
            VStack(spacing: 30) {
                Spacer()
                
                // App Icon with glow effect
                ZStack {
                    // Outer glow
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    Color.cyan.opacity(glowIntensity * 0.6),
                                    Color.blue.opacity(glowIntensity * 0.3),
                                    Color.clear
                                ]),
                                center: .center,
                                startRadius: 50,
                                endRadius: 150
                            )
                        )
                        .frame(width: 300, height: 300)
                        .blur(radius: 30)
                    
                    // Icon background
                    RoundedRectangle(cornerRadius: 30)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.1, green: 0.3, blue: 0.5),
                                    Color(red: 0.05, green: 0.15, blue: 0.3)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 150, height: 150)
                        .shadow(color: .cyan.opacity(0.5), radius: 20, x: 0, y: 0)
                        .scaleEffect(scale)
                    
                    
                    // App icon symbol
                    ZStack {
                        // Panel/breaker grid icon
                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.cyan)
                                    .frame(width: 16, height: 16)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.cyan)
                                    .frame(width: 16, height: 16)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.cyan)
                                    .frame(width: 16, height: 16)
                            }
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.blue.opacity(0.7))
                                    .frame(width: 16, height: 16)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.blue.opacity(0.7))
                                    .frame(width: 16, height: 16)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.blue.opacity(0.7))
                                    .frame(width: 16, height: 16)
                            }
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.cyan)
                                    .frame(width: 16, height: 16)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.cyan)
                                    .frame(width: 16, height: 16)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.blue.opacity(0.7))
                                    .frame(width: 16, height: 16)
                            }
                        }
                        
                        // Viewfinder corners overlay
                        Image(systemName: "viewfinder")
                            .font(.system(size: 100, weight: .thin))
                            .foregroundColor(.cyan.opacity(0.6))
                    }
                    .scaleEffect(scale)
                    .rotationEffect(.degrees(rotationAngle))
                    
                    // Scanning line effect
                    Rectangle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.clear,
                                    Color.cyan.opacity(0.8),
                                    Color.clear
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 180, height: 3)
                        .offset(y: scanLineOffset)
                        .blur(radius: 1)
                        .scaleEffect(scale)
                }
                .frame(width: 300, height: 300)
                
                // App Name
                VStack(spacing: 12) {
                    Text("Panel Scanner")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.cyan, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .opacity(opacity)
                    
                    Text("V3")
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.blue.opacity(0.3))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.cyan.opacity(0.5), lineWidth: 1)
                                )
                        )
                        .opacity(opacity)
                    
                    Text("Cummings Electrical")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .opacity(opacity)
                }
                
                Spacer()
                
                // Loading indicator
                HStack(spacing: 8) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(Color.cyan)
                            .frame(width: 8, height: 8)
                            .scaleEffect(glowIntensity > 0.5 ? 1.0 : 0.5)
                            .animation(
                                Animation.easeInOut(duration: 0.6)
                                    .repeatForever()
                                    .delay(Double(index) * 0.2),
                                value: glowIntensity
                            )
                    }
                }
                .opacity(opacity)
                .padding(.bottom, 50)
            }
        }
        .onAppear {
            startAnimations()
        }
    }
    
    private func startAnimations() {
        // Initial scale and fade in
        withAnimation(.easeOut(duration: 0.8)) {
            scale = 1.0
            opacity = 1.0
        }
        
        // Glow pulse
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            glowIntensity = 1.0
        }
        
        // Scanning line animation
        withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
            scanLineOffset = 200
        }
        
        // Subtle rotation
        withAnimation(.linear(duration: 20.0).repeatForever(autoreverses: false)) {
            rotationAngle = 360
        }
        
        // Epic lightning strikes with flicker
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            triggerLightning()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                triggerLightning() // Quick flicker
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            triggerLightning()
        }
        
        // Auto-dismiss after 2.5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeOut(duration: 0.5)) {
                opacity = 0
                scale = 1.2
            }
            
            // Complete callback
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                onComplete()
            }
        }
    }
    
    private func triggerLightning() {
        showLightning = true
        
        // Instant bright flash
        withAnimation(.linear(duration: 0.02)) {
            lightningOpacity = 1.0
        }
        
        // Quick fade
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            withAnimation(.easeOut(duration: 0.15)) {
                lightningOpacity = 0
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            showLightning = false
        }
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
    }
}

// MARK: - Electric Arc Shape (Branching Lightning)

struct ElectricArc: Shape {
    let angle: Double
    let length: CGFloat
    let branches: Int
    let seed: Int
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let centerX = rect.width / 2
        let centerY = rect.height / 2
        let radians = angle * .pi / 180
        
        path.move(to: CGPoint(x: centerX, y: centerY))
        
        // Main bolt
        var currentX = centerX
        var currentY = centerY
        let segments = 15
        
        for i in 0..<segments {
            let progress = CGFloat(i) / CGFloat(segments)
            let segmentLength = length / CGFloat(segments)
            
            // Random jitter based on seed
            let jitterX = CGFloat((seed * 17 + i * 23) % 40 - 20)
            let jitterY = CGFloat((seed * 13 + i * 19) % 30 - 15)
            
            currentX += cos(radians) * segmentLength + jitterX
            currentY += sin(radians) * segmentLength + jitterY
            
            path.addLine(to: CGPoint(x: currentX, y: currentY))
            
            // Add branches
            if i % 5 == 0 && i > 0 {
                let branchAngle = radians + (seed % 2 == 0 ? 0.5 : -0.5)
                let branchLength = segmentLength * 3
                let branchX = currentX + cos(branchAngle) * branchLength
                let branchY = currentY + sin(branchAngle) * branchLength
                
                path.move(to: CGPoint(x: currentX, y: currentY))
                path.addLine(to: CGPoint(x: branchX, y: branchY))
                path.move(to: CGPoint(x: currentX, y: currentY))
            }
        }
        
        return path
    }
}

#Preview {
    SplashScreenView(onComplete: {})
}

