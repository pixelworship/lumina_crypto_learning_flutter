import { formatResponse } from "./common/formatResponse.mjs"
import {
  CHART_EVENTS_TABLE,
  EVENT_COLUMNS,
  shapeEvent,
  supabase,
} from "./common/supabase.mjs"
import { isValidAssetSymbol } from "./common/assets.mjs"
import {
  INVALID,
  isLikelyUrl,
  parseTimestampField,
  readJsonBody,
  stringParam,
} from "./common/parsers.mjs"
import { recordLatestTimestamp } from "./common/eventCache.mjs"

/**
 * POST /v1/events
 * Body: { asset, title, body?, link?, created_at? }
 *
 * Inserts a single row into `chart_events`. `created_at` is optional —
 * absent / null / empty falls through to the column's default `now()`,
 * which lets the dashboard back- or future-date events without dropping
 * into the SQL editor. We intentionally accept any 1-16 char A-Z/0-9
 * ticker (catalog membership is a UI affordance, not a gate).
 */
export const handler = async (event) => {
  const parsed = readJsonBody(event)
  if (!parsed.ok) {
    return formatResponse(
      400,
      { error: "invalid_json", message: "Request body is not valid JSON." },
      { event },
    )
  }

  const body = parsed.body ?? {}
  const assetRaw = stringParam(body.asset)
  const title = stringParam(body.title)
  const bodyText = stringParam(body.body)
  const link = stringParam(body.link)

  if (!assetRaw) {
    return formatResponse(
      400,
      { error: "missing_field", message: "`asset` is required." },
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
  if (!title) {
    return formatResponse(
      400,
      { error: "missing_field", message: "`title` is required." },
      { event },
    )
  }
  if (link && !isLikelyUrl(link)) {
    return formatResponse(
      400,
      {
        error: "invalid_field",
        message: "`link` must be an http(s) URL.",
        link,
      },
      { event },
    )
  }

  const createdAt = parseTimestampField(body.created_at)
  if (createdAt === INVALID) {
    return formatResponse(
      400,
      {
        error: "invalid_created_at",
        message: "`created_at` must be ISO-8601 or epoch milliseconds.",
        created_at: body.created_at,
      },
      { event },
    )
  }

  const insertRow = {
    asset,
    title,
    body: bodyText,
    link,
  }
  if (createdAt) insertRow.created_at = createdAt.toISOString()

  const { data, error } = await supabase
    .from(CHART_EVENTS_TABLE)
    .insert(insertRow)
    .select(EVENT_COLUMNS)
    .single()

  if (error) {
    console.error("[createEvent] supabase error:", error)
    return formatResponse(
      502,
      {
        error: "supabase_insert_failed",
        message: error.message,
      },
      { event },
    )
  }

  // Write-through cache invalidation: the row we just inserted is now
  // the newest event for this asset (assuming `created_at` defaulted to
  // `now()`, or was an explicit forward-dated value). Bumping the
  // watermark here keeps `/v1/events/since` cache hits correct without
  // having to wait for the TTL to expire.
  recordLatestTimestamp(asset, data?.created_at).catch((err) => {
    console.error("[createEvent] cache update failed:", err)
  })

  return formatResponse(
    201,
    {
      asset,
      from: null,
      to: null,
      count: 1,
      events: [shapeEvent(data)],
    },
    { event },
  )
}
