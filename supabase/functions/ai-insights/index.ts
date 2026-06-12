import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const deepSeekEndpoint = "https://api.deepseek.com/v1/chat/completions"
const deepSeekModel = "deepseek-v4-flash"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
}

const systemPrompt =
  "Ты финансовый аналитик автодилерского бизнеса. Проанализируй данные и верни JSON: {summary: краткий итог 2-3 предложения, insights: массив из 3 конкретных наблюдений, recommendations: массив из 3 действий}. Отвечай только валидным JSON, на языке данных пользователя."

type DealerDataPayload = {
  sales?: unknown
  expenses?: unknown
  inventory?: unknown
  metadata?: unknown
}

type AIInsightsResponse = {
  summary: string
  insights: string[]
  recommendations: string[]
}

class HttpError extends Error {
  status: number

  constructor(message: string, status: number) {
    super(message)
    this.status = status
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

    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      { global: { headers: { Authorization: authorization } } }
    )

    const {
      data: { user },
      error: authError,
    } = await supabaseClient.auth.getUser()
    if (authError || !user) {
      throw new HttpError("Unauthorized", 401)
    }

    const deepSeekApiKey = Deno.env.get("DEEPSEEK_API_KEY")
    if (!deepSeekApiKey) {
      throw new HttpError("DeepSeek API key is not configured", 500)
    }

    const body = await req.json() as DealerDataPayload
    const payload = normalizeDealerData(body)

    const deepSeekResponse = await fetch(deepSeekEndpoint, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${deepSeekApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: deepSeekModel,
        temperature: 0.2,
        max_tokens: 900,
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: JSON.stringify(payload) },
        ],
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

    const parsed = parseAIInsights(content)
    return jsonResponse(parsed, 200)
  } catch (error) {
    const status = error instanceof HttpError ? error.status : 400
    return jsonResponse({ error: errorMessage(error) }, status)
  }
})

function normalizeDealerData(body: DealerDataPayload) {
  const sales = normalizeArray(body?.sales, "sales", 200)
  const expenses = normalizeArray(body?.expenses, "expenses", 500)
  const inventory = normalizeArray(body?.inventory, "inventory", 300)
  const metadata = body?.metadata && typeof body.metadata === "object" && !Array.isArray(body.metadata)
    ? body.metadata
    : {}

  if (sales.length === 0 && expenses.length === 0 && inventory.length === 0) {
    throw new HttpError("Dealer data is empty", 400)
  }

  return { sales, expenses, inventory, metadata }
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

function normalizeStringList(value: unknown): string[] {
  if (!Array.isArray(value)) return []
  return value
    .filter((item): item is string => typeof item === "string")
    .map((item) => item.trim())
    .filter((item) => item.length > 0)
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

function errorMessage(error: unknown) {
  if (typeof error === "object" && error && "message" in error) {
    return String((error as { message?: unknown }).message ?? "Unexpected error")
  }
  return "Unexpected error"
}
