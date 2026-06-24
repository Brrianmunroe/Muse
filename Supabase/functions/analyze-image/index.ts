// Supabase Edge Function: analyze-image
//
// Receives a base64 image from the Muse app and asks Claude (Haiku 4.5, vision)
// for a short design-language description plus a few design-term tags. The
// Anthropic API key lives here as a Supabase secret and never ships in the app.
//
//   supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
//   supabase functions deploy analyze-image

const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY");

// Controlled vocabulary the model must classify each image into. MUST stay in
// sync with Muse/Models/Taxonomy.swift — filtering relies on the model only
// ever emitting these exact values.
const TAXONOMY = {
  discipline: ["architecture", "typography", "motion", "product", "graphic",
               "fashion", "interior", "photography", "illustration"],
  color: ["warm", "cool", "muted", "vibrant", "monochrome", "pastel", "earthy"],
  mood: ["calm", "energetic", "playful", "serious", "elegant", "raw"],
  style: ["minimal", "maximal", "retro", "modern", "editorial", "organic", "geometric"],
} as const;

const SYSTEM_PROMPT =
  "You are a design-vocabulary expert helping someone broaden their design " +
  "vocabulary. Describe the image in 150-200 characters using precise, " +
  "evocative design terminology — typography, color, composition, materiality, " +
  "mood, and era/movement — so the reader learns the terms to describe what " +
  "they're seeing. Be specific and avoid generic filler. Also provide 3-5 " +
  "short design-term tags (1-3 words each, lowercase).\n\n" +
  "Additionally, classify the image into the provided facet categories " +
  "(discipline, color, mood, style). For each category choose ONLY from its " +
  "allowed values — the 1-2 that fit best, or none if genuinely uncertain. " +
  "Never invent values.";

// Each facet is an enum-constrained array — the schema is the real guardrail.
const FACETS_SCHEMA = {
  type: "object",
  properties: Object.fromEntries(
    Object.entries(TAXONOMY).map(([cat, vals]) => [
      cat,
      { type: "array", items: { type: "string", enum: vals } },
    ]),
  ),
  required: Object.keys(TAXONOMY),
  additionalProperties: false,
};

const RESPONSE_SCHEMA = {
  type: "object",
  properties: {
    description: { type: "string" },
    tags: { type: "array", items: { type: "string" } },
    facets: FACETS_SCHEMA,
  },
  required: ["description", "tags", "facets"],
  additionalProperties: false,
};

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "content-type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  if (!ANTHROPIC_API_KEY) {
    return json({ error: "ANTHROPIC_API_KEY not configured" }, 500);
  }

  let image_base64: string;
  let media_type: string;
  try {
    const body = await req.json();
    image_base64 = body.image_base64;
    media_type = body.media_type ?? "image/jpeg";
    if (!image_base64) throw new Error("missing image_base64");
  } catch {
    return json({ error: "invalid request body" }, 400);
  }

  const anthropicResponse = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: "claude-haiku-4-5",
      max_tokens: 400,
      system: SYSTEM_PROMPT,
      output_config: {
        format: { type: "json_schema", schema: RESPONSE_SCHEMA },
      },
      messages: [
        {
          role: "user",
          content: [
            {
              type: "image",
              source: { type: "base64", media_type, data: image_base64 },
            },
            { type: "text", text: "Describe this design inspiration image." },
          ],
        },
      ],
    }),
  });

  if (!anthropicResponse.ok) {
    const detail = await anthropicResponse.text();
    return json({ error: "anthropic request failed", detail }, 502);
  }

  const data = await anthropicResponse.json();
  const text = data?.content?.find((b: { type: string }) => b.type === "text")?.text;
  if (!text) return json({ error: "no content returned" }, 502);

  let parsed: {
    description: string;
    tags: string[];
    facets: Record<string, string[]>;
  };
  try {
    parsed = JSON.parse(text);
  } catch {
    return json({ error: "could not parse model output", raw: text }, 502);
  }

  return json({
    description: parsed.description,
    tags: parsed.tags ?? [],
    facets: parsed.facets ?? {},
  });
});
