import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2"

type AnySupabaseClient = SupabaseClient<any, any, any>

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
}

type InviteRow = {
  id: string
  token: string
  organization_id: string
  role: string | null
  status?: string | null
  permissions: Record<string, unknown> | null
  email: string | null
}

type InviteCodeRow = {
  id: string
  invitation_token: string
  invite_code: string
  invited_email: string | null
  max_uses: number
  used_count: number
  expires_at: string
  revoked_at: string | null
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  try {
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    )

    const authHeader = req.headers.get("Authorization")
    let currentUser = null
    if (authHeader) {
      const supabaseUser = createClient(
        Deno.env.get("SUPABASE_URL") ?? "",
        Deno.env.get("SUPABASE_ANON_KEY") ?? "",
        { global: { headers: { Authorization: authHeader } } }
      )
      const { data: { user } } = await supabaseUser.auth.getUser()
      currentUser = user
    }

    if (!currentUser) {
      throw new Error("Please sign in or sign up to accept the invitation")
    }

    const body = await req.json()
    const token = typeof body?.token === "string" ? body.token.trim() : ""
    const inviteCode = normalizeInviteCode(typeof body?.invite_code === "string" ? body.invite_code : "")

    if (!token && !inviteCode) {
      throw new Error("Invite token or code is required")
    }

    const strictEmailMatch = (Deno.env.get("INVITE_STRICT_EMAIL_MATCH") ?? "true") === "true"

    let invite: InviteRow | null = null
    let codeRow: InviteCodeRow | null = null

    if (inviteCode) {
      const limited = await isInviteCodeRateLimited(supabaseAdmin, currentUser.id, inviteCode)
      if (limited) {
        await logInviteCodeAttempt(supabaseAdmin, currentUser.id, inviteCode, false, "rate_limited")
        throw new Error("Too many failed attempts. Please wait 10 minutes and try again.")
      }

      const resolved = await resolveInviteByCode(supabaseAdmin, inviteCode)
      invite = resolved.invite
      codeRow = resolved.codeRow
    } else {
      invite = await resolveInviteByToken(supabaseAdmin, token)
    }

    if (!invite) {
      throw new Error("Invalid or expired invitation")
    }

    const invitedEmail = (codeRow?.invited_email ?? invite.email ?? "").toLowerCase()
    if (
      strictEmailMatch &&
      invitedEmail &&
      currentUser.email &&
      invitedEmail !== currentUser.email.toLowerCase()
    ) {
      if (inviteCode) {
        await logInviteCodeAttempt(supabaseAdmin, currentUser.id, inviteCode, false, "email_mismatch")
      }
      throw new Error("Email mismatch. Please sign in with the invited address.")
    }

    const { error: memberError } = await supabaseAdmin
      .from("dealer_team_members")
      .insert({
        organization_id: invite.organization_id,
        user_id: currentUser.id,
        role: invite.role ?? "viewer",
        status: "active",
        permissions: invite.permissions ?? {},
      })

    if (memberError) {
      if (getErrorCode(memberError) === "23505") {
        if (inviteCode) {
          await logInviteCodeAttempt(supabaseAdmin, currentUser.id, inviteCode, true, "already_member")
        }
        throw new Error("You are already a member of this team")
      }
      if (inviteCode) {
        await logInviteCodeAttempt(supabaseAdmin, currentUser.id, inviteCode, false, "member_insert_failed")
      }
      throw memberError
    }

    if (codeRow) {
      const nowIso = new Date().toISOString()
      const nextUsedCount = Number(codeRow.used_count) + 1
      const shouldRevoke = nextUsedCount >= Number(codeRow.max_uses)
      const { error: updateCodeError } = await supabaseAdmin
        .from("team_invite_codes")
        .update({
          used_count: nextUsedCount,
          last_used_at: nowIso,
          updated_at: nowIso,
          revoked_at: shouldRevoke ? nowIso : null,
        })
        .eq("id", codeRow.id)

      if (updateCodeError) throw updateCodeError
      if (shouldRevoke) {
        await supabaseAdmin.from("team_invitations").delete().eq("id", invite.id)
      }
      await logInviteCodeAttempt(supabaseAdmin, currentUser.id, codeRow.invite_code, true, null)
    } else {
      await supabaseAdmin.from("team_invitations").delete().eq("id", invite.id)
    }

    await supabaseAdmin.from("audit_logs").insert({
      organization_id: invite.organization_id,
      actor_id: currentUser.id,
      action: "JOIN_TEAM",
      details: {
        invite_id: invite.id,
        role: invite.role,
        method: codeRow ? "invite_code" : "token",
      },
    })

    return new Response(
      JSON.stringify({
        success: true,
        organization_id: invite.organization_id,
        role: invite.role,
        message: "Welcome to the team!",
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    )
  } catch (error) {
    const message =
      typeof error === "object" && error && "message" in error
        ? String(error.message)
        : "Unexpected error"
    return new Response(JSON.stringify({ error: message }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 400,
    })
  }
})

function normalizeInviteCode(raw: string) {
  return raw.trim().toUpperCase().replace(/[^A-Z0-9]/g, "")
}

function getErrorCode(error: unknown) {
  if (typeof error !== "object" || !error || !("code" in error)) return ""
  return String((error as { code?: unknown }).code ?? "")
}

async function resolveInviteByToken(
  supabaseAdmin: AnySupabaseClient,
  token: string
): Promise<InviteRow> {
  const { data, error } = await supabaseAdmin
    .from("team_invitations")
    .select("*")
    .eq("token", token)
    .gt("expires_at", new Date().toISOString())
    .single()

  if (error || !data) throw new Error("Invalid or expired invitation")
  return data as InviteRow
}

async function resolveInviteByCode(
  supabaseAdmin: AnySupabaseClient,
  inviteCode: string
): Promise<{ invite: InviteRow; codeRow: InviteCodeRow }> {
  const nowIso = new Date().toISOString()
  const { data: codeData, error: codeError } = await supabaseAdmin
    .from("team_invite_codes")
    .select("*")
    .eq("invite_code", inviteCode)
    .maybeSingle()

  if (codeError || !codeData) throw new Error("Invalid invite code")
  const codeRow = codeData as InviteCodeRow

  if (codeRow.revoked_at) throw new Error("Invite code has been revoked")
  if (new Date(codeRow.expires_at).toISOString() <= nowIso) throw new Error("Invite code has expired")
  if (Number(codeRow.used_count) >= Number(codeRow.max_uses)) throw new Error("Invite code has already been used")

  const { data: inviteData, error: inviteError } = await supabaseAdmin
    .from("team_invitations")
    .select("*")
    .eq("token", codeRow.invitation_token)
    .gt("expires_at", nowIso)
    .maybeSingle()

  if (inviteError || !inviteData) throw new Error("Invalid or expired invitation")

  return {
    invite: inviteData as InviteRow,
    codeRow,
  }
}

async function isInviteCodeRateLimited(
  supabaseAdmin: AnySupabaseClient,
  userId: string,
  inviteCode: string
) {
  const windowStart = new Date(Date.now() - 10 * 60 * 1000).toISOString()
  const { data: userData, error: userError } = await supabaseAdmin
    .from("team_invite_code_attempts")
    .select("id")
    .eq("user_id", userId)
    .eq("success", false)
    .gte("created_at", windowStart)
    .limit(7)
  if (userError) return false
  if (Array.isArray(userData) && userData.length >= 7) return true

  const { data: codeData, error: codeError } = await supabaseAdmin
    .from("team_invite_code_attempts")
    .select("id")
    .eq("invite_code", inviteCode)
    .eq("success", false)
    .gte("created_at", windowStart)
    .limit(20)

  if (codeError) return false
  return Array.isArray(codeData) && codeData.length >= 20
}

async function logInviteCodeAttempt(
  supabaseAdmin: AnySupabaseClient,
  userId: string,
  inviteCode: string,
  success: boolean,
  failureReason: string | null
) {
  await supabaseAdmin.from("team_invite_code_attempts").insert({
    user_id: userId,
    invite_code: inviteCode,
    success,
    failure_reason: failureReason,
  })
}
