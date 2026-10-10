import { createClient, type SupabaseClient } from "@supabase/supabase-js";

let client: SupabaseClient | undefined;

export function backendConfiguration() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim();
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY?.trim();
  return { url, key, isConfigured: Boolean(url && key) };
}

export function getSupabase(): SupabaseClient {
  const { url, key, isConfigured } = backendConfiguration();
  if (!isConfigured || !url || !key) throw new Error("Sidequest backend is not configured.");
  client ??= createClient(url, key, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
  });
  return client;
}
