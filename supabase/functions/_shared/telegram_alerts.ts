export type AdminAlert = {
  title: string
  lines?: Array<string | null | undefined>
  details?: Array<string | null | undefined>
  replyMarkup?: Record<string, unknown>
}

export async function sendAdminAlert(alert: AdminAlert): Promise<boolean> {
  const token = Deno.env.get("TELEGRAM_BOT_TOKEN")?.trim()
  const chatId = Deno.env.get("TELEGRAM_CHAT_ID")?.trim()
  const enabled = envFlag("TELEGRAM_ADMIN_ALERTS_ENABLED", true)

  if (!enabled || !token || !chatId) {
    return false
  }

  const text = buildMessage(alert)
  if (!text) {
    return false
  }

  const controller = new AbortController()
  const timeoutMs = envNumber("TELEGRAM_ALERT_TIMEOUT_MS", 3000)
  const timeout = setTimeout(() => controller.abort(), timeoutMs)

  try {
    const response = await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      signal: controller.signal,
      body: JSON.stringify({
        chat_id: chatId,
        text,
        parse_mode: "HTML",
        disable_web_page_preview: true,
        ...(alert.replyMarkup ? { reply_markup: alert.replyMarkup } : {}),
      }),
    })

    if (!response.ok) {
      console.error("Telegram alert failed", response.status, await response.text())
      return false
    }

    return true
  } catch (error) {
    console.error("Telegram alert request failed", error)
    return false
  } finally {
    clearTimeout(timeout)
  }
}

export function boolLabel(value: unknown): string {
  return value === true ? "yes" : "no"
}

export function countryLabel(countryCode: unknown): string | null {
  const code = countryCodeValue(countryCode)
  if (!code) return null
  const flag = flagEmoji(code)
  return flag ? `${flag} ${code}` : code
}

export function countryCodeValue(value: unknown): string | null {
  const cleaned = cleanValue(value)
  if (!cleaned) return null
  const normalized = cleaned.trim().toUpperCase()
  return /^[A-Z]{2}$/.test(normalized) && normalized !== "XX" ? normalized : null
}

export function durationSince(value: unknown, now = new Date()): string | null {
  const cleaned = cleanValue(value)
  if (!cleaned) return null

  const date = new Date(cleaned)
  const timestamp = date.getTime()
  if (!Number.isFinite(timestamp)) return null

  const diffMs = now.getTime() - timestamp
  if (diffMs < 0) return "future"

  const totalMinutes = Math.floor(diffMs / 60000)
  if (totalMinutes < 5) return "just now"
  if (totalMinutes < 60) return `${totalMinutes}m`

  const totalHours = Math.floor(totalMinutes / 60)
  if (totalHours < 48) return `${totalHours}h`

  const totalDays = Math.floor(totalHours / 24)
  if (totalDays < 60) return `${totalDays}d`

  const totalMonths = Math.floor(totalDays / 30)
  if (totalMonths < 24) return `${totalMonths}mo`

  const totalYears = Math.floor(totalDays / 365)
  return `${totalYears}y`
}

export function formatAmount(amount: unknown, currency: unknown): string | null {
  const amountText = cleanValue(amount)
  if (!amountText) return null

  const currencyText = cleanValue(currency)
  return currencyText ? `${amountText} ${currencyText.toUpperCase()}` : amountText
}

export function maskedIp(value: unknown): string | null {
  const cleaned = cleanValue(value)
  if (!cleaned) return null

  const first = cleaned.split(",")[0]?.trim()
  if (!first) return null

  if (/^\d{1,3}(\.\d{1,3}){3}$/.test(first)) {
    const parts = first.split(".")
    return `${parts[0]}.${parts[1]}.${parts[2]}.x`
  }

  if (/^[0-9a-f:]+$/i.test(first) && first.includes(":")) {
    const parts = first.split(":").filter(Boolean)
    return parts.length > 2 ? `${parts.slice(0, 3).join(":")}:...` : `${first}:...`
  }

  return null
}

export function compactUserId(value: unknown): string | null {
  const cleaned = cleanValue(value)
  if (!cleaned) return null
  return cleaned.length > 18 ? `${cleaned.slice(0, 8)}...${cleaned.slice(-6)}` : cleaned
}

export function cleanValue(value: unknown): string | null {
  if (value === null || value === undefined) return null
  if (typeof value === "string") {
    const trimmed = value.trim()
    return trimmed.length > 0 ? trimmed : null
  }
  if (typeof value === "number" || typeof value === "boolean") {
    return String(value)
  }
  if (Array.isArray(value)) {
    const parts = value.map(cleanValue).filter(Boolean)
    return parts.length > 0 ? parts.join(", ") : null
  }
  return null
}

export function alertLine(label: string, value: unknown): string | null {
  const cleaned = cleanValue(value)
  return cleaned ? `${label}: ${cleaned}` : null
}

export function alertSection(title: string): string {
  return `[${title}]`
}

function buildMessage(alert: AdminAlert): string {
  const title = cleanValue(alert.title)
  if (!title) return ""

  const lines = (alert.lines ?? [])
    .map((line) => cleanValue(line))
    .filter((line): line is string => Boolean(line))

  const details = (alert.details ?? [])
    .map((line) => cleanValue(line))
    .filter((line): line is string => Boolean(line))

  const visible = [
    `<b>${escapeHtml(title)}</b>`,
    ...lines.map(escapeHtml),
  ]

  if (details.length > 0) {
    visible.push("")
    visible.push(`<tg-spoiler>${escapeHtml(details.join("\n"))}</tg-spoiler>`)
  }

  return visible.join("\n").slice(0, 4000)
}

function envFlag(name: string, fallback: boolean): boolean {
  const value = Deno.env.get(name)?.trim().toLowerCase()
  if (!value) return fallback
  return !["0", "false", "no", "off"].includes(value)
}

function envNumber(name: string, fallback: number): number {
  const value = Number(Deno.env.get(name))
  return Number.isFinite(value) && value > 0 ? value : fallback
}

function flagEmoji(countryCode: string): string | null {
  if (!/^[A-Z]{2}$/.test(countryCode)) return null
  const base = 127397
  return String.fromCodePoint(...[...countryCode].map((char) => base + char.charCodeAt(0)))
}

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
}
