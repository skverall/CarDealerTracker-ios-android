# App Store release 2.1.20 build 13

Дата: 2026-06-18

## Итог

- App Store app id: `6755675367`
- Bundle id: `com.ezcar24.business`
- Version: `2.1.20`
- Build: `13`
- Build id: `9066df70-7898-4b45-aa99-952642f883c0`
- App Store version id: `dedef12b-7361-4762-84a9-6ac89ae07499`
- Review submission id: `10413f70-79f0-479f-beb3-acfaa8deee81`
- Processing state: `VALID`
- Build audience: `APP_STORE_ELIGIBLE`
- Export compliance: `usesNonExemptEncryption = false`
- Final App Store state: `WAITING_FOR_REVIEW`
- Release type: `AFTER_APPROVAL`

## Что вошло

- iOS version remains `2.1.20`; build number moved from `12` to `13` after build `12` upload stalled in Apple processing.
- Telegram admin safety alerts for new signup and subscription events are included.
- App Store Connect `What's New` updated for `en-US`, `ru`, `ja`, and `ar-SA`.
- No Supabase schema, RLS, Auth settings, sync contract, or financial calculation changes were made during this release step.

## Проверки

- `plutil -lint "iOS Car Dealer Tracker/Ezcar24Business/Info.plist" "iOS Car Dealer Tracker/Ezcar24Business.xcodeproj/project.pbxproj" "iOS Car Dealer Tracker/build/archives/ExportOptions-AppStoreConnect-2.1.20-build13.plist"` - passed
- Archive `Ezcar24Business-2.1.20-build13-20260617-235621.xcarchive` - passed
- Archive bundle check: `com.ezcar24.business`, version `2.1.20`, build `13`
- Local IPA export `Ezcar24Business-2.1.20-build13-20260617-235621-ipa/Ezcar24Business.ipa` - passed
- IPA bundle check: `com.ezcar24.business`, version `2.1.20`, build `13`, team `2RCZ658ZDD`
- `xcrun altool --validate-app ... Ezcar24Business.ipa` - passed, `VERIFY SUCCEEDED with no errors`
- `xcrun altool --upload-app ... Ezcar24Business.ipa` - passed, Delivery UUID `9066df70-7898-4b45-aa99-952642f883c0`
- App Store Connect API confirmed build `2.1.20 (13)` is `VALID`
- App Store Connect API confirmed build `2.1.20 (13)` is `APP_STORE_ELIGIBLE`
- App Store Connect API confirmed build `2.1.20 (13)` is attached to version `2.1.20`
- App Store Connect API confirmed review submission state: `WAITING_FOR_REVIEW`

## What's New

### en-US

Improved account and subscription monitoring to help keep Ezcar24Business safer and more reliable. New signups and billing events are tracked with clearer operational context, plus small stability improvements.

### ru

Улучшили мониторинг регистраций и подписок, чтобы быстрее замечать подозрительную активность и поддерживать стабильность сервиса. Добавили более понятный операционный контекст для новых аккаунтов и событий оплаты, а также небольшие улучшения стабильности.

### ja

新規登録とサブスクリプションイベントの監視を改善し、不審な動きにより早く気付けるようにしました。新しいアカウントと課金イベントの運用情報を見やすくし、安定性も向上しました。

### ar-SA

حسّنا مراقبة التسجيلات الجديدة وأحداث الاشتراك للمساعدة في اكتشاف النشاط المشبوه بشكل أسرع والحفاظ على استقرار الخدمة. كما أضفنا سياقًا أوضح للحسابات الجديدة وأحداث الدفع مع تحسينات بسيطة في الاستقرار.

## Артефакты

- Archive: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.20-build13-20260617-235621.xcarchive`
- Archive log: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.20-build13-20260617-235621.archive.log`
- Export log: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.20-build13-20260617-235621.export.log`
- IPA: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.20-build13-20260617-235621-ipa/Ezcar24Business.ipa`
- IPA SHA-256: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.20-build13-20260617-235621.ipa.sha256`
- altool validation log: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.20-build13-20260617-235621.altool-validate.log`
- altool upload log: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.20-build13-20260617-235621.altool-upload.log`
- Export options: `iOS Car Dealer Tracker/build/archives/ExportOptions-AppStoreConnect-2.1.20-build13.plist`

## Диагностика

- Initial build `2.1.20 (12)` was archived and uploaded through `xcodebuild -exportArchive` with `destination=upload`.
- Apple accepted the upload as buildUpload `c2db1aee-d500-4e27-b3ae-c08a3d269b0c`; all upload files reached `COMPLETE`, but the buildUpload stayed in `PROCESSING` and never appeared as a selectable `builds` record during the release window.
- The release was recovered by bumping only the build number to `13`, exporting a local IPA, validating it with `altool`, and uploading that IPA with `altool`.
- During fallback setup, the local App Store Connect `.p8` key path was restored from the backup under `~/Documents/Codex/.../appstoreconnect/private_keys/`. No private key contents were printed or committed.
- The stuck build `12` upload remains irrelevant to the submitted release; App Store version `2.1.20` is attached to build `13`.
