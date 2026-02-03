//
//  DaysInInventoryIndicator.swift
//  Ezcar24Business
//
//  Shows days in inventory with color coding
//

import SwiftUI

struct DaysInInventoryIndicator: View {
    let days: Int
    var showLabel: Bool = true
    var isCompact: Bool = false
    
    private var color: Color {
        switch days {
        case 0...30:
            return ColorTheme.success
        case 31...60:
            return ColorTheme.warning
        case 61...90:
            return Color.orange
        default:
            return ColorTheme.danger
        }
    }
    
    private var backgroundOpacity: Double {
        switch days {
        case 0...30:
            return 0.15
        case 31...60:
            return 0.2
        case 61...90:
            return 0.25
        default:
            return 0.3
        }
    }
    
    var body: some View {
        if isCompact {
            compactView
        } else {
            detailedView
        }
    }
    
    private var compactView: some View {
        HStack(spacing: 4) {
            Image(systemName: "calendar")
                .font(.caption2)
            
            Text("\(days)d")
                .font(.caption2)
                .fontWeight(.medium)
        }
        .foregroundColor(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(backgroundOpacity))
        )
    }
    
    private var detailedView: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.subheadline)
                .foregroundColor(color)
            
            if showLabel {
                Text("days_in_inventory".localizedString)
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.secondaryText)
            }
            
            Spacer()
            
            Text("\(days)")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text("days".localizedString)
                .font(.caption)
                .foregroundColor(ColorTheme.secondaryText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(backgroundOpacity))
        )
    }
    
    private var iconName: String {
        switch days {
        case 0...30:
            return "checkmark.circle.fill"
        case 31...60:
            return "exclamationmark.circle.fill"
        case 61...90:
            return "exclamationmark.triangle.fill"
        default:
            return "flame.fill"
        }
    }
}

struct DaysInInventoryBadge: View {
    let days: Int
    
    private var color: Color {
        switch days {
        case 0...30:
            return ColorTheme.success
        case 31...60:
            return ColorTheme.warning
        case 61...90:
            return Color.orange
        default:
            return ColorTheme.danger
        }
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            
            Text("\(days)d")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(color.opacity(0.1))
        )
        .overlay(
            Capsule()
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
}

#Preview {
    VStack(spacing: 16) {
        DaysInInventoryIndicator(days: 15, isCompact: true)
        DaysInInventoryIndicator(days: 45, isCompact: true)
        DaysInInventoryIndicator(days: 75, isCompact: true)
        DaysInInventoryIndicator(days: 120, isCompact: true)
        
        Divider()
        
        DaysInInventoryIndicator(days: 15, isCompact: false)
        DaysInInventoryIndicator(days: 45, isCompact: false)
        DaysInInventoryIndicator(days: 75, isCompact: false)
        DaysInInventoryIndicator(days: 120, isCompact: false)
        
        Divider()
        
        HStack(spacing: 12) {
            DaysInInventoryBadge(days: 15)
            DaysInInventoryBadge(days: 45)
            DaysInInventoryBadge(days: 75)
            DaysInInventoryBadge(days: 120)
        }
    }
    .padding()
    .background(ColorTheme.secondaryBackground)
}