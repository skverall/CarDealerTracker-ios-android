import SwiftUI

struct DebtsListView: View {
    @ObservedObject var viewModel: DebtViewModel
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var cloudSyncManager: CloudSyncManager
    @ObservedObject private var permissionService = PermissionService.shared

    private var canDeleteRecords: Bool {
        if case .signedIn = sessionStore.status {
            return permissionService.can(.deleteRecords)
        }
        return true
    }

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
                    .deleteDisabled(!canDeleteRecords)
                }
                .listStyle(.plain)
                .padding(.bottom, 90) // Ensure content clears tab bar
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
        guard canDeleteRecords else { return }
        for index in offsets {
            let debt = viewModel.debtItems[index].debt
            viewModel.deleteDebt(debt)
        }
    }
}

struct DebtCard: View {
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
                        .font(.system(.headline, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundColor(ColorTheme.primaryText)

                    if !item.phone.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 10))
                            Text(item.phone)
                                .font(.system(.caption, design: .rounded))
                        }
                        .foregroundColor(ColorTheme.secondaryText)
                    }

                    if let dueText = dueDateText {
                        HStack(spacing: 6) {
                            Image(systemName: item.isOverdue ? "exclamationmark.triangle.fill" : "calendar")
                                .font(.caption2)
                                .foregroundColor(item.isOverdue ? ColorTheme.danger : ColorTheme.secondaryText)
                            Text(item.isOverdue ? String(format: "Overdue • %@".localizedString, dueText) : String(format: "Due %@".localizedString, dueText))
                                .font(.system(.caption, design: .rounded))
                                .foregroundColor(item.isOverdue ? ColorTheme.danger : ColorTheme.secondaryText)
                        }
                    }
                }

                Spacer()

                DebtTag(text: item.direction.badgeTitle, color: item.direction.color)
            }

            Divider()
                .opacity(0.5)

            HStack(spacing: 0) {
                FinancialColumn(title: "Total", amount: item.totalAmount, color: ColorTheme.secondaryText)
                Divider().frame(height: 24)
                FinancialColumn(title: "Paid", amount: item.paidAmount, color: ColorTheme.primaryText)
                Divider().frame(height: 24)
                FinancialColumn(title: "Remaining", amount: item.outstandingAmount, color: remainingColor, isBold: true)
            }
            .padding(.vertical, 8)
            .background(ColorTheme.secondaryBackground.opacity(0.4))
        }
        .cardStyle()
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

struct EmptyDebtsView: View {
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
