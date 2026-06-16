# App Store release 2.1.19 build 11

Дата: 2026-06-17

## Итог

- App Store app id: `6755675367`
- Bundle id: `com.ezcar24.business`
- Version: `2.1.19`
- Build: `11`
- Build id: `44515745-2e54-4a3d-810d-458a45b734ce`
- App Store version id: `fbc3af00-0166-4597-8197-1cfb68c8a558`
- Review submission id: `43746079-252c-406f-8a94-45d437a5245d`
- Processing state: `VALID`
- Build audience: `APP_STORE_ELIGIBLE`
- Export compliance: `usesNonExemptEncryption = false`
- Final App Store state: `WAITING_FOR_REVIEW`
- Release type: `AFTER_APPROVAL`

## Что вошло

- iOS version bumped from `2.1.18 (10)` to `2.1.19 (11)`.
- Ideas & Voting reminder nudges are included from commit `1ba4e7e3`.
- App Store Connect `What's New` updated for `en-US`, `ru`, `ja`, and `ar-SA`.
- No Supabase schema, RLS, Edge Function, sync contract, or financial calculation changes were made during this release step.

## Проверки

- `plutil -lint "iOS Car Dealer Tracker/Ezcar24Business/Info.plist" "iOS Car Dealer Tracker/Ezcar24Business.xcodeproj/project.pbxproj"` - passed
- XcodeBuildMCP simulator build for `Ezcar24Business` on `iPhone 17 Pro` - passed
- `xcodebuild archive ... Ezcar24Business-2.1.19-build11-20260617-023456.xcarchive` - passed
- `xcodebuild -exportArchive ... ExportOptions-AppStoreConnect-2.1.19-build11.plist` - passed, uploaded
- App Store Connect API confirmed build `2.1.19 (11)` is `VALID`
- App Store Connect API confirmed build `2.1.19 (11)` is `APP_STORE_ELIGIBLE`
- App Store Connect API confirmed build `2.1.19 (11)` is attached to version `2.1.19`
- Submitted for App Review on `2026-06-16T21:53:08.88Z`
- Review submission state: `WAITING_FOR_REVIEW`

## What's New

### en-US

Added Ideas & Voting reminders so dealers can share product requests and vote on what should be built next. Improved notification routing directly to the Ideas board.

### ru

Добавили умные напоминания для Ideas & Voting: дилеры смогут быстрее предлагать улучшения и голосовать за нужные функции. Улучшили переход из уведомления сразу на страницу идей.

### ja

Ideas & Voting のリマインダーを追加しました。販売店が改善案を投稿し、必要な機能に投票しやすくなりました。通知からアイデア画面へ直接移動できるよう改善しました。

### ar-SA

أضفنا تذكيرات ذكية لقسم Ideas & Voting حتى يتمكن التجار من اقتراح التحسينات والتصويت على الميزات المطلوبة بسهولة أكبر. كما حسّنا الانتقال من الإشعار مباشرة إلى صفحة الأفكار.

## Артефакты

- Archive: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.19-build11-20260617-023456.xcarchive`
- Archive log: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.19-build11-20260617-023456.archive.log`
- Upload log: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.19-build11-20260617-023456.export-upload.log`
- Export options: `iOS Car Dealer Tracker/build/archives/ExportOptions-AppStoreConnect-2.1.19-build11.plist`

## Примечания

- App Store Connect plugin could not be used because the configured `.p8` path is stale, so the official App Store Connect API was used with credentials from macOS Keychain.
- Upload passed with non-blocking dSYM warnings for Firebase/Google frameworks, same class of warning as previous releases.
- The review submission was created through the modern `reviewSubmissions` API and is now waiting for Apple review.
