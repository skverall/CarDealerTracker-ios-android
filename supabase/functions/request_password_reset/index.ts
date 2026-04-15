import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

type InviteRow = {
  id: string
  token: string
  organization_id: string
  role: string | null
  permissions: Record<string, unknown> | null
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  try {
    const body = await req.json()
    const email = typeof body?.email === "string" ? body.email.trim().toLowerCase() : ""
    if (!email) throw new Error("Email is required")

    const redirectTo =
      typeof body?.redirect_to === "string" && body.redirect_to.length > 0
        ? body.redirect_to
        : Deno.env.get("PASSWORD_RESET_REDIRECT") ?? "com.ezcar24.business://login-callback"

    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    )

    let userId = await findUserIdByEmail(supabaseAdmin, email)

    let invite: InviteRow | null = null
    if (!userId) {
      const { data, error } = await supabaseAdmin
        .from("team_invitations")
        .select("id, token, organization_id, role, permissions")
        .eq("email", email)
        .gt("expires_at", new Date().toISOString())
        .limit(1)
        .maybeSingle()
      if (error) throw error
      invite = data as InviteRow | null
    }

    if (!userId && invite) {
      const password = generatePassword(14)
      const { data: createdUser, error: createError } = await supabaseAdmin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
      })

      if (createError) {
        if (!isUserExistsError(createError)) {
          throw createError
        }
        userId = await findUserIdByEmail(supabaseAdmin, email)
      } else {
        userId = createdUser?.user?.id ?? null
      }
    }

    if (userId && invite) {
      const { data: existingMember, error: memberCheckError } = await supabaseAdmin
        .from("dealer_team_members")
        .select("id")
        .eq("organization_id", invite.organization_id)
        .eq("user_id", userId)
        .maybeSingle()

      if (memberCheckError) throw memberCheckError

      if (!existingMember) {
        const permissions =
          invite.permissions && typeof invite.permissions === "object" ? invite.permissions : {}
        const role = invite.role ?? "viewer"
        const { error: memberInsertError } = await supabaseAdmin
          .from("dealer_team_members")
          .insert({
            organization_id: invite.organization_id,
            user_id: userId,
            role,
            status: "active",
            permissions,
          })

        if (memberInsertError) throw memberInsertError
      }

      await supabaseAdmin.from("team_invitations").delete().eq("id", invite.id)

      await supabaseAdmin.from("audit_logs").insert({
        organization_id: invite.organization_id,
        actor_id: userId,
        action: "AUTO_ACCEPT_INVITE",
        details: { invite_id: invite.id, email },
      })
    }

    if (userId) {
      await repairUserEmailState(supabaseAdmin, userId, email)

      let { data: linkData, error: linkError } = await supabaseAdmin.auth.admin.generateLink({
        type: "recovery",
        email,
        options: { redirectTo },
      })

      if (linkError) {
        await repairUserEmailState(supabaseAdmin, userId, email)
        const retry = await supabaseAdmin.auth.admin.generateLink({
          type: "recovery",
          email,
          options: { redirectTo },
        })
        linkData = retry.data
        linkError = retry.error
      }

      if (linkError) throw linkError

      const actionLink = extractActionLink(linkData)
      if (!actionLink) throw new Error("Failed to generate recovery link")

      await sendRecoveryEmail({ to: email, resetUrl: actionLink })
    }

    return new Response(JSON.stringify({ success: true }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    })
  } catch (error) {
    return new Response(JSON.stringify({ error: errorMessage(error) }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 400,
    })
  }
})

function errorMessage(error: unknown) {
  if (typeof error === "object" && error && "message" in error) {
    return String((error as { message?: unknown }).message ?? "Unexpected error")
  }
  return "Unexpected error"
}

function extractActionLink(data: unknown): string | null {
  if (!data || typeof data !== "object") return null
  const typed = data as Record<string, unknown>
  const direct = typed.action_link
  if (typeof direct === "string") return direct
  const properties = typed.properties
  if (properties && typeof properties === "object") {
    const actionLink = (properties as Record<string, unknown>).action_link
    if (typeof actionLink === "string") return actionLink
  }
  return null
}

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

async function findUserIdByEmail(
  supabaseAdmin: any,
  email: string
): Promise<string | null> {
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
    const match = users.find((u: any) => (u.email ?? "").toLowerCase() === email.toLowerCase())
    if (match) return match.id
    if (users.length < perPage) break
    page += 1
  }
  return null
}

async function repairUserEmailState(
  supabaseAdmin: any,
  userId: string,
  email: string
) {
  const { data: userData, error: userError } = await supabaseAdmin.auth.admin.getUserById(userId)
  if (userError) throw userError

  const currentMetadata =
    userData?.user?.user_metadata && typeof userData.user.user_metadata === "object"
      ? (userData.user.user_metadata as Record<string, unknown>)
      : {}

  const { error: updateError } = await supabaseAdmin.auth.admin.updateUserById(userId, {
    email,
    email_confirm: true,
    user_metadata: {
      ...currentMetadata,
      email,
      email_verified: true,
    },
  })

  if (updateError) throw updateError
}

async function sendRecoveryEmail(payload: { to: string; resetUrl: string }) {
  const apiKey = Deno.env.get("RESEND_API_KEY")
  if (!apiKey) {
    throw new Error("Email is not configured: RESEND_API_KEY is missing")
  }

  const from = Deno.env.get("RESEND_FROM_EMAIL") ?? "Ezcar24 <no-reply@ezcar24.com>"
  const subject = "Reset your Ezcar24 Business password"

  const text = [
    "We received a request to reset your Ezcar24 Business password.",
    `Reset password: ${payload.resetUrl}`,
    "If you did not request this, you can ignore this email.",
  ].join("\n")

  const html = `
    <div style="font-family: Arial, sans-serif; color: #111827; line-height: 1.5;">
      <h2 style="margin: 0 0 12px;">Reset your password</h2>
      <p style="margin: 0 0 8px;">We received a request to reset your Ezcar24 Business password.</p>
      <p style="margin: 0 0 16px;">
        <a href="${payload.resetUrl}" style="display: inline-block; padding: 10px 16px; background: #2563eb; color: #ffffff; text-decoration: none; border-radius: 6px;">
          Reset Password
        </a>
      </p>
      <p style="margin: 0; color: #6b7280; font-size: 13px;">
        If you did not request this, you can ignore this email.
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
