// ai-proxy
//
// Loop's AI backend proxy. The client sends ALREADY-REDACTED text (PII replaced
// with placeholders like [[PERSON_1]] on-device), so this function — and the LLM
// vendor it calls — never sees identifiable data. The provider API key lives only
// here as an environment secret, never in the app.
//
// When no provider key is configured (e.g. local development) the function
// returns a deterministic response so the end-to-end flow works without a vendor.
//
// JWT verification is enabled by default, so only authenticated users can call it.

interface RequestBody {
  action: "summarize" | "extract" | "draft" | "parseCard";
  text: string;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  let body: RequestBody;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const { action, text } = body;
  if (!action || typeof text !== "string") {
    return json({ error: "Missing action or text" }, 400);
  }

  const apiKey = Deno.env.get("AI_PROVIDER_API_KEY");

  try {
    const result = apiKey
      ? await callProvider(action, text, apiKey)
      : mockResult(action, text);
    return json({ result });
  } catch (_error) {
    return json({ error: "AI provider error" }, 502);
  }
});

function prompt(action: string): string {
  switch (action) {
    case "summarize":
      return "Summarize these networking conversation notes in 2-3 sentences. Preserve any placeholder tokens like [[PERSON_1]] exactly.";
    case "extract":
      return "Extract concrete next-step action items from these notes as a newline-separated list. Preserve placeholder tokens exactly.";
    case "draft":
      return "Draft a short, warm follow-up message based on these notes. Preserve placeholder tokens exactly.";
    case "parseCard":
      return "From this business card text, return name, title, company, email, and phone as labeled lines.";
    default:
      return "Assist with the following text.";
  }
}

// Calls a zero-retention / no-training chat completions endpoint. Configure
// AI_PROVIDER_URL + AI_PROVIDER_MODEL to match your provider (Bedrock, Azure
// OpenAI, etc.). The endpoint must be contracted for no retention and no training.
async function callProvider(action: string, text: string, apiKey: string): Promise<string> {
  const url = Deno.env.get("AI_PROVIDER_URL") ?? "https://api.openai.com/v1/chat/completions";
  const model = Deno.env.get("AI_PROVIDER_MODEL") ?? "gpt-4o-mini";

  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model,
      messages: [
        { role: "system", content: prompt(action) },
        { role: "user", content: text },
      ],
      temperature: 0.4,
    }),
  });

  if (!response.ok) throw new Error(`provider ${response.status}`);
  const data = await response.json();
  return data.choices?.[0]?.message?.content ?? "";
}

// Deterministic offline/local response that echoes placeholders so the app's
// rehydration step can be exercised end-to-end.
function mockResult(action: string, text: string): string {
  const firstLine = text.split("\n").map((l) => l.trim()).find((l) => l.length > 0) ?? "";
  switch (action) {
    case "summarize":
      return `Summary: ${truncate(text, 180)}`;
    case "extract":
      return ["Send a thank-you note", "Schedule a follow-up", "Share the promised resource"].join("\n");
    case "draft":
      return `Hi,\n\nGreat chatting earlier. ${truncate(firstLine, 120)} Would love to continue the conversation — let me know a good time.\n\nThanks!`;
    case "parseCard":
      return text;
    default:
      return text;
  }
}

function truncate(text: string, max: number): string {
  return text.length > max ? text.slice(0, max) + "…" : text;
}

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
