//
//  ColorTheme.swift
//  Ezcar24Business
//
//  Premium color scheme for business app featuring deep gradients and glassmorphism
//

import SwiftUI

struct ColorTheme {
    // Primary brand colors
    static let primary = Color(UIColor { traitCollection in
        return traitCollection.userInterfaceStyle == .dark 
            ? UIColor(red: 0.28, green: 0.52, blue: 0.90, alpha: 1.0) // Lighter blue for Dark Mode
            : UIColor(red: 0.09, green: 0.28, blue: 0.55, alpha: 1.0) // Deep navy for Light Mode
    })
    static let secondary = Color(red: 0.18, green: 0.52, blue: 0.92) // Bright blue
    static let accent = Color(red: 0.98, green: 0.55, blue: 0.22) // Warm orange accent
    static let dealerGreen = Color(red: 0/255, green: 210/255, blue: 106/255) // Bright, clean green for expenses UI
    static let purple = Color(red: 0.52, green: 0.43, blue: 0.95)
    
    // Status colors
    static let success = Color(red: 0.16, green: 0.67, blue: 0.39) // Green
    static let warning = Color(red: 1.0, green: 0.82, blue: 0.26) // Yellow
    static let danger = Color(red: 0.9, green: 0.2, blue: 0.26) // Red
    
    // Background colors (True Dark Mode Excellence & Crisp Light Mode)
    static let background = Color(UIColor { traitCollection in 
        traitCollection.userInterfaceStyle == .dark ? .black : UIColor(red: 0.96, green: 0.96, blue: 0.98, alpha: 1.0)
    })
    static let secondaryBackground = Color(UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark ? UIColor(white: 0.08, alpha: 1.0) : .white
    })
    static let cardBackground = Color(UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark ? UIColor(white: 0.12, alpha: 1.0) : .white
    })
    
    // Text colors
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let tertiaryText = Color(UIColor.tertiaryLabel)
    
    // Premium Gradients
    static let premiumAssetsGradient = LinearGradient(
        colors: [Color(red: 0.25, green: 0.35, blue: 0.95), Color(red: 0.45, green: 0.15, blue: 0.85)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    
    static let premiumProfitGradient = LinearGradient(
        colors: [Color(red: 0.15, green: 0.75, blue: 0.45), Color(red: 0.0, green: 0.5, blue: 0.3)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    
    // Glossy glass borders for cards
    static let glossyGlassBorder = LinearGradient(
        colors: [.white.opacity(0.4), .white.opacity(0.0), .white.opacity(0.1)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    
    // Vehicle status colors
    static func statusColor(for status: String) -> Color {
        switch status {
        case "reserved":
            return success
        case "on_sale":
            return Color(red: 0.0, green: 0.48, blue: 0.8) // blue
        case "available":
            return Color(red: 0.0, green: 0.48, blue: 0.8) // backward compatibility
        case "sold":
            return success // green
        case "in_transit":
            return warning
        case "under_service":
            return Color(red: 0.6, green: 0.4, blue: 0.8)
        default:
            return Color.gray
        }
    }

    // Expense category colors
    static func categoryColor(for category: String) -> Color {
        switch category {
        case "vehicle":
            return primary
        case "personal":
            return accent
        case "employee":
            return Color(red: 0.6, green: 0.4, blue: 0.8)
        default:
            return Color.gray
        }
    }
}

// Custom card modifier (Elevated Glassmorphism)
struct CardModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    func body(content: Content) -> some View {
        content
            .background(ColorTheme.cardBackground)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(colorScheme == .dark ? ColorTheme.glossyGlassBorder : LinearGradient(colors: [.black.opacity(0.04), .black.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.04), radius: 10, x: 0, y: 5)
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardModifier())
    }
    
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    func onTapToDismissKeyboard() -> some View {
        self.onTapGesture {
            hideKeyboard()
        }
    }
}

// MARK: - Premium Button Styles

struct HapticScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.snappy(duration: 0.18, extraBounce: 0.02), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == HapticScaleButtonStyle {
    static var hapticScale: HapticScaleButtonStyle {
        HapticScaleButtonStyle()
    }
}
