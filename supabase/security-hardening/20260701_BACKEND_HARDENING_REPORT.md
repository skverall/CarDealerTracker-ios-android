# Ezcar24 Supabase Backend Hardening Report

Date: 2026-07-01
Project ref: `haordpdxyyreliyzmire`

## Applied Migrations

- `20260701095758_harden_admin_identity_storage_and_anon_grants.sql`
  - Live Supabase migration history version: `20260701100636`
- `20260701100835_restore_crm_can_access_for_rls_policies.sql`
  - Live Supabase migration history version: `20260701100852`

Rollback script:

- `supabase/security-hardening/20260701_ROLLBACK_admin_identity_storage_and_anon_grants.sql`

## What Changed

### Admin Listing RPC Identity

The nine listing admin RPCs now resolve the acting admin through `public.require_admin_session(p_session_token, p_admin_user_id)` and use the returned admin row for audit-sensitive fields:

- `admin_add_listing_note`
- `admin_archive_listing`
- `admin_mark_listing_sold`
- `admin_moderate_listing`
- `admin_restore_listing`
- `admin_send_message_to_seller`
- `admin_unmark_listing_sold`
- `admin_update_listing_fields`
- `admin_update_listing_images`

The RPC signatures and JSON response shape were preserved. Invalid or mismatched sessions still return:

```json
{"success": false, "error": "Invalid or expired admin session"}
```

### Storage Listing Policies

The broad public `SELECT` policies on `storage.objects` for these public buckets were removed:

- `avatars`
- `car-reports`
- `listing-images`

They were replaced with owner-scoped authenticated `SELECT` policies for list/info/upload-update support. Public object URLs still work because public buckets do not require a table `SELECT` policy for direct object delivery.

### RLS No-Policy Tables

Explicit deny-only policies were added to the RLS-enabled tables that previously had no policies:

- `public.app_feedback_requests`
- `public.app_feedback_votes`
- `public.app_feedback_views`
- `public.ai_insight_reports`
- `public.monthly_report_deliveries`
- `public.monthly_report_preferences`
- `public.organization_deal_desk_settings`
- `public.organization_holding_cost_settings`
- `app_private.admin_bot_events`
- `app_private.admin_bot_alert_deliveries`

### Anonymous EXECUTE Grants

Anonymous `EXECUTE` was revoked from confirmed dealer-only RPCs such as organization, team, referral, vehicle-share, deal-desk, and CRM permission helpers. `process_referral_reward` is now `service_role` only.

`crm_can_access(uuid)` was intentionally restored to `PUBLIC` after validation because existing RLS policies with `roles = public` call it for denied/list paths across CRM and storage policy checks. Revoking it caused anonymous storage queries to fail with `permission denied for function crm_can_access` instead of cleanly returning no rows. A future policy rewrite can move those dependent policies to `TO authenticated`, then this grant can be revisited safely.

## Validation

### Advisor / Metadata Counts

| Metric | Result |
| --- | ---: |
| RLS-enabled tables with no policies | 0 |
| Broad public storage listing policies on target buckets | 0 |
| SECURITY DEFINER functions without `search_path` | 0 |
| Anonymous executable SECURITY DEFINER functions | 52 |
| Authenticated executable SECURITY DEFINER functions | 86 |

Remaining advisor warnings are expected for the current architecture until handled separately:

- Intentionally exposed pre-auth admin and marketplace RPCs that use token/session parameters.
- Signed-in callable SECURITY DEFINER RPCs that are legitimate app APIs but should continue to be audited in smaller batches.
- Leaked password protection is disabled in Supabase Auth.
- Supabase Postgres has security patches available.

### Runtime Checks

Transactional validation created a temporary admin user/session, exercised the hardened admin RPCs, then removed all test rows.

Passed:

- All nine RPCs rejected mismatched `p_admin_user_id` plus valid token with the existing invalid-session JSON response.
- Invalid token was rejected before mutation.
- No note, message, or activity-log rows were written for the mismatched admin id.
- Matching session tests confirmed token-derived admin id is written to:
  - `listing_admin_notes.admin_user_id`
  - `listings.moderated_by`
  - `messages.sender_id`
  - `admin_activity_log.admin_user_id`
- Cleanup left zero `codex-hardening-*` admin/session/note/message rows.
- Anonymous storage listing for `avatars`, `car-reports`, and `listing-images` returns no rows without error.
- Existing public object URLs for all three buckets still return `200`.

Observed legacy runtime issues that were intentionally left out of this hardening batch:

- `admin_archive_listing` still attempts to set `listings.status = 'inactive'`, but the live `listings_status_check` constraint allows only `active` and `sold`.
- `admin_moderate_listing(..., 'reject', ...)` can hit the same `inactive` status constraint when rejecting an active listing.
- `admin_update_listing_fields` still references `listings.location`, but the live table has `city` and no `location` column.

These marketplace admin RPC behavior bugs were fixed in the follow-up migration documented in `20260701_MARKETPLACE_ADMIN_RPC_RUNTIME_FIX_REPORT.md`.
