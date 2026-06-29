# Android vs iOS Parity Audit - 2026-06-29

Scope: code-level parity audit for the Android app against the current iOS implementation, focused on the user-reported gaps in reports/PDF, AI Insights, account loading, and team/subaccount management. This is not a full certification that every iOS feature is now identical; it is the working parity ledger for the remaining Android catch-up.

## P0 - Reports and PDF Export

Status: partially fixed.

iOS evidence:
- `iOS Car Dealer Tracker/Ezcar24Business/Views/BackupCenterView.swift`
- `iOS Car Dealer Tracker/Ezcar24Business/Services/BackupExportManager.swift`
- `iOS Car Dealer Tracker/Ezcar24Business/Views/MonthlyReportPreviewView.swift`
- `iOS Car Dealer Tracker/Ezcar24Business/Services/MonthlyReportSnapshotBuilder.swift`

Android evidence:
- `Android Car Dealer Tracker/app/src/main/java/com/ezcar24/business/ui/settings/BackupCenterScreen.kt`
- `Android Car Dealer Tracker/app/src/main/java/com/ezcar24/business/ui/settings/BackupCenterViewModel.kt`
- `Android Car Dealer Tracker/app/src/main/java/com/ezcar24/business/ui/settings/MonthlyReportPreviewScreen.kt`
- `Android Car Dealer Tracker/app/src/main/java/com/ezcar24/business/data/repository/MonthlyReportRepository.kt`

Findings:
- Android already had a rich monthly report preview and PDF export, but Backup Center did not use it.
- Backup Center generated a separate one-page PDF with only financial overview and top sold vehicles.
- Android Backup Center did not expose scheduled email reports from the Backup screen the way iOS does.
- Android date-range export silently swapped invalid dates instead of showing a validation state.

Changes applied:
- Backup Center now includes a Scheduled Reports entry that opens Monthly Report settings.
- Custom report date range defaults to the last month instead of a single-day range.
- Invalid date ranges now show an error and disable report/archive generation.
- Monthly report PDF rendering was extracted to `MonthlyReportPdfRenderer`.
- Backup Center custom PDF now uses the same rich report renderer as Monthly Report preview.
- `MonthlyReportRepository` now supports local snapshots for arbitrary calendar-day ranges.
- Archive metadata now uses full calendar-day start/end boundaries.

Remaining work:
- Smoke-test generated PDF text on a real Android device/emulator.
- Compare Android generated PDF pages against iOS PDF sections with sample data.
- Consider adding Android unit coverage for custom date range snapshot boundaries.

## P0 - AI Insights

Status: not functionally matched yet; visual overflow mitigation applied.

iOS evidence:
- `iOS Car Dealer Tracker/Ezcar24Business/Views/Analytics/AnalyticsHubView.swift`

Android evidence:
- `Android Car Dealer Tracker/app/src/main/java/com/ezcar24/business/ui/analytics/AnalyticsHubScreen.kt`

Findings:
- iOS has a real AI Insights flow with `AIInsightsViewModel`, Supabase `ai-insights` function calls, generation/regeneration, history, language filtering, usage limits, cache fingerprinting, and paywall handling.
- Android currently has a static AI Insights Center UI and destination cards.
- Android does not yet call the `ai-insights` function.
- Android does not yet have Generate/Regenerate report behavior, history, usage bar, or Pro gating matching iOS.
- Large AI metric values could overflow visually.

Changes applied:
- AI metric tiles now use auto-resizing text for large values.
- Hero pulse pills are horizontally scrollable to avoid cramped overflow.

Remaining work:
- Port the iOS AI Insights request/response models to Android.
- Add an Android `AIInsightsViewModel` and repository that invokes `ai-insights` with additive client-side behavior only.
- Add generate/regenerate button, loading skeleton, history list, usage bar, error states, paywall behavior, and cache fingerprinting.
- Add localization coverage for all AI Insights strings.
- Test logged-in Pro and non-Pro states.

## P1 - Account Loading Performance

Status: partially fixed.

Android evidence:
- `Android Car Dealer Tracker/app/src/main/java/com/ezcar24/business/ui/settings/SettingsViewModel.kt`
- `Android Car Dealer Tracker/app/src/main/java/com/ezcar24/business/data/repository/AccountRepository.kt`
- `Android Car Dealer Tracker/app/src/main/java/com/ezcar24/business/ui/settings/TeamMembersViewModel.kt`

Findings:
- Opening Account/Settings reloaded organizations and referral stats even when repository state already had them.
- Team members were fetched from backend every Team screen open.

Changes applied:
- `SettingsViewModel.loadProfile()` now uses cached organizations, active organization, and referral stats when available.
- `AccountRepository.fetchTeamMembers()` now has a short 60 second cache.
- Team mutations force-refresh the team list after invite/update/remove.

Remaining work:
- Measure Account open and Team screen open with logcat timing or Android Studio profiler.
- Add explicit pull-to-refresh behavior if product wants a guaranteed live team refresh.

## P1 - Team/Subaccounts

Status: present on Android, parity still needs UX verification.

iOS evidence:
- `iOS Car Dealer Tracker/Ezcar24Business/Views/TeamManagementView.swift`
- `iOS Car Dealer Tracker/Ezcar24Business/Views/UserManagementView.swift`
- `iOS Car Dealer Tracker/Ezcar24Business/Views/AccountView.swift`

Android evidence:
- `Android Car Dealer Tracker/app/src/main/java/com/ezcar24/business/ui/settings/TeamMembersScreen.kt`
- `Android Car Dealer Tracker/app/src/main/java/com/ezcar24/business/ui/settings/TeamMembersViewModel.kt`
- `Android Car Dealer Tracker/app/src/main/java/com/ezcar24/business/data/repository/AccountRepository.kt`

Findings:
- Android has team invite, role selection, permission toggles, pending invite display, invite cancellation, member removal, and "Create account now" with generated password display.
- The complaint is therefore likely about discoverability, visual parity, loading behavior, or an incomplete live flow rather than total absence.

Remaining work:
- Run logged-in Android UI flow: Account -> Team Members -> invite with create account -> generated password -> edit access -> remove/cancel.
- Compare visual states with iOS Team Management and User Management.
- Verify role/permission labels and localization match iOS strings.

## P2 - Navigation and Settings Parity

Status: ongoing.

Findings:
- Android Settings has management tools, backup center, monthly reports, team members, financial accounts, holding cost, and ideas board routes.
- Some iOS pathways are more discoverable because related tools are grouped together inside the same screen.

Changes applied:
- Backup Center now links directly to Scheduled Reports.

Remaining work:
- Build a complete navigation parity table for Account, Backup, Reports, Team, AI, Analytics, Expenses, and Finance.

## Safety Notes

- No Supabase schema, RPC, RLS, Auth configuration, Edge Function contract, or production data migration was changed.
- No financial calculation formula was intentionally changed. Custom date-range PDF export now reuses the existing Android monthly report snapshot logic for report composition.
- Existing simple archive JSON field names were preserved.

## Verification Plan

1. Run Android debug build:
   `cd "Android Car Dealer Tracker" && GRADLE_USER_HOME=/Volumes/LexarDev/Developer/Gradle ./gradlew :app:assembleDebug`
2. Run `git diff --check`.
3. Install on Android device/emulator and smoke-test:
   - Account opens without repeated full organization reload.
   - Backup Center shows Scheduled Reports.
   - Custom PDF report generates and shares.
   - Monthly preview PDF still generates and shares.
   - AI Insights metric cards do not overflow.
   - Team Members screen opens, caches repeat load, and force-refreshes after invite/update/remove.
4. Continue the P0 AI Insights port before calling Android parity complete.
