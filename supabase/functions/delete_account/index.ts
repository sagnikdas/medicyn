// Deletes the signed-in caller's account. Identity is established against
// the auth server (`caller.ts`) rather than trusted from the gateway's
// `verify_jwt` flag — that flag is satisfied by the publishable key, which
// ships in the app. After that, a service-role client acts only on
// `caller.userId`: revoke any care link, drop device tokens, then
// `auth.admin.deleteUser`.

import { handleDeleteAccount } from "./delete.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

Deno.serve((req) =>
  handleDeleteAccount(req, {
    supabaseUrl: SUPABASE_URL,
    serviceRoleKey: SERVICE_ROLE_KEY,
  })
);
