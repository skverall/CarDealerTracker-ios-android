import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2"

const deepSeekEndpoint = "https://api.deepseek.com/chat/completions"
const deepSeekModel = "deepseek-v4-flash"
const dailyLimit = positiveInteger(Deno.env.get("AI_INSIGHTS_DAILY_LIMIT"), 15)
const historyLimit = positiveInteger(Deno.env.get("AI_INSIGHTS_HISTORY_LIMIT"), 20)

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
}

const systemPrompt = [
  "You are a financial analyst for a car dealership business.",
  "Analyze the dealer data and return only valid JSON with this exact shape: {summary: string, insights: string[], recommendations: string[]}.",
  "The language rule is mandatory: write every user-facing value in summary, insights, and recommendations only in outputLanguage.name.",
  "Follow outputLanguage.instruction exactly, including script and transliteration rules.",
  "Brand names, vehicle model names, numbers, currency symbols, and currency codes may remain unchanged.",
  "Do not answer in any language other than outputLanguage.name.",
  "If previousReports use another language, use them only as context and rewrite the final answer in outputLanguage.name.",
  "Keep summary to 2-3 sentences, insights to 3 concrete observations, and recommendations to 3 practical actions.",
].join(" ")

const languageRepairPrompt = [
  "You are a strict business translation engine.",
  "Return only valid JSON with this exact shape: {summary: string, insights: string[], recommendations: string[]}.",
  "Rewrite every user-facing value into outputLanguage.name and follow outputLanguage.instruction exactly.",
  "Preserve the business meaning, numbers, currency symbols, currency codes, brand names, and vehicle model names.",
  "For Latin-script languages, translate into the actual requested language, not merely Latin letters.",
  "Never keep English prose unless outputLanguage.code is en.",
].join(" ")

const languageVerifierPrompt = [
  "You are a strict language verifier for business reports.",
  "Return only valid JSON with this exact shape: {matches: boolean, detectedLanguage: string, confidence: number}.",
  "matches must be true only when all user-facing business prose is written in outputLanguage.name and follows outputLanguage.instruction.",
  "Ignore brand names, vehicle model names, numbers, currency symbols, currency codes, URLs, and short technical product names.",
  "For Latin-script languages, identify the actual language, not only the script.",
  "English prose must not match Uzbek, Hindi, Russian, Arabic, Japanese, Korean, or any other non-English outputLanguage.",
].join(" ")

const languageHistoryVerifierPrompt = [
  "You are a strict language verifier for saved business reports.",
  "Return only valid JSON with this exact shape: {acceptedIds: string[]}.",
  "Include only report ids whose user-facing business prose is written in outputLanguage.name and follows outputLanguage.instruction.",
  "Ignore brand names, vehicle model names, numbers, currency symbols, currency codes, URLs, and short technical product names.",
  "For Latin-script languages, identify the actual language, not only the script.",
].join(" ")

const languageSpecs: Record<string, LanguageSpec> = {
  en: {
    code: "en",
    name: "English",
    semanticValidation: true,
  },
  ru: {
    code: "ru",
    name: "Russian",
    scriptInstruction: "Use Cyrillic script.",
    scriptPattern: /[\u0400-\u04FF]/u,
    minScriptCharacters: 12,
    minScriptRatio: 0.15,
    semanticValidation: true,
  },
  ar: {
    code: "ar",
    name: "Arabic",
    scriptInstruction: "Use Arabic script.",
    scriptPattern: /[\u0600-\u06FF]/u,
    minScriptCharacters: 12,
    minScriptRatio: 0.15,
    semanticValidation: true,
  },
  ja: {
    code: "ja",
    name: "Japanese",
    scriptInstruction: "Use Japanese script.",
    scriptPattern: /[\u3040-\u30FF\u3400-\u9FFF]/u,
    minScriptCharacters: 12,
    minScriptRatio: 0.15,
    semanticValidation: true,
  },
  ko: {
    code: "ko",
    name: "Korean",
    scriptInstruction: "Use Hangul script.",
    scriptPattern: /[\uAC00-\uD7AF\u1100-\u11FF\u3130-\u318F]/u,
    minScriptCharacters: 12,
    minScriptRatio: 0.15,
    semanticValidation: true,
  },
  uz: {
    code: "uz",
    name: "Uzbek",
    scriptInstruction: "Use modern Uzbek Latin prose. Do not use English or Russian sentences.",
    semanticValidation: true,
  },
  hi: {
    code: "hi",
    name: "Hindi",
    scriptInstruction: "Use Hindi in Devanagari script. Do not use English sentences or Latin transliteration.",
    scriptPattern: /[\u0900-\u097F]/u,
    minScriptCharacters: 18,
    minScriptRatio: 0.15,
    semanticValidation: true,
  },
}

type DealerDataPayload = {
  mode?: unknown
  sales?: unknown
  expenses?: unknown
  inventory?: unknown
  metadata?: unknown
  forceRefresh?: unknown
  fingerprint?: unknown
}

type NormalizedMetadata = {
  language: string
  currencyCode: string
  region: string
  period: string
  organizationId: string | null
  periodStart: string | null
  periodEnd: string | null
}

type NormalizedDealerData = {
  sales: unknown[]
  expenses: unknown[]
  inventory: unknown[]
  metadata: NormalizedMetadata
}

type AIInsightsPromptPayload = NormalizedDealerData & {
  outputLanguage: OutputLanguageInstruction
  previousReports?: AIInsightReportPayload[]
}

type OutputLanguageInstruction = {
  code: string
  name: string
  instruction: string
}

type LanguageSpec = {
  code: string
  name: string
  scriptInstruction?: string
  scriptPattern?: RegExp
  minScriptCharacters?: number
  minScriptRatio?: number
  semanticValidation: boolean
}

type LanguageVerificationResponse = {
  matches: boolean
  detectedLanguage: string
  confidence: number
}

type LanguageHistoryVerificationResponse = {
  acceptedIds: string[]
}

type AIInsightsResponse = {
  summary: string
  insights: string[]
  recommendations: string[]
}

type AIInsightsUsage = {
  used: number
  limit: number
  remaining: number
  resetsAt: string
}

type AIInsightReportPayload = AIInsightsResponse & {
  id: string
  period: string
  language: string | null
  createdAt: string
}

type AIInsightReportRow = {
  id: string
  period: string
  language: string | null
  summary: string
  insights: unknown
  recommendations: unknown
  created_at: string
}

class HttpError extends Error {
  status: number
  code?: string
  details?: Record<string, unknown>

  constructor(message: string, status: number, code?: string, details?: Record<string, unknown>) {
    super(message)
    this.status = status
    this.code = code
    this.details = details
  }
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  try {
    if (req.method !== "POST") {
      throw new HttpError("Method not allowed", 405)
    }

    const authorization = req.headers.get("Authorization")
    if (!authorization) {
      throw new HttpError("Unauthorized", 401)
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? ""
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? ""
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""

    const supabaseClient = createClient(
      supabaseUrl,
      anonKey,
      {
        auth: {
          persistSession: false,
          autoRefreshToken: false,
        },
        global: { headers: { Authorization: authorization } },
      },
    )

    const {
      data: { user },
      error: authError,
    } = await supabaseClient.auth.getUser()
    if (authError || !user) {
      throw new HttpError("Unauthorized", 401)
    }

    const admin = serviceRoleKey
      ? createClient(supabaseUrl, serviceRoleKey, {
        auth: {
          persistSession: false,
          autoRefreshToken: false,
        },
      })
      : null

    const body = await req.json() as DealerDataPayload
    const mode = body.mode === "history" ? "history" : "generate"
    const metadata = normalizeMetadata(body.metadata)
    const deepSeekApiKey = Deno.env.get("DEEPSEEK_API_KEY")

    if (mode === "history") {
      const organizationId = await resolveAuthorizedOrganizationId(admin, user.id, metadata.organizationId)
      const usage = await loadUsage(admin, user.id)
      const reports = await loadHistory(admin, organizationId, metadata.period, metadata.language, deepSeekApiKey)
      return jsonResponse({ reports, usage }, 200)
    }

    if (!deepSeekApiKey) {
      throw new HttpError("DeepSeek API key is not configured", 500)
    }

    const payload = normalizeDealerData(body, metadata)
    const fingerprint = normalizeFingerprint(body.fingerprint) ?? await fingerprintFor(payload)
    const forceRefresh = body.forceRefresh === true

    if (admin) {
      const organizationId = await resolveAuthorizedOrganizationId(admin, user.id, payload.metadata.organizationId)
      const usage = await loadUsage(admin, user.id)

      if (!forceRefresh) {
        const existingReport = await findExistingReport(
          admin,
          organizationId,
          payload.metadata.period,
          fingerprint,
          payload.metadata.language,
        )
        const outputLanguage = outputLanguageInstruction(payload.metadata.language)
        if (existingReport && await responseMatchesLanguage(deepSeekApiKey, existingReport, outputLanguage)) {
          const reports = await loadHistory(admin, organizationId, payload.metadata.period, payload.metadata.language, deepSeekApiKey)
          return jsonResponse({
            ...existingReport,
            reportId: existingReport.id,
            generatedAt: existingReport.createdAt,
            usage,
            history: reports,
          }, 200)
        }
      }

      if (usage.remaining <= 0) {
        throw new HttpError(
          "AI insights daily limit reached",
          429,
          "AI_INSIGHTS_LIMIT_REACHED",
          { usage },
        )
      }

      const previousReports = await loadHistory(admin, organizationId, payload.metadata.period, payload.metadata.language, deepSeekApiKey)
      const parsed = await requestDeepSeekInsights(deepSeekApiKey, payload, previousReports.slice(0, 5))
      const report = await saveReport(admin, {
        organizationId,
        requestedBy: user.id,
        fingerprint,
        payload,
        response: parsed,
      })
      const nextUsage = await loadUsage(admin, user.id)
      const reports = await loadHistory(admin, organizationId, payload.metadata.period, payload.metadata.language, deepSeekApiKey)

      return jsonResponse({
        ...parsed,
        reportId: report.id,
        generatedAt: report.createdAt,
        usage: nextUsage,
        history: reports,
      }, 200)
    }

    const parsed = await requestDeepSeekInsights(deepSeekApiKey, payload)
    return jsonResponse(parsed, 200)
  } catch (error) {
    const status = error instanceof HttpError ? error.status : 400
    return jsonResponse(errorBody(error), status)
  }
})

async function requestDeepSeekInsights(
  deepSeekApiKey: string,
  payload: NormalizedDealerData,
  previousReports: AIInsightReportPayload[] = [],
) {
  const outputLanguage = outputLanguageInstruction(payload.metadata.language)
  const promptPayload: AIInsightsPromptPayload = previousReports.length > 0
    ? { ...payload, outputLanguage, previousReports }
    : { ...payload, outputLanguage }

  const parsed = await requestDeepSeekJSON(
    deepSeekApiKey,
    [
      { role: "system", content: systemPrompt },
      { role: "user", content: JSON.stringify(promptPayload) },
    ],
  )
  return ensureResponseLanguage(deepSeekApiKey, parsed, outputLanguage)
}

async function requestDeepSeekJSON(
  deepSeekApiKey: string,
  messages: Array<{ role: "system" | "user"; content: string }>,
) {
  return parseAIInsights(await requestDeepSeekContent(deepSeekApiKey, messages, 900, 0.2))
}

async function requestDeepSeekContent(
  deepSeekApiKey: string,
  messages: Array<{ role: "system" | "user"; content: string }>,
  maxTokens: number,
  temperature: number,
) {
  const deepSeekResponse = await fetch(deepSeekEndpoint, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${deepSeekApiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: deepSeekModel,
      thinking: { type: "disabled" },
      response_format: { type: "json_object" },
      temperature,
      max_tokens: maxTokens,
      messages,
    }),
  })

  if (!deepSeekResponse.ok) {
    const detail = await safeResponseText(deepSeekResponse)
    console.error("DeepSeek ai-insights error", deepSeekResponse.status, detail)
    throw new HttpError("AI provider request failed", 502)
  }

  const deepSeekPayload = await deepSeekResponse.json()
  const content = deepSeekPayload?.choices?.[0]?.message?.content
  if (typeof content !== "string" || content.trim().length === 0) {
    throw new HttpError("AI provider returned an empty response", 502)
  }

  return content
}

async function ensureResponseLanguage(
  deepSeekApiKey: string,
  response: AIInsightsResponse,
  outputLanguage: OutputLanguageInstruction,
) {
  if (await responseMatchesLanguage(deepSeekApiKey, response, outputLanguage)) {
    return response
  }

  const repaired = await requestDeepSeekJSON(
    deepSeekApiKey,
    [
      { role: "system", content: languageRepairPrompt },
      {
        role: "user",
        content: JSON.stringify({
          outputLanguage,
          report: response,
        }),
      },
    ],
  )

  if (await responseMatchesLanguage(deepSeekApiKey, repaired, outputLanguage)) {
    return repaired
  }

  console.error("DeepSeek ai-insights language mismatch", outputLanguage.code)
  throw new HttpError(
    "AI provider returned report in the wrong language. Please try again.",
    502,
    "AI_INSIGHTS_LANGUAGE_MISMATCH",
  )
}

function normalizeDealerData(body: DealerDataPayload, metadata: NormalizedMetadata): NormalizedDealerData {
  const sales = normalizeArray(body?.sales, "sales", 200)
  const expenses = normalizeArray(body?.expenses, "expenses", 500)
  const inventory = normalizeArray(body?.inventory, "inventory", 300)

  if (sales.length === 0 && expenses.length === 0 && inventory.length === 0) {
    throw new HttpError("Dealer data is empty", 400)
  }

  return { sales, expenses, inventory, metadata }
}

function normalizeMetadata(value: unknown): NormalizedMetadata {
  const object = value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {}

  return {
    language: normalizeLanguageCode(object.language),
    currencyCode: cleanString(object.currencyCode, "USD"),
    region: cleanString(object.region, "unknown"),
    period: normalizePeriod(object.period),
    organizationId: sanitizeUuid(cleanString(object.organizationId, "")),
    periodStart: normalizeDateString(object.periodStart),
    periodEnd: normalizeDateString(object.periodEnd),
  }
}

function normalizeLanguageCode(value: unknown) {
  const code = cleanString(value, "en").toLowerCase().split(/[-_]/)[0]
  return languageSpecs[code] ? code : "en"
}

function outputLanguageInstruction(code: string): OutputLanguageInstruction {
  const spec = languageSpecFor(code)

  return {
    code: spec.code,
    name: spec.name,
    instruction: `Answer only in ${spec.name}.${spec.scriptInstruction ? ` ${spec.scriptInstruction}` : ""}`,
  }
}

function languageSpecFor(code: string) {
  return languageSpecs[normalizeLanguageCode(code)] ?? languageSpecs.en
}

async function responseMatchesLanguage(
  deepSeekApiKey: string,
  response: AIInsightsResponse,
  outputLanguage: OutputLanguageInstruction,
) {
  const spec = languageSpecFor(outputLanguage.code)
  if (!responseMatchesScript(response, spec)) {
    return false
  }
  if (!spec.semanticValidation) {
    return true
  }
  return await verifyResponseLanguage(deepSeekApiKey, response, outputLanguage)
}

function responseMatchesStaticLanguage(response: AIInsightsResponse, languageCode: string) {
  return responseMatchesScript(response, languageSpecFor(languageCode))
}

function responseMatchesScript(response: AIInsightsResponse, spec: LanguageSpec) {
  if (!spec.scriptPattern) return true

  const text = responseTextForLanguageValidation(response)
  const letters = countLetters(text)
  if (letters === 0) return false
  const scriptCharacters = countMatchingCharacters(text, spec.scriptPattern)
  const minCharacters = spec.minScriptCharacters ?? 12
  const minRatio = spec.minScriptRatio ?? 0.15
  return scriptCharacters >= minCharacters || scriptCharacters / letters >= minRatio
}

async function verifyResponseLanguage(
  deepSeekApiKey: string,
  response: AIInsightsResponse,
  outputLanguage: OutputLanguageInstruction,
) {
  const content = await requestDeepSeekContent(
    deepSeekApiKey,
    [
      { role: "system", content: languageVerifierPrompt },
      {
        role: "user",
        content: JSON.stringify({
          outputLanguage,
          reportText: responseTextForLanguageValidation(response),
        }),
      },
    ],
    220,
    0,
  )
  const verification = parseLanguageVerification(content)
  return verification.matches && verification.confidence >= 0.7
}

function parseLanguageVerification(content: string): LanguageVerificationResponse {
  const cleaned = content
    .trim()
    .replace(/^```json\s*/i, "")
    .replace(/^```\s*/i, "")
    .replace(/\s*```$/i, "")
    .trim()

  let parsed: unknown
  try {
    parsed = JSON.parse(cleaned)
  } catch {
    throw new HttpError("AI provider returned invalid language verification JSON", 502)
  }

  if (!parsed || typeof parsed !== "object") {
    throw new HttpError("AI provider returned invalid language verification shape", 502)
  }

  const object = parsed as Record<string, unknown>
  return {
    matches: object.matches === true,
    detectedLanguage: typeof object.detectedLanguage === "string" ? object.detectedLanguage.trim() : "unknown",
    confidence: typeof object.confidence === "number" && Number.isFinite(object.confidence)
      ? Math.max(0, Math.min(1, object.confidence))
      : 0,
  }
}

async function filterReportsBySemanticLanguage(
  reports: AIInsightReportPayload[],
  language: string,
  deepSeekApiKey?: string,
) {
  if (reports.length === 0) return reports
  const outputLanguage = outputLanguageInstruction(language)
  const spec = languageSpecFor(outputLanguage.code)
  if (!deepSeekApiKey || spec.scriptPattern || !spec.semanticValidation) {
    return reports
  }

  const content = await requestDeepSeekContent(
    deepSeekApiKey,
    [
      { role: "system", content: languageHistoryVerifierPrompt },
      {
        role: "user",
        content: JSON.stringify({
          outputLanguage,
          reports: reports.map((report) => ({
            id: report.id,
            text: responseTextForLanguageValidation(report),
          })),
        }),
      },
    ],
    600,
    0,
  )
  const verification = parseLanguageHistoryVerification(content)
  const acceptedIds = new Set(verification.acceptedIds)
  return reports.filter((report) => acceptedIds.has(report.id))
}

function parseLanguageHistoryVerification(content: string): LanguageHistoryVerificationResponse {
  const cleaned = content
    .trim()
    .replace(/^```json\s*/i, "")
    .replace(/^```\s*/i, "")
    .replace(/\s*```$/i, "")
    .trim()

  let parsed: unknown
  try {
    parsed = JSON.parse(cleaned)
  } catch {
    throw new HttpError("AI provider returned invalid language history verification JSON", 502)
  }

  if (!parsed || typeof parsed !== "object") {
    throw new HttpError("AI provider returned invalid language history verification shape", 502)
  }

  const object = parsed as Record<string, unknown>
  return {
    acceptedIds: Array.isArray(object.acceptedIds)
      ? object.acceptedIds.filter((id): id is string => typeof id === "string")
      : [],
  }
}

function responseTextForLanguageValidation(response: AIInsightsResponse) {
  return [
    response.summary,
    ...response.insights,
    ...response.recommendations,
  ].join(" ")
}

function countLetters(text: string) {
  let count = 0
  for (const character of text) {
    if (/\p{L}/u.test(character)) count += 1
  }
  return count
}

function countMatchingCharacters(text: string, pattern: RegExp) {
  let count = 0
  for (const character of text) {
    if (pattern.test(character)) count += 1
  }
  return count
}

function normalizePeriod(value: unknown) {
  const period = cleanString(value, "month")
  const allowed = new Set(["today", "week", "month", "threeMonths", "sixMonths", "all"])
  return allowed.has(period) ? period : "month"
}

function normalizeArray(value: unknown, name: string, maxItems: number): unknown[] {
  if (!Array.isArray(value)) {
    throw new HttpError(`${name} must be an array`, 400)
  }
  return value.slice(0, maxItems)
}

function parseAIInsights(content: string): AIInsightsResponse {
  const cleaned = content
    .trim()
    .replace(/^```json\s*/i, "")
    .replace(/^```\s*/i, "")
    .replace(/\s*```$/i, "")
    .trim()

  let parsed: unknown
  try {
    parsed = JSON.parse(cleaned)
  } catch {
    throw new HttpError("AI provider returned invalid JSON", 502)
  }

  if (!parsed || typeof parsed !== "object") {
    throw new HttpError("AI provider returned invalid JSON shape", 502)
  }

  const object = parsed as Record<string, unknown>
  const summary = typeof object.summary === "string" ? object.summary.trim() : ""
  const insights = normalizeStringList(object.insights)
  const recommendations = normalizeStringList(object.recommendations)

  if (!summary || insights.length === 0 || recommendations.length === 0) {
    throw new HttpError("AI provider returned incomplete JSON", 502)
  }

  return {
    summary,
    insights: insights.slice(0, 3),
    recommendations: recommendations.slice(0, 3),
  }
}

async function resolveAuthorizedOrganizationId(
  admin: SupabaseClient | null,
  userId: string,
  requestedOrganizationId: string | null,
) {
  if (!admin) {
    throw new HttpError("AI history storage is not configured", 500)
  }

  const organizationId = requestedOrganizationId ?? await resolveFallbackOrganizationId(admin, userId)
  if (!organizationId) {
    throw new HttpError("Organization not found", 403)
  }

  await assertOrganizationAccess(admin, userId, organizationId)
  return organizationId
}

async function resolveFallbackOrganizationId(admin: SupabaseClient, userId: string) {
  const { data: ownedOrg, error: ownedError } = await admin
    .from("organizations")
    .select("id")
    .eq("owner_id", userId)
    .order("created_at", { ascending: true })
    .limit(1)
    .maybeSingle()

  if (ownedError) throw ownedError
  if (ownedOrg?.id && typeof ownedOrg.id === "string") return ownedOrg.id

  const { data: membership, error: membershipError } = await admin
    .from("dealer_team_members")
    .select("organization_id")
    .eq("user_id", userId)
    .eq("status", "active")
    .order("created_at", { ascending: true })
    .limit(1)
    .maybeSingle()

  if (membershipError) throw membershipError
  return typeof membership?.organization_id === "string" ? membership.organization_id : null
}

async function assertOrganizationAccess(admin: SupabaseClient, userId: string, organizationId: string) {
  const { data: ownedOrg, error: ownedError } = await admin
    .from("organizations")
    .select("id")
    .eq("id", organizationId)
    .eq("owner_id", userId)
    .maybeSingle()

  if (ownedError) throw ownedError
  if (ownedOrg?.id) return

  const { data: membership, error: membershipError } = await admin
    .from("dealer_team_members")
    .select("id")
    .eq("organization_id", organizationId)
    .eq("user_id", userId)
    .eq("status", "active")
    .maybeSingle()

  if (membershipError) throw membershipError
  if (!membership?.id) {
    throw new HttpError("Forbidden", 403)
  }
}

async function loadUsage(admin: SupabaseClient | null, userId: string): Promise<AIInsightsUsage> {
  if (!admin) {
    throw new HttpError("AI history storage is not configured", 500)
  }

  const now = new Date()
  const windowStart = new Date(Date.UTC(
    now.getUTCFullYear(),
    now.getUTCMonth(),
    now.getUTCDate(),
  ))
  const resetsAt = new Date(windowStart)
  resetsAt.setUTCDate(resetsAt.getUTCDate() + 1)

  const { count, error } = await admin
    .from("ai_insight_reports")
    .select("id", { count: "exact", head: true })
    .eq("requested_by", userId)
    .gte("created_at", windowStart.toISOString())

  if (error) throw error

  const used = count ?? 0

  return {
    used,
    limit: dailyLimit,
    remaining: Math.max(0, dailyLimit - used),
    resetsAt: resetsAt.toISOString(),
  }
}

async function findExistingReport(
  admin: SupabaseClient,
  organizationId: string,
  period: string,
  fingerprint: string,
  language: string,
) {
  const { data, error } = await admin
    .from("ai_insight_reports")
    .select("id, period, language, summary, insights, recommendations, created_at")
    .eq("organization_id", organizationId)
    .eq("period", period)
    .eq("fingerprint", fingerprint)
    .eq("language", normalizeLanguageCode(language))
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle()

  if (error) throw error
  return data ? reportPayload(data as AIInsightReportRow) : null
}

async function loadHistory(
  admin: SupabaseClient | null,
  organizationId: string,
  period: string,
  language: string,
  deepSeekApiKey?: string,
) {
  if (!admin) {
    throw new HttpError("AI history storage is not configured", 500)
  }

  const query = admin
    .from("ai_insight_reports")
    .select("id, period, language, summary, insights, recommendations, created_at")
    .eq("organization_id", organizationId)
    .eq("period", period)
    .eq("language", normalizeLanguageCode(language))
    .order("created_at", { ascending: false })
    .limit(historyLimit)

  const { data, error } = await query

  if (error) throw error
  const reports = (data ?? [])
    .map((row) => reportPayload(row as AIInsightReportRow))
    .filter((report) => responseMatchesStaticLanguage(report, language))
  return await filterReportsBySemanticLanguage(reports, language, deepSeekApiKey)
}

async function saveReport(
  admin: SupabaseClient,
  args: {
    organizationId: string
    requestedBy: string
    fingerprint: string
    payload: NormalizedDealerData
    response: AIInsightsResponse
  },
) {
  const { organizationId, requestedBy, fingerprint, payload, response } = args
  const { data, error } = await admin
    .from("ai_insight_reports")
    .insert({
      organization_id: organizationId,
      requested_by: requestedBy,
      period: payload.metadata.period,
      range_start: payload.metadata.periodStart,
      range_end: payload.metadata.periodEnd,
      fingerprint,
      language: payload.metadata.language,
      currency_code: payload.metadata.currencyCode,
      region: payload.metadata.region,
      summary: response.summary,
      insights: response.insights,
      recommendations: response.recommendations,
      source_counts: {
        sales: payload.sales.length,
        expenses: payload.expenses.length,
        inventory: payload.inventory.length,
      },
      request_metadata: payload.metadata,
    })
    .select("id, period, language, summary, insights, recommendations, created_at")
    .single()

  if (error) throw error
  return reportPayload(data as AIInsightReportRow)
}

function reportPayload(row: AIInsightReportRow): AIInsightReportPayload {
  return {
    id: row.id,
    period: row.period,
    language: row.language,
    summary: row.summary,
    insights: normalizeStringList(row.insights),
    recommendations: normalizeStringList(row.recommendations),
    createdAt: row.created_at,
  }
}

function normalizeStringList(value: unknown): string[] {
  if (!Array.isArray(value)) return []
  return value
    .filter((item): item is string => typeof item === "string")
    .map((item) => item.trim())
    .filter((item) => item.length > 0)
}

async function fingerprintFor(payload: NormalizedDealerData) {
  const encoded = new TextEncoder().encode(stableStringify(payload))
  const digest = await crypto.subtle.digest("SHA-256", encoded)
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("")
}

function stableStringify(value: unknown): string {
  if (Array.isArray(value)) {
    return `[${value.map(stableStringify).join(",")}]`
  }
  if (value && typeof value === "object") {
    const object = value as Record<string, unknown>
    return `{${Object.keys(object).sort().map((key) => `${JSON.stringify(key)}:${stableStringify(object[key])}`).join(",")}}`
  }
  return JSON.stringify(value)
}

function cleanString(value: unknown, fallback: string) {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : fallback
}

function normalizeFingerprint(value: unknown) {
  const text = cleanString(value, "")
  return /^[0-9a-f]{64}$/i.test(text) ? text.toLowerCase() : null
}

function normalizeDateString(value: unknown) {
  const text = cleanString(value, "")
  return /^\d{4}-\d{2}-\d{2}$/.test(text) ? text : null
}

function sanitizeUuid(value: string | null | undefined) {
  if (!value) return null
  const trimmed = value.trim()
  const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
  return uuidRegex.test(trimmed) ? trimmed : null
}

function positiveInteger(value: string | null | undefined, fallback: number) {
  const parsed = Number.parseInt(value ?? "", 10)
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback
}

async function safeResponseText(response: Response) {
  try {
    return await response.text()
  } catch {
    return ""
  }
}

function jsonResponse(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  })
}

function errorBody(error: unknown) {
  if (error instanceof HttpError) {
    return {
      error: error.message,
      ...(error.code ? { code: error.code } : {}),
      ...(error.details ?? {}),
    }
  }
  return { error: errorMessage(error) }
}

function errorMessage(error: unknown) {
  if (typeof error === "object" && error && "message" in error) {
    return String((error as { message?: unknown }).message ?? "Unexpected error")
  }
  return "Unexpected error"
}
