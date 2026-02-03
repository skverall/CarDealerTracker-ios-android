import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? ""
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
const webhookSecret = Deno.env.get("REVENUECAT_WEBHOOK_SECRET") ?? ""
const revenueCatApiKey = Deno.env.get("REVENUECAT_PRIVATE_API_KEY") ?? ""
const entitlementId = Deno.env.get("REVENUECAT_ENTITLEMENT_ID") ?? ""

const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false }
})

const uuidRegex =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

const isValidUuid = (value: string | null | undefined) => {
  if (!value) return false
  return uuidRegex.test(value)
}

const getSecretMatch = (req: Request) => {
  if (!webhookSecret) return false
  const authHeader = req.headers.get("authorization") ?? ""
  const headerToken = authHeader.toLowerCase().startsWith("bearer ")
    ? authHeader.slice(7)
    : authHeader
  const altSecret = req.headers.get("x-revenuecat-webhook-secret")
    ?? req.headers.get("x-webhook-secret")
  return headerToken === webhookSecret || altSecret === webhookSecret
}

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 })
  }

  if (!getSecretMatch(req)) {
    const message = webhookSecret ? "Unauthorized" : "Webhook secret not configured"
    return new Response(message, { status: 401 })
  }

  try {
    const payload = await req.json()
    const event = payload?.event ?? payload ?? {}
    const eventType = event.type ?? event.event_type ?? event.eventType ?? ""
    const periodType = event.period_type ?? event.periodType ?? ""
    const appUserId = event.app_user_id ?? event.appUserId ?? ""
    const eventId = event.id ?? event.event_id ?? event.eventId ?? null

    if (!isValidUuid(appUserId)) {
      return new Response(JSON.stringify({ ok: true, skipped: true }), {
        headers: { "content-type": "application/json" }
      })
    }

    const params = {
      p_invited_user_id: appUserId,
      p_event_id: eventId,
      p_event_type: eventType,
      p_period_type: periodType
    }

    const normalizedEventType = String(eventType).toUpperCase()
    const normalizedPeriodType = String(periodType).toUpperCase()
    const eligibleEvent =
      (normalizedEventType === "INITIAL_PURCHASE" || normalizedEventType === "NON_RENEWING_PURCHASE")
      && normalizedPeriodType !== "TRIAL"

    const { data, error } = await supabase
      .rpc("process_referral_reward", params)
    if (error) {
      return new Response(JSON.stringify({ ok: false, error: error.message }), {
        status: 500,
        headers: { "content-type": "application/json" }
      })
    }

    let promoGranted = false
    if (data === true && revenueCatApiKey && entitlementId) {
      const rewardQuery = eventId
        ? supabase
            .from("dealer_referral_rewards")
            .select("referrer_user_id")
            .eq("event_id", eventId)
            .single()
        : supabase
            .from("dealer_referral_rewards")
            .select("referrer_user_id")
            .eq("invited_user_id", appUserId)
            .order("created_at", { ascending: false })
            .limit(1)
            .single()

      const { data: rewardRow } = await rewardQuery
      const referrerUserId = rewardRow?.referrer_user_id as string | undefined

      if (referrerUserId) {
        const grantResponse = await fetch(
          `https://api.revenuecat.com/v1/subscribers/${referrerUserId}/entitlements/${entitlementId}/promotional`,
          {
            method: "POST",
            headers: {
              "Accept": "application/json",
              "Authorization": `Bearer ${revenueCatApiKey}`,
              "Content-Type": "application/json"
            },
            body: JSON.stringify({ duration: "monthly" })
          }
        )

        promoGranted = grantResponse.ok
      }
    }

    if (data !== true && eligibleEvent && eventId) {
      await supabase
        .from("dealer_referral_pending_purchases")
        .insert({
          invited_user_id: appUserId,
          event_id: eventId,
          event_type: normalizedEventType,
          period_type: normalizedPeriodType
        })
    }

    return new Response(JSON.stringify({ ok: true, rewarded: data === true, promoGranted }), {
      headers: { "content-type": "application/json" }
    })
  } catch (_error) {
    return new Response(JSON.stringify({ ok: false }), {
      status: 500,
      headers: { "content-type": "application/json" }
    })
  }
})
