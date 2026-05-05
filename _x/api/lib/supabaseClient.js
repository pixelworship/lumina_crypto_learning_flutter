// Single shared Supabase client for the events API.
//
// Uses the service-role key, so all queries bypass Row Level Security.
// That's appropriate for this dev-only mock server, which sits behind
// the public-facing API and never exposes the key to a browser.
//
// Env vars (loaded from `_x/api/.env` by `dotenv/config` in server.js):
//
//   SUPABASE_URL                 e.g. https://<ref>.supabase.co
//   SUPABASE_SERVICE_ROLE_KEY    long JWT, found in project settings
//
// Throws at import time if either is missing — failing fast at boot is
// preferable to first-request 500s with a confusing stack trace.

import { createClient } from "@supabase/supabase-js"

const url = process.env.SUPABASE_URL
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY

if (!url || !serviceKey) {
  throw new Error(
    "Missing Supabase config. Set SUPABASE_URL and " +
      "SUPABASE_SERVICE_ROLE_KEY in _x/api/.env",
  )
}

export const supabase = createClient(url, serviceKey, {
  auth: { persistSession: false, autoRefreshToken: false },
  global: { headers: { "x-client-info": "lumina-events-api/0.2.0" } },
})

export const CHART_EVENTS_TABLE = "chart_events"
