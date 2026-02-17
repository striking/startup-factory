/**
 * Shared utility for resolving Supabase configuration from environment variables.
 * Prefers service role key, falls back to anon key.
 */
function resolveSupabaseConfig() {
  const url = process.env.SUPABASE_URL?.trim();
  if (!url) {
    return { error: "Missing SUPABASE_URL environment variable." };
  }

  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim();
  if (serviceRoleKey) {
    return { url, key: serviceRoleKey };
  }

  const anonKey = process.env.SUPABASE_ANON_KEY?.trim();
  if (anonKey) {
    return { url, key: anonKey };
  }

  return {
    error: "Missing SUPABASE_SERVICE_ROLE_KEY (or SUPABASE_ANON_KEY fallback) environment variable.",
  };
}

/**
 * Version for Node.js scripts that throws errors instead of returning error objects.
 */
function resolveSupabaseConfigThrows() {
  const config = resolveSupabaseConfig();
  if ("error" in config) {
    throw new Error(config.error);
  }
  return config;
}

module.exports = {
  resolveSupabaseConfig,
  resolveSupabaseConfigThrows,
};