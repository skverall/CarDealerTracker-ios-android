//
//  ColorTheme.swift
//  Ezcar24Business
//
//  Professional color scheme for business app
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
    
    // Background colors
    static let background = Color(UIColor.systemGroupedBackground)
    static let secondaryBackground = Color(UIColor.secondarySystemGroupedBackground)
    static let cardBackground = Color(UIColor.secondarySystemGroupedBackground)
    
    // Text colors
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let tertiaryText = Color(UIColor.tertiaryLabel)
    
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

// Custom card modifier
struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(ColorTheme.cardBackground)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
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
