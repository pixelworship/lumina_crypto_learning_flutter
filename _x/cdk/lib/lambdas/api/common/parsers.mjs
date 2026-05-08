// Shared input-parsing helpers used across the events lambdas. Pulled
// out of the route handlers so the validation behavior stays identical
// across listEvents / getEventsSince / getEventsByAsset / createEvent.

/** Coerces an API Gateway query/path value into a non-empty trimmed string. */
export function stringParam(v) {
  if (typeof v !== "string") return null
  const trimmed = v.trim()
  return trimmed.length > 0 ? trimmed : null
}

/**
 * Accepts ISO-8601 strings or epoch milliseconds (numeric string).
 * Returns a Date or null. Garbage in ⇒ null (callers decide whether
 * that's a 400 or a fall-through default).
 */
export function parseDateParam(v) {
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
 * Tri-state sentinel for parsing the optional POST `created_at` field —
 * tri-state because we need to distinguish "absent" (use the column
 * default) from "supplied but unparseable" (reject with 400).
 *   missing/null/empty → null
 *   valid date         → Date
 *   garbled            → INVALID (referentially unique)
 */
export const INVALID = Symbol("invalid_timestamp")

export function parseTimestampField(v) {
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

export function parseIntParam(v, fallback, lo, hi) {
  if (typeof v !== "string") return fallback
  const n = Math.floor(Number(v))
  if (!Number.isFinite(n)) return fallback
  return Math.min(hi, Math.max(lo, n))
}

export function isLikelyUrl(s) {
  try {
    const u = new URL(s)
    return u.protocol === "http:" || u.protocol === "https:"
  } catch {
    return false
  }
}

/**
 * Reads (and JSON-parses) the body off an API Gateway event, transparently
 * handling base64 encoding. Returns `{ ok: true, body }` on success or
 * `{ ok: false, error }` on JSON failure so callers can short-circuit
 * with a 400.
 */
export function readJsonBody(event) {
  const raw = event?.isBase64Encoded
    ? Buffer.from(event.body ?? "", "base64").toString("utf8")
    : event?.body ?? ""
  if (!raw) return { ok: true, body: {} }
  try {
    return { ok: true, body: JSON.parse(raw) }
  } catch (err) {
    return { ok: false, error: err }
  }
}
