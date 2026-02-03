import SwiftUI

struct DaysSincePurchaseView: View {
    let purchaseDate: Date
    @State private var days: Int = 0
    @State private var isAnimating = false
    
    // Cleaner, more professional look
    private let backgroundColor = Color.blue.opacity(0.1)
    private let foregroundColor = Color.blue
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.caption2)
                .foregroundColor(foregroundColor)
            
            Text("\(days) days")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(foregroundColor)
                // Monospaced digit for stable width during animation if we were counting up rapidly
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(days)))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(backgroundColor)
        .cornerRadius(12)
        .scaleEffect(isAnimating ? 1.05 : 1.0)
        .onAppear {
            // Subtle "pop" animation on appear
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                isAnimating = true
            }
            // Count up animation
            animateCountUp()
        }
    }
    
    private func animateCountUp() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: purchaseDate)
        let end = calendar.startOfDay(for: Date())
        let targetDays = calendar.dateComponents([.day], from: start, to: end).day ?? 0

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
