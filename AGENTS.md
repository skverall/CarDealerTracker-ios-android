# AGENTS.md

## Overview

CarDealerTracker (Ezcar24Business) is a multi-platform car dealer management app with Android (Kotlin/Compose), iOS (Swift/SwiftUI), and Supabase backend. It provides vehicle inventory tracking, expense management, sales recording, CRM, parts inventory, financial accounts, team management, analytics, and subscription-based monetization.

---

## ⛔ Backward Compatibility & Production Safety (MANDATORY)

This project has **active dealers in production** relying on the Supabase backend and client apps daily. Any change — no matter how small — **MUST NOT** break existing functionality for current users. Violations of these rules can cause financial data corruption and loss of dealer trust.

### Database & Backend Rules
1. **NEVER alter existing Supabase tables, columns, RPC functions, or RLS policies** in a way that changes behavior for existing data. Adding new columns or functions is allowed; modifying or removing existing ones is **PROHIBITED** without explicit user approval.
2. **NEVER rename or remove database columns, tables, or RPC parameters.** Existing clients depend on the current schema. If a column needs to change, add a new one and migrate data — never drop or rename in place.
3. **NEVER change Supabase Edge Function request/response contracts.** Older app versions in the wild still call these functions. Any change must be additive and backward-compatible.
4. **NEVER modify RLS (Row Level Security) policies** unless explicitly asked. Incorrect RLS changes can expose one dealer's data to another or lock dealers out of their own data.
5. **NEVER change Supabase Auth configuration, redirect URLs, or JWT settings.** This will immediately lock out all active users.

### Calculation & Formula Rules
6. **NEVER modify existing financial calculation formulas** (profit, expenses, holding costs, VAT refund, debt balances, account balances) without explicit user approval. Existing dealers rely on consistent numbers — changing a formula silently means their historical reports and dashboards will show different values after an app update.
7. **Before changing any calculator** (`VehicleFinancialsCalculator`, `HoldingCostCalculator`, `InventoryMetricsCalculator`, `LeadScoringEngine`, `DashboardViewModel` aggregations), **verify** that the change produces identical results for existing data and only differs for new scenarios.
8. **NEVER change the sync conflict resolution strategy** (server wins). Changing this can cause data loss or duplication for dealers with multiple team members.

### Data Migration Rules
9. **All database migrations MUST be additive and non-destructive.** Use `ALTER TABLE ... ADD COLUMN` with `DEFAULT` values; never use `DROP COLUMN`, `ALTER COLUMN TYPE`, or `TRUNCATE`.
10. **NEVER write migrations that update or transform existing dealer data** without explicit user approval. A migration that "fixes" old data can silently change financial records that dealers have already acted on.
11. **Test migrations against the existing schema** — ensure they are idempotent and safe to re-run.

### Sync & Data Integrity Rules
12. **NEVER change the `RemoteSnapshot` struct fields or `CodingKeys`** without also verifying backward compatibility with existing Supabase RPC responses. Mismatches cause full sync failures.
13. **NEVER change `SyncQueueItem` serialization format.** Dealers may have pending items in the offline queue — changing the format will lose those items on next app launch.
14. **NEVER modify `CloudSyncManager.parseRemoteExpenseDate` / `encodeRemoteExpenseDate`** without verifying all legacy and post-migration date formats still parse correctly.

### General Safety Checklist
Before making any backend or calculation change, **always verify:**
- [ ] Existing Supabase RPC functions still return the same shape for existing data
- [ ] All existing `Remote*` Codable models still decode correctly
- [ ] Financial totals (profit, expenses, balances) remain identical for existing records
- [ ] Sync (full and incremental) still works without errors
- [ ] Existing Edge Functions remain callable with the same parameters
- [ ] No existing database constraint, index, or trigger is broken

> **When in doubt — ASK before changing.** It is always better to ask than to silently alter production data or calculations.

---

## Build Commands

### Android (Kotlin)
```bash
cd "Android Car Dealer Tracker"

./gradlew build                # Full build
./gradlew assembleDebug        # Debug variant
./gradlew assembleRelease      # Release variant
./gradlew clean                # Clean build
./gradlew dependencies         # Check dependencies

# Unit tests
./gradlew test
./gradlew test --tests "com.example.cardealertrackerandroid.ExampleUnitTest"
./gradlew test --tests "com.example.cardealertrackerandroid.ExampleUnitTest.addition_isCorrect"

# Instrumented tests (requires device/emulator)
./gradlew connectedAndroidTest
./gradlew connectedAndroidTest --tests "com.example.cardealertrackerandroid.ExampleInstrumentedTest"
```

### iOS (Swift)
```bash
cd "iOS Car Dealer Tracker"

# Build
xcodebuild -project Ezcar24Business.xcodeproj -scheme Ezcar24Business build

# Build for testing
xcodebuild -project Ezcar24Business.xcodeproj -scheme Ezcar24Business \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build-for-testing

# Run all tests
xcodebuild test -project Ezcar24Business.xcodeproj -scheme Ezcar24Business \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Run specific test
xcodebuild test -project Ezcar24Business.xcodeproj -scheme Ezcar24Business \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:Ezcar24BusinessTests/Ezcar24BusinessRegressionTests/testExpenseDateSortUsesCreationTimeForSameDayRecords
```

### Supabase Functions
```bash
cd supabase

supabase functions deploy              # Deploy all functions
supabase functions deploy accept_invite
supabase functions deploy invite_member
supabase functions deploy request_password_reset
supabase functions deploy delete_account
supabase functions deploy monthly_report_dispatch
supabase functions deploy revenuecat_webhook
supabase functions deploy vehicle_share

supabase functions serve               # Run locally
supabase db push                       # Apply migrations
supabase gen types typescript          # Generate TS types
```

---

## Code Style Guidelines

### Kotlin (Android)

#### File Organization
- Package declaration at top, followed by imports grouped and sorted alphabetically
- Use single blank line between import groups: standard library, third-party, project imports
- Two blank lines before class declarations

#### Naming Conventions
- Classes: PascalCase (`VehicleViewModel`, `AppDatabase`)
- Functions: camelCase (`loadVehicles`, `saveVehicle`)
- Variables/properties: camelCase with private fields prefixed with underscore for mutable state (`_uiState`)
- Constants: UPPER_SNAKE_CASE (`SUPABASE_URL`)
- Data classes: noun-based (`VehicleUiState`, `VehicleWithFinancials`)

#### Type System
- Use `data class` for immutable models (Room entities are exceptions with var)
- Use `sealed class/interface` for restricted hierarchies
- Prefer `val` over `var` for immutability
- Use `UUID` for primary keys, `BigDecimal` for monetary values
- Nullable types with `?`, use `!!` only when guaranteed non-null
- Define default values in data class constructors (`deletedAt: Date? = null`)

#### Import Order
```kotlin
// Standard library (java.*, kotlin.*)
// AndroidX (androidx.*)
// Third-party (io.github.jan.supabase.*, dagger.*, coil.*)
// Project imports (com.ezcar24.*)
```

#### Error Handling
- Use `try-catch` with proper logging via `Log.e(tag, "message", exception)`
- Use `requireNotNull` or `checkNotNull` for validation
- Coroutines: handle exceptions in `viewModelScope.launch` with try-catch
- Prefer Result type for operations that may fail

#### Architecture Patterns
- MVVM: ViewModel with `@HiltViewModel`, UI state in `StateFlow`/`MutableStateFlow`
- Dependency Injection: Hilt modules in `di/` package
- Repository pattern for data access
- Flow-based reactive data: observe DAO flows, update state via `_uiState.update`

#### Compose Guidelines
- Composable functions: PascalCase (`VehicleListScreen`)
- Parameters with defaults: `onNavigateToAddVehicle: () -> Unit = {}`
- Use `@OptIn` for experimental APIs
- Material3: `MaterialTheme.typography`, `MaterialTheme.colorScheme`
- State: `LaunchedEffect` for one-time effects, `remember` for local state

#### Comments
- No comments unless explicitly asked (project rule)
- KDoc only for public APIs

---

### Swift (iOS)

#### File Organization
- Header comment with file name, project name, brief description
- Import statements: Foundation, SwiftUI, then custom modules alphabetically
- Use `// MARK: -` to organize sections

#### Naming Conventions
- Classes/Structs: PascalCase (`VehicleViewModel`, `VehicleListView`)
- Functions: camelCase (`fetchVehicles`, `saveVehicle`)
- Variables/properties: camelCase (`searchText`, `selectedStatus`)
- Constants: camelCase with `let` (`private let context`)
- Extensions: `Type+Category.swift` format (`String+Localization.swift`, `Expense+Extensions.swift`)
- CoreData models: auto-generated with `+CoreDataClass`/`+CoreDataProperties`
- Supabase models: `Remote` prefix (`RemoteVehicle`, `RemoteExpense`, `RemoteSale`)

#### Type System
- Use `struct` for value types (Views, Supabase models), `class` for reference types with identity (ViewModels, managers)
- `@Published` for ObservableObject properties
- `@StateObject`, `@ObservedObject`, `@EnvironmentObject` for state management
- Optional types: `Type?`, optional chaining `?.`, nil-coalescing `??`
- Force unwrap `!` only when guaranteed non-nil (rare)
- CoreData: `@NSManaged` properties, `FetchedResults` for queries
- `Decimal` / `NSDecimalNumber` for all monetary values
- `UUID` for all primary keys, `Date` for timestamps

#### Import Order
```swift
// Foundation (import Foundation)
// SwiftUI (import SwiftUI)
// System frameworks (import CoreData, import Network, import UserNotifications)
// Third-party (import Supabase, import RevenueCat, import FirebaseCore)
// Local modules (no imports, use same target)
```

#### Error Handling
- Use `do-catch` for throwing functions
- `try?` for optional result, `try!` only when guaranteed success
- Log errors with `print("Error: \(error)")`
- CoreData: `try context.save()` with catch

#### Architecture Patterns
- MVVM: ViewModel with `ObservableObject`, View with SwiftUI
- `@MainActor` for ViewModels and all `ObservableObject` managers (UI updates on main thread)
- Singleton services: `static let shared` pattern (`PermissionService.shared`, `ImageStore.shared`, `SubscriptionManager.shared`, `RegionSettingsManager.shared`, `LocalNotificationManager.shared`)
- Environment objects: `SessionStore`, `CloudSyncManager`, `NetworkMonitor`, `RegionSettingsManager` injected at app root
- CoreData: `PersistenceController.shared` with per-organization store isolation (`setActiveStore(organizationId:)`)
- Supabase client: `SupabaseClientProvider` loads config from `SupabaseConfig.plist` or env vars

#### SwiftUI Guidelines
- Views: `struct`, `@ViewBuilder` for complex layouts
- Modifiers: chaining order: data -> layout -> style -> behavior
- Navigation: `NavigationStack` (iOS 16+), `.navigationTitle`, `.toolbar`
- Sheet/fullScreenCover: `@State private var showingSheet = false`
- Environment: `@Environment(\.managedObjectContext)`, `@EnvironmentObject`
- Custom tab bar: system `UITabBar` hidden, custom floating capsule with `ultraThinMaterial`
- iPad: `UIDevice.current.userInterfaceIdiom == .pad` check, separate `iPadRootView`
- Haptics: `UIImpactFeedbackGenerator(style: .light)` on tab/button taps
- Animations: `.snappy(duration: 0.28, extraBounce: 0.04)` as primary transition

#### Comments
- No comments in code unless explicitly asked (project rule)
- Header comment with file name and purpose only

---

## Common Patterns

### Localization
- iOS: Use `"key".localizedString` extension from `String+Localization.swift`
- Manual localization with `RegionSettingsManager.shared.selectedLanguage`
- Bypasses `Bundle.main` default to enable immediate in-app language switching without restart
- Supported languages: English (`en`), Russian (`ru`), Arabic (`ar`), Korean (`ko`)
- `Localizable.xcstrings` for translation storage
- Android: Standard `stringResources` with separate values folders

### Multi-Region Support
- iOS: `AppRegion` enum supports 10 regions: UAE, USA, Canada, UK, Europe, Russia, Turkey, Japan, India, Korea
- Each region defines: `currencyCode`, `currencySymbol`, `localeIdentifier`, `usesKilometers`, `currencyDecimals`
- `RegionSettingsManager` manages region, language, formatters; persisted via `UserDefaults`
- Feature toggle: `isPartsEnabled` setting to hide Parts tab per dealer preference
- First launch shows `RegionSelectionSheet` via `fullScreenCover`

### Monetary Values
- Kotlin: `BigDecimal` for precision, `BigDecimalSerializer` for JSON
- Swift: `Decimal` / `NSDecimalNumber` for CoreData, `CurrencyFormatter` utility
- Use `value.asCurrency()` and `value.asCurrencyCompact()` extensions (MainActor)
- Use `value.asCurrencyFallback()` for nonisolated contexts (reads region from UserDefaults directly)

### Date/Time
- Kotlin: Use `DateUtils` object for ISO 8601 parsing (`parseIso8601`, `formatIso8601`)
- Swift: `Date` with `ISO8601DateFormatter`, expense dates use special parsing logic
- Remote models use `Date` (auto-decoded) or `String` (manual ISO 8601 parsing) for dates
- Expense timestamps: `CloudSyncManager.parseRemoteExpenseDate` / `encodeRemoteExpenseDate` handles legacy vs post-migration formats
- Calendar dates (purchase date, sale date, debt due): `encodeRemoteCalendarDate` → `YYYY-MM-DD` format

### UUID
- Both platforms use `UUID` for primary keys
- Kotlin: `UUID.randomUUID()`, `UUID.fromString(string)`
- Swift: `UUID()`, `UUID(uuidString:)`

### Soft Deletes
- Both: `deletedAt: Date?` nullable field
- Filter out records where `deletedAt != null`

### Sync Pattern
- Local-first with Supabase cloud sync via `CloudSyncManager`
- `CloudSyncManager.shared` — singleton set during app init
- Bidirectional sync: pull via `RemoteSnapshot` (bulk RPC), push via `SyncQueueManager`
- `SyncQueueManager` — actor-based, file-persisted queue with retry/backoff/dead-letter logic
- Queue compaction: repeated upserts for same record are deduplicated, delete supersedes queued upsert
- Sync strategies: `.full` (first sync) and `.incremental` (subsequent)
- Auto-sync on `scenePhase == .active` with throttling via `shouldRunAutoSync` policy
- Sync HUD: `syncHUDState` enum (`.syncing`, `.success`, `.failure`) drives overlay UI
- Diagnostics: `SyncDiagnosticsReport` with health status (`.healthy`, `.degraded`, `.blocked`)
- Conflict resolution: server wins for conflicts

### Multi-Tenancy (Organizations)
- Organization-based multi-tenancy via `SessionStore.activeOrganizationId`
- `CloudSyncEnvironment.currentDealerId` resolves active dealer
- CoreData: `PersistenceController` maintains separate SQLite stores per organization (`Stores/<orgId>/Ezcar24Business.sqlite`)
- `ImageStore` namespaces images by dealer: `Documents/VehicleImages/<dealerId>/`
- `PermissionService` fetches role-based permissions per organization via `get_my_permissions` RPC
- Organization switching: `switchOrganization(to:)` reloads context, permissions, and triggers sync

### Permission System
- Role-based: `owner`, `admin`, `sales`, `viewer`
- Permission keys: `viewFinancials`, `viewExpenses`, `viewInventory`, `createSale`, `viewPartsInventory`, `managePartsInventory`, `createPartSale`, `manageTeam`, `viewLeads`, `viewVehicleCost`, `viewVehicleProfit`, `viewPartCost`, `viewPartProfit`, `deleteRecords`
- `PermissionService.shared.can(.permissionKey)` to gate access
- `PermissionCatalog.resolvedPermissions` merges server overrides with role defaults
- UI gating: `RestrictedAccessView` shown when permission denied, `PermissionLoadingView` while loading
- Permissions cached in `UserDefaults` for instant UI on next launch

### Authentication
- Supabase Auth via `SessionStore` — email/password sign-in/sign-up
- `AuthGateView` — top-level auth gate, guest mode supported
- `AppSessionState` — manages login form state (email, password, mode, validation)
- Deep link handling: `com.ezcar24.business://login-callback` and `https://ezcar24.com/login-callback`
- Password recovery: edge function `request_password_reset`, recovery flow via deep link
- Account deletion: edge function `delete_account`
- RevenueCat linked on login: `SubscriptionManager.shared.logIn(userId:)`

### Subscription / Monetization
- RevenueCat SDK for in-app purchases (`SubscriptionManager`)
- Pro access: `isProAccessActive` — checks RevenueCat entitlements OR referral bonus
- Referral system: `getDealerReferralCode`, `claimPendingReferralIfPossible`, bonus extends pro access
- `PaywallView` for subscription offers
- `canUseRevenueCat` guard — all RevenueCat calls check `Purchases.isConfigured` to avoid crashes in tests

### Image Management
- `ImageStore` — singleton for vehicle photo persistence + in-memory `NSCache`
- Stores JPEG images under `Documents/VehicleImages/<dealerId>/<vehicleId>.jpg`
- Multi-photo: `Documents/VehicleImages/<dealerId>/<vehicleId>/<photoId>.jpg`
- Background IO via dedicated `DispatchQueue`, images auto-scaled and compressed (max 1600px, 0.8 quality)
- `CGImageSource` downsampling for thumbnails via `targetSize` parameter
- Supabase Storage for cloud photo sync (multi-photo gallery with `RemoteVehiclePhoto`)

### Remote Config & Force Update
- `RemoteConfigService` — checks App Store version + Supabase `get_app_config` RPC
- Kill switch: `min_version`, `force_update`, `block_level`, `maintenance_mode`
- `ForceUpdateView` shown via `fullScreenCover` when update required

### Local Notifications
- `LocalNotificationManager` — singleton, `UNUserNotificationCenterDelegate`
- Types: client reminders, debt due dates, daily expense reminder (8 PM), inventory digest alerts
- Inventory digest: groups stale vehicles (above configurable threshold), deduplicates by signature
- Refreshed on app launch and `scenePhase == .active`

### Network Monitoring
- `NetworkMonitor` — `NWPathMonitor` wrapped in `ObservableObject`
- `isConnected` published property, injected as `@EnvironmentObject`

### Backup / Export
- `BackupExportManager` — Excel/CSV export of dealer data
- `MonthlyReportSnapshotBuilder` + `MonthlyReportPreviewView` — PDF monthly reports
- `monthly_report_dispatch` edge function for scheduled reports

### Analytics / Calculators
- `InventoryMetricsCalculator` — inventory health, turnover, aging analysis
- `HoldingCostCalculator` — daily holding cost per vehicle
- `VehicleFinancialsCalculator` — profit/loss per vehicle
- `LeadScoringEngine` — CRM lead scoring
- `AnalyticsHubView`, `InventoryAnalyticsView` — analytics dashboards

---

## Project Structure

### Android
```
app/src/main/java/com/ezcar24/business/
├── data/
│   ├── local/          # Room entities and DAOs
│   ├── repository/     # Data repositories
│   └── sync/           # Supabase sync logic
├── di/                 # Hilt dependency injection modules
├── notification/       # Notification handling
├── ui/
│   ├── vehicle/        # Vehicle screens and ViewModels
│   ├── dashboard/      # Dashboard
│   ├── expense/        # Expense tracking
│   ├── finance/        # Financial accounts and debts
│   ├── client/         # Client/CRM
│   ├── sale/           # Sales
│   ├── auth/           # Authentication
│   ├── settings/       # Settings
│   ├── theme/          # Compose theme
│   └── main/           # Navigation shell
├── worker/             # Background workers
└── util/               # Utilities, extensions
```

### iOS
```
Ezcar24Business/
├── Ezcar24BusinessApp.swift       # @main entry point, DI wiring
├── ContentView.swift              # Tab navigation, custom tab bar, overlays
├── Auth/
│   ├── AppSessionState.swift      # Login form state machine
│   ├── AuthGateView.swift         # Auth gate + guest mode + auto-sync
│   ├── LoginView.swift            # Login/signup UI
│   ├── PasswordResetView.swift    # Password recovery flow
│   ├── SessionStore.swift         # Auth session, orgs, invites, referrals
│   └── SupabaseClientProvider.swift # Supabase client init from plist/env
├── Config/
│   └── Supabase.xcconfig          # Build config for Supabase credentials
├── Models/
│   ├── Ezcar24Business.xcdatamodeld # CoreData model
│   ├── PersistenceController.swift  # CoreData stack, per-org stores
│   ├── Enums/                       # AgingBucket, ExpenseCategoryType, InteractionType, etc.
│   ├── *+CoreDataClass.swift        # Auto-generated entity classes
│   ├── *+CoreDataProperties.swift   # Auto-generated entity properties
│   └── *+Extensions.swift           # Manual entity extensions (computed props)
├── Services/
│   ├── CloudSyncManager.swift       # Bidirectional sync engine (~210KB)
│   ├── CloudSyncEnvironment.swift   # currentDealerId resolution
│   ├── SupabaseModels.swift         # Remote* Codable structs for Supabase
│   ├── PermissionService.swift      # Role-based permission system
│   ├── SubscriptionManager.swift    # RevenueCat subscription management
│   ├── RemoteConfigService.swift    # Force update / kill switch
│   ├── LocalNotificationManager.swift # Local push notifications
│   ├── InventoryStatsManager.swift  # Inventory statistics
│   ├── BackupExportManager.swift    # Data export (Excel/CSV)
│   ├── MonthlyReportSnapshotBuilder.swift # PDF report generation
│   ├── MonthlyReportSupport.swift   # Report helpers
│   ├── AppReviewManager.swift       # App Store review prompts
│   ├── RevenueCatKeyProvider.swift   # API key provider
│   ├── CoreDataExtensions.swift     # Fetch request helpers
│   ├── Calculators/
│   │   ├── HoldingCostCalculator.swift
│   │   ├── InventoryMetricsCalculator.swift
│   │   ├── LeadScoringEngine.swift
│   │   └── VehicleFinancialsCalculator.swift
│   └── Notion/                      # (empty, reserved)
├── ViewModels/
│   ├── DashboardViewModel.swift     # Dashboard aggregations (~46KB)
│   ├── VehicleViewModel.swift       # Vehicle CRUD
│   ├── ExpenseViewModel.swift       # Expense CRUD, search debounce, snapshots
│   ├── SalesViewModel.swift         # Sales CRUD
│   ├── ClientViewModel.swift        # CRM client management
│   ├── DebtViewModel.swift          # Debt tracking
│   ├── FinancialAccountsViewModel.swift
│   ├── AccountTransactionsViewModel.swift
│   ├── PartsInventoryViewModel.swift
│   ├── PartSalesViewModel.swift
│   ├── InventoryAnalyticsViewModel.swift
│   ├── HoldingCostSettingsViewModel.swift
│   └── UserViewModel.swift          # Dealer user management
├── Views/
│   ├── DashboardView.swift          # Main dashboard (~77KB)
│   ├── VehicleListView.swift        # Vehicle inventory list
│   ├── VehicleDetailView.swift      # Vehicle detail (~145KB, largest view)
│   ├── AddVehicleView.swift         # Add/edit vehicle
│   ├── ExpenseListView.swift        # Expense dashboard (~69KB)
│   ├── AddExpenseView.swift         # Add/edit expense
│   ├── SalesListView.swift          # Sales list
│   ├── AddSaleView.swift            # Record sale
│   ├── ClientListView.swift         # CRM client list
│   ├── ClientDetailView.swift       # Client detail with interactions
│   ├── AccountView.swift            # Account/profile screen (~65KB)
│   ├── TeamManagementView.swift     # Team/org management
│   ├── PaywallView.swift            # Subscription paywall
│   ├── PartsDashboardView.swift     # Parts inventory
│   ├── AddPartView.swift / AddPartSaleView.swift
│   ├── DebtsListView.swift / DebtDetailView.swift / AddDebtView.swift
│   ├── FinancialAccountsView.swift / AddFinancialAccountView.swift
│   ├── GlobalSearchView.swift       # Universal search
│   ├── RegionSelectionView.swift    # Region/language picker
│   ├── BackupCenterView.swift       # Data export
│   ├── DataHealthView.swift         # Sync diagnostics
│   ├── MonthlyReportPreviewView.swift / MonthlyReportSettingsView.swift
│   ├── ForceUpdateView.swift        # Force update blocker
│   ├── UserGuideView.swift          # In-app help
│   ├── iPadRootView.swift           # iPad sidebar layout
│   ├── Analytics/
│   │   └── AnalyticsHubView.swift   # Analytics dashboard
│   ├── Inventory/
│   │   └── InventoryAnalyticsView.swift
│   ├── Components/
│   │   ├── DashboardComponents.swift # Reusable dashboard cards
│   │   ├── SyncHUDOverlay.swift     # Sync status HUD
│   │   ├── ToastView.swift          # Error/success toast
│   │   ├── VehicleSelectionSheet.swift
│   │   ├── DaysSincePurchaseView.swift
│   │   └── Inventory/              # AgingBucketBadge, ROIBadge, HoldingCostIndicator, etc.
│   └── Settings/
│       └── HoldingCostSettingsView.swift
├── Utilities/
│   ├── ColorTheme.swift             # Design tokens, CardModifier, HapticScaleButtonStyle
│   ├── CurrencyFormatter.swift      # Currency formatting + Decimal extensions
│   ├── RegionSettings.swift         # AppRegion, AppLanguage, RegionSettingsManager
│   ├── String+Localization.swift    # Manual localization for instant language switch
│   ├── ImagePicker.swift            # UIImagePickerController wrapper
│   ├── ImageStore.swift             # Vehicle photo persistence + NSCache
│   ├── ShareSheet.swift             # UIActivityViewController wrapper
│   ├── ShareLinkItemSource.swift    # Share link helper
│   ├── YearFormatter.swift          # Year formatting utility
│   └── FinancialAccountKind+UI.swift
├── Assets.xcassets                  # Images, colors
├── SupabaseConfig.plist             # Supabase URL + anon key
├── GoogleService-Info.plist         # Firebase config
├── Info.plist                       # App config, URL schemes
├── Ezcar24Business.entitlements     # App entitlements
└── Localizable.xcstrings            # All translations (~400KB)
```

### Supabase
```
supabase/
├── config.toml                      # Project config
├── functions/
│   ├── accept_invite/               # Accept team invitation
│   ├── delete_account/              # Account deletion
│   ├── invite_member/               # Send team invitation
│   ├── monthly_report_dispatch/     # Scheduled report emails
│   ├── request_password_reset/      # Custom password reset
│   ├── revenuecat_webhook/          # RevenueCat event handler
│   └── vehicle_share/               # Vehicle share links
├── migrations/                      # Database migrations
└── tests/                           # Function tests
```

---

## Testing Notes

### Android
- Unit tests: `app/src/test/`
- Instrumented tests: `app/src/androidTest/`
- Use JUnit 4, standard assertions `assertEquals`, `assertTrue`
- Run single test: `./gradlew test --tests "full.package.name.TestClassName.testMethodName"`

### iOS
- XCTest framework in `Ezcar24BusinessTests/`
- Single comprehensive test file: `Ezcar24BusinessRegressionTests.swift` (~1,738 lines, 63KB)
- Tests use in-memory CoreData: `PersistenceController(inMemory: true)`
- `@MainActor` on test class for concurrency safety
- Tests cover: auth logic, sync queue (retry/backoff/dead-letter/compaction), expense date parsing, diagnostics, auto-sync policy, image store namespacing, subscription manager, dashboard debouncer
- Helper: `drainMainQueue()` for async UI testing
- RevenueCat not configured in tests — `Purchases.isConfigured` returns false, guarded by `canUseRevenueCat`
- Temporary file cleanup in `tearDownWithError`
- Run via Xcode or `xcodebuild test`

---

## Dependencies

### Android (see `gradle/libs.versions.toml`)
- Compose BOM 2024.09.03, Material3
- Supabase 3.0.1 with Postgrest, Auth, Storage
- Room 2.6.1 for local database
- Hilt 2.51.1 for DI
- Coil 2.7.0 for image loading
- Kotlin Serialization 1.7.3
- Kotlin 2.2.10

### iOS (see `Package.resolved`)
- Supabase Swift SDK 2.37.0 (Postgrest, Auth, Storage, Functions)
- RevenueCat 5.48.0 for subscriptions
- Firebase iOS SDK 12.7.0 (FirebaseCore, RemoteConfig, Analytics)
- Swift Crypto 4.1.0, Swift HTTP Types 1.5.1 (transitive)
- No CocoaPods — pure Swift Package Manager

---

## Important Notes

### General
- No comments in code unless explicitly asked
- Separate `DESIGN.md` exists as the single source of truth for colors, typography, spacing, and component patterns — always reference `DESIGN.md` when modifying UI
- Both platforms use dealer-based multi-tenancy via organization system
- Offline-first architecture with sync queue

### iOS-Specific
- Supabase credentials loaded from `SupabaseConfig.plist` (or env vars `SUPABASE_URL` / `SUPABASE_ANON_KEY`)
- CoreData models are auto-generated — don't edit `+CoreDataClass.swift` / `+CoreDataProperties.swift` manually
- CoreData uses automatic lightweight migration (`shouldMigrateStoreAutomatically = true`)
- Per-organization SQLite stores isolated under `ApplicationSupport/Ezcar24Business/Stores/<orgId>/`
- All `ObservableObject` managers use `@MainActor` for thread safety
- `CloudSyncManager.shared` is set during `Ezcar24BusinessApp.init()` — not a static singleton
- `SessionStoreEnvironment.shared` is a weak reference set during init
- RevenueCat configured in `Ezcar24BusinessApp.init()` with user ID from current session
- Firebase configured via `AppDelegate` (skipped during tests via `AppRuntime.isRunningTests`)
- Deep links: URL scheme `com.ezcar24.business://` and universal links `https://ezcar24.com/`
- Custom floating tab bar hides system `UITabBar` via `UITabBar.appearance().isHidden = true`
- Use `ColorTheme.xxx` for all colors — never hardcode hex inline
- Use `.cardStyle()` modifier for standard elevated cards
- Use `.buttonStyle(.hapticScale)` for interactive cards

### Android-Specific
- Supabase credentials are hardcoded in `AppModule.kt` (move to BuildConfig)
- Android uses `fallbackToDestructiveMigration()` for development
