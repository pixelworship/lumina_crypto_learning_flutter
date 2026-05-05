import { Loader2 } from 'lucide-react'
import { useState } from 'react'

import { AssetPicker } from '@/components/AssetPicker'
import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogBody,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { ApiError, createEvent } from '@/lib/api'

export function NewEventDialog({
  open,
  onOpenChange,
  assets,
  recentCustom = [],
  onCustomAdded,
  defaultAsset,
  onCreated,
}) {
  // Form state initializes once from props. The parent re-keys this
  // dialog on `open` so a fresh instance with fresh state appears
  // every time the user clicks "New event" — no reset effect needed.
  const [asset, setAsset] = useState(
    () => defaultAsset ?? assets[0]?.symbol ?? '',
  )
  const [title, setTitle] = useState('')
  const [body, setBody] = useState('')
  const [link, setLink] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState(null)

  async function handleSubmit(e) {
    e.preventDefault()
    if (!asset || !title.trim()) {
      setError('Asset and title are required.')
      return
    }
    setSubmitting(true)
    setError(null)
    try {
      const created = await createEvent({
        asset,
        title: title.trim(),
        body: body.trim() ? body.trim() : null,
        link: link.trim() ? link.trim() : null,
      })
      onCreated?.(created)
      onOpenChange?.(false)
    } catch (err) {
      const message =
        err instanceof ApiError ? err.message : 'Failed to create event.'
      setError(message)
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <form onSubmit={handleSubmit}>
        <DialogHeader>
          <DialogTitle>New event</DialogTitle>
          <DialogDescription>
            Add a chart event. It becomes visible to anything reading
            <code className="mx-1 rounded bg-muted px-1 py-0.5 text-[11px]">
              /v1/events?asset={asset || 'BTC'}
            </code>
            immediately.
          </DialogDescription>
        </DialogHeader>
        <DialogBody className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="event-asset">Asset</Label>
            <AssetPicker
              id="event-asset"
              value={asset}
              onChange={setAsset}
              assets={assets}
              recentCustom={recentCustom}
              onCustomAdded={onCustomAdded}
              disabled={submitting}
              ariaLabel="Asset"
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="event-title">Title</Label>
            <Input
              id="event-title"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="Spot ETF inflow exceeds $500M"
              maxLength={200}
              disabled={submitting}
              required
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="event-body">Body</Label>
            <Textarea
              id="event-body"
              value={body}
              onChange={(e) => setBody(e.target.value)}
              placeholder="One or two sentences of context."
              maxLength={2000}
              disabled={submitting}
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="event-link">Link</Label>
            <Input
              id="event-link"
              type="url"
              value={link}
              onChange={(e) => setLink(e.target.value)}
              placeholder="https://example.com/article"
              disabled={submitting}
            />
          </div>
          {error ? (
            <p className="rounded-md border border-destructive/40 bg-destructive/10 px-3 py-2 text-sm text-destructive-foreground">
              {error}
            </p>
          ) : null}
        </DialogBody>
        <DialogFooter>
          <Button
            type="button"
            variant="ghost"
            onClick={() => onOpenChange?.(false)}
            disabled={submitting}
          >
            Cancel
          </Button>
          <Button type="submit" disabled={submitting}>
            {submitting ? (
              <>
                <Loader2 className="h-4 w-4 animate-spin" />
                Saving
              </>
            ) : (
              'Create event'
            )}
          </Button>
        </DialogFooter>
      </form>
    </Dialog>
  )
}
