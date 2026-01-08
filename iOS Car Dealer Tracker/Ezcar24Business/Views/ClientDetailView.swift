import SwiftUI
import CoreData

struct ClientDetailView: View {
    let client: Client?
    let context: NSManagedObjectContext
    var onSave: (Client) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var phone: String = ""
    @State private var email: String = ""
    @State private var notes: String = ""
    @State private var requestDetails: String = ""
    @State private var preferredDate: Date = Date()
    @State private var selectedVehicle: Vehicle?
    @State private var status: ClientStatus = .new
    @State private var isViewing: Bool
    @State private var interactionDrafts: [InteractionDraft] = []
    @State private var reminderDrafts: [ReminderDraft] = []
    @State private var isSaving: Bool = false
    @State private var showNotificationSettingsAlert = false
    @State private var notificationAlertMessage = ""

    @State private var showPreferredDatePicker = false
    @State private var showInteractionDatePicker = false
    @State private var showReminderDatePicker = false
    
    @State private var showVehicleSheet = false
    @State private var vehicleSearchText = ""
    
    // Track which item is being edited for interactions/reminders
    @State private var activeInteractionId: UUID?
    @State private var activeReminderId: UUID?

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }

    private var dateTimeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Vehicle.createdAt, ascending: false)],
        animation: .default)
    private var vehicles: FetchedResults<Vehicle>

    init(client: Client?, context: NSManagedObjectContext, onSave: @escaping (Client) -> Void) {
        self.client = client
        self.context = context
        self.onSave = onSave
        _name = State(initialValue: client?.name ?? "")
        _phone = State(initialValue: client?.phone ?? "")
        _email = State(initialValue: client?.email ?? "")
        _notes = State(initialValue: client?.notes ?? "")
        _requestDetails = State(initialValue: client?.requestDetails ?? "")
        _preferredDate = State(initialValue: client?.preferredDate ?? Date())
        _selectedVehicle = State(initialValue: client?.vehicle)
        _status = State(initialValue: client?.clientStatus ?? .new)
        _isViewing = State(initialValue: client != nil)
        _interactionDrafts = State(initialValue: client?.sortedInteractions.map { $0.asDraft() } ?? [])
        _reminderDrafts = State(initialValue: client?.sortedReminders.map { $0.asDraft() } ?? [])
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ColorTheme.background.ignoresSafeArea()
                    .onTapToDismissKeyboard()
                
                VStack(spacing: 0) {
                    // Custom Header
                    headerView
                    
                    if isViewing {
                        readOnlyView
                    } else {
                        editFormView
                    }
                }
                
                // Floating Save Button (only in edit mode)
                if !isViewing {
                    VStack {
                        Spacer()
                        saveButton
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showPreferredDatePicker) {
                VStack {
                    DatePicker("Preferred Date", selection: $preferredDate, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.graphical)
                        .padding()
                    
                    Button("done".localizedString) {
                        showPreferredDatePicker = false
                    }
                    .padding()
                    .foregroundColor(ColorTheme.primary)
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showInteractionDatePicker) {
                VStack {
                    if let id = activeInteractionId, let index = interactionDrafts.firstIndex(where: { $0.id == id }) {
                        let binding = $interactionDrafts[index].occurredAt
                        DatePicker("Date", selection: binding, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .padding()
                            .onChange(of: binding.wrappedValue) { _, _ in
                                showInteractionDatePicker = false
                            }
                    } else {
                        Text("Error: Interaction not found")
                    }
                    
                    Button("done".localizedString) {
                        showInteractionDatePicker = false
                    }
                    .padding()
                    .foregroundColor(ColorTheme.primary)
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showReminderDatePicker) {
                VStack {
                    if let id = activeReminderId, let index = reminderDrafts.firstIndex(where: { $0.id == id }) {
                        let binding = $reminderDrafts[index].dueDate
                        DatePicker("due_date".localizedString, selection: binding, displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.graphical)
                            .padding()
                    } else {
                        Text("Error: Reminder not found")
                    }
                    
                    Button("done".localizedString) {
                        showReminderDatePicker = false
                    }
                    .padding()
                    .foregroundColor(ColorTheme.primary)
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showVehicleSheet) {
                VehicleSelectionSheet(
                    isPresented: $showVehicleSheet,
                    searchText: $vehicleSearchText,
                    selectedVehicle: $selectedVehicle,
                    vehicles: Array(vehicles)
                )
            }
            .alert("Notifications", isPresented: $showNotificationSettingsAlert) {
                Button("Open Settings") {
                    LocalNotificationManager.shared.openSystemSettings()
                }
                Button("cancel".localizedString, role: .cancel) { }
            } message: {
                Text(notificationAlertMessage)
            }
    }
}
    
    // MARK: - Header
    
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
            
            Text(navigationTitle)
                .font(.headline)
                .foregroundColor(ColorTheme.primaryText)
            
            Spacer()
            
            if isViewing {
                Button {
                    startEditing()
                } label: {
                    Text("edit".localizedString)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(ColorTheme.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(ColorTheme.primary.opacity(0.1))
                        .cornerRadius(16)
                }
            } else {
                // Placeholder to balance the layout
                Color.clear.frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(ColorTheme.background)
    }
    
    // MARK: - Edit Form
    
    private var editFormView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Hero Name Input
                nameInputSection
                
                // Status Selector
                statusSelector
                
                // Contact Details
                contactSection
                
                // Vehicle Interest
                vehicleSection
                
                // Notes
                notesSection
                
                // Interactions & Reminders (Simplified for Add Mode)
                if client != nil {
                    // Only show complex history editing when editing an existing client
                    // For new clients, we keep it simple
                    interactionsSection
                    remindersSection
                }
                
                Spacer(minLength: 100)
            }
            .padding(.vertical, 20)
        }
        .scrollDismissesKeyboard(.interactively)
    }
    
    private var nameInputSection: some View {
        VStack(spacing: 8) {
            Text("client_name".localizedString)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(ColorTheme.secondaryText)
                .tracking(1)
            
            TextField("client_name_placeholder".localizedString, text: $name)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(ColorTheme.primaryText)
                .multilineTextAlignment(.center)
                .submitLabel(.next)
        }
        .padding(.top, 10)
    }
    
    private var statusSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ClientStatus.allCases) { s in
                    let isSelected = status == s
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            status = s
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Text(s.displayName)
                            .font(.subheadline)
                            .fontWeight(isSelected ? .semibold : .medium)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(isSelected ? s.color : ColorTheme.cardBackground)
                            .foregroundColor(isSelected ? .white : ColorTheme.secondaryText)
                            .cornerRadius(20)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(isSelected ? Color.clear : ColorTheme.secondaryText.opacity(0.2), lineWidth: 1)
                            )
                            .shadow(color: isSelected ? s.color.opacity(0.3) : Color.clear, radius: 5, y: 2)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
        }
    }
    
    private var contactSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("contact_details".localizedString)
            
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "phone.fill")
                        .foregroundColor(ColorTheme.secondaryText)
                        .frame(width: 24)
                    TextField("Phone Number", text: $phone)
                        .keyboardType(.phonePad)
                }
                .padding(16)
                
                Divider().padding(.leading, 52)
                
                HStack(spacing: 12) {
                    Image(systemName: "envelope.fill")
                        .foregroundColor(ColorTheme.secondaryText)
                        .frame(width: 24)
                    TextField("email_optional".localizedString, text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                }
                .padding(16)
            }
            .background(ColorTheme.cardBackground)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.03), radius: 5, x: 0, y: 2)
        }
        .padding(.horizontal, 20)
    }
    
    private var vehicleSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("vehicle_interest".localizedString)
            
            VStack(spacing: 0) {
                // Vehicle Picker
                HStack(spacing: 12) {
                    Image(systemName: "car.fill")
                        .foregroundColor(ColorTheme.secondaryText)
                        .frame(width: 24)
                    
                    Button {
                        showVehicleSheet = true
                    } label: {
                        HStack {
                            if let vehicle = selectedVehicle {
                                Text("\(vehicle.make ?? "") \(vehicle.model ?? "")")
                                    .foregroundColor(ColorTheme.primaryText)
                            } else {
                                Text("select_vehicle".localizedString)
                                    .foregroundColor(ColorTheme.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundColor(ColorTheme.tertiaryText)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                
                Divider().padding(.leading, 52)
                
                // Date Picker
                HStack(spacing: 12) {
                    Image(systemName: "calendar")
                        .foregroundColor(ColorTheme.secondaryText)
                        .frame(width: 24)
                    
                    Button {
                        showPreferredDatePicker = true
                    } label: {
                         HStack {
                             Text(preferredDate, formatter: dateTimeFormatter)
                                 .foregroundColor(ColorTheme.primaryText)
                             Spacer()
                         }
                         .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                }
                .padding(16)
                
                Divider().padding(.leading, 52)
                
                // Request Details
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "text.alignleft")
                        .foregroundColor(ColorTheme.secondaryText)
                        .frame(width: 24)
                        .padding(.top, 4)
                    
                    TextField("request_details".localizedString, text: $requestDetails, axis: .vertical)
                        .lineLimit(2...4)
                }
                .padding(16)
            }
            .background(ColorTheme.cardBackground)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.03), radius: 5, x: 0, y: 2)
        }
        .padding(.horizontal, 20)
    }
    
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("notes".localizedString)
            
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "note.text")
                        .foregroundColor(ColorTheme.secondaryText)
                        .frame(width: 24)
                        .padding(.top, 4)
                    
                    TextField("notes_placeholder".localizedString, text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
                .padding(16)
            }
            .background(ColorTheme.cardBackground)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.03), radius: 5, x: 0, y: 2)
        }
        .padding(.horizontal, 20)
    }
    
    private var interactionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("interactions".localizedString)
            
            ForEach(interactionDrafts) { interaction in
                if let binding = interactionBinding(for: interaction.id) {
                    interactionEditor(draft: binding) {
                        deleteInteractionDraft(interaction.id)
                    }
                }
            }
            
            Button {
                addInteractionDraft()
            } label: {
                Label("add_interaction".localizedString, systemImage: "plus.circle.fill")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(ColorTheme.primary)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(ColorTheme.cardBackground)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(ColorTheme.primary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5]))
                    )
            }
        }
        .padding(.horizontal, 20)
    }
    
    private var remindersSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("reminders".localizedString)
            
            ForEach(reminderDrafts) { reminder in
                if let binding = reminderBinding(for: reminder.id) {
                    reminderEditor(draft: binding) {
                        deleteReminderDraft(reminder.id)
                    }
                }
            }
            
            Button {
                addReminderDraft()
            } label: {
                Label("add_reminder".localizedString, systemImage: "bell.badge.fill")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(ColorTheme.primary)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(ColorTheme.cardBackground)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(ColorTheme.primary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5]))
                    )
            }
        }
        .padding(.horizontal, 20)
    }
    
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.bold)
            .foregroundColor(ColorTheme.secondaryText)
            .padding(.leading, 4)
    }
    
    private var saveButton: some View {
        Button(action: save) {
            HStack {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                        .padding(.trailing, 8)
                }
                Text(isSaving ? "saving".localizedString : "save_client".localizedString)
                    .font(.headline)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(name.isEmpty ? ColorTheme.secondaryText.opacity(0.3) : ColorTheme.primary)
            .cornerRadius(20)
            .shadow(color: name.isEmpty ? Color.clear : ColorTheme.primary.opacity(0.3), radius: 10, y: 5)
        }
        .disabled(name.isEmpty || isSaving)
    }
    
    // MARK: - Read Only View
    
    private var readOnlyView: some View {
        ScrollView {
            VStack(spacing: 16) {
                summaryCard
                contactCard
                vehicleCard
                notesCard
                interactionsCard
                remindersCard
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
    }
    
    // ... (Keep existing read-only card implementations, but ensure they use ColorTheme correctly)
    
    private var summaryCard: some View {
        crmCard(title: "CRM Summary", icon: "chart.bar.doc.horizontal") {
            HStack {
                statusBadge(status)
                Spacer()
                if let preferred = client?.preferredDate {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundColor(ColorTheme.secondaryText)
                        Text(preferred, formatter: mediumDateFormatter)
                            .font(.footnote)
                            .foregroundColor(ColorTheme.secondaryText)
                    }
                }
            }

            Divider().opacity(0.2)

            VStack(alignment: .leading, spacing: 8) {
                if let last = client?.lastInteraction {
                    HStack {
                        Label(last.interactionStage.label, systemImage: last.interactionStage.icon)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(last.interactionStage.color)
                        Spacer()
                        Text(last.occurredAt ?? Date(), formatter: shortDateFormatter)
                            .font(.footnote)
                            .foregroundColor(ColorTheme.secondaryText)
                    }
                    if let note = last.detail, !note.isEmpty {
                        Text(note)
                            .font(.footnote)
                            .foregroundColor(ColorTheme.primaryText)
                    }
                } else {
                    Text("no_interactions".localizedString)
                        .font(.footnote)
                        .foregroundColor(ColorTheme.secondaryText)
                }

                if let reminder = client?.nextReminder {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(reminder.statusColor.opacity(0.12))
                        .overlay(
                            HStack {
                                Image(systemName: "bell.fill")
                                    .foregroundColor(reminder.statusColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(reminder.title ?? "Reminder")
                                        .font(.subheadline.weight(.semibold))
                                    Text(reminder.dueDate ?? Date(), formatter: shortDateFormatter)
                                        .font(.footnote)
                                        .foregroundColor(ColorTheme.secondaryText)
                                }
                                Spacer()
                                Text(reminder.statusLabel)
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(reminder.statusColor)
                            }
                            .padding(10)
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
            }
        }
    }

    private var contactCard: some View {
        crmCard(title: "contact_info".localizedString, icon: "person.fill") {
            VStack(alignment: .leading, spacing: 8) {
                crmRow(label: "name_label".localizedString, value: displayValue(for: name), icon: "person")
                
                // Phone Row with Call Button
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "phone.fill")
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.secondaryText)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("phone".localizedString)
                            .font(.caption)
                            .foregroundColor(ColorTheme.secondaryText)
                        Text(displayValue(for: phone))
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(ColorTheme.primaryText)
                    }
                    Spacer()
                    if !phone.isEmpty {
                        Button {
                            call(phone)
                        } label: {
                            Image(systemName: "phone.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(ColorTheme.success)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                crmRow(label: "Email", value: displayValue(for: email), icon: "envelope.fill")
            }
        }
    }

    private var vehicleCard: some View {
        crmCard(title: "Vehicle Interest", icon: "car.fill") {
            crmRow(label: "Model", value: selectedVehicle?.displayName ?? "Not selected", icon: "car.side")
            crmRow(label: "Date", value: formattedDate(), icon: "calendar")
            if !requestDetails.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(requestDetails)
                    .font(.footnote)
                    .foregroundColor(ColorTheme.primaryText)
                    .padding(.top, 2)
            }
        }
    }

    private var notesCard: some View {
        crmCard(title: "Notes", icon: "text.bubble.fill") {
            Text(displayValue(for: notes))
                .font(.footnote)
                .foregroundColor(ColorTheme.primaryText)
        }
    }

    private var interactionsCard: some View {
        crmCard(title: "Deal History", icon: "clock.arrow.circlepath") {
            let interactions = client?.sortedInteractions ?? []
            if interactions.isEmpty {
                Text("Add the first interaction to build history.")
                    .font(.footnote)
                    .foregroundColor(ColorTheme.secondaryText)
            } else {
                VStack(spacing: 12) {
                    ForEach(interactions) { interaction in
                        interactionRow(interaction)
                    }
                }
            }
        }
    }

    private var remindersCard: some View {
        crmCard(title: "Reminders", icon: "bell.badge.fill") {
            let reminders = client?.sortedReminders ?? []
            if reminders.isEmpty {
                Text("Create a reminder to stay on track.")
                    .font(.footnote)
                    .foregroundColor(ColorTheme.secondaryText)
            } else {
                VStack(spacing: 12) {
                    ForEach(reminders) { reminder in
                        reminderRow(reminder)
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Components
    
    private func crmCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(ColorTheme.primary)
                Text(title)
                    .font(.headline)
                    .foregroundColor(ColorTheme.primaryText)
                Spacer()
            }
            content()
        }
        .padding()
        .background(ColorTheme.cardBackground)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
    
    private func crmRow(label: String, value: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(ColorTheme.secondaryText)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(ColorTheme.secondaryText)
                Text(value)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(ColorTheme.primaryText)
            }
            Spacer()
        }
    }
    
    private func statusBadge(_ status: ClientStatus) -> some View {
        Text(status.displayName.uppercased())
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(status.color.opacity(0.15))
            .foregroundColor(status.color)
            .clipShape(Capsule())
    }
    
    private func interactionRow(_ interaction: ClientInteraction) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(interaction.interactionStage.color.opacity(0.2))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: interaction.interactionStage.icon)
                            .foregroundColor(interaction.interactionStage.color)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(interaction.title ?? interaction.interactionStage.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(ColorTheme.primaryText)
                    Text(interaction.occurredAt ?? Date(), formatter: shortDateFormatter)
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)
                }

                Spacer()

                if let value = interaction.formattedValue {
                    Text(value)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(ColorTheme.success.opacity(0.12))
                        .foregroundColor(ColorTheme.success)
                        .clipShape(Capsule())
                }
            }

            if let note = interaction.detail, !note.isEmpty {
                Text(note)
                    .font(.footnote)
                    .foregroundColor(ColorTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(ColorTheme.secondaryBackground)
        .cornerRadius(12)
    }

    private func reminderRow(_ reminder: ClientReminder) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(reminder.statusColor.opacity(0.18))
                .frame(width: 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.title ?? "Reminder")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(ColorTheme.primaryText)
                if let notes = reminder.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.footnote)
                        .foregroundColor(ColorTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(reminder.dueDate ?? Date(), formatter: mediumDateFormatter)
                    .font(.caption)
                    .foregroundColor(ColorTheme.secondaryText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(reminder.statusLabel.uppercased())
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(reminder.statusColor.opacity(0.14))
                    .foregroundColor(reminder.statusColor)
                    .clipShape(Capsule())
                if reminder.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(ColorTheme.success)
                } else if reminder.isOverdue {
                    Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(ColorTheme.danger)
                } else {
                    Image(systemName: "clock.fill")
                        .foregroundColor(ColorTheme.accent)
                }
            }
        }
        .padding(12)
        .background(ColorTheme.secondaryBackground)
        .cornerRadius(12)
    }
    
    private func interactionEditor(draft: Binding<InteractionDraft>, onDelete: @escaping () -> Void) -> some View {
        let amountBinding = Binding<String>(
            get: {
                guard let value = draft.wrappedValue.value else { return "" }
                return NSDecimalNumber(decimal: value).stringValue
            },
            set: { newValue in
                let normalized = newValue.replacingOccurrences(of: ",", with: ".")
                draft.wrappedValue.value = Decimal(string: normalized)
            }
        )

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Title", text: draft.title)
                    .font(.headline)
                Spacer()
                Button(role: .destructive) { onDelete() } label: {
                    Image(systemName: "trash")
                        .foregroundColor(ColorTheme.danger)
                }
            }
            
            Divider()

            Picker("Stage", selection: draft.stage) {
                ForEach(InteractionStage.allCases) { stage in
                    Text(stage.label).tag(stage)
                }
            }
            .pickerStyle(.menu)

            Button {
                activeInteractionId = draft.wrappedValue.id
                showInteractionDatePicker = true
            } label: {
                HStack {
                    Text("date".localizedString)
                    Spacer()
                    Text(draft.wrappedValue.occurredAt, formatter: dateFormatter)
                        .foregroundColor(ColorTheme.primary)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            TextField("Deal Value (Optional)", text: amountBinding)
                .keyboardType(.decimalPad)
            
            TextField("Notes", text: draft.notes, axis: .vertical)
                .lineLimit(2...4)
        }
        .padding()
        .background(ColorTheme.cardBackground)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }

    private func reminderEditor(draft: Binding<ReminderDraft>, onDelete: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Task", text: draft.title)
                    .font(.headline)
                Spacer()
                Button(role: .destructive) { onDelete() } label: {
                    Image(systemName: "trash")
                        .foregroundColor(ColorTheme.danger)
                }
            }
            
            Divider()
            
            Button {
                activeReminderId = draft.wrappedValue.id
                showReminderDatePicker = true
            } label: {
                HStack {
                    Text("due_date".localizedString)
                    Spacer()
                    Text(draft.wrappedValue.dueDate, formatter: dateTimeFormatter)
                        .foregroundColor(ColorTheme.primary)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            TextField("Notes", text: draft.notes, axis: .vertical)
                .lineLimit(2...3)
            
            Toggle("Completed", isOn: draft.isCompleted)
        }
        .padding()
        .background(ColorTheme.cardBackground)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    // MARK: - Logic
    
    private var navigationTitle: String {
        if isViewing {
            return client?.name ?? "Client Details"
        }
        return client == nil ? "New Client" : "Edit Client"
    }
    
    private func displayValue(for text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Not provided" : trimmed
    }
    
    private func formattedDate() -> String {
        guard let date = client?.preferredDate else {
            return "Not scheduled"
        }
        return mediumDateFormatter.string(from: date)
    }
    
    private var mediumDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }
    
    private var shortDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }
    
    private func addInteractionDraft() {
        interactionDrafts.append(
            InteractionDraft(
                title: "",
                notes: "",
                occurredAt: Date(),
                stage: .outreach,
                value: nil
            )
        )
    }

    private func addReminderDraft() {
        let defaultDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        reminderDrafts.append(
            ReminderDraft(
                id: UUID(),
                title: "",
                notes: "",
                dueDate: defaultDate,
                isCompleted: false
            )
        )
    }

    private func deleteInteractionDraft(_ id: UUID) {
        DispatchQueue.main.async {
            interactionDrafts.removeAll { $0.id == id }
        }
    }

    private func deleteReminderDraft(_ id: UUID) {
        DispatchQueue.main.async {
            reminderDrafts.removeAll { $0.id == id }
        }
    }
    
    private func startEditing() {
        interactionDrafts = client?.sortedInteractions.map { $0.asDraft() } ?? interactionDrafts
        reminderDrafts = client?.sortedReminders.map { $0.asDraft() } ?? reminderDrafts
        isViewing = false
    }
    
    private func save() {
        isSaving = true
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        
        // Simulate delay for UX
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard let dealerId = CloudSyncEnvironment.currentDealerId else {
                isSaving = false
                return
            }

            let trimmedName = name.trimmingCharacters(in: .whitespaces)
            let isNew = client == nil
            let clientObject = client ?? Client(context: context)

            if isNew {
                clientObject.id = UUID()
                clientObject.createdAt = Date()
            }

            clientObject.name = trimmedName
            clientObject.phone = phone.isEmpty ? nil : phone
            clientObject.email = email.isEmpty ? nil : email
            clientObject.notes = notes.isEmpty ? nil : notes
            clientObject.requestDetails = requestDetails.isEmpty ? nil : requestDetails
            clientObject.preferredDate = preferredDate
            clientObject.vehicle = selectedVehicle
            clientObject.clientStatus = status
            clientObject.updatedAt = Date()
            
            syncInteractions(for: clientObject)
            syncReminders(for: clientObject)

            do {
                try context.save()
                Task {
                    await CloudSyncManager.shared?.upsertClient(clientObject, dealerId: dealerId)
                }
                Task {
                    if shouldScheduleReminders(), !NotificationPreference.isEnabled {
                        let granted = await LocalNotificationManager.shared.requestAuthorization()
                        NotificationPreference.setEnabled(granted)
                        if !granted {
                            await MainActor.run {
                                notificationAlertMessage = "Enable notifications in Settings to receive client reminders."
                                showNotificationSettingsAlert = true
                            }
                        }
                    }
                    await LocalNotificationManager.shared.refreshAll(context: context)
                }
                generator.notificationOccurred(.success)
                onSave(clientObject)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isSaving = false
                    dismiss()
                }
            } catch {
                print("Failed to save client: \(error)")
                generator.notificationOccurred(.error)
                isSaving = false
                context.rollback()
            }
        }
    }

    private func shouldScheduleReminders() -> Bool {
        let now = Date()
        return reminderDrafts.contains { draft in
            let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, !draft.isCompleted else { return false }
            return draft.dueDate > now
        }
    }
    
    private func syncInteractions(for clientObject: Client) {
        let existing = (clientObject.interactions as? Set<ClientInteraction>) ?? []
        var existingMap: [UUID: ClientInteraction] = [:]
        for item in existing {
            if let id = item.id {
                existingMap[id] = item
            }
        }

        let draftIds = Set(interactionDrafts.map { $0.id })
        for interaction in existing where !(interaction.id.map { draftIds.contains($0) } ?? false) {
            context.delete(interaction)
        }

        for draft in interactionDrafts {
            let trimmedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedNotes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty || !trimmedNotes.isEmpty else { continue }

            let interaction = existingMap[draft.id] ?? ClientInteraction(context: context)
            interaction.id = draft.id
            interaction.title = trimmedTitle.isEmpty ? draft.stage.label : trimmedTitle
            interaction.detail = trimmedNotes.isEmpty ? nil : trimmedNotes
            interaction.occurredAt = draft.occurredAt
            interaction.interactionStage = draft.stage
            interaction.value = draft.value.map { NSDecimalNumber(decimal: $0) }
            interaction.client = clientObject
        }
    }

    private func syncReminders(for clientObject: Client) {
        let existing = (clientObject.reminders as? Set<ClientReminder>) ?? []
        var existingMap: [UUID: ClientReminder] = [:]
        for reminder in existing {
            if let id = reminder.id {
                existingMap[id] = reminder
            }
        }

        let draftIds = Set(reminderDrafts.map { $0.id })
        for reminder in existing where !(reminder.id.map { draftIds.contains($0) } ?? false) {
            context.delete(reminder)
        }

        for draft in reminderDrafts {
            let trimmedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty else { continue }

            let reminder = existingMap[draft.id] ?? ClientReminder(context: context)
            reminder.id = draft.id
            reminder.title = trimmedTitle
            let trimmedNotes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            reminder.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
            reminder.dueDate = draft.dueDate
            reminder.isCompleted = draft.isCompleted
            reminder.createdAt = reminder.createdAt ?? Date()
            reminder.client = clientObject
        }
    }

    private func interactionBinding(for id: UUID) -> Binding<InteractionDraft>? {
        guard let index = interactionDrafts.firstIndex(where: { $0.id == id }) else { return nil }
        return $interactionDrafts[index]
    }

    private func reminderBinding(for id: UUID) -> Binding<ReminderDraft>? {
        guard let index = reminderDrafts.firstIndex(where: { $0.id == id }) else { return nil }
        return $reminderDrafts[index]
    }
    private func call(_ phone: String) {
        let clean = phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        if let url = URL(string: "tel://\(clean)"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
}
