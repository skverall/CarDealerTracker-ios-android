import { createClient } from "npm:@supabase/supabase-js@2"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
}

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? ""
const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? ""
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  try {
    const authHeader = req.headers.get("Authorization")
    if (!authHeader) {
      return jsonResponse({ error: "Unauthorized" }, 401)
    }
    if (!supabaseUrl || !anonKey || !serviceRoleKey) {
      return jsonResponse({ error: "Server configuration is incomplete" }, 500)
    }

    const userClient = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false },
      global: { headers: { Authorization: authHeader } },
    })
    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    })

    const {
      data: { user },
      error: userError,
    } = await userClient.auth.getUser()

    if (userError || !user) {
      return jsonResponse({ error: "Unauthorized" }, 401)
    }

    const userId = user.id
    const { data: ownedOrganizations, error: organizationsError } = await adminClient
      .from("organizations")
      .select("id")
      .eq("owner_id", userId)

    if (organizationsError) {
      throw organizationsError
    }

    const ownedOrganizationIds = (ownedOrganizations ?? [])
      .map((row) => row.id)
      .filter((value): value is string => typeof value === "string" && value.length > 0)

    const normalizedEmail = (user.email ?? "").trim().toLowerCase()

    if (normalizedEmail) {
      await maybeDelete(
        adminClient.from("team_invitations").delete().eq("email", normalizedEmail),
        "team_invitations_by_email"
      )
    }

    await maybeDelete(
      adminClient.from("team_invitations").delete().eq("created_by", userId),
      "team_invitations_by_creator"
    )

    await maybeDelete(
      adminClient.from("team_invite_code_attempts").delete().eq("user_id", userId),
      "team_invite_code_attempts"
    )

    await maybeDelete(
      adminClient.from("referral_bonus_access").delete().eq("user_id", userId),
      "referral_bonus_access"
    )

    await maybeDelete(
      adminClient.from("dealer_referrals").delete().or(`invited_user_id.eq.${userId},referrer_user_id.eq.${userId}`),
      "dealer_referrals"
    )

    await maybeDelete(
      adminClient.from("dealer_referral_rewards").delete().or(`invited_user_id.eq.${userId},referrer_user_id.eq.${userId}`),
      "dealer_referral_rewards"
    )

    await maybeDelete(
      adminClient.from("dealer_referral_pending_purchases").delete().eq("invited_user_id", userId),
      "dealer_referral_pending_purchases"
    )

    await maybeUpdate(
      adminClient.from("audit_logs").update({ actor_id: null }).eq("actor_id", userId),
      "audit_logs"
    )

    await maybeDelete(
      adminClient.from("dealer_team_members").delete().eq("user_id", userId),
      "dealer_team_members"
    )

    await removeBucketPrefix(adminClient, "avatars", userId.toLowerCase())

    for (const organizationId of ownedOrganizationIds) {
      const normalizedOrganizationId = organizationId.toLowerCase()
      await removeBucketPrefix(adminClient, "vehicle-images", `${normalizedOrganizationId}/vehicles`)
      await removeBucketPrefix(adminClient, "expense-receipts", `${normalizedOrganizationId}/expenses`)
      await removeBucketPrefix(adminClient, "dealer-backups", `${normalizedOrganizationId}/backups`)
    }

    if (ownedOrganizationIds.length > 0) {
      await maybeDelete(
        adminClient.from("organizations").delete().in("id", ownedOrganizationIds),
        "organizations"
      )
    }

    const { error: deleteUserError } = await adminClient.auth.admin.deleteUser(userId)
    if (deleteUserError) {
      throw deleteUserError
    }

    return jsonResponse({
      success: true,
      deletedUserId: userId,
      deletedOrganizationCount: ownedOrganizationIds.length,
    })
  } catch (error) {
    const message =
      typeof error === "object" && error && "message" in error
        ? String(error.message)
        : "Unexpected error"
    return jsonResponse({ error: message }, 400)
  }
})

function jsonResponse(payload: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  })
}

async function maybeDelete(operation: PromiseLike<{ error: { message: string } | null }>, context: string) {
  const { error } = await operation
  if (!error || isMissingRelationError(error.message)) {
    return
  }
  throw new Error(`${context}: ${error.message}`)
}

async function maybeUpdate(operation: PromiseLike<{ error: { message: string } | null }>, context: string) {
  const { error } = await operation
  if (!error || isMissingRelationError(error.message)) {
    return
  }
  throw new Error(`${context}: ${error.message}`)
}

function isMissingRelationError(message: string) {
  const normalized = message.toLowerCase()
  return normalized.includes("does not exist") ||
    normalized.includes("could not find the table") ||
    normalized.includes("not found")
}

async function removeBucketPrefix(
  adminClient: ReturnType<typeof createClient<any>>,
  bucket: string,
  prefix: string
) {
  const paths = await listBucketPaths(adminClient, bucket, prefix)
  if (paths.length === 0) {
    return
  }

  for (let index = 0; index < paths.length; index += 100) {
    const chunk = paths.slice(index, index + 100)
    const { error } = await adminClient.storage.from(bucket).remove(chunk)
    if (error && !isMissingRelationError(error.message)) {
      throw new Error(`${bucket}: ${error.message}`)
    }
  }
}

async function listBucketPaths(
  adminClient: ReturnType<typeof createClient<any>>,
  bucket: string,
  prefix: string
): Promise<string[]> {
  const queue = [prefix]
  const paths: string[] = []

  while (queue.length > 0) {
    const currentPrefix = queue.shift() ?? ""
    const { data, error } = await adminClient.storage.from(bucket).list(currentPrefix, {
      limit: 1000,
      sortBy: { column: "name", order: "asc" },
    })

    if (error) {
      if (isMissingRelationError(error.message)) {
        return []
      }
      throw new Error(`${bucket}: ${error.message}`)
    }

    for (const item of data ?? []) {
      if (!item.name) {
        continue
      }
      const fullPath = currentPrefix ? `${currentPrefix}/${item.name}` : item.name
      if (item.id) {
        paths.push(fullPath)
      } else {
        queue.push(fullPath)
      }
    }
  }

  return paths
}
