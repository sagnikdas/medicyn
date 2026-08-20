// Deletes the verified caller's account. The victim is always that caller —
// never a user id from the request body, which this handler does not read.
//
// Order: revoke any live care link this person sits on, drop their device
// tokens, then `auth.admin.deleteUser`. Postgres `on delete cascade` from
// `auth.users` then clears medicines, schedules, dose logs, profiles, and
// the rest. `revoke_care_link(uuid)` cannot be used here: it requires
// `auth.uid()`, and the service-role client has none.

import { createClient } from "@supabase/supabase-js";

import { verifyCaller } from "./caller.ts";

export interface AccountDeletionAdmin {
  revokeCareLinks(userId: string): Promise<{ error: { message: string } | null }>;
  deleteDeviceTokens(userId: string): Promise<{ error: { message: string } | null }>;
  deleteAuthUser(userId: string): Promise<{ error: { message: string } | null }>;
}

export type DeleteResult =
  | { ok: true }
  | { ok: false; error: string; status: number };

export async function handleDeleteAccount(
  req: Request,
  opts: {
    supabaseUrl: string | undefined;
    serviceRoleKey: string | undefined;
    verify?: typeof verifyCaller;
    admin?: AccountDeletionAdmin;
  },
): Promise<Response> {
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }
  if (!opts.supabaseUrl || !opts.serviceRoleKey) {
    console.error("SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY missing from the function environment");
    return json({ error: "server_misconfigured" }, 500);
  }

  const verify = opts.verify ?? verifyCaller;
  const caller = await verify(req.headers.get("Authorization"), {
    supabaseUrl: opts.supabaseUrl,
    serviceRoleKey: opts.serviceRoleKey,
  });
  if (!caller.ok) {
    return json({ error: caller.error }, caller.status);
  }

  // Do not read `req.json()`. A body of `{ userId: "<someone else>" }` must
  // not be able to retarget this, and the surest way is never to parse one.
  const admin = opts.admin ?? supabaseAdmin(opts.supabaseUrl, opts.serviceRoleKey);
  const result = await deleteAccountForUser(admin, caller.userId);
  if (!result.ok) {
    return json({ error: result.error }, result.status);
  }
  return json({ ok: true });
}

export async function deleteAccountForUser(
  admin: AccountDeletionAdmin,
  userId: string,
): Promise<DeleteResult> {
  const revoked = await admin.revokeCareLinks(userId);
  if (revoked.error) {
    console.error(`care_links_revoke_failed: ${revoked.error.message}`);
    return { ok: false, error: "delete_failed", status: 500 };
  }

  const tokens = await admin.deleteDeviceTokens(userId);
  if (tokens.error) {
    console.error(`device_tokens_delete_failed: ${tokens.error.message}`);
    return { ok: false, error: "delete_failed", status: 500 };
  }

  const deleted = await admin.deleteAuthUser(userId);
  if (deleted.error) {
    console.error(`auth_delete_user_failed: ${deleted.error.message}`);
    return { ok: false, error: "delete_failed", status: 500 };
  }

  return { ok: true };
}

export function supabaseAdmin(url: string, key: string): AccountDeletionAdmin {
  const client = createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  return {
    async revokeCareLinks(userId) {
      const { error } = await client
        .from("care_links")
        .update({
          status: "revoked",
          revoked_at: new Date().toISOString(),
          invite_code: null,
        })
        .neq("status", "revoked")
        .or(`patient_id.eq.${userId},caregiver_id.eq.${userId}`);
      return { error };
    },
    async deleteDeviceTokens(userId) {
      const { error } = await client.from("device_tokens").delete().eq("user_id", userId);
      return { error };
    },
    async deleteAuthUser(userId) {
      const { error } = await client.auth.admin.deleteUser(userId);
      return { error };
    },
  };
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}
