// Single shared Supabase client for the events lambdas.
//
// Uses the service-role key, so all queries bypass Row Level Security.
// The key only ever lives inside the Lambda execution environment — it
// never reaches the browser, so this is safe even though the API itself
// is publicly reachable.
//
// Throws at import time if either var is missing — failing fast at boot
// is preferable to first-request 500s with a confusing stack trace.

import { createClient } from "@supabase/supabase-js"

const url = process.env.SUPABASE_URL
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY

if (!url || !serviceKey) {
  throw new Error(
    "Missing Supabase config. Set SUPABASE_URL and " +
      "SUPABASE_SERVICE_ROLE_KEY in the lambda environment.",
  )
}

export const supabase = createClient(url, serviceKey, {
  auth: { persistSession: false, autoRefreshToken: false },
  global: { headers: { "x-client-info": "lumina-events-api/1.0.0" } },
})

export const CHART_EVENTS_TABLE = "chart_events"

export const EVENT_COLUMNS = "id, created_at, asset, title, body, link"

export function shapeEvent(row) {
  return {
    id: row.id,
    asset: row.asset,
    timestamp: row.created_at,
    title: row.title,
    body: row.body ?? null,
    link: row.link ?? null,
  }
}
