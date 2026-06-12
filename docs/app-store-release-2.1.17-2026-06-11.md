# App Store release 2.1.17

Дата: 2026-06-11

## Итог

- App Store app id: `6755675367`
- Bundle id: `com.ezcar24.business`
- Version: `2.1.17`
- Build: `9`
- Build id: `d36bfb67-6cc5-453c-a648-448b66df1a9f`
- Review submission id: `75127ca0-934d-4595-aa6f-4edf227e2387`
- Final App Store state: `WAITING_FOR_REVIEW`

## Что изменено для релиза

- iOS `CFBundleShortVersionString` поднят до `2.1.17`.
- iOS `CFBundleVersion` поднят до `9`.
- Xcode project `MARKETING_VERSION` поднят до `2.1.17`.
- Xcode project `CURRENT_PROJECT_VERSION` поднят до `9`.
- Build `9` загружен в App Store Connect и прикреплен к версии `2.1.17`.
- `usesNonExemptEncryption` установлен в `false`.
- `What's New` обновлен для `en-US`, `ru`, `ja`, `ar-SA`.

## What's New

### en-US

Added full Arabic localization with right-to-left layout support. Improved Arabic paywall, dashboard, vehicles, expenses, sales, clients, parts inventory, and App Store screenshots.

### ru

Добавили полную арабскую локализацию с поддержкой интерфейса справа налево. Улучшили арабские тексты на paywall, панели управления, экранах автомобилей, расходов, продаж, клиентов, запчастей и скриншотах App Store.

### ja

アラビア語ローカライズを追加し、右から左へのレイアウトに対応しました。Paywall、ダッシュボード、車両、経費、販売、顧客、部品在庫、App Storeスクリーンショットのアラビア語表示を改善しました。

### ar-SA

أضفنا اللغة العربية بالكامل مع دعم اتجاه الكتابة من اليمين إلى اليسار. حسّنا شاشة الترقية، لوحة التحكم، المركبات، المصروفات، المبيعات، العملاء، قطع الغيار ولقطات App Store العربية.

## Проверки

- `python3 -m json.tool "iOS Car Dealer Tracker/Ezcar24Business/Localizable.xcstrings" >/dev/null` - passed
- `plutil -lint "iOS Car Dealer Tracker/Ezcar24Business/Info.plist"` - passed
- `plutil -lint "iOS Car Dealer Tracker/Ezcar24Business.xcodeproj/project.pbxproj"` - passed
- `xcodebuild test -project "iOS Car Dealer Tracker/Ezcar24Business.xcodeproj" -scheme Ezcar24Business -destination 'platform=iOS Simulator,name=IOS 26.5' -derivedDataPath /tmp/cardealer-release-2.1.17-derived-data -only-testing:Ezcar24BusinessTests/Ezcar24BusinessRegressionTests/testUzbekistanRegionUsesUZSFormatting -only-testing:Ezcar24BusinessTests/Ezcar24BusinessRegressionTests/testJapaneseRegionUsesJPYFormattingAndLanguageOption` - passed
- `xcodebuild archive -project "iOS Car Dealer Tracker/Ezcar24Business.xcodeproj" -scheme Ezcar24Business -configuration Release -destination 'generic/platform=iOS' -archivePath "iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.17-build9-20260611-094833.xcarchive"` - passed
- `xcodebuild -exportArchive -archivePath "iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.17-build9-20260611-094833.xcarchive" -exportPath "iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.17-build9-20260611-094833-export" -exportOptionsPlist "iOS Car Dealer Tracker/build/archives/ExportOptions-AppStoreConnect-2.1.17-build9.plist"` - passed, uploaded

## Артефакты

- Archive: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.17-build9-20260611-094833.xcarchive`
- Archive log: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.17-build9-20260611-094833.archive.log`
- Upload log: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.17-build9-20260611-094833.export-upload.log`
- Export options: `iOS Car Dealer Tracker/build/archives/ExportOptions-AppStoreConnect-2.1.17-build9.plist`

## Примечания

- Upload прошел успешно: `Uploaded Ezcar24Business`, `EXPORT SUCCEEDED`.
- App Store Connect plugin в Codex не сработал из-за старого локального пути ключа, поэтому использовался официальный App Store Connect API с credentials из macOS Keychain.
- Во время upload были предупреждения о недостающих dSYM для Firebase/Google frameworks. Это не заблокировало upload и submit, но может ухудшить символикацию crash logs для этих сторонних frameworks.
