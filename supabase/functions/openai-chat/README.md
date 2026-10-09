# Savoria chat gateway

Project: `yfcmvdijvgeaihvwyssb` (KitchenApp). Keep provider credentials in Supabase Edge Function secrets, never in the shipped app.

- Primary: existing `OPENAI_API_KEY`, requested allowlisted `gpt-4.1-mini` / `gpt-4o-mini`.
- Fallback secret: `OPEN_ROUTER_KEY`.
- OpenRouter order: `qwen/qwen3.5-flash-02-23`, then `google/gemini-3.1-flash-lite`.
- HTTP 401/403/408/429/5xx, timeout, network failure, malformed/empty completion trigger fallback. Invalid request/model errors do not.
- One OpenAI attempt and one OpenRouter request, each with a 45-second timeout. OpenRouter routes between the two fallback models. Output is capped at 8192 tokens, default 4096. No arbitrary model or caller-controlled fallback switch.
- Messages, tools and response formats are preserved. Provider choice is returned in `X-Savoria-AI-Provider`; actual model is in the completion body. Provider errors and secrets are not forwarded.
- Audio transcription still uses the separate `openai-transcription` function. Chat/vision fallback does not provide transcription failover.

## Validation

Run `deno test supabase/functions/openai-chat/index_test.ts`. These tests inject fetch/secrets and make no network calls.

On 2026-10-09, the existing OpenAI account returned 429 credit_balance_exhausted. After deployment, two real calls succeeded through the server: Qwen returned text; Gemini returned valid function arguments (`registrar`, banana, 100 grams). These probes did not save food entries.

Reference pricing per million input/output tokens observed on that date: Qwen $0.065/$0.26, Gemini $0.25/$1.50. Prices can change. Consult https://openrouter.ai/api/v1/models and https://openrouter.ai/docs/guides/routing/model-fallbacks.

## Existing authentication limitation

The deployed legacy JWT verification remains enabled. The current app authenticates this gateway with the project's public anon key, so this is not a per-user entitlement or durable usage enforcement mechanism. Keeping secrets server-side prevents distributing provider keys, but production abuse protection still needs verified user/app identity and server-enforced quotas. This change does not disable JWT verification or alter database schemas/policies.

## Deployment

The active production function was updated through the authenticated Supabase dashboard. This source is the matching reviewable implementation. Do not run a local Supabase/Docker stack or disable gateway authentication to deploy. Preserve a copy of the currently deployed code before future changes. Remote API keys must stay in Secrets and must not be copied into logs or this repository.
