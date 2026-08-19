// How many billed extractions a signed-in user may run.
//
// `caller.ts` closed the hole where the publishable key alone was enough to
// spend the project owner's Anthropic budget. What remains is a signed-in
// Google account with no limit: still unbounded billed calls, just now
// attached to an identity. This ledger is the limit — 40 per rolling 24-hour
// window, keyed on the verified user id. Real setup is a handful of scans;
// 40 is plenty for that and a hard stop for a looped client or a harvested
// session.
//
// Fail closed in every direction, including when the table cannot be read
// or written. Skipping the check because the database is unreachable is
// how a blip becomes unbounded billed calls again. The increment happens
// *before* Claude is called, so a recorded slot the model then fails on is
// lost on purpose: counting attempts, not successes, is what keeps a
// failing client from retrying its way past the cap.

export type QuotaResult =
  | { ok: true }
  | { ok: false; error: string; status: number };

export const PARSE_MEDICINE_QUOTA_LIMIT = 40;
export const PARSE_MEDICINE_QUOTA_WINDOW_MS = 24 * 60 * 60 * 1000;

const DEFAULT_TIMEOUT_MS = 5_000;
const TABLE = "parse_medicine_usage";

interface UsageRow {
  user_id: string;
  window_start: string;
  call_count: number;
}

/**
 * Records one parse-medicine call against the caller's 24-hour window, or
 * explains why it must not proceed.
 *
 * The thing being protected is a billed upstream call, so an unreadable
 * ledger is 503 (`quota_unavailable`) rather than a free pass, and a spent
 * window is 429 (`quota_exceeded`) rather than a later Claude error.
 */
export async function consumeParseMedicineQuota(
  userId: string,
  opts: {
    supabaseUrl: string;
    serviceRoleKey: string;
    fetchImpl?: typeof fetch;
    timeoutMs?: number;
    now?: Date;
  },
): Promise<QuotaResult> {
  if (typeof userId !== "string" || userId.length === 0) {
    return { ok: false, error: "quota_unavailable", status: 503 };
  }

  const doFetch = opts.fetchImpl ?? fetch;
  const timeoutMs = opts.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const now = opts.now ?? new Date();
  const headers = {
    apikey: opts.serviceRoleKey,
    Authorization: `Bearer ${opts.serviceRoleKey}`,
    Accept: "application/json",
    "content-type": "application/json",
    Prefer: "return=representation",
  };
  const rowUrl =
    `${opts.supabaseUrl}/rest/v1/${TABLE}` +
    `?user_id=eq.${encodeURIComponent(userId)}` +
    `&select=user_id,window_start,call_count`;
  const tableUrl = `${opts.supabaseUrl}/rest/v1/${TABLE}`;

  const existing = await readRow(doFetch, rowUrl, headers, timeoutMs);
  if (!existing.ok) return unavailable();

  if (existing.row === null) {
    const inserted = await writeJson(
      doFetch,
      tableUrl,
      {
        method: "POST",
        headers,
        body: JSON.stringify({
          user_id: userId,
          window_start: now.toISOString(),
          call_count: 1,
        }),
      },
      timeoutMs,
    );
    if (!inserted.ok) return unavailable();
    // 409: another request created the row between our read and write.
    // Re-read and treat it as an existing window rather than skipping
    // the cap, which is what "just insert again" would do.
    if (inserted.status === 409) {
      const raced = await readRow(doFetch, rowUrl, headers, timeoutMs);
      if (!raced.ok || raced.row === null) return unavailable();
      return applyExisting(raced.row, userId, now, doFetch, rowUrl, headers, timeoutMs);
    }
    if (inserted.status < 200 || inserted.status >= 300) return unavailable();
    return { ok: true };
  }

  return applyExisting(existing.row, userId, now, doFetch, rowUrl, headers, timeoutMs);
}

async function applyExisting(
  row: UsageRow,
  userId: string,
  now: Date,
  doFetch: typeof fetch,
  rowUrl: string,
  headers: Record<string, string>,
  timeoutMs: number,
): Promise<QuotaResult> {
  if (row.user_id !== userId) return unavailable();

  const windowStart = new Date(row.window_start);
  if (Number.isNaN(windowStart.getTime())) return unavailable();
  if (!Number.isInteger(row.call_count) || row.call_count < 0) return unavailable();

  const windowExpired = now.getTime() - windowStart.getTime() >= PARSE_MEDICINE_QUOTA_WINDOW_MS;
  if (windowExpired) {
    const reset = await writeJson(
      doFetch,
      rowUrl,
      {
        method: "PATCH",
        headers,
        body: JSON.stringify({ window_start: now.toISOString(), call_count: 1 }),
      },
      timeoutMs,
    );
    if (!reset.ok || reset.status < 200 || reset.status >= 300) return unavailable();
    if (!patchTouchedARow(reset.body)) return unavailable();
    return { ok: true };
  }

  if (row.call_count >= PARSE_MEDICINE_QUOTA_LIMIT) {
    return { ok: false, error: "quota_exceeded", status: 429 };
  }

  const increment = await writeJson(
    doFetch,
    rowUrl,
    {
      method: "PATCH",
      headers,
      body: JSON.stringify({ call_count: row.call_count + 1 }),
    },
    timeoutMs,
  );
  if (!increment.ok || increment.status < 200 || increment.status >= 300) {
    return unavailable();
  }
  if (!patchTouchedARow(increment.body)) return unavailable();
  return { ok: true };
}

function unavailable(): QuotaResult {
  return { ok: false, error: "quota_unavailable", status: 503 };
}

function patchTouchedARow(body: unknown): boolean {
  // Prefer: return=representation. Zero rows means the row vanished or a
  // concurrent write won; either way we did not record this call.
  return Array.isArray(body) && body.length === 1;
}

async function readRow(
  doFetch: typeof fetch,
  url: string,
  headers: Record<string, string>,
  timeoutMs: number,
): Promise<{ ok: true; row: UsageRow | null } | { ok: false }> {
  const got = await writeJson(doFetch, url, { method: "GET", headers }, timeoutMs);
  if (!got.ok || got.status < 200 || got.status >= 300) return { ok: false };
  if (!Array.isArray(got.body)) return { ok: false };
  if (got.body.length === 0) return { ok: true, row: null };
  if (got.body.length !== 1) return { ok: false };
  const row = parseRow(got.body[0]);
  if (row === null) return { ok: false };
  return { ok: true, row };
}

function parseRow(value: unknown): UsageRow | null {
  if (value === null || typeof value !== "object") return null;
  const row = value as Record<string, unknown>;
  if (typeof row.user_id !== "string" || row.user_id.length === 0) return null;
  if (typeof row.window_start !== "string" || row.window_start.length === 0) return null;
  if (typeof row.call_count !== "number" || !Number.isInteger(row.call_count)) return null;
  return {
    user_id: row.user_id,
    window_start: row.window_start,
    call_count: row.call_count,
  };
}

async function writeJson(
  doFetch: typeof fetch,
  url: string,
  init: RequestInit,
  timeoutMs: number,
): Promise<{ ok: true; status: number; body: unknown } | { ok: false }> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  let res: Response;
  try {
    res = await doFetch(url, { ...init, signal: controller.signal });
  } catch {
    return { ok: false };
  } finally {
    clearTimeout(timer);
  }

  let body: unknown = null;
  const text = await res.text().catch(() => "");
  if (text.length > 0) {
    try {
      body = JSON.parse(text);
    } catch {
      // 409 from PostgREST is still a usable status even if the body is
      // not JSON we care about; other unparseable bodies are a failure.
      if (res.status !== 409) return { ok: false };
    }
  }
  return { ok: true, status: res.status, body };
}
