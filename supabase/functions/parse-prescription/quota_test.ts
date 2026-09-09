import { assertEquals } from "@std/assert";
import {
  consumeParsePrescriptionQuota,
  PARSE_PRESCRIPTION_QUOTA_LIMIT,
} from "./quota.ts";

const USER = "4d4e131a-9a1e-4ead-b530-ce3b8b300282";
const NOW = new Date("2026-08-19T12:00:00.000Z");
const OPTS = {
  supabaseUrl: "https://project.supabase.co",
  serviceRoleKey: "service-role",
  now: NOW,
};

const ROW_URL =
  `https://project.supabase.co/rest/v1/parse_prescription_usage` +
  `?user_id=eq.${USER}` +
  `&select=user_id,window_start,call_count`;
const TABLE_URL = "https://project.supabase.co/rest/v1/parse_prescription_usage";

interface Call {
  method: string;
  url: string;
  headers: Record<string, string>;
  body: string | null;
}

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function scriptedFetch(
  script: Array<(call: Call) => Response | Promise<Response>>,
): { fetchImpl: typeof fetch; calls: Call[] } {
  const calls: Call[] = [];
  const fetchImpl = ((input: string | URL | Request, init?: RequestInit) => {
    const call: Call = {
      method: (init?.method ?? "GET").toUpperCase(),
      url: String(input),
      headers: (init?.headers ?? {}) as Record<string, string>,
      body: typeof init?.body === "string" ? init.body : null,
    };
    calls.push(call);
    const step = script[calls.length - 1];
    if (!step) {
      return Promise.reject(new Error(`unexpected fetch #${calls.length}: ${call.method} ${call.url}`));
    }
    return Promise.resolve(step(call));
  }) as unknown as typeof fetch;
  return { fetchImpl, calls };
}

function row(callCount: number, windowStart: Date = NOW): Record<string, unknown> {
  return {
    user_id: USER,
    window_start: windowStart.toISOString(),
    call_count: callCount,
  };
}

Deno.test("a first call is allowed and inserts the ledger row", async () => {
  const { fetchImpl, calls } = scriptedFetch([
    () => jsonResponse(200, []),
    () => jsonResponse(201, [row(1)]),
  ]);

  const result = await consumeParsePrescriptionQuota(USER, { ...OPTS, fetchImpl });
  assertEquals(result, { ok: true });
  assertEquals(calls.map((c) => c.method), ["GET", "POST"]);
  assertEquals(calls[0].url, ROW_URL);
  assertEquals(calls[1].url, TABLE_URL);
  assertEquals(JSON.parse(calls[1].body!), {
    user_id: USER,
    window_start: NOW.toISOString(),
    call_count: 1,
  });
  assertEquals(calls[0].headers.apikey, "service-role");
  assertEquals(calls[0].headers.Authorization, "Bearer service-role");
});

Deno.test("the 15th call in the window is allowed", async () => {
  const { fetchImpl, calls } = scriptedFetch([
    () => jsonResponse(200, [row(PARSE_PRESCRIPTION_QUOTA_LIMIT - 1)]),
    () => jsonResponse(200, [row(PARSE_PRESCRIPTION_QUOTA_LIMIT)]),
  ]);

  const result = await consumeParsePrescriptionQuota(USER, { ...OPTS, fetchImpl });
  assertEquals(result, { ok: true });
  assertEquals(calls.map((c) => c.method), ["GET", "PATCH"]);
  assertEquals(JSON.parse(calls[1].body!), { call_count: PARSE_PRESCRIPTION_QUOTA_LIMIT });
});

Deno.test("the 16th call is refused as quota_exceeded and does not write", async () => {
  // The billed call is what this is here to stop. A GET that already shows
  // a spent window must not be followed by a write, and must not look like
  // anything that would proceed to Claude.
  const { fetchImpl, calls } = scriptedFetch([
    () => jsonResponse(200, [row(PARSE_PRESCRIPTION_QUOTA_LIMIT)]),
  ]);

  const result = await consumeParsePrescriptionQuota(USER, { ...OPTS, fetchImpl });
  assertEquals(result, { ok: false, error: "quota_exceeded", status: 429 });
  assertEquals(calls.map((c) => c.method), ["GET"]);
  assertEquals(calls.every((c) => !c.url.includes("anthropic")), true);
});

Deno.test("a window older than 24 hours resets rather than remaining spent", async () => {
  const expired = new Date(NOW.getTime() - 24 * 60 * 60 * 1000);
  const { fetchImpl, calls } = scriptedFetch([
    () => jsonResponse(200, [row(PARSE_PRESCRIPTION_QUOTA_LIMIT, expired)]),
    () => jsonResponse(200, [row(1, NOW)]),
  ]);

  const result = await consumeParsePrescriptionQuota(USER, { ...OPTS, fetchImpl });
  assertEquals(result, { ok: true });
  assertEquals(calls.map((c) => c.method), ["GET", "PATCH"]);
  assertEquals(JSON.parse(calls[1].body!), {
    window_start: NOW.toISOString(),
    call_count: 1,
  });
});

Deno.test("a window just under 24 hours is not reset", async () => {
  const stillOpen = new Date(NOW.getTime() - 24 * 60 * 60 * 1000 + 1);
  const { fetchImpl, calls } = scriptedFetch([
    () => jsonResponse(200, [row(PARSE_PRESCRIPTION_QUOTA_LIMIT, stillOpen)]),
  ]);

  const result = await consumeParsePrescriptionQuota(USER, { ...OPTS, fetchImpl });
  assertEquals(result, { ok: false, error: "quota_exceeded", status: 429 });
  assertEquals(calls.map((c) => c.method), ["GET"]);
});

Deno.test("an unreachable usage table fails closed, and says so distinctly", async () => {
  // Same reasoning as auth_unavailable: the thing being protected is a
  // billed upstream call, so an unreadable ledger must not get one. The
  // helper returning quota_unavailable is the gate — index.ts does not
  // call Claude unless this is ok, and nothing here even names Anthropic.
  const boom = (() => Promise.reject(new Error("connection reset"))) as unknown as typeof fetch;
  const result = await consumeParsePrescriptionQuota(USER, { ...OPTS, fetchImpl: boom });
  assertEquals(result, { ok: false, error: "quota_unavailable", status: 503 });
});

Deno.test("a usage-table error fails closed", async () => {
  const { fetchImpl } = scriptedFetch([() => jsonResponse(500, { message: "db down" })]);
  const result = await consumeParsePrescriptionQuota(USER, { ...OPTS, fetchImpl });
  assertEquals(result, { ok: false, error: "quota_unavailable", status: 503 });
});

Deno.test("an unparseable usage row fails closed", async () => {
  const garbage = (() =>
    Promise.resolve(new Response("not json", { status: 200 }))) as unknown as typeof fetch;
  const result = await consumeParsePrescriptionQuota(USER, { ...OPTS, fetchImpl: garbage });
  assertEquals(result, { ok: false, error: "quota_unavailable", status: 503 });
});

Deno.test("a write failure after a successful read fails closed and does not proceed", async () => {
  const { fetchImpl, calls } = scriptedFetch([
    () => jsonResponse(200, [row(1)]),
    () => Promise.reject(new Error("connection reset")),
  ]);

  const result = await consumeParsePrescriptionQuota(USER, { ...OPTS, fetchImpl });
  assertEquals(result, { ok: false, error: "quota_unavailable", status: 503 });
  assertEquals(calls.map((c) => c.method), ["GET", "PATCH"]);
  assertEquals(calls.every((c) => !c.url.includes("anthropic")), true);
});

Deno.test("a PATCH that touches no row fails closed", async () => {
  const { fetchImpl } = scriptedFetch([
    () => jsonResponse(200, [row(1)]),
    () => jsonResponse(200, []),
  ]);
  const result = await consumeParsePrescriptionQuota(USER, { ...OPTS, fetchImpl });
  assertEquals(result, { ok: false, error: "quota_unavailable", status: 503 });
});

Deno.test("an empty user id is refused without calling the database", async () => {
  let called = false;
  const spy = (() => {
    called = true;
    return Promise.resolve(new Response("[]", { status: 200 }));
  }) as unknown as typeof fetch;

  const result = await consumeParsePrescriptionQuota("", { ...OPTS, fetchImpl: spy });
  assertEquals(result, { ok: false, error: "quota_unavailable", status: 503 });
  assertEquals(called, false);
});
