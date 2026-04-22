# DESIGN.md — Car Dealer Tracker Design System

> **Source of truth** for colors, typography, spacing, and component patterns.
> AI agents **must** follow these conventions when modifying or creating UI.
> Reference implementation: iOS app (`ColorTheme.swift`, Views, Components).

---

## 1. Brand Identity

| Property | Value |
|---|---|
| App Name | Car Dealer Tracker |
| Visual Style | Premium minimalist, iOS-native, glassmorphism accents |
| Design Language | Clean, spacious, card-based layout with subtle depth |
| Dark Mode | True black (`#000000`) base — OLED optimized |
| Light Mode | Warm gray-white (`#F5F5FA`) base |
| Platforms | iOS (SwiftUI), Android (Compose/Material3) |

---

## 2. Color Palette

### 2.1 Primary Brand Colors

| Token | Light Mode | Dark Mode | Usage |
|---|---|---|---|
| `primary` | `rgb(23, 71, 140)` / `#17478C` | `rgb(71, 133, 230)` / `#4785E6` | Primary actions, selected states, links, key UI accents |
| `secondary` | `rgb(46, 133, 235)` / `#2E85EB` | same | Secondary buttons, highlights |
| `accent` | `rgb(250, 140, 56)` / `#FA8C38` | same | Warm contrast accent, edit actions, attention |
| `dealerGreen` | `rgb(0, 210, 106)` / `#00D26A` | same | Expenses UI specific green |
| `purple` | `rgb(133, 110, 242)` / `#856EF2` | same | Employee category, under_service status, invitations |

### 2.2 Status / Semantic Colors

| Token | Value (RGB) | Hex | Usage |
|---|---|---|---|
| `success` | `rgb(41, 171, 99)` / `#29AB63` | Green | Positive results, sold, synced, active |
| `warning` | `rgb(255, 209, 66)` / `#FFD142` | Yellow | Caution, holding cost alerts, in_transit |
| `danger` | `rgb(230, 51, 66)` / `#E63342` | Red | Errors, destructive actions, losses, under_service |

### 2.3 Background Colors

| Token | Light Mode | Dark Mode |
|---|---|---|
| `background` | `rgb(245, 245, 250)` / `#F5F5FA` | `#000000` (true black) |
| `secondaryBackground` | `#FFFFFF` | `rgb(20, 20, 20)` / `#141414` |
| `cardBackground` | `#FFFFFF` | `rgb(31, 31, 31)` / `#1F1F1F` |

### 2.4 Text Colors

| Token | Value | Usage |
|---|---|---|
| `primaryText` | `Color.primary` (system) | Main text, titles, amounts |
| `secondaryText` | `Color.secondary` (system) | Subtitles, descriptions, labels |
| `tertiaryText` | `UIColor.tertiaryLabel` (system) | Hints, placeholders, disabled text |

### 2.5 Dashboard-Specific Palette

Used exclusively in `DashboardView` and `DashboardComponents`:

| Token | Value | Usage |
|---|---|---|
| `cash` | `rgb(51, 191, 140)` / `#33BF8C` | Cash account cards |
| `bank` | `rgb(64, 115, 230)` / `#4073E6` | Bank account cards |
| `credit` | `rgb(242, 140, 64)` / `#F28C40` | Credit card account cards |
| `assets` | `rgb(31, 61, 99)` / `#1F3D63` | Inventory/assets |
| `sold` | `rgb(64, 107, 140)` / `#406B8C` | Sold vehicles |
| `revenue` | `rgb(38, 64, 102)` / `#264066` | Revenue card |
| `profit` | `rgb(46, 122, 87)` / `#2E7A57` | Profit (positive) |
| `loss` | `rgb(163, 71, 77)` / `#A3474D` | Profit (negative/loss) |

### 2.6 Vehicle Status Colors

| Status | Color | Hex |
|---|---|---|
| `on_sale` / `available` | Blue | `rgb(0, 122, 204)` / `#007ACC` |
| `reserved` | Blue | `rgb(0, 122, 204)` |
| `sold` | Green (success) | `#29AB63` |
| `in_transit` | Yellow (warning) | `#FFD142` |
| `under_service` | Purple | `rgb(153, 102, 204)` / `#9966CC` |

### 2.7 Expense Category Colors

| Category | Color |
|---|---|
| `vehicle` | `primary` (navy/blue) |
| `personal` | `accent` (warm orange) |
| `employee` | purple (`rgb(153, 102, 204)`) |

### 2.8 Paywall / Premium Gradient

| Name | Colors | Direction |
|---|---|---|
| Paywall Header | `#4A00E0` → `#8E2DE2` | topLeading → bottomTrailing |
| CTA Button | `#4A00E0` → `#8E2DE2` | leading → trailing |
| Premium Assets | `rgb(64,89,242)` → `rgb(115,38,217)` | topLeading → bottomTrailing |
| Premium Profit | `rgb(38,191,115)` → `rgb(0,128,77)` | topLeading → bottomTrailing |

### 2.9 Tab Bar Colors

| Tab | Color |
|---|---|
| Dashboard | `.blue` |
| Expenses | `.red` |
| Vehicles | `.purple` |
| Parts | `.orange` |
| Sales | `.green` |
| Clients | `.indigo` |

---

## 3. Typography

The app uses **system font** (San Francisco on iOS, Roboto on Android) exclusively.

### 3.1 Type Scale

| Role | Font | Weight | Size | Usage |
|---|---|---|---|---|
| Page Title | `.title` | `.heavy` | ~28pt | Dashboard title, main headers |
| Section Title | `.title3` | `.bold` | ~20pt | Section headers ("Account Balances") |
| Card Headline | `.headline` | `.bold` | ~17pt | Card primary values, list item titles |
| Subheadline | `.subheadline` | `.regular` / `.semibold` | ~15pt | Descriptions, secondary labels |
| Body | `.body` | `.regular` / `.semibold` | ~17pt | Menu row text, form fields |
| Caption | `.caption` | `.medium` | ~12pt | Timestamps, metadata, badges |
| Caption2 | `.caption2` | `.medium` / `.bold` | ~11pt | VIN numbers, tracking labels, micro-badges |
| Footnote | `.footnote` | `.regular` / `.semibold` | ~13pt | Legal text, stat details |

### 3.2 Number Display

| Context | Design | Font |
|---|---|---|
| Hero Amounts | `.system(size: 32, weight: .bold, design: .rounded)` | Rounded variant |
| Card Amounts | `.system(size: 17–20, weight: .bold, design: .rounded)` | Rounded variant |
| Small Values | `.headline` / `.subheadline` with `.weight(.bold)` | Default |
| Monospaced Data | `.monospacedDigit()` modifier | For VINs, IDs |

### 3.3 Text Patterns

- **Labels**: `.caption.weight(.medium)`, color: `secondaryText`
- **Section Headers**: `.caption`, `.fontWeight(.bold)`, `.textCase(.uppercase)`, color: `secondaryText`
- **Tracking/Letter Spacing**: Use `.tracking(0.5)` – `2` only on uppercase labels
- **Line Limits**: Always set `.lineLimit(1)` with `.minimumScaleFactor(0.5–0.8)` on amounts

---

## 4. Spacing & Layout

### 4.1 Spacing Scale

| Token | Value | Usage |
|---|---|---|
| `xs` | 4pt | Tight spacing between sub-elements |
| `sm` | 8pt | Between icon and text in badges |
| `md` | 12pt | Card internal spacing, vertical gaps |
| `lg` | 16pt | Card padding, section gaps |
| `xl` | 20pt | Screen horizontal padding, section spacing |
| `2xl` | 24pt | Major section separators, card internal padding |

### 4.2 Screen-Level Layout

| Property | Value |
|---|---|
| Horizontal Padding | `20pt` (consistent across all screens) |
| Vertical Section Spacing | `24pt` between major sections |
| List Row Insets | `EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20)` |
| iPad Max Width | `700pt` (content constrained) |

---

## 5. Corner Radii

| Component | Radius | Style |
|---|---|---|
| Cards (primary) | `20pt` | `.continuous` |
| Cards (summary/overview) | `24pt` | `.continuous` |
| Cards (small/balance) | `16–17pt` | `.continuous` |
| Cards (vehicle) | `14pt` | `.continuous` |
| Menu/Settings Rows | `16pt` | default |
| Buttons (pill/capsule) | `Capsule()` | natural |
| Buttons (standard) | `24pt` | default |
| Badges (status) | `8pt` | default |
| Icon Circles | `Circle()` | natural |
| Icon Rounded Squares | `12pt` | `.continuous` |
| Search Fields | `10pt` | default |
| Thumbnails | `10pt` | `.continuous` |

---

## 6. Shadows

| Usage | Color | Radius | Offset |
|---|---|---|---|
| Cards (standard) | `black 4%` | `8pt` | `y: 4` |
| Cards (outline) | `black 3–4%` | `4–5pt` | `y: 2` |
| Settings Cards | `black 3%` | `5pt` | `y: 2` |
| Elevated Cards | `black 6%` | `10pt` | `y: 5` |
| Tab Bar | `black 15%` | `20pt` | `y: 10` |
| Performance Card (dark) | `black 15%` | `8pt` | `y: 4` |
| Primary Button Glow | `primary 40%` | `4pt` | `y: 2` |
| Icon Circle Glow | `color 32%` | `5pt` | `y: 2` |

---

## 7. Borders & Overlays

| Usage | Style |
|---|---|
| Card Border (dark mode) | `LinearGradient` glass border: `white 40%` → `white 0%` → `white 10%` (glossy) |
| Card Border (light mode) | `black 4%` → `black 8%` top-to-bottom subtle gradient |
| Outline cards | `gray 6%` stroke, `1pt` width |
| Selected Card Border | `primary` stroke, `2pt` width |
| Search/filter border | `gray 20%` stroke, `1pt` width |
| Top bar circle buttons | `white` stroke, `1.5pt` width |
| Status badge border | `statusColor 30%` stroke, `1pt` width |

---

## 8. Materials & Effects

| Effect | Implementation | Usage |
|---|---|---|
| Glassmorphism | `.ultraThinMaterial` | Tab bar, top navigation bar, sync HUD |
| Tab Bar Glass | `Capsule().fill(.ultraThinMaterial)` + `white 20%` stroke | Custom tab bar |
| Bottom Fade | `LinearGradient(background 0% → 85% → 100%)` height `80pt` | Bottom content fade |
| Card Modifier | `cardBackground` + `cornerRadius(20)` + glass border + shadow | Reusable `.cardStyle()` |

---

## 9. Component Patterns

### 9.1 Cards

```
┌────────────────────────────────┐
│  ● Icon (circle bg, 12% tint) │
│                                │
│  Label (caption, secondary)    │
│  Amount (headline, bold)       │
│                                │
└────────────────────────────────┘
  background: cardBackground
  radius: 20pt continuous
  shadow: black 4%, radius 8, y 4
  border: gray 6%, 1pt
```

### 9.2 Menu/Settings Row

```
┌─────────────────────────────────────┐
│  [●] Icon    Title          [>]     │
│  (circle)    Subtitle               │
│  36×36       (caption, secondary)   │
│  color 10%                          │
└─────────────────────────────────────┘
  Icon: 36×36 circle, color.opacity(0.1), image 16pt weight .semibold
  Padding: 16pt all sides
  Dividers: padded .leading 52pt
```

### 9.3 Status Badges

```
┌──────────────┐
│  Status Text │
└──────────────┘
  font: system 10pt bold
  foreground: statusColor
  background: statusColor 15%
  border: statusColor 30%, 1pt
  padding: h8 v4
  radius: 8pt
```

### 9.4 Filter Chips

```
 ┌─────────────┐
 │  Chip Text  │
 └─────────────┘
  Selected: bg=primary, text=white, shadow=primary 30%
  Unselected: bg=background, text=secondaryText, border=gray 20%
  radius: 20pt (capsule-like)
  padding: h16 v8
```

### 9.5 Trend Badge

```
 ┌───────────┐
 │ ↗ 12.5%   │
 └───────────┘
  Up: success color with success 10% bg
  Down: danger color with danger 10% bg
  font: caption2 semibold
  bg: secondaryBackground
  shape: Capsule
  padding: h8 v4
```

### 9.6 Performance Card (Dark)

```
┌────────────────────────────────┐
│  Label (caption, white 70%)  ○ │
│  Amount (20pt bold, white)     │
│  ~~~ Sparkline Chart ~~~       │
└────────────────────────────────┘
  background: LinearGradient dark navy
    from: rgb(26, 38, 64) / #1A2640
    to: rgb(13, 20, 38) / #0D1426
  radius: 16pt continuous
  shadow: black 15%
```

---

## 10. Animations

| Animation | Implementation | Usage |
|---|---|---|
| Primary Transition | `.snappy(duration: 0.28, extraBounce: 0.04)` | Tab switches, state changes |
| Spring Entrance | `.spring(response: 0.8, dampingFraction: 0.8).delay(0.1)` | Paywall content entrance |
| Button Scale (Haptic) | `scaleEffect(0.96)` + `opacity(0.9)` + `.snappy(0.18, bounce 0.02)` | All interactive cards |
| Selection Spring | `.spring(response: 0.3, dampingFraction: 0.6–0.7)` | Plan cards, filter selection |
| Sync Spinner | `.linear(duration: 1.0).repeatForever(autoreverses: false)` | Rotation syncing icon |
| Toast Entry | `.move(edge: .bottom).combined(with: .opacity)` | Error/success toasts |
| HUD Entry (modal) | `.opacity.combined(with: .scale(scale: 0.96))` | Full-screen sync HUD |
| HUD Entry (compact) | `.move(edge: .bottom).combined(with: .opacity)` | Bottom bar sync HUD |
| General ease | `.easeInOut` | Status banners |

---

## 11. Iconography

- **Icon Library**: SF Symbols (iOS), Material Icons (Android)
- **Icon Weights**: `.medium` for nav, `.semibold` for cards, `.bold` for primary actions
- **Icon Sizes**:
  - Tab bar: `22pt`
  - Card icons: `16–18pt`
  - Navigation actions: `15pt`
  - Large decorative: `24–28pt`
  - Empty state: `48–80pt`
- **Icon Containers**: Circle with `color.opacity(0.1–0.12)`, sizes: `32–44pt`

### Key Icon Mappings

| Feature | Icon |
|---|---|
| Dashboard | `house.fill` |
| Expenses | `creditcard` |
| Vehicles | `car.fill` |
| Parts | `shippingbox` |
| Sales | `dollarsign.circle.fill` |
| Clients | `person.2` |
| Search | `magnifyingglass` |
| Profile | `person.crop.circle` |
| Add | `plus` / `plus.circle.fill` |
| Sync | `arrow.clockwise` / `arrow.triangle.2.circlepath` |
| Settings | `globe`, `bell.badge.fill`, `lock.rotation` |
| Cash | `banknote.fill` |
| Bank | `building.columns.fill` |
| Credit | `creditcard.fill` |

---

## 12. Button Styles

### Primary Action Button
```
Text: headline bold, white
Background: primary (or LinearGradient primary)
Padding: h32 v14
Radius: 24pt
Shadow: primary 30–40%, radius 4, y 2
```

### Haptic Scale Button (`.buttonStyle(.hapticScale)`)
```
scaleEffect: 0.96 on press
opacity: 0.9 on press
animation: .snappy(0.18, extraBounce: 0.02)
Usage: All card-level interactive elements
```

### Capsule Link Button
```
Text: caption/subheadline semibold, primary color
Background: secondaryBackground
Border: primary 15%, 1pt, capsule
Padding: h10 v6
```

### Destructive Button
```
foregroundColor: .red
Background: cardBackground
Radius: 16pt
Shadow: black 5%, radius 5, y 2
```

---

## 13. Form & Input Patterns

| Element | Style |
|---|---|
| Text Fields | `.textFieldStyle(.plain)` inside container |
| Search Bar | HStack with magnifying glass icon, `background(background)`, `cornerRadius(10)`, gray 20% border |
| Pickers | `.pickerStyle(.segmented)` for mode toggles |
| Toggles | `SwitchToggleStyle(tint: .orange)` |
| Steppers | `.labelsHidden()` with manual label |
| Date Pickers | standard SwiftUI `DatePicker` |

---

## 14. Navigation Patterns

| Pattern | Implementation |
|---|---|
| Custom Tab Bar | Floating capsule with `ultraThinMaterial`, 6 tabs |
| Navigation | `NavigationStack` with programmatic `path` |
| Sheets | `.presentationDetents([.medium, .large])` / `[.large]` |
| Close Button | `xmark.circle.fill`, gray, 24pt, top-right |
| Back Navigation | System default (no custom) |

---

## 15. Localization

| Platform | Method |
|---|---|
| iOS | `"key".localizedString` extension via `RegionSettingsManager` |
| Android | Standard `stringResource` with separate `values` folders |
| Section titles in code | `LocalizedStringKey` with `.localizedKey` |

---

## 16. Platform-Specific Notes

### iOS (SwiftUI)
- Use `ColorTheme.xxx` for all colors — never hardcode hex inline
- Use `.cardStyle()` modifier for standard elevated cards
- Use `.buttonStyle(.hapticScale)` for interactive cards
- All amounts must use `.asCurrency()` / `.asCurrencyCompact()` extensions
- Large amounts use `.design(.rounded)` font variant
- Use `UIDevice.current.userInterfaceIdiom == .pad` for iPad adaptation
- Set `.minimumScaleFactor(0.5–0.8)` + `.lineLimit(1)` on all currency displays

### Android (Compose / Material3)
- Mirror `ColorTheme` values in Compose theme
- Use `MaterialTheme.colorScheme` and `MaterialTheme.typography`
- Match corner radii and shadow depths from iOS
- Use `BigDecimal` for monetary values
- Apply same spacing scale (4, 8, 12, 16, 20, 24)

---

## 17. Do's and Don'ts

### ✅ DO
- Use `ColorTheme.xxx` tokens for all colors
- Use `.cardStyle()` for elevated card backgrounds
- Apply `.buttonStyle(.hapticScale)` to interactive cards
- Use `.continuous` corner style for cards
- Support both light and dark mode
- Use `RoundedRectangle(cornerRadius: X, style: .continuous)` for clip shapes
- Add subtle `gray 6%` overlay stroke on cards
- Use `.snappy` animation for UI state transitions
- Add haptic feedback on interactive elements

### ❌ DON'T
- Hardcode hex/RGB values directly in views — use `ColorTheme`
- Use sharp corners on cards (always `>=10pt` radius)
- Use heavy shadows (`>10%` opacity for standard cards)
- Mix font design variants (use `.rounded` only for numbers)
- Use system `TabView` appearance — it's hidden, custom tab bar is used
- Forget `.minimumScaleFactor` on price/amount labels
- Use inconsistent horizontal padding (stick to `20pt`)
- Add comments in code unless explicitly asked
