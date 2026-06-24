# Inventory Pulse Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the "Dealer Cockpit" with a single cohesive "Inventory Pulse" card + redesigned radar sheet, backed by a small additive-only ViewModel change and a consistent motion language — targeting Apple Design Awards (Delight and Fun + Visuals and Graphics).

**Architecture:** Presentation-layer-only redesign. New `InventoryPulseCard` + `InventoryRadarSheet` views replace the cockpit views. A new `PulseMood` enum and a couple of gradient/age color tokens are added. `DashboardViewModel.buildCockpitSnapshot` keeps its real metrics (days-in-inventory buckets, oldest cars, capital) but drops the fake 0–100 score and exposes a `pulseMood`. No DB/RPC/sync/formula changes.

**Tech Stack:** SwiftUI (iOS 17+), `ColorTheme` tokens, existing `HapticScaleButtonStyle`, `GeometryReader`-based arc + segmented bar, `@Environment(\.accessibilityReduceMotion)`.

**Spec:** `docs/superpowers/specs/2026-06-24-inventory-pulse-redesign.md`

All paths below are relative to the iOS project root:
`iOS Car Dealer Tracker/Ezcar24Business/...`

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `Utilities/ColorTheme.swift` | Modify | Add 3 pulse gradients + 3 age colors + `PulseMood` helper. |
| `ViewModels/DashboardViewModel.swift` | Modify | Add `PulseMood` enum; add `pulseMood` + `pulseArcFraction` to snapshot; remove `score` + scoring arithmetic. |
| `Views/DashboardView.swift` | Modify | Replace `DealerCockpitCard`/cockpit section with `InventoryPulseCard`; replace `InventoryRadarSheet` body; wire motion + reduce-motion. |
| `Views/Components/InventoryPulseCard.swift` | Create | Self-contained pulse card (arc + composition bar + mood). |
| `Views/Components/InventoryPulseArc.swift` | Create | Animated circular arc subview (draws from 0, re-trims on value change). |
| `Views/Components/InventoryRadarSheet.swift` | Create | The 3-zone radar sheet (story headline + age diagram + oldest cars + CTA). |
| `Localizable.xcstrings` | Modify | Add ~14 new keys; remove obsolete cockpit-score keys. |

Splitting the card/arc/sheet into their own files keeps `DashboardView.swift` from growing further (it is already 3200+ lines) and gives each component a single responsibility.

---

## Task 1: Add Pulse design tokens to ColorTheme

**Files:**
- Modify: `Utilities/ColorTheme.swift` (add after `premiumProfitGradient`, ~line 52)

- [ ] **Step 1: Add the age colors and pulse gradients**

Insert after the `premiumProfitGradient` closing (line 52), inside `struct ColorTheme`:

```swift
    // Inventory Pulse — age buckets
    static let ageFresh = Color(red: 0.16, green: 0.67, blue: 0.39)   // #29AB63 (success)
    static let ageAging = Color(red: 1.0, green: 0.82, blue: 0.26)    // #FFD142 (warning)
    static let ageStale = Color(red: 0.9, green: 0.2, blue: 0.26)     // #E63342 (danger)

    // Inventory Pulse — card mood gradients (one deliberate accent; rest of dashboard stays light/airy)
    static let pulseCalmGradient = LinearGradient(
        colors: [Color(red: 0.09, green: 0.28, blue: 0.55), Color(red: 0.18, green: 0.52, blue: 0.92)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let pulseWatchGradient = LinearGradient(
        colors: [Color(red: 0.09, green: 0.28, blue: 0.55), Color(red: 0.98, green: 0.55, blue: 0.22)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let pulseUrgentGradient = LinearGradient(
        colors: [Color(red: 0.23, green: 0.08, blue: 0.06), Color(red: 0.9, green: 0.2, blue: 0.26)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
```

- [ ] **Step 2: Build the iOS app to confirm it compiles**

Run:
```bash
cd "iOS Car Dealer Tracker"
xcodebuild -project Ezcar24Business.xcodeproj -scheme Ezcar24Business \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add "iOS Car Dealer Tracker/Ezcar24Business/Utilities/ColorTheme.swift"
git commit -m "Add Inventory Pulse color tokens"
```

---

## Task 2: Add PulseMood + drop fake score in DashboardViewModel

**Files:**
- Modify: `ViewModels/DashboardViewModel.swift` (~lines 98–103 snapshot struct, ~959–985 scoring block, ~878–888 `.empty`)

- [ ] **Step 1: Add the PulseMood enum**

Add near the existing `DashboardCockpitTone` enum (~line 98):

```swift
enum PulseMood {
    case calm, watch, urgent

    var gradient: LinearGradient {
        switch self {
        case .calm:   return ColorTheme.pulseCalmGradient
        case .watch:  return ColorTheme.pulseWatchGradient
        case .urgent: return ColorTheme.pulseUrgentGradient
        }
    }

    var arcColor: Color {
        switch self {
        case .calm:   return .white
        case .watch:  return ColorTheme.ageAging
        case .urgent: return ColorTheme.ageAging
        }
    }
}
```

- [ ] **Step 2: Extend the snapshot struct**

In `struct DashboardCockpitSnapshot` (~line 117), add two stored properties and drop `score`. Change:

```swift
    let score: Int
```
to:
```swift
    let pulseMood: PulseMood
    let pulseArcFraction: Double   // average days / 120, clamped 0...1
```

- [ ] **Step 3: Update the `.empty` static factory**

In `static var empty` (~line 134), replace `score: 100,` with:

```swift
            pulseMood: .calm,
            pulseArcFraction: 0,
```

- [ ] **Step 4: Compute mood + arc; remove scoring arithmetic**

In `buildCockpitSnapshot(vehicles:)` (~line 959–985), replace the block that computes `score`:

```swift
        var score = 100
        score -= min(45, criticalCount * 18 + staleCount * 12 + agingCount * 5)
        if periodSalesProfit < 0 { score -= 16 }
        if expensePressure { score -= 10 }
        if hasCreditPressure { score -= 8 }
        score = max(0, min(100, score))
```

with:

```swift
        let pulseMood: PulseMood
        if criticalCount > 0 {
            pulseMood = .urgent
        } else if staleCount > 0 || agingCount > 0 {
            pulseMood = .watch
        } else {
            pulseMood = .calm
        }
        let pulseArcFraction = min(1.0, max(0.0, Double(averageDays) / 120.0))
```

- [ ] **Step 5: Pass the new fields into the constructed snapshot**

In the final `DashboardCockpitSnapshot(...)` initializer call (~line 970–1040), replace `score: score,` with:

```swift
            pulseMood: pulseMood,
            pulseArcFraction: pulseArcFraction,
```

- [ ] **Step 6: Build to confirm no other references to `.score` remain**

Run:
```bash
cd "iOS Car Dealer Tracker"
xcodebuild -project Ezcar24Business.xcodeproj -scheme Ezcar24Business \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -8
```
Expected: `** BUILD SUCCEEDED **`. If it fails on `.score`, fix the remaining reference (search `cockpitSnapshot.score` / `snapshot.score`).

- [ ] **Step 7: Commit**

```bash
git add "iOS Car Dealer Tracker/Ezcar24Business/ViewModels/DashboardViewModel.swift"
git commit -m "Replace cockpit score with pulse mood and arc fraction"
```

---

## Task 3: Create the animated InventoryPulseArc component

**Files:**
- Create: `Views/Components/InventoryPulseArc.swift`

- [ ] **Step 1: Create the file with the arc view**

```swift
//
//  InventoryPulseArc.swift
//  Ezcar24Business
//

import SwiftUI

struct InventoryPulseArc: View {
    let fraction: Double          // 0...1
    let strokeColor: Color
    let centerValue: String
    let centerLabel: String

    @State private var displayedFraction: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.22), lineWidth: 7)

            Circle()
                .trim(from: 0, to: displayedFraction)
                .stroke(
                    strokeColor,
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 1) {
                Text(centerValue)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                Text(centerLabel)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.72))
                    .textCase(.uppercase)
            }
        }
        .frame(width: 76, height: 76)
        .onAppear { animate(to: fraction) }
        .onChange(of: fraction) { _, newValue in animate(to: newValue) }
    }

    private func animate(to value: Double) {
        if reduceMotion {
            displayedFraction = value
        } else {
            withAnimation(.snappy(duration: 0.5, extraBounce: 0.04)) {
                displayedFraction = value
            }
        }
    }
}
```

- [ ] **Step 2: Add the new file to the Xcode project**

The file must be a member of the `Ezcar24Business` target. If the project uses file-system-synchronized groups (Xcode 16), placing it under `Views/Components/` auto-includes it. Otherwise, add it via the `project.pbxproj` membership. Build in the next task will confirm.

- [ ] **Step 3: Commit**

```bash
git add "iOS Car Dealer Tracker/Ezcar24Business/Views/Components/InventoryPulseArc.swift"
git commit -m "Add animated Inventory Pulse arc"
```

---

## Task 4: Create the InventoryPulseCard component

**Files:**
- Create: `Views/Components/InventoryPulseCard.swift`

- [ ] **Step 1: Create the card view**

```swift
//
//  InventoryPulseCard.swift
//  Ezcar24Business
//

import SwiftUI

struct InventoryPulseCard: View {
    let snapshot: DashboardCockpitSnapshot
    let canViewInventory: Bool
    let canViewFinancials: Bool
    let onTap: () -> Void

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var mood: PulseMood { snapshot.pulseMood }

    private var headline: String {
        switch mood {
        case .calm:   return "pulse_headline_calm".localizedString
        case .watch:  return String(format: "pulse_headline_watch".localizedString, snapshot.slowVehicleCount + agingCount())
        case .urgent: return String(format: "pulse_headline_urgent".localizedString, criticalCount())
        }
    }

    private var subline: String {
        String(format: "pulse_subline".localizedString, snapshot.activeVehicleCount, snapshot.averageDaysInInventory)
    }

    private func agingCount() -> Int {
        snapshot.ageBuckets.first(where: { $0.id == "aging" })?.count ?? 0
    }
    private func criticalCount() -> Int {
        snapshot.ageBuckets.first(where: { $0.id == "critical" })?.count ?? 0
    }
    private func freshCount() -> Int {
        snapshot.ageBuckets.first(where: { $0.id == "fresh" })?.count ?? 0
    }
    private func staleCount() -> Int {
        snapshot.ageBuckets.first(where: { $0.id == "stale" })?.count ?? 0
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("pulse_eyebrow".localizedString)
                            .font(.caption.weight(.bold))
                            .foregroundColor(.white.opacity(0.72))
                            .textCase(.uppercase)
                            .tracking(1.2)

                        Text(headline)
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)

                        Text(subline)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.82))
                    }
                    Spacer(minLength: 12)
                    InventoryPulseArc(
                        fraction: snapshot.pulseArcFraction,
                        strokeColor: mood.arcColor,
                        centerValue: "\(snapshot.averageDaysInInventory)",
                        centerLabel: "pulse_avg_days".localizedString
                    )
                }

                compositionBar
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    mood.gradient
                    RadialGradient(
                        colors: [.white.opacity(0.16), .clear],
                        center: .topTrailing,
                        startRadius: 10,
                        endRadius: 220
                    )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.22), radius: 16, x: 0, y: 10)
        }
        .buttonStyle(.hapticScale)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .onAppear {
            if reduceMotion { appeared = true }
            else { withAnimation(.snappy(duration: 0.42, extraBounce: 0.06)) { appeared = true } }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(headline). \(subline)")
        .accessibilityAddTraits(.isButton)
    }

    private var compositionBar: some View {
        GeometryReader { proxy in
            let total = max(1, freshCount() + agingCount() + staleCount() + criticalCount())
            let spacing: CGFloat = 4
            let usable = max(0, proxy.size.width - spacing * 3)
            HStack(spacing: spacing) {
                segment(color: ColorTheme.ageFresh, count: freshCount(), total: total, width: usable, spacing: spacing, label: "pulse_fresh")
                segment(color: ColorTheme.ageAging, count: agingCount(), total: total, width: usable, spacing: spacing, label: "pulse_aging")
                segment(color: ColorTheme.ageStale, count: staleCount() + criticalCount(), total: total, width: usable, spacing: spacing, label: "pulse_stale")
            }
        }
        .frame(height: 30)
        .animation(reduceMotion ? nil : .snappy(duration: 0.38, extraBounce: 0.04), value: snapshot.ageBuckets.map(\.count))
    }

    private func segment(color: Color, count: Int, total: Int, width: CGFloat, spacing: CGFloat, label: LocalizedStringKey) -> some View {
        let w = max(0, width * CGFloat(count) / CGFloat(total))
        return RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(color)
            .frame(width: count > 0 ? w : 0)
            .overlay(
                count > 0 ?
                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.white)
                : nil
            )
            .accessibilityLabel(String(format: "pulse_segment_accessibility".localizedString, String(localized: label), count))
    }
}
```

- [ ] **Step 2: Build (confirms file target membership + snapshot fields)**

Run:
```bash
cd "iOS Car Dealer Tracker"
xcodebuild -project Ezcar24Business.xcodeproj -scheme Ezcar24Business \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -8
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add "iOS Car Dealer Tracker/Ezcar24Business/Views/Components/InventoryPulseCard.swift"
git commit -m "Add Inventory Pulse card component"
```

---

## Task 5: Create the redesigned InventoryRadarSheet component

**Files:**
- Create: `Views/Components/InventoryRadarSheet.swift`

- [ ] **Step 1: Create the sheet view (3 zones: story headline, age diagram, oldest cars, CTA)**

```swift
//
//  InventoryRadarSheet.swift
//  Ezcar24Business
//

import SwiftUI

struct InventoryRadarSheet: View {
    let snapshot: DashboardCockpitSnapshot
    let canViewInventory: Bool
    let canViewFinancials: Bool
    let onOpenVehicle: (NSManagedObjectID) -> Void
    let onReviewAll: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var criticalCount: Int { snapshot.ageBuckets.first(where: { $0.id == "critical" })?.count ?? 0 }
    private var staleCount: Int { snapshot.ageBuckets.first(where: { $0.id == "stale" })?.count ?? 0 }
    private var agingCount: Int { snapshot.ageBuckets.first(where: { $0.id == "aging" })?.count ?? 0 }
    private var freshCount: Int { snapshot.ageBuckets.first(where: { $0.id == "fresh" })?.count ?? 0 }

    private var staleTotal: Int { criticalCount + staleCount }

    private var storyTitle: String {
        String(format: staleTotal > 0
               ? "radar_story_title_stale".localizedString
               : "radar_story_title_ok".localizedString,
               staleTotal, snapshot.averageDaysInInventory)
    }

    private var totalTiedUp: Decimal {
        snapshot.riskVehicles.prefix(3).reduce(0) { $0 + $1.capital }
    }

    private var storyDetail: String {
        guard let oldest = snapshot.riskVehicles.first else {
            return String(format: "radar_story_detail_empty".localizedString, snapshot.averageDaysInInventory)
        }
        return String(format: "radar_story_detail".localizedString,
                      canViewFinancials ? totalTiedUp.asCurrencyCompact() : "",
                      oldest.daysInInventory)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                storyHeader
                ageDiagram
                oldestCarsSection
                if canViewInventory { reviewAllButton }
            }
            .padding(20)
        }
        .background(ColorTheme.background.ignoresSafeArea())
        .onAppear {
            if reduceMotion { appeared = true }
            else { withAnimation(.snappy(duration: 0.4, extraBounce: 0.05)) { appeared = true } }
        }
    }

    private var storyHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("radar_eyebrow".localizedString)
                .font(.caption.weight(.bold))
                .foregroundColor(ColorTheme.secondaryText)
                .textCase(.uppercase)
                .tracking(0.8)
            Text(storyTitle)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundColor(ColorTheme.primaryText)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
            Text(storyDetail)
                .font(.subheadline)
                .foregroundColor(ColorTheme.secondaryText)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
    }

    private var ageDiagram: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("radar_age_label".localizedString)
                .font(.caption.weight(.bold))
                .foregroundColor(ColorTheme.secondaryText)
                .textCase(.uppercase)

            GeometryReader { proxy in
                let total = max(1, freshCount + agingCount + staleCount + criticalCount)
                let spacing: CGFloat = 4
                let usable = max(0, proxy.size.width - spacing * 2)
                HStack(spacing: spacing) {
                    bar(ColorTheme.ageFresh, freshCount, total, usable, spacing)
                    bar(ColorTheme.ageAging, agingCount, total, usable, spacing)
                    bar(ColorTheme.ageStale, staleCount + criticalCount, total, usable, spacing)
                }
            }
            .frame(height: 36)

            HStack {
                axisLabel("0d"); Spacer(); axisLabel("30d"); Spacer(); axisLabel("60d"); Spacer(); axisLabel("90d+")
            }
        }
        .padding(14)
        .background(ColorTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .cardStyle()
    }

    private func bar(_ color: Color, _ count: Int, _ total: Int, _ width: CGFloat, _ spacing: CGFloat) -> some View {
        let w = max(0, width * CGFloat(count) / CGFloat(total))
        return RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(color)
            .frame(width: count > 0 ? w : 0)
            .overlay(count > 0 ? Text("\(count)").font(.caption.weight(.bold)).foregroundColor(.white) : nil)
    }

    private func axisLabel(_ text: String) -> some View {
        Text(text).font(.caption2).foregroundColor(ColorTheme.tertiaryText)
    }

    private var oldestCarsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !snapshot.riskVehicles.isEmpty {
                Text("radar_oldest_label".localizedString)
                    .font(.caption.weight(.bold))
                    .foregroundColor(ColorTheme.secondaryText)
                    .textCase(.uppercase)
            }
            ForEach(Array(snapshot.riskVehicles.prefix(3).enumerated()), id: \.element.id) { index, vehicle in
                Button { onOpenVehicle(vehicle.id) } label: {
                    HStack(spacing: 12) {
                        Circle().fill(ColorTheme.ageStale).frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(vehicle.title)
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(ColorTheme.primaryText)
                                .lineLimit(1)
                            Text(String(format: "radar_car_detail".localizedString, vehicle.daysInInventory,
                                        canViewFinancials ? vehicle.capital.asCurrencyCompact() : ""))
                                .font(.caption)
                                .foregroundColor(ColorTheme.secondaryText)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundColor(ColorTheme.tertiaryText)
                    }
                    .padding(14)
                    .background(ColorTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.hapticScale)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.3).delay(Double(index) * 0.05), value: appeared)
            }
        }
    }

    private var reviewAllButton: some View {
        Button(action: onReviewAll) {
            HStack {
                Text("radar_review_all".localizedString)
                Image(systemName: "arrow.right")
            }
            .font(.subheadline.weight(.bold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(ColorTheme.primary)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.hapticScale)
    }
}
```

- [ ] **Step 2: Build**

Run:
```bash
cd "iOS Car Dealer Tracker"
xcodebuild -project Ezcar24Business.xcodeproj -scheme Ezcar24Business \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -8
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add "iOS Car Dealer Tracker/Ezcar24Business/Views/Components/InventoryRadarSheet.swift"
git commit -m "Add redesigned Inventory Pulse radar sheet"
```

---

## Task 6: Wire the new components into DashboardView

**Files:**
- Modify: `Views/DashboardView.swift` (sheet `.inventoryRadar` switch ~line 109; `dealerCockpitSection` ~line 421; `DealerCockpitCard` struct ~line 872– end of cockpit code; old `InventoryRadarSheet` struct in same file)

- [ ] **Step 1: Replace the radar sheet presentation to use the new component + vehicle deep-link**

In the `.sheet(item: $presentedSheet)` switch (~line 110), replace the `case .inventoryRadar:` body with:

```swift
            case .inventoryRadar:
                InventoryRadarSheet(
                    snapshot: viewModel.cockpitSnapshot,
                    canViewInventory: permissionService.can(.viewInventory),
                    canViewFinancials: permissionService.can(.viewFinancials),
                    onOpenVehicle: { vehicleID in
                        presentedSheet = nil
                        DispatchQueue.main.async {
                            navPath.append(.priorityInventory)
                        }
                    },
                    onReviewAll: {
                        presentedSheet = nil
                        DispatchQueue.main.async {
                            navPath.append(.priorityInventory)
                        }
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
```

(Note: per-vehicle deep-linking into VehicleDetailView from the sheet is intentionally reduced to "open focused inventory" in this iteration to avoid coupling the radar to the vehicle navigation path; the focused list already sorts oldest-first so the dealer lands on the right car. A future task can wire per-vehicle navigation.)

- [ ] **Step 2: Replace the `dealerCockpitSection` computed property**

Replace the existing `dealerCockpitSection` (~line 421–444) with:

```swift
    var dealerCockpitSection: some View {
        Group {
            if permissionService.can(.viewInventory) || permissionService.can(.viewFinancials) {
                Section {
                    InventoryPulseCard(
                        snapshot: viewModel.cockpitSnapshot,
                        canViewInventory: permissionService.can(.viewInventory),
                        canViewFinancials: permissionService.can(.viewFinancials),
                        onTap: { presentedSheet = .inventoryRadar }
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 0, trailing: 0))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
    }
```

- [ ] **Step 3: Delete the now-dead cockpit view structs**

Remove these private structs from `DashboardView.swift` entirely (they are fully replaced by the new component files):
- `DealerCockpitCard`
- `CockpitScoreRing`
- `CockpitInventoryBadge`
- `CockpitMetricTile`
- `CockpitAgeTrack`
- `CockpitVehicleRow`
- The old `InventoryRadarSheet` defined in this file

Search for each `private struct …` and delete from its declaration through its closing brace. `DashboardCockpitTone.color` is still referenced by the ViewModel bucket tones; keep `DashboardCockpitTone` and its `color` extension where it lives (ViewModel) — do not delete it.

- [ ] **Step 4: Build**

Run:
```bash
cd "iOS Car Dealer Tracker"
xcodebuild -project Ezcar24Business.xcodeproj -scheme Ezcar24Business \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -8
```
Expected: `** BUILD SUCCEEDED **`. If a symbol is "ambiguous" because both old and new `InventoryRadarSheet` exist, the deletion in Step 3 missed one — remove it.

- [ ] **Step 5: Commit**

```bash
git add "iOS Car Dealer Tracker/Ezcar24Business/Views/DashboardView.swift"
git commit -m "Replace cockpit with Inventory Pulse card and radar"
```

---

## Task 7: Add localizations

**Files:**
- Modify: `Localizable.xcstrings`

- [ ] **Step 1: Add the new keys with translations (en, ru, ar, ko)**

Add these keys (the `.xcstrings` format is JSON; keys at the top level map to a localization dictionary). Values:

| Key | en | ru | ar | ko |
|---|---|---|---|---|
| `pulse_eyebrow` | `Inventory pulse · today` | `Пульс стока · сегодня` | `نبعة المخزون · اليوم` | `재고 펄스 · 오늘` |
| `pulse_avg_days` | `avg days` | `дн. в стоке` | `يوم` | `평균 일` |
| `pulse_headline_calm` | `All stock healthy` | `Сток в порядке` | `المخزون بحالة جيدة` | `재고 양호` |
| `pulse_headline_watch` | `%d cars are aging` | `%d авто стареют` | `%d سيارات تتقدم في العمر` | `%d대 노후화 중` |
| `pulse_headline_urgent` | `%d cars need action` | `%d авто требуют внимания` | `%d سيارات تحتاج إجراء` | `%d대 조치 필요` |
| `pulse_subline` | `%d cars · avg %d days in stock` | `%d авто · в среднем %d дн.` | `%d سيارة · بمعدل %d يوم` | `%d대 · 평균 %d일` |
| `pulse_fresh` | `fresh` | `свежие` | `جديد` | `신규` |
| `pulse_aging` | `aging` | `стареющие` | `يتقدم` | `노후화` |
| `pulse_stale` | `stale` | `залежавшиеся` | `راكد` | `장기` |
| `pulse_segment_accessibility` | `%1$@: %2$d cars` | `%1$@: %2$d авто` | `%1$@: %2$d سيارة` | `%1$@: %2$d대` |
| `radar_eyebrow` | `Inventory review` | `Обзор стока` | `مراجعة المخزون` | `재고 점검` |
| `radar_story_title_stale` | `%1$d cars past 90 days · avg %2$d days` | `%1$d авто старше 90 дней · средне %2$d дн.` | `%1$d سيارة تجاوزت ٩٠ يومًا · بمعدل %2$d يوم` | `90일 이상 %1$d대 · 평균 %2$d일` |
| `radar_story_title_ok` | `No stale stock · avg %2$d days` | `Залежавшихся нет · средне %2$d дн.` | `لا مخزون راكد · بمعدل %2$d يوم` | `장기 재고 없음 · 평균 %2$d일` |
| `radar_story_detail` | `Together they tie up %@. Oldest: %d days.` | `В них заморожено %@. Старейшее: %d дн.` | `تربط %@. الأقدم: %d يومًا.` | `총 %@ 묶여 있음. 최장: %d일.` |
| `radar_story_detail_empty` | `Average %d days in stock — all healthy.` | `В среднем %d дн. — всё в порядке.` | `بمعدل %d يومًا — الكل بحالة جيدة.` | `평균 %d일 — 모두 양호.` |
| `radar_age_label` | `Stock by age` | `Сток по возрасту` | `المخزون حسب العمر` | `기간별 재고` |
| `radar_oldest_label` | `Oldest on your lot` | `Старейшие на площадке` | `الأقدم في ساحتك` | `가장 오래된 차량` |
| `radar_car_detail` | `%1$d days · %2$@ tied up` | `%1$d дн. · заморожено %2$@` | `%1$d يومًا · %2$@ مرتبطة` | `%1$d일 · %2$@ 묶임` |
| `radar_review_all` | `Review all inventory` | `Открыть весь сток` | `مراجعة كل المخزون` | `전체 재고 보기` |

- [ ] **Step 2: Build to validate xcstrings JSON**

Run:
```bash
cd "iOS Car Dealer Tracker"
xcodebuild -project Ezcar24Business.xcodeproj -scheme Ezcar24Business \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add "iOS Car Dealer Tracker/Ezcar24Business/Localizable.xcstrings"
git commit -m "Add Inventory Pulse localizations"
```

---

## Task 8: Verify in simulator + regression tests

**Files:** none (verification only)

- [ ] **Step 1: Run the existing iOS regression tests**

Run:
```bash
cd "iOS Car Dealer Tracker"
xcodebuild test -project Ezcar24Business.xcodeproj -scheme Ezcar24Business \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -15
```
Expected: all tests pass (the dashboard VM changes are additive; no financial formula changed). If a cockpit-score test exists, update it to assert `pulseMood`/`pulseArcFraction` instead.

- [ ] **Step 2: Build & run on simulator, visually verify moods**

Run via the ios-simulator tooling or:
```bash
xcodebuild -project Ezcar24Business.xcodeproj -scheme Ezcar24Business \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```
Then launch in Simulator and confirm:
- Empty inventory → calm card, "All stock healthy".
- Add a vehicle with a purchase date 100 days ago → card flips to urgent mood, arc fills red, "1 car need action".
- Tap card → radar sheet opens with story headline + oldest car row.
- Tap "Review all inventory" → focused inventory list sorted oldest-first.
- Enable Settings → Accessibility → Reduce Motion → reopen dashboard → card + arc appear instantly (no animation).

- [ ] **Step 3: Check dark mode + RTL**

In Simulator, toggle dark mode and set language to Arabic; confirm the pulse card gradient, arc, and composition bar render without clipping, and the sheet reads right-to-left.

- [ ] **Step 4: Final commit (if any verification fixes)**

```bash
git status
# only commit if changes were made
git commit -am "Fix [issue found in verification]"
```

---

## Self-Review (completed)

- **Spec coverage:** §3.1 card → Task 4; §3.2 radar → Task 5; §4 motion → Tasks 3–5 (reduce-motion in each); §5 tokens → Task 1; §6 ViewModel → Task 2; §7 screens → Task 6; localizations (§8) → Task 7; validation (§10) → Task 8. All sections covered.
- **Placeholder scan:** No TBD/TODO. All code blocks complete. Any "future task" notes are explicitly out-of-scope per spec §7, not placeholders.
- **Type consistency:** `PulseMood` defined in Task 2, used in Tasks 2/4. `pulseMood`/`pulseArcFraction` snapshot fields added in Task 2, consumed in Tasks 4/5. `InventoryPulseArc(fraction:strokeColor:centerValue:centerLabel:)` matches between Task 3 (def) and Task 4 (call). `InventoryRadarSheet(snapshot:canViewInventory:canViewFinancials:onOpenVehicle:onReviewAll:)` matches Task 5 (def) and Task 6 (call). `InventoryPulseCard(snapshot:canViewInventory:canViewFinancials:onTap:)` matches Task 4 (def) and Task 6 (call).
