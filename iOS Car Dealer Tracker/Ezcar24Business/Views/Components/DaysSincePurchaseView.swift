import SwiftUI

struct DaysSincePurchaseView: View {
    let purchaseDate: Date
    @State private var days: Int = 0
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.caption2.weight(.medium))
                .foregroundColor(ColorTheme.primary)
            
            Text("\(days)d in stock")
                .font(.caption2.weight(.semibold))
                .foregroundColor(ColorTheme.primaryText)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(days)))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(ColorTheme.secondaryBackground)
        .overlay(
            Capsule()
                .strokeBorder(ColorTheme.primary.opacity(0.15), lineWidth: 1)
        )
        .clipShape(Capsule())
        .onAppear {
            calculateDays()
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                isAnimating = true
            }
            animateCountUp()
        }
    }
    
    private func calculateDays() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: purchaseDate)
        let end = calendar.startOfDay(for: Date())
        _ = calendar.dateComponents([.day], from: start, to: end)
    }
    
    private func animateCountUp() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: purchaseDate)
        let end = calendar.startOfDay(for: Date())
        let targetDays = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        
        let _ = 1.0 // duration retained conceptually but unused

        
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
