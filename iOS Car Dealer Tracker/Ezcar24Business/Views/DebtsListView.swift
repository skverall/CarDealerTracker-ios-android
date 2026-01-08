import SwiftUI

struct DebtsListView: View {
    @ObservedObject var viewModel: DebtViewModel
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var cloudSyncManager: CloudSyncManager

    var body: some View {
        Group {
            if viewModel.debtItems.isEmpty {
                EmptyDebtsView()
            } else {
                List {
                    ForEach(viewModel.debtItems) { item in
                        NavigationLink(destination: DebtDetailView(debt: item.debt, viewModel: viewModel)) {
                            DebtCard(item: item)
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                    .onDelete(perform: deleteItems)
                }
                .listStyle(.plain)
                .refreshable {
                    if case .signedIn(let user) = sessionStore.status {
                        await cloudSyncManager.manualSync(user: user)
                        viewModel.fetchDebts()
                    }
                }
            }
        }
    }

    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            let debt = viewModel.debtItems[index].debt
            viewModel.deleteDebt(debt)
        }
    }
}

private struct DebtCard: View {
    let item: DebtItem

    private var remainingColor: Color {
        if item.isPaid {
            return ColorTheme.secondaryText
        }
        switch item.direction {
        case .owedToMe:
            return ColorTheme.success
        case .iOwe:
            return ColorTheme.danger
        }
    }

    private var dueDateText: String? {
        guard let due = item.dueDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: due)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.headline)
                        .foregroundColor(ColorTheme.primaryText)

                    if !item.phone.isEmpty {
                        Text(item.phone)
                            .font(.caption)
                            .foregroundColor(ColorTheme.secondaryText)
                    }

                    if let dueText = dueDateText {
                        HStack(spacing: 6) {
                            Image(systemName: item.isOverdue ? "exclamationmark.triangle.fill" : "calendar")
                                .font(.caption2)
                                .foregroundColor(item.isOverdue ? ColorTheme.danger : ColorTheme.secondaryText)
                            Text(item.isOverdue ? "Overdue • \(dueText)" : "Due \(dueText)")
                                .font(.caption)
                                .foregroundColor(item.isOverdue ? ColorTheme.danger : ColorTheme.secondaryText)
                        }
                    }
                }

                Spacer()

                DebtTag(text: item.direction.badgeTitle, color: item.direction.color)
            }

            Divider()

            HStack(spacing: 0) {
                FinancialColumn(title: "Total", amount: item.totalAmount, color: ColorTheme.secondaryText)
                Divider().frame(height: 40)
                FinancialColumn(title: "Paid", amount: item.paidAmount, color: ColorTheme.primaryText)
                Divider().frame(height: 40)
                FinancialColumn(title: "Remaining", amount: item.outstandingAmount, color: remainingColor, isBold: true)
            }
            .padding(.vertical, 8)
            .background(ColorTheme.secondaryBackground.opacity(0.5))
        }
        .padding(16)
        .background(ColorTheme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}

private struct DebtTag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}

private struct EmptyDebtsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "person.2.wave.2")
                .font(.system(size: 60))
                .foregroundColor(ColorTheme.secondaryText.opacity(0.3))

            Text("No Debts Yet")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(ColorTheme.primaryText)

            Text("Track money you owe or that is owed to you.")
                .font(.subheadline)
                .foregroundColor(ColorTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
        }
    }
}
