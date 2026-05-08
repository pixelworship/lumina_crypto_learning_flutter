import { formatResponse } from "./common/formatResponse.mjs"
import { SUPPORTED_ASSETS } from "./common/assets.mjs"

/**
 * GET /v1/assets
 *
 * Returns the recommended catalog of asset symbols the events API knows
 * about. Mirrors the Flutter app's static asset list — the dashboard's
 * dropdown and the chart's filters both populate from this endpoint.
 *
 * Catalog membership is a UI affordance, NOT an authorization check:
 * `POST /v1/events` accepts any 1-16 char A-Z/0-9 ticker (so the
 * dashboard's "Other..." flow works for tickers we haven't blessed yet).
 */
export const handler = async (event) => {
  return formatResponse(
    200,
    {
      count: SUPPORTED_ASSETS.length,
      assets: SUPPORTED_ASSETS,
    },
    { event },
  )
}
