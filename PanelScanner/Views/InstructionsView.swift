import SwiftUI

struct InstructionsView: View {
    @State private var expandedSection: String? = nil
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.cyan, .blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .padding(.top, 20)
                        
                        Text("Panel Scanner Guide")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        
                        Text("Learn how to capture panel data efficiently")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.bottom, 10)
                    
                    // Quick Start
                    QuickStartCard()
                    
                    // Feature sections
                    FeatureSection(
                        icon: "camera.viewfinder",
                        title: "Scanning Modes",
                        color: .blue,
                        isExpanded: expandedSection == "scanning"
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            FeatureItem(
                                icon: "tag.fill",
                                title: "Panel Mode",
                                description: "Focuses on panel label detection. Perfect for quick panel identification."
                            )
                            
                            FeatureItem(
                                icon: "viewfinder",
                                title: "Full Mode",
                                description: "Detects panel labels and all breakers. Use for comprehensive panel documentation."
                            )
                            
                            FeatureItem(
                                icon: "arkit",
                                title: "AR Mode",
                                description: "View floating 3D labels in augmented reality. Great for hands-free inspection."
                            )
                        }
                    }
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3)) {
                            expandedSection = expandedSection == "scanning" ? nil : "scanning"
                        }
                    }
                    
                    FeatureSection(
                        icon: "record.circle",
                        title: "Recording",
                        color: .red,
                        isExpanded: expandedSection == "recording"
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            FeatureItem(
                                icon: "video.fill",
                                title: "Video Capture",
                                description: "Records your scan with synchronized detection data for documentation and review."
                            )
                            
                            FeatureItem(
                                icon: "text.viewfinder",
                                title: "OCR Confirmation",
                                description: "Review and confirm detected panel labels before they're saved. Tap to accept or ignore."
                            )
                            
                            FeatureItem(
                                icon: "square.and.arrow.up",
                                title: "Export & Share",
                                description: "Save as JSON, CSV, and video. Share via Files, OneDrive, or AirDrop."
                            )
                        }
                    }
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3)) {
                            expandedSection = expandedSection == "recording" ? nil : "recording"
                        }
                    }
                    
                    FeatureSection(
                        icon: "chart.bar.fill",
                        title: "Stats & Tracking",
                        color: .green,
                        isExpanded: expandedSection == "stats"
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            FeatureItem(
                                icon: "number.circle.fill",
                                title: "Live Counters",
                                description: "See real-time breaker counts and panel labels as you scan."
                            )
                            
                            FeatureItem(
                                icon: "clock.arrow.circlepath",
                                title: "Session History",
                                description: "Access all previous scans from the History tab. Review, share, or delete."
                            )
                            
                            FeatureItem(
                                icon: "checkmark.circle.fill",
                                title: "Cumulative Tracking",
                                description: "Track total captured breakers across your entire recording session."
                            )
                        }
                    }
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3)) {
                            expandedSection = expandedSection == "stats" ? nil : "stats"
                        }
                    }
                    
                    FeatureSection(
                        icon: "gearshape.fill",
                        title: "Settings & Customization",
                        color: .gray,
                        isExpanded: expandedSection == "settings"
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            FeatureItem(
                                icon: "slider.horizontal.3",
                                title: "Detection Tuning",
                                description: "Adjust confidence thresholds and tracking parameters for your environment."
                            )
                            
                            FeatureItem(
                                icon: "speedometer",
                                title: "Performance",
                                description: "Control max FPS to balance detection speed with battery life."
                            )
                            
                            FeatureItem(
                                icon: "video.badge.checkmark",
                                title: "Video Options",
                                description: "Enable or disable video recording to save storage space."
                            )
                        }
                    }
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3)) {
                            expandedSection = expandedSection == "settings" ? nil : "settings"
                        }
                    }
                    
                    // Pro Tips
                    ProTipsCard()
                    
                    // Easter egg hint
                    EasterEggHint()
                    
                    // Footer
                    Text("Panel Scanner V3")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 20)
                        .padding(.bottom, 40)
                }
                .padding()
            }
            .navigationTitle("Help")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Quick Start Card

struct QuickStartCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "bolt.circle.fill")
                    .font(.title2)
                    .foregroundColor(.yellow)
                Text("Quick Start")
                    .font(.headline)
            }
            
            VStack(alignment: .leading, spacing: 10) {
                QuickStep(number: 1, text: "Point camera at electrical panel")
                QuickStep(number: 2, text: "Wait for green confirmation boxes")
                QuickStep(number: 3, text: "Tap record button to start capturing")
                QuickStep(number: 4, text: "Review and confirm panel labels")
                QuickStep(number: 5, text: "Stop recording and share your data")
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        )
    }
}

struct QuickStep: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.cyan, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)
                
                Text("\(number)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            Text(text)
                .font(.subheadline)
        }
    }
}

// MARK: - Feature Section

struct FeatureSection<Content: View>: View {
    let icon: String
    let title: String
    let color: Color
    let isExpanded: Bool
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                    .frame(width: 30)
                
                Text(title)
                    .font(.headline)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: isExpanded ? 16 : 16)
                    .fill(Color(.systemBackground))
            )
            
            // Expandable content
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    Divider()
                        .padding(.horizontal)
                    
                    content
                        .padding()
                }
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemBackground))
                )
            }
        }
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
    }
}

// MARK: - Feature Item

struct FeatureItem: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.cyan)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Pro Tips Card

struct ProTipsCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
                Text("Pro Tips")
                    .font(.headline)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                ProTip(icon: "light.max", text: "Use good lighting for best OCR accuracy")
                ProTip(icon: "hand.raised.fill", text: "Hold device steady when panel label appears")
                ProTip(icon: "battery.100", text: "Lower FPS in Settings to extend battery life")
                ProTip(icon: "iphone.gen3", text: "Use landscape mode for wider panels")
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        )
    }
}

struct ProTip: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.orange)
                .frame(width: 20)
            
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Easter Egg Hint

struct EasterEggHint: View {
    var body: some View {
        HStack {
            Image(systemName: "bolt.fill")
                .font(.title3)
                .foregroundColor(.yellow)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Hidden Feature")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text("Check the Play tab for a surprise... ⚡")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [Color.yellow.opacity(0.1), Color.orange.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

#Preview {
    InstructionsView()
}

