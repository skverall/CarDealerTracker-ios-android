import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // Handle CORS
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: req.headers.get('Authorization')! } } }
    )

    const { email, role, language } = await req.json()
    if (!email || typeof email !== "string") {
      throw new Error("Email is required")
    }
    if (!role || typeof role !== "string") {
      throw new Error("Role is required")
    }
    const normalizedRole = role.toLowerCase()
    const allowedRoles = new Set(["admin", "sales", "viewer"])
    if (!allowedRoles.has(normalizedRole)) {
      throw new Error("Invalid role")
    }
    
    // 1. Get User
    const { data: { user } } = await supabaseClient.auth.getUser()
    if (!user) throw new Error("Unauthorized")

    // 2. Identify Organization (Context: User is Member of Org)
    // We assume the inviter is acting on behalf of the org they are effectively "logged into".
    // For now, since 1 User = 1 Org (mostly), we fetch the org where they are an Owner/Admin.
    // In a multi-org future, 'organization_id' should be passed in the body.
    const { data: membership, error: memError } = await supabaseClient
      .from('dealer_team_members')
      .select('organization_id')
      .eq('user_id', user.id)
      .single()

    if (memError || !membership) throw new Error("Organization membership not found")

    // 3. Verify Permission (The Gatekeeper)
    let canManage = false
    for (const permKey of ["manage_team", "MANAGE_TEAM"]) {
      const { data, error } = await supabaseClient.rpc("has_permission", {
        _user_id: user.id,
        _org_id: membership.organization_id,
        _perm_key: permKey,
      })
      if (error) throw error
      if (data) {
        canManage = true
        break
      }
    }

    if (!canManage) throw new Error("Forbidden: insufficient permissions")

    // 4. Create Invitation
    const token = crypto.randomUUID()
    const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString() // 24h

    const { error: inviteError } = await supabaseClient
      .from('team_invitations')
      .insert({
        organization_id: membership.organization_id,
        email,
        role: normalizedRole,
        token,
        created_by: user.id,
        expires_at: expiresAt
      })

    if (inviteError) throw inviteError

    // 5. Audit Log
    await supabaseClient.from('audit_logs').insert({
      organization_id: membership.organization_id,
      actor_id: user.id,
      action: 'INVITE_MEMBER',
      details: { email, role: normalizedRole, token_id: token } // Log token ID not value? Value needed for link though.
    })

    const baseUrl = Deno.env.get("INVITE_BASE_URL") ?? "https://ezcar24.com/accept-invite"
    const inviteUrl = new URL(baseUrl)
    inviteUrl.searchParams.set("token", token)
    if (typeof language === "string" && language.length > 0) {
      inviteUrl.searchParams.set("lang", language)
    }

    await sendInviteEmail({
      to: email,
      role: normalizedRole,
      inviteUrl: inviteUrl.toString(),
    })

    return new Response(
      JSON.stringify({
        success: true,
        token,
        invite_url: inviteUrl.toString(),
        message: "Invitation created",
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    )
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 400,
    })
  }
})

async function sendInviteEmail(payload: { to: string; role: string; inviteUrl: string }) {
  const apiKey = Deno.env.get("RESEND_API_KEY")
  if (!apiKey) {
    throw new Error("Email is not configured: RESEND_API_KEY is missing")
  }

  const from = Deno.env.get("RESEND_FROM_EMAIL") ?? "Ezcar24 <no-reply@ezcar24.com>"
  const subject = "You have been invited to Ezcar24 Business"
  const safeRole = payload.role.toUpperCase()

  const text = [
    "You have been invited to join a team in Ezcar24 Business.",
    `Role: ${safeRole}`,
    `Accept invite: ${payload.inviteUrl}`,
    "",
    "If you did not expect this invitation, you can ignore this email.",
  ].join("\n")

  const html = `
    <div style="font-family: Arial, sans-serif; color: #111827; line-height: 1.5;">
      <h2 style="margin: 0 0 12px;">You have been invited</h2>
      <p style="margin: 0 0 8px;">You were invited to join a team in Ezcar24 Business.</p>
      <p style="margin: 0 0 12px;"><strong>Role:</strong> ${safeRole}</p>
      <p style="margin: 0 0 16px;">
        <a href="${payload.inviteUrl}" style="display: inline-block; padding: 10px 16px; background: #16a34a; color: #ffffff; text-decoration: none; border-radius: 6px;">
          Accept Invite
        </a>
      </p>
      <p style="margin: 0; color: #6b7280; font-size: 13px;">
        If you did not expect this invitation, you can ignore this email.
      </p>
    </div>
  `

  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from,
      to: [payload.to],
      subject,
      html,
      text,
    }),
  })

  if (!response.ok) {
    const details = await response.text()
    throw new Error(`Resend error: ${details}`)
  }
}
