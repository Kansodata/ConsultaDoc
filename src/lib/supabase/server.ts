import { createClient, type SupabaseClient } from "@supabase/supabase-js";

const globalForSupabase = globalThis as unknown as {
  supabaseServer: SupabaseClient | undefined;
};

export const supabaseServer =
  globalForSupabase.supabaseServer ??
  createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

if (process.env.NODE_ENV !== "production")
  globalForSupabase.supabaseServer = supabaseServer;
