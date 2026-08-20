import { assertEquals } from "@std/assert";

import { AccountDeletionAdmin, deleteAccountForUser, handleDeleteAccount } from "./delete.ts";

const ENV = {
  supabaseUrl: "https://project.supabase.co",
  serviceRoleKey: "service-role",
};

const CALLER = "4d4e131a-9a1e-4ead-b530-ce3b8b300282";
const OTHER = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";

function recordingAdmin(opts?: {
  failAt?: "revoke" | "tokens" | "auth";
}): AccountDeletionAdmin & { seen: string[] } {
  const seen: string[] = [];
  return {
    seen,
    async revokeCareLinks(userId) {
      seen.push(`revoke:${userId}`);
      if (opts?.failAt === "revoke") return { error: { message: "revoke boom" } };
      return { error: null };
    },
    async deleteDeviceTokens(userId) {
      seen.push(`tokens:${userId}`);
      if (opts?.failAt === "tokens") return { error: { message: "tokens boom" } };
      return { error: null };
    },
    async deleteAuthUser(userId) {
      seen.push(`auth:${userId}`);
      if (opts?.failAt === "auth") return { error: { message: "auth boom" } };
      return { error: null };
    },
  };
}

function post(body: unknown, headers: Record<string, string> = { Authorization: "Bearer user-jwt" }): Request {
  return new Request("http://fn/delete_account", {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
}

Deno.test("a verified caller is deleted, and a body-supplied userId is ignored", async () => {
  const admin = recordingAdmin();
  const req = post({ userId: OTHER });
  const res = await handleDeleteAccount(req, {
    ...ENV,
    verify: async () => ({ ok: true, userId: CALLER }),
    admin,
  });
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { ok: true });
  assertEquals(admin.seen, [`revoke:${CALLER}`, `tokens:${CALLER}`, `auth:${CALLER}`]);
  // The handler never consumed the body: this would throw if it had called
  // `req.json()`, which is the accidental-parse case this test exists for.
  assertEquals(await req.json(), { userId: OTHER });
});

Deno.test("the handler never reads the body even when it is empty", async () => {
  const admin = recordingAdmin();
  const req = new Request("http://fn/delete_account", {
    method: "POST",
    headers: { Authorization: "Bearer user-jwt" },
  });
  const res = await handleDeleteAccount(req, {
    ...ENV,
    verify: async () => ({ ok: true, userId: CALLER }),
    admin,
  });
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { ok: true });
  assertEquals(admin.seen, [`revoke:${CALLER}`, `tokens:${CALLER}`, `auth:${CALLER}`]);
});

Deno.test("a missing Authorization header is refused without touching the account", async () => {
  const admin = recordingAdmin();
  const res = await handleDeleteAccount(post({}, {}), {
    ...ENV,
    admin,
  });
  assertEquals(res.status, 401);
  assertEquals(await res.json(), { error: "not_authenticated" });
  assertEquals(admin.seen, []);
});

Deno.test("an anonymous / unverifiable caller is refused without touching the account", async () => {
  const admin = recordingAdmin();
  const res = await handleDeleteAccount(post({ userId: OTHER }), {
    ...ENV,
    verify: async () => ({ ok: false, error: "not_authenticated", status: 401 }),
    admin,
  });
  assertEquals(res.status, 401);
  assertEquals(await res.json(), { error: "not_authenticated" });
  assertEquals(admin.seen, []);
});

Deno.test("an unreachable auth server is 503, not a deletion", async () => {
  const admin = recordingAdmin();
  const res = await handleDeleteAccount(post({}), {
    ...ENV,
    verify: async () => ({ ok: false, error: "auth_unavailable", status: 503 }),
    admin,
  });
  assertEquals(res.status, 503);
  assertEquals(await res.json(), { error: "auth_unavailable" });
  assertEquals(admin.seen, []);
});

Deno.test("missing function secrets are 500 and do not call admin", async () => {
  const admin = recordingAdmin();
  const res = await handleDeleteAccount(post({}), {
    supabaseUrl: undefined,
    serviceRoleKey: undefined,
    admin,
  });
  assertEquals(res.status, 500);
  assertEquals(await res.json(), { error: "server_misconfigured" });
  assertEquals(admin.seen, []);
});

Deno.test("non-POST is refused", async () => {
  const admin = recordingAdmin();
  const req = new Request("http://fn/delete_account", { method: "GET" });
  const res = await handleDeleteAccount(req, { ...ENV, admin });
  assertEquals(res.status, 405);
  assertEquals(await res.json(), { error: "method_not_allowed" });
  assertEquals(admin.seen, []);
});

Deno.test("a failed revoke does not delete tokens or the auth user", async () => {
  const admin = recordingAdmin({ failAt: "revoke" });
  const result = await deleteAccountForUser(admin, CALLER);
  assertEquals(result, { ok: false, error: "delete_failed", status: 500 });
  assertEquals(admin.seen, [`revoke:${CALLER}`]);
});

Deno.test("a failed token delete does not delete the auth user", async () => {
  const admin = recordingAdmin({ failAt: "tokens" });
  const result = await deleteAccountForUser(admin, CALLER);
  assertEquals(result, { ok: false, error: "delete_failed", status: 500 });
  assertEquals(admin.seen, [`revoke:${CALLER}`, `tokens:${CALLER}`]);
});
