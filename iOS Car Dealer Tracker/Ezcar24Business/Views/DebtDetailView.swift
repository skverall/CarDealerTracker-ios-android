import SwiftUI

struct DebtDetailView: View {
    @ObservedObject var debt: Debt
    @ObservedObject var viewModel: DebtViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var showAddPayment = false
    @State private var showDeleteAlert = false

    private var paymentItems: [DebtPayment] {
        debt.paymentsArray
    }

    var body: some View {
        List {
            Section {
                DebtSummaryCard(debt: debt)
            }

            Section {
                if paymentItems.isEmpty {
                    ContentUnavailableView("No Payments", systemImage: "creditcard", description: Text("Record a payment to reduce the balance."))
                } else {
                    ForEach(paymentItems, id: \.objectID) { payment in
                        DebtPaymentRow(payment: payment, direction: debt.directionEnum)
                    }
                    .onDelete(perform: deletePayments)
                }
            } header: {
                Text("Payments")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("debt_details".localizedString)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddPayment = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(ColorTheme.primary)
                }
                .disabled(debt.isPaid)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .alert("Delete Debt", isPresented: $showDeleteAlert) {
            Button("cancel".localizedString, role: .cancel) {}
            Button("delete".localizedString, role: .destructive) {
                viewModel.deleteDebt(debt)
                dismiss()
            }
        } message: {
            Text("This will remove the debt and all its payments.")
        }
        .sheet(isPresented: $showAddPayment) {
            AddDebtPaymentView(debt: debt)
                .presentationDetents([.medium, .large])
        }
    }

    private func deletePayments(at offsets: IndexSet) {
        for index in offsets {
            let payment = paymentItems[index]
            viewModel.deletePayment(payment)
        }
    }
}

private struct DebtSummaryCard: View {
    @ObservedObject var debt: Debt

    private var remainingColor: Color {
        if debt.isPaid {
            return ColorTheme.secondaryText
        }
        switch debt.directionEnum {
        case .owedToMe:
            return ColorTheme.success
        case .iOwe:
            return ColorTheme.danger
        }
    }

    private var dueDateText: String? {
        guard let due = debt.dueDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: due)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(debt.counterpartyName ?? "Unknown")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(ColorTheme.primaryText)

                    if let phone = debt.counterpartyPhone, !phone.isEmpty {
                        Text(phone)
                            .font(.caption)
                            .foregroundColor(ColorTheme.secondaryText)
                    }

                    if let dueText = dueDateText {
                        Text("Due \(dueText)")
                            .font(.caption)
                            .foregroundColor(ColorTheme.secondaryText)
                    }
                }

                Spacer()

                DebtDirectionTag(direction: debt.directionEnum)
            }

            HStack(spacing: 0) {
                FinancialColumn(title: "Total", amount: debt.totalAmountDecimal, color: ColorTheme.secondaryText)
                Divider().frame(height: 40)
                FinancialColumn(title: "Paid", amount: debt.totalPaid, color: ColorTheme.primaryText)
                Divider().frame(height: 40)
                FinancialColumn(title: "Remaining", amount: debt.outstandingAmount, color: remainingColor, isBold: true)
            }
            .padding(.vertical, 8)
            .background(ColorTheme.secondaryBackground.opacity(0.5))

            if let notes = debt.notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("notes".localizedString)
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)
                    Text(notes)
                        .font(.body)
                        .foregroundColor(ColorTheme.primaryText)
                }
            }
        }
        .padding(16)
        .background(ColorTheme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct DebtDirectionTag: View {
    let direction: DebtDirection

    var body: some View {
        Text(direction.badgeTitle)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(direction.color.opacity(0.15))
            .foregroundColor(direction.color)
            .clipShape(Capsule())
    }
}

private struct DebtPaymentRow: View {
    let payment: DebtPayment
    let direction: DebtDirection

    private var amountColor: Color {
        switch direction {
        case .owedToMe:
            return ColorTheme.success
        case .iOwe:
            return ColorTheme.danger
        }
    }

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: payment.date ?? Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text((payment.amount?.decimalValue ?? 0).asCurrency())
                    .font(.headline)
                    .foregroundColor(amountColor)
                Spacer()
                Text(dateText)
                    .font(.caption)
                    .foregroundColor(ColorTheme.secondaryText)
            }

            HStack(spacing: 8) {
                if let method = payment.paymentMethod, !method.isEmpty {
                    Label(method, systemImage: "creditcard")
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)
                }

                if let account = payment.account?.accountType, !account.isEmpty {
                    Label(account, systemImage: "building.columns.fill")
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)
                }
            }

            if let note = payment.note, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundColor(ColorTheme.secondaryText)
            }
        }
        .padding(.vertical, 4)
    }
}
