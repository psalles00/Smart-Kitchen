const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, accept-language",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Cache-Control": "no-store",
} as const;

const OPENAI_ENDPOINT = "https://api.openai.com/v1/chat/completions";
const OPENROUTER_ENDPOINT = "https://openrouter.ai/api/v1/chat/completions";
// Multimodal models with tools/JSON support; provider keys stay in Supabase secrets.
export const FALLBACK_MODELS = [
  "qwen/qwen3.5-flash-02-23",
  "google/gemini-3.1-flash-lite",
];
// Recipe discovery needs substantive combinations, not just valid JSON.
// Keep the cheaper default for other chat requests; reuse the same two models
// with explicit bounded attempts for the structured recipe workflow.
export const RECIPE_IDEA_FALLBACK_MODELS = [
  "google/gemini-3.1-flash-lite",
  "qwen/qwen3.5-flash-02-23",
];
const ALLOWED_MODELS = new Set(["gpt-4.1-mini", "gpt-4o-mini"]);
const MAX_MESSAGES = 40;
const MAX_TOOLS = 24;
const MAX_PAYLOAD_BYTES = 8_000_000;

type JsonObject = Record<string, unknown>;

function jsonResponse(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json; charset=utf-8",
    },
  });
}

function isPlainObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function stringValue(value: unknown): string | undefined {
  return typeof value === "string" ? value.trim() || undefined : undefined;
}

// Some routed providers accept structured outputs but reject local references.
// Inline only the three ingredient references emitted by this app. Preserve
// the same enum and all other constraints; never rewrite arbitrary schemas.
export function portableRecipeFormat(format: JsonObject): JsonObject {
  const result = structuredClone(format);
  const schema = isPlainObject(result.json_schema)
    ? result.json_schema.schema
    : undefined;
  if (!isPlainObject(schema) || !isPlainObject(schema.$defs)) return format;
  const ingredient = schema.$defs.ingredientName;
  const properties = isPlainObject(schema.properties)
    ? schema.properties
    : undefined;
  const ideas = properties && isPlainObject(properties.ideas)
    ? properties.ideas
    : undefined;
  const item = ideas && isPlainObject(ideas.items) ? ideas.items : undefined;
  const fields = item && isPlainObject(item.properties)
    ? item.properties
    : undefined;
  if (!isPlainObject(ingredient) || ingredient.type !== "string" || !fields) {
    return format;
  }
  const reference = (value: unknown) =>
    isPlainObject(value) &&
    Object.keys(value).length === 1 && value.$ref === "#/$defs/ingredientName";
  if (
    !reference(fields.mainIngredient) || !isPlainObject(fields.ingredients) ||
    !reference(fields.ingredients.items) ||
    !isPlainObject(fields.requiresPrecooked) ||
    !reference(fields.requiresPrecooked.items)
  ) return format;
  fields.mainIngredient = structuredClone(ingredient);
  fields.ingredients.items = structuredClone(ingredient);
  fields.requiresPrecooked.items = structuredClone(ingredient);
  // Keep definitions only if an unfamiliar reference may still use them.
  const { $defs: _definitions, ...root } = schema;
  if (!JSON.stringify(root).includes('"$ref"')) delete schema.$defs;
  return result;
}

export async function handleRequest(
  request: Request,
  dependencies = { fetch, env: (name: string) => Deno.env.get(name) },
) {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  const openAIKey = dependencies.env("OPENAI_API_KEY")?.trim() ?? "";
  const openRouterKey = dependencies.env("OPEN_ROUTER_KEY")?.trim() ?? "";

  let body: JsonObject;
  try {
    const raw = await request.text();
    if (new TextEncoder().encode(raw).byteLength > MAX_PAYLOAD_BYTES) {
      return jsonResponse({ error: "Payload too large" }, 413);
    }
    const parsed = JSON.parse(raw);
    if (!isPlainObject(parsed)) {
      return jsonResponse({ error: "Body must be an object" }, 400);
    }
    body = parsed;
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

  const messages = body.messages;
  if (
    !Array.isArray(messages) || messages.length === 0 ||
    messages.length > MAX_MESSAGES
  ) {
    return jsonResponse({
      error: `messages must contain between 1 and ${MAX_MESSAGES} items`,
    }, 400);
  }

  if (!messages.every(isPlainObject)) {
    return jsonResponse({ error: "Each message must be an object" }, 400);
  }

  const tools = body.tools;
  if (tools !== undefined) {
    if (
      !Array.isArray(tools) || tools.length > MAX_TOOLS ||
      !tools.every(isPlainObject)
    ) {
      return jsonResponse({
        error: `tools must be an array with at most ${MAX_TOOLS} items`,
      }, 400);
    }
  }

  const model = stringValue(body.model) ??
    dependencies.env("OPENAI_MODEL")?.trim() ?? "gpt-4.1-mini";
  if (!ALLOWED_MODELS.has(model)) {
    return jsonResponse({ error: `Model ${model} is not allowed` }, 400);
  }

  const serializedPayload = JSON.stringify(body);
  if (
    new TextEncoder().encode(serializedPayload).byteLength > MAX_PAYLOAD_BYTES
  ) {
    return jsonResponse({ error: "Payload too large" }, 413);
  }

  const upstreamBody: JsonObject = {
    model,
    messages,
  };

  if (Array.isArray(tools) && tools.length > 0) {
    upstreamBody.tools = tools;
    upstreamBody.tool_choice = body.tool_choice === "required"
      ? "required"
      : "auto";
  }

  if (isPlainObject(body.response_format)) {
    upstreamBody.response_format = body.response_format;
  }

  if (typeof body.temperature === "number") {
    upstreamBody.temperature = body.temperature;
  }

  upstreamBody.max_tokens =
    typeof body.max_tokens === "number" && Number.isFinite(body.max_tokens)
      ? Math.min(8192, Math.max(1, Math.floor(body.max_tokens)))
      : 4096;

  async function callProvider(
    endpoint: string,
    key: string,
    payload: JsonObject,
    timeoutMs = 45_000,
  ) {
    const upstreamResponse = await dependencies.fetch(endpoint, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${key}`,
        ...(endpoint === OPENROUTER_ENDPOINT
          ? { "HTTP-Referer": "https://smartkitchen.app", "X-Title": "Savoria" }
          : {}),
      },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(timeoutMs),
    });

    const responseText = await upstreamResponse.text();
    // Some upstream providers report errors/empty choices with HTTP 200.
    let valid = false;
    try {
      const result = JSON.parse(responseText);
      const message = result?.choices?.[0]?.message;
      valid = !result.error && !!message &&
        ((typeof message.content === "string" &&
          message.content.trim().length > 0) ||
          (Array.isArray(message.tool_calls) && message.tool_calls.length > 0));
    } catch { /* A malformed completion must not be accepted as success. */ }
    return {
      status: upstreamResponse.ok && !valid ? 502 : upstreamResponse.status,
      text: responseText,
      valid,
    };
  }

  let primary: { status: number; text: string; valid: boolean } | undefined;
  if (openAIKey) {
    try {
      primary = await callProvider(OPENAI_ENDPOINT, openAIKey, upstreamBody);
      if (primary.status < 400) {
        return completion(primary.text, primary.status, "openai");
      }
      if (
        ![401, 403, 408, 429].includes(primary.status) && primary.status < 500
      ) {
        return jsonResponse({
          error: "Invalid AI request",
          upstream_status: primary.status,
        }, primary.status);
      }
    } catch { /* Network failure/timeout: one bounded fallback request. */ }
  }
  if (openRouterKey) {
    const format = upstreamBody.response_format;
    const isRecipeIdeas = isPlainObject(format) &&
      format.type === "json_schema" &&
      isPlainObject(format.json_schema) &&
      format.json_schema.name === "recipe_ideas";
    const fallbackBody: JsonObject = {
      ...upstreamBody,
      models: isRecipeIdeas ? RECIPE_IDEA_FALLBACK_MODELS : FALLBACK_MODELS,
      provider: { require_parameters: true },
      // Recipe selection benefits from bounded low-effort ingredient planning.
      reasoning: isRecipeIdeas
        ? { effort: "low", exclude: true }
        : { enabled: false },
    };
    if (isRecipeIdeas && isPlainObject(format)) {
      fallbackBody.response_format = portableRecipeFormat(format);
    }
    delete (fallbackBody as JsonObject).model;
    // Explicit recipe attempts make model availability observable. Ordinary chat
    // keeps its existing single router request. No model is attempted twice here.
    const candidates = isRecipeIdeas ? RECIPE_IDEA_FALLBACK_MODELS : [undefined];
    let failure: string | undefined;
    let lastStatus: number | undefined;
    // Preserve the existing 45-second total fallback time budget. Reserve up to
    // 15 seconds for Qwen if Gemini stalls; do not extend the client wait.
    const fallbackDeadline = Date.now() + 45_000;
    for (const candidate of candidates) {
      const payload = { ...fallbackBody };
      if (candidate) {
        delete payload.models;
        payload.model = candidate;
        payload.reasoning = candidate.startsWith("google/")
          ? { effort: "low", exclude: true }
          : { enabled: false };
        // The app validates every ingredient/category/constraint after decoding.
        // Gemini's JSON mode avoids provider-specific schema compiler failures.
        if (candidate.startsWith("google/")) payload.response_format = { type: "json_object" };
      }
      try {
        const remaining = fallbackDeadline - Date.now();
        if (remaining <= 0) break;
        const timeout = Math.min(remaining, candidate?.startsWith("google/") ? 30_000 : 45_000);
        const fallback = await callProvider(OPENROUTER_ENDPOINT, openRouterKey, payload, timeout);
        if (fallback.status < 400) {
          return completion(fallback.text, fallback.status, "openrouter", failure);
        }
        lastStatus = fallback.status;
        failure = `${fallback.status}:${classifyFailure(fallback.text)}`;
      } catch {
        failure = "network_or_timeout";
      }
    }
    return jsonResponse({ error: "AI providers unavailable", upstream_status: lastStatus }, 502);
  }
  return jsonResponse({
    error: "AI providers unavailable",
    upstream_status: primary?.status,
  }, 502);
}

// Only fixed classifications leave the server, never upstream messages or data.
function classifyFailure(text: string): string {
  let error: unknown;
  try { error = JSON.parse(text)?.error; } catch { return "invalid_response"; }
  const details = JSON.stringify(error ?? {}).toLowerCase();
  if (/credit|balance|payment/.test(details)) return "credits";
  if (/no endpoints|no provider|model.*not found|model.*not allowed/.test(details)) return "model_unavailable";
  if (/schema|response_format|responseformat/.test(details)) return "schema";
  if (/thinking|reasoning/.test(details)) return "reasoning";
  if (/rate.limit/.test(details)) return "rate_limit";
  if (/unauthorized|authentication|api.key/.test(details)) return "authentication";
  return "provider_error";
}

function completion(text: string, status: number, provider: string, failure?: string) {
  return new Response(text, {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json; charset=utf-8",
      "X-Savoria-AI-Provider": provider,
      ...(failure ? { "X-Savoria-AI-Fallback-Failure": failure } : {}),
    },
  });
}

if (import.meta.main) Deno.serve((request) => handleRequest(request));
