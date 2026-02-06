
import SwiftUI
import CoreData

struct ExpenseDetailSheet: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    let expense: Expense
    @State private var commentDraft: String
    @State private var isSaving: Bool = false
    @State private var saveError: String? = nil
    @State private var showSavedToast: Bool = false
    @State private var receiptShareUrl: URL? = nil
    @State private var showReceiptShare: Bool = false

    init(expense: Expense) {
        self.expense = expense
        _commentDraft = State(initialValue: expense.expenseDescription ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        let description = expense.expenseDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
                        Text((description?.isEmpty == false ? description : nil) ?? expense.categoryTitle)
                            .font(.title3.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(expense.amountDecimal.asCurrency())
                            .font(.largeTitle.weight(.bold))
                            .foregroundColor(ColorTheme.primaryText)
                    }
                    .padding(.top, 24)

                    VStack(alignment: .leading, spacing: 10) {
                        DetailRow(title: "Category", value: expense.categoryTitle, icon: "tag")
                        DetailRow(title: "Vehicle", value: expense.vehicleSubtitle, icon: "car.fill")
                        DetailRow(title: "Date", value: expense.dateString, icon: "calendar")
                    }

                    if expense.receiptPath != nil {
                        Button {
                            openReceipt()
                        } label: {
                            HStack {
                                Image(systemName: "paperclip")
                                Text("view_receipt".localizedString)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(ColorTheme.tertiaryText)
                            }
                            .padding(12)
                            .background(ColorTheme.secondaryBackground)
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Comment")
                            .font(.caption)
                            .foregroundColor(ColorTheme.secondaryText)

                        ZStack(alignment: .topLeading) {
                            if commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("Add a note (what was this expense for?)")
                                    .font(.body)
                                    .foregroundColor(ColorTheme.secondaryText.opacity(0.6))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                            }

                            TextEditor(text: $commentDraft)
                                .frame(minHeight: 90)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .scrollContentBackground(.hidden)
                                .background(Color.clear)
                        }
                        .background(ColorTheme.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    if let saveError {
                        Text(saveError)
                            .font(.caption)
                            .foregroundColor(ColorTheme.danger)
                    } else if showSavedToast {
                        Text("Saved")
                            .font(.caption)
                            .foregroundColor(ColorTheme.success)
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
            .sheet(isPresented: $showReceiptShare) {
                if let url = receiptShareUrl {
                    ActivityView(activityItems: [url])
                }
            }
            
            // Sticky Footer
            VStack {
                Button {
                    saveComment()
                } label: {
                    if isSaving {
                        ProgressView()
                        .frame(maxWidth: .infinity)
                    } else {
                        Text("Save Comment")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(ColorTheme.primary)
                .disabled(isSaving)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 20)
            .background(ColorTheme.background)
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: -4)
        }
        .background(ColorTheme.background)
        .onDisappear {
            let trimmed = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            let current = (expense.expenseDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !isSaving, trimmed != current {
                // Background save if dismissed without clicking button
                saveComment(shouldDismiss: false)
            }
        }
    }

    private func openReceipt() {
        guard let path = expense.receiptPath else { return }
        Task {
            if let data = await CloudSyncManager.shared?.downloadExpenseReceipt(path: path) {
                let fileName = URL(fileURLWithPath: path).lastPathComponent
                let tempUrl = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                do {
                    try data.write(to: tempUrl, options: .atomic)
                    await MainActor.run {
                        receiptShareUrl = tempUrl
                        showReceiptShare = true
                    }
                } catch {
                    print("Failed to write receipt: \(error)")
                }
            }
        }
    }

    private func saveComment(shouldDismiss: Bool = true) {
        guard !isSaving else { return }
        isSaving = true
        saveError = nil
        showSavedToast = false

        let trimmed = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        expense.expenseDescription = trimmed.isEmpty ? nil : trimmed
        expense.updatedAt = Date()

        do {
            try viewContext.save()
            showSavedToast = true

            if let dealerId = CloudSyncEnvironment.currentDealerId {
                Task {
                    await CloudSyncManager.shared?.upsertExpense(expense, dealerId: dealerId)
                }
            }

            if shouldDismiss {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    dismiss()
                }
            }
        } catch {
            viewContext.rollback()
            saveError = "Failed to save"
            print("Failed to save expense comment: \(error)")
        }

        isSaving = false
    }
}

struct DetailRow: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(ColorTheme.primary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(.caption)
                    .foregroundColor(ColorTheme.secondaryText)
                Text(value)
                    .font(.body)
                    .foregroundColor(ColorTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }
}
