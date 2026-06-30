import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import {
  alertLine,
  alertSection,
  boolLabel,
  compactUserId,
  countryCodeValue,
  countryLabel,
  durationSince,
  maskedIp,
  sendAdminAlert,
} from "../_shared/telegram_alerts.ts"

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

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405)
  }

  try {
    const body = await readJson(req)
    const event = typeof body?.event === "string" ? body.event : ""
    if (!["signup_completed", "auth_completed"].includes(event)) {
      return jsonResponse({ error: "Unsupported alert event" }, 400)
    }

    const authorization = req.headers.get("Authorization") ?? ""
    const client = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false },
      global: { headers: { Authorization: authorization } },
    })

    const { data, error } = await client.auth.getUser()
    if (error || !data.user) {
      return jsonResponse({ error: "Unauthorized" }, 401)
    }

    const source = bodyString(body, "source") ?? "unknown"
    const referralCodePresent = body?.referral_code_present === true
    const teamInviteCodePresent = body?.team_invite_code_present === true
    const authMode = bodyString(body, "auth_mode") ?? (event === "signup_completed" ? "sign_up" : null)
    const authMethod = bodyString(body, "auth_method") ?? (event === "signup_completed" ? "email" : null)
    const user = data.user
    const now = new Date()
    const networkCountryCode = countryCodeFromHeaders(req.headers)
    const deviceCountryCode = bodyString(body, "device_country_code")
    const bestCountry = networkCountryCode ?? countryCodeValue(deviceCountryCode)
    const appVersion = versionLabel(bodyString(body, "app_version"), bodyString(body, "app_build"))
    const device = deviceLabel(
      bodyString(body, "device_model"),
      bodyString(body, "os_version")
    )
    const ip = firstHeaderValue(req.headers, [
      "cf-connecting-ip",
      "x-real-ip",
      "x-forwarded-for",
    ])
    const provider = authProviderLabel(user.app_metadata, authMethod)
    const metadata = {
      event,
      accountCreatedAt: user.created_at,
      networkCountryCode,
      maskedIp: maskedIp(ip),
    }

    await recordAdminBotEvent({
      eventType: "auth_completed",
      userId: user.id,
      authMode,
      authMethod,
      provider,
      source,
      platform: bodyString(body, "platform"),
      appVersion: bodyString(body, "app_version"),
      appBuild: bodyString(body, "app_build"),
      appRegion: bodyString(body, "app_region"),
      appLanguage: bodyString(body, "app_language"),
      currencyCode: bodyString(body, "currency_code"),
      deviceLocale: bodyString(body, "device_locale"),
      deviceCountryCode: deviceCountryCode ?? bestCountry,
      timezone: bodyString(body, "timezone"),
      metadata,
    })

    const shouldSendSignupAlert =
      isFreshAccount(user.created_at, now)
      && await claimAdminAlertDelivery(`signup:${user.id}`, "signup", user.id, metadata)

    if (!shouldSendSignupAlert) {
      return jsonResponse({ ok: true, sent: false })
    }

    const sent = await sendAdminAlert({
      title: "New Ezcar24Business signup",
      lines: [
        alertLine("Email", user.email),
        alertLine("Provider", provider),
        alertLine("Account age", durationSince(user.created_at, now)),
        alertLine("Country signal", countryLabel(bestCountry)),
        alertLine("Platform", bodyString(body, "platform")),
        alertLine("App version", appVersion),
        alertLine("Local time", formatInTimezone(now, ownerTimezone())),
      ],
      details: [
        alertLine("User ID", user.id),
        alertLine("Short ID", compactUserId(user.id)),
        alertLine("Auth mode", authMode),
        alertLine("Auth method", authMethod),
        alertSection("Acquisition"),
        alertLine("Referral code", boolLabel(referralCodePresent)),
        alertLine("Team invite code", boolLabel(teamInviteCodePresent)),
        alertSection("Location"),
        alertLine("Network country", countryLabel(networkCountryCode)),
        alertLine("Device country", countryLabel(deviceCountryCode)),
        alertLine("IP", maskedIp(ip)),
        alertSection("App"),
        alertLine("Source", source),
        alertLine("App region", bodyString(body, "app_region")),
        alertLine("Currency", bodyString(body, "currency_code")),
        alertLine("Language", bodyString(body, "app_language")),
        alertLine("Device locale", bodyString(body, "device_locale")),
        alertLine("Timezone", bodyString(body, "timezone")),
        alertLine("Device", device),
        alertSection("Timing"),
        alertLine("Created at", user.created_at),
        alertLine("Reported at", now.toISOString()),
      ],
    })

    return jsonResponse({ ok: true, sent })
  } catch (error) {
    console.error("admin_alerts failed", error)
    return jsonResponse({ error: "Unexpected error" }, 500)
  }
})

type AdminBotEventPayload = {
  eventType: string
  userId: string
  authMode: string | null
  authMethod: string | null
  provider: string | null
  source: string | null
  platform: string | null
  appVersion: string | null
  appBuild: string | null
  appRegion: string | null
  appLanguage: string | null
  currencyCode: string | null
  deviceLocale: string | null
  deviceCountryCode: string | null
  timezone: string | null
  metadata: Record<string, unknown>
}

async function recordAdminBotEvent(payload: AdminBotEventPayload) {
  const adminClient = serviceClient()
  if (!adminClient) return

  const { error } = await adminClient.rpc("record_admin_bot_event", {
    p_event_type: payload.eventType,
    p_user_id: payload.userId,
    p_auth_mode: payload.authMode,
    p_auth_method: payload.authMethod,
    p_provider: payload.provider,
    p_source: payload.source,
    p_platform: payload.platform,
    p_app_version: payload.appVersion,
    p_app_build: payload.appBuild,
    p_app_region: payload.appRegion,
    p_app_language: payload.appLanguage,
    p_currency_code: payload.currencyCode,
    p_device_locale: payload.deviceLocale,
    p_device_country_code: payload.deviceCountryCode,
    p_timezone: payload.timezone,
    p_metadata: payload.metadata,
  })

  if (error) {
    console.warn("admin_bot event record failed", error.message)
  }
}

async function claimAdminAlertDelivery(
  alertKey: string,
  alertType: string,
  userId: string,
  metadata: Record<string, unknown>
): Promise<boolean> {
  const adminClient = serviceClient()
  if (!adminClient) return true

  const { data, error } = await adminClient.rpc("claim_admin_bot_alert_delivery", {
    p_alert_key: alertKey,
    p_alert_type: alertType,
    p_user_id: userId,
    p_metadata: metadata,
  })

  if (error) {
    console.warn("admin_bot alert delivery claim failed", error.message)
    return true
  }

  return data === true
}

function serviceClient() {
  if (!supabaseUrl || !serviceRoleKey) return null
  return createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  })
}

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  })
}

function bodyString(body: Record<string, unknown>, key: string): string | null {
  const value = body[key]
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : null
}

function versionLabel(version: string | null, build: string | null): string | null {
  if (version && build) return `${version} (${build})`
  return version ?? build
}

function deviceLabel(model: string | null, osVersion: string | null): string | null {
  if (model && osVersion) return `${model} / ${osVersion}`
  return model ?? osVersion
}

function countryCodeFromHeaders(headers: Headers): string | null {
  return countryCodeValue(firstHeaderValue(headers, ["cf-ipcountry", "x-vercel-ip-country"]))
}

function firstHeaderValue(headers: Headers, names: string[]): string | null {
  for (const name of names) {
    const value = headers.get(name)
    if (value?.trim()) return value.trim()
  }
  return null
}

function isFreshAccount(createdAt: unknown, now: Date): boolean {
  const created = typeof createdAt === "string" ? new Date(createdAt) : null
  const timestamp = created?.getTime()
  if (!timestamp || !Number.isFinite(timestamp)) return false

  const maxAgeMinutes = envNumber("SIGNUP_ALERT_MAX_ACCOUNT_AGE_MINUTES", 1440)
  return now.getTime() - timestamp <= maxAgeMinutes * 60_000
}

function authProviderLabel(appMetadata: unknown, authMethod: string | null): string | null {
  if (appMetadata && typeof appMetadata === "object" && !Array.isArray(appMetadata)) {
    const metadata = appMetadata as Record<string, unknown>
    const provider = typeof metadata.provider === "string" ? metadata.provider : null
    if (provider?.trim()) return provider.trim()
    const providers = Array.isArray(metadata.providers)
      ? metadata.providers.filter((value) => typeof value === "string")
      : []
    if (providers.length > 0) return providers.join(", ")
  }
  return authMethod
}

function ownerTimezone(): string {
  return Deno.env.get("ADMIN_ALERT_TIMEZONE")?.trim() || "Asia/Tashkent"
}

function formatInTimezone(date: Date, timezone: string): string {
  try {
    return new Intl.DateTimeFormat("en-GB", {
      timeZone: timezone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      hour12: false,
    }).format(date)
  } catch {
    return date.toISOString()
  }
}

function envNumber(name: string, fallback: number): number {
  const value = Number(Deno.env.get(name))
  return Number.isFinite(value) && value > 0 ? value : fallback
}

async function readJson(req: Request): Promise<Record<string, unknown>> {
  try {
    const body = await req.json()
    return body && typeof body === "object" && !Array.isArray(body)
      ? body as Record<string, unknown>
      : {}
  } catch {
    return {}
  }
}
