//
//  InventoryHealthScore.swift
//  Ezcar24Business
//
//  Circular health score display with color coding and grade
//

import SwiftUI

struct InventoryHealthScore: View {
    let score: Int
    var size: CGFloat = 120
    var showGrade: Bool = true
    var showLabel: Bool = true
    
    private var color: Color {
        switch score {
        case 90...100:
            return ColorTheme.success
        case 75..<90:
            return ColorTheme.warning
        case 60..<75:
            return Color.orange
        default:
            return ColorTheme.danger
        }
    }
    
    private var grade: String {
        switch score {
        case 90...100:
            return "A"
        case 80..<90:
            return "B"
        case 70..<80:
            return "C"
        case 60..<70:
            return "D"
        default:
            return "F"
        }
    }
    
    private var statusText: String {
        switch score {
        case 90...100:
            return "excellent".localizedString
        case 75..<90:
            return "good".localizedString
        case 60..<75:
            return "needs_attention".localizedString
        default:
            return "critical".localizedString
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: size * 0.08)
                    .frame(width: size, height: size)
                
                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(
                        color,
                        style: StrokeStyle(
                            lineWidth: size * 0.08,
                            lineCap: .round
                        )
                    )
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.8), value: score)
                
                VStack(spacing: 2) {
                    Text("\(score)")
                        .font(.system(size: size * 0.35, weight: .bold, design: .rounded))
                        .foregroundColor(color)
                    
                    if showGrade {
                        Text(grade)
                            .font(.system(size: size * 0.2, weight: .bold, design: .rounded))
                            .foregroundColor(color.opacity(0.8))
                    }
                }
            }
            
            if showLabel {
                VStack(spacing: 2) {
                    Text("health_score".localizedString)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(ColorTheme.primaryText)
                    
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(color)
                        .fontWeight(.medium)
                }
            }
        }
    }
}

struct InventoryHealthScoreCompact: View {
    let score: Int
    var size: CGFloat = 50
    
    private var color: Color {
        switch score {
        case 90...100:
            return ColorTheme.success
        case 75..<90:
            return ColorTheme.warning
        case 60..<75:
            return Color.orange
        default:
            return ColorTheme.danger
        }
    }
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: size * 0.1)
                .frame(width: size, height: size)
            
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(
                    color,
                    style: StrokeStyle(
                        lineWidth: size * 0.1,
                        lineCap: .round
                    )
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
            
            Text("\(score)")
                .font(.system(size: size * 0.40, weight: .bold, design: .rounded))
                .foregroundColor(color)
        }
    }
}

struct InventoryMetricsCard: View {
    let title: String
    let value: String
    let subtitle: String?
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(ColorTheme.primaryText)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(ColorTheme.secondaryText)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(ColorTheme.tertiaryText)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ColorTheme.cardBackground)
        .cornerRadius(12)
    }
}

struct TurnoverMetricsCard: View {
    let ratio: Double
    let averageDays: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "arrow.2.circlepath")
                    .font(.title3)
                    .foregroundColor(ColorTheme.primary)
                
                Spacer()
            }
            
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: "%.1f", ratio))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(ColorTheme.primaryText)
                    
                    Text("turnover_ratio".localizedString)
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)
                }
                
                Divider()
                    .frame(height: 40)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(averageDays)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(ColorTheme.primaryText)
                    
                    Text("avg_days".localizedString)
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)
                }
            }
        }
        .padding()
        .background(ColorTheme.cardBackground)
        .cornerRadius(12)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 24) {
            HStack(spacing: 20) {
                InventoryHealthScore(score: 95, size: 100)
                InventoryHealthScore(score: 82, size: 100)
                InventoryHealthScore(score: 65, size: 100)
                InventoryHealthScore(score: 45, size: 100)
            }
            
            Divider()
            
            HStack(spacing: 16) {
                InventoryHealthScoreCompact(score: 95, size: 50)
                InventoryHealthScoreCompact(score: 82, size: 50)
                InventoryHealthScoreCompact(score: 65, size: 50)
                InventoryHealthScoreCompact(score: 45, size: 50)
            }
            
            Divider()
            
            HStack(spacing: 12) {
                InventoryMetricsCard(
                    title: "Total Holding Cost",
                    value: "$12,450",
                    subtitle: "Across 19 vehicles",
                    icon: "dollarsign.circle.fill",
                    color: ColorTheme.warning
                )
                
                InventoryMetricsCard(
                    title: "Avg Days in Inventory",
                    value: "45",
                    subtitle: "Target: < 30 days",
                    icon: "calendar",
                    color: ColorTheme.primary
                )
            }
            
            TurnoverMetricsCard(ratio: 8.1, averageDays: 45)
        }
        .padding()
    }
    .background(ColorTheme.secondaryBackground)
}