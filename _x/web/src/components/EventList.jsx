import { ExternalLink, Inbox, Loader2, Trash2 } from 'lucide-react'
import { useState } from 'react'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardTitle } from '@/components/ui/card'
import { ApiError, deleteEvent } from '@/lib/api'
import {
  formatAbsolute,
  formatRelative,
  formatShortAbsolute,
} from '@/lib/time'

export function EventList({ events, loading, onDeleted }) {
  if (loading) {
    return (
      <div className="space-y-3">
        {Array.from({ length: 3 }).map((_, i) => (
          <Card key={i} className="animate-pulse">
            <CardContent className="space-y-3 p-5">
              <div className="h-3 w-24 rounded bg-muted" />
              <div className="h-4 w-2/3 rounded bg-muted" />
              <div className="h-3 w-full rounded bg-muted" />
              <div className="h-3 w-4/5 rounded bg-muted" />
            </CardContent>
          </Card>
        ))}
      </div>
    )
  }

  if (events.length === 0) {
    return (
      <Card className="border-dashed">
        <CardContent className="flex flex-col items-center justify-center gap-3 py-16 text-center">
          <div className="rounded-full bg-muted p-3">
            <Inbox className="h-6 w-6 text-muted-foreground" />
          </div>
          <CardTitle className="text-base">No events yet</CardTitle>
          <CardDescription className="max-w-sm">
            Create the first one with the “New event” button. It will be
            available immediately to any client reading this asset.
          </CardDescription>
        </CardContent>
      </Card>
    )
  }

  return (
    <div className="space-y-3">
      {events.map((event) => (
        <EventRow key={event.id} event={event} onDeleted={onDeleted} />
      ))}
    </div>
  )
}

function EventRow({ event, onDeleted }) {
  const [deleting, setDeleting] = useState(false)
  const [error, setError] = useState(null)

  async function handleDelete() {
    const ok = window.confirm(
      `Delete "${event.title}"? This cannot be undone.`,
    )
    if (!ok) return
    setDeleting(true)
    setError(null)
    try {
      await deleteEvent(event.id)
      onDeleted?.(event)
    } catch (err) {
      const message =
        err instanceof ApiError
          ? `${err.message}${err.status ? ` (${err.status})` : ''}`
          : 'Failed to delete event.'
      setError(message)
      setDeleting(false)
    }
  }

  return (
    <Card
      className={`group transition-colors hover:border-border ${
        deleting ? 'opacity-60' : ''
      }`}
    >
      <CardContent className="space-y-3 p-5">
        <div className="flex items-center justify-between gap-3">
          <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
            <Badge>{event.asset}</Badge>
            <span
              className="text-xs text-muted-foreground"
              title={formatAbsolute(event.timestamp)}
            >
              {formatRelative(event.timestamp)}
            </span>
            <span aria-hidden className="text-muted-foreground/40">
              ·
            </span>
            <time
              dateTime={event.timestamp}
              className="text-xs tabular-nums text-muted-foreground/80"
              title={formatAbsolute(event.timestamp)}
            >
              {formatShortAbsolute(event.timestamp)}
            </time>
          </div>
          <div className="flex items-center gap-2">
            <span className="text-[11px] uppercase tracking-wide text-muted-foreground/70">
              #{event.id}
            </span>
            <Button
              variant="ghost"
              size="icon"
              onClick={handleDelete}
              disabled={deleting}
              aria-label={`Delete event #${event.id}`}
              title="Delete event"
              className="h-8 w-8 text-muted-foreground opacity-0 transition-opacity hover:text-destructive focus-visible:opacity-100 group-hover:opacity-100"
            >
              {deleting ? (
                <Loader2 className="h-4 w-4 animate-spin" />
              ) : (
                <Trash2 className="h-4 w-4" />
              )}
            </Button>
          </div>
        </div>
        <h3 className="text-base font-semibold leading-tight">
          {event.title}
        </h3>
        {event.body ? (
          <p className="text-sm leading-relaxed text-muted-foreground">
            {event.body}
          </p>
        ) : null}
        {event.link ? (
          <a
            href={event.link}
            target="_blank"
            rel="noreferrer"
            className="inline-flex items-center gap-1.5 text-xs font-medium text-primary hover:underline"
          >
            <ExternalLink className="h-3.5 w-3.5" />
            <span className="max-w-[28ch] truncate">{event.link}</span>
          </a>
        ) : null}
        {error ? (
          <p className="rounded-md border border-destructive/40 bg-destructive/10 px-3 py-2 text-xs text-destructive-foreground">
            {error}
          </p>
        ) : null}
      </CardContent>
    </Card>
  )
}
