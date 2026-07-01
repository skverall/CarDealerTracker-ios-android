# TestFlight build 2.1.29 build 19

Date: 2026-07-01

## Scope

- Added vehicle-level income tracking for inventory vehicles.
- Applied the additive production Supabase migration for `crm.vehicle_income_entries`.
- Uploaded iOS `2.1.29 (19)` to TestFlight for internal testing.

## Production Supabase

- Project: `Ezcar24.com` (`haordpdxyyreliyzmire`)
- Migration applied in production: `20260701153306 vehicle_income_entries`
- Verified `crm.vehicle_income_entries` exists with RLS enabled.
- Verified authenticated users have table access and `sync_vehicle_income_entries(jsonb)` execute access.
- Verified anonymous users do not have execute access to `sync_vehicle_income_entries(jsonb)`.
- Verified `get_changes` includes `vehicle_income_entries`.
- Production smoke passed through the public app RPC flow:
  - sign in as demo user
  - create one temporary vehicle income entry via `sync_vehicle_income_entries`
  - verify it appears in `get_changes`
  - delete it via `delete_crm_vehicle_income_entries`
  - remove the temporary smoke row after verification

## Local QA

- iOS simulator build passed.
- Android `./gradlew assembleDebug` passed.
- Android emulator UI smoke passed:
  - opened a vehicle detail screen
  - confirmed the new Vehicle income section appears after Financial Summary
  - added a rental income entry
  - verified the amount and row rendering
  - deleted the entry and verified the section returned to empty state
- `git diff --check` passed.

## TestFlight

- App Store Connect app: `Car Dealer Tracker`
- Bundle ID: `com.ezcar24.business`
- Version: `2.1.29`
- Build: `19`
- Build ID: `707f0cc9-3b91-4485-96bc-8947eabd1184`
- App Store version ID: `c9205f63-ec1d-40f6-a742-3e569d6f718d`
- Processing state: `VALID`
- Audience type: `APP_STORE_ELIGIBLE`
- Export compliance: `usesNonExemptEncryption=false`
- Internal TestFlight group: `ezcar24 business test`
- Internal group access: `hasAccessToAllBuilds=true`
- Build `19` is visible in the internal group.
- App Review was not submitted.

## Artifacts

- Archive: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.29-build19-20260701-203819.xcarchive`
- Archive log: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.29-build19-20260701-203819.archive.log`
- Export log: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.29-build19-20260701-203819.export.log`
- IPA: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.29-build19-20260701-203819-ipa/Ezcar24Business.ipa`
- SHA-256: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.29-build19-20260701-203819.ipa.sha256`
- altool validation log: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.29-build19-20260701-203819.altool-validate.log`
- altool upload log: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.29-build19-20260701-203819.altool-upload.log`
- Export options: `iOS Car Dealer Tracker/build/archives/ExportOptions-AppStoreConnect-2.1.29-build19.plist`
