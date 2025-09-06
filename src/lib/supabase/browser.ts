'use client'
import { createClient, type SupabaseClient } from '@supabase/supabase-js'
// import type { Database } from '@/types/supabase' // si generaste tipos

const url  = process.env.NEXT_PUBLIC_SUPABASE_URL
const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY

if (!url || !anon) {
  throw new Error('Faltan NEXT_PUBLIC_SUPABASE_URL o NEXT_PUBLIC_SUPABASE_ANON_KEY')
}

// Singleton para evitar múltiples instancias en HMR
const globalForSupabase = globalThis as unknown as {
  supabaseBrowser?: SupabaseClient // SupabaseClient<Database> si usas tipos
}

export function supabaseBrowser(): SupabaseClient { // <- ahora es FUNCIÓN
  if (!globalForSupabase.supabaseBrowser) {
    globalForSupabase.supabaseBrowser = createClient(/*<Database>*/ url, anon, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true,
      },
    })
  }
  return globalForSupabase.supabaseBrowser
}
