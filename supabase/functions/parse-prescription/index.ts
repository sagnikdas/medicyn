// Structures raw OCR text from a scanned or PDF-uploaded prescription into a
// list of medicines and a list of scheduled care items (tests, scans,
// therapy/counselling, follow-up appointments) via Claude. Runs server-side
// so the Anthropic key never ships in the app. Called by the Flutter
// prescription review screen; nothing here is persisted -- the client shows
// every detected item for the user to edit, include/exclude, and confirm.
//
// Deliberately a sibling of parse-medicine, not a change to it: that
// function is proven and used by two existing single-item flows, and this
// one's contract (a list, not one flat object; a longer, more expensive
// call; a different quota) is different enough that sharing code paths
// would risk both.

import { verifyCaller } from "./caller.ts";
import { sanitiseExtraction } from "./extraction.ts";
import { consumeParsePrescriptionQuota } from "./quota.ts";

const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY");
const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const ANTHROPIC_MODEL = "claude-haiku-4-5";
const REQUEST_TIMEOUT_MS = 20_000;
// A multi-page document is legitimately longer than one label; the OCR text
// still goes straight into a billed model call, so it stays capped rather
// than trusted.
const MAX_FIELD_CHARS = 16_000;
const MAX_ATTEMPTS = 2;

type ClaudeResult =
  | { ok: true; data: unknown }
  | { ok: false; error: string; status?: number };

const MEDICINE_SCHEMA = {
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
      description: "24h HH:mm times of day to take the dose, best-effort inferred from the document.",
    },
    daysOfWeek: {
      type: "array",
      items: { type: "integer", minimum: 0, maximum: 6 },
      description: "0=Sunday..6=Saturday. Only set when frequencyType is 'specific_days'.",
    },
    intervalHours: {
      type: "integer",
      minimum: 1,
      maximum: 24,
      description:
        "Hours between doses. Only set when frequencyType is 'every_x_hours'; times[0] is then the first dose of the day.",
    },
    notes: { type: "string", description: "Any other relevant instructions, e.g. 'take with food'." },
    confidence: {
      type: "number",
      minimum: 0,
      maximum: 1,
      description: "Your confidence that this one medicine's extraction is correct and complete.",
    },
  },
  required: ["drugName", "doseAmount", "frequencyType", "times", "confidence"],
};

const CARE_ITEM_SCHEMA = {
  type: "object",
  properties: {
    title: { type: "string", description: "Short name, e.g. 'Fasting blood glucose', 'MRI brain', 'Physiotherapy'." },
    kind: {
      type: "string",
      enum: ["test", "scan", "therapy", "appointment", "other"],
      description: "test = lab/blood work. scan = imaging. therapy = physio/counselling/rehab sessions. appointment = a follow-up visit. other = anything else actionable.",
    },
    notes: { type: "string", description: "Any other relevant instructions or context." },
    firstDate: {
      type: "string",
      description:
        "ISO YYYY-MM-DD for when this is first due, if a date is stated or inferable relative to the document's own date. Empty string if not statable.",
    },
    recurrence: {
      type: "string",
      enum: ["none", "weekly", "every_n_days", "every_n_months"],
      description: "'none' for a single one-off item.",
    },
    intervalN: {
      type: "integer",
      minimum: 1,
      maximum: 365,
      description: "Only meaningful for 'every_n_days' or 'every_n_months' -- the N.",
    },
    occurrenceCount: {
      type: "integer",
      minimum: 1,
      maximum: 52,
      description: "Total reminders to generate, including the first -- e.g. 'once a week, 6 sessions' = 6. 1 for a one-off item.",
    },
    confidence: {
      type: "number",
      minimum: 0,
      maximum: 1,
      description: "Your confidence that this one care item's extraction is correct and complete.",
    },
  },
  required: ["title", "kind", "recurrence", "occurrenceCount", "confidence"],
};

const EXTRACT_TOOL = {
  name: "extract_prescription",
  description:
    "Every medicine and every scheduled care action (a specific test, imaging/scan, therapy/counselling series, or follow-up appointment) extracted from OCR'd prescription or discharge-document text, possibly spanning multiple pages.",
  input_schema: {
    type: "object",
    properties: {
      medicines: { type: "array", items: MEDICINE_SCHEMA },
      careItems: { type: "array", items: CARE_ITEM_SCHEMA },
    },
    required: ["medicines", "careItems"],
  },
};

const SYSTEM_PROMPT = `You extract a structured list of medicines and a structured list of scheduled care actions from OCR'd text of a prescription or discharge document, which may span multiple pages marked "PAGE n OF m". The OCR may contain unrelated letterhead text, misreads, or line breaks mid-word.

For every medicine mentioned, add one entry to "medicines" with its own dosage/schedule -- there is often more than one. Infer clock times where possible (e.g. "twice daily" without more detail -> ["09:00","21:00"]; "every 8 hours" -> ["06:00","14:00","22:00"]).

For every distinct actionable scheduled instruction that is NOT a medicine -- a specific lab test, imaging/scan, a therapy or counselling series, or a follow-up appointment -- add one entry to "careItems". If the instruction repeats (e.g. "physiotherapy once a week for 6 sessions" or "repeat this scan in 3 months"), describe that with "recurrence"/"intervalN"/"occurrenceCount" rather than listing each occurrence separately. A one-off item gets recurrence "none" and occurrenceCount 1.

Do not invent an entry for something that is not an actionable instruction: ignore letterhead, a diagnosis stated without a scheduled action attached, and general advice with no date or repeat pattern. If something is genuinely unclear, use an empty string (or the "other"/"none" default) rather than guessing wildly, and lower your confidence score accordingly. Always call the extract_prescription tool exactly once with your best extraction, even if one of the two lists is empty.`;

interface ParseRequest {
  ocrText?: string;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return jsonResponse({ success: false, data: null, error: "method_not_allowed" }, 405);
  }
  if (!ANTHROPIC_API_KEY || !SUPABASE_URL || !SERVICE_ROLE_KEY) {
    return jsonResponse({ success: false, data: null, error: "server_misconfigured" }, 500);
  }

  // Before anything that costs money. The gateway's `verify_jwt` is satisfied
  // by the publishable key, which ships in the app, so it does not establish
  // that a *user* is calling -- see caller.ts.
  const caller = await verifyCaller(req.headers.get("Authorization"), {
    supabaseUrl: SUPABASE_URL,
    serviceRoleKey: SERVICE_ROLE_KEY,
  });
  if (!caller.ok) {
    return jsonResponse({ success: false, data: null, error: caller.error }, caller.status);
  }

  // After identity, before anything that costs money. See quota.ts for why
  // this cap is tighter than parse-medicine's.
  const quota = await consumeParsePrescriptionQuota(caller.userId, {
    supabaseUrl: SUPABASE_URL,
    serviceRoleKey: SERVICE_ROLE_KEY,
  });
  if (!quota.ok) {
    return jsonResponse({ success: false, data: null, error: quota.error }, quota.status);
  }

  let body: ParseRequest;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ success: false, data: null, error: "invalid_json_body" }, 400);
  }

  const ocrText = (body.ocrText ?? "").trim().slice(0, MAX_FIELD_CHARS);
  if (!ocrText) {
    return jsonResponse({ success: false, data: null, error: "empty_input" }, 400);
  }

  const userMessage = `PRESCRIPTION OCR TEXT:\n${ocrText}`;

  // Two attempts. A thrown error (timeout, connection reset) and a 429/5xx
  // from Anthropic are both retried.
  let result: ClaudeResult | null = null;
  let thrownError = "upstream_failed";

  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    try {
      result = await callClaude(userMessage, REQUEST_TIMEOUT_MS);
    } catch (err) {
      thrownError = `upstream_failed: ${String(err)}`;
      result = null;
    }
    if (result?.ok) break;
    if (result && !result.error.startsWith("retryable_status_")) break;
  }

  if (result === null) {
    return jsonResponse({ success: false, data: null, error: thrownError }, 502);
  }
  if (!result.ok) {
    return jsonResponse({ success: false, data: null, error: result.error }, result.status ?? 502);
  }

  return jsonResponse({ success: true, data: result.data, error: null });
});

/// Timing out is enforced with an AbortController rather than by racing a
/// timer: the losing request would otherwise stay in flight, so a timeout
/// followed by a retry would mean two concurrent billed calls.
async function callClaude(userMessage: string, timeoutMs: number): Promise<ClaudeResult> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await requestClaude(userMessage, controller.signal);
  } finally {
    clearTimeout(timer);
  }
}

async function requestClaude(userMessage: string, signal: AbortSignal): Promise<ClaudeResult> {
  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    signal,
    headers: {
      "content-type": "application/json",
      "x-api-key": ANTHROPIC_API_KEY!,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: ANTHROPIC_MODEL,
      // A prescription can list several medicines and several care items;
      // parse-medicine's 1024 is sized for one flat object.
      max_tokens: 2048,
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
    console.error(`anthropic_error_${res.status}: ${text.slice(0, 300)}`);
    return { ok: false, error: `anthropic_error_${res.status}`, status: 502 };
  }

  const payload = await res.json();
  const toolUse = (payload.content ?? []).find((block: { type: string }) => block.type === "tool_use");
  if (!toolUse) {
    return { ok: false, error: "no_tool_use_in_response" };
  }
  return { ok: true, data: sanitiseExtraction(toolUse.input) };
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}
