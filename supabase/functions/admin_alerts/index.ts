import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import {
  alertLine,
  alertSection,
  boolLabel,
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
    if (event !== "signup_completed") {
      return jsonResponse({ error: "Unsupported alert event" }, 400)
    }

    const authorization = req.headers.get("Authorization") ?? ""
    const client = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      {
        auth: { persistSession: false },
        global: { headers: { Authorization: authorization } },
      }
    )

    const { data, error } = await client.auth.getUser()
    if (error || !data.user) {
      return jsonResponse({ error: "Unauthorized" }, 401)
    }

    const source = typeof body?.source === "string" ? body.source.trim() : "unknown"
    const referralCodePresent = body?.referral_code_present === true
    const teamInviteCodePresent = body?.team_invite_code_present === true
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

    const sent = await sendAdminAlert({
      title: "New Ezcar24Business signup",
      lines: [
        alertLine("Email", user.email),
        alertLine("User ID", user.id),
        alertLine("Account age", durationSince(user.created_at, now)),
        alertSection("Acquisition"),
        alertLine("Referral code", boolLabel(referralCodePresent)),
        alertLine("Team invite code", boolLabel(teamInviteCodePresent)),
        alertSection("Location"),
        alertLine("Network country", countryLabel(networkCountryCode)),
        alertLine("Device country", countryLabel(deviceCountryCode)),
        alertLine("Country signal", countryLabel(bestCountry)),
        alertLine("IP", maskedIp(ip)),
        alertSection("App"),
        alertLine("Source", source),
        alertLine("Platform", bodyString(body, "platform")),
        alertLine("App version", appVersion),
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
