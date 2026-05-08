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
  getCacheEntry,
  recordLatestTimestamp,
} from "./common/eventCache.mjs"

const DEFAULT_LIMIT = 200
const MAX_LIMIT = 1000

/**
 * GET /v1/events?asset=BTC&from=ISO&to=ISO&limit=200
 *
 * Window query — both `from` and `to` are optional. Sorted descending
 * (most-recent first) for human-readable list UIs; the Flutter chart
 * re-sorts ascending client-side.
 */
export const handler = async (event) => {
  const qs = event?.queryStringParameters ?? {}
  const assetRaw = stringParam(qs.asset)
  if (!assetRaw) {
    return formatResponse(
      400,
      {
        error: "missing_query_param",
        message: "Pass `?asset=BTC` (or use /v1/events/{asset}).",
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

  const from = parseDateParam(qs.from)
  const to = parseDateParam(qs.to)

  if (from && to && to.getTime() <= from.getTime()) {
    return formatResponse(
      400,
      {
        error: "invalid_range",
        message: "`to` must be strictly after `from`.",
        from: from.toISOString(),
        to: to.toISOString(),
      },
      { event },
    )
  }

  const limit = parseIntParam(qs.limit, DEFAULT_LIMIT, 1, MAX_LIMIT)

  // Cache fast path. We can only short-circuit when the caller pinned
  // the lower bound of the window (`from`) AND we know the newest
  // event predates it — then the window can't possibly contain
  // anything. Without `from` the window is open-ended backwards, so
  // we have to query Supabase even when nothing is "new".
  if (from) {
    const cacheEntry = await getCacheEntry(asset)
    if (
      cacheEntry?.isFresh &&
      Date.parse(cacheEntry.latestEventTimestamp) < from.getTime()
    ) {
      console.log(
        `[listEvents] cache hit asset=${asset} from=${from.toISOString()} ` +
          `latest=${cacheEntry.latestEventTimestamp}`,
      )
      return formatResponse(
        200,
        {
          asset,
          from: from.toISOString(),
          to: to ? to.toISOString() : null,
          count: 0,
          events: [],
          cached: true,
        },
        { event },
      )
    }
  }

  let query = supabase
    .from(CHART_EVENTS_TABLE)
    .select(EVENT_COLUMNS)
    .eq("asset", asset)
    .order("created_at", { ascending: false })
    .limit(limit)

  if (from) query = query.gte("created_at", from.toISOString())
  if (to) query = query.lte("created_at", to.toISOString())

  const { data, error } = await query
  if (error) {
    console.error("[listEvents] supabase error:", error)
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

  // Refresh the cache with whatever's newest in the window we just
  // pulled. `events[0]` is the newest because the query orders DESC.
  // We deliberately don't write when 0 rows came back — a window
  // returning empty doesn't tell us anything reliable about events
  // OUTSIDE the window, so the watermark is left to the polling path
  // (and the TTL) to maintain.
  if (events.length) {
    recordLatestTimestamp(asset, events[0].timestamp).catch((err) => {
      console.error("[listEvents] cache update failed:", err)
    })
  }

  return formatResponse(
    200,
    {
      asset,
      from: from ? from.toISOString() : null,
      to: to ? to.toISOString() : null,
      count: events.length,
      events,
    },
    { event },
  )
}
