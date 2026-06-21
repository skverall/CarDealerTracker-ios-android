# TestFlight build 2.1.22 build 15

Дата: 2026-06-21

## Итог

- App Store app id: `6755675367`
- Bundle id: `com.ezcar24.business`
- Version: `2.1.22`
- Build: `15`
- Build id: `0e87d72d-3f28-4800-8583-49c7374d2a36`
- Delivery UUID: `0e87d72d-3f28-4800-8583-49c7374d2a36`
- Processing state: `VALID`
- Build audience: `APP_STORE_ELIGIBLE`
- Export compliance: `usesNonExemptEncryption = false`
- TestFlight internal group: `ezcar24 business test`
- Internal group access: `hasAccessToAllBuilds = true`

## Что вошло

- TestFlight train bumped from `2.1.21 (14)` to `2.1.22 (15)` because App Store Connect closed the approved `2.1.21` train for new uploads.
- `CFBundleShortVersionString` now resolves from `$(MARKETING_VERSION)`.
- `CFBundleVersion` now resolves from `$(CURRENT_PROJECT_VERSION)`.
- The build contains the Google sign-in and Apple sign-in work from the previous commit.
- Xcode string-catalog extraction synced auth strings in `Localizable.xcstrings`.
- No Supabase schema, RLS, Auth settings, sync contract, or financial calculation changes were made during this TestFlight upload step.

## Проверки

- `plutil -lint "iOS Car Dealer Tracker/Ezcar24Business/Info.plist" "iOS Car Dealer Tracker/Ezcar24Business.xcodeproj/project.pbxproj"` - passed
- `xcodebuild -showBuildSettings` confirmed `MARKETING_VERSION = 2.1.22`, `CURRENT_PROJECT_VERSION = 15`, `PRODUCT_BUNDLE_IDENTIFIER = com.ezcar24.business`
- Archive `Ezcar24Business-2.1.22-build15-20260621-135435.xcarchive` - passed
- Archive bundle check: `com.ezcar24.business`, version `2.1.22`, build `15`
- Archive entitlements check confirmed `com.apple.developer.applesignin`
- Local IPA export `Ezcar24Business-2.1.22-build15-20260621-135435-ipa/Ezcar24Business.ipa` - passed
- IPA bundle check: `com.ezcar24.business`, version `2.1.22`, build `15`
- IPA signing check confirmed Store provisioning profile and `get-task-allow = false`
- IPA entitlements check confirmed `com.apple.developer.applesignin`
- `xcrun altool --validate-app ... Ezcar24Business.ipa` - passed, `VERIFY SUCCEEDED with no errors`
- `xcrun altool --upload-app ... Ezcar24Business.ipa` - passed, `UPLOAD SUCCEEDED with no errors`
- App Store Connect API confirmed build `2.1.22 (15)` is `VALID`
- App Store Connect API confirmed build `2.1.22 (15)` is `APP_STORE_ELIGIBLE`
- App Store Connect API confirmed `usesNonExemptEncryption = false`
- App Store Connect API confirmed internal TestFlight group `ezcar24 business test` has access to all builds

## Артефакты

- Archive: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.22-build15-20260621-135435.xcarchive`
- Archive log: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.22-build15-20260621-135435.archive.log`
- Export log: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.22-build15-20260621-135435.export.log`
- IPA: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.22-build15-20260621-135435-ipa/Ezcar24Business.ipa`
- IPA SHA-256: `f9122ea44afedbb1077ba57e8b8654333c78c1ac9c99576fadeebacd9c72b8ac`
- altool validation log: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.22-build15-20260621-135435.validate.log`
- altool upload log: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.22-build15-20260621-135435.upload.log`
- Export options: `iOS Car Dealer Tracker/build/archives/ExportOptions-AppStoreConnect-2.1.22-build15.plist`

## Примечания

- Initial validation for `2.1.21 (15)` failed because App Store Connect reported: `The train version '2.1.21' is closed for new build submissions`.
- The successful TestFlight upload uses the next train, `2.1.22 (15)`.
