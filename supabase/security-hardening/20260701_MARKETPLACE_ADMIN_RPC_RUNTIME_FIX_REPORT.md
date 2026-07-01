# Marketplace Admin RPC Runtime Fix Report

Date: 2026-07-01
Project ref: `haordpdxyyreliyzmire`

## Applied Migration

- `supabase/migrations/20260701110446_fix_marketplace_admin_listing_runtime.sql`
  - Live Supabase migration history version: `20260701111028`

Rollback script:

- `supabase/security-hardening/20260701_ROLLBACK_marketplace_admin_listing_runtime_fix.sql`

## What Changed

The fix is limited to marketplace listing admin RPC runtime failures found during the security-hardening validation. No table constraints, RLS policies, Edge Function contracts, mobile sync models, or financial calculations were changed.

### `admin_archive_listing(uuid, uuid, text)`

Before: attempted `status = 'inactive'`, but the live `listings_status_check` allows only `active` and `sold`.

Now: soft-archives with existing `deleted_at = COALESCE(deleted_at, now())` and preserves the current `status`.

### `admin_restore_listing(uuid, uuid, text)`

Before: restored `status = 'active'` only.

Now: restores `status = 'active'` and clears `deleted_at`, so listings archived by the fixed archive RPC can be restored.

### `admin_moderate_listing(uuid, uuid, text, text, text)`

Before: reject path attempted to move active listings to `status = 'inactive'`.

Now: reject path keeps the allowed status value and hides the listing with existing `is_draft = true`; approve path keeps restoring `status = 'active'` and `is_draft = false`.

### `admin_moderate_listing(uuid, uuid, text, text)`

The legacy tokenless overload received the same reject/approve visibility behavior. Its signature and JSON return type were preserved.

Direct SQL calls with exactly four positional args remain ambiguous because the five-arg overload has a default `p_session_token`. This is existing overload architecture, not introduced by this migration. The function body compiles and remains available for clients that resolve RPCs by named parameters.

### `admin_update_listing_fields(uuid, uuid, text, text, numeric, text, text)`

Before: attempted to update non-existent `listings.location`.

Now: keeps the existing `p_location` API parameter but writes it to the live `listings.city` column.

## Validation

Dry-run validation was performed inside a rolled-back transaction before applying the migration.

Live validation after applying the migration passed:

- Mismatched admin id plus valid session token is still rejected with `Invalid or expired admin session`.
- `admin_archive_listing` succeeds and sets `deleted_at` without writing invalid `status = 'inactive'`.
- `admin_restore_listing` succeeds and clears `deleted_at`.
- Five-arg `admin_moderate_listing(..., 'reject', ...)` succeeds, writes `moderation_status = 'rejected'`, sets `is_draft = true`, and does not write invalid `status = 'inactive'`.
- Five-arg `admin_moderate_listing(..., 'approve', ...)` succeeds and restores `is_draft = false` plus `status = 'active'`.
- `admin_update_listing_fields` succeeds and writes the location parameter into `city`.
- No activity rows were written for a mismatched admin id.
- Cleanup left zero `codex-runtime-live-*` admin, session, or activity rows.
