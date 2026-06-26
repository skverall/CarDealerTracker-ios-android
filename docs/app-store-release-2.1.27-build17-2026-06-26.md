# App Store release 2.1.27 build 17

Date: 2026-06-26

## Result

- App Store app id: `6755675367`
- Bundle id: `com.ezcar24.business`
- Version: `2.1.27`
- Build: `17`
- Build id / Delivery UUID: `a287f033-1384-4398-a634-4edcf8de42eb`
- App Store version id: `8b3c59e9-6efd-48d7-a638-65adb599090e`
- Review submission id: `41aefb87-c629-4e86-afe5-1d5365926a3b`
- Processing state: `VALID`
- Build audience: `APP_STORE_ELIGIBLE`
- Export compliance: `usesNonExemptEncryption = false`
- Final App Store state: `WAITING_FOR_REVIEW`
- Release type: `AFTER_APPROVAL`

## Included

- iOS version bumped from `2.1.23 (16)` to `2.1.27 (17)`.
- RevenueCat Standard Apple Ads attribution token collection was enabled after the existing `Purchases.configure(...)` call.
- The Pro paywall was redesigned and tightened for better localization and plan visibility.
- Dashboard quick actions now offer `Add Expense` and `Add Vehicle`; adding a vehicle opens the add vehicle flow directly.
- Vehicle list navigation from dashboard keeps a visible navigation bar/back path.
- No Supabase schema, RLS, Auth settings, sync contract, or financial calculation changes were made during this release step.

## Verification

- `plutil -lint "iOS Car Dealer Tracker/Ezcar24Business/Info.plist" "iOS Car Dealer Tracker/Ezcar24Business.xcodeproj/project.pbxproj"` - passed
- `xcodebuild -showBuildSettings` confirmed `MARKETING_VERSION = 2.1.27`, `CURRENT_PROJECT_VERSION = 17`, `PRODUCT_BUNDLE_IDENTIFIER = com.ezcar24.business`
- `jq empty "iOS Car Dealer Tracker/Ezcar24Business/Localizable.xcstrings"` - passed
- `jq empty "iOS Car Dealer Tracker/build/archives/whats-new-2.1.27.json"` - passed
- `git diff --check` - passed
- Simulator build after enabling RevenueCat AdServices attribution - passed
- Archive `Ezcar24Business-2.1.27-build17-20260626-134312.xcarchive` - passed
- Archive bundle check: `com.ezcar24.business`, version `2.1.27`, build `17`
- Local IPA export `Ezcar24Business-2.1.27-build17-20260626-134312-ipa/Ezcar24Business.ipa` - passed
- IPA bundle check: `com.ezcar24.business`, version `2.1.27`, build `17`
- IPA signing check confirmed `get-task-allow = false`
- IPA entitlements check confirmed `com.apple.developer.applesignin`
- `xcrun altool --validate-app ... Ezcar24Business.ipa` - passed, `VERIFY SUCCEEDED with no errors`
- `xcrun altool --upload-app ... Ezcar24Business.ipa` - passed, Delivery UUID `a287f033-1384-4398-a634-4edcf8de42eb`
- App Store Connect API confirmed build `2.1.27 (17)` is `VALID`
- App Store Connect API confirmed build `2.1.27 (17)` is `APP_STORE_ELIGIBLE`
- App Store Connect API confirmed `usesNonExemptEncryption = false`
- App Store Connect API confirmed `What's New` is present for `en-US`, `ru`, `ja`, `ar-SA`, `pt-BR`, and `id`
- App Store Connect API confirmed review submission state: `WAITING_FOR_REVIEW`

## What's New

### en-US

Improved the Pro upgrade screen with clearer plans and trial details, fixed Dashboard quick actions for adding vehicles and expenses, and made subscription campaign tracking more reliable.

### ru

Обновили экран Pro: планы и пробный период стали понятнее. Исправили быстрые действия на дашборде для добавления расходов и автомобилей, а также улучшили точность аналитики подписок для рекламных кампаний.

### ja

Proアップグレード画面を改善し、プランとトライアル内容をより分かりやすくしました。ダッシュボードの車両・経費追加アクションを修正し、広告キャンペーンのサブスクリプション計測もより正確になりました。

### ar-SA

حسّنا شاشة الترقية إلى Pro لتوضيح الخطط والتجربة المجانية بشكل أفضل، وأصلحنا إجراءات لوحة التحكم السريعة لإضافة المركبات والمصروفات، مع تحسين دقة تتبع حملات الاشتراك.

### pt-BR

Melhoramos a tela de upgrade para o Pro com planos e detalhes do teste mais claros, corrigimos as ações rápidas do Dashboard para adicionar veículos e despesas e deixamos o rastreamento de campanhas de assinatura mais confiável.

### id

Kami meningkatkan layar upgrade Pro dengan paket dan detail uji coba yang lebih jelas, memperbaiki aksi cepat Dashboard untuk menambahkan kendaraan dan pengeluaran, serta membuat pelacakan kampanye langganan lebih andal.

## Artifacts

- Archive: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.27-build17-20260626-134312.xcarchive`
- Archive log: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.27-build17-20260626-134312.archive.log`
- Export log: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.27-build17-20260626-134312.export.log`
- IPA: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.27-build17-20260626-134312-ipa/Ezcar24Business.ipa`
- IPA SHA-256: `a2b085cb266631f2cf1503479b86c024415e847acfe56d39a99a5505160f28b7`
- altool validation log: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.27-build17-20260626-134312.altool-validate.log`
- altool upload log: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.27-build17-20260626-134312.altool-upload.log`
- Export options: `iOS Car Dealer Tracker/build/archives/ExportOptions-AppStoreConnect-2.1.27-build17.plist`
- What's New JSON: `iOS Car Dealer Tracker/build/archives/whats-new-2.1.27.json`

## Notes

- The first archive attempt failed in Xcode's `ExtractAppIntentsMetadata` step for the Swift package target `IssueReportingPackageSupport` because `appintentsmetadataprocessor` could not load `libSwiftSyntax.dylib` due to local system policy.
- The successful archive used `ENABLE_APP_INTENTS_METADATA_EXTRACTION=NO`. The app target itself has no AppIntents dependency, and the successful archive log confirms metadata extraction was skipped with `No AppIntents.framework dependency found`.
