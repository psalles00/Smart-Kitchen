import {
  FALLBACK_MODELS,
  handleRequest,
  RECIPE_IDEA_FALLBACK_MODELS,
} from "./index.ts";
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
Deno.test("Recipe ideas explicitly try Gemini before any secondary model", async () => {
  const format = {
    type: "json_schema",
    json_schema: {
      name: "recipe_ideas",
      strict: true,
      schema: { type: "object" },
    },
  };
  const f = fixture([
    Response.json({ error: "balance unavailable" }, { status: 429 }),
    Response.json(complete),
  ]);
  const r = await handleRequest(
    request({
      model: "gpt-4.1-mini",
      messages: [{ role: "user", content: "o que fazer no cafe da manha" }],
      response_format: format,
      max_tokens: 4096,
    }),
    f.dependencies,
  );
  assert(r.status === 200 && f.calls.length === 2);
  assert(
    f.calls[1].body.model === RECIPE_IDEA_FALLBACK_MODELS[0] &&
      f.calls[1].body.models === undefined,
  );
  assert(
    JSON.stringify(f.calls[1].body.response_format) === JSON.stringify({type: "json_object"}),
  );
  assert(f.calls[1].body.max_tokens === 4096);
  assert(JSON.stringify(f.calls[1].body.reasoning) ===
    JSON.stringify({ effort: "low", exclude: true }));
});
Deno.test("Recipe primary success still skips every fallback", async () => {
  const f = fixture([Response.json(complete)]);
  const r = await handleRequest(
    request({
      messages: [{ role: "user", content: "cafe da manha" }],
      response_format: {
        type: "json_schema",
        json_schema: { name: "recipe_ideas" },
      },
    }),
    f.dependencies,
  );
  assert(r.status === 200 && f.calls.length === 1);
});
Deno.test("Secondary recipe schema keeps pantry and category constraints", async () => {
  const ingredient = { type: "string", enum: ["Ovos", "Banana"] };
  const reference = { $ref: "#/$defs/ingredientName" };
  const format = {
    type: "json_schema",
    json_schema: {
      name: "recipe_ideas",
      strict: true,
      schema: {
        type: "object",
        $defs: { ingredientName: ingredient },
        properties: {
          ideas: {
            type: "array",
            maxItems: 18,
            items: {
              type: "object",
              required: [
                "mainIngredient",
                "ingredients",
                "requiresPrecooked",
                "category",
              ],
              properties: {
                mainIngredient: reference,
                ingredients: { type: "array", minItems: 2, items: reference },
                requiresPrecooked: { type: "array", items: reference },
                category: {
                  type: "string",
                  enum: ["quick", "unique", "pantry"],
                },
              },
            },
          },
        },
      },
    },
  };
  const original = JSON.stringify(format);
  const f = fixture([
    Response.json({}, { status: 429 }),
    Response.json({error:"schema"}, {status:400}),
    Response.json(complete),
  ]);
  const r = await handleRequest(
    request({
      messages: [{ role: "user", content: "breakfast" }],
      response_format: format,
    }),
    f.dependencies,
  );
  assert(r.status === 200 && f.calls.length === 3);
  assert(
    JSON.stringify(f.calls[0].body.response_format) === original,
    "OpenAI schema remains untouched",
  );
  const routed = f.calls[2].body.response_format as typeof format;
  const fields = routed.json_schema.schema.properties.ideas.items.properties;
  assert(JSON.stringify(fields.mainIngredient) === JSON.stringify(ingredient));
  assert(
    JSON.stringify(fields.ingredients.items) === JSON.stringify(ingredient),
  );
  assert(
    JSON.stringify(fields.requiresPrecooked.items) ===
      JSON.stringify(ingredient),
  );
  assert(
    JSON.stringify(fields.category) ===
      JSON.stringify(
        format.json_schema.schema.properties.ideas.items.properties.category,
      ),
  );
  assert(fields.ingredients.minItems === 2);
  assert(!JSON.stringify(routed).includes('"$ref"'));
  assert(!JSON.stringify(routed).includes('"$defs"'));
  assert(
    JSON.stringify(format) === original,
    "Caller data must not be mutated",
  );
});
for (
  const format of [undefined, { type: "json_object" }, {
    type: "json_schema",
    json_schema: { name: "nutrition" },
  }, { type: "json_schema", json_schema: "recipe_ideas" }]
) {
  Deno.test(`Other formats keep the default routing: ${JSON.stringify(format)}`, async () => {
    const f = fixture([
      Response.json({}, { status: 503 }),
      Response.json(complete),
    ]);
    const r = await handleRequest(
      request({
        messages: [{ role: "user", content: "recipe_ideas" }],
        response_format: format,
      }),
      f.dependencies,
    );
    assert(r.status === 200 && f.calls.length === 2);
    assert(
      JSON.stringify(f.calls[1].body.models) ===
        JSON.stringify(FALLBACK_MODELS),
    );
  });
}
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

Deno.test("Recipe Gemini failure tries Qwen once and exposes only fixed classification", async () => {
  const f = fixture([
    Response.json({error:"credits"}, {status:429}),
    Response.json({error:{message:"Invalid response_schema: private prompt and fake-secret"}}, {status:400}),
    Response.json(complete),
  ]);
  const r = await handleRequest(request({messages:[{role:"user",content:"breakfast"}],response_format:{type:"json_schema",json_schema:{name:"recipe_ideas"}}}),f.dependencies);
  assert(r.status===200 && f.calls.length===3);
  assert(f.calls[1].body.model===RECIPE_IDEA_FALLBACK_MODELS[0]);
  assert(f.calls[2].body.model===RECIPE_IDEA_FALLBACK_MODELS[1]);
  assert(JSON.stringify(f.calls[2].body.reasoning)===JSON.stringify({enabled:false}));
  assert(r.headers.get("X-Savoria-AI-Fallback-Failure")==="400:schema");
  assert(!(await r.text()).includes("private prompt"));
});
Deno.test("Both explicit recipe models fail without retry loops or upstream leakage", async () => {
  const f = fixture([Response.json({error:"credit"},{status:429}),new Error("offline"),Response.json({error:"secret"},{status:503})]);
  const r=await handleRequest(request({messages:[{role:"user",content:"breakfast"}],response_format:{type:"json_schema",json_schema:{name:"recipe_ideas"}}}),f.dependencies);
  assert(r.status===502 && f.calls.length===3);
  assert(!(await r.text()).includes("secret"));
});
