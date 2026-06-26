//
//  PaywallView.swift
//  Ezcar24Business
//
//  Premium RevenueCat paywall for Pro subscription.
//

import Foundation
import SwiftUI
import AVFoundation
import FirebaseAnalytics
import FirebaseCore
import RevenueCat

enum PaywallSource: String {
    case general
    case vehicleLimit = "vehicle_limit"
    case aiInsights = "ai_insights"
}

struct PaywallContext {
    let source: PaywallSource
    let vehicleCount: Int?
    let freeLimit: Int?

    var analyticsParameters: [String: Any] {
        var parameters: [String: Any] = [
            "source": source.rawValue
        ]
        if let vehicleCount {
            parameters["vehicle_count"] = vehicleCount
        }
        if let freeLimit {
            parameters["free_limit"] = freeLimit
        }
        return parameters
    }
}

enum PaywallAnalytics {
    static func log(_ event: String, context: PaywallContext, extra: [String: Any] = [:]) {
        guard FirebaseApp.app() != nil else { return }
        var parameters = context.analyticsParameters
        extra.forEach { parameters[$0.key] = $0.value }
        Analytics.logEvent(event, parameters: parameters)
    }

    static func logVehicleLimitGate(vehicleCount: Int, freeLimit: Int, entryPoint: String) {
        log(
            "vehicle_limit_gate_shown",
            context: PaywallContext(source: .vehicleLimit, vehicleCount: vehicleCount, freeLimit: freeLimit),
            extra: ["entry_point": entryPoint]
        )
    }
}

enum PaywallPalette {
    static let gold = Color(hex: "0F66FF")
    static let goldLight = Color(hex: "4F91FF")
    static let goldDeep = Color(hex: "0848C7")
    static let inkOnGold = Color.white
    static let slate = Color(hex: "DCEAFF")
    static let background = Color(hex: "F7FAFF")
    static let surface = Color.white
    static let surfaceSoft = Color(hex: "F0F6FF")
    static let text = Color(hex: "07142F")
    static let mutedText = Color(hex: "69748C")
    static let border = Color(hex: "DCE6F6")
    static let success = Color(hex: "22C55E")
}

enum PaywallMode: String, Identifiable {
    case upgrade
    case manage

    var id: String { rawValue }
}

struct PaywallView: View {
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var appSessionState: AppSessionState
    @EnvironmentObject private var regionSettings: RegionSettingsManager
    @Environment(\.dismiss) private var dismiss

    let mode: PaywallMode
    let context: PaywallContext

    @State private var animateContent = false
    @State private var selectedPlanId: String?
    @State private var showConfetti = false
    @State private var isSuccessAnimating = false
    @State private var didLogShown = false
    @State private var didLogDismissed = false
    @State private var didCompletePurchase = false

    private let features = [
        PaywallFeature(icon: "car.fill", title: "Unlimited Inventory", shortTitle: "paywall_feature_unlimited", subtitle: "paywall_feature_unlimited_detail"),
        PaywallFeature(icon: "icloud.fill", title: "Cloud Sync", shortTitle: "Sync", subtitle: "paywall_feature_sync_detail"),
        PaywallFeature(icon: "doc.text.fill", title: "PDF Reports", shortTitle: "paywall_feature_reports", subtitle: "paywall_feature_reports_detail")
    ]

    init(mode: PaywallMode = .upgrade, source: PaywallSource = .general, vehicleCount: Int? = nil, freeLimit: Int? = nil) {
        self.mode = mode
        self.context = PaywallContext(source: source, vehicleCount: vehicleCount, freeLimit: freeLimit)
    }

    private var isSignedIn: Bool {
        if case .signedIn = sessionStore.status { return true }
        return false
    }

    private var isGuest: Bool {
        appSessionState.isGuestMode && !isSignedIn
    }

    private var isProManagement: Bool {
        mode == .manage && subscriptionManager.isProAccessActive
    }

    private var isArabicLanguage: Bool {
        regionSettings.selectedLanguage == .arabic
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = PaywallLayout(size: geometry.size, safeAreaInsets: geometry.safeAreaInsets)

            ZStack(alignment: .topTrailing) {
                paywallBackground

                VStack(spacing: layout.mainSpacing) {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: layout.contentSpacing) {
                            heroSection(layout: layout)
                            if isProManagement {
                                proManagementSection(layout: layout)
                            } else {
                                planSelectionSection(layout: layout)
                            }
                            featuresSection(layout: layout)

                            if isGuest && !layout.isTiny && !isProManagement {
                                guestSyncPrompt(layout: layout)
                            }
                        }
                        .padding(.horizontal, layout.horizontalPadding)
                        .padding(.top, layout.topPadding)
                        .padding(.bottom, layout.contentSpacing)
                        .frame(maxWidth: layout.contentMaxWidth)
                        .frame(maxWidth: .infinity)
                    }
                    .opacity(animateContent ? 1 : 0)
                    .offset(y: animateContent ? 0 : 18)

                    Group {
                        if isProManagement {
                            proManagementBottomBar(layout: layout)
                        } else {
                            bottomBar(layout: layout)
                        }
                    }
                    .opacity(animateContent ? 1 : 0)
                    .offset(y: animateContent ? 0 : 34)
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)

                closeButton(layout: layout)

                if showConfetti {
                    PaywallConfettiView()
                        .allowsHitTesting(false)
                        .ignoresSafeArea()
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .preferredColorScheme(.light)
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.82).delay(0.08)) {
                animateContent = true
            }

            if !isProManagement && subscriptionManager.currentOffering == nil {
                subscriptionManager.fetchOfferings()
            }

            if !isProManagement {
                syncSelectedPlan()
            }

            logPaywallShownIfNeeded()
        }
        .onChange(of: subscriptionManager.currentOffering) { _, newOffering in
            guard newOffering != nil else { return }
            if !isProManagement {
                syncSelectedPlan()
            }
        }
        .onReceive(subscriptionManager.$standaloneSubscriptionProducts) { _ in
            if !isProManagement {
                syncSelectedPlan()
            }
        }
        .onChange(of: subscriptionManager.isProAccessActive) { _, isPro in
            if mode == .upgrade && isPro && !isSuccessAnimating {
                dismiss()
            }
        }
        .onDisappear {
            logPaywallDismissedIfNeeded(reason: "sheet_disappear")
        }
    }

    private var paywallBackground: some View {
        ZStack {
            PaywallPalette.background

            RadialGradient(
                colors: [PaywallPalette.goldLight.opacity(0.24), .clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 420
            )

            RadialGradient(
                colors: [PaywallPalette.slate.opacity(0.75), .clear],
                center: .bottomLeading,
                startRadius: 20,
                endRadius: 520
            )

            LinearGradient(
                colors: [Color.white.opacity(0.95), PaywallPalette.background.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private func heroSection(layout: PaywallLayout) -> some View {
        VStack(spacing: layout.heroSectionSpacing) {
            VStack(spacing: layout.heroTextSpacing) {
                HStack(spacing: 7) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: layout.badgeIconSize, weight: .semibold))
                    Text(heroBadgeText)
                        .font(.system(size: layout.badgeFontSize, weight: .semibold))
                        .tracking(isArabicLanguage ? 0 : 0.2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .foregroundStyle(PaywallPalette.gold)
                .padding(.horizontal, layout.badgeHorizontalPadding)
                .padding(.vertical, layout.badgeVerticalPadding)
                .background(Capsule().fill(PaywallPalette.gold.opacity(0.1)))
                .overlay(Capsule().stroke(PaywallPalette.gold.opacity(0.14), lineWidth: 1))

                heroTitle(layout: layout)

                Text(heroSubtitle)
                    .font(.system(size: layout.subtitleFontSize, weight: .medium))
                    .foregroundStyle(PaywallPalette.mutedText)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.72)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, layout.heroHeaderHorizontalPadding)
            .frame(maxWidth: layout.heroHeaderMaxWidth)
            .frame(maxWidth: .infinity)

            ZStack {
                LinearGradient(
                    colors: [
                        Color.white,
                        PaywallPalette.surfaceSoft,
                        PaywallPalette.goldLight.opacity(0.18)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                PaywallHeroVideoView(resourceName: "PaywallHero911", verticalShift: layout.heroVideoVerticalShift)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity)
            .frame(height: layout.heroMediaHeight)
            .clipShape(RoundedRectangle(cornerRadius: layout.heroMediaCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: layout.heroMediaCornerRadius, style: .continuous)
                    .stroke(PaywallPalette.border.opacity(0.72), lineWidth: 1)
                    .allowsHitTesting(false)
            )
            .shadow(color: PaywallPalette.gold.opacity(0.12), radius: 18, y: 10)
        }
        .frame(maxWidth: .infinity)
    }

    private func featuresSection(layout: PaywallLayout) -> some View {
        VStack(spacing: layout.sectionTitleSpacing) {
            paywallSectionTitle("paywall_features_title", layout: layout)

            VStack(spacing: 0) {
                ForEach(Array(features.enumerated()), id: \.element.title) { index, feature in
                    PaywallFeatureCard(feature: feature, layout: layout)
                        .staggeredAppear(index: index, baseDelay: 0.15, step: 0.06)
                    if index < features.count - 1 {
                        Divider()
                            .padding(.leading, layout.featureCardIconBox + 26)
                    }
                }
            }
            .background(PaywallGlassBackground(cornerRadius: layout.planCornerRadius))
        }
    }

    private func proManagementSection(layout: PaywallLayout) -> some View {
        VStack(spacing: layout.sectionTitleSpacing) {
            paywallSectionTitle("paywall_pro_status_title", layout: layout)

            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(hex: "22C55E").opacity(0.18))
                        .frame(width: layout.proStatusIconBoxSize, height: layout.proStatusIconBoxSize)

                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: layout.proStatusIconSize, weight: .bold))
                        .foregroundStyle(PaywallPalette.success)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(proStatusTitle)
                        .font(.system(size: layout.proStatusTitleSize, weight: .bold))
                        .foregroundStyle(PaywallPalette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)

                    Text(proStatusSubtitle)
                        .font(.system(size: layout.proStatusSubtitleSize, weight: .medium))
                        .foregroundStyle(PaywallPalette.mutedText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                }

                Spacer(minLength: 6)

                Text((subscriptionManager.isTrial ? "Trial" : "Active").localizedString)
                    .font(.system(size: layout.proStatusBadgeSize, weight: .heavy))
                    .foregroundStyle(PaywallPalette.success)
                    .lineLimit(1)
                    .padding(.horizontal, layout.proStatusBadgeHorizontalPadding)
                    .padding(.vertical, 6)
                    .background(Color(hex: "22C55E").opacity(0.15), in: Capsule())
                    .overlay(Capsule().stroke(Color(hex: "22C55E").opacity(0.34), lineWidth: 1))
            }
            .padding(.horizontal, layout.proStatusHorizontalPadding)
            .padding(.vertical, layout.isCompact ? 10 : 12)
            .frame(maxWidth: .infinity)
            .frame(minHeight: layout.statusCardHeight)
            .background(PaywallGlassBackground(cornerRadius: layout.planCornerRadius))
        }
    }

    private func planSelectionSection(layout: PaywallLayout) -> some View {
        VStack(spacing: layout.sectionTitleSpacing) {
            paywallSectionTitle("paywall_choose_plan_title", layout: layout)
            let plans = displayPlans()

            if subscriptionManager.isLoading && plans.isEmpty {
                ProgressView()
                    .tint(PaywallPalette.gold)
                    .frame(height: layout.planCardHeight)
            } else if plans.isEmpty {
                emptyPlansState(layout: layout)
            } else {
                planCards(plans, layout: layout)
                if let yearlySavingsText = plans.first(where: { $0.periodUnit == .year })?.savingsDetailText {
                    annualSavingsBanner(yearlySavingsText, layout: layout)
                }
            }
        }
    }

    private func emptyPlansState(layout: PaywallLayout) -> some View {
        VStack(spacing: 10) {
            Text("Unable to load plans".localizedString)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PaywallPalette.text)

            Button("Retry".localizedString) {
                subscriptionManager.fetchOfferings()
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(PaywallPalette.gold)
            .frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: layout.statusCardHeight)
        .background(PaywallGlassBackground(cornerRadius: layout.planCornerRadius))
    }

    private func annualSavingsBanner(_ text: String, layout: PaywallLayout) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: layout.savingsBannerIconSize + 2, weight: .semibold))
                .foregroundStyle(PaywallPalette.gold)

            Text(text)
                .font(.system(size: layout.savingsBannerFontSize, weight: .semibold))
                .foregroundStyle(PaywallPalette.goldDeep)
                .multilineTextAlignment(isArabicLanguage ? .trailing : .leading)
                .lineLimit(2)
                .minimumScaleFactor(isArabicLanguage ? 0.62 : 0.72)
                .allowsTightening(true)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, layout.isCompact ? 12 : 14)
        .frame(maxWidth: .infinity)
        .frame(minHeight: layout.savingsBannerHeight)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(PaywallPalette.gold.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [PaywallPalette.gold.opacity(0.32), PaywallPalette.goldDeep.opacity(0.12)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }

    @ViewBuilder
    private func planCards(_ plans: [PaywallDisplayPlan], layout: PaywallLayout) -> some View {
        VStack(spacing: layout.planCardSpacing) {
            ForEach(plans) { plan in
                PaywallPlanCard(
                    plan: plan,
                    width: 0,
                    height: layout.planCardHeight,
                    isCompact: layout.isCompact,
                    isArabicLanguage: isArabicLanguage,
                    isSelected: selectedPlanId == plan.id,
                    isBestValue: plan.periodUnit == .year,
                    isIntroEligible: plan.isIntroEligible
                ) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        selectedPlanId = plan.id
                    }
                    logPlanSelected(plan)
                }
            }
        }
    }

    private func guestSyncPrompt(layout: PaywallLayout) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(PaywallPalette.gold)
                .frame(width: 34, height: 34)
                .background(Circle().fill(PaywallPalette.gold.opacity(0.09)))

            VStack(alignment: .leading, spacing: 2) {
                Text("Purchase without an account".localizedString)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PaywallPalette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("Sign in only for sync or restore on other devices.".localizedString)
                    .font(.caption2)
                    .foregroundStyle(PaywallPalette.mutedText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 4)

            Button {
                appSessionState.exitGuestModeForLogin()
                dismiss()
            } label: {
                Text("Sign In".localizedString)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(PaywallPalette.gold.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(PaywallPalette.gold)
            }
            .buttonStyle(.hapticScale)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: layout.guestPromptHeight)
        .background(PaywallGlassBackground(cornerRadius: 18))
    }

    private func bottomBar(layout: PaywallLayout) -> some View {
        VStack(spacing: layout.bottomSpacing) {
            trustSection(layout: layout)

            ctaButton(layout: layout)

            if let disclosure = selectedPlanDisclosure {
                Text(disclosure)
                    .font(.system(size: layout.disclosureFontSize, weight: .medium))
                    .foregroundStyle(PaywallPalette.mutedText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
            }

            Button {
                subscriptionManager.restorePurchases()
            } label: {
                Text((subscriptionManager.isRestoring ? "Restoring..." : "Restore Purchases").localizedString)
                    .font(.system(size: layout.restoreFontSize, weight: .medium))
                    .foregroundStyle(PaywallPalette.gold)
                    .frame(minHeight: layout.restoreButtonMinHeight)
            }
            .disabled(subscriptionManager.isRestoring)

            if let restoreMessage {
                Text(restoreMessage)
                    .font(.caption2)
                    .foregroundStyle(PaywallPalette.mutedText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            legalLinksSection(layout: layout)
        }
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.top, layout.bottomTopPadding)
        .padding(.bottom, layout.bottomPadding)
        .frame(maxWidth: layout.contentMaxWidth)
        .frame(maxWidth: .infinity)
        .background(
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [PaywallPalette.background.opacity(0), PaywallPalette.background.opacity(0.92), PaywallPalette.background],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: layout.bottomFadeHeight)

                PaywallPalette.background
            }
            .ignoresSafeArea()
        )
    }

    private func proManagementBottomBar(layout: PaywallLayout) -> some View {
        VStack(spacing: layout.bottomSpacing) {
            HStack(spacing: 8) {
                Image(systemName: "crown.fill")
                    .font(.system(size: layout.trustIconSize, weight: .semibold))
                    .foregroundStyle(PaywallPalette.gold)
                Text("All Pro tools are unlocked on this account.".localizedString)
                    .font(.system(size: layout.trustFontSize, weight: .medium))
                    .foregroundStyle(PaywallPalette.mutedText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Button {
                dismiss()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(.system(size: layout.ctaFontSize * 0.78, weight: .bold))
                    Text("Done".localizedString)
                        .font(.system(size: layout.ctaFontSize, weight: .bold))
                        .lineLimit(1)
                }
                .foregroundStyle(PaywallPalette.inkOnGold)
                .frame(maxWidth: .infinity)
                .frame(height: layout.ctaHeight)
                .background(
                    LinearGradient(
                        colors: [PaywallPalette.goldLight, PaywallPalette.gold, PaywallPalette.goldDeep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: layout.ctaCornerRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: layout.ctaCornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.8)
                )
                .shadow(color: PaywallPalette.gold.opacity(0.32), radius: layout.ctaShadowRadius, y: 7)
            }
            .buttonStyle(.hapticScale)

            if hasRevenueCatSubscription {
                Button {
                    subscriptionManager.showManageSubscriptions()
                } label: {
                    Text("Open Apple Subscription Settings".localizedString)
                        .font(.system(size: layout.restoreFontSize, weight: .medium))
                        .foregroundStyle(PaywallPalette.gold)
                        .frame(minHeight: layout.restoreButtonMinHeight)
                }
            }

            Button {
                subscriptionManager.restorePurchases()
            } label: {
                Text((subscriptionManager.isRestoring ? "Restoring..." : "Restore Purchases").localizedString)
                    .font(.system(size: layout.restoreFontSize, weight: .medium))
                    .foregroundStyle(PaywallPalette.gold)
                    .frame(minHeight: layout.restoreButtonMinHeight)
            }
            .disabled(subscriptionManager.isRestoring)

            if let restoreMessage {
                Text(restoreMessage)
                    .font(.caption2)
                    .foregroundStyle(PaywallPalette.mutedText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.top, layout.bottomTopPadding)
        .padding(.bottom, layout.bottomPadding)
        .frame(maxWidth: layout.contentMaxWidth)
        .frame(maxWidth: .infinity)
        .background(
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [PaywallPalette.background.opacity(0), PaywallPalette.background.opacity(0.92), PaywallPalette.background],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: layout.bottomFadeHeight)

                PaywallPalette.background
            }
            .ignoresSafeArea()
        )
    }

    private func trustSection(layout: PaywallLayout) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "shield.checkered")
                .font(.system(size: layout.trustIconSize, weight: .semibold))
                .foregroundStyle(PaywallPalette.gold)
            Text("Cancel anytime. No hidden fees.".localizedString)
                .font(.system(size: layout.trustFontSize, weight: .medium))
                .foregroundStyle(PaywallPalette.mutedText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func ctaButton(layout: PaywallLayout) -> some View {
        Button {
            guard let plan = selectedDisplayPlan else { return }
            PaywallAnalytics.log("paywall_cta_tapped", context: context, extra: analyticsParameters(for: plan))
            purchase(plan: plan) { success in
                if success {
                    didCompletePurchase = true
                    PaywallAnalytics.log("paywall_purchase_success", context: context, extra: analyticsParameters(for: plan))
                    isSuccessAnimating = true
                    withAnimation {
                        showConfetti = true
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        dismiss()
                    }
                } else {
                    PaywallAnalytics.log("paywall_purchase_not_completed", context: context, extra: analyticsParameters(for: plan))
                }
            }
        } label: {
            HStack(spacing: 10) {
                if subscriptionManager.isLoading {
                    ProgressView()
                        .tint(PaywallPalette.inkOnGold)
                }

                Text(ctaText)
                    .font(.system(size: layout.ctaFontSize, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(isArabicLanguage ? 0.55 : 0.68)
                    .allowsTightening(true)
            }
            .foregroundStyle(PaywallPalette.inkOnGold)
            .padding(.horizontal, layout.isCompact ? 12 : 16)
            .frame(maxWidth: .infinity)
            .frame(height: layout.ctaHeight)
            .background(
                LinearGradient(
                    colors: [PaywallPalette.goldLight, PaywallPalette.gold, PaywallPalette.goldDeep],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: layout.ctaCornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: layout.ctaCornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.32), lineWidth: 0.8)
            )
            .shadow(color: PaywallPalette.gold.opacity(0.32), radius: layout.ctaShadowRadius, y: 7)
        }
        .buttonStyle(.hapticScale)
        .disabled(selectedDisplayPlan == nil || subscriptionManager.isLoading)
        .opacity(selectedDisplayPlan == nil ? 0.55 : 1)
    }

    private func legalLinksSection(layout: PaywallLayout) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                Link("Terms of Use".localizedString, destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                Text("|")
                    .foregroundStyle(PaywallPalette.mutedText.opacity(0.45))
                Link("Privacy Policy".localizedString, destination: URL(string: "https://www.ezcar24.com/en/privacy-policy")!)
            }

            VStack(spacing: 4) {
                Link("Terms of Use".localizedString, destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                Link("Privacy Policy".localizedString, destination: URL(string: "https://www.ezcar24.com/en/privacy-policy")!)
            }
        }
        .font(.system(size: layout.legalFontSize, weight: .regular))
        .foregroundStyle(PaywallPalette.mutedText)
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .minimumScaleFactor(0.8)
    }

    private func closeButton(layout: PaywallLayout) -> some View {
        Button {
            logPaywallDismissedIfNeeded(reason: "close_button")
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: layout.closeIconSize, weight: .bold))
                .foregroundStyle(PaywallPalette.text)
                .frame(width: layout.closeButtonSize, height: layout.closeButtonSize)
                .background(Circle().fill(Color.white.opacity(0.82)))
                .overlay(Circle().stroke(PaywallPalette.border, lineWidth: 1))
        }
        .buttonStyle(.hapticScale)
        .padding(.top, layout.closeTopPadding)
        .padding(.trailing, layout.closeTrailingPadding)
    }

    private var ctaText: String {
        if subscriptionManager.isLoading { return "Processing...".localizedString }
        guard let plan = selectedDisplayPlan else { return "Select a Plan".localizedString }
        return plan.isIntroEligible ? "paywall_trial_cta".localizedString : "Continue".localizedString
    }

    private var selectedPlanDisclosure: String? {
        guard let plan = selectedDisplayPlan else { return nil }

        if plan.isIntroEligible, plan.periodUnit == .year {
            return String(format: "paywall_trial_disclosure_yearly".localizedString, plan.priceText)
        }

        if plan.periodUnit == .year {
            return String(format: "paywall_renews_yearly".localizedString, plan.priceText)
        }

        return String(format: "paywall_renews_generic".localizedString, plan.priceText)
    }

    private func heroTitle(layout: PaywallLayout) -> some View {
        Text(heroTitleText)
            .font(.system(size: layout.titleFontSize, weight: .black, design: .rounded))
            .foregroundStyle(
                LinearGradient(
                    colors: [PaywallPalette.text, PaywallPalette.goldDeep],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.58)
            .allowsTightening(true)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }

    private var heroBadgeText: String {
        if isProManagement {
            return "Pro Access Active".localizedString
        }
        if context.source == .vehicleLimit {
            return "paywall_vehicle_limit_badge".localizedString
        }
        if context.source == .aiInsights {
            return "paywall_ai_badge".localizedString
        }
        return "Unlock Full Potential".localizedString
    }

    private var heroTitleText: String {
        if isProManagement {
            return "paywall_manage_title".localizedString
        }
        if context.source == .vehicleLimit {
            return "paywall_vehicle_limit_title".localizedString
        }
        if context.source == .aiInsights {
            return "paywall_ai_title".localizedString
        }
        return "paywall_upgrade_title".localizedString
    }

    private var heroSubtitle: String {
        if isProManagement {
            return "paywall_manage_subtitle".localizedString
        }
        if context.source == .vehicleLimit {
            return "paywall_vehicle_limit_subtitle".localizedString
        }
        if context.source == .aiInsights {
            return "paywall_ai_subtitle".localizedString
        }
        return "paywall_upgrade_subtitle".localizedString
    }

    private var hasRevenueCatSubscription: Bool {
        !(subscriptionManager.customerInfo?.entitlements.active.isEmpty ?? true)
    }

    private var proStatusTitle: String {
        if subscriptionManager.isTrial {
            return "Your Pro trial is active".localizedString
        }

        if let bonusUntil = subscriptionManager.bonusAccessUntil, bonusUntil > Date(), !hasRevenueCatSubscription {
            return "Your Pro bonus is active".localizedString
        }

        return "You're a Pro user".localizedString
    }

    private var proStatusSubtitle: String {
        if let expirationDate = subscriptionManager.expirationDate {
            return String(format: "Active until %@".localizedString, expirationDate.formatted(date: .abbreviated, time: .omitted))
        }

        if let bonusUntil = subscriptionManager.bonusAccessUntil, bonusUntil > Date() {
            return String(format: "Bonus access until %@".localizedString, bonusUntil.formatted(date: .abbreviated, time: .omitted))
        }

        return "Unlimited inventory, cloud sync, reports, and analytics are ready.".localizedString
    }

    private var restoreMessage: String? {
        switch subscriptionManager.restoreStatus {
        case .idle:
            return nil
        case .success:
            return "Purchases restored.".localizedString
        case .noPurchases:
            return "No active purchases found.".localizedString
        case .error(let message):
            return message
        }
    }

    private func paywallSectionTitle(_ title: String, layout: PaywallLayout) -> some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(PaywallPalette.border)
                .frame(height: 1)

            Text(title.localizedString)
                .font(.system(size: layout.sectionTitleFontSize, weight: .heavy))
                .foregroundStyle(PaywallPalette.mutedText)
                .tracking(isArabicLanguage ? 0 : layout.sectionTitleTracking)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .layoutPriority(1)

            Rectangle()
                .fill(PaywallPalette.border)
                .frame(height: 1)
        }
    }

    private var selectedDisplayPlan: PaywallDisplayPlan? {
        guard let selectedPlanId else { return nil }
        return displayPlans().first { $0.id == selectedPlanId }
    }

    private func availablePlans() -> [SubscriptionPurchasePlan] {
        subscriptionManager.currentSubscriptionPlans
    }

    private func displayPlans() -> [PaywallDisplayPlan] {
        let plans = availablePlans()
        let monthlyPlan = plans.first { $0.storeProduct.subscriptionPeriod?.unit == .month }
        let purchasePlans = plans.map { plan in
            let isYearlyIntroEligible = plan.storeProduct.subscriptionPeriod?.unit == .year && isIntroEligible(for: plan)
            let savings = annualSavings(for: plan.storeProduct, comparedTo: monthlyPlan?.storeProduct)
            return PaywallDisplayPlan(
                id: plan.id,
                title: planTitle(for: plan.storeProduct.subscriptionPeriod),
                priceText: plan.storeProduct.localizedPriceString,
                periodLabel: periodLabel(for: plan.storeProduct.subscriptionPeriod),
                billingLine: isYearlyIntroEligible ? "paywall_trial_billing_yearly".localizedString : billingLine(for: plan.storeProduct.subscriptionPeriod),
                savingsBadgeText: savings?.badgeText,
                savingsDetailText: savings?.detailText,
                periodUnit: plan.storeProduct.subscriptionPeriod?.unit,
                productIdentifier: plan.storeProduct.productIdentifier,
                purchasePlan: plan,
                isIntroEligible: isYearlyIntroEligible
            )
        }

        guard !purchasePlans.isEmpty || subscriptionManager.currentOffering != nil else {
            return []
        }

        let sortedPlans = sortDisplayPlans(purchasePlans)

        guard !sortedPlans.contains(where: { $0.periodUnit == .week }) else {
            return sortedPlans
        }

        return sortDisplayPlans(sortedPlans + [fallbackWeeklyPlan(existingPlans: sortedPlans)])
    }

    private func sortDisplayPlans(_ plans: [PaywallDisplayPlan]) -> [PaywallDisplayPlan] {
        plans.sorted { lhs, rhs in
            displaySortOrder(for: lhs) < displaySortOrder(for: rhs)
        }
    }

    private func displaySortOrder(for plan: PaywallDisplayPlan) -> Int {
        switch plan.periodUnit {
        case .year:
            return 0
        case .month:
            return 1
        case .week:
            return 2
        default:
            return 9
        }
    }

    private func syncSelectedPlan() {
        let plans = displayPlans()
        guard !plans.isEmpty else {
            selectedPlanId = nil
            return
        }

        if let selectedPlanId,
           plans.contains(where: { $0.id == selectedPlanId }) {
            return
        }

        if let yearly = plans.first(where: { $0.periodUnit == .year }) {
            selectedPlanId = yearly.id
        } else if let monthly = plans.first(where: { $0.periodUnit == .month }) {
            selectedPlanId = monthly.id
        } else {
            selectedPlanId = plans.first?.id
        }
    }

    private func purchase(plan: PaywallDisplayPlan, completion: @escaping (Bool) -> Void) {
        if let purchasePlan = plan.purchasePlan {
            subscriptionManager.purchase(plan: purchasePlan, completion: completion)
        } else {
            subscriptionManager.purchaseStandaloneProduct(productIdentifier: plan.productIdentifier, completion: completion)
        }
    }

    private func isIntroEligible(for plan: SubscriptionPurchasePlan) -> Bool {
        let eligibility = subscriptionManager.introEligibility[plan.storeProduct.productIdentifier]
        let hasIntroOffer = plan.storeProduct.introductoryDiscount != nil
        return hasIntroOffer && eligibility?.status == .eligible
    }

    private func annualSavings(for yearlyProduct: StoreProduct, comparedTo monthlyProduct: StoreProduct?) -> PaywallAnnualSavings? {
        guard yearlyProduct.subscriptionPeriod?.unit == .year,
              let monthlyProduct,
              monthlyProduct.subscriptionPeriod?.unit == .month else { return nil }

        let monthlyAnnualPrice = monthlyProduct.price * Decimal(12)
        let yearlyPrice = yearlyProduct.price
        guard monthlyAnnualPrice > yearlyPrice else { return nil }

        let discount = monthlyAnnualPrice - yearlyPrice
        let discountPercentDecimal = discount / monthlyAnnualPrice * Decimal(100)
        let discountPercent = Int(floor(NSDecimalNumber(decimal: discountPercentDecimal).doubleValue))
        guard discountPercent > 0 else { return nil }

        let fullYearPriceText = formattedPrice(monthlyAnnualPrice, using: yearlyProduct.priceFormatter ?? monthlyProduct.priceFormatter)
        return PaywallAnnualSavings(
            badgeText: String(format: "paywall_yearly_savings_badge".localizedString, discountPercent),
            detailText: String(format: "paywall_yearly_savings_line".localizedString, fullYearPriceText)
        )
    }

    private func formattedPrice(_ price: Decimal, using formatter: NumberFormatter?) -> String {
        if let formatter = formatter?.copy() as? NumberFormatter,
           let priceText = formatter.string(from: price as NSDecimalNumber) {
            return priceText
        }
        return NSDecimalNumber(decimal: price).stringValue
    }

    private func fallbackWeeklyPlan(existingPlans: [PaywallDisplayPlan]) -> PaywallDisplayPlan {
        PaywallDisplayPlan(
            id: SubscriptionPackageCatalog.standaloneWeeklyProductIdentifiers[0],
            title: "Weekly".localizedString,
            priceText: fallbackWeeklyPriceText(existingPlans: existingPlans),
            periodLabel: "paywall_period_week".localizedString,
            billingLine: "Billed weekly".localizedString,
            savingsBadgeText: nil,
            savingsDetailText: nil,
            periodUnit: .week,
            productIdentifier: SubscriptionPackageCatalog.standaloneWeeklyProductIdentifiers[0],
            purchasePlan: nil,
            isIntroEligible: false
        )
    }

    private func fallbackWeeklyPriceText(existingPlans: [PaywallDisplayPlan]) -> String {
        let samplePrice = existingPlans.first?.priceText ?? "$9.99"
        if samplePrice.contains("AED") { return "AED 14.99" }
        if samplePrice.contains("$") { return "$3.99" }
        if samplePrice.contains("€") { return "€3.99" }
        if samplePrice.contains("£") { return "£3.99" }
        return "3.99"
    }

    private func planTitle(for period: SubscriptionPeriod?) -> String {
        guard let period else { return "Plan".localizedString }

        switch period.unit {
        case .week:
            return "Weekly".localizedString
        case .month:
            return (period.value == 3 ? "Quarterly" : "Monthly").localizedString
        case .year:
            return "Yearly".localizedString
        default:
            return "Plan".localizedString
        }
    }

    private func periodLabel(for period: SubscriptionPeriod?) -> String {
        guard let period else { return "paywall_period_generic".localizedString }

        switch period.unit {
        case .day:
            return "paywall_period_day".localizedString
        case .week:
            return "paywall_period_week".localizedString
        case .month:
            return (period.value == 3 ? "paywall_period_three_months" : "paywall_period_month").localizedString
        case .year:
            return "paywall_period_year".localizedString
        @unknown default:
            return "paywall_period_generic".localizedString
        }
    }

    private func billingLine(for period: SubscriptionPeriod?) -> String {
        guard let period else { return "Billed automatically".localizedString }

        switch period.unit {
        case .day:
            return "Billed daily".localizedString
        case .week:
            return "Billed weekly".localizedString
        case .month:
            return (period.value == 3 ? "Billed quarterly" : "Billed monthly").localizedString
        case .year:
            return "Billed yearly".localizedString
        @unknown default:
            return "Billed automatically".localizedString
        }
    }

    private func logPaywallShownIfNeeded() {
        guard !didLogShown else { return }
        didLogShown = true
        var parameters: [String: Any] = [
            "mode": mode.rawValue
        ]
        if let selectedDisplayPlan {
            analyticsParameters(for: selectedDisplayPlan).forEach { parameters[$0.key] = $0.value }
        }
        PaywallAnalytics.log("paywall_shown", context: context, extra: parameters)
    }

    private func logPaywallDismissedIfNeeded(reason: String) {
        guard !didLogDismissed, !didCompletePurchase, !subscriptionManager.isProAccessActive else { return }
        didLogDismissed = true
        var parameters: [String: Any] = [
            "reason": reason,
            "mode": mode.rawValue
        ]
        if let selectedDisplayPlan {
            analyticsParameters(for: selectedDisplayPlan).forEach { parameters[$0.key] = $0.value }
        }
        PaywallAnalytics.log("paywall_dismissed", context: context, extra: parameters)
    }

    private func logPlanSelected(_ plan: PaywallDisplayPlan) {
        PaywallAnalytics.log("paywall_plan_selected", context: context, extra: analyticsParameters(for: plan))
    }

    private func analyticsParameters(for plan: PaywallDisplayPlan) -> [String: Any] {
        [
            "product_id": plan.productIdentifier,
            "plan_period": plan.analyticsPeriod,
            "is_yearly": plan.periodUnit == .year,
            "is_intro_eligible": plan.isIntroEligible
        ]
    }
}

struct PaywallFeature {
    let icon: String
    let title: String
    let shortTitle: String
    let subtitle: String
}

struct PaywallLayout {
    let size: CGSize
    let safeAreaInsets: EdgeInsets

    var isUltraTiny: Bool { size.height < 640 || size.width < 340 }
    var isTiny: Bool { size.height < 720 || size.width < 370 }
    var isCompact: Bool { size.height < 800 || size.width < 390 }

    var contentMaxWidth: CGFloat { 560 }
    var horizontalPadding: CGFloat { isUltraTiny ? 12 : (size.width < 370 ? 14 : 18) }
    var topPadding: CGFloat { isUltraTiny ? 14 : (isTiny ? 18 : (isCompact ? 20 : 22)) }
    var mainSpacing: CGFloat { isUltraTiny ? 4 : (isTiny ? 6 : 8) }
    var contentSpacing: CGFloat { isUltraTiny ? 7 : (isTiny ? 9 : (isCompact ? 10 : 12)) }
    var heroSectionSpacing: CGFloat { isUltraTiny ? 8 : (isTiny ? 9 : 10) }
    var heroMediaHeight: CGFloat { isUltraTiny ? 190 : (isTiny ? 214 : (isCompact ? 238 : min(254, size.height * 0.3))) }
    var heroVideoVerticalShift: CGFloat { isUltraTiny ? 56 : (isTiny ? 62 : 68) }
    var heroMediaCornerRadius: CGFloat { isUltraTiny ? 22 : (isTiny ? 24 : 28) }
    var heroHeaderHorizontalPadding: CGFloat { isUltraTiny ? 6 : 10 }
    var heroHeaderMaxWidth: CGFloat { min(size.width - horizontalPadding * 2, isUltraTiny ? 320 : 440) }
    var heroTextSpacing: CGFloat { isUltraTiny ? 4 : (isTiny ? 5 : (isCompact ? 7 : 8)) }
    var titleFontSize: CGFloat { isUltraTiny ? 26 : (isTiny ? 29 : (isCompact ? 31 : 34)) }
    var subtitleFontSize: CGFloat { isUltraTiny ? 11.5 : (isTiny ? 12 : 13) }
    var badgeFontSize: CGFloat { isUltraTiny ? 10.5 : (isTiny ? 12 : (isCompact ? 13 : 14)) }
    var badgeIconSize: CGFloat { isUltraTiny ? 10 : (isTiny ? 12 : (isCompact ? 13 : 15)) }
    var badgeHorizontalPadding: CGFloat { isUltraTiny ? 10 : (isTiny ? 12 : 16) }
    var badgeVerticalPadding: CGFloat { isUltraTiny ? 5 : (isTiny ? 6 : 8) }
    var carWidthScale: CGFloat { isUltraTiny ? 1.04 : (isTiny ? 1.12 : (isCompact ? 1.18 : 1.25)) }
    var carOffset: CGFloat { isUltraTiny ? 18 : (isTiny ? 26 : (isCompact ? 32 : 40)) }
    var sectionTitleFontSize: CGFloat { isUltraTiny ? 10 : (isTiny ? 11 : 12) }
    var sectionTitleTracking: CGFloat { isUltraTiny ? 0.4 : (isTiny ? 0.6 : 0.8) }
    var sectionTitleSpacing: CGFloat { isUltraTiny ? 4 : (isTiny ? 6 : 8) }
    var featureSpacing: CGFloat { isUltraTiny ? 5 : (isTiny ? 6 : 8) }
    var featureHeight: CGFloat { isUltraTiny ? 32 : (isTiny ? 38 : 44) }
    var featureIconSize: CGFloat { isUltraTiny ? 11 : (isTiny ? 13 : 15) }
    var featureFontSize: CGFloat { isUltraTiny ? 9 : (isTiny ? 10 : 11) }
    var featureCardHeight: CGFloat { isUltraTiny ? 56 : (isTiny ? 62 : (isCompact ? 68 : 72)) }
    var featureCardIconBox: CGFloat { isUltraTiny ? 34 : (isTiny ? 38 : 42) }
    var featureCardIconSize: CGFloat { isUltraTiny ? 16 : (isTiny ? 18 : 20) }
    var featureCardTitleSize: CGFloat { isUltraTiny ? 13 : (isTiny ? 14 : 15.5) }
    var featureCardSubtitleSize: CGFloat { isUltraTiny ? 11 : (isTiny ? 12 : 12.5) }
    var proStatusIconBoxSize: CGFloat { isUltraTiny ? 36 : (isTiny ? 42 : 48) }
    var proStatusIconSize: CGFloat { isUltraTiny ? 17 : (isTiny ? 20 : 23) }
    var proStatusTitleSize: CGFloat { isUltraTiny ? 15 : (isTiny ? 17 : 19) }
    var proStatusSubtitleSize: CGFloat { isUltraTiny ? 11 : (isTiny ? 12 : 13) }
    var proStatusBadgeSize: CGFloat { isUltraTiny ? 9 : (isTiny ? 10 : 11) }
    var proStatusBadgeHorizontalPadding: CGFloat { isUltraTiny ? 7 : 9 }
    var proStatusHorizontalPadding: CGFloat { isUltraTiny ? 10 : (isTiny ? 12 : 14) }
    var planCardSpacing: CGFloat { isUltraTiny ? 4 : (isTiny ? 5 : 6) }
    var planCardHeight: CGFloat { isUltraTiny ? 50 : (isTiny ? 54 : (isCompact ? 58 : 60)) }
    var scrollingPlanCardWidth: CGFloat { isUltraTiny ? 100 : (isTiny ? 112 : 124) }
    var planCornerRadius: CGFloat { isUltraTiny ? 16 : (isTiny ? 18 : 20) }
    var statusCardHeight: CGFloat { isUltraTiny ? 56 : (isTiny ? 62 : (isCompact ? 66 : 70)) }
    var savingsBannerHeight: CGFloat { isUltraTiny ? 28 : (isTiny ? 32 : 36) }
    var savingsBannerFontSize: CGFloat { isUltraTiny ? 10 : (isTiny ? 11 : 12) }
    var savingsBannerIconSize: CGFloat { isUltraTiny ? 10 : (isTiny ? 11 : 12) }
    var guestPromptHeight: CGFloat { 48 }
    var bottomSpacing: CGFloat { isUltraTiny ? 3 : (isTiny ? 4 : 5) }
    var bottomTopPadding: CGFloat { isUltraTiny ? 4 : (isTiny ? 5 : 6) }
    var bottomPadding: CGFloat { isUltraTiny ? 4 : max(4, safeAreaInsets.bottom == 0 ? 4 : safeAreaInsets.bottom * 0.34) }
    var bottomFadeHeight: CGFloat { isUltraTiny ? 14 : (isTiny ? 17 : 20) }
    var trustIconSize: CGFloat { isUltraTiny ? 11 : (isTiny ? 12 : 13) }
    var trustFontSize: CGFloat { isUltraTiny ? 11 : (isTiny ? 12 : 12.5) }
    var ctaHeight: CGFloat { isUltraTiny ? 42 : (isTiny ? 46 : (isCompact ? 50 : 52)) }
    var ctaFontSize: CGFloat { isUltraTiny ? 15.5 : (isTiny ? 17 : 18) }
    var ctaCornerRadius: CGFloat { isUltraTiny ? 16 : (isTiny ? 18 : 20) }
    var ctaShadowRadius: CGFloat { isUltraTiny ? 8 : (isTiny ? 10 : 12) }
    var disclosureFontSize: CGFloat { isUltraTiny ? 9.5 : (isTiny ? 10 : 11) }
    var restoreFontSize: CGFloat { isUltraTiny ? 11 : (isTiny ? 12 : 13) }
    var restoreButtonMinHeight: CGFloat { isUltraTiny ? 18 : (isTiny ? 20 : 21) }
    var legalFontSize: CGFloat { isUltraTiny ? 9.5 : (isTiny ? 10 : 10.5) }
    var closeButtonSize: CGFloat { isUltraTiny ? 34 : (isTiny ? 36 : 38) }
    var closeIconSize: CGFloat { isUltraTiny ? 12 : (isTiny ? 13 : 14) }
    var closeTopPadding: CGFloat { isUltraTiny ? 6 : (isTiny ? 8 : 10) }
    var closeTrailingPadding: CGFloat { isUltraTiny ? 10 : 12 }
}

struct PaywallFeatureCard: View {
    let feature: PaywallFeature
    let layout: PaywallLayout

    private var subtitleText: String {
        feature.subtitle.localizedString
    }

    var body: some View {
        HStack(alignment: .center, spacing: layout.isCompact ? 8 : 10) {
            ZStack {
                RoundedRectangle(cornerRadius: layout.isCompact ? 10 : 12, style: .continuous)
                    .fill(PaywallPalette.gold.opacity(0.09))
                    .frame(width: layout.featureCardIconBox, height: layout.featureCardIconBox)
                Image(systemName: feature.icon)
                    .font(.system(size: layout.featureCardIconSize, weight: .semibold))
                    .foregroundStyle(PaywallPalette.gold)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(feature.shortTitle.localizedString)
                    .font(.system(size: layout.featureCardTitleSize, weight: .semibold))
                    .foregroundStyle(PaywallPalette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(subtitleText)
                    .font(.system(size: layout.featureCardSubtitleSize, weight: .regular))
                    .foregroundStyle(PaywallPalette.mutedText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.64)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, layout.isCompact ? 9 : 10)
        .padding(.vertical, layout.isCompact ? 8 : 10)
        .frame(maxWidth: .infinity)
        .frame(minHeight: layout.featureCardHeight)
        .background(Color.clear)
    }
}

struct PaywallFeatureChip: View {
    let feature: PaywallFeature
    let layout: PaywallLayout

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: feature.icon)
                .font(.system(size: layout.featureIconSize, weight: .semibold))
                .foregroundStyle(PaywallPalette.gold)

            Text(feature.shortTitle.localizedString)
                .font(.system(size: layout.featureFontSize, weight: .bold))
                .foregroundStyle(PaywallPalette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
        }
        .frame(maxWidth: .infinity)
        .frame(height: layout.featureHeight)
        .background(PaywallGlassBackground(cornerRadius: 14))
    }
}

struct PaywallDisplayPlan: Identifiable {
    let id: String
    let title: String
    let priceText: String
    let periodLabel: String
    let billingLine: String
    let savingsBadgeText: String?
    let savingsDetailText: String?
    let periodUnit: SubscriptionPeriod.Unit?
    let productIdentifier: String
    let purchasePlan: SubscriptionPurchasePlan?
    let isIntroEligible: Bool

    var analyticsPeriod: String {
        switch periodUnit {
        case .day:
            return "day"
        case .week:
            return "week"
        case .month:
            return "month"
        case .year:
            return "year"
        default:
            return "unknown"
        }
    }
}

struct PaywallAnnualSavings {
    let badgeText: String
    let detailText: String
}

struct PaywallPlanCard: View {
    let plan: PaywallDisplayPlan
    let width: CGFloat
    let height: CGFloat
    let isCompact: Bool
    let isArabicLanguage: Bool
    let isSelected: Bool
    let isBestValue: Bool
    let isIntroEligible: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: isCompact ? 10 : 12) {
                selectionIndicator

                VStack(alignment: .leading, spacing: 2) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) {
                            planTitleText
                            if let badge = badgeText {
                                badgeLabel(badge)
                            }
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            planTitleText
                            if let badge = badgeText {
                                badgeLabel(badge)
                            }
                        }
                    }
                    Text(plan.billingLine)
                        .font(.system(size: isCompact ? 10.5 : 11.5, weight: .regular))
                        .foregroundStyle(PaywallPalette.mutedText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                }
                .layoutPriority(1)

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(plan.priceText)
                        .font(.system(size: isCompact ? 17 : 20, weight: .bold))
                        .foregroundStyle(isSelected ? PaywallPalette.gold : PaywallPalette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(plan.periodLabel)
                        .font(.system(size: isCompact ? 10 : 11, weight: .regular))
                        .foregroundStyle(PaywallPalette.mutedText)
                        .lineLimit(1)
                }
                .frame(minWidth: isCompact ? 82 : 96, alignment: .trailing)
            }
            .padding(.horizontal, isCompact ? 12 : 14)
            .padding(.vertical, isCompact ? 7 : 8)
            .frame(maxWidth: .infinity)
            .frame(minHeight: height)
            .background(
                RoundedRectangle(cornerRadius: isCompact ? 14 : 16, style: .continuous)
                    .fill(
                        isSelected
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [PaywallPalette.surface, PaywallPalette.surfaceSoft],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            : AnyShapeStyle(PaywallPalette.surface)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: isCompact ? 14 : 16, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [PaywallPalette.goldDeep, PaywallPalette.gold, PaywallPalette.goldLight],
                                    startPoint: .bottomLeading,
                                    endPoint: .topTrailing
                                )
                            )
                            : AnyShapeStyle(PaywallPalette.border),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .shadow(color: isSelected ? PaywallPalette.gold.opacity(0.22) : .clear, radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isSelected)
    }

    private var selectionIndicator: some View {
        ZStack {
            if isSelected {
                Circle()
                    .fill(PaywallPalette.gold)
                    .frame(width: isCompact ? 22 : 24, height: isCompact ? 22 : 24)
                Image(systemName: "checkmark")
                    .font(.system(size: isCompact ? 10 : 11, weight: .heavy))
                    .foregroundStyle(PaywallPalette.inkOnGold)
            } else {
                Circle()
                    .stroke(PaywallPalette.border, lineWidth: 2)
                    .frame(width: isCompact ? 22 : 24, height: isCompact ? 22 : 24)
            }
        }
    }

    private var badgeText: String? {
        if isBestValue { return plan.savingsBadgeText ?? (isCompact ? "Best" : "Best value").localizedString }
        if isIntroEligible { return "Trial".localizedString }
        return nil
    }

    private var planTitle: String {
        plan.title
    }

    private var planTitleText: some View {
        Text(planTitle)
            .font(.system(size: isCompact ? 14 : 15.5, weight: .semibold))
            .foregroundStyle(PaywallPalette.text)
            .lineLimit(1)
            .minimumScaleFactor(0.74)
            .layoutPriority(1)
    }

    private func badgeLabel(_ badge: String) -> some View {
        Text(badge)
            .font(.system(size: isCompact ? 8 : 9, weight: .heavy))
            .foregroundStyle(PaywallPalette.inkOnGold)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                LinearGradient(
                    colors: [PaywallPalette.goldLight, PaywallPalette.gold],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: Capsule()
            )
    }
}

struct PaywallGlassBackground: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(PaywallPalette.surface.opacity(0.92))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(PaywallPalette.border.opacity(0.9), lineWidth: 1)
            )
            .shadow(color: PaywallPalette.gold.opacity(0.07), radius: 12, y: 6)
    }
}

struct PaywallHeroVideoView: UIViewRepresentable {
    let resourceName: String
    let verticalShift: CGFloat

    func makeUIView(context: Context) -> PaywallLoopingVideoUIView {
        PaywallLoopingVideoUIView(resourceName: resourceName, verticalShift: verticalShift)
    }

    func updateUIView(_ uiView: PaywallLoopingVideoUIView, context: Context) {
        uiView.verticalShift = verticalShift
        uiView.resume()
    }

    static func dismantleUIView(_ uiView: PaywallLoopingVideoUIView, coordinator: ()) {
        uiView.pause()
    }
}

final class PaywallLoopingVideoUIView: UIView {
    private let resourceName: String
    private let playerLayer = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    var verticalShift: CGFloat {
        didSet {
            setNeedsLayout()
        }
    }

    init(resourceName: String, verticalShift: CGFloat) {
        self.resourceName = resourceName
        self.verticalShift = verticalShift
        super.init(frame: .zero)
        setupPlayer()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let shift = max(0, verticalShift)
        playerLayer.frame = CGRect(
            x: 0,
            y: -shift,
            width: bounds.width,
            height: bounds.height + shift
        )
    }

    func resume() {
        player?.play()
    }

    func pause() {
        player?.pause()
    }

    private func setupPlayer() {
        backgroundColor = .clear
        clipsToBounds = true
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "mp4") else { return }

        let item = AVPlayerItem(url: url)
        let queuePlayer = AVQueuePlayer()
        queuePlayer.isMuted = true
        queuePlayer.actionAtItemEnd = .none
        queuePlayer.automaticallyWaitsToMinimizeStalling = false

        playerLayer.player = queuePlayer
        playerLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(playerLayer)

        looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        player = queuePlayer
        queuePlayer.play()
    }
}

struct PaywallConfettiView: View {
    var body: some View {
        ZStack {
            ForEach(0..<50) { _ in
                PaywallConfettiParticle()
            }
        }
    }
}

struct PaywallConfettiParticle: View {
    @State private var location = CGPoint(x: 0, y: 0)
    @State private var rotation: Double = 0

    private let animation = Animation.linear(duration: Double.random(in: 2...4)).repeatForever(autoreverses: false)
    private let colors: [Color] = [
        PaywallPalette.goldLight,
        PaywallPalette.gold,
        PaywallPalette.goldDeep,
        .white,
        Color(hex: "E6D8B8")
    ]

    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(colors.randomElement() ?? .purple)
                .frame(width: 10, height: 10)
                .position(location)
                .rotationEffect(.degrees(rotation))
                .onAppear {
                    location = CGPoint(x: Double.random(in: 0...geometry.size.width), y: -20)

                    withAnimation(animation) {
                        location = CGPoint(x: Double.random(in: 0...geometry.size.width), y: geometry.size.height + 20)
                        rotation = Double.random(in: 0...360)
                    }
                }
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64

        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

struct PaywallView_Previews: PreviewProvider {
    static var previews: some View {
        PaywallView()
            .environmentObject(RegionSettingsManager.shared)
    }
}
