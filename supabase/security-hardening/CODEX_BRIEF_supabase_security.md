# Task brief: harden the Ezcar24 Supabase backend (for OpenAI Codex)

You are hardening the security of a **shared production Supabase project**. This brief is
self-contained — everything you need is below. Read the **Constraints / DO NOT** section
before touching anything: a careless change here locks admins out of a live marketplace.

---

## 1. Context you must know

- **Supabase project:** name `Ezcar24.com`, ref/project_id **`haordpdxyyreliyzmire`**, Postgres 17.
- This one database backs **two separate products**:
  1. **CarDealerTracker** dealer apps (iOS/Android/web) — sign in with **Supabase Auth**, call RPCs as the **`authenticated`** role. Prefixes: `crm_*`, `get_my_*`, `app_feedback_*`, referral funcs, `organization_*`.
  2. **ezcar24.com consumer marketplace + its admin panel** — the admin panel does **NOT** use Supabase Auth. It uses a **custom auth system** and connects with the Supabase **anon key**, passing a session token as an RPC parameter on every call.
- **The marketplace + admin-panel source code is in a DIFFERENT repository** (not the CarDealerTracker repo where this brief lives). Any change that alters an RPC signature **must be mirrored in that repo's RPC calls** — you will need access to it.

### The custom admin auth system (tables + canonical validators)
- `public.admin_users` (id uuid, username, password_hash, `role` IN `('admin','moderator','super_admin')`, is_active bool, failed_login_attempts, locked_until, …)
- `public.admin_sessions` (id, admin_user_id → admin_users.id, session_token text, is_active bool, expires_at timestamptz, last_activity_at, ip_address, user_agent)
- `public.authenticate_admin(p_username, p_password, p_ip_address, p_user_agent)` → jsonb, issues a `session_token` (12h TTL). **anon-executable by necessity (it is the login endpoint).**
- `public.require_admin_session(p_session_token, p_admin_user_id default null)` → returns an `admin_users` row, **RAISES** on invalid/expired. This is the **canonical validator** — it derives the admin from the token.
- `public.validate_admin_session(p_session_token)` → jsonb `{valid, user}`.
- Support funcs: `verify_password`, `hash_password`, `change_admin_password`, `logout_admin`, `provision_admin_user`, `clean_expired_admin_sessions`.

---

## 2. What has ALREADY been fixed (do NOT redo)

On 2026-07-01 the following were already applied to project `haordpdxyyreliyzmire`:

1. **9 listing-moderation RPCs** had *optional* session validation (`IF p_session_token IS NOT NULL THEN … END IF`) with `p_session_token text DEFAULT NULL`, so an anon caller could bypass auth by passing NULL. Validation is now **mandatory** (NULL/invalid token → `{"success":false,"error":"Invalid or expired admin session"}`). Signatures unchanged. Functions: `admin_add_listing_note`, `admin_archive_listing`, `admin_mark_listing_sold`, `admin_moderate_listing` (5-arg overload), `admin_restore_listing`, `admin_send_message_to_seller`, `admin_unmark_listing_sold`, `admin_update_listing_fields`, `admin_update_listing_images`. Rollback: `supabase/security-hardening/20260701_ROLLBACK_admin_listing_functions.sql`.
2. The token-less 4-arg overload `admin_moderate_listing(uuid,uuid,text,text)` got a mandatory `admin_users` role check (it has no token param to validate).
3. `public.build_monthly_report_preferences_payload(...)` got `SET search_path TO 'pg_catalog'` (was mutable).

Your job is the **deeper redesign** + the **remaining advisor items** below.

---

## 3. Tasks

### Task A — Stop trusting the client-supplied `p_admin_user_id` (core redesign)
Many admin RPCs accept `p_admin_user_id uuid` as a **separate parameter** and use it for
authorization and for audit fields (`moderated_by`, `log_admin_activity(...)`). The admin
identity must come **only from the validated session token**, never from a client-supplied
uuid.

For every `admin_*` / `*_for_admin` SECURITY DEFINER function that takes a session token:
1. Resolve the admin **from the token** via `require_admin_session(p_session_token)` (returns the `admin_users` row, RAISES on failure). Use its `.id` as the effective admin id.
2. If the function still declares `p_admin_user_id` in its signature (keep it for PostgREST call-compatibility), **ignore its value for trust decisions** — instead assert `resolved.id = p_admin_user_id` and reject on mismatch, or simply overwrite all uses with `resolved.id`.
3. Use `resolved.id` for `moderated_by`, `sender_id`, `log_admin_activity(...)`, etc.
4. Enforce role where relevant (e.g. moderation requires `role IN ('admin','moderator','super_admin')`).
5. **Preserve the exact function signature** (param names, order, defaults, return type) so existing PostgREST calls keep resolving. Only change the body.

Then **remove the redundant token-less overloads** that can't validate a session (e.g. the
4-arg `admin_moderate_listing`) **only after** confirming the admin-panel repo no longer calls
that signature.

**Acceptance:** for each function, a call with a valid token but a *mismatched* `p_admin_user_id`
is rejected; a call with a valid token and matching id behaves exactly as before; audit rows
record the token-derived admin id.

### Task B — Audit `anon` EXECUTE grants (73 functions flagged)
`get_advisors(security)` flags 73 SECURITY DEFINER funcs executable by `anon`. Most are
**intentional** (the admin panel calls them as anon with a session token; and pre-auth funcs
like `authenticate_admin` MUST be anon). For each flagged function decide:
- **Keep anon**: any admin-panel/marketplace/pre-auth function (validates a token or credentials internally).
- **Revoke anon** (keep `authenticated`): functions used **only** by the CarDealerTracker dealer apps, which always call as `authenticated` (e.g. verify each `crm_*`, `get_my_*`, referral, `organization_*` helper is never invoked from an anon context). Revoke only after confirming no anon caller.

**Acceptance:** produce a table (function → verdict → reason). Apply revokes only for the confirmed dealer-app-only set. **Never** revoke from `authenticate_admin`, `validate_admin_session`, `require_admin_session`, or any pre-login function.

### Task C — Tighten public storage buckets
Buckets `avatars`, `car-reports`, `listing-images` are public AND have broad SELECT policies on
`storage.objects` that let clients **list all files**. Public object-URL access does not need
listing. Narrow/remove the broad `SELECT` policies so direct object URLs still work but
enumeration is blocked. Verify a known object URL still loads afterward.

### Task D — RLS "enabled but no policy" (INFO) — confirm & document
Tables flagged: `public.app_feedback_requests`, `app_feedback_votes`, `app_feedback_views`,
`ai_insight_reports`, `monthly_report_deliveries`, `monthly_report_preferences`,
`organization_deal_desk_settings`, `organization_holding_cost_settings`,
`app_private.admin_bot_events`, `app_private.admin_bot_alert_deliveries`. These are reached only
via SECURITY DEFINER RPCs, so "no policy" = deny-all direct access = intentional. Either add an
explicit `USING (false)` deny policy for clarity, or document why each is safe. Do not open them up.

### Task E — Remaining `function_search_path_mutable`
Scan all `public`/`app_private` functions for a role-mutable `search_path` and pin it
(`SET search_path TO …`). One was already fixed (`build_monthly_report_preferences_payload`).

### Task F — Dashboard-only items (cannot be done via SQL migration — hand back to the human)
- Enable **Auth → leaked-password protection** (HaveIBeenPwned).
- **Upgrade Postgres** (`supabase-postgres-17.4.1.069` has outstanding security patches) — needs a maintenance window.
List these clearly in your final report as manual owner actions.

---

## 4. Constraints / DO NOT

- **DO NOT** `REVOKE … FROM anon` on `authenticate_admin`, `validate_admin_session`, `require_admin_session`, `logout_admin`, `provision_admin_user`, `change_admin_password`, or any function the admin panel/marketplace calls pre-auth — the admin panel authenticates as **anon**, so this breaks admin login entirely.
- **DO NOT** change RPC signatures (param names/order/defaults/return type) unless you also update the marketplace/admin-panel repo that calls them. Prefer body-only changes.
- **DO NOT** switch these to `SECURITY INVOKER` blindly — they need definer rights to read `admin_users`/`admin_sessions`.
- **Preserve return shapes** (`{"success":bool,"error":…}` vs RAISE) — the panel parses them.
- Save a rollback for every batch (see the existing `20260701_ROLLBACK_admin_listing_functions.sql` as the pattern).
- Apply changes to project `haordpdxyyreliyzmire`. Work on a Supabase **branch** first if possible, then merge.

## 5. Verification

- Run `get_advisors(security)` before and after; confirm the WARN count drops and no new ones appear.
- For each hardened function: (a) valid token + matching id → works; (b) NULL/invalid token → rejected error, **no data mutated**; (c) valid token + mismatched `p_admin_user_id` → rejected.
- Confirm the admin panel still logs in and can moderate/edit a listing (needs the marketplace repo running).
- Confirm a known public object URL (avatar/listing image) still loads after Task C.

## 6. Reference — current audit findings (from get_advisors, 2026-07-01)
- 83 × `authenticated_security_definer_function_executable` (WARN)
- 73 × `anon_security_definer_function_executable` (WARN) ← Task B
- 10 × `rls_enabled_no_policy` (INFO) ← Task D
- 3 × `public_bucket_allows_listing` (WARN) ← Task C
- 1 × `function_search_path_mutable` (WARN, 1 already fixed) ← Task E
- 1 × `auth_leaked_password_protection` (WARN) ← Task F
- 1 × `vulnerable_postgres_version` (WARN) ← Task F
