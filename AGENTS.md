# AGENTS.md

## Overview

CarDealerTracker is a multi-platform car dealer management app with Android (Kotlin/Compose), iOS (Swift/SwiftUI), and Supabase backend.

---

## Build Commands

### Android (Kotlin)
```bash
# Build the project
cd "Android Car Dealer Tracker"
./gradlew build

# Build specific variant (debug/release)
./gradlew assembleDebug
./gradlew assembleRelease

# Run unit tests
./gradlew test

# Run specific test class
./gradlew test --tests "com.example.cardealertrackerandroid.ExampleUnitTest"

# Run specific test method
./gradlew test --tests "com.example.cardealertrackerandroid.ExampleUnitTest.addition_isCorrect"

# Run instrumented tests (requires connected device/emulator)
./gradlew connectedAndroidTest

# Run instrumented test class
./gradlew connectedAndroidTest --tests "com.example.cardealertrackerandroid.ExampleInstrumentedTest"

# Run connected tests on specific device
./gradlew connectedAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.example.cardealertrackerandroid.ExampleInstrumentedTest

# Clean build
./gradlew clean

# Check dependencies
./gradlew dependencies
```

### iOS (Swift)
```bash
# Build the project
cd "iOS Car Dealer Tracker"
xcodebuild -project Ezcar24Business.xcodeproj -scheme Ezcar24Business build

# Build for testing
xcodebuild -project Ezcar24Business.xcodeproj -scheme Ezcar24Business -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build-for-testing

# Run all tests
xcodebuild test -project Ezcar24Business.xcodeproj -scheme Ezcar24Business -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Run specific test
xcodebuild test -project Ezcar24Business.xcodeproj -scheme Ezcar24Business -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:Ezcar24BusinessTests/ExampleTest/testExample
```

### Supabase Functions
```bash
# Deploy all functions
cd supabase
supabase functions deploy

# Deploy specific function
supabase functions deploy accept_invite
supabase functions deploy invite_member
supabase functions deploy request_password_reset

# Run functions locally
supabase functions serve

# Apply migrations
supabase db push

# Generate TypeScript types
supabase gen types typescript
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
- Extensions: `Type+Category.swift` format
- CoreData models: auto-generated with `+CoreDataClass`/`+CoreDataProperties`

#### Type System
- Use `struct` for value types (Views), `class` for reference types with identity (ViewModels)
- `@Published` for ObservableObject properties
- `@StateObject`, `@ObservedObject`, `@EnvironmentObject` for state management
- Optional types: `Type?`, optional chaining `?.`, nil-coalescing `??`
- Force unwrap `!` only when guaranteed non-nil (rare)
- CoreData: `@NSManaged` properties, `FetchedResults` for queries

#### Import Order
```swift
// Foundation (import Foundation)
// SwiftUI (import SwiftUI)
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
- @MainActor for ViewModels (UI updates on main thread)
- Combine: `$property` publisher, `.sink { }` subscribers, `@Published` for changes
- CoreData: `@FetchRequest`, `NSManagedObjectContext`, `PersistenceController`

#### SwiftUI Guidelines
- Views: `struct`, `@ViewBuilder` for complex layouts
- Modifiers: chaining order: data -> layout -> style -> behavior
- Navigation: `NavigationStack` (iOS 16+), `.navigationTitle`, `.toolbar`
- Sheet/fullScreenCover: `@State private var showingSheet = false`
- Environment: `@Environment(\.managedObjectContext)`, `@EnvironmentObject`

#### Comments
- Header comment with purpose (no inline comments unless explicit)

---

## Common Patterns

### Localization
- iOS: Use `"key".localizedString` extension from `String+Localization.swift`
- Manual localization with `RegionSettingsManager.shared.selectedLanguage`
- Android: Standard `stringResources` with separate values folders

### Date/Time
- Kotlin: Use `DateUtils` object for ISO 8601 parsing (`parseIso8601`, `formatIso8601`)
- Swift: `Date` with `DateFormatter`, ISO 8601 format

### Monetary Values
- Kotlin: `BigDecimal` for precision, `BigDecimalSerializer` for JSON
- Swift: `Decimal` type, `CurrencyFormatter` utility

### UUID
- Both platforms use `UUID` (UUID in Kotlin, UUID in Swift) for primary keys
- Kotlin: `UUID.randomUUID()`, `UUID.fromString(string)`
- Swift: `UUID()`, `UUID(uuidString:)`

### Soft Deletes
- Both: `deletedAt: Date?` nullable field
- Filter out records where `deletedAt != null`

### Sync Pattern
- Local-first with Supabase cloud sync
- `CloudSyncManager` handles bidirectional sync
- Sync queue for offline operations
- Conflict resolution: server wins for conflicts

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
├── Views/              # SwiftUI views
├── ViewModels/         # ObservableObject ViewModels
├── Models/             # CoreData models
├── Services/           # Supabase, sync, permissions
├── Auth/               # Authentication
├── Config/             # Configuration
├── Utilities/          # Extensions, formatters
└── Assets.xcassets     # Images, colors
```

---

## Testing Notes

### Android
- Unit tests: `app/src/test/`
- Instrumented tests: `app/src/androidTest/`
- Use JUnit 4, standard assertions `assertEquals`, `assertTrue`
- Run single test: `./gradlew test --tests "full.package.name.TestClassName.testMethodName"`

### iOS
- XCTest framework
- Add test target to Xcode project for new tests
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
- Supabase Swift SDK 2.37.0
- RevenueCat 5.48.0 for subscriptions
- Firebase 12.7.0 for remote config/analytics

---

## Important Notes

- No comments in code unless explicitly asked
- Supabase credentials are hardcoded in `AppModule.kt` (move to BuildConfig)
- Android uses `fallbackToDestructiveMigration()` for development
- CoreData models are auto-generated, don't edit manually
- Both platforms use dealer-based multi-tenancy via `CloudSyncEnvironment.currentDealerId`
- Sync is bi-directional with conflict resolution favoring server
- Offline-first architecture with sync queue
