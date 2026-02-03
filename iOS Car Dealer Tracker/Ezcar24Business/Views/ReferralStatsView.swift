import SwiftUI

struct ReferralStatsView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @State private var stats: ReferralStats = .empty
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            ColorTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    summaryCard
                    detailsCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
        }
        .navigationTitle("referral_stats".localizedString)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadStats() }
        .refreshable { await loadStats() }
        .alert("error".localizedString, isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("ok".localizedString, role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("referral_summary".localizedString)
                .font(.headline)
                .foregroundColor(ColorTheme.primaryText)

            HStack {
                statTile(
                    title: "referral_months_earned".localizedString,
                    value: "\(stats.totalMonths)"
                )
                statTile(
                    title: "referral_successful".localizedString,
                    value: "\(stats.totalRewards)"
                )
            }

            if let until = stats.bonusAccessUntil, until > Date() {
                Text(String(format: "referral_bonus_until".localizedString, until.formatted(date: .numeric, time: .omitted)))
                    .font(.caption)
                    .foregroundColor(.green)
            } else {
                Text("referral_no_active_bonus".localizedString)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(ColorTheme.cardBackground)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.03), radius: 5, x: 0, y: 2)
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("referral_details".localizedString)
                .font(.headline)
                .foregroundColor(ColorTheme.primaryText)

            HStack {
                Text("referral_last_reward".localizedString)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(lastRewardText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(ColorTheme.primaryText)
            }

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(ColorTheme.cardBackground)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.03), radius: 5, x: 0, y: 2)
    }

    private func statTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundColor(ColorTheme.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lastRewardText: String {
        if let last = stats.lastRewardedAt {
            return last.formatted(date: .numeric, time: .omitted)
        }
        return "referral_no_rewards".localizedString
    }

    private func loadStats() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        let result = await sessionStore.fetchReferralStats()
        await MainActor.run {
            stats = result
            isLoading = false
        }
    }
}
