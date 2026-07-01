# App Store release 2.1.28 build 18

Date: 2026-06-30

## Result

- App Store app id: `6755675367`
- Bundle id: `com.ezcar24.business`
- Version: `2.1.28`
- Build: `18`
- Build id / Delivery UUID: `e7f87a95-5525-4c3d-8be7-674d8d135a60`
- App Store version id: `a9001fbd-b01a-4137-913c-820255a9cbeb`
- Review submission id: `20c9409f-9ccd-4951-a214-82a5a0a15b4e`
- Processing state: `VALID`
- Build audience: `APP_STORE_ELIGIBLE`
- Export compliance: `usesNonExemptEncryption = false`
- Final App Store state: `WAITING_FOR_REVIEW`
- Release type: `AFTER_APPROVAL`

## Included

- iOS version bumped from `2.1.27 (17)` to `2.1.28 (18)`.
- Apple Search Ads attribution is reported to RevenueCat for more reliable subscription campaign analytics.
- Onboarding and login tracking were refined.
- Vehicle creation gating and dashboard navigation were tightened.
- App Store `What's New` was updated for `en-US`, `ru`, `ja`, `ar-SA`, `pt-BR`, and `id`.
- No Supabase schema, RLS, Auth settings, sync contract, or financial calculation changes were made during this release step.

## Verification

- `plutil -lint "iOS Car Dealer Tracker/Ezcar24Business/Info.plist" "iOS Car Dealer Tracker/Ezcar24Business.xcodeproj/project.pbxproj"` - passed
- `xcodebuild -showBuildSettings` confirmed `MARKETING_VERSION = 2.1.28`, `CURRENT_PROJECT_VERSION = 18`, `PRODUCT_BUNDLE_IDENTIFIER = com.ezcar24.business`
- `jq empty "iOS Car Dealer Tracker/Ezcar24Business/Localizable.xcstrings"` - passed
- `jq empty "iOS Car Dealer Tracker/build/archives/whats-new-2.1.28.json"` - passed
- `git diff --check` - passed
- `xcodebuild test -project "iOS Car Dealer Tracker/Ezcar24Business.xcodeproj" -scheme Ezcar24Business -destination "platform=iOS Simulator,name=iPhone 17 Pro" -derivedDataPath "iOS Car Dealer Tracker/build/DD"` - passed
- Archive `Ezcar24Business-2.1.28-build18-20260630-174305.xcarchive` - passed
- Archive bundle check: `com.ezcar24.business`, version `2.1.28`, build `18`
- Local IPA export `Ezcar24Business-2.1.28-build18-20260630-174305-ipa/Ezcar24Business.ipa` - passed
- IPA bundle check: `com.ezcar24.business`, version `2.1.28`, build `18`
- IPA signing check confirmed `get-task-allow = false`
- IPA entitlements check confirmed `com.apple.developer.applesignin`
- `xcrun altool --validate-app ... Ezcar24Business.ipa` - passed, `VERIFY SUCCEEDED with no errors`
- `xcrun altool --upload-app ... Ezcar24Business.ipa` - passed, Delivery UUID `e7f87a95-5525-4c3d-8be7-674d8d135a60`
- App Store Connect API confirmed build `2.1.28 (18)` is `VALID`
- App Store Connect API confirmed build `2.1.28 (18)` is `APP_STORE_ELIGIBLE`
- App Store Connect API confirmed `usesNonExemptEncryption = false`
- App Store Connect API confirmed `What's New` is present for `en-US`, `ru`, `ja`, `ar-SA`, `pt-BR`, and `id`
- App Store Connect API confirmed review submission state: `WAITING_FOR_REVIEW`

## What's New

### en-US

Improved onboarding and login tracking, added Apple Search Ads attribution for more reliable subscription campaign reporting, and refined vehicle creation limits and dashboard navigation.

### ru

Улучшили отслеживание онбординга и входа, добавили атрибуцию Apple Search Ads для более точной аналитики подписок и доработали лимиты добавления автомобилей и навигацию дашборда.

### ja

オンボーディングとログインの計測を改善し、サブスクリプション広告キャンペーンの分析精度を高めるApple Search Adsアトリビューションを追加しました。車両追加制限とダッシュボードのナビゲーションも調整しました。

### ar-SA

حسّنا تتبع الإعداد الأولي وتسجيل الدخول، وأضفنا إسناد Apple Search Ads لقياس حملات الاشتراك بدقة أكبر، مع تحسين حدود إضافة المركبات والتنقل في لوحة التحكم.

### pt-BR

Melhoramos o rastreamento de onboarding e login, adicionamos atribuição do Apple Search Ads para relatórios de campanhas de assinatura mais confiáveis e refinamos os limites de criação de veículos e a navegação do Dashboard.

### id

Kami meningkatkan pelacakan onboarding dan login, menambahkan atribusi Apple Search Ads agar laporan kampanye langganan lebih andal, serta menyempurnakan batas pembuatan kendaraan dan navigasi Dashboard.

## Artifacts

- Archive: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.28-build18-20260630-174305.xcarchive`
- Archive log: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.28-build18-20260630-174305.archive.log`
- Export log: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.28-build18-20260630-174305.export.log`
- IPA: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.28-build18-20260630-174305-ipa/Ezcar24Business.ipa`
- IPA SHA-256: `d5c1feaf8ef4427322fc98d5684fa5cd8456a2287d04c0179a248ce02fde9901`
- altool validation log: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.28-build18-20260630-174305.altool-validate.log`
- altool upload log: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.28-build18-20260630-174305.altool-upload.log`
- Export options: `iOS Car Dealer Tracker/build/archives/ExportOptions-AppStoreConnect-2.1.28-build18.plist`
- What's New JSON: `iOS Car Dealer Tracker/build/archives/whats-new-2.1.28.json`

## Notes

- The archive used `ENABLE_APP_INTENTS_METADATA_EXTRACTION=NO`, matching the successful 2.1.27 release path. The archive log confirms metadata extraction skipped with `No AppIntents.framework dependency found`.
