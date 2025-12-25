import SwiftUI

struct OCRConfirmationOverlay: View {
    let confirmation: PendingOCRConfirmation
    let onConfirm: () -> Void
    let onIgnore: () -> Void
    
    @State private var scale: CGFloat = 0.8
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Semi-transparent background (NO TAP - forces button selection)
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header with type indicator
                    HStack {
                        Image(systemName: confirmation.className == "panel_label" ? "tag.fill" : "rectangle.fill")
                            .font(.title2)
                        
                        Text(confirmation.displayTitle)
                            .font(.headline)
                            .fontWeight(.bold)
                        
                        Spacer()
                    }
                    .padding()
                    .background(confirmation.displayColor)
                    .foregroundColor(.white)
                    
                    // OCR Result Display
                    VStack(spacing: 16) {
                        Text("OCR Detected:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text(confirmation.text)
                            .font(.system(size: 32, weight: .bold, design: .monospaced))
                            .padding(.horizontal)
                            .multilineTextAlignment(.center)
                        
                        // Confidence indicator
                        HStack(spacing: 8) {
                            Text("Confidence:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            ProgressView(value: Double(confirmation.confidence))
                                .frame(width: 100)
                            
                            Text("\(Int(confirmation.confidence * 100))%")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .padding(.bottom, 8)
                        
                        // Action Buttons
                        HStack(spacing: 20) {
                            // Ignore Button
                            Button(action: {
                                withAnimation(.spring(response: 0.3)) {
                                    scale = 0.8
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    onIgnore()
                                }
                            }) {
                                HStack {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title3)
                                    Text("Ignore")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                            
                            // Confirm Button
                            Button(action: {
                                withAnimation(.spring(response: 0.3)) {
                                    scale = 1.1
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    onConfirm()
                                }
                            }) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title3)
                                    Text("Confirm")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding()
                    .background(Color(UIColor.systemBackground))
                }
                .frame(maxWidth: 400)
                .cornerRadius(16)
                .shadow(radius: 20)
                .scaleEffect(scale)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                scale = 1.0
            }
        }
    }
}

#Preview {
    OCRConfirmationOverlay(
        confirmation: PendingOCRConfirmation(
            trackID: "test",
            text: "BJA36050",
            confidence: 0.95,
            boundingBox: CGRect(x: 0.5, y: 0.5, width: 0.2, height: 0.1),
            className: "breaker_face",
            timestamp: Date()
        ),
        onConfirm: {},
        onIgnore: {}
    )
}

