//
//  AgingBucketBadge.swift
//  Ezcar24Business
//
//  Badge showing aging bucket with color coding
//

import SwiftUI

struct AgingBucketBadge: View {
    let bucket: AgingBucket
    var showCount: Int? = nil
    var isLarge: Bool = false
    
    private var color: Color {
        switch bucket {
        case .fresh:
            return ColorTheme.success
        case .normal:
            return Color.blue
        case .aging:
            return ColorTheme.warning
        case .stale:
            return Color.orange
        case .critical:
            return ColorTheme.danger
        }
    }
    
    var body: some View {
        HStack(spacing: isLarge ? 6 : 4) {
            Circle()
                .fill(color)
                .frame(width: isLarge ? 8 : 6, height: isLarge ? 8 : 6)
            
            Text(bucket.displayName)
                .font(isLarge ? .subheadline : .caption)
                .fontWeight(.medium)
                .foregroundColor(color)
            
            if let count = showCount {
                Text("(\(count))")
                    .font(isLarge ? .caption : .caption2)
                    .foregroundColor(ColorTheme.secondaryText)
            }
        }
        .padding(.horizontal, isLarge ? 12 : 8)
        .padding(.vertical, isLarge ? 6 : 4)
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

struct AgingBucketBar: View {
    let distribution: [AgingBucket: Int]
    let total: Int
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                ForEach(AgingBucket.allCases, id: \.self) { bucket in
                    let count = distribution[bucket] ?? 0
                    if count > 0 {
                        Rectangle()
                            .fill(colorForBucket(bucket))
                            .frame(width: widthForBucket(bucket, in: geometry.size.width))
                    }
                }
            }
            .cornerRadius(4)
        }
        .frame(height: 12)
    }
    
    private func colorForBucket(_ bucket: AgingBucket) -> Color {
        switch bucket {
        case .fresh:
            return ColorTheme.success
        case .normal:
            return Color.blue
        case .aging:
            return ColorTheme.warning
        case .stale:
            return Color.orange
        case .critical:
            return ColorTheme.danger
        }
    }
    
    private func widthForBucket(_ bucket: AgingBucket, in totalWidth: CGFloat) -> CGFloat {
        let count = distribution[bucket] ?? 0
        guard total > 0 else { return 0 }
        let percentage = CGFloat(count) / CGFloat(total)
        return max(4, totalWidth * percentage)
    }
}

struct AgingDistributionChart: View {
    let distribution: [AgingBucket: Int]
    
    private var total: Int {
        distribution.values.reduce(0, +)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            AgingBucketBar(distribution: distribution, total: total)
            
            HStack(spacing: 12) {
                ForEach(AgingBucket.allCases, id: \.self) { bucket in
                    let count = distribution[bucket] ?? 0
                    if count > 0 {
                        AgingBucketBadge(bucket: bucket, showCount: count)
                    }
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        HStack(spacing: 12) {
            AgingBucketBadge(bucket: .fresh)
            AgingBucketBadge(bucket: .normal)
            AgingBucketBadge(bucket: .aging)
            AgingBucketBadge(bucket: .stale)
            AgingBucketBadge(bucket: .critical)
        }
        
        HStack(spacing: 12) {
            AgingBucketBadge(bucket: .fresh, showCount: 5, isLarge: true)
            AgingBucketBadge(bucket: .aging, showCount: 3, isLarge: true)
            AgingBucketBadge(bucket: .critical, showCount: 1, isLarge: true)
        }
        
        AgingBucketBar(
            distribution: [
                .fresh: 5,
                .normal: 8,
                .aging: 3,
                .stale: 2,
                .critical: 1
            ],
            total: 19
        )
        .frame(height: 12)
        
        AgingDistributionChart(distribution: [
            .fresh: 5,
            .normal: 8,
            .aging: 3,
            .stale: 2,
            .critical: 1
        ])
    }
    .padding()
    .background(ColorTheme.secondaryBackground)
}