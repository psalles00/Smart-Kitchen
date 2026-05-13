import { serve } from "https://deno.land/std@0.224.0/http/server.ts"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Cache-Control": "no-store",
} as const

const OPENAI_ENDPOINT = "https://api.openai.com/v1/chat/completions"
const DEFAULT_MODEL = "gpt-4.1-mini"
const MAX_MESSAGES = 40
const MAX_TOOLS = 24
const MAX_PAYLOAD_BYTES = 120_000

type JsonObject = Record<string, unknown>

function jsonResponse(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json; charset=utf-8",
    },
  })
}

function isPlainObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value)
}

serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405)
  }

  const openAIKey = Deno.env.get("OPENAI_API_KEY")?.trim() ?? ""
  const model = Deno.env.get("OPENAI_MODEL")?.trim() || DEFAULT_MODEL

  if (!openAIKey) {
    return jsonResponse({ error: "OPENAI_API_KEY is missing in Supabase secrets" }, 500)
  }

  let body: JsonObject
  try {
    body = await request.json()
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400)
  }

  const messages = body.messages
  if (!Array.isArray(messages) || messages.length == 0 || messages.length > MAX_MESSAGES) {
    return jsonResponse({ error: `messages must contain between 1 and ${MAX_MESSAGES} items` }, 400)
  }

  if (!messages.every(isPlainObject)) {
    return jsonResponse({ error: "Each message must be an object" }, 400)
  }

  const tools = body.tools
  if (tools !== undefined) {
    if (!Array.isArray(tools) || tools.length > MAX_TOOLS || !tools.every(isPlainObject)) {
      return jsonResponse({ error: `tools must be an array with at most ${MAX_TOOLS} items` }, 400)
    }
  }

  const serializedPayload = JSON.stringify({ messages, tools })
  if (new TextEncoder().encode(serializedPayload).byteLength > MAX_PAYLOAD_BYTES) {
    return jsonResponse({ error: "Payload too large" }, 413)
  }

  const upstreamBody: JsonObject = {
    model,
    messages,
  }

  if (Array.isArray(tools) && tools.length > 0) {
    upstreamBody.tools = tools
    upstreamBody.tool_choice = "auto"
  }

  try {
    const upstreamResponse = await fetch(OPENAI_ENDPOINT, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${openAIKey}`,
      },
      body: JSON.stringify(upstreamBody),
    })

    const responseText = await upstreamResponse.text()

    return new Response(responseText, {
      status: upstreamResponse.status,
      headers: {
        ...corsHeaders,
        "Content-Type": upstreamResponse.headers.get("content-type") ?? "application/json; charset=utf-8",
      },
    })
  } catch {
    return jsonResponse({ error: "Failed to contact OpenAI from the Supabase function" }, 502)
  }
})