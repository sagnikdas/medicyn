// Validation for the structure the model returns.
//
// Lives outside `index.ts` because that module calls `Deno.serve` at import
// time, which a test cannot do — the same reason `notify-care` keeps its FCM
// logic in `fcm.ts`, and parse-medicine keeps this logic in its own
// extraction.ts. Duplicated here rather than imported from parse-medicine:
// this repo has no shared-module convention between function directories,
// and the two extraction contracts are close but not identical (a
// prescription also carries careItems, which parse-medicine's shape has no
// concept of).

const FREQUENCY_TYPES = ["daily", "specific_days", "every_x_hours", "as_needed"];
const CARE_KINDS = ["test", "scan", "therapy", "appointment", "other"];
const RECURRENCES = ["none", "weekly", "every_n_days", "every_n_months"];

/** `HH:mm`, hour 0-23, minute 0-59. A single-digit hour is allowed. */
export function isClockTime(value: unknown): value is string {
  if (typeof value !== "string") return false;
  const match = /^(\d{1,2}):(\d{2})$/.exec(value);
  if (!match) return false;
  const hour = Number(match[1]);
  const minute = Number(match[2]);
  return hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59;
}

const DAYS_IN_MONTH = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

/**
 * `YYYY-MM-DD`, a real calendar date. Permissive about leap years (allows
 * Feb 29 in any year) rather than modelling the century rule — a model
 * occasionally being one day generous in a century-boundary edge case is
 * nowhere near the cost of a hand-rolled leap-year calculation getting it
 * wrong here.
 */
export function isIsoDate(value: unknown): value is string {
  if (typeof value !== "string") return false;
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) return false;
  const month = Number(match[2]);
  const day = Number(match[3]);
  if (month < 1 || month > 12) return false;
  if (day < 1 || day > DAYS_IN_MONTH[month - 1]) return false;
  return true;
}

/**
 * Drops anything in the model's tool output that the client could not
 * schedule for one medicine.
 *
 * The tool's `input_schema` bounds `times`, `daysOfWeek` and `intervalHours`
 * — but an input schema is guidance to the model, not a validator the API
 * enforces, so nothing had actually checked these before they were returned
 * verbatim (parse-medicine's history). That matters more than a normal
 * parsing question because the input is attacker-influenceable: `ocrText`
 * is whatever was photographed or in the uploaded PDF, so a crafted
 * document can try to steer the extraction, and the values land on a
 * device that arms medication alarms from them.
 */
function sanitiseMedicine(input: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = { ...input };

  out.times = Array.isArray(input.times) ? input.times.filter(isClockTime) : [];

  out.daysOfWeek = Array.isArray(input.daysOfWeek)
    ? [...new Set(
      input.daysOfWeek.filter((d): d is number => typeof d === "number" && Number.isInteger(d) && d >= 0 && d <= 6),
    )].sort((a, b) => a - b)
    : [];

  const interval = input.intervalHours;
  out.intervalHours = typeof interval === "number" && Number.isInteger(interval) && interval >= 1 && interval <= 24
    ? interval
    : undefined;

  if (typeof input.frequencyType !== "string" || !FREQUENCY_TYPES.includes(input.frequencyType)) {
    out.frequencyType = "daily";
  }

  const confidence = input.confidence;
  out.confidence = typeof confidence === "number" && confidence >= 0 && confidence <= 1 ? confidence : 0;

  return out;
}

/**
 * Drops anything in the model's tool output that the client could not turn
 * into one or more `TodayCareReminder` rows. Same defensive philosophy as
 * `sanitiseMedicine`: this eventually arms real alarms, from input the
 * model read off an uploaded document.
 */
function sanitiseCareItem(input: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = { ...input };

  out.title = typeof input.title === "string" ? input.title.trim().slice(0, 200) : "";
  out.notes = typeof input.notes === "string" ? input.notes.slice(0, 2_000) : "";

  // Mirrors the Dart-side TodayCareKind.fromName's `orElse: () => other`.
  out.kind = typeof input.kind === "string" && CARE_KINDS.includes(input.kind) ? input.kind : "other";

  out.recurrence = typeof input.recurrence === "string" && RECURRENCES.includes(input.recurrence)
    ? input.recurrence
    : "none";

  out.firstDate = isIsoDate(input.firstDate) ? input.firstDate : "";

  const intervalN = input.intervalN;
  out.intervalN = typeof intervalN === "number" && Number.isInteger(intervalN) && intervalN >= 1 && intervalN <= 365
    ? intervalN
    : 1;

  // Capped at 52 (a year of weekly sessions) — the client expands this into
  // that many individual reminders, so an unbounded value here is a client-
  // side resource-exhaustion vector, not just a data-quality one.
  const occurrenceCount = input.occurrenceCount;
  out.occurrenceCount =
    typeof occurrenceCount === "number" && Number.isInteger(occurrenceCount) && occurrenceCount >= 1 &&
      occurrenceCount <= 52
      ? occurrenceCount
      : 1;

  const confidence = input.confidence;
  out.confidence = typeof confidence === "number" && confidence >= 0 && confidence <= 1 ? confidence : 0;

  return out;
}

/**
 * Sanitises the full multi-item extraction: every element of `medicines`
 * through `sanitiseMedicine`, every element of `careItems` through
 * `sanitiseCareItem`. A malformed or missing array on either key becomes an
 * empty array rather than a thrown error — a document with only medicines,
 * or only care items, is a normal and expected result, not a failure.
 */
export function sanitiseExtraction(input: Record<string, unknown>): Record<string, unknown> {
  const medicines = Array.isArray(input.medicines) ? input.medicines : [];
  const careItems = Array.isArray(input.careItems) ? input.careItems : [];

  return {
    medicines: medicines
      .filter((m): m is Record<string, unknown> => m !== null && typeof m === "object")
      .map(sanitiseMedicine),
    careItems: careItems
      .filter((c): c is Record<string, unknown> => c !== null && typeof c === "object")
      .map(sanitiseCareItem),
  };
}
