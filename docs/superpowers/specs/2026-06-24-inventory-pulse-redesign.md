# Inventory Pulse — Cockpit Redesign for Apple Design Awards

> **Goal:** Replace the junior designer's "Dealer Cockpit" (always-dark navy island, fake readiness score, 5 competing ideas) with a single cohesive **"Inventory Pulse"** card + redesigned radar sheet, built around one dominant idea and a polished motion language. Target ADA categories: **Delight and Fun** + **Visuals and Graphics**.

---

## 1. Problem with the current branch

The `codex/design-award-cockpit` branch added ~1350 lines (DashboardView, DashboardViewModel, VehicleListView) implementing a "Dealer Cockpit":

1. **Always-dark navy block** sitting on top of a light glassmorphism dashboard → looks like two different apps. Violates cohesion, the #1 thing ADA juries reward.
2. **Readiness score 0–100** is an invented metric (`100 − critical×18 − stale×12 − …`). Dealers don't know what "62/100" means. Gamification for its own sake.
3. **Five competing elements** in one card: score ring + 3 metric tiles + age track + 3 risk cars + 2 buttons. Information overload — the opposite of good dashboard design.
4. **Hardcoded colors** (`Color(red:…)`, `Color.white.opacity(…)`) instead of design tokens — directly violates the project's "no inline hex" rule.
5. **Zero animation.** Ring, tiles, and track appear instantly and statically. The brief was "smooth, everything moves beautifully" — currently nothing does.

**Good seeds to keep:** the idea of "what needs attention right now," age buckets (fresh/aging/stale), the list of oldest cars, and the transition into a focused inventory list.

---

## 2. Design direction (decided)

**Hybrid A+B: "calm clarity" as the foundation + a living "business pulse" through motion and one breathing graphic.** Scope: large redesign (cockpit + motion language applied to key screens).

The dominant idea of the redesigned dashboard hero card is **the state of the stock** — a single, real, understandable metric (average days in inventory) rendered as a breathing arc, with the card's mood (gradient + arc color) shifting based on whether attention is needed.

**Why this wins:** one idea done flawlessly beats five done adequately. A real metric (avg days) is honest and useful. Motion creates the "delight" the jury rewards. The card stays cohesive with the app's premium language rather than being a foreign dark island.

---

## 3. Component design

### 3.1 `InventoryPulseCard` (replaces `DealerCockpitCard`)

A single card. One dominant idea. Tapping it opens the radar sheet.

**Anatomy (top → bottom):**
- Eyebrow label: `"Inventory pulse · today"` (caption, uppercase, tracked).
- Headline: one sentence reflecting stock state —
  - calm: `"All stock healthy"`
  - watch: `"3 cars are aging"`
  - urgent: `"2 cars need action"`
- Sub-line: `"<count> cars · avg <n> days in stock"`.
- **Pulse arc** (right side): a circular progress arc whose fill = average days in inventory mapped onto a 0–120 day scale. Center of the arc shows the number (`47`) + `"avg days"`. This replaces the fake readiness score.
- **Stock composition bar** (bottom): single horizontal segmented bar — `fresh / aging / stale` with counts. Proportional widths. This replaces both the age-track AND the metric tiles.

**Three mood states** (gradient + arc color + composition emphasis change; layout identical):

| State | Trigger | Gradient | Arc color | Emphasis |
|---|---|---|---|---|
| `calm` | no car ≥ 31 days | navy → blue (`#17478C` → `#2E85EB`) | white | fresh segment dominant |
| `watch` | cars 31–89 days, none ≥ 90 | navy → warm (`#17478C` → `#FA8C38`) | amber (`#FFD142`) | aging segment highlighted |
| `urgent` | any car ≥ 90 days | crimson → deep (`#3A1410` → `#E63342`) | amber→red | stale segment highlighted |

> Light mode: the card stays a rich gradient block by design (like the Performance Card in DESIGN.md §9.6) — this is ONE deliberate accent, not a foreign island, because the rest of the dashboard stays light and airy around it.

### 3.2 `InventoryRadarSheet` (replaces `InventoryRadarSheet`)

Redesigned from 5 blocks → a short narrative with 3 zones.

1. **Story headline:** large prose title built from data — `"Your lot has 2 cars past 90 days."` + one detail line — `"Together they tie up ₽4.2M. The oldest has been sitting for 112 days."`
2. **Stock-by-age diagram:** ONE horizontal proportioned bar (fresh/aging/stale) with a `0d · 30d · 60d · 90d+` axis beneath. Replaces the separate metric tiles + age track.
3. **"Oldest on your lot":** up to 3 large, tappable rows (car title · days · capital tied up). Tapping a row navigates to that vehicle's detail. Replaces the dense risk-vehicle list.
4. **Primary CTA:** `"Review all inventory →"` (navy pill) → focused inventory list sorted by age desc.

**Removed from radar:** readiness score ring, 3 metric tiles, separate age track, secondary "open analytics" button (analytics still reachable via the existing dashboard analytics destination).

### 3.3 VehicleListView aging focus (keep, lighten)

The `focusAgingInventory` flow stays (preset sort = daysDesc, show a banner). The banner is simplified to a single line + dismiss. No new chrome.

---

## 4. Motion language (the "delight" layer)

This is what the junior designer's work entirely lacked. A small, consistent set of animations applied across the redesigned surfaces. All honor `Reduce Motion`.

| Moment | Animation | Timing |
|---|---|---|
| Pulse card appears (dashboard open) | fade + slide-up + arc draws from 0 | `.snappy(0.42, bounce 0.06)`, arc draw 0.5s easeOut |
| Pulse arc value changes (data refresh) | arc re-trims with spring; number crossfades | `.spring(0.5, 0.8)` |
| Composition bar changes | segment widths animate to new proportions | `.snappy(0.38, bounce 0.04)` |
| Mood change (calm→urgent) | gradient crossfade + arc color transition | `.easeInOut(0.6)` |
| Card tap (open radar) | card scales 0.96 + haptic; sheet scales in | hapticScale + `.opacity+.scale(0.96)` |
| Radar headline | typewriter-ish staggered fade of title words | `.easeOut`, 40ms stagger |
| Radar car rows | staggered slide-in as sheet opens | `.snappy`, 50ms stagger, max 4 rows |
| Pull-to-refresh | arc spins one revolution while syncing | `.linear(1.0).repeatForever` |

**Principles:** one dominant motion per moment (never competing), springy not linear, haptic on every meaningful state transition, instantly skippable. Reuse existing `ColorTheme` motion tokens (`.snappy(duration:extraBounce:)`, hapticScale button style) so the new motion matches the rest of the app.

---

## 5. Token discipline

All new UI uses the existing `ColorTheme` palette and a few **new, documented** tokens added to the design system (not inline hex):
- `ColorTheme.pulseCalmGradient` / `pulseWatchGradient` / `pulseUrgentGradient` — the three card gradients.
- `ColorTheme.ageFresh` / `ageAging` / `ageStale` — segment colors (`#29AB63` / `#FFD142` / `#E63342`, lifted from existing status palette).
- Arc stroke = `ColorTheme.primary` / `warning` / `danger` per mood.

DESIGN.md is not treated as sacred (per user), but the *discipline* of using tokens rather than inline hex is kept — it's what makes multi-screen redesign maintainable and dark-mode-correct.

---

## 6. DashboardViewModel changes (additive, no formula changes)

Keep the existing `buildCockpitSnapshot` data computation (it already computes days-in-inventory buckets, oldest cars, capital tied up). Adapt the **presentation model** only:

- `DashboardCockpitSnapshot` → keep; add `pulseMood: PulseMood` (`.calm`/`.watch`/`.urgent`) derived from the existing bucket counts (≥90 urgent; else ≥31 watch; else calm).
- **Drop** `score` (the fake 0–100) from the public model. Remove the scoring arithmetic (`score -= min(45, …)`). The arc now represents average days / 120.
- Keep `activeVehicleCount`, `averageDaysInInventory`, age buckets, `riskVehicles`, capital sums — these feed the card and sheet directly.
- **No financial calculation formula is changed.** Profit, expenses, balances, holding costs remain byte-identical (production-safety rule §6).

### Permission handling (unchanged behavior)
- `viewInventory` gates the card. `viewFinancials` gates the capital figures and the analytics deep-link. `viewVehicleProfit` gates profit copy. Same gating as the current cockpit — only presentation changes.

---

## 7. Screens in scope (large redesign)

| Screen | Change |
|---|---|
| Dashboard (`DashboardView`) | Replace cockpit section with `InventoryPulseCard`; apply entrance + data-change motion. |
| Radar sheet | Rebuild as 3-zone narrative per §3.2. |
| VehicleListView | Lighten the aging-focus banner (keep behavior). |
| Design tokens | Add pulse + age tokens to `ColorTheme`. |
| DashboardViewModel | Drop fake score, add `pulseMood`, keep all real metrics + financials. |

**Out of scope for this iteration** (future polish, not blocking ADA submission): full motion rollout to VehicleDetailView/ExpenseListView, dark-mode-only "neon" variant, iPad-specific pulse layout.

---

## 8. Accessibility & inclusivity (ADA-relevant)

- Every animation gated behind `@Environment(\.accessibilityReduceMotion)` → instant states when on.
- Arc is decorative; the number + headline carry the meaning and are read by VoiceOver as `"Inventory pulse. 2 cars need action. Average 47 days in stock."`
- Composition bar segments labeled (`"5 fresh, 3 aging, 2 stale"`).
- Min contrast checked for all three gradient states in light and dark mode.
- All four languages (en/ru/ar/ko) + RTL: the arc and composition bar are layout-direction-agnostic; text flips via existing localization.

---

## 9. Backward compatibility (production safety)

- **No DB, RPC, RLS, Edge Function, or sync-format changes.** Pure presentation layer.
- **No financial formula changes.** The pulse uses already-computed values (days in inventory, capital = purchase price + expenses, which the cockpit already summed).
- **No `RemoteSnapshot`/`SyncQueueItem` changes.**
- Existing dashboard destinations, navigation paths, and permission gates preserved.
- Safe to ship; dealers see a prettier hero card with identical underlying numbers.

---

## 10. Validation criteria

- Dashboard builds and renders in light + dark; card shows correct mood for a dealer with 0 / some / stale stock.
- Tapping the card opens the radar sheet; tapping a car row navigates to VehicleDetail; CTA navigates to focused inventory list.
- Average-days arc animates on first appear and on data refresh; mood gradient transitions when buckets change.
- Reduce Motion: all animations collapse to instant state changes.
- `xcodebuild test` passes; no regressions in existing dashboard regression tests.
- Dark mode + light mode + RTL (Arabic) + iPhone + iPad all render without clipping (arc + composition bar scale via `GeometryReader`, `minimumScaleFactor` on all numbers).
