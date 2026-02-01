import SwiftUI

struct DaysSincePurchaseView: View {
    let purchaseDate: Date
    @State private var days: Int = 0
    @State private var isAnimating = false
    
    // Gradient for the text/background to make it look premium
    private let gradient = LinearGradient(
        colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.8)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.caption2)
                .foregroundColor(.white)
            
            Text("\(days) days")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                // Monospaced digit for stable width during animation if we were counting up rapidly
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(days)))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(gradient)
        .cornerRadius(12)
        .shadow(color: Color.purple.opacity(0.3), radius: 4, x: 0, y: 2)
        .scaleEffect(isAnimating ? 1.05 : 1.0)
        .onAppear {
            calculateDays()
            // Subtle "pop" animation on appear
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                isAnimating = true
            }
            // Count up animation
            animateCountUp()
        }
    }
    
    private func calculateDays() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: purchaseDate)
        let end = calendar.startOfDay(for: Date())
        let components = calendar.dateComponents([.day], from: start, to: end)
        // We set the target days here, but 'days' state starts at 0 for animation if we want
        // For now, let's just calculate the final value.
        // If we want a counting animation, we handle it in animateCountUp
    }
    
    private func animateCountUp() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: purchaseDate)
        let end = calendar.startOfDay(for: Date())
        let targetDays = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        
        let duration: Double = 1.0
        let steps = min(targetDays, 50) // Don't animate every single number if it's large, but SwiftUI contentTransition helps
        let delay = duration / Double(steps > 0 ? steps : 1)
        
        // Simple linear interpolation for the effect
        // For a smoother "rolling" effect with contentTransition, we can just set the value.
        // SwiftUI's .contentTransition(.numericText) works best when value changes.
        
        // Let's just set it directly with animation for now as a simple robust approach, 
        // asking the user allows for more complex "ticking" if desired.
        // But the user asked for "beautiful animation".
        // Let's do a simple timer based count up if the number is small, or just a spring transition.
        
        withAnimation(.easeOut(duration: 1.5)) {
            days = targetDays
        }
    }
}

#Preview {
    VStack {
        DaysSincePurchaseView(purchaseDate: Date().addingTimeInterval(-86400 * 5)) // 5 days ago
        DaysSincePurchaseView(purchaseDate: Date().addingTimeInterval(-86400 * 125)) // 125 days ago
    }
    .padding()
    .background(Color.gray.opacity(0.1))
}
