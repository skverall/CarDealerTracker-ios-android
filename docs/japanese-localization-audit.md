# Japanese Localization Audit

Date: 2026-05-19

## Scope

- Repository contains iOS, Android, and Supabase code.
- Backend schema, migrations, RLS, RPCs, and Edge Functions were not modified.
- Public app name is kept as `Car Dealer Tracker` in user-facing app name strings.

## Localization Systems Detected

- iOS: Apple String Catalog at `iOS Car Dealer Tracker/Ezcar24Business/Localizable.xcstrings`, plus a custom `String.localizedString` wrapper using `RegionSettingsManager.selectedLanguage`.
- Android: Android resources exist, but prior to this work `strings.xml` only contained `app_name`; most Compose UI strings remain hard-coded in Kotlin.
- Shared localization generator: none detected.

## Pre-change Coverage

- iOS string catalog keys: 1105.
- iOS languages before changes: `en`, `ru`.
- Pre-change localized value counts from audit: `en` 974, `ru` 969, `ja` 0.
- Android localized resource strings before changes: `values/strings.xml` only (`app_name`). No `values-ru` or `values-ja` directory existed.

## Post-change iOS Coverage

- iOS string catalog keys after changes: 1200.
- Locales present after changes: en, ja, ru.
- Localized value counts: {'en': 1200, 'ja': 1200, 'ru': 1200}.
- Missing/empty localized values, excluding the intentional empty string key: {'en': 0, 'ja': 0, 'ru': 0}.
- Placeholder mismatches found by static audit: 0.
- SwiftUI literal audit: 780 obvious `Text`/`Button`/`Label`/`TextField`/`SecureField`/`Picker`/`Toggle`/`navigationTitle` string literals, 780 catalog-covered.
- Dynamic iOS display helpers now use localized fallback strings for financial account kinds, expense category fallback labels, debt badges, transaction types, inventory health labels, paywall chips, local notification titles, auth/invite toasts, diagnostics errors, holding-cost validation, and sale/export error messages.
- Full key map: `docs/japanese-localization-coverage.csv`.
- Android resource coverage map: `docs/android-japanese-localization-coverage.csv`.

## Japan Market Adaptation Review

- Language option added as `日本語` with locale key `ja`.
- Japan region already uses `JPY`, `¥`, `ja_JP`, kilometers, and zero currency decimals; formatting was adjusted so Japanese yen does not render with a space after `¥`.
- Japanese expense quick-add UX now prioritizes dealer workflows: auction fee, inspection/shaken, repair, transport, parking, warranty, insurance, and registration/plate.
- Deal Desk generic settings now seed Japan-safe defaults when the selected app region is Japan without introducing a new synced remote enum: consumption tax at 10%, plus registration/plate and inspection/shaken fee rows at 0 fixed amount.
- Vehicle category terms were added to localization resources: new car, used car, and kei car. No persisted vehicle category field was added because that would require data model/backend compatibility review.

## Android Status

- Added `values-ja/strings.xml` and expanded Android `values/strings.xml` from `app_name` only to 430 aligned string resources in English and Japanese.
- Added `AppLanguage.JAPANESE`, Japan yen formatting without a post-symbol space, and tests for Japan enum settings.
- Added `AndroidLocalization.kt`, a local source-string lookup helper used by Compose, Context-based flows, exported PDF labels, notification titles, toasts, chooser labels, status messages, permission labels, and inventory alert templates.
- Static audit now finds 292 `localizedUiString("...")` literal sources and all 292 have English and Japanese resources. The remaining obvious `Text("...")` scan hits are dealer data, counters, notification payload values, or non-visible clipboard labels rather than fixed UI copy.
- Android verification requires local environment overrides because default `java` is not configured and `local.properties` points to `/Users/aydmaxx/Library/Android/sdk`. A gitignored dummy `app/google-services.json` was temporarily created only for local compile/test and removed after verification.

## Verification Results

- `python3 -m json.tool iOS Car Dealer Tracker/Ezcar24Business/Localizable.xcstrings`: passed.
- iOS string catalog placeholder/value audit: passed, 1200 keys, 0 missing values for `en`, `ru`, or `ja`, 0 placeholder mismatches.
- iOS SwiftUI literal coverage audit: passed, 780 inspected, 0 missing catalog keys.
- `xmllint --noout Android Car Dealer Tracker/app/src/main/res/values/strings.xml Android Car Dealer Tracker/app/src/main/res/values-ja/strings.xml`: passed.
- `xcodebuild test -project iOS Car Dealer Tracker/Ezcar24Business.xcodeproj -scheme Ezcar24Business -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcode-derived -disablePackageRepositoryCache -packageCachePath .build/xcode-package-cache -clonedSourcePackagesDirPath .build/xcode-source-packages`: passed with `** TEST SUCCEEDED **`.
- `./gradlew test`: blocked by missing Java in the default shell.
- `JAVA_HOME=/opt/homebrew/opt/openjdk@17 ANDROID_HOME=/opt/homebrew/share/android-commandlinetools ANDROID_SDK_ROOT=/opt/homebrew/share/android-commandlinetools ./gradlew :app:compileDebugKotlin`: passed with a temporary gitignored dummy `app/google-services.json`.
- `JAVA_HOME=/opt/homebrew/opt/openjdk@17 ANDROID_HOME=/opt/homebrew/share/android-commandlinetools ANDROID_SDK_ROOT=/opt/homebrew/share/android-commandlinetools ./gradlew test`: passed with the same temporary local dummy `app/google-services.json`.

## Static Audit Notes

- Source references and adaptation flags are recorded in `docs/japanese-localization-coverage.csv`.
- Remaining forbidden product-name hits are internal code symbols, bundle/model names, or non-user-facing header comments. User-facing UI references found during this pass were changed to `Car Dealer Tracker`.
- Strings needing owner review: subscription legal copy, tax/fee wording in Deal Desk, and whether Japan dealers need a persisted vehicle category field for new/used/kei.
