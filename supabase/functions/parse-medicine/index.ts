// Structures raw OCR label text + a spoken dosage/schedule transcript into a
// medicine reminder via Claude. Runs server-side so the Anthropic key never
// ships in the app. Called by the Flutter review screen; nothing here is
// persisted — the client shows the result for the user to edit and confirm.

const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY");
const ANTHROPIC_MODEL = "claude-haiku-4-5";
const REQUEST_TIMEOUT_MS = 10_000;

const EXTRACT_TOOL = {
  name: "extract_medicine_schedule",
  description:
    "Structured medicine reminder extracted from a label photo's OCR text and a spoken description of dosage/schedule.",
  input_schema: {
    type: "object",
    properties: {
      drugName: { type: "string", description: "Best-guess name of the medicine." },
      strength: { type: "string", description: "e.g. '500mg', '10ml'. Empty string if unknown." },
      form: { type: "string", description: "e.g. tablet, capsule, syrup, injection. Empty string if unknown." },
      doseAmount: { type: "string", description: "Amount taken per dose, e.g. '1 tablet', '2 puffs'." },
      frequencyType: {
        type: "string",
        enum: ["daily", "specific_days", "every_x_hours", "as_needed"],
        description: "How the schedule repeats.",
      },
      times: {
        type: "array",
        items: { type: "string", pattern: "^[0-2][0-9]:[0-5][0-9]$" },
        description: "24h HH:mm times of day to take the dose, best-effort inferred from the transcript.",
      },
      daysOfWeek: {
        type: "array",
        items: { type: "integer", minimum: 0, maximum: 6 },
        description: "0=Sunday..6=Saturday. Only set when frequencyType is 'specific_days'.",
      },
      notes: { type: "string", description: "Any other relevant instructions, e.g. 'take with food'." },
      confidence: {
        type: "number",
        minimum: 0,
        maximum: 1,
        description: "Your confidence that this extraction is correct and complete.",
      },
    },
    required: ["drugName", "doseAmount", "frequencyType", "times", "confidence"],
  },
};

const SYSTEM_PROMPT = `You extract a structured medicine reminder from two noisy inputs: OCR'd text from a photographed medicine label, and a transcript of the user speaking their dosage/schedule out loud. The label OCR may contain unrelated packaging text, misreads, or line breaks mid-word. The transcript may be casual speech ("twice a day, morning and night" or "every 8 hours"). Infer clock times where possible (e.g. "twice daily" without more detail -> ["09:00","21:00"]; "every 8 hours" -> ["06:00","14:00","22:00"]). Prefer the transcript for dosage/frequency and the label for the drug name/strength/form when both are present. If something is genuinely unknown, use an empty string (or empty array) rather than guessing wildly, and lower your confidence score accordingly. Always call the extract_medicine_schedule tool exactly once with your best extraction.`;

interface ParseRequest {
  ocrText?: string;
  transcript?: string;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return jsonResponse({ success: false, data: null, error: "method_not_allowed" }, 405);
  }
  if (!ANTHROPIC_API_KEY) {
    return jsonResponse({ success: false, data: null, error: "server_misconfigured" }, 500);
  }

  let body: ParseRequest;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ success: false, data: null, error: "invalid_json_body" }, 400);
  }

  const ocrText = (body.ocrText ?? "").trim();
  const transcript = (body.transcript ?? "").trim();
  if (!ocrText && !transcript) {
    return jsonResponse({ success: false, data: null, error: "empty_input" }, 400);
  }

  const userMessage = [
    ocrText ? `LABEL OCR TEXT:\n${ocrText}` : "LABEL OCR TEXT: (none captured)",
    transcript ? `SPOKEN TRANSCRIPT:\n${transcript}` : "SPOKEN TRANSCRIPT: (none captured)",
  ].join("\n\n");

  const attempt = async () => callClaude(userMessage);

  let result;
  try {
    result = await withTimeout(attempt(), REQUEST_TIMEOUT_MS);
  } catch (_err) {
    try {
      result = await withTimeout(attempt(), REQUEST_TIMEOUT_MS);
    } catch (err) {
      return jsonResponse({ success: false, data: null, error: `upstream_failed: ${String(err)}` }, 502);
    }
  }

  if (!result.ok) {
    return jsonResponse({ success: false, data: null, error: result.error }, result.status ?? 502);
  }

  return jsonResponse({ success: true, data: result.data, error: null });
});

async function callClaude(
  userMessage: string,
): Promise<{ ok: true; data: unknown } | { ok: false; error: string; status?: number }> {
  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": ANTHROPIC_API_KEY!,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: ANTHROPIC_MODEL,
      max_tokens: 1024,
      system: SYSTEM_PROMPT,
      tools: [EXTRACT_TOOL],
      tool_choice: { type: "tool", name: EXTRACT_TOOL.name },
      messages: [{ role: "user", content: userMessage }],
    }),
  });

  if (res.status === 429 || res.status >= 500) {
    return { ok: false, error: `retryable_status_${res.status}`, status: res.status };
  }
  if (!res.ok) {
    const text = await res.text().catch(() => "");
    return { ok: false, error: `anthropic_error_${res.status}: ${text.slice(0, 300)}`, status: 502 };
  }

  const payload = await res.json();
  const toolUse = (payload.content ?? []).find((block: { type: string }) => block.type === "tool_use");
  if (!toolUse) {
    return { ok: false, error: "no_tool_use_in_response" };
  }
  return { ok: true, data: toolUse.input };
}

function withTimeout<T>(promise: Promise<T>, ms: number): Promise<T> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("timeout")), ms);
    promise.then((v) => {
      clearTimeout(timer);
      resolve(v);
    }, (e) => {
      clearTimeout(timer);
      reject(e);
    });
  });
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}
