"use client";

import { createClient, type SupabaseClient } from "@supabase/supabase-js";

const globalForSupabase = globalThis as unknown as {
  supabaseBrowser: SupabaseClient | undefined;
};

export const supabaseBrowser =
  globalForSupabase.supabaseBrowser ??
  createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true,
      },
    },
  );

if (process.env.NODE_ENV !== "production")
  globalForSupabase.supabaseBrowser = supabaseBrowser;
