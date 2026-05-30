//
//  PaywallView.swift
//  Ezcar24Business
//
//  Premium RevenueCat paywall for Pro subscription.
//

import Foundation
import SwiftUI
import FirebaseAnalytics
import FirebaseCore
import RevenueCat

enum PaywallSource: String {
    case general
    case vehicleLimit = "vehicle_limit"
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

enum PaywallMode: String, Identifiable {
    case upgrade
    case manage

    var id: String { rawValue }
}

struct PaywallView: View {
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var appSessionState: AppSessionState
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
        PaywallFeature(icon: "infinity.circle.fill", title: "Unlimited Inventory", shortTitle: "paywall_feature_unlimited", subtitle: "No car limit"),
        PaywallFeature(icon: "chart.line.uptrend.xyaxis", title: "Profit Per Vehicle", shortTitle: "paywall_feature_profit", subtitle: "Know each deal"),
        PaywallFeature(icon: "icloud.fill", title: "Cloud Sync", shortTitle: "Sync", subtitle: "All devices"),
        PaywallFeature(icon: "doc.text.fill", title: "PDF Reports", shortTitle: "paywall_feature_reports", subtitle: "Shareable docs")
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

    var body: some View {
        GeometryReader { geometry in
            let layout = PaywallLayout(size: geometry.size, safeAreaInsets: geometry.safeAreaInsets)

            ZStack(alignment: .topTrailing) {
                paywallBackground

                VStack(spacing: layout.mainSpacing) {
                    VStack(spacing: layout.contentSpacing) {
                        heroSection(layout: layout)
                        featuresSection(layout: layout)
                        if isProManagement {
                            proManagementSection(layout: layout)
                        } else {
                            planSelectionSection(layout: layout)
                        }

                        if isGuest && !layout.isTiny && !isProManagement {
                            guestSyncPrompt(layout: layout)
                        }
                    }
                    .padding(.horizontal, layout.horizontalPadding)
                    .padding(.top, layout.topPadding)
                    .opacity(animateContent ? 1 : 0)
                    .offset(y: animateContent ? 0 : 18)

                    Spacer(minLength: 0)

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
        .preferredColorScheme(.dark)
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
            Color.black

            RadialGradient(
                colors: [Color(hex: "7C3AED").opacity(0.34), .clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 380
            )

            RadialGradient(
                colors: [Color(hex: "2563EB").opacity(0.24), .clear],
                center: .bottomLeading,
                startRadius: 20,
                endRadius: 460
            )
        }
        .ignoresSafeArea()
    }

    private func heroSection(layout: PaywallLayout) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Image("PaywallNeonCar")
                    .resizable()
                    .scaledToFit()
                    .frame(width: geometry.size.width * layout.carWidthScale)
                    .offset(y: layout.carOffset)
                    .opacity(0.96)

                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black.opacity(0.34), location: 0.38),
                        .init(color: .black.opacity(0.02), location: 0.68),
                        .init(color: .black.opacity(0.9), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(spacing: layout.heroTextSpacing) {
                    HStack(spacing: 7) {
                        Image(systemName: "sparkles")
                            .font(.system(size: layout.badgeIconSize, weight: .bold))
                        Text(heroBadgeText)
                            .font(.system(size: layout.badgeFontSize, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.76)
                    }
                    .foregroundStyle(Color(hex: "A855F7"))
                    .padding(.horizontal, layout.badgeHorizontalPadding)
                    .padding(.vertical, layout.badgeVerticalPadding)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.48))
                            .overlay(
                                Capsule()
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color(hex: "A855F7"), Color(hex: "4F46E5")],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ),
                                        lineWidth: 1.5
                                    )
                            )
                    )
                    .shadow(color: Color(hex: "8B5CF6").opacity(0.3), radius: 16, y: 7)

                    HStack(spacing: 7) {
                        Text(heroTitlePrefix)
                            .foregroundStyle(.white)
                        Text(heroTitleHighlight)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(hex: "F0ABFC"), Color(hex: "A855F7"), Color(hex: "7C3AED")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .font(.system(size: layout.titleFontSize, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)

                    Text(heroSubtitle)
                        .font(.system(size: layout.subtitleFontSize, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .lineSpacing(layout.subtitleLineSpacing)
                        .lineLimit(2)
                        .minimumScaleFactor(0.74)
                }
                .padding(.top, layout.heroTextTopPadding)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .frame(height: layout.heroHeight)
    }

    private func featuresSection(layout: PaywallLayout) -> some View {
        VStack(spacing: layout.sectionTitleSpacing) {
            paywallSectionTitle("WHAT YOU GET", layout: layout)

            HStack(spacing: layout.featureSpacing) {
                ForEach(features, id: \.title) { feature in
                    PaywallFeatureChip(feature: feature, layout: layout)
                }
            }
        }
    }

    private func proManagementSection(layout: PaywallLayout) -> some View {
        VStack(spacing: layout.sectionTitleSpacing) {
            paywallSectionTitle("YOUR PRO STATUS", layout: layout)

            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(hex: "22C55E").opacity(0.18))
                        .frame(width: layout.proStatusIconBoxSize, height: layout.proStatusIconBoxSize)

                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: layout.proStatusIconSize, weight: .bold))
                        .foregroundStyle(Color(hex: "4ADE80"))
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(proStatusTitle)
                        .font(.system(size: layout.proStatusTitleSize, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)

                    Text(proStatusSubtitle)
                        .font(.system(size: layout.proStatusSubtitleSize, weight: .medium))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                }

                Spacer(minLength: 6)

                Text((subscriptionManager.isTrial ? "Trial" : "Active").localizedString)
                    .font(.system(size: layout.proStatusBadgeSize, weight: .heavy))
                    .foregroundStyle(Color(hex: "86EFAC"))
                    .lineLimit(1)
                    .padding(.horizontal, layout.proStatusBadgeHorizontalPadding)
                    .padding(.vertical, 6)
                    .background(Color(hex: "22C55E").opacity(0.15), in: Capsule())
                    .overlay(Capsule().stroke(Color(hex: "22C55E").opacity(0.34), lineWidth: 1))
            }
            .padding(.horizontal, layout.proStatusHorizontalPadding)
            .frame(maxWidth: .infinity)
            .frame(height: layout.planCardHeight)
            .background(PaywallGlassBackground(cornerRadius: layout.planCornerRadius))
        }
    }

    private func planSelectionSection(layout: PaywallLayout) -> some View {
        VStack(spacing: layout.sectionTitleSpacing) {
            paywallSectionTitle("CHOOSE YOUR PLAN", layout: layout)
            let plans = displayPlans()

            if subscriptionManager.isLoading && plans.isEmpty {
                ProgressView()
                    .tint(.white)
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
                .foregroundStyle(.white.opacity(0.78))

            Button("Retry".localizedString) {
                subscriptionManager.fetchOfferings()
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Color(hex: "A855F7"))
            .frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity)
        .frame(height: layout.planCardHeight)
        .background(PaywallGlassBackground(cornerRadius: layout.planCornerRadius))
    }

    private func annualSavingsBanner(_ text: String, layout: PaywallLayout) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "tag.fill")
                .font(.system(size: layout.savingsBannerIconSize, weight: .bold))
                .foregroundStyle(Color(hex: "86EFAC"))

            Text(text)
                .font(.system(size: layout.savingsBannerFontSize, weight: .bold))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(layout.isUltraTiny ? 1 : 2)
                .minimumScaleFactor(0.72)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, layout.isCompact ? 10 : 12)
        .frame(maxWidth: .infinity)
        .frame(minHeight: layout.savingsBannerHeight)
        .background(Color(hex: "22C55E").opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(hex: "86EFAC").opacity(0.22), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func planCards(_ plans: [PaywallDisplayPlan], layout: PaywallLayout) -> some View {
        GeometryReader { proxy in
            let spacing = layout.planCardSpacing
            let count = max(CGFloat(plans.count), 1)
            let fittedWidth = (proxy.size.width - spacing * (count - 1)) / count
            let width = plans.count <= 3
                ? fittedWidth
                : layout.scrollingPlanCardWidth

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: spacing) {
                    ForEach(plans) { plan in
                        PaywallPlanCard(
                            plan: plan,
                            width: width,
                            height: layout.planCardHeight,
                            isCompact: layout.isCompact,
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
            .scrollDisabled(plans.count <= 3)
        }
        .frame(height: layout.planCardHeight)
    }

    private func guestSyncPrompt(layout: PaywallLayout) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(hex: "A855F7"))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color(hex: "6D28D9").opacity(0.22)))

            VStack(alignment: .leading, spacing: 2) {
                Text("Purchase without an account".localizedString)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                Text("Sign in only for sync or restore on other devices.".localizedString)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.64))
                    .lineLimit(1)
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
                    .background(Color(hex: "A855F7").opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(Color(hex: "C084FC"))
            }
            .buttonStyle(.hapticScale)
        }
        .padding(.horizontal, 12)
        .frame(height: layout.guestPromptHeight)
        .background(PaywallGlassBackground(cornerRadius: 18))
    }

    private func bottomBar(layout: PaywallLayout) -> some View {
        VStack(spacing: layout.bottomSpacing) {
            trustSection(layout: layout)

            ctaButton(layout: layout)

            if let disclosure = selectedPlanDisclosure {
                Text(disclosure)
                    .font(.system(size: layout.disclosureFontSize, weight: .medium))
                    .foregroundStyle(.white.opacity(0.64))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
            }

            Button {
                subscriptionManager.restorePurchases()
            } label: {
                Text((subscriptionManager.isRestoring ? "Restoring..." : "Restore Purchases").localizedString)
                    .font(.system(size: layout.restoreFontSize, weight: .medium))
                    .foregroundStyle(Color(hex: "A855F7"))
                    .frame(minHeight: 24)
            }
            .disabled(subscriptionManager.isRestoring)

            if let restoreMessage {
                Text(restoreMessage)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.58))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            legalLinksSection(layout: layout)
        }
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.top, layout.bottomTopPadding)
        .padding(.bottom, layout.bottomPadding)
        .background(
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [.black.opacity(0), .black.opacity(0.9), .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: layout.bottomFadeHeight)

                Color.black
            }
            .ignoresSafeArea()
        )
    }

    private func proManagementBottomBar(layout: PaywallLayout) -> some View {
        VStack(spacing: layout.bottomSpacing) {
            HStack(spacing: 8) {
                Image(systemName: "crown.fill")
                    .font(.system(size: layout.trustIconSize, weight: .semibold))
                    .foregroundStyle(Color(hex: "FACC15"))
                Text("All Pro tools are unlocked on this account.".localizedString)
                    .font(.system(size: layout.trustFontSize, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Button {
                dismiss()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(.system(size: layout.ctaFontSize * 0.78, weight: .heavy))
                    Text("Done".localizedString)
                        .font(.system(size: layout.ctaFontSize, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: layout.ctaHeight)
                .background(
                    LinearGradient(
                        colors: [Color(hex: "4A00E0"), Color(hex: "8E2DE2"), Color(hex: "A855F7")],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: layout.ctaCornerRadius, style: .continuous)
                )
                .shadow(color: Color(hex: "8E2DE2").opacity(0.42), radius: layout.ctaShadowRadius, y: 7)
            }
            .buttonStyle(.hapticScale)

            if hasRevenueCatSubscription {
                Button {
                    subscriptionManager.showManageSubscriptions()
                } label: {
                    Text("Open Apple Subscription Settings".localizedString)
                        .font(.system(size: layout.restoreFontSize, weight: .medium))
                        .foregroundStyle(Color(hex: "A855F7"))
                        .frame(minHeight: 24)
                }
            }

            Button {
                subscriptionManager.restorePurchases()
            } label: {
                Text((subscriptionManager.isRestoring ? "Restoring..." : "Restore Purchases").localizedString)
                    .font(.system(size: layout.restoreFontSize, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
                    .frame(minHeight: 24)
            }
            .disabled(subscriptionManager.isRestoring)

            if let restoreMessage {
                Text(restoreMessage)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.58))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.top, layout.bottomTopPadding)
        .padding(.bottom, layout.bottomPadding)
        .background(
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [.black.opacity(0), .black.opacity(0.9), .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: layout.bottomFadeHeight)

                Color.black
            }
            .ignoresSafeArea()
        )
    }

    private func trustSection(layout: PaywallLayout) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "shield.checkered")
                .font(.system(size: layout.trustIconSize, weight: .semibold))
                .foregroundStyle(Color(hex: "A855F7"))
            Text("Cancel anytime. No hidden fees.".localizedString)
                .font(.system(size: layout.trustFontSize, weight: .medium))
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(1)
                .minimumScaleFactor(0.74)
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
                        .tint(.white)
                }

                Text(ctaText)
                    .font(.system(size: layout.ctaFontSize, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: layout.ctaHeight)
            .background(
                LinearGradient(
                    colors: [Color(hex: "4A00E0"), Color(hex: "8E2DE2"), Color(hex: "A855F7")],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: layout.ctaCornerRadius, style: .continuous)
            )
            .shadow(color: Color(hex: "8E2DE2").opacity(0.42), radius: layout.ctaShadowRadius, y: 7)
        }
        .buttonStyle(.hapticScale)
        .disabled(selectedDisplayPlan == nil || subscriptionManager.isLoading)
        .opacity(selectedDisplayPlan == nil ? 0.55 : 1)
    }

    private func legalLinksSection(layout: PaywallLayout) -> some View {
        HStack(spacing: 16) {
            Link("Terms of Use".localizedString, destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
            Text("|")
                .foregroundStyle(.white.opacity(0.32))
            Link("Privacy Policy".localizedString, destination: URL(string: "https://www.ezcar24.com/en/privacy-policy")!)
        }
        .font(.system(size: layout.legalFontSize, weight: .regular))
        .foregroundStyle(.white.opacity(0.56))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func closeButton(layout: PaywallLayout) -> some View {
        Button {
            logPaywallDismissedIfNeeded(reason: "close_button")
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: layout.closeIconSize, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: layout.closeButtonSize, height: layout.closeButtonSize)
                .background(Circle().fill(Color.white.opacity(0.08)))
                .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
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

    private var heroBadgeText: String {
        if isProManagement {
            return "Pro Access Active".localizedString
        }
        if context.source == .vehicleLimit {
            return "paywall_vehicle_limit_badge".localizedString
        }
        return "Unlock Full Potential".localizedString
    }

    private var heroTitlePrefix: String {
        if isProManagement {
            return "paywall_manage_title_prefix".localizedString
        }
        if context.source == .vehicleLimit {
            return "paywall_vehicle_limit_title_prefix".localizedString
        }
        return "paywall_upgrade_title_prefix".localizedString
    }

    private var heroTitleHighlight: String {
        if isProManagement {
            return "paywall_manage_title_highlight".localizedString
        }
        if context.source == .vehicleLimit {
            return "paywall_vehicle_limit_title_highlight".localizedString
        }
        return "paywall_upgrade_title_highlight".localizedString
    }

    private var heroSubtitle: String {
        if isProManagement {
            return "Your dealership tools are unlocked.\nKeep growing with Car Dealer Tracker.".localizedString
        }
        if context.source == .vehicleLimit {
            return "paywall_vehicle_limit_subtitle".localizedString
        }
        return "Everything you need to grow\nyour dealership business.".localizedString
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
                .fill(Color.white.opacity(0.12))
                .frame(height: 1)

            Text(title.localizedString)
                .font(.system(size: layout.sectionTitleFontSize, weight: .heavy))
                .foregroundStyle(.white.opacity(0.58))
                .tracking(layout.sectionTitleTracking)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)

            Rectangle()
                .fill(Color.white.opacity(0.12))
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
            detailText: String(format: "paywall_yearly_savings_detail".localizedString, discountPercent, yearlyProduct.localizedPriceString, fullYearPriceText)
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

    var horizontalPadding: CGFloat { isUltraTiny ? 12 : (size.width < 370 ? 14 : 18) }
    var topPadding: CGFloat { isUltraTiny ? 28 : (isTiny ? 38 : (isCompact ? 44 : 54)) }
    var mainSpacing: CGFloat { isUltraTiny ? 4 : (isTiny ? 6 : 8) }
    var contentSpacing: CGFloat { isUltraTiny ? 5 : (isTiny ? 8 : (isCompact ? 10 : 12)) }
    var heroHeight: CGFloat { isUltraTiny ? 178 : (isTiny ? 238 : (isCompact ? 268 : min(316, size.height * 0.35))) }
    var heroTextTopPadding: CGFloat { isUltraTiny ? 14 : (isTiny ? 20 : (isCompact ? 24 : 30)) }
    var heroTextSpacing: CGFloat { isUltraTiny ? 5 : (isTiny ? 7 : (isCompact ? 9 : 12)) }
    var titleFontSize: CGFloat { isUltraTiny ? 28 : (isTiny ? 34 : (isCompact ? 39 : 44)) }
    var subtitleFontSize: CGFloat { isUltraTiny ? 12 : (isTiny ? 14 : (isCompact ? 15 : 17)) }
    var subtitleLineSpacing: CGFloat { isUltraTiny ? 0 : (isTiny ? 1 : 2) }
    var badgeFontSize: CGFloat { isUltraTiny ? 11 : (isTiny ? 13 : (isCompact ? 15 : 17)) }
    var badgeIconSize: CGFloat { isUltraTiny ? 10 : (isTiny ? 12 : (isCompact ? 13 : 15)) }
    var badgeHorizontalPadding: CGFloat { isUltraTiny ? 10 : (isTiny ? 12 : 16) }
    var badgeVerticalPadding: CGFloat { isUltraTiny ? 5 : (isTiny ? 6 : 8) }
    var carWidthScale: CGFloat { isUltraTiny ? 1.04 : (isTiny ? 1.12 : (isCompact ? 1.18 : 1.25)) }
    var carOffset: CGFloat { isUltraTiny ? 18 : (isTiny ? 26 : (isCompact ? 32 : 40)) }
    var sectionTitleFontSize: CGFloat { isUltraTiny ? 10 : (isTiny ? 11 : 12) }
    var sectionTitleTracking: CGFloat { isUltraTiny ? 2 : (isTiny ? 2.5 : 3.5) }
    var sectionTitleSpacing: CGFloat { isUltraTiny ? 4 : (isTiny ? 6 : 8) }
    var featureSpacing: CGFloat { isUltraTiny ? 5 : (isTiny ? 6 : 8) }
    var featureHeight: CGFloat { isUltraTiny ? 32 : (isTiny ? 38 : 44) }
    var featureIconSize: CGFloat { isUltraTiny ? 11 : (isTiny ? 13 : 15) }
    var featureFontSize: CGFloat { isUltraTiny ? 9 : (isTiny ? 10 : 11) }
    var proStatusIconBoxSize: CGFloat { isUltraTiny ? 36 : (isTiny ? 42 : 48) }
    var proStatusIconSize: CGFloat { isUltraTiny ? 17 : (isTiny ? 20 : 23) }
    var proStatusTitleSize: CGFloat { isUltraTiny ? 15 : (isTiny ? 17 : 19) }
    var proStatusSubtitleSize: CGFloat { isUltraTiny ? 11 : (isTiny ? 12 : 13) }
    var proStatusBadgeSize: CGFloat { isUltraTiny ? 9 : (isTiny ? 10 : 11) }
    var proStatusBadgeHorizontalPadding: CGFloat { isUltraTiny ? 7 : 9 }
    var proStatusHorizontalPadding: CGFloat { isUltraTiny ? 10 : (isTiny ? 12 : 14) }
    var planCardSpacing: CGFloat { isUltraTiny ? 6 : (isTiny ? 7 : 10) }
    var planCardHeight: CGFloat { isUltraTiny ? 112 : (isTiny ? 132 : (isCompact ? 144 : 154)) }
    var scrollingPlanCardWidth: CGFloat { isUltraTiny ? 100 : (isTiny ? 112 : 124) }
    var planCornerRadius: CGFloat { isUltraTiny ? 16 : (isTiny ? 18 : 20) }
    var savingsBannerHeight: CGFloat { isUltraTiny ? 28 : (isTiny ? 32 : 36) }
    var savingsBannerFontSize: CGFloat { isUltraTiny ? 10 : (isTiny ? 11 : 12) }
    var savingsBannerIconSize: CGFloat { isUltraTiny ? 10 : (isTiny ? 11 : 12) }
    var guestPromptHeight: CGFloat { 48 }
    var bottomSpacing: CGFloat { isUltraTiny ? 4 : (isTiny ? 7 : 9) }
    var bottomTopPadding: CGFloat { isUltraTiny ? 6 : (isTiny ? 8 : 10) }
    var bottomPadding: CGFloat { isUltraTiny ? 5 : max(7, safeAreaInsets.bottom == 0 ? 7 : safeAreaInsets.bottom * 0.55) }
    var bottomFadeHeight: CGFloat { isUltraTiny ? 20 : (isTiny ? 26 : 32) }
    var trustIconSize: CGFloat { isUltraTiny ? 12 : (isTiny ? 13 : 15) }
    var trustFontSize: CGFloat { isUltraTiny ? 12 : (isTiny ? 13 : 14) }
    var ctaHeight: CGFloat { isUltraTiny ? 46 : (isTiny ? 52 : (isCompact ? 56 : 60)) }
    var ctaFontSize: CGFloat { isUltraTiny ? 17 : (isTiny ? 19 : 21) }
    var ctaCornerRadius: CGFloat { isUltraTiny ? 18 : (isTiny ? 20 : 23) }
    var ctaShadowRadius: CGFloat { isUltraTiny ? 10 : (isTiny ? 12 : 16) }
    var disclosureFontSize: CGFloat { isUltraTiny ? 10 : (isTiny ? 11 : 12) }
    var restoreFontSize: CGFloat { isUltraTiny ? 12 : (isTiny ? 13 : 15) }
    var legalFontSize: CGFloat { isUltraTiny ? 10 : (isTiny ? 11 : 12) }
    var closeButtonSize: CGFloat { isUltraTiny ? 40 : (isTiny ? 46 : 52) }
    var closeIconSize: CGFloat { isUltraTiny ? 14 : (isTiny ? 16 : 18) }
    var closeTopPadding: CGFloat { isUltraTiny ? 12 : (isTiny ? 18 : 24) }
    var closeTrailingPadding: CGFloat { isUltraTiny ? 12 : (isTiny ? 14 : 18) }
}

struct PaywallFeatureChip: View {
    let feature: PaywallFeature
    let layout: PaywallLayout

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: feature.icon)
                .font(.system(size: layout.featureIconSize, weight: .bold))
                .foregroundStyle(Color(hex: "A855F7"))

            Text(feature.shortTitle.localizedString)
                .font(.system(size: layout.featureFontSize, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
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
    let isSelected: Bool
    let isBestValue: Bool
    let isIntroEligible: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: isCompact ? 5 : 7) {
                HStack(alignment: .top) {
                    if let badgeText {
                        Text(badgeText)
                            .font(.system(size: isCompact ? 8 : 9, weight: .heavy))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, isCompact ? 6 : 8)
                            .padding(.vertical, 4)
                            .background(
                                LinearGradient(
                                    colors: [Color(hex: "A855F7"), Color(hex: "7C3AED")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: Capsule()
                            )
                    } else {
                        Color.clear
                            .frame(width: 1, height: isCompact ? 20 : 22)
                    }

                    Spacer(minLength: 4)

                    selectionIndicator
                }

                Spacer(minLength: 0)

                Text(planTitle)
                    .font(.system(size: isCompact ? 14 : 16, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                VStack(alignment: .leading, spacing: 1) {
                    Text(plan.priceText)
                        .font(.system(size: isCompact ? 17 : 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.45)

                    Text(plan.periodLabel)
                        .font(.system(size: isCompact ? 11 : 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Text(plan.billingLine)
                    .font(.system(size: isCompact ? 11 : 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }
            .padding(isCompact ? 10 : 12)
            .frame(width: width, height: height)
            .background(
                RoundedRectangle(cornerRadius: isCompact ? 18 : 20, style: .continuous)
                    .fill(
                        isSelected
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [Color(hex: "111827").opacity(0.92), Color(hex: "2E1065").opacity(0.9)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            : AnyShapeStyle(Color.white.opacity(0.08))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: isCompact ? 18 : 20, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [Color(hex: "60A5FA"), Color(hex: "A855F7"), Color(hex: "F0ABFC")],
                                    startPoint: .bottomLeading,
                                    endPoint: .topTrailing
                                )
                            )
                            : AnyShapeStyle(Color.white.opacity(0.14)),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(color: isSelected ? Color(hex: "8E2DE2").opacity(0.34) : .clear, radius: 14, y: 7)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isSelected)
    }

    private var selectionIndicator: some View {
        ZStack {
            if isSelected {
                Circle()
                    .fill(Color(hex: "C084FC"))
                    .frame(width: isCompact ? 24 : 28, height: isCompact ? 24 : 28)
                Image(systemName: "checkmark")
                    .font(.system(size: isCompact ? 11 : 12, weight: .heavy))
                    .foregroundStyle(.black.opacity(0.68))
            } else {
                Circle()
                    .stroke(Color.white.opacity(0.44), lineWidth: 2)
                    .frame(width: isCompact ? 24 : 28, height: isCompact ? 24 : 28)
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
}

struct PaywallGlassBackground: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.11), Color.white.opacity(0.055)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.22), Color.white.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
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
    private let colors: [Color] = [.red, .blue, .green, .yellow, .pink, .purple, .orange]

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
    }
}
