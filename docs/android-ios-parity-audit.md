# Android vs iOS Parity Audit

Date: 2026-06-29

Scope: Ezcar24Business iOS source of truth vs native Android Kotlin/Jetpack Compose app. iOS files were treated as the contract unless a clear iOS runtime bug was visible.

## Evidence and Environment

- Android debug build passed before audit: `cd "Android Car Dealer Tracker" && ./gradlew assembleDebug --console=plain` -> `BUILD SUCCESSFUL in 1m`.
- Android unit tests passed after fixes: `./gradlew testDebugUnitTest --console=plain` -> `BUILD SUCCESSFUL in 9s`.
- Android debug build passed after fixes: `./gradlew assembleDebug --console=plain` -> `BUILD SUCCESSFUL in 1s`.
- Android unit tests passed after the follow-up user-QA fixes: `./gradlew testDebugUnitTest --console=plain` -> `BUILD SUCCESSFUL in 2s`.
- Android debug build passed after the follow-up user-QA fixes: `./gradlew assembleDebug --console=plain` -> `BUILD SUCCESSFUL in 542ms`.
- Android install passed after fixes: `./gradlew :app:installDebug --console=plain` -> installed `app-debug.apk` on connected device `25078RA3EA - 15`.
- Android follow-up install and cold launch passed after the Hilt/localization crash fix: `./gradlew :app:installDebug --console=plain` -> `BUILD SUCCESSFUL in 24s`; `adb shell am start -W ...` -> `Status: ok`, `LaunchState: COLD`.
- Android crash buffer after the final follow-up launch was empty: `adb logcat -d -b crash | tail -n 80` -> no output.
- Android compile passed after the bottom-navigation follow-up: `./gradlew :app:compileDebugKotlin --console=plain` -> `BUILD SUCCESSFUL in 682ms`.
- Android bottom-navigation follow-up install passed: `./gradlew :app:installDebug --console=plain` -> `BUILD SUCCESSFUL in 23s`.
- Final Android unit tests passed: `./gradlew testDebugUnitTest --console=plain` -> `BUILD SUCCESSFUL in 3s`.
- Final Android debug build passed: `./gradlew assembleDebug --console=plain` -> `BUILD SUCCESSFUL in 682ms`.
- Final whitespace check passed: `git diff --check` -> no output.
- Final Android unit tests after Dashboard localization/fit passed: `./gradlew testDebugUnitTest --console=plain` -> `BUILD SUCCESSFUL in 3s`.
- Final Android debug build after Dashboard localization/fit passed: `./gradlew assembleDebug --console=plain` -> `BUILD SUCCESSFUL in 690ms`.
- Final Android crash buffer after Dashboard localization/fit launch was empty: `adb logcat -d -b crash | tail -n 80` -> no output.
- Final whitespace check after Dashboard localization/fit passed: `git diff --check` -> no output.
- Final Android unit tests after Region/Language follow-up passed: `./gradlew testDebugUnitTest --console=plain` -> `BUILD SUCCESSFUL in 4s`.
- Final Android debug build after Region/Language follow-up passed: `./gradlew assembleDebug --console=plain` -> `BUILD SUCCESSFUL in 747ms`.
- Final Android crash buffer after Region/Language follow-up launch was empty: `adb logcat -d -b crash | tail -n 80` -> no output.
- Final whitespace check after Region/Language follow-up passed: `git diff --check` -> no output.
- Final Android unit tests after Clients detail/edit follow-up passed: `./gradlew testDebugUnitTest --console=plain` -> `BUILD SUCCESSFUL in 4s`.
- Final Android debug build after Clients detail/edit follow-up passed: `./gradlew assembleDebug --console=plain` -> `BUILD SUCCESSFUL in 700ms`.
- Final Android install after Clients detail/edit follow-up passed: `adb install -r "app/build/outputs/apk/debug/app-debug.apk"` -> `Success`.
- Final Android crash buffer after Clients detail/edit follow-up was empty: `adb logcat -d -b crash | tail -n 80` -> no output.
- Final whitespace check after Clients detail/edit follow-up passed: `git diff --check` -> no output.
- Android emulator install passed after fixes: `adb -s emulator-5554 install -r app/build/outputs/apk/debug/app-debug.apk` -> `Success`.
- Android launched with `adb ... am start -n com.ezcar24.business.debug/com.ezcar24.business.MainActivity`.
- Android Room migration path was runtime-checked on the existing AVD database after the vehicle `inventoryId` and `purchaseAccountId` schema bumps: reinstall succeeded and the app reached Dashboard, confirming no schema-open crash on that test database.
- Android launch screenshot: `docs/parity-screenshots/android-launch-before.png`.
- iOS build/run passed through XcodeBuildMCP on iPhone 17 Pro simulator, scheme `Ezcar24Business`, app bundle `com.ezcar24.business`, DerivedData `/Volumes/LexarDev/Developer/Xcode/DerivedData/Ezcar24Business-parity-audit`.
- iOS simulator login succeeded with the existing review/demo account and loaded organization `Ezcar24 App Review Demo`.
- iOS authenticated dashboard screenshot: `docs/parity-screenshots/ios-dashboard-authenticated.jpg`.
- iOS dashboard plus menu screenshot: `docs/parity-screenshots/ios-dashboard-plus-menu.jpg`.
- iOS add-vehicle top screenshot: `docs/parity-screenshots/ios-add-vehicle-top.jpg`.
- A dedicated Android AVD was created on external storage at `/Volumes/LexarDev/Developer/SDKs/Android/avd/ezcar24_parity_pixel7_api35.avd` to avoid the locked physical Xiaomi/MIUI device blocking screenshots.
- Android authenticated dashboard screenshot after fixes: `docs/parity-screenshots/android-dashboard-authenticated-after.png`.
- Android dashboard car screenshot after fixes: `docs/parity-screenshots/android-dashboard-car-after.png`.
- Android dashboard plus menu screenshot after fixes: `docs/parity-screenshots/android-dashboard-plus-menu-after.png`.
- Android add-vehicle top screenshot after fixes: `docs/parity-screenshots/android-add-vehicle-top-after.png`.
- Android add-expense screenshot after fixes: `docs/parity-screenshots/android-add-expense-after.png`.
- Android Account/Settings section screenshots after fixes: `docs/parity-screenshots/android-settings-after.png`, `docs/parity-screenshots/android-settings-sections-after.png`, `docs/parity-screenshots/android-settings-business-after.png`, `docs/parity-screenshots/android-settings-sync-after.png`.
- Android dashboard-car Settings switch screenshot after fixes: `docs/parity-screenshots/android-settings-dashboard-car-after.png`.
- Android Data Health screenshot after cleanup relocation: `docs/parity-screenshots/android-data-health-after.png`.
- Android Financial Accounts screenshot after grouping fixes: `docs/parity-screenshots/android-financial-accounts-after.png`.
- Android Vehicles screenshot after reserved-status fixes: `docs/parity-screenshots/android-vehicles-after.png`.
- Android Add Vehicle screenshot after Inventory ID parity fix: `docs/parity-screenshots/android-add-vehicle-inventory-id-after.png`.
- Android Vehicle Detail screenshot after financial-summary parity fix: `docs/parity-screenshots/android-vehicle-detail-after.png`.
- Android first-launch region selection screenshot after fixes: `docs/parity-screenshots/android-region-selection-after.png`.
- Android login screenshot after fixes: `docs/parity-screenshots/android-login-after-region.png`.
- Follow-up source fix after user QA: Android now includes iOS's Uzbekistan/UZS region and applies selected language through a dedicated Compose `LocalAppLanguage` string provider, so language changes are visible immediately after selection instead of only being persisted.
- Follow-up source fix after user QA: Android Inventory Pulse now uses iOS-style calm/watch/urgent gradient moods; vehicles over 90 days render the urgent red card instead of always using the blue card.
- Follow-up source fix after user QA: Android Vehicles status pills now use active-only filled styling and a compact localized search placeholder so inactive pills no longer look pressed and search text fits.
- Follow-up source fix after user QA: Android Clients list rows now follow the iOS row anatomy more closely with gradient avatar, inline date, vehicle/request line, status badge, and circular call/WhatsApp/SMS buttons.
- Follow-up runtime evidence after user QA: `docs/parity-screenshots/android-followup-after.png` shows Android launching without crash and rendering the dashboard in Uzbek after the language-context fix.
- Follow-up runtime evidence after user QA: `docs/parity-screenshots/android-vehicles-filter-followup-after.png` shows the Vehicles filter/search state after pill/search fixes.
- Follow-up runtime evidence after user QA: `docs/parity-screenshots/android-clients-followup-after.png` shows the redesigned Clients rows with compact circular actions.
- Follow-up crash found and fixed during runtime QA: the first language-context implementation replaced Compose `LocalContext`, which broke Hilt ViewModel creation on device. It was corrected by keeping Activity `LocalContext` intact and introducing a separate `LocalAppLanguage` only for localized string lookup.
- Physical Xiaomi/MIUI device install and cold launch succeeded after the follow-up localization fix. Earlier physical-device screenshots were blocked by keyguard/NotificationShade, but the later Dashboard/Vehicles/Clients follow-up screenshots were captured from the connected device after relaunch.
- Follow-up runtime evidence for bottom navigation: `docs/parity-screenshots/android-bottom-tabs-followup-after.png` shows short localized tab labels fitting in the iOS-style floating capsule on the connected device. UI tree confirmed visible Uzbek labels: `Boshqaruv`, `Xarajat`, `Avto`, `Qismlar`, `Sotuv`, `Mijozlar`.
- Follow-up runtime evidence for Dashboard localization/fit: `docs/parity-screenshots/android-dashboard-uz-localized-fit-after.png` shows the visible first-screen Dashboard sections localized in Uzbek without the Inventory Pulse subline clipping. UI tree confirmed `Inventar holati · bugun`, `3 avto · oʻrt. 164 kun`, `Hisob balanslari`, `Natija va foyda`, `Sotuv foydasi`, and `Operatsiyalar`.
- Follow-up runtime evidence for Region/Language settings before this pass: `docs/parity-screenshots/android-region-language-before-followup.png` showed Uzbek UI with mixed English region/unit text such as `USD • miles`.
- Follow-up runtime evidence for Region/Language settings after this pass: `docs/parity-screenshots/android-region-language-after-followup-localized.png` shows localized Uzbek region names around the selected `Oʻzbekiston` row, and `docs/parity-screenshots/android-region-language-languages-final.png` shows iOS-style language rows with flags and Hindi visible.
- Follow-up runtime evidence for currency application: `docs/parity-screenshots/android-dashboard-uzs-after-followup.png` and UI tree confirmed Dashboard values rendered in `soʻm` after selecting Uzbekistan/UZS.
- Follow-up runtime evidence for Clients before this pass: `docs/parity-screenshots/android-client-detail-before-followup.png` and `docs/parity-screenshots/android-client-edit-before-followup.png` showed Android's old TopAppBar/outlined-field form and broken read-only contact buttons with vertically clipped labels.
- Follow-up runtime evidence for Clients after this pass: `docs/parity-screenshots/android-client-detail-after-followup-final.png`, `docs/parity-screenshots/android-client-edit-after-followup-final2.png`, and `docs/parity-screenshots/android-client-vehicle-sheet-after-followup.png` show the iOS-style centered header, large centered name field, card rows, floating bottom Save button, compact circular contact actions, and vehicle bottom sheet.
- Paywall follow-up source fix after user QA: Android Paywall now follows iOS `PaywallView.swift` structure more closely: light blue/white palette, badge/title/subtitle hero, the same `PaywallHero911.mp4` asset, plan section before features, sticky bottom CTA, restore, and legal links.
- Paywall follow-up video fix after runtime QA: Android initially rendered the portrait mp4 as a tiny `VideoView` inside the hero card. It was replaced with `TextureView + MediaPlayer` and an aspect-fill transform so the car fills the hero area like iOS `AVPlayerLayer.videoGravity = .resizeAspectFill`.
- Paywall follow-up pricing check: Android plan prices are read from `RevenueCatPackage.product.price.formatted`; iOS uses `StoreProduct.localizedPriceString`. No prices, product identifiers, RevenueCat config, or backend contracts were changed.
- Paywall follow-up RevenueCat config check after user QA: Android debug/release builds were locally missing `REVENUECAT_ANDROID_API_KEY`, so the Android SDK could not request plans and the Paywall showed the empty plan state. The Android public SDK key for the RevenueCat app `EzCar24 Business Android` was copied from the logged-in RevenueCat project and saved only to ignored local config files (`Android Car Dealer Tracker/keystore.properties` and `~/.gradle/gradle.properties`), not to tracked source.
- Paywall follow-up RevenueCat offering check: RevenueCat project `EzCar24 Business` has default offering `default` with four packages. Android products are attached as `com.ezcar24.business.weekly:weekly`, `com.ezcar24.business.monthly:monthly`, `com.ezcar24.business.quarterly:quarterly`, and `com.ezcar24.business.yearly:yearly`; the RevenueCat API returned `current_offering_id=default` with four packages for the Android SDK key.
- Paywall follow-up runtime limitation: the local Pixel 7 API 35 AVD uses a `google_apis` image, not a Google Play image, and reported `Billing is not available in this device` plus `Network is unreachable`; it cannot validate real Google Play price strings. Production/runtime price rendering still needs a Play Store-capable device/emulator with package `com.ezcar24.business`.
- Paywall follow-up Xiaomi device finding: the Xiaomi Play Store install is `com.ezcar24.business` version `2.1.14` (`versionCode=2114`, installer `com.android.vending`), while the rebuilt Android app with the new Paywall is local `2.1.23` (`versionCode=2123`). The old Paywall on Xiaomi is therefore the old Play build, not a regression in the current local Paywall source. The production Play build can fetch Google Play products/prices; tapping Continue showed the Google Play purchase sheet for `Yearly Plan` with AED pricing. To see the new Paywall with real store prices on Xiaomi, the current signed build must be uploaded through Google Play, or the production app must be replaced locally with a same-package test build after explicit approval because that can delete local app data and is blocked by Xiaomi install restrictions.
- Paywall follow-up Internal App Sharing: Google Play Console Internal App Sharing terms were accepted with explicit user approval, the `billingDebug` AAB for `com.ezcar24.business` version `2.1.23-billing-debug` was uploaded successfully, and a Play internal sharing install link was generated. This gives a Play-delivered same-package path for testing the new Paywall without the missing production release signing key. Xiaomi install verification is pending because wireless ADB disconnected; the device pings at `192.168.1.9`, but `adb connect` to the advertised wireless debugging port returns `Connection refused`.
- Paywall follow-up vehicle-limit fix: iOS and Android now both use a shared 2-vehicle free limit policy. Free users with 0-1 vehicles can add; free users at 2+ vehicles are routed to Paywall; Pro users and status-checking state are not blocked. Existing records are not modified or deleted.
- Paywall follow-up runtime evidence: `docs/parity-screenshots/android-paywall-after.png` shows the rebuilt Android Paywall on the authenticated Pixel 7 API 35 AVD with the corrected full-width hero video crop.
- Paywall follow-up verification: Android `:app:testDebugUnitTest` and `:app:assembleDebug` passed after the Paywall/video changes; Android crash buffer was empty after opening Paywall. iOS targeted regression `Ezcar24BusinessRegressionTests/testSubscriptionAccessPolicyGatesThirdFreeVehicle` passed on iPhone 17 Pro simulator.

## Priority Legend

- P0: broken navigation, wrong calculation, save/edit/delete bugs, crash, login blocker, dashboard data mismatch.
- P1: visible UI mismatch, missing state, wrong label/default, missing expected screen behavior.
- P2: polish, spacing, small icon or animation differences.

## Screen Map

| Area | iOS source | Android source | Navigation path | Priority |
|---|---|---|---|---|
| Login | `Auth/LoginView.swift`, `Auth/AuthGateView.swift`, `Auth/AppSessionState.swift` | `ui/auth/LoginScreen.kt`, `ui/auth/AuthViewModel.kt`, `MainActivity.kt` | Launch when signed out | P1 |
| Signup | `LoginView.swift` mode switch | `LoginScreen.kt` mode switch | Login -> Sign Up | P1 |
| Guest mode | `AuthGateView.swift`, `ContentView.swift`, `GuestFeaturePreviewView` | `LoginScreen.kt`, `MainScreen.kt`, `GuestFeaturePreview` | Login -> guest mode | P1 |
| Password reset | `Auth/PasswordResetView.swift` | `ui/auth/PasswordResetScreen.kt` | Login -> Forgot password/deep link | P1 |
| Region/currency first launch | `Views/RegionSelectionView.swift`, `Utilities/RegionSettings.swift` | `ui/settings/RegionSelectionScreen.kt`, `util/RegionSettings.kt` | First launch before auth/home | P1 |
| Force update | `Views/ForceUpdateView.swift`, `RemoteConfigService.swift` | `ui/update/ForceUpdateScreen.kt`, `PlayStoreVersionChecker` | App start when required | P1 |
| Main navigation | `ContentView.swift`, `CustomTabBar` | `ui/main/MainScreen.kt`, `MainActivity.kt` | Home tabs | P1 |
| Dashboard | `Views/DashboardView.swift`, `DashboardViewModel.swift`, `DashboardComponents.swift` | `ui/dashboard/DashboardScreen.kt`, `DashboardViewModel.kt` | Dashboard tab | P0 |
| Vehicles list | `Views/VehicleListView.swift`, `VehicleViewModel.swift` | `ui/vehicle/VehicleListScreen.kt`, `VehicleViewModel.kt` | Vehicles tab | P1 |
| Add vehicle | `Views/AddVehicleView.swift` | `ui/vehicle/VehicleAddEditScreen.kt` | Vehicles plus or Dashboard plus | P1 |
| Vehicle details/edit | `Views/VehicleDetailView.swift` | `ui/vehicle/VehicleDetailScreen.kt`, `VehicleAddEditScreen.kt` | Vehicle row -> detail -> edit | P1 |
| Sold vehicles/status | `VehicleListView.swift`, `AddSaleView.swift`, `VehicleDetailView.swift` | `VehicleListScreen.kt`, `AddSaleScreen.kt`, `VehicleAddEditScreen.kt` | Dashboard sold card, Vehicles filters, Sales flow | P0 |
| Expenses dashboard/list | `Views/ExpenseListView.swift`, `DealerExpenseDashboardView` | `ui/expense/ExpenseScreen.kt` | Expenses tab | P1 |
| Add/edit expense | `Views/AddExpenseView.swift` | `ui/expense/AddExpenseSheet.kt` | Expenses plus, Dashboard plus, edit sheet | P1 |
| Expense details | `Views/ExpenseDetailSheet.swift` | `ui/expense/ExpenseDetailBottomSheet.kt` | Expense row/card tap | P1 |
| Sales list | `Views/SalesListView.swift`, `SalesViewModel.swift` | `ui/sale/SalesScreen.kt`, `SalesViewModel.kt` | Sales tab | P1 |
| Add sale | `Views/AddSaleView.swift` | `ui/sale/AddSaleScreen.kt` | Sales plus | P1 |
| Clients list | `Views/ClientListView.swift`, `ClientViewModel.swift` | `ui/client/ClientListScreen.kt`, `ClientViewModel.kt` | Clients tab | P1 |
| Add/edit client | `Views/ClientDetailView.swift` | `ui/client/ClientDetailScreen.kt` | Clients plus or row -> edit | P1 |
| Financial accounts | `Views/FinancialAccountsView.swift`, `FinancialAccount+Extensions.swift` | `ui/finance/FinancialAccountScreens.kt` | Dashboard account cards, Settings | P0 |
| Debts | `Views/DebtsListView.swift`, `DebtDetailView.swift`, `AddDebtView.swift` | `ui/finance/DebtScreens.kt`, `DebtViewModel.kt` | Sales debts section or Settings | P1 |
| Settings/account/team | `Views/AccountView.swift`, `TeamManagementView.swift`, settings views | `ui/settings/SettingsScreen.kt`, `TeamMembersScreen.kt`, profile/settings screens | Dashboard profile, Settings | P1 |
| Search | `Views/GlobalSearchView.swift` | `ui/search/GlobalSearchScreen.kt` | Dashboard search | P1 |
| Paywall | `Views/PaywallView.swift`, `SubscriptionManager.swift` | `ui/settings/PaywallScreen.kt`, billing manager | Vehicle limit, settings/paywall route | P1 |
| Sync/offline/data health | `SyncHUDOverlay.swift`, `DataHealthView.swift`, `CloudSyncManager.swift` | `SyncStatusCard`, `DataHealthScreen.kt`, `CloudSyncManager.kt` | Dashboard sync card, Data Health | P0 |

## Screen-by-Screen Parity Notes

| Screen/flow | Visual differences | Functional differences | Missing/different fields, defaults, validation, calculations, states | Priority/status |
|---|---|---|---|---|
| Login/signup | Android uses Material form styling; iOS uses SwiftUI card/auth styling and social buttons. Android header was changed from a square brand mark to the iOS-like circular car mark. | Both have email/password, mode switch, reset, and Google entry. iOS also exposes Apple Sign In. | Runtime login succeeded on both iOS simulator and Android emulator with the same review/demo account. Empty/error copy still needs a dedicated visual pass. | P1 partly fixed |
| Guest mode | Android guest preview is tab-level route content; iOS wraps guest access through `AuthGateView` and `GuestFeaturePreviewView`. | Both block production data access for guest mode. | Need live walkthrough to confirm every guest tab has same locked/preview state. | P1 remaining |
| Password reset | Android is a full Compose route; iOS uses password reset flow and deep-link callback. | Both call the password-reset backend path. | No backend contract changes made. Deep-link success/failure copy not runtime-verified. | P1 remaining |
| Region/currency selection | Android was a large tile grid; it now matches the iOS sheet/list pattern more closely with compact header, single rounded list, row dividers, selected-row highlight, flags in the language list, and fixed Done/Continue actions. | Both have region/language concepts and currency formatting utilities. Android now includes iOS's Uzbekistan region (`UZS`, `soʻm`, `uz-UZ`, 0 decimals), Hindi as a selectable language, localized region display names in existing Android locales, and a dedicated `LocalAppLanguage` string provider so language changes visibly apply after selection without breaking Hilt's Activity context. | Runtime-verified on the connected Android device: selecting Uzbekistan changed Dashboard currency to `soʻm`; Settings summary changed to `Oʻzbekiston • Oʻzbekcha`; Region/Language list showed localized Uzbek region names and Hindi. Exact SF Symbol/blur treatment and full Hindi app-wide string coverage are still not complete. | P1 partly fixed |
| Force update | Android has Play Store version checker screen; iOS has App Store/Supabase remote config blocker. | Same conceptual blocker, different store plumbing. | Not triggered in current environment, so empty/error state is source-inspected only. | P1 remaining |
| Dashboard | Android Material cards vs iOS material/glass cards; Android top bar less glass-like. | Before fix, Android period math, credit accounts, account navigation, plus action, dashboard-car lane, Inventory Pulse color mood, and several first-screen localized labels diverged. | Fixed period windows, credit-card totals, account-card routes, plus menu, inventory pulse placement, compact cards, iOS runtime `Sales Profit` label, dashboard car lane, urgent/watch/calm Inventory Pulse coloring, and first-screen Dashboard label localization/fit for supported Android resource folders. Remaining visual polish and radar sheet parity. | P0/P1 partly fixed |
| Main tabs | Android bottom nav uses Material icons; iOS custom floating capsule uses SF Symbols. Android now uses short localized visible tab labels so long translated titles do not clip inside the capsule. | Labels/order match the actual iOS `ContentView.swift` source order: Dashboard, Expenses, Vehicles, Parts when enabled, Sales, Clients. Full tab names remain available to accessibility descriptions. | Runtime-verified on the connected Android device in Uzbek. Icon exactness and selected/unselected color/shape still not exact. | P2 partly fixed |
| Vehicles list | Android list/filter chips are Compose/Material; iOS uses SwiftUI inventory layout. Android status filter pills now use active-only filled styling with colored inactive tints, and the search placeholder was shortened/localized to fit in the field. | Default list excludes sold vehicles on both platforms. Sold status route exists. Android status filters now treat `reserved` as the primary iOS value while preserving legacy `owned`, and `on_sale` includes legacy `available`. Android now searches and displays vehicle `Inventory ID` where present. | Need live data verification for sort/filter defaults and empty state copy. | P1 partly fixed |
| Add/edit vehicle | Android form was much larger than iOS and used a full-width photo block. | Android save path preserves asking price for edits; iOS add form does not expose asking price. Android now saves Reserved vehicles with iOS-compatible `reserved` instead of Android-only `owned`, while legacy `owned` records still display as Reserved. Android now includes iOS's `Inventory ID`, syncs it through the existing Supabase `inventory_id` column, stores `purchase_account_id`, and deducts purchase price from the selected Paid From account for new Android vehicles like iOS. | New Android add form now uses compact centered photo picker, centered top bar, smaller fields/cards, hides Asking Price for create mode while keeping it in edit mode, and shows `Inventory ID` under VIN like iOS. | P0/P1 partly fixed |
| Vehicle details/status | Android detail now follows the iOS display hierarchy more closely: photo area, header card, single financial summary, expenses. Removed Android-only visible pricing recommendation and separate holding-cost cards from display mode. | Android status update and sale recording exist. Android financial summary labels are now localized, expense-type labels are correctly mapped, and inspection report links display/open from the same summary area as iOS. | Runtime Add Vehicle -> Vehicles list -> Vehicle Detail was verified on AVD with a created `Toyota Camry` record. Remaining: full iOS share composer/PDF/photo-gallery parity and sold-status edit regression. | P1 partly fixed |
| Expenses list/dashboard | Android expense dashboard is close but Material-styled. | Add/edit/delete and dashboard refresh paths exist. | Category labels now align with iOS's visible add-expense categories (`Vehicle`, `Personal`, `Employee`, `Bills`, `Marketing`); list filter/details still need a runtime state comparison. | P1 remaining |
| Add/edit expense | Android bottom sheet with segmented surfaces; iOS SwiftUI sheet/form. Android no longer shows the Android-only `Expense Type` selector, and the header now follows iOS close/title/Save instead of the previous Android overflow button. | Both support amount/category/date/vehicle/account/user-style associations in code. Android now blocks vehicle-category expense save without a selected vehicle, matching iOS. Template use/save actions remain available as form chips instead of being removed. | Need live validation parity for account/user linking and edit-mode prefill. Picker sheet styling and exact template action placement still differ from iOS. | P0/P1 partly fixed |
| Expense details | Android bottom sheet differs from iOS detail sheet styling. | Both expose details and edit/delete entry points. | Empty/error/loading state copy not runtime-verified. | P1 remaining |
| Sales list/add/detail | Android sales routes exist and sale recording marks vehicles sold. New Sale now has the iOS-style Vehicle/Parts selector and centered close/title header. | iOS is source for final revenue/profit presentation; Android uses existing save logic for vehicle sales and now uses existing `PartSalesViewModel.createSale` for parts sales from the unified New Sale sheet. Android CRM sale interaction details now use region currency formatting like iOS instead of storing a bare number. | No calculation formulas were changed. Vehicle sale save behavior matches the iOS shape closely; parts sale now supports date, client, payment method, account, notes, line items, stock validation, localized stock/save errors, account deposit, and batch stock deduction. Remaining: seeded data comparison for profit/revenue and more exact sheet/card styling. | P0/P1 partly fixed |
| Clients list/add/detail | Android main Clients tab top bar now matches iOS more closely: filter action plus add action, without the extra Lead Management shortcut. Client list rows now match the iOS row hierarchy more closely: gradient avatar, name/date row, request/vehicle line, status badge, and compact circular call/WhatsApp/SMS actions in the same card. Client detail/add/edit now uses the iOS-like centered sheet header, large centered name input, horizontal colored status pills, card-row contact/vehicle/notes sections, and floating bottom Save button instead of the old Android TopAppBar/outlined form. | Both have client list and detail/edit flows. Android client status sections, edit pills, and detail summary now follow the iOS `new/contacted/viewing/negotiation/sold` status model while preserving legacy raw-value normalization and existing stored CRM metadata. Vehicle selection now opens a bottom sheet instead of an inline dropdown. | Remaining: preferred-date picking still uses native Android date/time dialogs rather than the iOS graphical sheet picker; exact card shadow/material is close but not pixel-identical. | P1 partly fixed |
| Financial accounts | Android now uses grouped account sections, iOS-style row anatomy, kind icons/colors, chevrons, and filtered empty states instead of the old raw flat list. | Fixed kind parsing/composition for Cash/Bank/Credit Card/Other and filtered dashboard routes. Add Account now saves iOS-compatible account type strings, hides the type selector when launched from a filtered dashboard card, and uses the same empty/duplicate-name validation messages as iOS. | Remaining: transaction detail still uses a full-screen Android route rather than iOS sheet/list presentation. | P0/P1 partly fixed |
| Debts | Android debt screens exist with full-screen Material forms. | iOS has debts list/detail/add views. | Totals and due-state parity require seeded data comparison; no formula changes made. | P1 remaining |
| Settings/account/team | Android Account now follows the iOS section rhythm more closely: App Settings, Business, Management/Sync, Security, Support, Legal. | Team/account actions remain available; Reports & Data Export now points to the Backup Center where Android already exposes Scheduled Reports/Email Reports. Deal Desk permission gating now follows iOS intent (`createSale` or owner/admin). Dashboard car toggle now controls the Android dashboard lane using the same persisted intent as iOS. | Remaining: Android still has full-screen routes instead of iOS sheet/list presentation. | P1 partly fixed |
| Sync/offline/data health | Android has sync status card and data health screen; iOS has HUD overlay and Data Health. Android Data Health now includes the iOS-style Clean Up Duplicates action in the diagnostics controls for users with `manageTeam`. | Manual sync, diagnostics, force refresh, report copy/share, and duplicate cleanup paths exist. | No sync serialization, server-wins strategy, RemoteSnapshot, or backend contracts were changed. Queue/error-state visual parity still needs runtime offline testing. | P0 guarded, P1 partly fixed |
| Search | Android global search route exists; iOS global search opens from dashboard. | Both reachable from dashboard search button. | Result grouping/order and empty state copy not runtime-verified. | P1 remaining |
| Paywall/subscription | Android was visually different from iOS and rendered the copied portrait car video incorrectly during the first runtime check. Android now uses the iOS light paywall structure, same hero mp4, aspect-fill crop, plan-first layout, feature rows, sticky CTA, restore, and legal links. Xiaomi currently shows the old Paywall only because Google Play installed production `2.1.14`; the current local Paywall code is `2.1.23`. | Vehicle-limit Paywall routing now exists as `paywall/vehicle_limit` on Android and `.vehicleLimit` on iOS. Both platforms gate new free users at 2 vehicles. Existing users with 3+ vehicles are not modified; the next create attempt is gated unless Pro is active. | Store prices remain RevenueCat/store-driven on both platforms. The missing local Android `REVENUECAT_ANDROID_API_KEY` was restored from RevenueCat to ignored local config; RevenueCat `default` offering and four Android published products were verified. Play Store-installed `2.1.14` on Xiaomi opened the Google Play purchase sheet with AED pricing, proving production products load. A same-package `2.1.23-billing-debug` AAB is now uploaded to Google Play Internal App Sharing for new Paywall QA; Xiaomi installation is pending ADB reconnect. | P0/P1 fixed locally; Internal App Sharing install verification pending |

## Findings Before Android Fixes

Main navigation source note: the written acceptance checklist lists `Dashboard, Vehicles, Expenses, Sales, Clients`, but the actual iOS source of truth in `ContentView.swift` currently orders mobile tabs as `Dashboard, Expenses, Vehicles, Parts, Sales, Clients` with Parts conditional. Android already follows this actual iOS source order, so no tab-order code change was made.

### P0

1. Dashboard selected period math differs from iOS. Android `ONE_WEEK` starts seven days before today, producing an 8-day inclusive trend, while iOS `.week` starts six days before today and builds 7 points. Android `ONE_MONTH` uses calendar month subtraction, while iOS uses a day-count window. This can change expenses, trends, and comparison percentages.
2. Android dashboard ignores credit-card financial accounts. iOS parses `Cash`, `Bank`, `Credit Card`, and prefixed account names such as `Credit Card - Visa`; Android only sums exact `cash` and `bank`.
3. Android dashboard cash and bank cards both navigate to the unfiltered financial account list. iOS routes cash, bank, and credit cards to filtered account lists.
4. Android dashboard plus action opens add expense directly. iOS shows a plus menu with Add Expense and Add Vehicle, permission gated.

### P1

1. Android dashboard account overview has two account cards; iOS has Cash, Bank, and Credit Card.
2. Android dashboard visual scale was much larger than iOS: oversized account/performance cards, a visible idle sync row, and no iOS-style inventory pulse card at the top.
3. Android top bar is solid background; iOS top bar uses ultra-thin material with shadow. Android is close but less glass-like.
4. Android dashboard includes AI/CRM/inventory summary cards in roughly the right area, but iOS order is cockpit, financial overview, AI, today's expenses, summary, recent expenses. Android order is mostly aligned but lacks the iOS inventory pulse/radar sheet parity.
5. Android add vehicle exposed `Asking Price` on the add form while iOS add-vehicle does not, although iOS vehicle detail edit has asking price.
6. Android add vehicle used a full-width photo block and oversized form controls compared with the iOS compact add-photo tile and card fields.
7. Android add vehicle uses chip-style status selectors; iOS add-vehicle uses a menu picker. Behavior is acceptable but visually different.
8. Android Add Expense exposed an extra `Expense Type` selector (`Holding Cost`, `Improvement`, `Operational`) that iOS does not show in the add-expense form.
9. Android financial accounts screen is raw account-string based and does not present grouped account kinds like iOS.
10. Android client detail primary read/edit flow is now much closer to iOS; remaining mismatch is the preferred-date picker, which still uses Android native date/time dialogs instead of the iOS graphical sheet.
11. Android settings/account screens are route-based full screens; iOS profile/account is presented as a dashboard profile sheet.

### P2

1. Bottom tab icons are Android Material equivalents, not exact SF Symbols. Order matches iOS, including conditional Parts; visible labels now use short localized tab strings to avoid clipping.
2. Android card shadows/radii are close but not fully identical to the iOS design system.
3. Android date pickers use native Android dialogs; iOS often uses sheet/date-picker combinations.
4. Android screenshots are now captured on a dedicated Pixel 7 API 35 emulator; the earlier physical-device capture limitation is no longer blocking parity work.

## Fixed Items

1. Fixed Android dashboard time-range boundaries to match iOS intent more closely:
   - `1W` now starts six days before today for a 7-day window.
   - `1M` now uses a 30-day window instead of calendar-month subtraction.
   - `Today` now has an explicit exclusive end bound at tomorrow's start.
   - `All` no longer uses epoch as the lower bound.
2. Reworked Android expense trend generation so it no longer builds huge all-time daily point arrays. `All` now builds a compact 12-month trend; longer ranges use weekly/monthly-style buckets.
3. Changed Android dashboard previous-period comparison so a zero previous period returns no percentage, matching iOS behavior more closely instead of forcing `100%`.
4. Added shared Android financial account kind parsing for `Cash`, `Bank`, `Credit Card`, and prefixed labels such as `Credit Card - Visa`.
5. Added dashboard credit-card total support and rendered the third account card so Android matches the iOS Cash/Bank/Credit Card structure.
6. Routed dashboard Cash, Bank, and Credit Card cards to filtered financial-account screens instead of the same unfiltered account list.
7. Changed Android dashboard plus behavior from direct Add Expense navigation to an iOS-style menu with Add Expense and Add Vehicle.
8. Kept/restored the dashboard profit label as `Sales Profit` after authenticated iOS runtime verification showed `net_profit` localizes to `Sales Profit`.
9. Added an Android inventory pulse card near the top of Dashboard to match the iOS first-screen structure.
10. Hid the Android idle sync row from the first dashboard viewport; sync/failure/queued states still surface when actionable, and pull-to-refresh/manual sync remains available.
11. Reduced dashboard card/time-selector scale so account cards, performance cards, and `AED` currency values fit without crowding.
12. Changed Android Add Vehicle create flow to use a compact centered Add Photo tile, centered iOS-like top bar, smaller fields/cards, and no Asking Price field in create mode.
13. Added unit tests for financial account kind parsing and dashboard range boundaries.
14. Changed Android first-launch Region Selection from a divergent tile grid to the iOS-like single-card list pattern and added localized first-launch strings for supported Android resource folders.
15. Changed Android login header to use the iOS-like circular car icon instead of the square Android brand mark and routed the header title/subtitle through localization.
16. Removed the Android-only visible `Expense Type` selector from Add Expense while preserving Android's existing internal default for save compatibility.
17. Fixed Add Expense vehicle-category validation so Android now matches iOS: saving a vehicle expense without a vehicle shows an inline error and does not create the record.
18. Localized visible Add Expense strings added during the validation fix (`New Expense`, vehicle-required error, receipt labels).
19. Added the iOS-style `Vehicle` / `Parts` sale type selector to Android New Sale.
20. Added a real embedded Android parts-sale form inside New Sale using existing Android `PartSalesViewModel.createSale`, including account deposit, client selection, date, payment method, notes, line items, stock checks, and batch stock deduction.
21. Changed Android New Sale header to the iOS-like centered title with a circular close button.
22. Added localized Android resources for parts-sale `Add Item`, stock warning, and save error strings across supported resource folders.
23. Removed the extra Lead Management shortcut from the main Android Clients top bar so the primary tab matches iOS's filter/add toolbar intent. Lead Management remains reachable from Dashboard/Analytics routes.
24. Aligned Android client status grouping and edit chips with iOS `ClientStatus`: `new`, `contacted`, `viewing`, `negotiation`, `sold`. Legacy Android/server values (`engaged`, `in_progress`, `completed`, `purchased`) are normalized without schema changes.
25. Added localized Android resources for the new visible `Contacted` and `Viewing` status labels across supported resource folders.
26. Reworked Android Financial Accounts list to match iOS grouping: sections by Cash, Bank, Credit Card, Other; account rows now use kind icon/color, short title, optional kind subtitle, right-aligned current balance, and chevron.
27. Removed the Android-only inline account delete action from Financial Accounts list rows; destructive transaction/account operations remain in detail flows instead of the primary list row.
28. Added iOS-compatible account type helpers on Android (`parse`, `compose`, display/short/subtitle titles) and expanded unit coverage for prefixed account labels such as `Bank - Main` and `Credit Card - Visa`.
29. Added localized Android strings for Financial Accounts filtered empty states, `Credit Card`, `Account Type`, standalone `Current Balance`, and the iOS footer copy across supported resource folders.
30. Reordered Android Account/Settings sections to match iOS more closely: `App Settings`, `Business`, `Management`/`Sync`, `Security`, `Support`, `Legal`.
31. Moved Android Business rows out of the old `General` section and aligned Deal Desk visibility with iOS (`createSale` permission or owner/admin) while keeping Financial Accounts owner/admin gated.
32. Removed the duplicate top-level `Email Reports` Account row; the functionality remains under Backup Center -> Scheduled Reports, matching the iOS `Reports & Data Export` grouping better.
33. Moved Android `Clean Up Duplicates` from Account/Settings into Data Health controls, matching iOS Data Health placement and preserving `manageTeam` permission gating.
34. Added Data Health cleanup loading/success state and localized the new visible cleanup strings across supported Android resource folders.
35. Aligned Android vehicle reserved status with iOS: Add/Edit now uses `reserved`, list filters/counts include both new `reserved` and legacy `owned`, and on-sale filters include legacy `available`.
36. Fixed Android vehicle status badge/color mapping so Reserved and On Sale use the iOS/design-system blue family instead of Android-only green/gray status treatment.
37. Added shared Android `VehicleStatus` compatibility helpers and unit tests so legacy `owned`/`available` values continue to display/filter like iOS `reserved`/`on_sale`.
38. Matched Android Financial Accounts name validation to iOS: blank composed account names and duplicate composed account types now show localized `Account Error` alerts using the same user-facing messages.
39. Added Android local persistence for iOS vehicle `Inventory ID` with an additive Room 11 -> 12 migration (`vehicles.inventoryId TEXT`) and no backend schema changes.
40. Added Android `inventory_id` support to `RemoteVehicle` pull/push mapping, using the existing production Supabase column already used by iOS.
41. Added Android Add/Edit Vehicle `Inventory ID` field, edit prefill, vehicle list/detail/search display, and localized visible labels across supported resource folders.
42. Added Android local persistence and Supabase sync mapping for vehicle `purchase_account_id` with an additive Room 12 -> 13 migration (`vehicles.purchaseAccountId TEXT`), matching the iOS `RemoteVehicle.purchaseAccountId` contract without backend changes.
43. Fixed Android Add Vehicle financial behavior so new vehicles deduct `purchasePrice` from the selected Paid From account and sync the updated account balance, matching iOS's AddVehicleView behavior.
44. Split Android Add/Edit Vehicle purchase account and sale deposit account state so editing a sold vehicle does not accidentally overwrite the purchase account with the sale account. Legacy Android vehicles that were created without a purchase account are not automatically backfilled or rebalanced during ordinary edit saves.
45. Added Android unit tests for vehicle purchase-account balance deltas: new vehicle deduction, same-account edit delta, changed-account restore/deduct, and legacy no-account protection.
46. Reworked Android Vehicle Detail display mode to remove Android-only visible `Pricing Recommendations` and separate `HoldingCostCard` sections; financial data now sits in a single iOS-style `Financial Summary`.
47. Localized Android Vehicle Detail financial summary labels across all Android resource folders and fixed the expense-type breakdown label bug where `HOLDING_COST` and `OPERATIONAL` were displayed under the wrong labels.
48. Added the iOS-style inspection report row to Android Vehicle Detail financial summary, opening the existing `reportURL` without changing the vehicle schema.
49. Removed Android-only mileage and aging-badge rows from the Vehicle Detail header display so the header matches iOS's title/year/status/Inventory ID/VIN/purchase-date/notes rhythm.
50. Updated Android vehicle-sale CRM interaction details to use region currency formatting, matching iOS's `asCurrencyFallback()` behavior for sale interaction text.
51. Runtime-verified Android Add Vehicle -> Vehicles list -> Vehicle Detail on the Pixel 7 API 35 AVD, including `Inventory ID`, `reserved` status, purchase price display, and the new single financial summary.
52. Reworked Android Client Detail to remove Android-only lead stage/source/priority/score/estimated-value panels from the primary edit and read-only surfaces while preserving the stored CRM fields during save. The read-only summary now follows iOS with status, preferred date, last interaction/no-interactions state, and next reminder.
53. Added Android dashboard car lane below the time-range selector, matching the iOS `DrivingCarLane` behavior at product level: tap pauses/resumes, long-press opens a parking confirmation, and Settings can restore visibility.
54. Added Android Settings `Dashboard car` switch with localized title/hint/dialog strings across supported resource folders, using local SharedPreferences only and no backend/schema changes.
55. Changed Android Add Expense header from an Android-only overflow menu to the iOS-like close/title/Save layout. Template use/save actions remain available as compact form chips, so no template functionality was silently removed.
56. Added iOS-parity Android Uzbekistan region support (`UZS`, `soʻm`, `uz-UZ`, 0 decimals) and localized the visible `Uzbekistan` row across Android resource folders.
57. Fixed Android language selection application with a dedicated `LocalAppLanguage` provider used by `localizedUiString`; selected languages now update visible strings immediately instead of only persisting the preference.
58. Changed Android Inventory Pulse mood coloring to follow iOS `calm/watch/urgent` intent, including red urgent gradient for vehicles over 90 days and warning arc color for aging/urgent stock.
59. Restyled Android Vehicles status pills so inactive filters no longer look pressed/selected, and added a short localized `Search vehicles` placeholder that fits the search field.
60. Reworked Android Clients list row chrome to mirror iOS: gradient avatar, inline activity date, request/vehicle line, status capsule, and circular call/WhatsApp/SMS quick actions inside the same card.
61. Corrected the Android localization runtime fix after device QA exposed a Hilt crash: Activity `LocalContext` is no longer replaced; localized string lookup now uses a separate `LocalAppLanguage` provider.
62. Runtime-verified the corrected build on the connected Android device: install succeeded, cold launch reached Dashboard, Uzbek strings rendered in Dashboard/Vehicles/Clients, and no new crash-buffer output appeared after relaunch.
63. Fixed Android bottom navigation label clipping in long locales by separating full route titles from short localized visible tab titles. Screen titles still use the full strings; bottom tabs now use compact strings such as Uzbek `Boshqaruv`, `Xarajat`, `Avto`, `Qismlar`, `Sotuv`, `Mijozlar`, matching the iOS intent of always-readable one-line tab labels.
64. Added missing Android Dashboard localization resources across supported resource folders for Inventory Pulse, account balances, performance/profit, operations, CRM summary, inventory summary, and related metric labels. The Uzbek Inventory Pulse subline now uses a compact translation and `AutoResizingText` so it fits the card instead of truncating.
65. Reworked Android Region/Language settings to match iOS behavior and presentation more closely: language rows now use flag icons and native names without Android-only subtitles, Hindi is selectable like iOS, composed region subtitles localize units instead of falling back to raw English, and Settings summary localizes the selected region name.
66. Added localized region display-name resources across existing Android language folders, plus a minimal Hindi resource layer for Region/Language, main tabs, and first-screen Dashboard labels.
67. Runtime-verified Region/Language on the connected Android device: Uzbekistan row selected with `UZS • km`, Settings summary showed `Oʻzbekiston • Oʻzbekcha`, Dashboard money rendered as `soʻm`, localized Uzbek region names appeared in the region list, and Hindi appeared in the language list.
68. Added Android unit coverage for Uzbekistan/UZS and Hindi language metadata in `RegionSettingsTest`.
69. Reworked Android Client Detail/Add/Edit to match the iOS `ClientDetailView` structure: centered custom header with close/edit, large centered name field, iOS-style colored status pills, contact/vehicle/notes card rows, and a floating bottom Save button instead of the previous Android TopAppBar with top Save.
70. Replaced the Android client vehicle dropdown with a bottom sheet selector, aligning the flow with iOS's sheet-based vehicle picker while preserving the existing `vehicleId` save behavior.
71. Fixed the read-only Client Detail contact actions that previously rendered tall/narrow text buttons with clipped vertical labels; they now render compact circular call/WhatsApp/SMS/email icon actions.
72. Corrected the visible Uzbek uppercase `VEHICLE INTEREST` translation from `AVTOMOBILGA QIZIQAT` to `AVTOMOBILGA QIZIQISH`.
73. Rebuilt Android Paywall to match iOS `PaywallView.swift` more closely: light palette, badge/title/subtitle hero, same local `PaywallHero911.mp4`, plan cards before feature rows, sticky CTA, restore purchase action, and legal links.
74. Replaced Android Paywall's incorrectly scaled `VideoView` with a `TextureView + MediaPlayer` implementation using aspect-fill transform and vertical framing so the car video fills the hero card like iOS `AVPlayerLayer.videoGravity = .resizeAspectFill`.
75. Added Android `paywall/vehicle_limit` routing from Vehicles and Add Vehicle flows, including auto-gating direct add-vehicle routes before a user fills an unavailable form.
76. Changed the free vehicle creation limit on both platforms from 3 to 2 through shared access-policy helpers (`SubscriptionAccessPolicy` on iOS, `SubscriptionAccess` on Android), without modifying existing vehicle records or backend data.
77. Updated iOS and Android user-facing vehicle-limit strings/localizations from 3 vehicles to 2 vehicles and removed stale Android 3-vehicle resource strings.
78. Added regression coverage for the 2-vehicle gate on both platforms and verified store-price sourcing remains dynamic: Android uses `RevenueCatPackage.product.price.formatted`; iOS uses `StoreProduct.localizedPriceString`.
79. Restored the local Android RevenueCat public SDK key from the logged-in RevenueCat project into ignored local config (`keystore.properties` and `~/.gradle/gradle.properties`), verified `BuildConfig.REVENUECAT_ANDROID_API_KEY` is non-empty with `goog_` prefix, and verified RevenueCat returns the `default` offering with four packages for the Android SDK key.

## Remaining Known Gaps

- Android is closer on the dashboard, but it is not fully visually identical to iOS. The top bar material, card elevation/radius, inventory radar sheet treatment, and exact lower-dashboard card rhythm still need further design parity work.
- Android Region/Language now supports Uzbekistan/UZS, immediate Compose localization, Hindi as a selectable language, and localized region names in existing Android locale folders. Full Hindi app-wide translation coverage is still partial; the new `values-hi` layer covers Region/Language, main tabs, and first-screen Dashboard labels.
- Android language switching now applies immediately, and the first-screen Dashboard labels shown in the follow-up Uzbek screenshot are localized. A broader full-app string audit is still needed for deeper/less visible Dashboard cards and secondary flows.
- Add Vehicle is closer, but still differs in some form mechanics: Android status selection remains chips while iOS presents picker-style controls, and Android Paid From is visible earlier because account selection is mandatory.
- Vehicle Detail is closer, but the iOS share composer/PDF export and richer photo gallery management remain deeper than Android's current native share/photo surfaces.
- Android Add Expense is closer after moving Save into the header, but picker sheet styling and the exact template action placement still differ from iOS. Template functionality was not removed silently.
- Android New Sale is closer, but vehicle selection still appears as an inline list rather than the iOS vehicle-selection sheet, and the parts-sale form does not yet show iOS's permission-gated cost/profit summary.
- Android Clients list/detail/add/edit is much closer to iOS after row restyling, iOS-like detail/edit form structure, bottom Save, compact contact actions, and vehicle bottom sheet. Preferred-date picking still uses native Android date/time dialogs, and exact card material/shadow remains a P2 pixel-level difference.
- Financial accounts list presentation is now close to iOS, but the account transaction detail remains a full-screen Android route instead of iOS's sheet/list presentation.
- Android Account/Settings section order and dashboard-car toggle are closer to iOS, but Android still uses full-screen route transitions instead of iOS sheet/list presentation.
- Sync/offline, force-update, and auth deep-link flows need device-authenticated runtime walkthroughs before marking them fully aligned.
- Paywall is now visually much closer and runtime-screenshot verified on Android, including hero video crop. The earlier empty plan state was caused first by missing local Android RevenueCat key; that local config is fixed. Xiaomi Play Store QA confirmed Google Play products/prices load on production package `com.ezcar24.business`, but that installed app is old `2.1.14`, so it still shows the old Paywall. A same-package `2.1.23-billing-debug` AAB is uploaded to Internal App Sharing for Play-delivered QA. Remaining Paywall gap: reconnect Xiaomi ADB or open the generated internal sharing link on the phone to install the uploaded build and verify the new Paywall UI and live price strings together.
- Android first-launch Region Selection is now structurally close to iOS, but exact symbol rendering, material blur, and animation timing are still P2 visual differences.
- Android login is closer to iOS, but Apple Sign In is iOS-only in the current Android UI and social button ordering therefore differs by platform.

## Commands Run

```bash
cd "/Volumes/LexarDev/Developer/Projects/CarDealerTracker/Android Car Dealer Tracker"
./gradlew assembleDebug --console=plain
./gradlew testDebugUnitTest --console=plain
./gradlew assembleDebug --console=plain
./gradlew testDebugUnitTest --console=plain && ./gradlew assembleDebug --console=plain && git diff --check
./gradlew testDebugUnitTest --console=plain
./gradlew testDebugUnitTest --console=plain && ./gradlew assembleDebug --console=plain && git diff --check
./gradlew testDebugUnitTest --console=plain && ./gradlew assembleDebug --console=plain && git diff --check
./gradlew testDebugUnitTest --console=plain && ./gradlew assembleDebug --console=plain && git diff --check
./gradlew testDebugUnitTest --console=plain && ./gradlew assembleDebug --console=plain && git diff --check
./gradlew :app:installDebug --console=plain
./gradlew :app:compileDebugKotlin --console=plain
./gradlew :app:compileDebugKotlin --console=plain
./gradlew :app:compileDebugKotlin --console=plain
./gradlew :app:installDebug --console=plain
adb logcat -c
adb shell am force-stop com.ezcar24.business.debug
adb shell am start -W -n com.ezcar24.business.debug/com.ezcar24.business.MainActivity
adb exec-out uiautomator dump /dev/tty
adb exec-out screencap -p > ../docs/parity-screenshots/android-followup-after.png
adb shell input tap 310 1494
adb exec-out screencap -p > ../docs/parity-screenshots/android-vehicles-filter-followup-after.png
adb shell input tap 613 1494
adb exec-out screencap -p > ../docs/parity-screenshots/android-clients-followup-after.png
adb logcat -d -b crash
./gradlew testDebugUnitTest --console=plain && ./gradlew assembleDebug --console=plain && git -C .. diff --check
./gradlew :app:installDebug --console=plain
./gradlew :app:compileDebugKotlin --console=plain
./gradlew :app:installDebug --console=plain
adb logcat -c
adb shell am force-stop com.ezcar24.business.debug
adb shell am start -W -n com.ezcar24.business.debug/com.ezcar24.business.MainActivity
adb exec-out screencap -p > ../docs/parity-screenshots/android-bottom-tabs-followup-after.png
adb exec-out uiautomator dump /dev/tty
adb logcat -d -b crash
./gradlew testDebugUnitTest --console=plain
./gradlew assembleDebug --console=plain
git diff --check
./gradlew :app:compileDebugKotlin --console=plain
./gradlew :app:installDebug --console=plain
adb logcat -c
adb shell am force-stop com.ezcar24.business.debug
adb shell am start -W -n com.ezcar24.business.debug/com.ezcar24.business.MainActivity
adb exec-out screencap -p > ../docs/parity-screenshots/android-dashboard-uz-localized-after.png
adb exec-out screencap -p > ../docs/parity-screenshots/android-dashboard-uz-localized-fit-after.png
adb exec-out uiautomator dump /dev/tty
./gradlew testDebugUnitTest --console=plain
./gradlew assembleDebug --console=plain
adb logcat -d -b crash
git diff --check
./gradlew :app:compileDebugKotlin --console=plain
./gradlew :app:installDebug --console=plain
adb exec-out screencap -p > ../docs/parity-screenshots/android-region-language-before-followup.png
adb exec-out screencap -p > ../docs/parity-screenshots/android-region-language-after-followup-top.png
adb exec-out screencap -p > ../docs/parity-screenshots/android-region-language-uz-selected-after.png
adb exec-out screencap -p > ../docs/parity-screenshots/android-dashboard-uzs-after-followup.png
adb exec-out screencap -p > ../docs/parity-screenshots/android-region-language-after-followup-localized.png
adb exec-out screencap -p > ../docs/parity-screenshots/android-region-language-languages-final.png
adb exec-out uiautomator dump /dev/tty
./gradlew testDebugUnitTest --console=plain
./gradlew assembleDebug --console=plain
adb logcat -d -b crash
git diff --check
./gradlew :app:compileDebugKotlin --console=plain
./gradlew assembleDebug --console=plain
adb install -r "app/build/outputs/apk/debug/app-debug.apk"
adb shell am start -n com.ezcar24.business.debug/com.ezcar24.business.MainActivity
adb exec-out screencap -p > docs/parity-screenshots/android-clients-before-followup.png
adb exec-out screencap -p > docs/parity-screenshots/android-client-detail-before-followup.png
adb exec-out screencap -p > docs/parity-screenshots/android-client-edit-before-followup.png
adb exec-out screencap -p > docs/parity-screenshots/android-client-detail-after-followup-final.png
adb exec-out screencap -p > docs/parity-screenshots/android-client-edit-after-followup-final2.png
adb exec-out screencap -p > docs/parity-screenshots/android-client-vehicle-sheet-after-followup.png
adb -s emulator-5554 install -r app/build/outputs/apk/debug/app-debug.apk
adb -s emulator-5554 install -r "Android Car Dealer Tracker/app/build/outputs/apk/debug/app-debug.apk"
adb -s emulator-5554 shell am force-stop com.ezcar24.business.debug
adb -s emulator-5554 shell am start -n com.ezcar24.business.debug/com.ezcar24.business.MainActivity
git diff --check
adb devices
sdkmanager "system-images;android-35;google_apis;arm64-v8a"
ANDROID_AVD_HOME="$ANDROID_SDK_ROOT/avd" avdmanager create avd -n ezcar24_parity_pixel7_api35 -k "system-images;android-35;google_apis;arm64-v8a" -d pixel_7 --force
ANDROID_AVD_HOME="$ANDROID_SDK_ROOT/avd" emulator -avd ezcar24_parity_pixel7_api35 -no-snapshot -no-audio -no-boot-anim -gpu swiftshader_indirect
adb -s adb-6DVGOFPVNBM7LNMR-htEvLr._adb-tls-connect._tcp shell cmd package resolve-activity --brief com.ezcar24.business.debug
adb -s adb-6DVGOFPVNBM7LNMR-htEvLr._adb-tls-connect._tcp shell am start -n com.ezcar24.business.debug/com.ezcar24.business.MainActivity
adb -s adb-6DVGOFPVNBM7LNMR-htEvLr._adb-tls-connect._tcp exec-out uiautomator dump /dev/tty
adb -s adb-6DVGOFPVNBM7LNMR-htEvLr._adb-tls-connect._tcp exec-out screencap -p > docs/parity-screenshots/android-launch-before.png
adb -s emulator-5554 exec-out screencap -p > docs/parity-screenshots/android-dashboard-authenticated-after.png
adb -s emulator-5554 exec-out screencap -p > docs/parity-screenshots/android-add-vehicle-top-after.png
adb -s emulator-5554 exec-out screencap -p > docs/parity-screenshots/android-add-expense-after.png
adb -s emulator-5554 exec-out screencap -p > docs/parity-screenshots/android-settings-after.png
adb -s emulator-5554 exec-out screencap -p > docs/parity-screenshots/android-settings-sections-after.png
adb -s emulator-5554 exec-out screencap -p > docs/parity-screenshots/android-settings-business-after.png
adb -s emulator-5554 exec-out screencap -p > docs/parity-screenshots/android-settings-sync-after.png
adb -s emulator-5554 exec-out screencap -p > docs/parity-screenshots/android-data-health-after.png
adb -s emulator-5554 exec-out screencap -p > docs/parity-screenshots/android-financial-accounts-after.png
adb -s emulator-5554 exec-out screencap -p > docs/parity-screenshots/android-vehicles-after.png
adb -s emulator-5554 exec-out screencap -p > docs/parity-screenshots/android-add-vehicle-inventory-id-after.png
adb -s emulator-5554 exec-out screencap -p > docs/parity-screenshots/android-vehicle-detail-after.png
adb -s adb-6DVGOFPVNBM7LNMR-htEvLr._adb-tls-connect._tcp exec-out screencap -p > docs/parity-screenshots/android-dashboard-car-after.png
adb -s adb-6DVGOFPVNBM7LNMR-htEvLr._adb-tls-connect._tcp exec-out screencap -p > docs/parity-screenshots/android-settings-dashboard-car-after.png
adb -s emulator-5554 exec-out screencap -p > docs/parity-screenshots/android-region-selection-after.png
adb -s emulator-5554 exec-out screencap -p > docs/parity-screenshots/android-login-after-region.png
adb shell input keyevent 224
adb shell wm dismiss-keyguard
adb shell dumpsys window policy
./gradlew :app:testDebugUnitTest --console=plain
./gradlew :app:assembleDebug --console=plain
adb -s emulator-5554 install -r app/build/outputs/apk/debug/app-debug.apk
adb -s emulator-5554 shell am force-stop com.ezcar24.business.debug
adb -s emulator-5554 shell am start -W -n com.ezcar24.business.debug/com.ezcar24.business.MainActivity
adb -s emulator-5554 exec-out screencap -p > ../docs/parity-screenshots/android-paywall-after.png
adb -s emulator-5554 logcat -d -b crash
./gradlew :app:assembleDebug --console=plain
awk -F'"' '/REVENUECAT_ANDROID_API_KEY/ { status=($2=="" ? "blank" : "present"); prefix=($2=="" ? "" : substr($2,1,5)); print "generated BuildConfig: " status ", length=" length($2) (prefix=="" ? "" : ", prefix=" prefix) }' "app/build/generated/source/buildConfig/debug/com/ezcar24/business/BuildConfig.java"
curl -sS -H "Authorization: Bearer <redacted-android-revenuecat-key>" -H "X-Platform: android" "https://api.revenuecat.com/v1/subscribers/%24RCAnonymousID%3Acodex-parity-check/offerings"
ANDROID_AVD_HOME=/Volumes/LexarDev/Developer/SDKs/Android/avd emulator -list-avds
adb install -r "Android Car Dealer Tracker/app/build/outputs/apk/debug/app-debug.apk"
adb shell am start -W -n com.ezcar24.business.debug/com.ezcar24.business.MainActivity
adb logcat -d | rg -i "RevenueCat|SubscriptionManager|offerings|purchases|billing|StoreProduct|ProductDetails|CustomerInfo"
adb shell ping -c 1 api.revenuecat.com
PYTHONPATH=/Volumes/LexarDev/Developer/Temp/ezcar24-play-status-deps /Users/shokhabbos/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 scripts/play_release_status.py
```

XcodeBuildMCP:

```text
session_show_defaults
list_sims
session_set_defaults(projectPath: iOS Car Dealer Tracker/Ezcar24Business.xcodeproj, scheme: Ezcar24Business, simulator: iPhone 17 Pro)
build_run_sim
snapshot_ui
screenshot
```

iOS targeted regression:

```bash
cd "/Volumes/LexarDev/Developer/Projects/CarDealerTracker/iOS Car Dealer Tracker"
xcodebuild test -project "Ezcar24Business.xcodeproj" -scheme Ezcar24Business -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /Volumes/LexarDev/Developer/DerivedData/CarDealerTracker-PaywallParity -only-testing:Ezcar24BusinessTests/Ezcar24BusinessRegressionTests/testSubscriptionAccessPolicyGatesThirdFreeVehicle
```
