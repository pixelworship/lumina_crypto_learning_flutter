// Thin wrapper around the `_x/api` Express server. The web app never
// talks to Supabase directly — the service-role key lives only in the
// API process, so all reads and writes go through HTTP.
//
// Configure the base URL with VITE_API_BASE_URL (see .env).

const BASE = (
  import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:4001'
).replace(/\/+$/, '')

async function request(path, init) {
  let res
  try {
    res = await fetch(`${BASE}${path}`, init)
  } catch (e) {
    throw new ApiError(
      `Network error contacting ${BASE}${path}: ${e.message}`,
      0,
      null,
    )
  }
  let payload = null
  const ct = res.headers.get('content-type') ?? ''
  if (ct.includes('application/json')) {
    try {
      payload = await res.json()
    } catch {
      payload = null
    }
  }
  if (!res.ok) {
    const message =
      payload?.message ?? payload?.error ?? `Request failed (${res.status})`
    throw new ApiError(message, res.status, payload)
  }
  return payload
}

export class ApiError extends Error {
  constructor(message, status, payload) {
    super(message)
    this.name = 'ApiError'
    this.status = status
    this.payload = payload
  }
}

export async function listAssets() {
  const data = await request('/v1/assets')
  return data?.assets ?? []
}

export async function listEvents(asset, { from, to, limit } = {}) {
  const params = new URLSearchParams({ asset })
  if (from) params.set('from', from)
  if (to) params.set('to', to)
  if (limit) params.set('limit', String(limit))
  const data = await request(`/v1/events?${params.toString()}`)
  return {
    asset: data?.asset ?? asset,
    from: data?.from ?? null,
    to: data?.to ?? null,
    count: data?.count ?? 0,
    events: data?.events ?? [],
  }
}

export async function createEvent({ asset, title, body, link, createdAt }) {
  const payload = { asset, title, body, link }
  // Only include `created_at` when the caller explicitly chose a
  // timestamp; otherwise let the server's column default apply.
  if (createdAt) payload.created_at = createdAt
  const data = await request('/v1/events', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  })
  return data?.events?.[0] ?? null
}

export async function deleteEvent(id) {
  const data = await request(`/v1/events/${encodeURIComponent(id)}`, {
    method: 'DELETE',
  })
  return {
    deleted: data?.deleted ?? true,
    id: data?.id ?? id,
    event: data?.event ?? null,
  }
}
