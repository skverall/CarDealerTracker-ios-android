import SwiftUI
import CoreData

struct AddDebtView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var counterpartyName: String = ""
    @State private var counterpartyPhone: String = ""
    @State private var amount: String = ""
    @State private var direction: DebtDirection = .owedToMe
    @State private var includeDueDate: Bool = false
    @State private var dueDate: Date = Date()
    @State private var notes: String = ""

    @State private var isSaving: Bool = false
    @State private var showSavedToast: Bool = false

    private var amountDecimal: Decimal {
        Decimal(string: amount.filter { "0123456789.".contains($0) }) ?? 0
    }

    private var isFormValid: Bool {
        !counterpartyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && amountDecimal > 0
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
                            counterpartySection
                            detailsSection
                            notesSection
                            Spacer(minLength: 100)
                        }
                        .padding(.vertical, 20)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }

                VStack {
                    Spacer()
                    saveButton
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                }

                if showSavedToast {
                    savedToast
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

            Text("new_debt".localizedString)
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

    private var counterpartySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("counterparty".localizedString)

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "person.fill")
                        .foregroundColor(ColorTheme.secondaryText)
                        .frame(width: 24)
                    TextField("name".localizedString, text: $counterpartyName)
                }
                .padding(16)

                Divider().padding(.leading, 52)

                HStack(spacing: 12) {
                    Image(systemName: "phone.fill")
                        .foregroundColor(ColorTheme.secondaryText)
                        .frame(width: 24)
                    TextField("phone_optional".localizedString, text: $counterpartyPhone)
                        .keyboardType(.phonePad)
                }
                .padding(16)
            }
            .background(ColorTheme.cardBackground)
            .cornerRadius(16)
            .padding(.horizontal, 20)
            .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 4)
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("debt_details".localizedString)

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("aed_or_symbol".localizedString) // Use generic or keep hardcoded if mapped
                        .font(.headline)
                        .foregroundColor(ColorTheme.tertiaryText)
                        .frame(width: 40)

                    TextField("amount".localizedString, text: $amount)
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
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundColor(ColorTheme.secondaryText)
                        .frame(width: 24)

                    Text("direction".localizedString)
                        .font(.body)
                        .foregroundColor(ColorTheme.primaryText)

                    Spacer()

                    Picker("direction".localizedString, selection: $direction) {
                        ForEach(DebtDirection.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .accentColor(ColorTheme.primary)
                }
                .padding(16)

                Divider().padding(.leading, 20)

                Toggle(isOn: $includeDueDate) {
                    Label("due_date".localizedString, systemImage: "calendar")
                        .foregroundColor(ColorTheme.primaryText)
                }
                .padding(16)

                if includeDueDate {
                    Divider().padding(.leading, 20)

                    DatePicker("", selection: $dueDate, displayedComponents: .date)
                        .labelsHidden()
                        .padding(16)
                }
            }
            .background(ColorTheme.cardBackground)
            .cornerRadius(16)
            .padding(.horizontal, 20)
            .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 4)
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("notes".localizedString)

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "note.text")
                        .foregroundColor(ColorTheme.secondaryText)
                        .frame(width: 24)
                        .padding(.top, 4)

                    TextField("add_details_optional".localizedString, text: $notes, axis: .vertical)
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
        Button(action: saveDebt) {
            HStack {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                        .padding(.trailing, 8)
                }
                Text(isSaving ? "saving".localizedString : "save_debt".localizedString)
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

    private var savedToast: some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.green)
                Text("debt_saved".localizedString)
                    .font(.headline)
                    .foregroundColor(ColorTheme.primaryText)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(ColorTheme.cardBackground)
            .cornerRadius(30)
            .shadow(color: Color.black.opacity(0.1), radius: 20, y: 10)
            .padding(.bottom, 40)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .zIndex(100)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundColor(ColorTheme.secondaryText)
            .tracking(1)
            .padding(.horizontal, 20)
    }

    private func saveDebt() {
        guard isFormValid else { return }
        isSaving = true
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            do {
                let debt = Debt(context: viewContext)
                debt.id = UUID()
                debt.counterpartyName = counterpartyName.trimmingCharacters(in: .whitespacesAndNewlines)
                debt.counterpartyPhone = counterpartyPhone.trimmingCharacters(in: .whitespacesAndNewlines)
                debt.direction = direction.rawValue
                debt.amount = NSDecimalNumber(decimal: amountDecimal)
                debt.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                debt.dueDate = includeDueDate ? dueDate : nil
                debt.createdAt = Date()
                debt.updatedAt = debt.createdAt

                try viewContext.save()

                if let dealerId = CloudSyncEnvironment.currentDealerId {
                    Task {
                        await CloudSyncManager.shared?.upsertDebt(debt, dealerId: dealerId)
                    }
                }
                Task {
                    await LocalNotificationManager.shared.refreshAll(context: viewContext)
                }

                generator.notificationOccurred(.success)
                withAnimation {
                    showSavedToast = true
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    dismiss()
                }
            } catch {
                isSaving = false
                generator.notificationOccurred(.error)
                print("Failed to save debt: \(error)")
            }
        }
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    return AddDebtView()
        .environment(\.managedObjectContext, context)
}
