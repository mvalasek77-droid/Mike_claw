const schema = {
  type: "object",
  additionalProperties: false,
  properties: {
    headline: { type: "string" },
    translation: { type: "string" },
    psychology: { type: "string" },
    receipts: { type: "array", items: { type: "string" }, minItems: 1, maxItems: 6 },
    suggestedReplies: { type: "array", items: { type: "string" }, minItems: 1, maxItems: 4 },
    realityScore: { type: "integer", minimum: 0, maximum: 100 },
    energy: { type: "string" },
    flags: { type: "array", items: { type: "string" }, maxItems: 5 }
  },
  required: ["headline", "translation", "psychology", "receipts", "suggestedReplies", "realityScore", "energy", "flags"]
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Allow-Methods": "POST, OPTIONS"
};

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return new Response(null, { headers: corsHeaders });
    }
    if (request.method !== "POST") {
      return json({ error: "POST /decode only" }, 405);
    }
    if (!env.OPENAI_API_KEY) {
      return json({ error: "OPENAI_API_KEY is not configured" }, 500);
    }

    let payload;
    try {
      payload = await request.json();
    } catch {
      return json({ error: "Invalid JSON" }, 400);
    }

    const text = String(payload.text || "").trim().slice(0, 6000);
    const tone = String(payload.tone || "group-chat funny");
    const context = String(payload.context || "dating");
    if (!text) {
      return json({ error: "text is required" }, 400);
    }

    const response = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${env.OPENAI_API_KEY}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        model: env.OPENAI_MODEL || "gpt-5.4-mini",
        instructions: [
          "You are ChadDrop, a fun and sharp text decoder for women figuring out what a guy really means.",
          "Use psychology, dating dynamics, and the dating marketplace to reveal the truth behind his words.",
          "Be playful, witty, and honest — like your smartest friend giving you the real read.",
          "Do not claim certainty, diagnose people, or present therapy/legal advice.",
          "A little crude is okay; sexual explicitness, cruelty, slurs, and protected-class insults are not.",
          "If the text suggests threats, coercion, abuse, stalking, or self-harm, drop the comedy and prioritize safety.",
          "Return only JSON matching the schema."
        ].join(" "),
        input: [
          {
            role: "user",
            content: JSON.stringify({ text, tone, context })
          }
        ],
        text: {
          format: {
            type: "json_schema",
            name: "decode_result",
            strict: true,
            schema
          }
        }
      })
    });

    if (!response.ok) {
      const body = await response.text();
      return json({ error: "OpenAI request failed", detail: body.slice(0, 1000) }, response.status);
    }

    const data = await response.json();
    const output = data.output_text || extractOutputText(data);
    if (!output) {
      return json({ error: "No model output" }, 502);
    }

    return new Response(output, {
      headers: { ...corsHeaders, "Content-Type": "application/json" }
    });
  }
};

function extractOutputText(data) {
  const chunks = [];
  for (const item of data.output || []) {
    for (const content of item.content || []) {
      if (content.type === "output_text" && content.text) {
        chunks.push(content.text);
      }
    }
  }
  return chunks.join("");
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" }
  });
}
