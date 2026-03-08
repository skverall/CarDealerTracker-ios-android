//
//  MonthlyReportSettingsView.swift
//  Ezcar24Business
//
//  Email report settings for monthly finance snapshots.
//

import SwiftUI

@MainActor
struct MonthlyReportSettingsView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @StateObject private var viewModel: MonthlyReportSettingsViewModel

    init(viewModel: MonthlyReportSettingsViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? MonthlyReportSettingsViewModel())
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerCard
                deliveryCard
                recipientsCard
                detailsCard
                actionsCard
            }
            .padding(16)
        }
        .background(ColorTheme.background.ignoresSafeArea())
        .navigationTitle("Email Reports")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: sessionStore.activeOrganizationId) {
            await viewModel.load(organizationId: sessionStore.activeOrganizationId)
        }
    }

    private var headerCard: some View {
        card {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: "envelope.badge")
                            .foregroundColor(.blue)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Monthly email reports")
                            .font(.headline)
                            .foregroundColor(ColorTheme.primaryText)

                        Text("Preview and export the same finance snapshot that will back future email delivery.")
                            .font(.subheadline)
                            .foregroundColor(ColorTheme.secondaryText)
                    }
                }

                Toggle(isOn: Binding(
                    get: { viewModel.preferences.isEnabled },
                    set: { newValue in
                        Task {
                            await viewModel.updateEnabled(newValue, organizationId: sessionStore.activeOrganizationId)
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enable monthly report emails")
                            .foregroundColor(ColorTheme.primaryText)
                        Text("Owner and admin recipients only")
                            .font(.caption)
                            .foregroundColor(ColorTheme.secondaryText)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: ColorTheme.primary))

                if viewModel.isLoading {
                    ProgressView()
                }

                if let infoMessage = viewModel.infoMessage {
                    statusPill(text: infoMessage, color: .green)
                }

                if let errorMessage = viewModel.errorMessage {
                    statusPill(text: errorMessage, color: .red)
                }
            }
        }
    }

    private var deliveryCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Delivery")
                    .font(.headline)
                    .foregroundColor(ColorTheme.primaryText)

                detailRow(title: "Schedule", value: viewModel.scheduleDescription)
                detailRow(title: "Timezone", value: viewModel.timezoneDescription)
                detailRow(title: "Preview month", value: viewModel.previewMonth.displayTitle)
            }
        }
    }

    private var recipientsCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Recipients")
                    .font(.headline)
                    .foregroundColor(ColorTheme.primaryText)

                Text("All owner and admin members with a resolved email address.")
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.secondaryText)

                if let warning = viewModel.recipientWarningMessage {
                    statusPill(text: warning, color: .orange)
                }

                if viewModel.recipients.isEmpty {
                    Text("No recipients resolved yet.")
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.secondaryText)
                } else {
                    ForEach(viewModel.recipients) { recipient in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(recipient.email)
                                    .foregroundColor(ColorTheme.primaryText)
                                Text(recipient.role.capitalized)
                                    .font(.caption)
                                    .foregroundColor(ColorTheme.secondaryText)
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private var detailsCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Report contents")
                    .font(.headline)
                    .foregroundColor(ColorTheme.primaryText)

                detailRow(title: "Scope", value: "Finance + inventory + parts")
                detailRow(title: "Format", value: "Email summary + PDF attachment")
                detailRow(title: "Profit display", value: "Realized sales profit, monthly expenses, and net cash movement")
            }
        }
    }

    private var actionsCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Actions")
                    .font(.headline)
                    .foregroundColor(ColorTheme.primaryText)

                NavigationLink {
                    MonthlyReportPreviewView(referenceDate: Date())
                } label: {
                    actionRow(
                        icon: "doc.text.magnifyingglass",
                        title: "Preview previous month",
                        subtitle: "Open the finance snapshot used for PDF export"
                    )
                }

                Divider()

                Button {
                    Task {
                        await viewModel.sendTest(organizationId: sessionStore.activeOrganizationId)
                    }
                } label: {
                    HStack(spacing: 12) {
                        actionRow(
                            icon: "paperplane.fill",
                            title: "Send test email",
                            subtitle: "Uses the delivery client contract"
                        )

                        if viewModel.isSendingTest {
                            ProgressView()
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSendingTest)
            }
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ColorTheme.cardBackground)
        .cornerRadius(18)
    }

    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(ColorTheme.secondaryText)
            Text(value)
                .foregroundColor(ColorTheme.primaryText)
        }
    }

    private func actionRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(ColorTheme.primary.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .foregroundColor(ColorTheme.primary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .foregroundColor(ColorTheme.primaryText)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(ColorTheme.secondaryText)
            }

            Spacer()
        }
    }

    private func statusPill(text: String, color: Color) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.12))
            .cornerRadius(10)
    }
}
