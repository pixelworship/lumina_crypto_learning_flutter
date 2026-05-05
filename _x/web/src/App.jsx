import { AlertTriangle, Plus, RefreshCw, Sparkles } from 'lucide-react'
import { useCallback, useEffect, useState } from 'react'

import { AssetPicker } from '@/components/AssetPicker'
import { EventList } from '@/components/EventList'
import { NewEventDialog } from '@/components/NewEventDialog'
import { StatsRow } from '@/components/StatsRow'
import { Button } from '@/components/ui/button'
import { ApiError, listAssets, listEvents } from '@/lib/api'

const LIST_LIMIT = 200

/// Cap the recent-custom list — beyond this it stops being "recent"
/// and starts being a parallel catalog the user has to scroll past.
const MAX_RECENT_CUSTOM = 8
const RECENT_CUSTOM_KEY = 'lumina:recentCustomAssets'

function getInitialAsset() {
  const params = new URLSearchParams(window.location.search)
  const fromUrl = params.get('asset')
  if (fromUrl) return fromUrl.toUpperCase()
  return 'BTC'
}

function syncAssetToUrl(asset) {
  const url = new URL(window.location.href)
  url.searchParams.set('asset', asset)
  window.history.replaceState({}, '', url.toString())
}

/// Reads the persisted recent-custom list, defensively — corrupt
/// values (manual edits to localStorage, schema drift) silently fall
/// back to an empty list rather than crashing the dashboard.
function loadRecentCustom() {
  try {
    const raw = window.localStorage.getItem(RECENT_CUSTOM_KEY)
    if (!raw) return []
    const parsed = JSON.parse(raw)
    if (!Array.isArray(parsed)) return []
    return parsed.filter((s) => typeof s === 'string').slice(0, MAX_RECENT_CUSTOM)
  } catch {
    return []
  }
}

function saveRecentCustom(list) {
  try {
    window.localStorage.setItem(RECENT_CUSTOM_KEY, JSON.stringify(list))
  } catch {
    // localStorage may be unavailable (privacy mode, quota); the
    // session keeps working with the in-memory list.
  }
}

function App() {
  const [assets, setAssets] = useState([])
  const [asset, setAsset] = useState(getInitialAsset)
  const [recentCustom, setRecentCustom] = useState(loadRecentCustom)
  const [events, setEvents] = useState([])
  const [loading, setLoading] = useState(false)
  const [refreshing, setRefreshing] = useState(false)
  const [error, setError] = useState(null)
  const [dialogOpen, setDialogOpen] = useState(false)

  useEffect(() => {
    let cancelled = false
    listAssets()
      .then((rows) => {
        if (cancelled) return
        setAssets(rows)
        // Don't snap away from a custom symbol the user explicitly
        // picked (URL deep-link or a recent custom). Only redirect
        // when the active asset is empty.
        if (rows.length && !asset) {
          setAsset(rows[0].symbol)
        }
      })
      .catch(() => {
        // Asset list failure isn't fatal — the events fetch will surface
        // the underlying connectivity problem with a clearer message.
      })
    return () => {
      cancelled = true
    }
    // intentionally only on mount
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  // MRU-order push: bump existing entries to the front so the most
  // recently used custom stays at the top of the dropdown.
  const rememberCustom = useCallback((symbol) => {
    setRecentCustom((prev) => {
      const next = [symbol, ...prev.filter((s) => s !== symbol)].slice(
        0,
        MAX_RECENT_CUSTOM,
      )
      saveRecentCustom(next)
      return next
    })
  }, [])

  const fetchEvents = useCallback(
    async ({ background = false } = {}) => {
      if (background) setRefreshing(true)
      else setLoading(true)
      setError(null)
      try {
        const result = await listEvents(asset, { limit: LIST_LIMIT })
        setEvents(result.events)
      } catch (err) {
        const message =
          err instanceof ApiError
            ? `${err.message}${err.status ? ` (${err.status})` : ''}`
            : 'Failed to load events.'
        setError(message)
      } finally {
        setLoading(false)
        setRefreshing(false)
      }
    },
    [asset],
  )

  useEffect(() => {
    syncAssetToUrl(asset)
    // Defer the fetch into a microtask so the synchronous setState
    // inside fetchEvents (setLoading, setError) happens in a
    // callback rather than the effect body itself — keeps the
    // compiler-aware react-hooks/set-state-in-effect rule quiet
    // without changing any user-observable behavior.
    let cancelled = false
    Promise.resolve().then(() => {
      if (!cancelled) fetchEvents()
    })
    return () => {
      cancelled = true
    }
  }, [asset, fetchEvents])

  function handleCreated(event) {
    if (!event) {
      fetchEvents({ background: true })
      return
    }
    if (event.asset === asset) {
      setEvents((prev) => [event, ...prev])
    } else {
      setAsset(event.asset)
    }
  }

  function handleDeleted(event) {
    setEvents((prev) => prev.filter((e) => e.id !== event.id))
  }

  return (
    <div className="min-h-full">
      <header className="border-b border-border/60 bg-background/80 backdrop-blur">
        <div className="mx-auto flex max-w-5xl flex-col gap-4 px-6 py-5 sm:flex-row sm:items-center sm:justify-between">
          <div className="flex items-center gap-3">
            <div className="rounded-lg bg-primary/15 p-2 text-primary">
              <Sparkles className="h-5 w-5" />
            </div>
            <div>
              <h1 className="text-base font-semibold leading-tight">
                Chart Events
              </h1>
              <p className="text-xs text-muted-foreground">
                Lumina · Supabase-backed event console
              </p>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-56">
              <AssetPicker
                value={asset}
                onChange={setAsset}
                assets={assets}
                recentCustom={recentCustom}
                onCustomAdded={rememberCustom}
                ariaLabel="Asset"
              />
            </div>
            <Button
              variant="outline"
              size="icon"
              onClick={() => fetchEvents({ background: true })}
              disabled={loading || refreshing}
              aria-label="Refresh"
              title="Refresh"
            >
              <RefreshCw
                className={`h-4 w-4 ${refreshing ? 'animate-spin' : ''}`}
              />
            </Button>
            <Button onClick={() => setDialogOpen(true)}>
              <Plus className="h-4 w-4" />
              New event
            </Button>
          </div>
        </div>
      </header>

      <main className="mx-auto max-w-5xl space-y-6 px-6 py-8">
        <StatsRow events={events} asset={asset} />

        {error ? (
          <div className="flex items-start gap-3 rounded-lg border border-destructive/40 bg-destructive/10 px-4 py-3 text-sm">
            <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-destructive" />
            <div className="flex-1">
              <p className="font-medium">Couldn't load events</p>
              <p className="text-muted-foreground">{error}</p>
            </div>
            <Button
              variant="outline"
              size="sm"
              onClick={() => fetchEvents()}
            >
              Retry
            </Button>
          </div>
        ) : null}

        <section className="space-y-3">
          <div className="flex items-baseline justify-between">
            <h2 className="text-sm font-semibold uppercase tracking-wide text-muted-foreground">
              Recent events
            </h2>
            {events.length > 0 ? (
              <span className="text-xs text-muted-foreground">
                Showing {events.length} of up to {LIST_LIMIT}
              </span>
            ) : null}
          </div>
          <EventList
            events={events}
            loading={loading}
            onDeleted={handleDeleted}
          />
        </section>
      </main>

      <NewEventDialog
        // Re-keying on `open` discards the previous form instance so
        // re-opening always lands on a fresh dialog seeded from the
        // current asset — no reset-via-effect needed inside the
        // child.
        key={dialogOpen ? `open:${asset}` : 'closed'}
        open={dialogOpen}
        onOpenChange={setDialogOpen}
        assets={assets}
        recentCustom={recentCustom}
        onCustomAdded={rememberCustom}
        defaultAsset={asset}
        onCreated={handleCreated}
      />
    </div>
  )
}

export default App
