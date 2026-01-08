import SwiftUI
import CoreData

struct AddDebtPaymentView: View {
    @ObservedObject var debt: Debt
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var amount: String = ""
    @State private var date: Date = Date()
    @State private var paymentMethod: String = "Cash"
    @State private var note: String = ""
    @State private var selectedAccount: FinancialAccount?

    @State private var isSaving: Bool = false

    private let paymentMethods = ["Cash", "Bank Transfer", "Cheque", "Other"]

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \FinancialAccount.accountType, ascending: true)],
        animation: .default)
    private var accounts: FetchedResults<FinancialAccount>

    private var amountDecimal: Decimal {
        Decimal(string: amount.filter { "0123456789.".contains($0) }) ?? 0
    }

    private var remaining: Decimal {
        debt.outstandingAmount
    }

    private var isFormValid: Bool {
        amountDecimal > 0 && amountDecimal <= remaining
    }

    private var remainingColor: Color {
        switch debt.directionEnum {
        case .owedToMe:
            return ColorTheme.success
        case .iOwe:
            return ColorTheme.danger
        }
    }

    private var selectedAccountLabel: String {
        selectedAccount?.accountType ?? "None"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ColorTheme.background.ignoresSafeArea()
                    .onTapToDismissKeyboard()

                VStack(spacing: 0) {
                    headerView

                    ScrollView {
                        VStack(spacing: 24) {
                            remainingSection
                            paymentDetailsSection
                            accountSection
                            notesSection
                            Spacer(minLength: 100)
                        }
                        .padding(.vertical, 20)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .scrollIndicators(.hidden)
                }

                VStack {
                    Spacer()
                    saveButton
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                }
            }
        }
    }

    private var headerView: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(ColorTheme.secondaryText)
                    .frame(width: 36, height: 36)
                    .background(ColorTheme.secondaryBackground)
                    .clipShape(Circle())
            }

            Spacer()

            Text("add_payment".localizedString)
                .font(.headline)
                .foregroundColor(ColorTheme.primaryText)

            Spacer()

            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(ColorTheme.background)
    }

    private var remainingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("REMAINING")

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("outstanding".localizedString)
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)

                    Text(remaining.asCurrency())
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(remainingColor)
                }

                Spacer()

                Text(debt.directionEnum.badgeTitle)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(remainingColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(remainingColor.opacity(0.12))
                    .clipShape(Capsule())
            }
            .padding(16)
            .background(ColorTheme.cardBackground)
            .cornerRadius(16)
            .padding(.horizontal, 20)
            .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 4)
        }
    }

    private var paymentDetailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("PAYMENT DETAILS")

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("AED")
                        .font(.headline)
                        .foregroundColor(ColorTheme.tertiaryText)
                        .frame(width: 40)

                    TextField("Amount", text: $amount)
                        .keyboardType(.decimalPad)
                        .font(.headline)
                        .onChange(of: amount) { _, newValue in
                            let filtered = newValue.filter { "0123456789.".contains($0) }
                            if filtered != newValue { amount = filtered }
                        }
                }
                .padding(16)

                Divider().padding(.leading, 20)

                HStack(spacing: 12) {
                    Image(systemName: "calendar")
                        .foregroundColor(ColorTheme.secondaryText)
                        .frame(width: 24)

                    Text("date".localizedString)
                        .foregroundColor(ColorTheme.primaryText)

                    Spacer()

                    DatePicker("", selection: $date, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .tint(ColorTheme.primary)
                }
                .padding(16)

                Divider().padding(.leading, 20)

                Menu {
                    ForEach(paymentMethods, id: \.self) { method in
                        Button(method) {
                            paymentMethod = method
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "creditcard.fill")
                            .foregroundColor(ColorTheme.secondaryText)
                            .frame(width: 24)

                        Text("method".localizedString)
                            .foregroundColor(ColorTheme.primaryText)

                        Spacer()

                        Text(paymentMethod)
                            .foregroundColor(ColorTheme.primary)

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                            .foregroundColor(ColorTheme.tertiaryText)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(16)
            }
            .background(ColorTheme.cardBackground)
            .cornerRadius(16)
            .padding(.horizontal, 20)
            .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 4)
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("DEPOSIT / WITHDRAW ACCOUNT")

            Menu {
                Button("none".localizedString) { selectedAccount = nil }
                ForEach(accounts) { account in
                    Button(account.accountType ?? "Unknown") {
                        selectedAccount = account
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "building.columns.fill")
                        .foregroundColor(ColorTheme.secondaryText)
                        .frame(width: 24)

                    Text("account".localizedString)
                        .foregroundColor(ColorTheme.primaryText)

                    Spacer()

                    Text(selectedAccountLabel)
                        .foregroundColor(ColorTheme.primary)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundColor(ColorTheme.tertiaryText)
                }
                .contentShape(Rectangle())
                .padding(16)
                .background(ColorTheme.cardBackground)
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 4)
                .padding(.horizontal, 20)
            }
            .buttonStyle(.plain)
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("NOTES")

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "note.text")
                        .foregroundColor(ColorTheme.secondaryText)
                        .frame(width: 24)
                        .padding(.top, 4)

                    TextField("Note (Optional)", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
                .padding(16)
            }
            .background(ColorTheme.cardBackground)
            .cornerRadius(16)
            .padding(.horizontal, 20)
            .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 4)
        }
    }

    private var saveButton: some View {
        Button(action: savePayment) {
            HStack {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                        .padding(.trailing, 8)
                }
                Text(isSaving ? "Saving..." : "Save Payment")
                    .font(.headline)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isFormValid ? ColorTheme.primary : ColorTheme.secondaryText.opacity(0.3))
            .cornerRadius(20)
            .shadow(color: isFormValid ? ColorTheme.primary.opacity(0.3) : Color.clear, radius: 10, y: 5)
        }
        .disabled(!isFormValid || isSaving)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundColor(ColorTheme.secondaryText)
            .tracking(1)
            .padding(.horizontal, 20)
    }

    private func savePayment() {
        guard isFormValid else { return }
        isSaving = true

        do {
            let payment = DebtPayment(context: viewContext)
            payment.id = UUID()
            payment.amount = NSDecimalNumber(decimal: amountDecimal)
            payment.date = date
            payment.paymentMethod = paymentMethod
            payment.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
            payment.createdAt = Date()
            payment.updatedAt = payment.createdAt
            payment.debt = debt
            payment.account = selectedAccount

            debt.updatedAt = Date()

            if let account = selectedAccount {
                let currentBalance = account.balance?.decimalValue ?? 0
                switch debt.directionEnum {
                case .owedToMe:
                    account.balance = NSDecimalNumber(decimal: currentBalance + amountDecimal)
                case .iOwe:
                    account.balance = NSDecimalNumber(decimal: currentBalance - amountDecimal)
                }
                account.updatedAt = Date()
            }

            try viewContext.save()

            if let dealerId = CloudSyncEnvironment.currentDealerId {
                Task {
                    await CloudSyncManager.shared?.upsertDebt(debt, dealerId: dealerId)
                    await CloudSyncManager.shared?.upsertDebtPayment(payment, dealerId: dealerId)
                    if let account = selectedAccount {
                        await CloudSyncManager.shared?.upsertFinancialAccount(account, dealerId: dealerId)
                    }
                }
            }
            Task {
                await LocalNotificationManager.shared.refreshAll(context: viewContext)
            }

            dismiss()
        } catch {
            isSaving = false
            print("Failed to save debt payment: \(error)")
        }
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let debt = Debt(context: context)
    debt.id = UUID()
    debt.counterpartyName = "Preview"
    debt.amount = NSDecimalNumber(value: 1000)
    debt.direction = DebtDirection.owedToMe.rawValue
    debt.createdAt = Date()
    debt.updatedAt = Date()

    return AddDebtPaymentView(debt: debt)
        .environment(\.managedObjectContext, context)
}
