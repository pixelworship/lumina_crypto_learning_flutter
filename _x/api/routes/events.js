// /v1/events — Supabase-backed CRUD for the `chart_events` table.
//
// `asset` is gated on FORMAT only (`^[A-Z0-9]{1,16}$`), not on
// catalog membership — `/v1/assets` is just the recommended set the
// UI surfaces in dropdowns. Custom tickers (e.g. "CYAN") are first-
// class so the dashboard's "Other..." flow works without any allow-
// list maintenance here.
//
// Two read shapes intentionally split by URL so callers can't
// accidentally mix "fetch a window" with "tail what's new":
//
//   GET    /v1/events?asset=BTC&from=ISO&to=ISO&limit=200
//          → window query. Both `from` and `to` are optional. Used by
//            the web dashboard's list view and by the Flutter chart's
//            initial load + history-extend paths. Sorted descending
//            (most-recent first) for human-readable list UIs; the
//            chart re-sorts ascending client-side.
//
//   GET    /v1/events/since?asset=BTC&since=ISO&limit=500
//          → delta query. `since` is REQUIRED and EXCLUSIVE
//            (`created_at > since`). Sorted ascending so callers can
//            merge directly without a re-sort, and uses a higher
//            default limit so a backgrounded client can catch up in
//            one round-trip when it returns to the foreground.
//
//   GET    /v1/events/:asset
//          → 24h shortcut for ad-hoc inspection.
//
//   POST   /v1/events             { asset, title, body?, link? }
//   DELETE /v1/events/:id
//
// Response envelope (kept stable for the Flutter client and any other
// downstream consumer):
//
//   {
//     "asset":  "BTC",
//     "from":   "..." | null,    // window queries
//     "to":     "..." | null,    // window queries
//     "since":  "..." | null,    // delta queries
//     "count":  N,
//     "events": [
//       { "id": 42, "asset": "BTC", "timestamp": "...", "title": "...",
//         "body":  "...", "link": "https://..." | null }
//     ]
//   }
//
// `timestamp` is just `created_at` re-aliased so existing client code
// that parsed `event.timestamp` keeps working.

import { Router } from "express"

import { isValidAssetSymbol } from "../data/assets.js"
import { CHART_EVENTS_TABLE, supabase } from "../lib/supabaseClient.js"

const ONE_DAY_MS = 24 * 60 * 60 * 1000
const DEFAULT_LIMIT = 200
const DEFAULT_DELTA_LIMIT = 500
const MAX_LIMIT = 1000

export const eventsRouter = Router()

eventsRouter.get("/", async (req, res) => {
  const asset = stringParam(req.query.asset)
  if (!asset) {
    return res.status(400).json({
      error: "missing_query_param",
      message: "Pass `?asset=BTC` (or use /v1/events/:asset).",
    })
  }
  return handleListEvents(req, res, asset, { defaultWindow: false })
})

// IMPORTANT: register `/since` before `/:asset` so Express doesn't
// route a delta call to the 24h shortcut with `asset = "since"`.
eventsRouter.get("/since", async (req, res) => {
  const asset = stringParam(req.query.asset)
  if (!asset) {
    return res.status(400).json({
      error: "missing_query_param",
      message: "Pass `?asset=BTC&since=ISO`.",
    })
  }
  return handleEventsSince(req, res, asset)
})

eventsRouter.get("/:asset", async (req, res) => {
  return handleListEvents(req, res, req.params.asset, { defaultWindow: true })
})

eventsRouter.post("/", async (req, res) => {
  const body = req.body ?? {}
  const assetRaw = stringParam(body.asset)
  const title = stringParam(body.title)
  const bodyText = stringParam(body.body)
  const link = stringParam(body.link)

  if (!assetRaw) {
    return res.status(400).json({
      error: "missing_field",
      message: "`asset` is required.",
    })
  }
  const asset = assetRaw.toUpperCase()
  if (!isValidAssetSymbol(asset)) {
    return res.status(400).json({
      error: "invalid_asset",
      message:
        "`asset` must be 1-16 characters of A-Z / 0-9. " +
        "See GET /v1/assets for the recommended catalog.",
      asset,
    })
  }
  if (!title) {
    return res.status(400).json({
      error: "missing_field",
      message: "`title` is required.",
    })
  }
  if (link && !isLikelyUrl(link)) {
    return res.status(400).json({
      error: "invalid_field",
      message: "`link` must be an http(s) URL.",
      link,
    })
  }

  // Optional override for the `created_at` column. Lets the dashboard
  // backdate (or future-date) events without dropping into the SQL
  // editor — useful when annotating historical chart moves.
  // Accepts ISO-8601 strings or epoch milliseconds (number or
  // numeric string). Absent / null / empty falls through to the
  // column's default `now()`.
  const createdAt = parseTimestampField(body.created_at)
  if (createdAt === INVALID) {
    return res.status(400).json({
      error: "invalid_created_at",
      message: "`created_at` must be ISO-8601 or epoch milliseconds.",
      created_at: body.created_at,
    })
  }

  const insertRow = {
    asset,
    title,
    body: bodyText,
    link: link,
  }
  if (createdAt) insertRow.created_at = createdAt.toISOString()

  const { data, error } = await supabase
    .from(CHART_EVENTS_TABLE)
    .insert(insertRow)
    .select("id, created_at, asset, title, body, link")
    .single()

  if (error) {
    process.stderr.write(`[events:POST] supabase error: ${error.message}\n`)
    return res.status(502).json({
      error: "supabase_insert_failed",
      message: error.message,
    })
  }

  return res.status(201).json({
    asset,
    from: null,
    to: null,
    count: 1,
    events: [shapeEvent(data)],
  })
})

eventsRouter.delete("/:id", async (req, res) => {
  const idRaw = req.params.id
  const id = Math.floor(Number(idRaw))
  if (!Number.isFinite(id) || id <= 0 || !/^\d+$/.test(idRaw)) {
    return res.status(400).json({
      error: "invalid_id",
      message: "`id` must be a positive integer.",
      id: idRaw,
    })
  }

  const { data, error } = await supabase
    .from(CHART_EVENTS_TABLE)
    .delete()
    .eq("id", id)
    .select("id, created_at, asset, title, body, link")
    .maybeSingle()

  if (error) {
    process.stderr.write(`[events:DELETE] supabase error: ${error.message}\n`)
    return res.status(502).json({
      error: "supabase_delete_failed",
      message: error.message,
    })
  }

  if (!data) {
    return res.status(404).json({
      error: "event_not_found",
      message: `No event with id ${id}.`,
      id,
    })
  }

  return res.json({
    deleted: true,
    id,
    event: shapeEvent(data),
  })
})

async function handleListEvents(req, res, assetRaw, { defaultWindow }) {
  const asset = assetRaw.toUpperCase()
  if (!isValidAssetSymbol(asset)) {
    return res.status(400).json({
      error: "invalid_asset",
      message:
        "`asset` must be 1-16 characters of A-Z / 0-9. " +
        "See GET /v1/assets for the recommended catalog.",
      asset,
    })
  }

  const now = new Date()
  const to = parseDateParam(req.query.to)
  const from = parseDateParam(req.query.from)

  // /:asset shortcut defaults to the last 24h. The explicit ?asset=
  // form does NOT — callers that want the firehose can omit both.
  let effectiveFrom = from
  let effectiveTo = to
  if (defaultWindow) {
    effectiveTo = effectiveTo ?? now
    effectiveFrom = effectiveFrom ?? new Date(effectiveTo.getTime() - ONE_DAY_MS)
  }

  if (effectiveFrom && effectiveTo && effectiveTo.getTime() <= effectiveFrom.getTime()) {
    return res.status(400).json({
      error: "invalid_range",
      message: "`to` must be strictly after `from`.",
      from: effectiveFrom.toISOString(),
      to: effectiveTo.toISOString(),
    })
  }

  const limit = parseIntParam(req.query.limit, DEFAULT_LIMIT, 1, MAX_LIMIT)

  let query = supabase
    .from(CHART_EVENTS_TABLE)
    .select("id, created_at, asset, title, body, link")
    .eq("asset", asset)
    .order("created_at", { ascending: false })
    .limit(limit)

  if (effectiveFrom) query = query.gte("created_at", effectiveFrom.toISOString())
  if (effectiveTo) query = query.lte("created_at", effectiveTo.toISOString())

  const { data, error } = await query
  if (error) {
    process.stderr.write(`[events:GET] supabase error: ${error.message}\n`)
    return res.status(502).json({
      error: "supabase_query_failed",
      message: error.message,
    })
  }

  const events = (data ?? []).map(shapeEvent)
  return res.json({
    asset,
    from: effectiveFrom ? effectiveFrom.toISOString() : null,
    to: effectiveTo ? effectiveTo.toISOString() : null,
    count: events.length,
    events,
  })
}

// Delta query — returns events strictly newer than `since`, ascending.
//
// Strict-greater-than (vs. >=) means the client can use the timestamp
// of the last event it received as the next cursor without an off-by-
// one fudge: subsequent calls only see events created later.
async function handleEventsSince(req, res, assetRaw) {
  const asset = assetRaw.toUpperCase()
  if (!isValidAssetSymbol(asset)) {
    return res.status(400).json({
      error: "invalid_asset",
      message:
        "`asset` must be 1-16 characters of A-Z / 0-9. " +
        "See GET /v1/assets for the recommended catalog.",
      asset,
    })
  }

  const since = parseDateParam(req.query.since)
  if (!since) {
    return res.status(400).json({
      error: "missing_query_param",
      message: "`since` is required (ISO-8601 timestamp or epoch ms).",
    })
  }

  const limit = parseIntParam(
    req.query.limit,
    DEFAULT_DELTA_LIMIT,
    1,
    MAX_LIMIT,
  )

  const { data, error } = await supabase
    .from(CHART_EVENTS_TABLE)
    .select("id, created_at, asset, title, body, link")
    .eq("asset", asset)
    .gt("created_at", since.toISOString())
    .order("created_at", { ascending: true })
    .limit(limit)

  if (error) {
    process.stderr.write(`[events:since] supabase error: ${error.message}\n`)
    return res.status(502).json({
      error: "supabase_query_failed",
      message: error.message,
    })
  }

  const events = (data ?? []).map(shapeEvent)
  return res.json({
    asset,
    since: since.toISOString(),
    count: events.length,
    events,
  })
}

function shapeEvent(row) {
  return {
    id: row.id,
    asset: row.asset,
    timestamp: row.created_at,
    title: row.title,
    body: row.body ?? null,
    link: row.link ?? null,
  }
}

function stringParam(v) {
  if (typeof v !== "string") return null
  const trimmed = v.trim()
  return trimmed.length > 0 ? trimmed : null
}

function parseDateParam(v) {
  if (typeof v !== "string") return null
  const trimmed = v.trim()
  if (!trimmed) return null
  const asInt = Number(trimmed)
  if (Number.isFinite(asInt) && /^\d+$/.test(trimmed)) {
    const d = new Date(asInt)
    return Number.isFinite(d.getTime()) ? d : null
  }
  const d = new Date(trimmed)
  return Number.isFinite(d.getTime()) ? d : null
}

/**
 * Tri-state sentinel for parsing the optional POST `created_at`
 * field — tri-state because we need to distinguish "absent" (use the
 * column default) from "supplied but unparseable" (reject with 400).
 *   missing/null/empty → null
 *   valid date         → Date
 *   garbled            → INVALID (referentially unique)
 */
const INVALID = Symbol("invalid_timestamp")

function parseTimestampField(v) {
  if (v === undefined || v === null) return null
  if (typeof v === "number") {
    if (!Number.isFinite(v)) return INVALID
    const d = new Date(v)
    return Number.isFinite(d.getTime()) ? d : INVALID
  }
  if (typeof v === "string") {
    if (v.trim() === "") return null
    const parsed = parseDateParam(v)
    return parsed ?? INVALID
  }
  return INVALID
}

function parseIntParam(v, fallback, lo, hi) {
  if (typeof v !== "string") return fallback
  const n = Math.floor(Number(v))
  if (!Number.isFinite(n)) return fallback
  return Math.min(hi, Math.max(lo, n))
}

function isLikelyUrl(s) {
  try {
    const u = new URL(s)
    return u.protocol === "http:" || u.protocol === "https:"
  } catch {
    return false
  }
}
