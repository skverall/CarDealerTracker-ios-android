import SwiftUI
import RevenueCat

struct PaywallView: View {
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var appSessionState: AppSessionState
    @EnvironmentObject private var cloudSyncManager: CloudSyncManager
    @Environment(\.dismiss) private var dismiss

    // Animation States
    @State private var animateContent: Bool = false
    @State private var selectedPackage: Package?
    @State private var showConfetti: Bool = false
    @State private var isSuccessAnimating: Bool = false

    private var isSignedIn: Bool {
        if case .signedIn = sessionStore.status { return true }
        return false
    }

    private var isGuest: Bool {
        appSessionState.isGuestMode && !isSignedIn
    }

    var body: some View {
        ZStack {
            // Background
            ColorTheme.background.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 1. Premium Header (Compact)
                headerSection
                    .frame(height: 300) // Increased height for safe area
                    .opacity(animateContent ? 1 : 0)
                    .offset(y: animateContent ? 0 : -20)
                
                VStack(spacing: 16) { // Tighter spacing
                    // 2. Value Proposition / Features
                    featuresSection
                        .opacity(animateContent ? 1 : 0)
                        .offset(y: animateContent ? 0 : 20)
                    
                    // 3. Plan Selection
                    planSelectionSection
                        .opacity(animateContent ? 1 : 0)
                        .offset(y: animateContent ? 0 : 30)
                    
                    if isGuest {
                        guestSyncPrompt
                            .opacity(animateContent ? 1 : 0)
                            .offset(y: animateContent ? 0 : 30)
                    }
                    
                    // Subscription details / auto-renew copy
                    subscriptionDetailsSection
                        .opacity(animateContent ? 1 : 0)
                        .offset(y: animateContent ? 0 : 40)
                    
                    Spacer() // Push content up, CTA down
                    
                    // 4. Trust / Social Proof
                    trustSection
                        .opacity(animateContent ? 1 : 0)
                        .padding(.bottom, 10)
                    
                    // 5. CTA Button
                    ctaButton
                        .opacity(animateContent ? 1 : 0)
                        .offset(y: animateContent ? 0 : 50)
                    
                    // 6. Legal Links
                    legalLinksSection
                        .opacity(animateContent ? 1 : 0)
                        .offset(y: animateContent ? 0 : 50)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 20)
            }
            .ignoresSafeArea(.container, edges: .top)
            
            // Confetti Overlay
            if showConfetti {
                ConfettiView()
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
            }
            
            // Close Button
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(8)
                            .background(.black.opacity(0.3))
                            .clipShape(Circle())
                    }
                    .padding(.top, 50)
                    .padding(.trailing, 20)
                }
                Spacer()
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.8).delay(0.1)) {
                animateContent = true
            }
            
            if subscriptionManager.currentOffering == nil {
                subscriptionManager.fetchOfferings()
            }
            
            // Ensure selection on appear
            if let offering = subscriptionManager.currentOffering {
                selectBestPackage(from: offering)
            }
        }
        .onChange(of: subscriptionManager.currentOffering) { _, newOffering in
            if let offering = newOffering {
                // Always try to select if nothing is selected, or re-validate
                if selectedPackage == nil {
                    selectBestPackage(from: offering)
                }
            }
        }
        .onChange(of: subscriptionManager.isProAccessActive) { _, isPro in
            // Only dismiss automatically if we are NOT in the middle of a success animation.
            // If we ARE animating, we'll dismiss manually after the animation.
            // This handles "Restore Purchases" which should dismiss immediately.
            if isPro && !isSuccessAnimating {
                dismiss()
            }
        }
    }
    
    private func selectBestPackage(from offering: Offering) {
        let packages = filteredPackages(offering.availablePackages)
        // Prefer Yearly Paid plan
        if let yearly = packages.first(where: { $0.storeProduct.subscriptionPeriod?.unit == .year }) {
            selectedPackage = yearly
        } else {
            selectedPackage = packages.first
        }
    }
    
    // MARK: - Sections
    
    private var headerSection: some View {
        ZStack(alignment: .bottom) {
            // Dynamic Gradient Background
            LinearGradient(
                colors: [Color(hex: "4A00E0"), Color(hex: "8E2DE2")], // Purple/Blue gradient
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .mask(
                CustomShape(corner: [.bottomLeft, .bottomRight], radii: 40)
            )
            
            VStack(spacing: 8) {
                // Icon
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.2))
                        .frame(width: 80, height: 80) // Smaller icon
                        .blur(radius: 10)
                    
                    Image(systemName: "crown.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                }
                .padding(.bottom, 5)
                
                Text("Upgrade to Pro")
                    .font(.system(size: 28, weight: .heavy, design: .rounded)) // Smaller font
                    .foregroundColor(.white)
                
                Text("Unlock unlimited potential for your\ndealership business.")
                    .font(.subheadline) // Smaller font
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 40)
                    .padding(.bottom, 30)
            }
        }
    }
    
    private var featuresSection: some View {
        VStack(spacing: 12) {
            Text("WHAT YOU GET")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .tracking(2)
            
            // Grid layout for features to save vertical space
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                PremiumFeatureRow(icon: "car.fill", title: "Unlimited Cars", subtitle: "No limits")
                PremiumFeatureRow(icon: "icloud.fill", title: "Cloud Sync", subtitle: "All devices")
                PremiumFeatureRow(icon: "doc.text.fill", title: "PDF Reports", subtitle: "Pro invoices")
                PremiumFeatureRow(icon: "chart.bar.fill", title: "Analytics", subtitle: "Track growth")
            }
        }
    }
    
    private var planSelectionSection: some View {
        VStack(spacing: 12) {
            if subscriptionManager.isLoading {
                ProgressView()
                    .padding()
            } else if let offering = subscriptionManager.currentOffering {
                // Use HStack with equal spacing instead of ScrollView
                HStack(spacing: 8) {
                    ForEach(filteredPackages(offering.availablePackages)) { package in
                        PlanCard(
                            package: package,
                            isSelected: selectedPackage?.identifier == package.identifier,
                            action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedPackage = package
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 20)
            } else {
                Text("Unable to load plans")
                    .foregroundColor(.secondary)
                    .font(.caption)
                Button("Retry") { subscriptionManager.fetchOfferings() }
                    .font(.caption)
            }
            
            // Restore Button
            Button(action: { subscriptionManager.restorePurchases() }) {
                Text(subscriptionManager.isRestoring ? "Restoring..." : "Restore Purchases")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .underline()
            }
            .disabled(subscriptionManager.isRestoring)
        }
    }
    
    private var guestSyncPrompt: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 26))
                    .foregroundColor(.secondary)
                    .padding(10)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Purchase without an account")
                        .font(.headline)
                    Text("You can buy now as a guest. Sign in only if you want to sync or restore purchases on other devices.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Button {
                appSessionState.exitGuestModeForLogin()
                dismiss()
            } label: {
                Text("Sign In (Optional)")
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(ColorTheme.primary.opacity(0.1))
                    .foregroundColor(ColorTheme.primary)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 10)
        }
        .padding(.vertical, 10)
    }
    
    private var trustSection: some View {
        HStack(spacing: 4) {
            Image(systemName: "shield.fill")
                .foregroundColor(.green)
                .font(.caption)
            Text("Secured by App Store")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    private var legalLinksSection: some View {
        HStack(spacing: 20) {
            Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
            Link("Privacy Policy", destination: URL(string: "https://www.ezcar24.com/en/privacy-policy")!)
        }
        .font(.caption2)
        .foregroundColor(.secondary)
        .padding(.top, 8)
    }
    
    private var subscriptionDetailsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SUBSCRIPTION DETAILS")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .tracking(1.5)
            
            if let package = selectedPackage ?? subscriptionManager.currentOffering?.availablePackages.first {
                Text(planSummary(for: package))
                    .font(.footnote)
                    .foregroundColor(ColorTheme.primaryText)
                
                if let intro = introText(for: package) {
                    Text(intro)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("Select a plan to view pricing and renewal details.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            
            Text("Payment is charged to your Apple ID at confirmation. Subscriptions renew automatically unless canceled at least 24 hours before the end of the period. Manage or cancel anytime in Settings > Apple ID > Subscriptions. Deleting the app does not cancel the subscription.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(ColorTheme.cardBackground)
        .cornerRadius(14)
    }
    
    private var ctaButton: some View {
        Button(action: {
            if let pkg = selectedPackage {
                subscriptionManager.purchase(package: pkg) { success in
                    if success {
                        isSuccessAnimating = true
                        withAnimation {
                            showConfetti = true
                        }
                        
                        // Dismiss after delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            dismiss()
                        }
                    }
                }
            }
        }) {
            HStack {
                if subscriptionManager.isLoading {
                    ProgressView().tint(.white)
                }
                Text(ctaText)
                    .font(.headline)
                    .fontWeight(.bold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [Color(hex: "4A00E0"), Color(hex: "8E2DE2")],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(16)
            .shadow(color: Color(hex: "4A00E0").opacity(0.4), radius: 8, y: 4)
        }
        .disabled(selectedPackage == nil || subscriptionManager.isLoading)
    }

    
    private var ctaText: String {
        if subscriptionManager.isLoading { return "Processing..." }
        guard let pkg = selectedPackage else { return "Select a Plan" }
        
        // Check eligibility
        let eligibility = subscriptionManager.introEligibility[pkg.storeProduct.productIdentifier]
        let isEligible = eligibility?.status == .eligible
        
        if pkg.storeProduct.subscriptionPeriod?.unit == .year && isEligible {
            return "Start 1 Week Free Trial"
        } else {
            return "Continue" // Fallback to standard subscribe text
        }
    }
    
    // MARK: - Helpers
    
    private func planSummary(for package: Package) -> String {
        let title = package.storeProduct.localizedTitle
        let price = package.storeProduct.localizedPriceString
        return "\(title): \(price) \(billingDescription(for: package))"
    }
    
    private func billingDescription(for package: Package) -> String {
        guard let period = package.storeProduct.subscriptionPeriod else {
            return "one-time purchase"
        }
        
        switch period.unit {
        case .day: return "per day"
        case .week: return "per week"
        case .month: return "per month"
        case .year: return "per year"
        @unknown default: return "per period"
        }
    }
    
    private func introText(for package: Package) -> String? {
        guard isIntroEligible(for: package) else { return nil }
        let price = package.storeProduct.localizedPriceString
        let billing = billingDescription(for: package)
        return "Free trial converts to \(price) \(billing) unless canceled at least 24 hours before the trial ends."
    }
    
    private func filteredPackages(_ packages: [Package]) -> [Package] {
        packages
            .filter {
                guard let unit = $0.storeProduct.subscriptionPeriod?.unit else { return true } // Allow lifetime
                return unit == .month || unit == .year
            }
            .sorted { lhs, rhs in
                // Sort: Monthly -> Yearly -> Lifetime
                let lhsType = sortOrder(for: lhs)
                let rhsType = sortOrder(for: rhs)
                return lhsType < rhsType
            }
    }
    
    private func sortOrder(for package: Package) -> Int {
        if package.storeProduct.productType == .nonConsumable { return 3 } // Lifetime last
        if package.storeProduct.subscriptionPeriod?.unit == .year { return 2 }
        return 1 // Monthly first
    }
    
    private func isIntroEligible(for package: Package) -> Bool {
        let eligibility = subscriptionManager.introEligibility[package.storeProduct.productIdentifier]
        let hasIntroOffer = package.storeProduct.introductoryDiscount != nil
        return hasIntroOffer && eligibility?.status == .eligible
    }
}

// MARK: - Subviews

struct PremiumFeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(ColorTheme.primary.opacity(0.1))
                    .frame(width: 36, height: 36)
                
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(ColorTheme.primary)
            }
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ColorTheme.primaryText)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(ColorTheme.secondaryText)
            }
            
            Spacer()
        }
        .padding(10)
        .background(ColorTheme.cardBackground)
        .cornerRadius(12)
        // Removed shadow for flatter, cleaner look in grid
    }
}

struct PlanCard: View {
    let package: Package
    let isSelected: Bool
    let action: () -> Void
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                // Header Badge
                HStack {
                    if isBestValue && isEligibleForTrial {
                        Text("BEST")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.green)
                            .cornerRadius(4)
                    } else if isLifetime {
                        Text("once".localizedString)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                            .cornerRadius(4)
                    } else {
                        Spacer().frame(height: 12)
                    }
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(ColorTheme.primary)
                            .font(.system(size: 14))
                    } else {
                        Circle()
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
                            .frame(width: 14, height: 14)
                    }
                }
                
                // Title
                Text(planTitle)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(ColorTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                
                // Price
                VStack(alignment: .leading, spacing: 0) {
                    Text(package.storeProduct.localizedPriceString)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(ColorTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    
                    if let period = package.storeProduct.subscriptionPeriod {
                        Text("/ \(period.unit == .year ? "year" : "mo")")
                            .font(.system(size: 9))
                            .foregroundColor(ColorTheme.secondaryText)
                    } else {
                         Text("once")
                            .font(.system(size: 9))
                            .foregroundColor(ColorTheme.secondaryText)
                    }
                }
                
                // Savings/Trial Info
                if isBestValue && isEligibleForTrial {
                    Text("7 Days Free")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(ColorTheme.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else {
                    Text("Standard")
                        .font(.system(size: 9))
                        .foregroundColor(.clear)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity) // Flexible width
            .frame(height: 130) // Reduced height
            .background(isSelected ? ColorTheme.cardBackground : ColorTheme.background)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? ColorTheme.primary : Color.clear, lineWidth: 2)
            )
            .shadow(color: isSelected ? ColorTheme.primary.opacity(0.2) : Color.black.opacity(0.05), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
    }
    
    var isBestValue: Bool {
        package.storeProduct.subscriptionPeriod?.unit == .year
    }
    
    var isLifetime: Bool {
        package.storeProduct.productType == .nonConsumable
    }
    
    var planTitle: String {
        if isLifetime { return "Lifetime" }
        if package.storeProduct.subscriptionPeriod?.unit == .year { return "Yearly" }
        return "Monthly"
    }
    
    var isEligibleForTrial: Bool {
        let eligibility = subscriptionManager.introEligibility[package.storeProduct.productIdentifier]
        return eligibility?.status == .eligible
    }
}

// Custom Shape for Header
struct CustomShape: Shape {
    var corner: UIRectCorner
    var radii: CGFloat
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corner,
            cornerRadii: CGSize(width: radii, height: radii)
        )
        return Path(path.cgPath)
    }
}

// Color Hex Helper
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

struct PaywallView_Previews: PreviewProvider {
    static var previews: some View {
        PaywallView()
    }
}

// MARK: - Confetti View
struct ConfettiView: View {
    @State private var animate = false
    
    var body: some View {
        ZStack {
            ForEach(0..<50) { _ in
                ConfettiParticle()
            }
        }
        .onAppear {
            animate = true
        }
    }
}

struct ConfettiParticle: View {
    @State private var animation = Animation.linear(duration: Double.random(in: 2...4)).repeatForever(autoreverses: false)
    @State private var location: CGPoint = CGPoint(x: 0, y: 0)
    @State private var rotation: Double = 0
    
    let colors: [Color] = [.red, .blue, .green, .yellow, .pink, .purple, .orange]
    
    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(colors.randomElement()!)
                .frame(width: 10, height: 10)
                .position(location)
                .rotationEffect(.degrees(rotation))
                .onAppear {
                    // Start from top, random X
                    location = CGPoint(x: Double.random(in: 0...geometry.size.width), y: -20)
                    
                    withAnimation(animation) {
                        // Fall to bottom
                        location = CGPoint(x: Double.random(in: 0...geometry.size.width), y: geometry.size.height + 20)
                        rotation = Double.random(in: 0...360)
                    }
                }
        }
    }
}
