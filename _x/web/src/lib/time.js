// Tiny date helpers — no deps; we only need a relative formatter and
// a friendly absolute formatter for the event list.

const RELATIVE = new Intl.RelativeTimeFormat(undefined, { numeric: 'auto' })
const ABSOLUTE = new Intl.DateTimeFormat(undefined, {
  year: 'numeric',
  month: 'short',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
})
// Year-less variant for inline display next to a relative time.
// Falls back gracefully on dates from prior years (the tooltip still
// shows the full absolute via formatAbsolute).
const SHORT_ABSOLUTE = new Intl.DateTimeFormat(undefined, {
  month: 'short',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
})

export function formatRelative(iso, now = Date.now()) {
  if (!iso) return ''
  const t = new Date(iso).getTime()
  if (!Number.isFinite(t)) return ''
  const diffSec = Math.round((t - now) / 1000)
  const abs = Math.abs(diffSec)
  if (abs < 60) return RELATIVE.format(diffSec, 'second')
  if (abs < 3600) return RELATIVE.format(Math.round(diffSec / 60), 'minute')
  if (abs < 86400) return RELATIVE.format(Math.round(diffSec / 3600), 'hour')
  if (abs < 86400 * 30) {
    return RELATIVE.format(Math.round(diffSec / 86400), 'day')
  }
  if (abs < 86400 * 365) {
    return RELATIVE.format(Math.round(diffSec / (86400 * 30)), 'month')
  }
  return RELATIVE.format(Math.round(diffSec / (86400 * 365)), 'year')
}

export function formatAbsolute(iso) {
  if (!iso) return ''
  const d = new Date(iso)
  if (!Number.isFinite(d.getTime())) return ''
  return ABSOLUTE.format(d)
}

/// Year-less absolute. Pair with [formatRelative] to show
/// "2h ago · May 4, 14:30" — the relative gives at-a-glance recency,
/// the short absolute gives precision without the wall of text.
export function formatShortAbsolute(iso) {
  if (!iso) return ''
  const d = new Date(iso)
  if (!Number.isFinite(d.getTime())) return ''
  return SHORT_ABSOLUTE.format(d)
}

export function dayKey(iso) {
  if (!iso) return ''
  const d = new Date(iso)
  if (!Number.isFinite(d.getTime())) return ''
  return d.toISOString().slice(0, 10)
}
