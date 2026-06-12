# App Store Release 2.1.16 - 2026-06-08

## Status

- App Store app ID: `6755675367`
- App name: `Car Dealer Tracker`
- Bundle ID: `com.ezcar24.business`
- Version: `2.1.16`
- Build: `8`
- App Store version ID: `ac0fe1f4-2062-4030-a22e-9692f777192b`
- Build ID: `d9e598a2-c4c8-42cf-9936-ea4aeaf6a03e`
- Review submission ID: `e0b673eb-bfaf-4a3a-823d-331dd3146441`
- Review item ID: `ZTBiNjczZWItYmZhZi00YTNhLTgyM2QtMzMxZGQzMTQ2NDQxfDZ8ODg2NjgyMzY2`
- Final App Store state: `WAITING_FOR_REVIEW`

## Release Notes Updated

- `en-US`: Uzbek language support, Uzbekistan UZS formatting, improved dashboard, expenses, parts, sales, and login translations.
- `ru`: Uzbek language support, Uzbekistan UZS formatting, improved dashboard, expenses, parts, sales, and login translations.
- `ja`: Uzbek language support, Uzbekistan UZS formatting, improved dashboard, expenses, parts, sales, and login translations.

## Checks

- `Localizable.xcstrings` parsed as valid JSON with 1280 keys.
- `Info.plist` passed `plutil -lint`.
- iOS app version was bumped to `2.1.16`.
- iOS build number was bumped to `8`.
- Targeted iOS simulator tests passed: `2/2`.
- Tested `testUzbekistanRegionUsesUZSFormatting`.
- Tested `testJapaneseRegionUsesJPYFormattingAndLanguageOption`.
- Supabase migrations diff was empty.
- Supabase diff scan found no dangerous schema, RLS, policy, grant, revoke, or destructive migration changes.
- App Store Connect build processing finished with build `8` in `VALID` state.
- App Store Connect export compliance was set to `usesNonExemptEncryption = false`.
- Version `2.1.16` was submitted and reached `WAITING_FOR_REVIEW`.

## Build Artifacts

- Archive: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.16-build8-20260608-194024.xcarchive`
- Archive log: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.16-build8-20260608-194024.archive.log`
- Export options: `iOS Car Dealer Tracker/build/archives/ExportOptions-AppStoreConnect-2.1.16-build8.plist`
- Export/upload log: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.16-build8-20260608-194024.export-upload.log`

## Notes

- The App Store Connect plugin still pointed to an old local `.p8` path, so the release used the official App Store Connect API with credentials from macOS Keychain.
- Upload completed with non-blocking dSYM warnings for Firebase and Google measurement frameworks. The archive upload and App Store submission succeeded.
