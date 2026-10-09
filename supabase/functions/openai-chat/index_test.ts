import { FALLBACK_MODELS, handleRequest } from "./index.ts";
const complete = { choices: [{ message: { content: '{"ok":true}' } }] };
const request = (
  body: unknown = {
    model: "gpt-4.1-mini",
    messages: [{ role: "user", content: "arroz" }],
  },
) =>
  new Request("https://example.test", {
    method: "POST",
    body: JSON.stringify(body),
  });
function assert(
  condition: unknown,
  message = "Assertion failed",
): asserts condition {
  if (!condition) throw Error(message);
}
function fixture(steps: (Response | Error)[], keys = true) {
  const calls: {
    url: string;
    body: Record<string, unknown>;
    authorization: string | null;
  }[] = [];
  return {
    calls,
    dependencies: {
      env: (name: string) =>
        keys
          ? ({
            OPENAI_API_KEY: "fake-openai",
            OPEN_ROUTER_KEY: "fake-router",
          } as Record<string, string>)[name]
          : undefined,
      fetch: (async (url: string | URL | Request, init?: RequestInit) => {
        calls.push({
          url: String(url),
          body: JSON.parse(String(init?.body)),
          authorization: new Headers(init?.headers).get("Authorization"),
        });
        const next = steps.shift();
        if (next instanceof Error) throw next;
        if (!next) throw Error("Unexpected extra request");
        return next;
      }) as typeof fetch,
    },
  };
}
Deno.test("OpenAI success never invokes OpenRouter", async () => {
  const f = fixture([Response.json(complete)]);
  const r = await handleRequest(request(), f.dependencies);
  assert(r.status === 200 && f.calls.length === 1);
  assert(r.headers.get("X-Savoria-AI-Provider") === "openai");
});
for (const status of [401, 403, 408, 429, 500, 503]) {
  Deno.test(`OpenAI ${status} invokes one bounded server fallback`, async () => {
    const f = fixture([
      Response.json({ error: "private-upstream-detail" }, { status }),
      Response.json(complete),
    ]);
    const r = await handleRequest(request(), f.dependencies);
    assert(r.status === 200 && f.calls.length === 2);
    assert(r.headers.get("X-Savoria-AI-Provider") === "openrouter");
    assert(f.calls[1].authorization === "Bearer fake-router");
    assert(
      JSON.stringify(f.calls[1].body.models) ===
        JSON.stringify(FALLBACK_MODELS),
    );
    assert(!("model" in f.calls[1].body));
  });
}
Deno.test("Network error falls back preserving image, tools and JSON schema", async () => {
  const messages = [{
    role: "user",
    content: [{
      type: "image_url",
      image_url: { url: "data:image/png;base64,AAA" },
    }],
  }];
  const tools = [{
    type: "function",
    function: { name: "lookup", parameters: { type: "object" } },
  }];
  const f = fixture([
    Error("network"),
    Response.json({
      choices: [{
        message: {
          tool_calls: [{
            id: "call",
            type: "function",
            function: { name: "lookup", arguments: "{}" },
          }],
        },
      }],
    }),
  ]);
  const r = await handleRequest(
    request({
      messages,
      tools,
      response_format: { type: "json_object" },
      max_tokens: 99999,
    }),
    f.dependencies,
  );
  assert(r.status === 200);
  assert(JSON.stringify(f.calls[1].body.messages) === JSON.stringify(messages));
  assert(JSON.stringify(f.calls[1].body.tools) === JSON.stringify(tools));
  assert(f.calls[1].body.max_tokens === 8192);
  assert(
    (f.calls[1].body.response_format as Record<string, string>).type ===
      "json_object",
  );
});
Deno.test("Invalid user request does not trigger a paid fallback", async () => {
  const f = fixture([Response.json({ error: "wrong input" }, { status: 400 })]);
  const r = await handleRequest(request(), f.dependencies);
  assert(r.status === 400 && f.calls.length === 1);
});
Deno.test("Empty 200 completion triggers fallback", async () => {
  const f = fixture([Response.json({ choices: [] }), Response.json(complete)]);
  const r = await handleRequest(request(), f.dependencies);
  assert(r.status === 200 && f.calls.length === 2);
});
Deno.test("Both providers fail: bounded calls, no secret or upstream body leak", async () => {
  const f = fixture([
    Response.json({ error: "fake-openai" }, { status: 500 }),
    Response.json({ error: "fake-router" }, { status: 401 }),
  ]);
  const r = await handleRequest(request(), f.dependencies);
  const t = await r.text();
  assert(r.status === 502 && f.calls.length === 2);
  assert(!t.includes("fake-"));
});
Deno.test("Missing OpenAI key allows existing OpenRouter secret", async () => {
  const f = fixture([Response.json(complete)]);
  f.dependencies.env = (n) =>
    n === "OPEN_ROUTER_KEY" ? "fake-router" : undefined;
  const r = await handleRequest(request(), f.dependencies);
  assert(r.status === 200 && f.calls.length === 1);
  assert(f.calls[0].url.includes("openrouter.ai"));
});
Deno.test("Reject arbitrary model, non-object, tools and oversize payload without calls", async () => {
  for (
    const body of [
      [],
      { model: "expensive-model", messages: [{}] },
      { messages: [] },
      { messages: [{}], tools: "invalid" },
      { messages: [{ content: "a".repeat(8_000_001) }] },
    ]
  ) {
    const f = fixture([]);
    const r = await handleRequest(request(body), f.dependencies);
    assert(r.status >= 400 && f.calls.length === 0);
  }
});
