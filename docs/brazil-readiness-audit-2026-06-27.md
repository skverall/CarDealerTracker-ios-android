# Brazil Readiness Audit - iOS - 2026-06-27

Scope: iOS app localization, iOS App Store presence, website copy, screenshot assets, and pricing documentation. Backend, Supabase, sync, RLS, Android, and financial calculations were not modified or audited for behavior.

## Summary

- `pt-BR` exists in the iOS project `knownRegions`, `Localizable.xcstrings`, and `InfoPlist.xcstrings`.
- Brazil exists in iOS region settings with `BRL`, `R$`, and `pt_BR`; Portuguese (Brazil) is selectable in the in-app language picker.
- `Localizable.xcstrings` has `1,606 / 1,608` keys with `pt-BR` entries. `InfoPlist.xcstrings` has `4 / 4`.
- The requested iOS surfaces had `346` extracted localized string literals; `4` are missing catalog entries and will fall back to their English/raw source text.
- `PaywallView.swift` had `53` extracted localized string literals; `0` are missing `pt-BR` values. I did not find a paywall-specific raw localization key fallback.
- Local website and screenshot assets do not have a dedicated `pt-BR` variant. The live Brazil App Store page does have Portuguese title/subtitle/description and Portuguese recent release notes, but local repo assets are not complete for Brazil.
- Pricing documentation is stale or contradictory if the intended source of truth is `$9.99/month` and `$99.99/year`. One iOS pricing doc still describes future `$14.99/month` and `$119.99/year` pricing. The public US App Store page checked during this audit showed `$19.99/month` and `$119.99/year`, so pricing should be verified in App Store Connect/RevenueCat before patching docs.

## Missing Strings

### Global Catalog Gaps

These two `Localizable.xcstrings` keys have no `pt-BR` localization:

| Key | Risk |
| --- | --- |
| `%@. %@` | Low. Generic format key; verify call sites before translating. |
| `G` | Low. Google button/logo glyph candidate; probably should remain as-is or be excluded from localization. |

### Requested iOS Surface Gaps

These strings are used with `.localizedString` on requested settings/maintenance surfaces but are not present in `Localizable.xcstrings`, so Portuguese users will see the English source text:

| File | Line | Missing key/source text | Surface |
| --- | ---: | --- | --- |
| `iOS Car Dealer Tracker/Ezcar24Business/Views/DataHealthView.swift` | 61 | `Maintenance` | Settings / Sync & Maintenance |
| `iOS Car Dealer Tracker/Ezcar24Business/Views/DataHealthView.swift` | 65 | `Sync your data with the cloud or clean up duplicate records.` | Settings / Sync & Maintenance |
| `iOS Car Dealer Tracker/Ezcar24Business/Views/DataHealthView.swift` | 75 | `Syncing...` | Settings / Sync & Maintenance |
| `iOS Car Dealer Tracker/Ezcar24Business/Views/BackupCenterView.swift` | 51 | `Schedule automatic monthly report emails.` | Settings / Reports |

No missing `pt-BR` values were found in the extracted localized literals for `PaywallView.swift`, `LoginView.swift`, `AuthGateView.swift`, `RegionSelectionView.swift`, `AddVehicleView.swift`, or `DashboardView.swift`.

## Paywall Raw-Key Check

I did not find paywall keys falling back to raw localization keys:

- `PaywallView.swift`: `53` localized literals extracted, `0` missing from `pt-BR`.
- Dynamic paywall keys such as `paywall_upgrade_title`, `paywall_upgrade_subtitle`, `paywall_trial_cta`, `paywall_renews_yearly`, `paywall_yearly_savings_badge`, `Restore Purchases`, `Restoring...`, `Monthly`, `Yearly`, and `Billed yearly` all have `pt-BR` catalog values.
- The RevenueCat price text itself is StoreKit-provided (`localizedPriceString`), not a local string key.

Translation-quality risks still exist even when values are present:

| Key | Current `pt-BR` value | Risk |
| --- | --- | --- |
| `SUBSCRIPTION DETAILS` | `ASSINATURA DETAILS` | Mixed Portuguese/English; should be `Detalhes da assinatura`. |
| `paywall_ai_title_prefix` | `Desbloquear AI` | Uses English `AI`; pt-BR app copy elsewhere uses `IA`. |
| `paywall_yearly_savings_badge` | `Salvar %d%%` | Literal translation; Brazilian product copy should likely be `Economize %d%%`. |
| `Edit Profile` | `Editar arquivo Pro` | Wrong meaning on a settings/profile surface. |
| `feedback_status_in_progress` / `in_progress` | `Em Progress` | Mixed Portuguese/English. |

## App Store, Website, And Screenshot Assets

### App Store

Live public pages checked:

- Brazil: `https://apps.apple.com/br/app/car-dealer-tracker/id6755675367`
- United States: `https://apps.apple.com/us/app/car-dealer-tracker/id6755675367`

Findings:

- Brazil listing redirects to `Car Dealer Tracker Revendas` and has Portuguese subtitle/copy.
- Brazil listing reports Portuguese as an app language and shows Portuguese recent version notes for `2.1.23` and `2.1.22`.
- Older version history entries on the Brazil page still include English copy.
- Repo release doc `docs/app-store-release-2.1.27-build17-2026-06-26.md` says App Store Connect had `pt-BR` What's New for release `2.1.27`, but that version was `WAITING_FOR_REVIEW` in the doc and the live public page showed `2.1.23` during this audit.
- No dedicated local Portuguese App Store copy file was found. Existing local copy files/docs are language-specific for Japanese, Arabic, Hindi, Russian, and release notes, not a complete Brazil metadata pack.

### Website

Local website files are English-only:

- `website/index.html` uses `<html lang="en">`.
- Website metadata, JSON-LD, FAQ, CTA copy, image alt text, `website/sitemap.xml` image titles, and `website/assets/og-image.svg` text are English.
- No `pt-BR`, `pt_BR`, `Português`, `Brazil`, or `Brasil` website variant was found.

### Screenshot Assets

Local screenshot directories found:

- `app-store-screenshots-ar/public/screenshots/apple/iphone/ar`
- `app-store-screenshots-ar/public/screenshots/apple/iphone/en`
- `app-store-screenshots-ja/public/screenshots/apple/iphone/ja`
- `app-store-screenshots-ja/public/screenshots/apple/iphone/ru`
- `app-store-screenshots-ja/public/screenshots/apple/iphone/en`
- `app-store-screenshots-en-ipad/public/screenshots/apple/ipad/en`
- `Screenshots Languages/English Screenshots`
- `Screenshots Languages/Russian Screenshots`
- `Screenshots Languages/JAPAN SCREENSHOTS`

No local `pt`, `pt-BR`, `pt_BR`, `Portuguese`, `Brasil`, or `Brazil` screenshot asset folder was found.

## Pricing Docs

Stale/contradictory files:

| File | Current content | Risk |
| --- | --- | --- |
| `docs/ios-subscription-trial-pricing-2026-05-30.md` | Says new subscribers were scheduled for `$14.99/month` and `$119.99/year` from `2026-06-01`, while preserved current rows were `$9.99/month` and `$99.99/year`. | Stale if the intended current pricing is `$9.99/month` and `$99.99/year`. |
| `docs/google-play-release.md` | Mentions Android `$14.99/month` and `$119.99/year`. | Android/out of iOS scope, but still contradicts the stated current pricing if used as shared pricing reference. |

Live public US App Store check on 2026-06-27 showed in-app purchase rows for `EzCar24 Dealer Pro Monthly $19.99` and `EzCar24 Dealer Pro Yearly $119.99`. That conflicts with the stated `$9.99/month` and `$99.99/year` target. Treat pricing docs as unsafe to patch until App Store Connect and RevenueCat are checked as the billing source of truth.

## Risky Files

| File | Why risky | Safe handling |
| --- | --- | --- |
| `iOS Car Dealer Tracker/Ezcar24Business/Localizable.xcstrings` | Large shared iOS catalog; missing settings strings and several low-quality Portuguese values. | Additive string-only patch; validate JSON with `jq empty`; do not touch unrelated languages except where necessary. |
| `iOS Car Dealer Tracker/Ezcar24Business/InfoPlist.xcstrings` | Public permission prompts and app display metadata. | Already has `pt-BR`; only copy review if needed. |
| `iOS Car Dealer Tracker/Ezcar24Business/Utilities/RegionSettings.swift` | Region/language source of truth. | No code change needed for Brazil readiness based on this audit. |
| `iOS Car Dealer Tracker/Ezcar24Business/Views/PaywallView.swift` | Monetization UI; bad copy can hurt conversion and compliance. | No code change needed for raw-key fallback; only string-catalog copy fixes. |
| `iOS Car Dealer Tracker/Ezcar24Business/Views/DataHealthView.swift` | Settings strings currently missing from catalog. | Do not edit view code; add missing source keys to catalog. |
| `iOS Car Dealer Tracker/Ezcar24Business/Views/BackupCenterView.swift` | Settings/report subtitle currently missing from catalog. | Do not edit view code; add missing source key to catalog. |
| `website/index.html`, `website/sitemap.xml`, `website/assets/og-image.svg` | English-only public marketing/SEO copy. | Add a deliberate `pt-BR` website strategy instead of one-off replacing English. |
| `app-store-screenshots-*` and `Screenshots Languages/*` | No Brazilian Portuguese screenshot set. | Create separate `pt-BR` screenshot project/export folders; do not overwrite existing locale assets. |
| `docs/ios-subscription-trial-pricing-2026-05-30.md` | Pricing source is stale/contradictory. | Verify live billing first, then replace with a current pricing note. |

## Safe Patch Plan

1. Add the four missing settings strings to `Localizable.xcstrings` with `pt-BR` values and preserve existing source keys:
   - `Maintenance` -> `Manutenção`
   - `Sync your data with the cloud or clean up duplicate records.` -> `Sincronize seus dados com a nuvem ou limpe registros duplicados.`
   - `Syncing...` -> `Sincronizando...`
   - `Schedule automatic monthly report emails.` -> `Agende e-mails automáticos com relatórios mensais.`
2. Fix Portuguese quality issues in `Localizable.xcstrings` without touching app logic:
   - `SUBSCRIPTION DETAILS` -> `Detalhes da assinatura`
   - `paywall_ai_title_prefix` -> `Desbloquear IA`
   - `paywall_yearly_savings_badge` -> `Economize %d%%`
   - `Edit Profile` -> `Editar perfil`
   - `feedback_status_in_progress` / `in_progress` -> `Em andamento`
3. Re-run the localized-literal comparison for requested surfaces and paywall.
4. Verify the billing source of truth in App Store Connect and RevenueCat before editing pricing docs. If `$9.99/month` and `$99.99/year` are confirmed current, update `docs/ios-subscription-trial-pricing-2026-05-30.md` to mark the `$14.99/$119.99` plan as obsolete/canceled or historical.
5. Create a separate Brazil storefront asset pack:
   - App Store metadata copy file for `pt-BR`.
   - iPhone and iPad screenshot JSON/assets under dedicated `pt-BR` folders.
   - Website plan: either a `/pt-BR/` localized page or explicit decision to keep website English-only.
6. Validate locally; do not touch backend, Supabase, sync, RLS, or financial calculation files.

## Commands To Validate

```bash
jq empty "iOS Car Dealer Tracker/Ezcar24Business/Localizable.xcstrings"
jq empty "iOS Car Dealer Tracker/Ezcar24Business/InfoPlist.xcstrings"
```

```bash
jq -r '.strings | to_entries[] | select((.value.localizations["pt-BR"]? // null) == null) | .key' \
  "iOS Car Dealer Tracker/Ezcar24Business/Localizable.xcstrings"
```

```bash
rg --no-filename -o '"([^"\\]|\\.)+"\.(localizedString|localizedKey)' \
  "iOS Car Dealer Tracker/Ezcar24Business/Views/PaywallView.swift" \
  "iOS Car Dealer Tracker/Ezcar24Business/Auth/LoginView.swift" \
  "iOS Car Dealer Tracker/Ezcar24Business/Auth/AuthGateView.swift" \
  "iOS Car Dealer Tracker/Ezcar24Business/Views/RegionSelectionView.swift" \
  "iOS Car Dealer Tracker/Ezcar24Business/Views/AddVehicleView.swift" \
  "iOS Car Dealer Tracker/Ezcar24Business/Views/DashboardView.swift" \
  "iOS Car Dealer Tracker/Ezcar24Business/Views/AccountView.swift" \
  "iOS Car Dealer Tracker/Ezcar24Business/Views/Settings/HoldingCostSettingsView.swift" \
  "iOS Car Dealer Tracker/Ezcar24Business/Views/MonthlyReportSettingsView.swift" \
  "iOS Car Dealer Tracker/Ezcar24Business/Views/DataHealthView.swift" \
  "iOS Car Dealer Tracker/Ezcar24Business/Views/BackupCenterView.swift" \
  | sed -E 's/^"(.*)"\.localized.*/\1/' | sort -u > /tmp/ios_surface_keys.txt

jq -r '.strings | to_entries[] | select(.value.localizations["pt-BR"]? != null) | .key' \
  "iOS Car Dealer Tracker/Ezcar24Business/Localizable.xcstrings" | sort -u > /tmp/ios_ptbr_keys.txt

comm -23 /tmp/ios_surface_keys.txt /tmp/ios_ptbr_keys.txt
```

```bash
rg --no-filename -o '"([^"\\]|\\.)+"\.localizedString' \
  "iOS Car Dealer Tracker/Ezcar24Business/Views/PaywallView.swift" \
  | sed -E 's/^"(.*)"\.localizedString/\1/' | sort -u > /tmp/paywall_keys.txt

comm -23 /tmp/paywall_keys.txt /tmp/ios_ptbr_keys.txt
```

```bash
find app-store-screenshots-ar app-store-screenshots-ja app-store-screenshots-en-ipad "Screenshots Languages" \
  -path '*/node_modules/*' -prune -o -path '*/.next/*' -prune -o -type d -print \
  | rg '/(en|ru|ar|ja|pt|pt-BR|id)$' | sort
```

```bash
rg -n "pt-BR|pt_BR|Português|Portuguese|Brazil|Brasil|BRL|R\\$|9\\.99|99\\.99|14\\.99|119\\.99|19\\.99|\\$[0-9]" \
  docs website app-store-screenshots-ar app-store-screenshots-ja app-store-screenshots-en-ipad \
  -g '!**/node_modules/**' -g '!**/.next/**' -g '!**/*.png' -g '!**/*.jpg' -g '!**/*.jpeg' \
  -g '!**/*.zip' -g '!**/pnpm-lock.yaml' -g '!**/package-lock.json' -g '!**/bun.lock'
```

```bash
xcodebuild -project "iOS Car Dealer Tracker/Ezcar24Business.xcodeproj" \
  -scheme Ezcar24Business \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build

git diff --check
```
