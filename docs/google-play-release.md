# Google Play Release Notes

## App

- App name in Play Console: Car Dealer Tracker
- Android package name: `com.ezcar24.business`
- Current Android version in project: `2.1.14`
- Current Android version code in project: `2114`
- Current Android compile SDK: `35`
- Current Android target SDK: `35`

## Current release status

Updated: 2026-06-14 02:12 UZT

Firebase Android config is installed locally at:

```text
Android Car Dealer Tracker/app/google-services.json
```

Backup copy is stored outside the repository at:

```text
~/.hermes/secrets/firebase/com.ezcar24.business-google-services.json
```

The backup path is saved in macOS Keychain under:

```text
firebase.com.ezcar24.business.google_services_json_path
```

Local checks passed after moving the Android project to target API 35:

```bash
JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
ANDROID_HOME=/opt/homebrew/share/android-commandlinetools \
./gradlew :app:compileDebugKotlin

JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
ANDROID_HOME=/opt/homebrew/share/android-commandlinetools \
./gradlew test

JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
ANDROID_HOME=/opt/homebrew/share/android-commandlinetools \
./gradlew assembleDebug
```

Latest local release AAB after Android RevenueCat Google Play base-plan
identifier support, RevenueCat Android product setup, Play privacy cleanup, and
native-symbol configuration:

```text
Android Car Dealer Tracker/app/build/outputs/bundle/release/app-release.aab
```

Size: `14M`

SHA-256:

```text
e6257a5aab16923f249e8aaf63d97ec02401c1f929357fe80c007b484703e645
```

This `2114 (2.1.14)` AAB was uploaded to Google Play closed testing
(`alpha`) through the Android Publisher API on 2026-06-14 02:12 UZT.

RevenueCat Android verification on 2026-06-14 after Merchant Payment Setup and
Google Play subscription setup:

```bash
./scripts/play_release_status.py
./scripts/revenuecat_prepare_android_products.py
```

Result: Google Play returns all four expected subscriptions as `ACTIVE`.
RevenueCat Management API returns the Android app, current `default` offering,
active Pro entitlement, all four Android products, and all four package
attachments. The local Android public SDK key also matches the RevenueCat
Android app public API key.

Rechecked at 2026-06-14 14:30 UZT: the SDK-facing RevenueCat v1 offerings
endpoint now returns `count=1`, current offering `default`, and all four Android
products. RevenueCat propagation is no longer a release blocker. The remaining
billing check is a real Play-installed tester build purchase/restore smoke.

The previous API-uploaded closed testing release `2113 (2.1.13)` has SHA-256:

```text
3676623bce3f899496769771861efbd35b5ccfa9b152da6029a61c5bf9ebdbce
```

The AAB already uploaded to Play Console for closed testing release
`2112 (2.1.12)` has SHA-256:

```text
4350ab21294b25bf7c0270e48e2fbe21c5ac0d5fb310991a2eeeadd9210a2506
```

Do not upload another `2112` or `2113` artifact. Future Play uploads must use a
version code higher than `2114`.

Release build command after the RevenueCat key is configured:

```bash
JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
ANDROID_HOME=/opt/homebrew/share/android-commandlinetools \
./gradlew :app:bundleRelease
```

The release build now intentionally fails without `REVENUECAT_ANDROID_API_KEY`:

```text
Missing REVENUECAT_ANDROID_API_KEY. Add the RevenueCat Android public SDK key as a Gradle property or environment variable before building release.
```

The key can be supplied through a Gradle property, environment variable, or the
ignored local `keystore.properties` file:

```bash
REVENUECAT_ANDROID_API_KEY="goog_..." ./gradlew :app:bundleRelease
./gradlew :app:bundleRelease -PREVENUECAT_ANDROID_API_KEY="goog_..."
```

The real Android RevenueCat public SDK key is now stored locally in:

```text
~/.gradle/gradle.properties
```

The value starts with `goog_` and is not stored in the repository.

Latest local release APK for direct device smoke testing:

```text
Android Car Dealer Tracker/app/build/outputs/apk/release/app-release.apk
```

Version: `2.1.14 (2114)`

SHA-256:

```text
706ea662dcb5da82efe542128dbd997c5c8c1d478c54a14fbbbe5cf77abf1960
```

`apksigner verify --verbose --print-certs` passed on 2026-06-14. The APK is
signed by the Ezcar24 upload certificate and declares
`com.android.vending.BILLING`.

Helper command for installing this APK on a connected Android phone:

```bash
./scripts/android_install_release_apk.py --wait
```

If no device is visible, unlock the phone, reconnect USB, enable USB debugging,
and tap `Allow` on the RSA debugging prompt. The helper uses the installed
Android platform-tools path directly, so it works even when `adb` is not in the
shell `PATH`.

Latest local checks:

```bash
JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
./gradlew :app:testDebugUnitTest --tests "com.ezcar24.business.util.calculator.DashboardMetricsCalculatorTest"

JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
./gradlew :app:testDebugUnitTest

JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
./gradlew :app:assembleDebug

JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
ANDROID_HOME=/opt/homebrew/share/android-commandlinetools \
./gradlew :app:bundleRelease
```

Latest verification on 2026-06-13 23:38 UZT:

```bash
JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
ANDROID_HOME=/opt/homebrew/share/android-commandlinetools \
./gradlew :app:testDebugUnitTest :app:assembleDebug

bundletool validate --bundle="Android Car Dealer Tracker/app/build/outputs/bundle/release/app-release.aab"

JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
jarsigner -verify "Android Car Dealer Tracker/app/build/outputs/bundle/release/app-release.aab"

bundletool dump manifest \
  --bundle="Android Car Dealer Tracker/app/build/outputs/bundle/release/app-release.aab" \
  --module=base

git diff --check
```

All commands passed. `jarsigner` returned `JARSIGNER_EXIT=0` and `jar
verified.` The release manifest still contains package `com.ezcar24.business`,
version `2112 (2.1.12)`, no Advertising ID permissions, and Firebase ad-id
collection remains disabled.

Release lint verification on 2026-06-13 23:45 UZT:

```bash
JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
ANDROID_HOME=/opt/homebrew/share/android-commandlinetools \
./gradlew :app:lintVitalRelease
```

Result: `BUILD SUCCESSFUL`. The generated text report says:

```text
No issues found.
```

Release APK install smoke on Xiaomi Redmi 15C on 2026-06-14 00:02 UZT:

```bash
JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
ANDROID_HOME=/opt/homebrew/share/android-commandlinetools \
./gradlew :app:assembleRelease

JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
apksigner verify --verbose --print-certs \
  Android\ Car\ Dealer\ Tracker/app/build/outputs/apk/release/app-release.apk

adb -s 6DVGOFPVNBM7LNMR install -r -g \
  Android\ Car\ Dealer\ Tracker/app/build/outputs/apk/release/app-release.apk
```

Result: `assembleRelease` passed, release APK SHA-256 is
`17ceb88539be3a71d52e62ebb9d9089e2461336f09fd7d2220ed171dc2e852f6`, and
`apksigner` verified the APK with the Ezcar24 upload certificate. The release
package `com.ezcar24.business` version code `2112` installed successfully on
the Xiaomi alongside the debug package `com.ezcar24.business.debug`.

Runtime result: `com.ezcar24.business/.MainActivity` launched, stayed alive
with pid `19776`, showed the first-launch region picker, then reached the
`Welcome Back` login screen after `Continue`. The crash buffer was empty and
no `FATAL EXCEPTION` was found for `com.ezcar24.business`.

Observed non-crash warning: RevenueCat logs a configuration error because the
Android RevenueCat app still has no Google Play products in its offerings.
This matches the existing Play blocker: Google Play subscription products are
not created yet because merchant setup is still incomplete.

Result before RevenueCat migration: all four commands passed. `jarsigner
-verify` exited successfully for the pre-RevenueCat AAB; it printed standard
AAB `JarFile` / `JarInputStream` warnings but no signing failure. Latest
signing verification returned `JARSIGNER_EXIT=0`.

Result after RevenueCat migration:

```bash
JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
./gradlew :app:compileDebugKotlin

JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
./gradlew :app:testDebugUnitTest :app:assembleDebug

JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
ANDROID_HOME=/opt/homebrew/share/android-commandlinetools \
./gradlew :app:compileReleaseKotlin
```

All three commands passed. Release `bundleRelease` without the key was tested
and correctly failed early. `bundletool` is installed locally and is now used
to validate release AAB files before upload.

Result after making destructive Room fallback debug-only:

```bash
JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
./gradlew :app:testDebugUnitTest :app:assembleDebug

JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
./gradlew :app:compileReleaseKotlin

JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
./gradlew :app:bundleRelease
```

Debug tests/APK passed. Release Kotlin compilation now uses the locally
configured RevenueCat Android key. Release `bundleRelease` without the real
`REVENUECAT_ANDROID_API_KEY` was rechecked and correctly failed early. The
RevenueCat purchase flow now uses the current `PurchaseParams` SDK API instead
of deprecated `purchasePackageWith`; debug and release Kotlin compilation
passed after that change.

Result after sales/client sync parity pass:

```bash
JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
./gradlew :app:testDebugUnitTest --tests "com.ezcar24.business.ui.sale.SaleBalanceChangeTest" --tests "com.ezcar24.business.data.sync.SaleRemoteMappingTest"

JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
./gradlew :app:testDebugUnitTest :app:assembleDebug

JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
./gradlew :app:compileReleaseKotlin

JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
./gradlew :app:bundleRelease
```

Targeted tests passed. Full debug unit tests and debug APK passed. Release
Kotlin compilation now uses the locally configured RevenueCat Android key.
Release `bundleRelease` without the real `REVENUECAT_ANDROID_API_KEY` was
rechecked and correctly failed early. Android sales sync now preserves the
selected client's existing name, phone, and notes like iOS; Deal Desk sales now
send the existing backend columns `jurisdiction_type`, `jurisdiction_code`,
`out_the_door_total`, `cash_received_now`, `amount_financed`, and
`monthly_payment_estimate`; sale `created_at` now uses the local sale creation
timestamp instead of the current sync time.

Client form local-first parity follow-up on 2026-06-14 00:10 UZT:

```bash
JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
./gradlew :app:compileDebugKotlin

JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
./gradlew :app:testDebugUnitTest --tests "com.ezcar24.business.data.sync.ClientRemoteMappingTest" --tests "com.ezcar24.business.ui.sale.SaleBalanceChangeTest"

JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
ANDROID_HOME=/opt/homebrew/share/android-commandlinetools \
./gradlew :app:compileReleaseKotlin
```

All three commands passed. Android client creation/edit now normalizes text
fields like iOS (`name` trimmed, blank phone/email/notes/request details saved
as null) and saves the client to local Room before attempting cloud sync. If
the sync context is temporarily unavailable, the client remains saved locally
instead of being lost behind a backend error.

Latest local release AAB with this client form fix was rebuilt and verified on
2026-06-14 00:14 UZT:

```bash
JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
ANDROID_HOME=/opt/homebrew/share/android-commandlinetools \
./gradlew :app:bundleRelease

bundletool validate \
  --bundle="Android Car Dealer Tracker/app/build/outputs/bundle/release/app-release.aab"

JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
jarsigner -verify \
  "Android Car Dealer Tracker/app/build/outputs/bundle/release/app-release.aab"

bundletool dump manifest \
  --bundle="Android Car Dealer Tracker/app/build/outputs/bundle/release/app-release.aab" \
  --module=base
```

Result: `bundleRelease` passed, `bundletool validate` passed, and `jarsigner`
returned `JARSIGNER_EXIT=0` with `jar verified.` The manifest still reports
package `com.ezcar24.business`, version `2112 (2.1.12)`, and no Advertising ID
permissions. Because Play already has `2112` in closed testing review, this
local artifact is verification evidence only; the next upload must increment
the Android version code.

Version bump and release AAB rebuild on 2026-06-14 01:22 UZT:

```bash
JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
./gradlew :app:testDebugUnitTest --tests "com.ezcar24.business.data.billing.SubscriptionManagerTest" --tests "com.ezcar24.business.data.sync.ClientRemoteMappingTest" --tests "com.ezcar24.business.ui.sale.SaleBalanceChangeTest"

JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
ANDROID_HOME=/opt/homebrew/share/android-commandlinetools \
./gradlew :app:bundleRelease

bundletool validate \
  --bundle="Android Car Dealer Tracker/app/build/outputs/bundle/release/app-release.aab"

JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
jarsigner -verify \
  "Android Car Dealer Tracker/app/build/outputs/bundle/release/app-release.aab"

bundletool dump manifest \
  --bundle="Android Car Dealer Tracker/app/build/outputs/bundle/release/app-release.aab" \
  --module=base
```

Result: targeted billing/client/sale tests passed, `bundleRelease` passed,
`bundletool validate` passed, and `jarsigner` returned `jar verified.` The
latest local release AAB is `14M`, SHA-256
`3676623bce3f899496769771861efbd35b5ccfa9b152da6029a61c5bf9ebdbce`, package
`com.ezcar24.business`, version `2113 (2.1.13)`, with no Advertising ID
permission and Firebase ad-id collection still disabled.

Result after RevenueCat Android app setup and billing product ID parity pass:

```bash
JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
./gradlew :app:testDebugUnitTest --tests "com.ezcar24.business.data.billing.SubscriptionManagerTest" --tests "com.ezcar24.business.data.sync.ClientRemoteMappingTest" --tests "com.ezcar24.business.data.sync.SaleRemoteMappingTest" --tests "com.ezcar24.business.ui.sale.SaleBalanceChangeTest"

JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
./gradlew :app:assembleDebug

JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
./gradlew :app:bundleRelease
```

All three commands passed. `jarsigner -verify -verbose -certs` returned
`JARSIGNER_EXIT=0` and `jar verified.` for the latest release AAB. RevenueCat
project `EzCar24 Business` now contains Android app `EzCar24 Business Android`
with app id `app27b3a3dc3a`, package `com.ezcar24.business`, and a public SDK
key starting with `goog_`. Android billing code now accepts the real RevenueCat
product ids `com.ezcar24.business.weekly`, `com.ezcar24.business.monthly`,
`com.ezcar24.business.quarterly`, and `com.ezcar24.business.yearly`, while
keeping the older `ezcar24_weekly`, `ezcar24_monthly`, `ezcar24_quarterly`, and
`ezcar24_yearly` aliases as fallback. App Store Connect confirmed all four iOS
subscriptions are `APPROVED`, so Android keeps the same catalog for parity.

Result after Play privacy manifest cleanup:

```bash
JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
./gradlew :app:bundleRelease

bundletool validate --bundle="Android Car Dealer Tracker/app/build/outputs/bundle/release/app-release.aab"

bundletool dump manifest \
  --bundle="Android Car Dealer Tracker/app/build/outputs/bundle/release/app-release.aab" \
  --module=base
```

The release AAB passed `bundletool validate` with `BUNDLETOOL_EXIT=0`, and
`jarsigner` returned `JARSIGNER_EXIT=0` with `jar verified.` The final bundle
manifest no longer contains `com.google.android.gms.permission.AD_ID`,
`android.permission.ACCESS_ADSERVICES_AD_ID`,
`android.permission.ACCESS_ADSERVICES_ATTRIBUTION`,
`android.adservices.AD_SERVICES_CONFIG`, or `android.ext.adservices`.
Firebase Analytics ad-id collection and ad-personalization signals are disabled
via manifest metadata.

Result after first Play Console closed testing upload:

```text
Track: Closed testing - Alpha
Release: 2112 (2.1.12)
Artifact: app-release.aab
Status after submit: Changes in review
```

The latest release AAB was uploaded through Play Console because Android
Publisher API returned `Package not found` until the first Play artifact was
saved through the UI. Play accepted the AAB and showed:

```text
Version: 2112 (2.1.12)
API levels: 26+
Target SDK: 35
Screen layouts: 4
ABIs: 4
Required features: 1
New install size: 6.7 MB
```

Release notes used for `en-US`:

```text
Improved dashboard metrics, client and sales sync, subscriptions setup, account deletion flow, and release stability for Android.
```

Play reported one non-blocking warning:

```text
This App Bundle contains native code, and you've not uploaded debug symbols.
```

The warning affects crash/ANR symbolication quality, not Play upload validity.
After saving the release, `Send 14 changes for review` was confirmed from
Publishing overview. On 2026-06-13 23:17 UZT, Publishing overview still showed
`Changes in review` and `Running quick checks for commonly found issues` with
about 9 minutes remaining.

Rechecked on 2026-06-13 23:30 UZT: Publishing overview shows
`Changes in review`; the earlier quick-check countdown is no longer shown.

Rechecked via Android Publisher API on 2026-06-13 23:36 UZT:

- `subscriptions.list`: HTTP 204, no Google Play subscription products
  returned.
- Temporary `edits.insert`: HTTP 200, then deleted with HTTP 204.
- `track.alpha`: one release, version `2112`, status `completed`.
- `track.internal`: one draft release with no version code.
- `track.beta` and `track.production`: no releases.

Publishing overview in Play Console still shows `Changes in review`; Managed
publishing is off, so approved changes should publish automatically to closed
testing.

Rechecked on 2026-06-13 23:42 UZT:

- Play Console Publishing overview still shows `Changes in review`.
- `track.alpha`: one release, version `2112`, status `completed`.
- `subscriptions.list`: HTTP 204, no Google Play subscription products
  returned.

Rechecked via Android Publisher API on 2026-06-14 00:03 UZT:

- `subscriptions.list`: HTTP 204, no Google Play subscription products
  returned.
- Temporary `edits.insert`: HTTP 200, then deleted with HTTP 204.
- `track.alpha`: one release, version `2112`, status `completed`.
- `track.internal`: one draft release with no version code.
- `track.beta` and `track.production`: no releases.

Native debug symbols follow-up on 2026-06-13:

- Release build now has `android.buildTypes.release.ndk.debugSymbolLevel =
  "SYMBOL_TABLE"` configured.
- Rebuilt local release AAB passed `bundletool validate`.
- `jarsigner -verify -verbose -certs` returned `JARSIGNER_EXIT=0` and
  `jar verified.`
- Bundle manifest still contains no Advertising ID permissions and keeps
  Firebase ad-id collection disabled.
- No separate `native-debug-symbols.zip` was generated, and the rebuilt AAB did
  not contain native debug-symbol metadata. The only native libraries are
  dependency-provided `libandroidx.graphics.path.so` files, so the debug
  information appears to already be stripped in the dependency. Android
  documentation says this can happen when dependencies contain native
  libraries whose debug information has already been stripped.

Public listing URLs checked on 2026-06-13:

- `https://www.ezcar24.com/en/privacy-policy` returns HTTP 200.
- `https://www.ezcar24.com/en/delete-account` returns HTTP 200.

Runtime smoke on Xiaomi Redmi 15C debug install:

- Debug APK installed successfully via ADB.
- App process stayed alive after launch.
- Startup `get_my_organizations` network failures now log in `MainViewModel`
  instead of crashing the app.
- Room migration ran on the device database: `PRAGMA user_version` now returns
  `10`, and the `sales` table contains `vatRefundPercent` and
  `vatRefundAmount`.
- UI dump on the Xiaomi Dashboard confirmed the Android labels requested for
  iOS parity after the latest install: `Total Revenue`, `Sales Profit`,
  `Inventory`, `Vehicles Sold`, and `AI Insights Center`.
- Xiaomi Sales screen opened after the Sales Profit formula update without a
  crash. No test sale/client records were created during the smoke pass.
- Account settings now include a native in-app `Delete Account & Data` flow
  matching the iOS backend contract: the Android app posts `{}` to
  `delete_account`, expects `success: true`, then signs out and clears local
  session state. The destructive endpoint was not invoked during this smoke
  pass.
- Xiaomi smoke confirmed the Account screen, Security row, and delete-account
  confirmation dialog open without crashes. The dialog uses stacked fields for
  small Android screens and requires `DELETE` plus the account email before
  enabling the final delete action.
- After replacing direct Google BillingClient with RevenueCat SDK, the debug APK
  installed successfully on Xiaomi and launched without crash before the real
  Android key was added locally.
- After making destructive Room fallback debug-only, the latest debug APK
  `2.1.12` / `2112` installed successfully on Xiaomi Redmi 15C at
  `2026-06-13 21:41:48` and launched without crash-log entries.
- After the sales/client sync parity pass, the latest debug APK `2.1.12` /
  `2112` installed successfully on Xiaomi Redmi 15C at `2026-06-13 21:52:58`
  and launched without crash-log entries.
- After RevenueCat Android setup and billing ID parity, the latest debug APK
  `2.1.12` / `2112` installed successfully on Xiaomi Redmi 15C at
  `2026-06-13 22:29:38` and launched without crash-log entries.
- After Play privacy manifest cleanup, the latest debug APK `2.1.12` / `2112`
  installed successfully on Xiaomi Redmi 15C at `2026-06-13 22:58:23` and
  launched without `FATAL EXCEPTION` / `AndroidRuntime` crash entries.

Data parity note from the local debug device database:

- The old Android local dealer database still contained 7 active vehicle sale
  rows totaling `876600.00`.
- The corrected iOS-parity Dashboard formula also includes active part sales;
  this debug database has active part sales totaling `12256.00`, so the local
  debug Dashboard shows `888856.00` Total Revenue.
- One active sale row had no `vehicleId`, which explains why the old Android
  Dashboard could display a larger Total Revenue than iOS on that device.
- The local debug database also contains obvious test records, so do not use
  this phone database as production revenue evidence without a fresh sync or
  reviewed cleanup.
- No automatic data cleanup was performed. Production data changes must remain
  explicit and reviewable.

Google Play Developer API candidate key is configured in Keychain under:

```text
googleplay.com.ezcar24.business.service_account_json_path
```

The canonical local JSON path for this project-specific Keychain entry is:

```text
~/.hermes/secrets/google-play/com.ezcar24.business-service-account.json
```

The file exists with mode `600`. A duplicate copy currently also exists under
`~/Library/Application Support/EzCar24Business/Keys/`; both files matched byte
for byte when checked on 2026-06-13.

The key can obtain a Google OAuth token, but Android Publisher API currently
returns:

```text
Package not found: com.ezcar24.business.
```

Rechecked on 2026-06-13 20:53 UZT:

- OAuth token exchange: OK.
- Android Publisher `edits.insert`: HTTP 404 `NOT_FOUND`.
- Message: `Package not found: com.ezcar24.business.`

This means the service account does not currently see the Play Console app, or
the app has not been created in Play Console with package `com.ezcar24.business`.
Next Play Console step: create/open the app with package `com.ezcar24.business`
and grant this service account app access before attempting an internal testing
upload through the API.

Rechecked on 2026-06-13 22:31 UZT:

- Play Console UI shows app `Car Dealer Tracker` at app id `4972106538142649755`.
- The same service account still receives Android Publisher API HTTP 404
  `NOT_FOUND` for package `com.ezcar24.business`.
- Store subscriptions page is blocked in Play Console with:
  `You need to set up a Google Payments merchant account to access this page`.
- Dashboard shows closed testing production-access requirement:
  `0 testers currently opted-in`; Google requires at least 12 opted-in testers
  and a closed test for at least 14 days before applying for production access.

Rechecked on 2026-06-13 22:59 UZT before first Play Console upload:

- OAuth token exchange: OK.
- Android Publisher `edits.insert`: HTTP 404 `NOT_FOUND`.
- Message: `Package not found: com.ezcar24.business.`
- Local release AAB, package id, signing, and `bundletool validate` all pass;
  the remaining API issue is Play Console access/visibility for the service
  account, not a local build artifact problem.

Rechecked on 2026-06-13 23:14 UZT after the first Play Console upload:

- Android Publisher `edits.insert`: HTTP 200.
- A temporary API edit was created successfully and then deleted with HTTP 204.
- The previous `Package not found: com.ezcar24.business` blocker is resolved.

A read-only helper script now checks Google Play API state without opening
Chrome:

```bash
scripts/play_release_status.py
```

The helper below creates/activates the expected Google Play subscription
products without opening Chrome:

```bash
scripts/play_prepare_subscriptions.py
```

The helper below uploads the current release AAB to Google Play closed testing
without opening Chrome:

```bash
scripts/play_upload_aab.py
```

Google Play subscription setup via Android Publisher API on 2026-06-14
01:55 UZT:

```bash
./scripts/play_prepare_subscriptions.py
./scripts/play_prepare_subscriptions.py --apply
./scripts/play_prepare_subscriptions.py --apply --activate
./scripts/play_release_status.py
```

The preparation script uses App Store Connect-confirmed USA prices and Google
Play `pricing:convertRegionPrices` for regional prices:

- `com.ezcar24.business.weekly`: `3.99 USD`, `P1W`
- `com.ezcar24.business.monthly`: `14.99 USD`, `P1M`
- `com.ezcar24.business.quarterly`: `24.99 USD`, `P3M`
- `com.ezcar24.business.yearly`: `119.99 USD`, `P1Y`

Current output on 2026-06-14 02:12 UZT:

```text
package: com.ezcar24.business
subscriptions: HTTP 200; count=4
  - com.ezcar24.business.monthly; basePlans=1; listings=1; states=[monthly:ACTIVE]
  - com.ezcar24.business.quarterly; basePlans=1; listings=1; states=[quarterly:ACTIVE]
  - com.ezcar24.business.weekly; basePlans=1; listings=1; states=[weekly:ACTIVE]
  - com.ezcar24.business.yearly; basePlans=1; listings=1; states=[yearly:ACTIVE]
subscriptions.expected:
  - com.ezcar24.business.weekly: HTTP 200; basePlans=1; listings=1; states=[weekly:ACTIVE]
  - com.ezcar24.business.monthly: HTTP 200; basePlans=1; listings=1; states=[monthly:ACTIVE]
  - com.ezcar24.business.quarterly: HTTP 200; basePlans=1; listings=1; states=[quarterly:ACTIVE]
  - com.ezcar24.business.yearly: HTTP 200; basePlans=1; listings=1; states=[yearly:ACTIVE]
edits.insert: HTTP 200; temporary edit created
track.internal: releases=1; versions=[]; statuses=['draft']
track.alpha: releases=1; versions=['2114']; statuses=['completed']
track.beta: releases=0; versions=[]; statuses=[]
track.production: releases=0; versions=[]; statuses=[]
edits.delete: HTTP 204
```

RevenueCat Android product/offering setup via Management API on 2026-06-14
02:12 UZT:

```bash
./scripts/revenuecat_prepare_android_products.py
./scripts/revenuecat_prepare_android_products.py --apply
./scripts/revenuecat_prepare_android_products.py
```

Result:

```text
android_app: EzCar24 Business Android (app27b3a3dc3a)
default_offering: ofrng51f329a569; is_current=True
entitlement: EzCar24 Business Pro (entl6673ef1e66)
com.ezcar24.business.weekly:weekly: product exists
com.ezcar24.business.monthly:monthly: product exists
com.ezcar24.business.quarterly:quarterly: product exists
com.ezcar24.business.yearly:yearly: product exists
entitlement_missing_android_products=0
$rc_weekly: android product attached
$rc_monthly: android product attached
$rc_three_month: android product attached
$rc_annual: android product attached
```

The public Android offerings check initially returned `count=0` immediately
after configuration. It was rechecked at 2026-06-14 14:30 UZT and now returns
`count=1`, current offering `default`, and all four Android products:

- `com.ezcar24.business.weekly`
- `com.ezcar24.business.monthly`
- `com.ezcar24.business.quarterly`
- `com.ezcar24.business.yearly`

Rechecked on 2026-06-14 02:27 UZT after Merchant Payment Setup:

- Google Play API still returns all four expected subscription products as
  `ACTIVE`.
- Play `alpha` track still contains closed testing release `2114` with status
  `completed`.
- RevenueCat Management API still returns all four Android products attached to
  the Pro entitlement and default packages.
- RevenueCat Android app package name is `com.ezcar24.business`.
- Local Android SDK key matches the RevenueCat Android app public API key.
- The SDK-facing public offerings endpoint now returns current offering
  `default` and all four Android products. RevenueCat propagation is clear.
- The next billing check is only the real Play-installed tester-build smoke:
  open paywall, confirm 4 plans, run test purchase, then restore.
- `adb devices` currently returns no connected devices, so Xiaomi installation
  cannot be verified until the phone is visible again.

Google Play closed testing AAB upload via Android Publisher API on 2026-06-14
01:59 UZT:

```bash
./scripts/play_upload_aab.py
./scripts/play_upload_aab.py --apply --commit
./scripts/play_release_status.py
```

Upload result:

```text
package: com.ezcar24.business
aab: /Users/shokhabbos/Desktop/CarDealerTracker-ios-android/Android Car Dealer Tracker/app/build/outputs/bundle/release/app-release.aab
size_mb: 14.2
sha256: 3676623bce3f899496769771861efbd35b5ccfa9b152da6029a61c5bf9ebdbce
track: alpha
release_name: 2.1.13 (2113)
mode: apply
edits.insert: HTTP 200
bundles.upload: HTTP 200; versionCode=2113
tracks.update: HTTP 200; track=alpha; versionCode=2113
edits.validate: HTTP 200
edits.commit: HTTP 200
```

Google Play closed testing AAB upload via Android Publisher API on 2026-06-14
02:12 UZT after RevenueCat Google Play base-plan identifier support:

```bash
JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
./gradlew :app:testDebugUnitTest --tests "com.ezcar24.business.data.billing.SubscriptionManagerTest"

JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
ANDROID_HOME=/opt/homebrew/share/android-commandlinetools \
./gradlew :app:bundleRelease

bundletool validate \
  --bundle="Android Car Dealer Tracker/app/build/outputs/bundle/release/app-release.aab"

JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
jarsigner -verify \
  "Android Car Dealer Tracker/app/build/outputs/bundle/release/app-release.aab"

./scripts/play_upload_aab.py --apply --commit
./scripts/play_release_status.py
```

Upload result:

```text
package: com.ezcar24.business
size_mb: 14.2
sha256: e6257a5aab16923f249e8aaf63d97ec02401c1f929357fe80c007b484703e645
track: alpha
release_name: 2.1.14 (2114)
mode: apply
edits.insert: HTTP 200
bundles.upload: HTTP 200; versionCode=2114
tracks.update: HTTP 200; track=alpha; versionCode=2114
edits.validate: HTTP 200
edits.commit: HTTP 200
```

The same key cannot currently fetch Firebase Android config. Firebase Management
API is disabled or unavailable for that Google Cloud/Firebase project.

## Remaining Play blockers

- Closed testing release `2114 (2.1.14)` is committed to the Play `alpha`
  track with status `completed`. If Play Console still shows `Changes in
  review`, wait for Google review to finish.
- Production access is still not ready: Play Console previously showed
  `0 testers currently opted-in`; Google requires at least 12 opted-in testers
  and at least 14 days of closed testing before production access can be
  requested. Official reference:
  `https://support.google.com/googleplay/android-developer/answer/14151465`.
- Google Play subscription products are created and active for weekly, monthly,
  quarterly, and yearly. RevenueCat Android products are also created and
  attached to the Pro entitlement and default offering packages. The remaining
  subscription check is runtime: a tester-installed Play build must show Android
  plans in the paywall after propagation.
- The next Play upload after this one must increment beyond version code
  `2114`.
- Native debug symbol configuration has been added for future AABs. The current
  native libraries appear to be dependency-provided and already stripped, so no
  separate uploadable `native-debug-symbols.zip` was generated locally.
- The local Xiaomi debug database contains stale/test sale records. For a clean
  smoke test against production data, clear only the debug app data after
  confirming no unsynced test data needs to be kept, then sign in and sync
  fresh.

## Security cleanup before final release

- `opencode.json` no longer stores the Rube MCP bearer token; the checked-in
  MCP entry is disabled.
- Local Rube/OpenCode credentials must live outside the repository. See
  `docs/local-opencode-config.md`.
- If the previous checked-in Rube token was real, revoke or rotate it before
  using Rube again. The token may still exist in git history until history is
  rewritten or the token is invalidated.
- Local generated build/error logs were removed from tracked files:
  `Android Car Dealer Tracker/build_log_*.txt` and
  `Android Car Dealer Tracker/.kotlin/errors/*.log`. `.gitignore` now excludes
  future copies of those files.

## Release signing key

- Keystore path: `/Users/shokhabbos/.android-signing/ezcar24/ezcar24-business-release.jks`
- Key alias: `ezcar24business-upload`
- SHA-256 fingerprint for Android developer verification:

```text
55:B2:2C:4F:D0:42:98:4E:53:08:2D:31:3F:A7:B4:76:02:81:EC:EA:28:76:C6:C0:26:00:37:02:D8:C2:D8:55
```

## macOS Keychain entries

Signing secrets are stored in macOS Keychain, not in Git.

- Account: `com.ezcar24.business`
- Keystore path service: `googleplay.com.ezcar24.business.upload_keystore_path`
- Keystore password service: `googleplay.com.ezcar24.business.upload_keystore_password`
- Key alias service: `googleplay.com.ezcar24.business.upload_key_alias`
- Key password service: `googleplay.com.ezcar24.business.upload_key_password`

To retrieve a value manually:

```bash
security find-generic-password -w \
  -a "com.ezcar24.business" \
  -s "googleplay.com.ezcar24.business.upload_keystore_path"
```

Use the same pattern for the other services.

## Local Gradle signing config

The local file below was created so Gradle can sign release builds:

```text
Android Car Dealer Tracker/keystore.properties
```

This file contains signing passwords and is ignored by Git via `.gitignore`.

## Local Java

OpenJDK 17 is installed through Homebrew. For Gradle commands in Terminal, use:

```bash
export JAVA_HOME="$(brew --prefix openjdk@17)/libexec/openjdk.jdk/Contents/Home"
```

Signing was verified with:

```bash
JAVA_HOME="$(brew --prefix openjdk@17)/libexec/openjdk.jdk/Contents/Home" ./gradlew :app:signingReport
```
