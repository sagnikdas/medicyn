/// Project-level Supabase config for the "medicyn" project — safe to embed
/// (the publishable/anon key is meant to be public; every access rule lives
/// in Postgres Row Level Security, see supabase/migrations/*.sql). No
/// service-role key or database password ever belongs in this app.
class SupabaseConfig {
  static const url = 'https://twybepxnqayypzljhcnx.supabase.co';
  static const publishableKey = 'sb_publishable_6b-JpRS4agNW_gRaLE_yWQ__ShNr7hP';
}
