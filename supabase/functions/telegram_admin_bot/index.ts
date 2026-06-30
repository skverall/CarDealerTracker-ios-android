import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? ""
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
const botToken = Deno.env.get("TELEGRAM_BOT_TOKEN")?.trim() ?? ""
const ownerChatId = Deno.env.get("TELEGRAM_CHAT_ID")?.trim() ?? ""
const webhookSecret = Deno.env.get("TELEGRAM_WEBHOOK_SECRET")?.trim() ?? ""
const webhookSetupSecret = Deno.env.get("TELEGRAM_WEBHOOK_SETUP_SECRET")?.trim() ?? ""
const adminTimezone = Deno.env.get("ADMIN_ALERT_TIMEZONE")?.trim() || "Asia/Tashkent"

const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false },
})

Deno.serve(async (req) => {
  const url = new URL(req.url)

  if (req.method === "GET" && url.pathname.endsWith("/setup")) {
    return setupTelegramWebhook(url)
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405)
  }

  if (webhookSecret && req.headers.get("x-telegram-bot-api-secret-token") !== webhookSecret) {
    return jsonResponse({ error: "Unauthorized" }, 401)
  }

  const update = await readJson(req)
  const callback = update.callback_query as Record<string, unknown> | undefined
  const message = update.message as Record<string, unknown> | undefined

  if (callback) {
    await handleCallback(callback)
  } else if (message) {
    await handleMessage(message)
  }

  return jsonResponse({ ok: true })
})

async function setupTelegramWebhook(url: URL) {
  if (!webhookSetupSecret || !setupSecretMatches(url)) {
    return jsonResponse({ error: "Not found" }, 404)
  }

  if (!botToken) {
    return jsonResponse({ ok: false, error: "TELEGRAM_BOT_TOKEN is not configured" }, 500)
  }

  const webhookUrl = `https://${url.host}${url.pathname.replace(/\/setup\/?$/, "")}`
  const response = await telegram("setWebhook", {
    url: webhookUrl,
    allowed_updates: ["message", "callback_query"],
    drop_pending_updates: false,
    ...(webhookSecret ? { secret_token: webhookSecret } : {}),
  })

  return jsonResponse(response, response.ok ? 200 : 500)
}

function setupSecretMatches(url: URL): boolean {
  const bearer = url.searchParams.get("token") ?? ""
  return bearer === webhookSetupSecret
}

async function handleMessage(message: Record<string, unknown>) {
  const chatId = chatIdFromMessage(message)
  if (!isOwnerChat(chatId)) return

  const text = typeof message.text === "string" ? message.text.trim() : ""
  const [command, arg] = text.split(/\s+/, 2)

  if (command.startsWith("/stats")) {
    await sendMessage(chatId, await statsText(), menuMarkup())
  } else if (command.startsWith("/users")) {
    await sendMessage(chatId, await usersText(arg), menuMarkup())
  } else if (command.startsWith("/peak")) {
    await sendMessage(chatId, await peakText(arg), menuMarkup())
  } else {
    await sendMessage(chatId, helpText(), menuMarkup())
  }
}

async function handleCallback(callback: Record<string, unknown>) {
  const data = typeof callback.data === "string" ? callback.data : ""
  const callbackId = typeof callback.id === "string" ? callback.id : null
  const message = callback.message as Record<string, unknown> | undefined
  const chatId = message ? chatIdFromMessage(message) : null
  if (!isOwnerChat(chatId)) {
    if (callbackId) await answerCallback(callbackId, "Not allowed")
    return
  }

  if (callbackId) await answerCallback(callbackId)

  if (data === "stats") {
    await sendMessage(chatId, await statsText(), menuMarkup())
  } else if (data === "users") {
    await sendMessage(chatId, await usersText(), menuMarkup())
  } else if (data === "peak") {
    await sendMessage(chatId, await peakText(), menuMarkup())
  } else {
    await sendMessage(chatId, helpText(), menuMarkup())
  }
}

async function statsText(): Promise<string> {
  const { data, error } = await supabase.rpc("get_admin_bot_stats", {
    p_timezone: adminTimezone,
  })

  if (error) return errorText("Stats unavailable", error.message)

  const stats = data as Record<string, unknown>
  const users = objectValue(stats.users)
  const sessions = objectValue(stats.sessions)
  const events = objectValue(stats.events)
  const providers = arrayValue(stats.providers)

  return [
    "<b>Ezcar24 admin stats</b>",
    `Timezone: ${escapeHtml(String(stats.timezone ?? adminTimezone))}`,
    "",
    `<b>Users</b>: ${intValue(users.total)} total | +${intValue(users.last_24h)} 24h | +${intValue(users.last_7d)} 7d | +${intValue(users.last_30d)} 30d`,
    `<b>Sessions</b>: +${intValue(sessions.created_7d)} 7d | +${intValue(sessions.created_30d)} 30d | ${intValue(sessions.refreshed_7d)} refreshed 7d`,
    `<b>Captured auth events</b>: ${intValue(events.auth_7d)} 7d | ${intValue(events.captured_timezones_30d)} user timezones 30d`,
    "",
    "<b>Providers</b>",
    ...providers.map((provider) => {
      const item = objectValue(provider)
      return `${escapeHtml(String(item.provider ?? "unknown"))}: ${intValue(item.total)} total | +${intValue(item.last_7d)} 7d | +${intValue(item.last_30d)} 30d`
    }),
  ].join("\n")
}

async function usersText(rawLimit?: string): Promise<string> {
  const limit = boundedInt(rawLimit, 10, 1, 25)
  const { data, error } = await supabase.rpc("get_admin_bot_recent_users", {
    p_limit: limit,
    p_timezone: adminTimezone,
  })

  if (error) return errorText("Recent users unavailable", error.message)

  const users = arrayValue(data)
  if (users.length === 0) return "<b>Recent users</b>\nNo users found."

  return [
    `<b>Recent users</b> (${limit})`,
    `Timezone: ${escapeHtml(adminTimezone)}`,
    "",
    ...users.map((value, index) => {
      const user = objectValue(value)
      const id = compactUserId(user.id) ?? "unknown"
      const email = maskEmail(String(user.email ?? ""))
      const provider = String(user.provider ?? "unknown")
      const created = String(user.created_local ?? user.created_at ?? "")
      const last = user.last_sign_in_local ? ` | last ${user.last_sign_in_local}` : ""
      return `${index + 1}. ${escapeHtml(email)} | ${escapeHtml(provider)} | ${escapeHtml(created)} | ${escapeHtml(id)}${escapeHtml(last)}`
    }),
  ].join("\n")
}

async function peakText(rawDays?: string): Promise<string> {
  const days = boundedInt(rawDays, 30, 1, 180)
  const { data, error } = await supabase.rpc("get_admin_bot_peak_hours", {
    p_days: days,
    p_timezone: adminTimezone,
  })

  if (error) return errorText("Peak hours unavailable", error.message)

  const peak = objectValue(data)
  const starts = arrayValue(peak.session_created_hours)
  const refreshes = arrayValue(peak.session_refresh_hours)
  const userLocal = arrayValue(peak.captured_user_timezone_hours)

  return [
    `<b>Peak hours</b> (${days}d)`,
    `Owner timezone: ${escapeHtml(String(peak.timezone ?? adminTimezone))}`,
    "",
    "<b>Session starts</b>",
    formatHours(starts),
    "",
    "<b>Session refreshes</b>",
    formatHours(refreshes),
    "",
    "<b>User local timezone</b>",
    userLocal.length > 0 ? formatHours(userLocal) : "Will fill after updated apps report auth events.",
  ].join("\n")
}

function helpText(): string {
  return [
    "<b>Ezcar24 admin bot</b>",
    "/stats - users, providers, sessions",
    "/users [1-25] - recent users",
    "/peak [days] - peak login/session hours",
  ].join("\n")
}

function menuMarkup() {
  return {
    inline_keyboard: [
      [
        { text: "Stats", callback_data: "stats" },
        { text: "Users", callback_data: "users" },
        { text: "Peak", callback_data: "peak" },
      ],
    ],
  }
}

function formatHours(values: unknown[]): string {
  if (values.length === 0) return "No activity in this window."
  return values.map((value) => {
    const item = objectValue(value)
    const hour = String(item.hour ?? "0").padStart(2, "0")
    return `${hour}:00 - ${intValue(item.count)}`
  }).join("\n")
}

async function sendMessage(
  chatId: string,
  text: string,
  replyMarkup?: Record<string, unknown>
) {
  await telegram("sendMessage", {
    chat_id: chatId,
    text,
    parse_mode: "HTML",
    disable_web_page_preview: true,
    ...(replyMarkup ? { reply_markup: replyMarkup } : {}),
  })
}

async function answerCallback(callbackQueryId: string, text?: string) {
  await telegram("answerCallbackQuery", {
    callback_query_id: callbackQueryId,
    ...(text ? { text } : {}),
  })
}

async function telegram(method: string, payload: Record<string, unknown>) {
  if (!botToken) return { ok: false, description: "TELEGRAM_BOT_TOKEN is not configured" }

  const response = await fetch(`https://api.telegram.org/bot${botToken}/${method}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  })
  const body = await response.json().catch(() => ({}))
  return response.ok ? body : { ok: false, status: response.status, body }
}

function chatIdFromMessage(message: Record<string, unknown>): string | null {
  const chat = message.chat as Record<string, unknown> | undefined
  const id = chat?.id
  return typeof id === "number" || typeof id === "string" ? String(id) : null
}

function isOwnerChat(chatId: string | null): chatId is string {
  return Boolean(chatId && ownerChatId && chatId === ownerChatId)
}

function objectValue(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {}
}

function arrayValue(value: unknown): unknown[] {
  return Array.isArray(value) ? value : []
}

function intValue(value: unknown): number {
  const number = typeof value === "number" ? value : Number(value)
  return Number.isFinite(number) ? Math.trunc(number) : 0
}

function boundedInt(value: unknown, fallback: number, min: number, max: number): number {
  const number = Number(value)
  if (!Number.isFinite(number)) return fallback
  return Math.min(Math.max(Math.trunc(number), min), max)
}

function maskEmail(value: string): string {
  const [name, domain] = value.split("@")
  if (!name || !domain) return value || "unknown"
  const prefix = name.slice(0, Math.min(name.length, 2))
  return `${prefix}${"*".repeat(Math.max(3, Math.min(8, name.length - prefix.length)))}@${domain}`
}

function compactUserId(value: unknown): string | null {
  const cleaned = typeof value === "string" ? value.trim() : null
  if (!cleaned) return null
  return cleaned.length > 18 ? `${cleaned.slice(0, 8)}...${cleaned.slice(-6)}` : cleaned
}

function errorText(title: string, message: string): string {
  return `<b>${escapeHtml(title)}</b>\n${escapeHtml(message)}`
}

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
}

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  })
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
