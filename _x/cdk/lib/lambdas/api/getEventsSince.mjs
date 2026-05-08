import { formatResponse } from "./common/formatResponse.mjs"
import {
  CHART_EVENTS_TABLE,
  EVENT_COLUMNS,
  shapeEvent,
  supabase,
} from "./common/supabase.mjs"
import { isValidAssetSymbol } from "./common/assets.mjs"
import {
  parseDateParam,
  parseIntParam,
  stringParam,
} from "./common/parsers.mjs"
import {
  canSkipSupabase,
  getCacheEntry,
  recordLatestTimestamp,
} from "./common/eventCache.mjs"

const DEFAULT_DELTA_LIMIT = 500
const MAX_LIMIT = 1000

/**
 * GET /v1/events/since?asset=BTC&since=ISO&limit=500
 *
 * Delta query — returns events strictly newer than `since`, ascending.
 *
 * Strict-greater-than (vs. >=) means the client can use the timestamp
 * of the last event it received as the next cursor without an off-by-one
 * fudge: subsequent calls only see events created later. The default
 * limit is intentionally higher than the window query so a backgrounded
 * client can catch up in a single round-trip after coming back to the
 * foreground.
 */
export const handler = async (event) => {
  const qs = event?.queryStringParameters ?? {}
  const assetRaw = stringParam(qs.asset)
  if (!assetRaw) {
    return formatResponse(
      400,
      {
        error: "missing_query_param",
        message: "Pass `?asset=BTC&since=ISO`.",
      },
      { event },
    )
  }

  const asset = assetRaw.toUpperCase()
  if (!isValidAssetSymbol(asset)) {
    return formatResponse(
      400,
      {
        error: "invalid_asset",
        message:
          "`asset` must be 1-16 characters of A-Z / 0-9. " +
          "See GET /v1/assets for the recommended catalog.",
        asset,
      },
      { event },
    )
  }

  const since = parseDateParam(qs.since)
  if (!since) {
    return formatResponse(
      400,
      {
        error: "missing_query_param",
        message: "`since` is required (ISO-8601 timestamp or epoch ms).",
      },
      { event },
    )
  }

  const limit = parseIntParam(qs.limit, DEFAULT_DELTA_LIMIT, 1, MAX_LIMIT)

  // Cache fast path. The Flutter chart re-asks this endpoint once per
  // second per mounted chart; ~99% of the time the answer is "nothing
  // new". We skip Supabase entirely when the cache is fresh and the
  // caller's cursor is already at-or-past our high-watermark.
  const cacheEntry = await getCacheEntry(asset)
  if (canSkipSupabase(cacheEntry, since)) {
    console.log(
      `[getEventsSince] cache hit asset=${asset} since=${since.toISOString()} ` +
        `latest=${cacheEntry.latestEventTimestamp}`,
    )
    return formatResponse(
      200,
      {
        asset,
        since: since.toISOString(),
        count: 0,
        events: [],
        cached: true,
      },
      { event },
    )
  }

  const { data, error } = await supabase
    .from(CHART_EVENTS_TABLE)
    .select(EVENT_COLUMNS)
    .eq("asset", asset)
    .gt("created_at", since.toISOString())
    .order("created_at", { ascending: true })
    .limit(limit)

  if (error) {
    console.error("[getEventsSince] supabase error:", error)
    return formatResponse(
      502,
      {
        error: "supabase_query_failed",
        message: error.message,
      },
      { event },
    )
  }

  const events = (data ?? []).map(shapeEvent)

  // Update the cache so the next caller can short-circuit.
  //
  // - Some events returned ⇒ bump to the newest one we observed.
  // - Zero events returned ⇒ bump to `since` itself: we just confirmed
  //   nothing exists with `created_at > since`, so future polls with
  //   the same (or later) cursor are safe to short-circuit. Within
  //   `EVENT_CACHE_TTL_SECONDS` this trades a tiny bit of staleness on
  //   out-of-band inserts for a steady-state savings of one Supabase
  //   query per poll. Over the TTL, cache refreshes anyway.
  const newestSeen = events.length
    ? events[events.length - 1].timestamp
    : since.toISOString()
  recordLatestTimestamp(asset, newestSeen).catch((err) => {
    console.error("[getEventsSince] cache update failed:", err)
  })

  return formatResponse(
    200,
    {
      asset,
      since: since.toISOString(),
      count: events.length,
      events,
    },
    { event },
  )
}
