# iOS Subscription Trial And Pricing - 2026-05-30

## App Store Connect Changes

- App: `Car Dealer Tracker` (`6755675367`)
- Monthly product: `com.ezcar24.business.monthly` (`6755675259`)
- Yearly product: `com.ezcar24.business.yearly` (`6755675665`)
- Effective start date: `2026-06-01` (earliest date Apple API allowed on 2026-05-30)
- Monthly price for new subscribers: `14.99 USD` in the USA price point, with Apple equalized prices scheduled for all 175 territories.
- Yearly price for new subscribers: `119.99 USD` in the USA price point, with Apple equalized prices scheduled for 170 territories; 5 territories were already on the matching equalized yearly price and did not need a future row.
- Existing subscribers are preserved on their current prices. API verification showed current USA rows as `preserved=true`:
  - monthly current: `9.99 USD`
  - yearly current: `99.99 USD`
- Yearly introductory offer created for all 175 territories:
  - `offerMode`: `FREE_TRIAL`
  - `duration`: `ONE_WEEK`
  - `numberOfPeriods`: `1`
  - `startDate`: `2026-06-01`
  - `endDate`: none

## Verification

- App Store Connect API verification:
  - monthly prices: 175 current rows + 175 future rows for `2026-06-01`
  - monthly current preservation: `175/175`
  - yearly prices: 175 current rows + 170 future rows for `2026-06-01`
  - yearly current preservation: `170/175`; the remaining 5 territories had no future yearly price row because the current equalized price already matched the target.
  - USA monthly: current `9.99 USD` preserved, future `14.99 USD` from `2026-06-01`
  - USA yearly: current `99.99 USD` preserved, future `119.99 USD` from `2026-06-01`
  - yearly introductory offers: 175 rows, all `ONE_WEEK` + `FREE_TRIAL`, all starting `2026-06-01`
- iOS release preparation:
  - local app version updated to `2.1.15`
  - local build number updated to `7`
  - archive created: `build/archives/Ezcar24Business-2.1.15-build7-20260530-231150.xcarchive`
  - uploaded to App Store Connect at `2026-05-30T11:16:26-07:00`
  - App Store Connect build ID: `37701193-7098-43f8-ab91-b303cb2dfe28`
  - App Store Connect processing state: `VALID`
  - App Store Connect audience: `APP_STORE_ELIGIBLE`
  - App Store version `2.1.15` created with ID `e2550e63-5bd5-477d-83ba-54267a237e51`
  - build `37701193-7098-43f8-ab91-b303cb2dfe28` attached to version `2.1.15`
  - App Store version state: `PREPARE_FOR_SUBMISSION`
  - `Submit for Review` was not clicked
- RevenueCat public offerings check:
  - current offering: `default`
  - products present: `com.ezcar24.business.weekly`, `com.ezcar24.business.monthly`, `com.ezcar24.business.yearly`

## Notes

- App Store Connect product metadata can take time to propagate to sandbox and RevenueCat.
- On 2026-05-30, Apple API rejected same-day price activation and required a future date on or after `2026-06-01`; until that date StoreKit can still return the active current prices (`9.99 USD` monthly and `99.99 USD` yearly in the USA).
- The iOS Paywall only shows the 7-day trial copy when RevenueCat reports intro eligibility for the yearly product.
