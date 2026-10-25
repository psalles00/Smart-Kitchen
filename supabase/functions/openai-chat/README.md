# Savoria chat gateway

Project: `yfcmvdijvgeaihvwyssb` (KitchenApp). Keep provider credentials in Supabase Edge Function secrets, never in the shipped app.

- Primary: existing `OPENAI_API_KEY`, requested allowlisted `gpt-4.1-mini` / `gpt-4o-mini`.
- Fallback secret: `OPEN_ROUTER_KEY`.
- OpenRouter order: `qwen/qwen3.5-flash-02-23`, then `google/gemini-3.1-flash-lite`.
- HTTP 401/403/408/429/5xx, timeout, network failure, malformed/empty completion trigger fallback. Invalid request/model errors do not.
- Ordinary requests use one OpenAI attempt and one OpenRouter request, each with a 45-second timeout. Recipe discovery uses the bounded profile below. Output is capped at 8192 tokens, default 4096. No arbitrary model or caller-controlled fallback switch.
- Messages and tools are preserved; response formats follow the recipe compatibility profile below when applicable. Provider choice is returned in `X-Savoria-AI-Provider`; actual model is in the completion body. Provider errors and secrets are not forwarded.
- Audio transcription still uses the separate `openai-transcription` function. Chat/vision fallback does not provide transcription failover.

### Recipe discovery profile — 2026-10-25

Only `response_format.type = json_schema` with schema name `recipe_ideas` uses
explicit Gemini-first, Qwen-second fallback. OpenAI remains primary. Ordinary
chat, tools, nutrition and vision retain the existing single router request.
Each recipe model is attempted at most once, within one shared 45-second
fallback deadline (Gemini up to 30 seconds; Qwen gets remaining time). Thus the
existing primary+fallback wait budget stays approximately 90 seconds. Recipe
requests can use three upstream HTTP attempts instead of two; failed inference
may be charged and is reserved conservatively in the test ledger.

Gemini uses JSON object mode with low reasoning effort and excluded reasoning
text. Its structured schema request returned HTTP 400 in real tests; the same
request in JSON mode succeeded. The app still checks every ingredient, category,
time, portion and original restriction before displaying ideas. OpenAI gets the
original strict schema. Qwen gets an equivalent schema with the app's three
ingredient references inlined, preserving ingredient enums and constraints.
Missing categories remain rejected, and only one existing content repair is
allowed. Valid short answers do not trigger refill calls.

`X-Savoria-AI-Fallback-Failure`, when present after a successful secondary attempt,
contains only an HTTP status and fixed failure classification. Never return raw
provider errors, messages, prompts or credentials. This is operational diagnosis,
not a caller-controlled model switch or entitlement check.

Official prices checked 2026-10-25: Gemini input/output $0.25/$1.50 per million
tokens versus Qwen $0.065/$0.26. At 6,000 input/2,500 total output tokens this is
$0.00525 versus $0.00104 per successful inference, excluding failed attempts,
gateway/egress, web search and credit-purchase fees. Reasoning tokens count toward
output and the unchanged 4,096-token app cap. No service or paid plan was added.
Pedro authorized an accumulated test ceiling of $5; this temporary test guard is
not a production financial limit. Full proportional costs and E2E evidence are in
[`docs/testing-assistant-variety.md`](../../../docs/testing-assistant-variety.md).

## Validation

Run `deno test supabase/functions/openai-chat/index_test.ts`. These tests inject fetch/secrets and make no network calls.

On 2026-10-09, the existing OpenAI account returned 429 credit_balance_exhausted. After deployment, two real calls succeeded through the server: Qwen returned text; Gemini returned valid function arguments (`registrar`, banana, 100 grams). These probes did not save food entries.

Reference pricing per million input/output tokens observed on that date: Qwen $0.065/$0.26, Gemini $0.25/$1.50. Prices can change. Consult https://openrouter.ai/api/v1/models and https://openrouter.ai/docs/guides/routing/model-fallbacks.

## Existing authentication limitation

The deployed legacy JWT verification remains enabled. The current app authenticates this gateway with the project's public anon key, so this is not a per-user entitlement or durable usage enforcement mechanism. Keeping secrets server-side prevents distributing provider keys, but production abuse protection still needs verified user/app identity and server-enforced quotas. This change does not disable JWT verification or alter database schemas/policies.

## Deployment and CLI access

Supabase CLI 2.122.0 was authenticated through the authorized Safari Savoria
profile, and `projects list` verified **KitchenApp / yfcmvdijvgeaihvwyssb**. The
repository is already linked to this ref. Six exact never-used legacy CLI tokens
were revoked with Pedro's explicit approval to satisfy the account's token cap;
the used VS Code token and other credentials were preserved. Provider secrets
were neither retrieved nor changed.

```sh
supabase --agent no projects list --output json
supabase --agent no functions list --project-ref yfcmvdijvgeaihvwyssb --output json
supabase --agent no functions deploy openai-chat --project-ref yfcmvdijvgeaihvwyssb --use-api
# Download into a separate task evidence directory; never overwrite local edits.
supabase --agent no functions download openai-chat --project-ref yfcmvdijvgeaihvwyssb --use-api --workdir /absolute/task/readback
```

`--use-api` bundles server-side without Docker. Name the single function explicitly;
do not use `--prune` or `--no-verify-jwt`. Preserve and verify the currently deployed
source before future edits, compare downloaded source bytes after publishing, and
confirm function metadata still reports `verify_jwt: true`. Keys remain in Secrets,
never logs or source. Routine future deployments use the saved CLI login; a browser
is needed only if that authentication expires or is revoked.
