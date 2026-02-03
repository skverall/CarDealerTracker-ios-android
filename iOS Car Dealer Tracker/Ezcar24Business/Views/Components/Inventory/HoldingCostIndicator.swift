//
//  HoldingCostIndicator.swift
//  Ezcar24Business
//
//  Shows daily holding cost and accumulated cost
//

import SwiftUI

struct HoldingCostIndicator: View {
    let dailyCost: Decimal
    let accumulatedCost: Decimal
    var isCompact: Bool = false
    
    var body: some View {
        if isCompact {
            compactView
        } else {
            detailedView
        }
    }
    
    private var compactView: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.caption)
                .foregroundColor(accumulatedCost > 0 ? ColorTheme.warning : ColorTheme.secondaryText)
            
            Text(accumulatedCost.asCurrency())
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(accumulatedCost > 0 ? ColorTheme.warning : ColorTheme.secondaryText)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(accumulatedCost > 0 ? ColorTheme.warning.opacity(0.1) : ColorTheme.secondaryBackground)
        )
    }
    
    private var detailedView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title3)
                    .foregroundColor(ColorTheme.primary)
                
                Text("holding_cost".localizedString)
                    .font(.headline)
                    .foregroundColor(ColorTheme.primaryText)
                
                Spacer()
            }
            
            Divider()
            
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("daily_rate".localizedString)
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)
                    
                    Text(dailyCost.asCurrency())
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(ColorTheme.primaryText)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("accumulated".localizedString)
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)
                    
                    Text(accumulatedCost.asCurrency())
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(accumulatedCost > 0 ? ColorTheme.warning : ColorTheme.success)
                }
            }
        }
        .padding()
        .background(ColorTheme.cardBackground)
        .cornerRadius(12)
    }
}

struct HoldingCostMiniIndicator: View {
    let dailyCost: Decimal
    let accumulatedCost: Decimal
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "dollarsign.circle.fill")
                .font(.caption2)
                .foregroundColor(accumulatedCost > 0 ? ColorTheme.warning : ColorTheme.secondaryText)
            
            VStack(alignment: .leading, spacing: 0) {
                Text(accumulatedCost.asCurrency())
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(accumulatedCost > 0 ? ColorTheme.warning : ColorTheme.secondaryText)
                
                if dailyCost > 0 {
                    Text("\(dailyCost.asCurrency())/day")
                        .font(.caption2)
                        .foregroundColor(ColorTheme.tertiaryText)
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        HoldingCostIndicator(
            dailyCost: 45.50,
            accumulatedCost: 1365.00,
            isCompact: true
        )
        
        HoldingCostIndicator(
            dailyCost: 45.50,
            accumulatedCost: 1365.00,
            isCompact: false
        )
        
        HoldingCostMiniIndicator(
            dailyCost: 45.50,
            accumulatedCost: 1365.00
        )
    }
    .padding()
    .background(ColorTheme.secondaryBackground)
}