import { formatResponse } from "./common/formatResponse.mjs"
import {
  CHART_EVENTS_TABLE,
  EVENT_COLUMNS,
  shapeEvent,
  supabase,
} from "./common/supabase.mjs"
import { isValidAssetSymbol } from "./common/assets.mjs"
import { parseIntParam } from "./common/parsers.mjs"
import {
  getCacheEntry,
  recordLatestTimestamp,
} from "./common/eventCache.mjs"

const ONE_DAY_MS = 24 * 60 * 60 * 1000
const DEFAULT_LIMIT = 200
const MAX_LIMIT = 1000

/**
 * GET /v1/events/{key}
 *
 * 24h shortcut for ad-hoc inspection. Path param `{key}` is interpreted
 * as the asset symbol — sibling DELETE handler interprets the same param
 * as an event id. Using a shared `{key}` resource keeps API Gateway
 * happy (path-parameter names must match across methods on a resource).
 */
export const handler = async (event) => {
  const key = event?.pathParameters?.key
  if (typeof key !== "string" || !key) {
    return formatResponse(
      400,
      { error: "missing_path_param", message: "Path param `key` is required." },
      { event },
    )
  }

  const asset = key.toUpperCase()
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

  const qs = event?.queryStringParameters ?? {}
  const limit = parseIntParam(qs.limit, DEFAULT_LIMIT, 1, MAX_LIMIT)

  const now = new Date()
  const from = new Date(now.getTime() - ONE_DAY_MS)

  // Cache fast path. If the cache says the newest event for this asset
  // predates our 24h window, skip Supabase — the window can't contain
  // anything. Quiet assets (no recent events) hit this every time.
  const cacheEntry = await getCacheEntry(asset)
  if (
    cacheEntry?.isFresh &&
    Date.parse(cacheEntry.latestEventTimestamp) < from.getTime()
  ) {
    console.log(
      `[getEventsByAsset] cache hit asset=${asset} from=${from.toISOString()} ` +
        `latest=${cacheEntry.latestEventTimestamp}`,
    )
    return formatResponse(
      200,
      {
        asset,
        from: from.toISOString(),
        to: now.toISOString(),
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
    .gte("created_at", from.toISOString())
    .lte("created_at", now.toISOString())
    .order("created_at", { ascending: false })
    .limit(limit)

  if (error) {
    console.error("[getEventsByAsset] supabase error:", error)
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

  if (events.length) {
    recordLatestTimestamp(asset, events[0].timestamp).catch((err) => {
      console.error("[getEventsByAsset] cache update failed:", err)
    })
  }

  return formatResponse(
    200,
    {
      asset,
      from: from.toISOString(),
      to: now.toISOString(),
      count: events.length,
      events,
    },
    { event },
  )
}
