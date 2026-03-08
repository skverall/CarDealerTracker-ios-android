import SwiftUI
import Charts

struct FinancialCard: View {
    let title: String
    let amount: Decimal
    let icon: String
    let color: Color
    var isCount: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.12))
                    .clipShape(Circle())
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundColor(ColorTheme.secondaryText)
                    .lineLimit(1)
                
                if isCount {
                    Text("\(NSDecimalNumber(decimal: amount).intValue)")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(ColorTheme.primaryText)
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                } else {
                    Text(amount.asCurrency())
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(ColorTheme.primaryText)
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ColorTheme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.gray.opacity(0.06), lineWidth: 1)
        )
    }
}

struct TodayExpenseCard: View {
    @ObservedObject var expense: Expense
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    ZStack {
                        Circle()
                            .fill(ColorTheme.categoryColor(for: expense.category ?? "").opacity(0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: expense.categoryIcon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(ColorTheme.categoryColor(for: expense.category ?? ""))
                    }
                    
                    Spacer()
                    
                    Text(expense.timeString)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(ColorTheme.background)
                        .foregroundColor(ColorTheme.secondaryText)
                        .clipShape(Capsule())
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(expense.amountDecimal.asCurrency())
                        .font(.title2.weight(.bold))
                        .foregroundColor(ColorTheme.primaryText)
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                    
                    Text(expense.vehicleTitle)
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.secondaryText)
                        .lineLimit(1)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
            .background(ColorTheme.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.gray.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct EmptyTodayCard: View {
    let addAction: () -> Void

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            Image(systemName: "list.bullet.clipboard")
                .font(.largeTitle)
                .foregroundColor(ColorTheme.secondaryText.opacity(0.5))
                .padding(.bottom, 4)
            
            Text("no_expenses_today".localizedString)
                .font(.headline)
                .foregroundColor(ColorTheme.primaryText)
            
            Button(action: addAction) {
                Text("add_expense".localizedString)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(ColorTheme.primary)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .shadow(color: ColorTheme.primary.opacity(0.3), radius: 4, x: 0, y: 2)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(ColorTheme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 2)
    }
}

struct AddQuickCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Circle()
                    .fill(ColorTheme.primary.opacity(0.1))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "plus")
                            .font(.title3.weight(.semibold))
                            .foregroundColor(ColorTheme.primary)
                    )
                
                Text("add_new".localizedString)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(ColorTheme.primary)
            }
            .frame(maxWidth: .infinity, minHeight: 130)
            .background(ColorTheme.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(ColorTheme.primary.opacity(0.1), lineWidth: 1)
                    .padding(1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct SummaryOverviewCard: View {
    let totalSpent: Decimal
    let changePercent: Double?
    let trendPoints: [TrendPoint]
    let range: DashboardTimeRange
    
    private var xDomain: ClosedRange<Date> {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: Date())
        switch range {
        case .today:
            let end = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
            return startOfDay...end
        case .week:
            let start = cal.date(byAdding: .day, value: -6, to: startOfDay) ?? startOfDay
            let end = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
            return start...end
        case .month:
            let start = cal.date(byAdding: .day, value: -29, to: startOfDay) ?? startOfDay
            let end = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
            return start...end
        case .threeMonths:
            let start = cal.date(byAdding: .month, value: -3, to: startOfDay) ?? startOfDay
            let end = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
            return start...end
        case .sixMonths:
            let start = cal.date(byAdding: .month, value: -6, to: startOfDay) ?? startOfDay
            let end = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
            return start...end
        case .all:
            let start = cal.date(byAdding: .month, value: -11, to: startOfDay) ?? startOfDay
            let alignedStart = cal.date(from: cal.dateComponents([.year, .month], from: start)) ?? start
            let end = cal.date(byAdding: .month, value: 12, to: alignedStart) ?? alignedStart
            return alignedStart...end
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("total_spend".localizedString + " (\(range.displayLabel))")
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.secondaryText)
                    
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(totalSpent.asCurrency())
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(ColorTheme.primaryText)
                        
                        if let changePercent {
                            HStack(spacing: 4) {
                                Image(systemName: changePercent >= 0 ? "arrow.up.right" : "arrow.down.right")
                                Text("\(abs(changePercent).formatted(.number.precision(.fractionLength(1))))%")
                            }
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(changePercent >= 0 ? ColorTheme.danger.opacity(0.1) : ColorTheme.success.opacity(0.1))
                            .foregroundColor(changePercent >= 0 ? ColorTheme.danger : ColorTheme.success)
                            .clipShape(Capsule())
                        }
                    }
                }
                Spacer()
            }

            if !trendPoints.isEmpty {
                Chart(trendPoints) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Amount", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [ColorTheme.primary.opacity(0.2), ColorTheme.primary.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Amount", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(ColorTheme.primary)
                    .lineStyle(StrokeStyle(lineWidth: 3))
                }
                .frame(height: 160)
                .chartXScale(domain: xDomain)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
            } else {
                Text("no_spending_data".localizedString)
                    .font(.footnote)
                    .foregroundColor(ColorTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            }
        }
        .padding(24)
        .background(ColorTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.gray.opacity(0.06), lineWidth: 1)
        )
    }
}

struct ProfitOverviewCard: View {
    let totalProfit: Decimal
    let trendPoints: [TrendPoint]
    let range: DashboardTimeRange
    
    private var xDomain: ClosedRange<Date> {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: Date())
        switch range {
        case .today:
            let end = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
            return startOfDay...end
        case .week:
            let start = cal.date(byAdding: .day, value: -6, to: startOfDay) ?? startOfDay
            let end = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
            return start...end
        case .month:
            let start = cal.date(byAdding: .day, value: -29, to: startOfDay) ?? startOfDay
            let end = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
            return start...end
        case .threeMonths:
            let start = cal.date(byAdding: .month, value: -3, to: startOfDay) ?? startOfDay
            let end = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
            return start...end
        case .sixMonths:
            let start = cal.date(byAdding: .month, value: -6, to: startOfDay) ?? startOfDay
            let end = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
            return start...end
        case .all:
            let start = cal.date(byAdding: .month, value: -11, to: startOfDay) ?? startOfDay
            let alignedStart = cal.date(from: cal.dateComponents([.year, .month], from: start)) ?? start
            let end = cal.date(byAdding: .month, value: 12, to: alignedStart) ?? alignedStart
            return alignedStart...end
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("net_profit".localizedString + " (\(range.displayLabel))")
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.secondaryText)
                    
                    Text(totalProfit.asCurrency())
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(ColorTheme.primaryText)
                }
                Spacer()
            }

            if !trendPoints.isEmpty {
                Chart(trendPoints) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Amount", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.green.opacity(0.2), Color.green.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Amount", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.green)
                    .lineStyle(StrokeStyle(lineWidth: 3))
                }
                .frame(height: 160)
                .chartXScale(domain: xDomain)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
            } else {
                Text("no_profit_data".localizedString)
                    .font(.footnote)
                    .foregroundColor(ColorTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            }
        }
        .padding(24)
        .background(ColorTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.gray.opacity(0.06), lineWidth: 1)
        )
    }
}

struct CategoryBreakdownCard: View {
    let stats: [CategoryStat]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("spending_breakdown".localizedString)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(ColorTheme.primaryText)

            if stats.isEmpty {
                Text("no_expenses_period".localizedString)
                    .font(.footnote)
                    .foregroundColor(ColorTheme.secondaryText)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 16) {
                    ForEach(stats) { stat in
                        CategoryBreakdownRow(stat: stat)
                    }
                }
            }
        }
        .padding(24)
        .background(ColorTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.gray.opacity(0.06), lineWidth: 1)
        )
    }
}

struct CategoryBreakdownRow: View {
    let stat: CategoryStat

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                HStack(spacing: 12) {
                    Circle()
                        .fill(ColorTheme.categoryColor(for: stat.key))
                        .frame(width: 12, height: 12)
                    Text(stat.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(ColorTheme.primaryText)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(stat.amount.asCurrency())
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(ColorTheme.primaryText)
                    Text("\(stat.percent, format: .number.precision(.fractionLength(1)))%")
                        .font(.caption2)
                        .foregroundColor(ColorTheme.secondaryText)
                }
            }

            GeometryReader { proxy in
                let width = proxy.size.width * CGFloat(max(stat.percent / 100.0, 0))
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(ColorTheme.background)
                        .frame(height: 6)
                    
                    Capsule()
                        .fill(ColorTheme.categoryColor(for: stat.key))
                        .frame(width: max(width, 6), height: 6)
                }
            }
            .frame(height: 6)
        }
    }
}

struct RecentExpenseRow: View {
    @ObservedObject var expense: Expense

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(ColorTheme.categoryColor(for: expense.category ?? "").opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: expense.categoryIcon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(ColorTheme.categoryColor(for: expense.category ?? ""))
            }

            VStack(alignment: .leading, spacing: 4) {
                let description = expense.expenseDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
                Text((description?.isEmpty == false ? description : nil) ?? expense.categoryTitle)
                    .font(.body.weight(.semibold))
                    .foregroundColor(ColorTheme.primaryText)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    let subtitle = expense.vehicleSubtitle
                    Text(subtitle)
                        .lineLimit(1)
                    if !subtitle.isEmpty {
                        Text("•")
                            .opacity(0.5)
                    }
                    Text(expense.dateString)
                }
                .font(.caption)
                .foregroundColor(ColorTheme.secondaryText)
            }

            Spacer()

            Text(expense.amountDecimal.asCurrency())
                .font(.headline)
                .foregroundColor(ColorTheme.primaryText)
        }
        .padding(14)
        .background(ColorTheme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.gray.opacity(0.08), lineWidth: 1)
        )
    }
}
