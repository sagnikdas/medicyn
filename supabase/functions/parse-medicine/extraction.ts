// Validation for the structure the model returns.
//
// Lives outside `index.ts` because that module calls `Deno.serve` at import
// time, which a test cannot do — the same reason `notify-care` keeps its FCM
// logic in `fcm.ts`.

const FREQUENCY_TYPES = ["daily", "specific_days", "every_x_hours", "as_needed"];

/** `HH:mm`, hour 0-23, minute 0-59. A single-digit hour is allowed. */
export function isClockTime(value: unknown): value is string {
  if (typeof value !== "string") return false;
  const match = /^(\d{1,2}):(\d{2})$/.exec(value);
  if (!match) return false;
  const hour = Number(match[1]);
  const minute = Number(match[2]);
  return hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59;
}

/**
 * Drops anything in the model's tool output that the client could not
 * schedule.
 *
 * The tool's `input_schema` above bounds `times`, `daysOfWeek` and
 * `intervalHours` — but an input schema is guidance to the model, not a
 * validator the API enforces, so nothing had actually checked these before
 * they were returned verbatim. That matters more than a normal parsing
 * question because the input is attacker-influenceable: `ocrText` is whatever
 * was in front of the camera, so a crafted label can try to steer the
 * extraction, and the values land on a device that arms medication alarms
 * from them.
 *
 * The client validates these too, and must keep doing so — an old build is
 * still out there, and this function is not the only writer of a schedule.
 * Validating here as well means a malformed structure never reaches any
 * client, old or new.
 *
 * Note `^[0-2][0-9]:[0-5][0-9]$` in the schema admits "29:00"; the check
 * here does not.
 */
export function sanitiseExtraction(input: Record<string, unknown>): Record<string, unknown> {
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
    // The client defaults an unrecognised value to daily; say so explicitly
    // rather than letting it infer that from a missing field.
    out.frequencyType = "daily";
  }

  const confidence = input.confidence;
  out.confidence = typeof confidence === "number" && confidence >= 0 && confidence <= 1 ? confidence : 0;

  return out;
}
