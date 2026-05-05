import { Check, X } from 'lucide-react'
import { useEffect, useRef, useState } from 'react'

import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { cn } from '@/lib/cn'

/** Sentinel option value used to enter "type a custom ticker" mode. */
const OTHER_SENTINEL = '__other__'

/** Same shape the API enforces — see _x/api/data/assets.js. */
const TICKER_REGEX = /^[A-Z0-9]{1,16}$/

/**
 * Asset dropdown with an "Other..." escape hatch.
 *
 * Renders the catalog [assets] plus, when present, an `<optgroup>` of
 * recent custom symbols, plus a final "Other..." entry that swaps the
 * select for an inline text input. Submitting a non-catalog symbol
 * notifies the parent via [onCustomAdded] so the symbol is remembered
 * across sessions (parent owns the localStorage write).
 *
 * The picker is fully controlled — the parent holds the active
 * symbol in [value] and reacts to [onChange] confirmations. The only
 * internal state is the transient mode + draft text.
 */
export function AssetPicker({
  value,
  onChange,
  assets,
  recentCustom = [],
  onCustomAdded,
  disabled,
  id,
  className,
  ariaLabel = 'Asset',
}) {
  const [mode, setMode] = useState('select')
  const [draft, setDraft] = useState('')
  const [error, setError] = useState(null)
  const inputRef = useRef(null)

  // When mode flips to custom, focus + select the input so the user
  // can type immediately. Setting the draft text itself happens in
  // the click handler below (synchronously with the user gesture)
  // rather than here — keeping the effect to pure DOM side-effects
  // avoids cascading-render warnings from React's compiler-aware
  // hook lint.
  useEffect(() => {
    if (mode !== 'custom') return undefined
    const handle = requestAnimationFrame(() => {
      inputRef.current?.focus()
      inputRef.current?.select()
    })
    return () => cancelAnimationFrame(handle)
  }, [mode])

  function handleSelectChange(e) {
    const next = e.target.value
    if (next === OTHER_SENTINEL) {
      // Pre-fill with the current value (uppercased) so editing a
      // typo is one keystroke instead of starting from scratch.
      setDraft((value ?? '').toUpperCase())
      setError(null)
      setMode('custom')
      return
    }
    onChange?.(next)
  }

  function commitCustom() {
    const symbol = (draft ?? '').trim().toUpperCase()
    if (!TICKER_REGEX.test(symbol)) {
      setError('1-16 characters, A-Z and 0-9 only.')
      return
    }
    // If the user typed a catalog symbol, treat it as a normal pick:
    // don't pollute "Recent custom" with entries that are already
    // first-class in the dropdown.
    const inCatalog = assets.some((a) => a.symbol === symbol)
    if (!inCatalog) onCustomAdded?.(symbol)
    onChange?.(symbol)
    setMode('select')
  }

  function cancelCustom() {
    setMode('select')
    setError(null)
  }

  function handleInputKeyDown(e) {
    if (e.key === 'Enter') {
      e.preventDefault()
      commitCustom()
    } else if (e.key === 'Escape') {
      e.preventDefault()
      cancelCustom()
    }
  }

  // Stage the dropdown contents. If the active value is neither in the
  // catalog nor in recent customs (e.g. came from a URL deep-link
  // before being typed), surface it as its own option so the select
  // visibly reflects the current state.
  if (mode === 'custom') {
    return (
      <div className={cn('flex items-center gap-1.5', className)}>
        <Input
          id={id}
          ref={inputRef}
          value={draft}
          onChange={(e) => setDraft(e.target.value.toUpperCase())}
          onKeyDown={handleInputKeyDown}
          placeholder="CYAN"
          maxLength={16}
          autoCapitalize="characters"
          spellCheck={false}
          disabled={disabled}
          aria-label="Custom asset symbol"
          aria-invalid={Boolean(error)}
          aria-describedby={error ? `${id ?? 'asset'}-error` : undefined}
          className="font-mono uppercase"
        />
        <Button
          type="button"
          size="icon"
          onClick={commitCustom}
          disabled={disabled || !draft.trim()}
          aria-label="Use this symbol"
          title="Use this symbol (Enter)"
          className="h-10 w-10 shrink-0"
        >
          <Check className="h-4 w-4" />
        </Button>
        <Button
          type="button"
          variant="ghost"
          size="icon"
          onClick={cancelCustom}
          disabled={disabled}
          aria-label="Cancel"
          title="Cancel (Esc)"
          className="h-10 w-10 shrink-0"
        >
          <X className="h-4 w-4" />
        </Button>
        {error ? (
          <p
            id={`${id ?? 'asset'}-error`}
            className="sr-only"
            role="alert"
          >
            {error}
          </p>
        ) : null}
      </div>
    )
  }

  const inCatalog = assets.some((a) => a.symbol === value)
  const inRecents = recentCustom.includes(value)
  const showOrphan = value && !inCatalog && !inRecents

  return (
    <div className={cn('space-y-1', className)}>
      <Select
        id={id}
        value={value ?? ''}
        onChange={handleSelectChange}
        disabled={disabled}
        aria-label={ariaLabel}
      >
        {showOrphan ? (
          <option value={value}>{value} (custom)</option>
        ) : null}
        {assets.length > 0 ? (
          <optgroup label="Catalog">
            {assets.map((a) => (
              <option key={a.symbol} value={a.symbol}>
                {a.symbol} — {a.name}
              </option>
            ))}
          </optgroup>
        ) : (
          // Catalog hasn't loaded yet — keep the current value visible
          // so the select isn't blank during the first render.
          <option value={value ?? ''}>{value ?? ''}</option>
        )}
        {recentCustom.length > 0 ? (
          <optgroup label="Recent custom">
            {recentCustom.map((sym) => (
              <option key={sym} value={sym}>
                {sym}
              </option>
            ))}
          </optgroup>
        ) : null}
        <option value={OTHER_SENTINEL}>Other…</option>
      </Select>
      {error ? (
        <p className="text-xs text-destructive" role="alert">
          {error}
        </p>
      ) : null}
    </div>
  )
}
