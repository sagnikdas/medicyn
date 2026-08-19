import { assertEquals } from "@std/assert";
import { verifyCaller } from "./caller.ts";

// The case these exist for: the deployed function answered a request carrying
// only the publishable key — no account, no sign-in — and ran a billed model
// call. `verify_jwt` accepted it because the publishable key is a credential
// the project accepts; it simply names no user.

const OPTS = { supabaseUrl: "https://project.supabase.co", serviceRoleKey: "service-role" };

/** An auth server that answers with `status`, and `body` when it answers 200. */
function stubAuth(status: number, body: unknown = {}): typeof fetch {
  return ((_input: string | URL | Request, _init?: RequestInit) =>
    Promise.resolve(
      new Response(JSON.stringify(body), {
        status,
        headers: { "content-type": "application/json" },
      }),
    )) as unknown as typeof fetch;
}

Deno.test("a real user is accepted, and their id is reported", async () => {
  const result = await verifyCaller("Bearer user-jwt", {
    ...OPTS,
    fetchImpl: stubAuth(200, { id: "4d4e131a-9a1e-4ead-b530-ce3b8b300282", email: "a@b.invalid" }),
  });
  assertEquals(result, { ok: true, userId: "4d4e131a-9a1e-4ead-b530-ce3b8b300282" });
});

Deno.test("the publishable key alone is refused", async () => {
  // /auth/v1/user 401s for a key that names no user. This is the hole.
  const result = await verifyCaller("Bearer sb_publishable_abc123", {
    ...OPTS,
    fetchImpl: stubAuth(401, { message: "invalid claim: missing sub claim" }),
  });
  assertEquals(result, { ok: false, error: "not_authenticated", status: 401 });
});

Deno.test("no Authorization header is refused without calling the auth server", async () => {
  let called = false;
  const spy = (() => {
    called = true;
    return Promise.resolve(new Response("{}", { status: 200 }));
  }) as unknown as typeof fetch;

  const result = await verifyCaller(null, { ...OPTS, fetchImpl: spy });
  assertEquals(result, { ok: false, error: "not_authenticated", status: 401 });
  assertEquals(called, false);
});

Deno.test("an empty or whitespace bearer token is refused", async () => {
  for (const header of ["", "Bearer ", "Bearer    "]) {
    const result = await verifyCaller(header, { ...OPTS, fetchImpl: stubAuth(200, { id: "x" }) });
    assertEquals(result, { ok: false, error: "not_authenticated", status: 401 });
  }
});

Deno.test("a bare token without the Bearer prefix still resolves", async () => {
  const result = await verifyCaller("user-jwt", { ...OPTS, fetchImpl: stubAuth(200, { id: "u1" }) });
  assertEquals(result, { ok: true, userId: "u1" });
});

Deno.test("a 200 that names no user is refused, not read as an identity", async () => {
  for (const body of [{}, { id: "" }, { id: 42 }, { id: null }]) {
    const result = await verifyCaller("Bearer t", { ...OPTS, fetchImpl: stubAuth(200, body) });
    assertEquals(result, { ok: false, error: "not_authenticated", status: 401 });
  }
});

Deno.test("a 403 is refused", async () => {
  const result = await verifyCaller("Bearer t", { ...OPTS, fetchImpl: stubAuth(403) });
  assertEquals(result, { ok: false, error: "not_authenticated", status: 401 });
});

Deno.test("an unreachable auth server fails closed, and says so distinctly", async () => {
  // The thing being protected is a billed upstream call, so an unverifiable
  // caller must not get one. 503 rather than 401 so a legitimate client can
  // tell "try again" from "sign in again".
  const boom = (() => Promise.reject(new Error("connection reset"))) as unknown as typeof fetch;
  const result = await verifyCaller("Bearer t", { ...OPTS, fetchImpl: boom });
  assertEquals(result, { ok: false, error: "auth_unavailable", status: 503 });
});

Deno.test("an auth server error fails closed", async () => {
  const result = await verifyCaller("Bearer t", { ...OPTS, fetchImpl: stubAuth(500) });
  assertEquals(result, { ok: false, error: "auth_unavailable", status: 503 });
});

Deno.test("an unparseable auth response fails closed", async () => {
  const garbage = (() =>
    Promise.resolve(new Response("not json", { status: 200 }))) as unknown as typeof fetch;
  const result = await verifyCaller("Bearer t", { ...OPTS, fetchImpl: garbage });
  assertEquals(result, { ok: false, error: "auth_unavailable", status: 503 });
});

Deno.test("the token is sent as the bearer and the service key as the apikey", async () => {
  let seenUrl = "";
  let seenHeaders: Record<string, string> = {};
  const capture = ((input: string | URL | Request, init?: RequestInit) => {
    seenUrl = String(input);
    seenHeaders = (init?.headers ?? {}) as Record<string, string>;
    return Promise.resolve(
      new Response(JSON.stringify({ id: "u1" }), { status: 200 }),
    );
  }) as unknown as typeof fetch;

  await verifyCaller("Bearer user-jwt", { ...OPTS, fetchImpl: capture });
  assertEquals(seenUrl, "https://project.supabase.co/auth/v1/user");
  assertEquals(seenHeaders.Authorization, "Bearer user-jwt");
  assertEquals(seenHeaders.apikey, "service-role");
});
