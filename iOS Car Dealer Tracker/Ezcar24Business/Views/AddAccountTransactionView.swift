import SwiftUI

struct AddAccountTransactionView: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (AccountTransactionType, Decimal, Date, String?) -> Void

    @State private var transactionType: AccountTransactionType = .deposit
    @State private var amount: String = ""
    @State private var date: Date = Date()
    @State private var note: String = ""

    private var amountDecimal: Decimal {
        Decimal(string: amount.filter { "0123456789.".contains($0) }) ?? 0
    }

    private var isFormValid: Bool {
        amountDecimal > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Type".localizedString) {
                    Picker("Transaction".localizedString, selection: $transactionType) {
                        ForEach(AccountTransactionType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Amount".localizedString) {
                    TextField("amount".localizedString, text: $amount)
                        .keyboardType(.decimalPad)
                        .onChange(of: amount) { _, newValue in
                            let filtered = newValue.filter { "0123456789.".contains($0) }
                            if filtered != newValue { amount = filtered }
                        }
                }

                Section("date".localizedString) {
                    DatePicker("date".localizedString, selection: $date, displayedComponents: [.date, .hourAndMinute])
                }

                Section("Note".localizedString) {
                    TextField("Note (Optional)".localizedString, text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("New Transaction".localizedString)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel".localizedString) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save".localizedString) {
                        onSave(transactionType, amountDecimal, date, note.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .disabled(!isFormValid)
                }
            }
        }
    }
}
