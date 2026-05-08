import { formatResponse } from "./common/formatResponse.mjs"
import {
  CHART_EVENTS_TABLE,
  EVENT_COLUMNS,
  shapeEvent,
  supabase,
} from "./common/supabase.mjs"

/**
 * DELETE /v1/events/{key}
 *
 * `{key}` is shared with the GET handler (which interprets it as an
 * asset symbol) — here it's the numeric event id. Returns 404 when no
 * row matches so the dashboard can distinguish "you tried to delete a
 * stale id" from "request was malformed".
 */
export const handler = async (event) => {
  const idRaw = event?.pathParameters?.key
  if (typeof idRaw !== "string" || !idRaw) {
    return formatResponse(
      400,
      { error: "missing_path_param", message: "Path param `key` is required." },
      { event },
    )
  }

  const id = Math.floor(Number(idRaw))
  if (!Number.isFinite(id) || id <= 0 || !/^\d+$/.test(idRaw)) {
    return formatResponse(
      400,
      {
        error: "invalid_id",
        message: "`id` must be a positive integer.",
        id: idRaw,
      },
      { event },
    )
  }

  const { data, error } = await supabase
    .from(CHART_EVENTS_TABLE)
    .delete()
    .eq("id", id)
    .select(EVENT_COLUMNS)
    .maybeSingle()

  if (error) {
    console.error("[deleteEvent] supabase error:", error)
    return formatResponse(
      502,
      {
        error: "supabase_delete_failed",
        message: error.message,
      },
      { event },
    )
  }

  if (!data) {
    return formatResponse(
      404,
      {
        error: "event_not_found",
        message: `No event with id ${id}.`,
        id,
      },
      { event },
    )
  }

  return formatResponse(
    200,
    {
      deleted: true,
      id,
      event: shapeEvent(data),
    },
    { event },
  )
}
