# App Store / TestFlight release 2.1.18 build 10

Дата: 2026-06-15

## Итог

- App Store app id: `6755675367`
- Bundle id: `com.ezcar24.business`
- Version: `2.1.18`
- Build: `10`
- Build id: `bed970d6-5366-4b65-a8af-d3b6887d1622`
- App Store version id: `2528762c-4757-4506-bf71-495c41a13ca5`
- Review submission id: `6abbd89f-bf7a-4809-bb26-02ed3ad5561e`
- TestFlight processing state: `VALID`
- Final App Store state: `WAITING_FOR_REVIEW`
- Internal TestFlight group found: `ezcar24 business test`

## Что вошло

- Исправлен AI Insights regenerate flow: вместо старого system dialog используется inline confirmation inside AI card.
- Повторная кнопка generate теперь проходит через testable action policy.
- AI report cache/history разделены по языку приложения.
- AI prompt жестко требует язык ответа из in-app language.
- Daily limit policy проверена: default `15`, reset на следующий UTC midnight.
- Supabase `ai-insights` function deployed as active version `4`.
- Production table `public.ai_insight_reports` создана через additive migration `20260613120000_ai_insight_history.sql`.
- PostgREST schema cache reload добавлен через `NOTIFY pgrst, 'reload schema';`.

## Проверки

- `python3 -m json.tool "iOS Car Dealer Tracker/Ezcar24Business/Localizable.xcstrings"` - passed
- `plutil -lint "iOS Car Dealer Tracker/Ezcar24Business/Info.plist" "iOS Car Dealer Tracker/Ezcar24Business.xcodeproj/project.pbxproj"` - passed
- `deno check supabase/functions/ai-insights/index.ts` - passed
- `xcodebuild test ... testAIInsightsActionRequiresInlineConfirmationBeforeReplacingReport ... testAIInsightsCacheAndHistoryAreLanguageScoped` - passed, 4/4
- `xcodebuild archive ... Ezcar24Business-2.1.18-build10-20260615-161630.xcarchive` - passed
- `xcodebuild -exportArchive ... ExportOptions-AppStoreConnect-2.1.18-build10.plist` - passed, uploaded
- App Store Connect API confirmed build `2.1.18 (10)` is `VALID`
- App Store Connect API confirmed build `2.1.18 (10)` is `APP_STORE_ELIGIBLE`
- `What's New` updated for `en-US`, `ru`, `ja`, `ar-SA`
- Submitted for App Review on `2026-06-16T11:02:17.562Z`
- Review submission state: `WAITING_FOR_REVIEW`
- Supabase confirmed `public.ai_insight_reports` exists and RLS is enabled

## What's New

### en-US

New AI Insights experience for Pro dealers: generate clear period summaries for sales, expenses, inventory, and profit. Reports are saved in history, daily usage is shown clearly, and the app asks before replacing an existing report. We also improved analytics localization, App Store screenshots, and release stability.

### ru

Улучшили AI Insights для Pro: теперь приложение понятнее суммирует продажи, расходы, склад и прибыль за выбранный период. Добавили историю AI-отчётов, видимый дневной лимит и подтверждение перед заменой существующего отчёта. Также улучшили локализацию аналитики, стабильность и скриншоты App Store.

### ja

Pro向けのAI Insightsを改善しました。売上、経費、在庫、利益を選択した期間ごとにわかりやすく要約できます。レポート履歴、1日の利用状況表示、既存レポートを置き換える前の確認を追加し、分析画面のローカライズと安定性も向上しました。

### ar-SA

حسّنا تجربة AI Insights لمستخدمي Pro: ملخصات واضحة للمبيعات والمصروفات والمخزون والأرباح حسب الفترة المحددة. أصبحت التقارير محفوظة في السجل، ويظهر حد الاستخدام اليومي بوضوح، ويطلب التطبيق التأكيد قبل استبدال تقرير موجود. كما حسّنا الترجمة والاستقرار ولقطات App Store.

## Артефакты

- Archive: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.18-build10-20260615-161630.xcarchive`
- Archive log: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.18-build10-20260615-161630.archive.log`
- Upload log: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.18-build10-20260615-161630.export-upload.log`
- Export options: `iOS Car Dealer Tracker/build/archives/ExportOptions-AppStoreConnect-2.1.18-build10.plist`

## Примечания

- Первая попытка upload как `2.1.17 (10)` была отклонена Apple: train `2.1.17` закрыт, потому что предыдущая approved version уже `2.1.17`.
- После этого version поднят до `2.1.18`, build оставлен `10`, upload прошел успешно.
- Apple API не разрешает программно прикреплять build к internal TestFlight group: `Cannot add internal group to a build`.
- Если build не появится у internal testers автоматически, вручную выбрать: App Store Connect -> Car Dealer Tracker -> TestFlight -> Internal Testing -> `ezcar24 business test` -> Builds -> добавить `2.1.18 (10)`.
- Upload прошел с non-blocking dSYM warnings для Firebase/Google frameworks, как и предыдущие релизы.
