import SwiftUI

struct AddFinancialAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: FinancialAccountsViewModel
    
    let preselectedKind: FinancialAccountKind?

    @State private var name: String = ""
    @State private var kind: FinancialAccountKind = .bank
    @State private var startingBalance: String = ""
    @State private var errorMessage: String?
    
    init(viewModel: FinancialAccountsViewModel, preselectedKind: FinancialAccountKind? = nil) {
        self.viewModel = viewModel
        self.preselectedKind = preselectedKind
        _kind = State(initialValue: preselectedKind ?? .bank)
    }

    private var balanceDecimal: Decimal {
        Decimal(string: startingBalance.filter { "0123456789.".contains($0) }) ?? 0
    }

    private var requiresName: Bool {
        kind == .bank || kind == .creditCard
    }

    private var isValid: Bool {
        if requiresName {
            return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
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
                            if preselectedKind == nil {
                                typeSection
                            }
                            nameSection
                            balanceSection
                            Spacer(minLength: 80)
                        }
                        .padding(.vertical, 20)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .safeAreaInset(edge: .bottom) {
                saveButton
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .background(ColorTheme.background)
            }
            .alert("Account Error", isPresented: Binding(get: {
                errorMessage != nil
            }, set: { _ in
                errorMessage = nil
            })) {
                Button("ok".localizedString, role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
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

            Text("New Account")
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

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Account Type")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(ColorTheme.secondaryText)
                .tracking(1)
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                Picker("Account Type", selection: $kind) {
                    Text(FinancialAccountKind.cash.title).tag(FinancialAccountKind.cash)
                    Text(FinancialAccountKind.bank.title).tag(FinancialAccountKind.bank)
                    Text(FinancialAccountKind.creditCard.title).tag(FinancialAccountKind.creditCard)
                }
                .pickerStyle(.segmented)
                .padding(16)
            }
            .background(ColorTheme.cardBackground)
            .cornerRadius(16)
            .padding(.horizontal, 20)
            .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 4)
        }
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(requiresName ? "Account Name" : "Account Name (optional)")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(ColorTheme.secondaryText)
                .tracking(1)
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: kind.iconName)
                        .foregroundColor(ColorTheme.secondaryText)
                        .frame(width: 24)

                    TextField("e.g. HSBC Business", text: $name)
                        .font(.body)
                }
                .padding(16)
            }
            .background(ColorTheme.cardBackground)
            .cornerRadius(16)
            .padding(.horizontal, 20)
            .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 4)
        }
    }

    private var balanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Starting Balance")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(ColorTheme.secondaryText)
                .tracking(1)
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "banknote.fill")
                        .foregroundColor(ColorTheme.secondaryText)
                        .frame(width: 24)

                    TextField("0.00", text: $startingBalance)
                        .keyboardType(.decimalPad)
                        .font(.body)
                        .onChange(of: startingBalance) { _, newValue in
                            let filtered = newValue.filter { "0123456789.".contains($0) }
                            if filtered != newValue { startingBalance = filtered }
                        }
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
        Button {
            let error = viewModel.createAccount(kind: kind, name: name, startingBalance: balanceDecimal)
            if let error {
                errorMessage = error
            } else {
                dismiss()
            }
        } label: {
            Text("Create Account")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(isValid ? ColorTheme.primary : ColorTheme.secondaryText.opacity(0.3))
                .cornerRadius(20)
                .shadow(color: isValid ? ColorTheme.primary.opacity(0.3) : Color.clear, radius: 10, y: 5)
        }
        .disabled(!isValid)
    }
}
