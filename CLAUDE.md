# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CarDealerTracker (Ezcar24 Business) is a multi-platform car dealer management app for the UAE automotive market. It consists of:
- **Android app** — Kotlin + Jetpack Compose, Room, Hilt, Supabase SDK
- **iOS app** — Swift + SwiftUI, CoreData, Supabase Swift SDK
- **Web platform** (`Ezcar24business-dealers/uae-wheels-hub/`) — React + TypeScript + Vite + Tailwind + Radix/Shadcn
- **Supabase backend** — PostgreSQL with RLS, Edge Functions (Deno), Auth, Storage
- **Monorepo structure** — each platform is a separate top-level directory, all share one Supabase backend

## Build & Run Commands

### Android
```bash
cd "Android Car Dealer Tracker"
./gradlew assembleDebug          # Debug build
./gradlew assembleRelease        # Release build (needs keystore.properties)
./gradlew test                   # Unit tests
./gradlew test --tests "com.ezcar24.business.SomeTest.method"  # Single test
./gradlew connectedAndroidTest   # Instrumented tests (requires device)
./gradlew clean
```

### iOS
```bash
cd "iOS Car Dealer Tracker"
xcodebuild -project Ezcar24Business.xcodeproj -scheme Ezcar24Business build
xcodebuild test -project Ezcar24Business.xcodeproj -scheme Ezcar24Business \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
# Single test:
xcodebuild test ... -only-testing:Ezcar24BusinessTests/TestName/testMethod
```

### Web Platform
```bash
cd Ezcar24business-dealers/uae-wheels-hub
npm install
npm run dev                       # Dev server at localhost:5173
npm run build                     # Production build
npm run lint                      # ESLint
npm run test                      # Vitest unit tests
npm run test:e2e                  # Playwright E2E tests
npm run build:native              # Build + Capacitor sync for mobile
```

### Supabase
```bash
cd supabase
supabase functions deploy <fn>    # Deploy an edge function
supabase functions serve          # Run functions locally
supabase db push                  # Apply migrations
supabase gen types typescript     # Generate TypeScript types
```

Edge functions: `accept_invite`, `delete_account`, `invite_member`, `monthly_report_dispatch`, `request_password_reset`, `revenuecat_webhook`, `vehicle_share`

## Architecture

### Data Sync (core to all platforms)
- **Offline-first** with local database (Room on Android, CoreData on iOS)
- `CloudSyncManager` handles bidirectional sync with Supabase
- Pull changes via `lastSyncTimestamp`, push local changes to server
- Conflict resolution: server wins / last-write-wins
- Sync queue for offline operations
- Dealer-based multi-tenancy via `CloudSyncEnvironment.currentDealerId`

### Android (package: `com.ezcar24.business`)
- **MVVM** with `@HiltViewModel`, `StateFlow`/`MutableStateFlow` for UI state
- **Hilt** DI modules in `di/` package
- **Room** for local DB, entities in `data/local/`, DAOs expose `Flow` for reactive queries
- **Repository pattern** in `data/repository/` — mediates between local DB and Supabase
- Compose UI in `ui/` organized by feature: `vehicle/`, `dashboard/`, `expense/`, `finance/`, `client/`, `sale/`, `auth/`, `settings/`
- Background workers in `worker/`
- `BigDecimal` for monetary values, `UUID` for primary keys
- Soft deletes via `deletedAt: Date?`

### iOS
- **MVVM** with `ObservableObject` ViewModels, `@MainActor`
- **CoreData** with `@FetchRequest`, `NSManagedObjectContext`, `PersistenceController`
- SwiftUI views in `Views/`, ViewModels in `ViewModels/`, services in `Services/`
- `Decimal` for monetary values
- CoreData models are auto-generated (`+CoreDataClass`/`+CoreDataProperties`) — do not edit manually

### Web Platform
- React + TypeScript + Vite + Tailwind CSS
- TanStack Query (React Query) for server state
- Radix UI / Shadcn components
- Centralized error handling in `src/core/` with `AppError`, `ApiError`, `ValidationError` hierarchy
- Logging via `src/core/logging/` with `Logger` and `ErrorHandler` (writes to `application_logs` table)
- Supabase client for data, auth, and storage
- Capacitor for optional native mobile builds

### Supabase Backend
- PostgreSQL with Row Level Security (RLS) for dealer data isolation
- Edge Functions in Deno for server-side logic (invites, webhooks, reports)
- Migrations are timestamped SQL files in `supabase/migrations/`
- Storage buckets for vehicle images and documents

## Tool Preferences

- **Web Search**: Always use `mcp__MiniMax__web_search` — NEVER use the built-in `WebSearch`
- **Image Analysis**: Always use `mcp__MiniMax__understand_image` — NEVER use `mcp__4_5v_mcp__analyze_image` or built-in analysis

## Code Style Rules

- **No comments** in code unless explicitly asked
- Kotlin: `val` over `var`, `data class` for models, `sealed class/interface` for hierarchies, `UUID` primary keys
- Swift: `struct` for views, `class` for ViewModels, force-unwrap `!` only when guaranteed non-nil
- Both platforms: soft deletes via `deletedAt` field, ISO 8601 for dates
- Android uses `fallbackToDestructiveMigration()` (development convenience)
- Supabase credentials currently hardcoded in `AppModule.kt` — should move to BuildConfig

## Key Dependencies

### Android (from `gradle/libs.versions.toml`)
Compose BOM 2024.09.03 · Material3 · Supabase 3.0.1 · Room 2.6.1 · Hilt 2.51.1 · Coil 2.7.0 · Kotlin 2.2.10 · Firebase (Crashlytics, Remote Config)

### iOS
Supabase Swift SDK 2.37.0 · RevenueCat 5.48.0 · Firebase 12.7.0

### Web
React · TanStack Query · Radix UI / Shadcn · Tailwind CSS · Supabase JS · Capacitor
