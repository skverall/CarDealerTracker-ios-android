//
//  ROIBadge.swift
//  Ezcar24Business
//
//  Shows ROI percentage with color coding
//

import SwiftUI

struct ROIBadge: View {
    let roi: Decimal
    var isCompact: Bool = false
    var showLabel: Bool = true
    
    private var color: Color {
        let roiValue = NSDecimalNumber(decimal: roi).doubleValue
        if roiValue >= 20 {
            return ColorTheme.success
        } else if roiValue >= 10 {
            return Color.blue
        } else if roiValue >= 0 {
            return ColorTheme.warning
        } else {
            return ColorTheme.danger
        }
    }
    
    private var iconName: String {
        let roiValue = NSDecimalNumber(decimal: roi).doubleValue
        if roiValue >= 0 {
            return "arrow.up.right"
        } else {
            return "arrow.down.right"
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
        HStack(spacing: 2) {
            Image(systemName: iconName)
                .font(.caption2)
            
            Text(String(format: "%.1f%%", NSDecimalNumber(decimal: roi).doubleValue))
                .font(.caption)
                .fontWeight(.semibold)
        }
        .foregroundColor(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var detailedView: some View {
        HStack(spacing: 8) {
            if showLabel {
                Text("roi".localizedString)
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.secondaryText)
                
                Spacer()
            }
            
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.caption)
                
                Text(String(format: "%.1f%%", NSDecimalNumber(decimal: roi).doubleValue))
                    .font(.headline)
                    .fontWeight(.bold)
            }
            .foregroundColor(color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
}

struct ProfitBadge: View {
    let profit: Decimal
    var isCompact: Bool = false
    
    private var color: Color {
        profit >= 0 ? ColorTheme.success : ColorTheme.danger
    }
    
    private var iconName: String {
        profit >= 0 ? "plus.circle.fill" : "minus.circle.fill"
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(isCompact ? .caption2 : .caption)
            
            Text(profit.asCurrency())
                .font(isCompact ? .caption : .subheadline)
                .fontWeight(.semibold)
        }
        .foregroundColor(color)
        .padding(.horizontal, isCompact ? 6 : 10)
        .padding(.vertical, isCompact ? 2 : 4)
        .background(
            RoundedRectangle(cornerRadius: isCompact ? 4 : 6)
                .fill(color.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: isCompact ? 4 : 6)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
}

#Preview {
    VStack(spacing: 16) {
        HStack(spacing: 12) {
            ROIBadge(roi: 25.5, isCompact: true)
            ROIBadge(roi: 15.0, isCompact: true)
            ROIBadge(roi: 5.0, isCompact: true)
            ROIBadge(roi: -10.0, isCompact: true)
        }
        
        Divider()
        
        ROIBadge(roi: 25.5, isCompact: false)
        ROIBadge(roi: 5.0, isCompact: false)
        ROIBadge(roi: -10.0, isCompact: false)
        
        Divider()
        
        HStack(spacing: 12) {
            ProfitBadge(profit: 5000, isCompact: true)
            ProfitBadge(profit: -1500, isCompact: true)
        }
        
        HStack(spacing: 12) {
            ProfitBadge(profit: 5000, isCompact: false)
            ProfitBadge(profit: -1500, isCompact: false)
        }
    }
    .padding()
    .background(ColorTheme.secondaryBackground)
}