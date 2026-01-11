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
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    const body = await req.json()
    const { email, role, language, permissions, create_account, organization_id } = body ?? {}
    if (!email || typeof email !== "string") {
      throw new Error("Email is required")
    }
    if (!role || typeof role !== "string") {
      throw new Error("Role is required")
    }
    const normalizedEmail = email.trim().toLowerCase()
    const normalizedRole = role.toLowerCase()
    const allowedRoles = new Set(["admin", "sales", "viewer"])
    if (!allowedRoles.has(normalizedRole)) {
      throw new Error("Invalid role")
    }

    const allowedPermissions = new Set([
      "view_expenses",
      "view_inventory",
      "create_sale",
      "manage_team",
      "view_leads",
      "delete_records",
      "view_vehicle_cost",
      "view_vehicle_profit",
    ])
    const normalizedPermissions: Record<string, boolean> = {}
    if (permissions && typeof permissions === "object" && !Array.isArray(permissions)) {
      for (const key of allowedPermissions) {
        const value = (permissions as Record<string, unknown>)[key]
        if (typeof value === "boolean") {
          normalizedPermissions[key] = value
        }
      }
    }

    // 1. Get User
    const { data: { user } } = await supabaseClient.auth.getUser()
    if (!user) throw new Error("Unauthorized")

    // 2. Identify Organization (Context: User is Member of Org)
    const orgIdOverride = typeof organization_id === "string" ? organization_id : null
    let targetOrgId: string | null = null
    if (orgIdOverride) {
      const { data: membership, error: memError } = await supabaseClient
        .from('dealer_team_members')
        .select('organization_id')
        .eq('user_id', user.id)
        .eq('organization_id', orgIdOverride)
        .single()
      if (memError || !membership) throw new Error("Organization membership not found")
      targetOrgId = membership.organization_id
    } else {
      const { data: memberships, error: memError } = await supabaseClient
        .from('dealer_team_members')
        .select('organization_id')
        .eq('user_id', user.id)
      if (memError || !memberships || memberships.length == 0) {
        throw new Error("Organization membership not found")
      }
      targetOrgId = memberships[0].organization_id
    }

    // 3. Verify Permission (The Gatekeeper)
    let canManage = false
    for (const permKey of ["manage_team", "MANAGE_TEAM"]) {
      const { data, error } = await supabaseClient.rpc("has_permission", {
        _user_id: user.id,
        _org_id: targetOrgId,
        _perm_key: permKey,
      })
      if (error) throw error
      if (data) {
        canManage = true
        break
      }
    }

    if (!canManage) throw new Error("Forbidden: insufficient permissions")

    const shouldCreateAccount = create_account === true
    if (shouldCreateAccount) {
      if (!Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')) {
        throw new Error("Missing SUPABASE_SERVICE_ROLE_KEY")
      }

      let generatedPassword: string | null = null
      let targetUserId: string | null = null
      let existingUser = false

      const password = generatePassword(12)
      const { data: createdUser, error: createError } = await supabaseAdmin.auth.admin.createUser({
        email: normalizedEmail,
        password,
        email_confirm: true,
      })

      if (createError) {
        if (isUserExistsError(createError)) {
          existingUser = true
          targetUserId = await findUserIdByEmail(supabaseAdmin, normalizedEmail)
          if (!targetUserId) {
            throw new Error("User already exists but could not be loaded")
          }
        } else {
          throw createError
        }
      } else {
        targetUserId = createdUser?.user?.id ?? null
        if (!targetUserId) {
          throw new Error("Failed to create user")
        }
        generatedPassword = password
      }

      const { data: existingMember, error: memberCheckError } = await supabaseAdmin
        .from('dealer_team_members')
        .select('id')
        .eq('organization_id', targetOrgId)
        .eq('user_id', targetUserId)
        .maybeSingle()

      if (memberCheckError) throw memberCheckError
      if (existingMember) throw new Error("User is already a member of this team")

      const { error: memberInsertError } = await supabaseAdmin
        .from('dealer_team_members')
        .insert({
          organization_id: targetOrgId,
          user_id: targetUserId,
          role: normalizedRole,
          status: 'active',
          permissions: normalizedPermissions,
        })

      if (memberInsertError) throw memberInsertError

      await supabaseAdmin.from('team_invitations')
        .delete()
        .eq('organization_id', targetOrgId)
        .eq('email', normalizedEmail)

      await supabaseAdmin.from('audit_logs').insert({
        organization_id: targetOrgId,
        actor_id: user.id,
        action: 'ADD_TEAM_MEMBER',
        details: { email: normalizedEmail, role: normalizedRole, permissions: normalizedPermissions, existing_user: existingUser }
      })

      const message = existingUser
        ? "Member linked to existing account"
        : "Member created with generated password"

      return new Response(
        JSON.stringify({
          success: true,
          email: normalizedEmail,
          user_id: targetUserId,
          role: normalizedRole,
          existing_user: existingUser,
          generated_password: generatedPassword,
          message,
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    // 4. Create Invitation
    const token = crypto.randomUUID()
    const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString() // 24h

    const { error: inviteError } = await supabaseClient
      .from('team_invitations')
      .insert({
        organization_id: targetOrgId,
        email: normalizedEmail,
        role: normalizedRole,
        token,
        created_by: user.id,
        expires_at: expiresAt,
        permissions: normalizedPermissions
      })

    if (inviteError) throw inviteError

    // 5. Audit Log
    await supabaseClient.from('audit_logs').insert({
      organization_id: targetOrgId,
      actor_id: user.id,
      action: 'INVITE_MEMBER',
      details: { email: normalizedEmail, role: normalizedRole, token_id: token, permissions: normalizedPermissions }
    })

    const baseUrl = Deno.env.get("INVITE_BASE_URL") ?? "https://ezcar24.com/accept-invite"
    const inviteUrl = new URL(baseUrl)
    inviteUrl.searchParams.set("token", token)
    if (typeof language === "string" && language.length > 0) {
      inviteUrl.searchParams.set("lang", language)
    }

    await sendInviteEmail({
      to: normalizedEmail,
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

function generatePassword(length = 12): string {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@$%&*?"
  const bytes = new Uint8Array(length)
  crypto.getRandomValues(bytes)
  let result = ""
  for (const byte of bytes) {
    result += chars[byte % chars.length]
  }
  return result
}

function isUserExistsError(error: { message?: string }) {
  const message = (error?.message ?? "").toLowerCase()
  return message.includes("already") && (message.includes("registered") || message.includes("exists"))
}

async function findUserIdByEmail(supabaseAdmin: ReturnType<typeof createClient>, email: string) {
  const { data: profile, error: profileError } = await supabaseAdmin
    .from("profiles")
    .select("user_id")
    .eq("email", email)
    .maybeSingle()

  if (!profileError && profile?.user_id) {
    return profile.user_id as string
  }

  let page = 1
  const perPage = 200
  while (page <= 25) {
    const { data, error } = await supabaseAdmin.auth.admin.listUsers({ page, perPage })
    if (error) break
    const users = data?.users ?? []
    const match = users.find((u) => (u.email ?? "").toLowerCase() === email.toLowerCase())
    if (match) return match.id
    if (users.length < perPage) break
    page += 1
  }
  return null
}

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
