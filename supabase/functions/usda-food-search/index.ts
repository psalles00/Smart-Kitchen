const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, accept-language",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
}

import { lookupName, type NutritionPayload } from "./lookup.ts"

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  })
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405)
  }

  const apiKey = Deno.env.get("USDA_API_KEY")
  if (!apiKey) {
    return json({ error: "USDA_API_KEY not configured" }, 500)
  }

  try {
    const body = await request.json()
    const names = Array.isArray(body.names)
      ? body.names.filter((value: unknown): value is string => typeof value === "string" && value.trim().length > 0)
      : []

    if (names.length === 0) {
      return json({ items: [] })
    }

    const items: NutritionPayload[] = []
    for (const name of names.slice(0, 20)) {
      try {
        const match = await lookupName(name, apiKey)
        if (match) {
          items.push(match)
        }
      } catch (error) {
        console.error(`USDA lookup failed for ${name}:`, error)
      }
    }

    return json({ items })
  } catch (error) {
    console.error("usda-food-search fatal error", error)
    return json({ error: error instanceof Error ? error.message : "Unknown error" }, 500)
  }
})
