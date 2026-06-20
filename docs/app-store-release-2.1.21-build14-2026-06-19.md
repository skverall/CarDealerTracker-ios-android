# App Store release 2.1.21 build 14

Дата: 2026-06-19

## Итог

- App Store app id: `6755675367`
- Bundle id: `com.ezcar24.business`
- Version: `2.1.21`
- Build: `14`
- Build id: `f8fe4d9b-e800-442c-b0bf-797d17902d4a`
- App Store version id: `2863cf3b-8fb5-450a-9c2f-c9b6741be100`
- Review submission id: `958435ac-6045-42f6-a075-79fdb6ffb1e5`
- Processing state: `VALID`
- Build audience: `APP_STORE_ELIGIBLE`
- Export compliance: `usesNonExemptEncryption = false`
- Final App Store state: `WAITING_FOR_REVIEW`
- Release type: `AFTER_APPROVAL`

## Что вошло

- iOS version bumped from `2.1.20 (13)` to `2.1.21 (14)`.
- Hindi language support is included in the app.
- AI Insights language verification is hardened.
- Monthly PDF reports were redesigned.
- iPad layouts, settings, and form sheet presentation were polished.
- App Store Connect `What's New` updated for `en-US`, `ru`, `ja`, and `ar-SA`.
- No Supabase schema, RLS, Auth settings, sync contract, or financial calculation changes were made during this release step.

## Проверки

- `plutil -lint "iOS Car Dealer Tracker/Ezcar24Business/Info.plist" "iOS Car Dealer Tracker/Ezcar24Business.xcodeproj/project.pbxproj"` - passed
- Archive `Ezcar24Business-2.1.21-build14-20260619-155048.xcarchive` - passed
- Archive bundle check: `com.ezcar24.business`, version `2.1.21`, build `14`
- Local IPA export `Ezcar24Business-2.1.21-build14-20260619-155048-ipa/Ezcar24Business.ipa` - passed
- IPA bundle check: `com.ezcar24.business`, version `2.1.21`, build `14`
- `xcrun altool --validate-app ... Ezcar24Business.ipa` - passed, `VERIFY SUCCEEDED with no errors`
- `xcrun altool --upload-app ... Ezcar24Business.ipa` - passed, Delivery UUID `f8fe4d9b-e800-442c-b0bf-797d17902d4a`
- App Store Connect API confirmed build `2.1.21 (14)` is `VALID`
- App Store Connect API confirmed build `2.1.21 (14)` is `APP_STORE_ELIGIBLE`
- App Store Connect API confirmed build `2.1.21 (14)` is attached to version `2.1.21`
- App Store Connect API confirmed review submission state: `WAITING_FOR_REVIEW`
- `git diff --check` - passed

## What's New

### en-US

Added Hindi language support across the app, improved AI Insights language accuracy, redesigned monthly PDF reports, and polished iPad layouts, settings, and form sheets for a smoother dealer workflow.

### ru

Добавили поддержку Hindi во всём приложении, улучшили точность языка в AI Insights, обновили дизайн ежемесячных PDF-отчётов и отполировали iPad-версию, настройки и формы для более удобной работы дилера.

### ja

アプリ全体にヒンディー語対応を追加しました。AI Insights の言語精度を改善し、月次PDFレポートを刷新。iPad レイアウト、設定画面、入力フォームもより使いやすく調整しました。

### ar-SA

أضفنا دعم اللغة الهندية داخل التطبيق، وحسّنا دقة اللغة في AI Insights، وأعدنا تصميم تقارير PDF الشهرية، مع تحسين تخطيطات iPad والإعدادات ونماذج الإدخال لتجربة أكثر سلاسة للتجار.

## Артефакты

- Archive: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.21-build14-20260619-155048.xcarchive`
- Archive log: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.21-build14-20260619-155048.archive.log`
- Export log: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.21-build14-20260619-155048.export-with-api-key.log`
- IPA: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.21-build14-20260619-155048-ipa/Ezcar24Business.ipa`
- IPA SHA-256: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.21-build14-20260619-155048.ipa.sha256`
- altool validation log: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.21-build14-20260619-155048.altool-validate.log`
- altool upload log: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.21-build14-20260619-155048.altool-upload.log`
- Export options: `iOS Car Dealer Tracker/build/archives/ExportOptions-AppStoreConnect-2.1.21-build14.plist`

## Примечания

- Local export initially failed because no local `iOS Distribution` certificate was installed.
- The release was exported successfully with `-allowProvisioningUpdates` and the App Store Connect API key from macOS Keychain.
- Archive warning was limited to AppIntents metadata extraction being skipped because the app has no AppIntents dependency.
