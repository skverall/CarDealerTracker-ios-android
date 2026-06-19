import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import {
  alertLine,
  alertSection,
  compactUserId,
  countryLabel,
  durationSince,
  formatAmount,
  sendAdminAlert,
} from "../_shared/telegram_alerts.ts"

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
    const normalizedEventType = String(eventType).toUpperCase()
    const normalizedPeriodType = String(periodType).toUpperCase()

    await notifyRevenueCatEvent(event, normalizedEventType, normalizedPeriodType, appUserId)

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

async function notifyRevenueCatEvent(
  event: Record<string, unknown>,
  eventType: string,
  periodType: string,
  appUserId: string
) {
  if (!shouldAlertRevenueCatEvent(event, eventType, periodType)) return

  const price = event.price_in_purchased_currency ?? event.price
  const currency = event.currency ?? event.currency_code
  const user = await getAuthUserForAlert(appUserId)
  const riskFlags = revenueCatRiskFlags(event, eventType, periodType, appUserId)
  const risk = revenueCatRiskLabel(riskFlags)
  const title = risk === "HIGH"
    ? "Suspicious RevenueCat subscription"
    : "RevenueCat subscription event"

  await sendAdminAlert({
    title,
    lines: [
      alertLine("Risk", risk),
      alertLine("Flags", riskFlags),
      alertSection("Event"),
      alertLine("Event", eventType),
      alertLine("Period", periodType),
      alertLine("Product", event.product_id ?? event.productId),
      alertLine("Entitlements", event.entitlement_ids ?? event.entitlementIds),
      alertLine("Price", formatAmount(price, currency)),
      alertLine("Store", event.store),
      alertLine("Environment", event.environment),
      alertLine("Country", countryLabel(event.country_code ?? event.countryCode)),
      alertSection("User"),
      alertLine("Email", user?.email),
      alertLine("User ID", appUserId),
      alertLine("Short ID", compactUserId(appUserId)),
      alertLine("Account age", durationSince(user?.createdAt)),
      alertLine("Created at", user?.createdAt),
      alertSection("Trace"),
      alertLine("Event ID", event.id ?? event.event_id ?? event.eventId),
      alertLine("Reported at", new Date().toISOString()),
    ],
  })
}

type AuthAlertUser = {
  email?: string
  createdAt?: string
}

async function getAuthUserForAlert(userId: string): Promise<AuthAlertUser | null> {
  if (!isValidUuid(userId) || !serviceRoleKey) return null

  try {
    const { data, error } = await supabase.auth.admin.getUserById(userId)
    if (error || !data?.user) return null

    return {
      email: data.user.email ?? undefined,
      createdAt: data.user.created_at ?? undefined,
    }
  } catch (error) {
    console.warn("RevenueCat auth user lookup failed", error)
    return null
  }
}

function shouldAlertRevenueCatEvent(
  event: Record<string, unknown>,
  eventType: string,
  periodType: string
): boolean {
  if (isSuspiciousRevenueCatEvent(event, eventType, periodType)) return true
  return new Set([
    "INITIAL_PURCHASE",
    "NON_RENEWING_PURCHASE",
    "PRODUCT_CHANGE",
    "BILLING_ISSUE",
    "CANCELLATION",
    "UNCANCELLATION",
    "EXPIRATION",
    "TRANSFER",
    "TEMPORARY_ENTITLEMENT_GRANT",
  ]).has(eventType)
}

function isSuspiciousRevenueCatEvent(
  event: Record<string, unknown>,
  eventType: string,
  periodType: string
): boolean {
  if (periodType === "TRIAL") return false
  if (!["INITIAL_PURCHASE", "NON_RENEWING_PURCHASE", "PRODUCT_CHANGE"].includes(eventType)) {
    return false
  }

  const price = numberValue(event.price_in_purchased_currency ?? event.price)
  return price !== null && price <= 0
}

function revenueCatRiskFlags(
  event: Record<string, unknown>,
  eventType: string,
  periodType: string,
  appUserId: string
): string[] {
  const flags: string[] = []
  if (isSuspiciousRevenueCatEvent(event, eventType, periodType)) {
    flags.push("paid event with zero/non-positive price")
  }
  if (!isValidUuid(appUserId)) {
    flags.push("app user id is not a Supabase UUID")
  }
  if (eventType === "TRANSFER") {
    flags.push("subscription transferred between users")
  }
  if (eventType === "TEMPORARY_ENTITLEMENT_GRANT") {
    flags.push("temporary entitlement grant")
  }
  if (String(event.environment ?? "").toUpperCase() === "SANDBOX") {
    flags.push("sandbox event")
  }
  return flags
}

function revenueCatRiskLabel(flags: string[]): string {
  if (flags.some((flag) =>
    flag.includes("zero/non-positive")
    || flag.includes("not a Supabase UUID")
    || flag.includes("temporary entitlement")
  )) {
    return "HIGH"
  }
  if (flags.length > 0) return "WATCH"
  return "INFO"
}

function numberValue(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value
  if (typeof value === "string") {
    const parsed = Number(value)
    return Number.isFinite(parsed) ? parsed : null
  }
  return null
}
