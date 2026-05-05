// Lightweight dialog built on the native <dialog> element. Avoids
// pulling Radix for a single-modal app while still getting:
//   - focus trap (browser-native)
//   - Escape to close
//   - centered modal positioning
//   - backdrop via ::backdrop
//
// API mirrors shadcn/Radix loosely so swapping in @radix-ui later is
// a straight find-and-replace.

import { X } from 'lucide-react'
import { useEffect, useRef } from 'react'

import { cn } from '@/lib/cn'

import { Button } from './button'

export function Dialog({ open, onOpenChange, children }) {
  const ref = useRef(null)

  useEffect(() => {
    const node = ref.current
    if (!node) return
    if (open && !node.open) {
      node.showModal()
    } else if (!open && node.open) {
      node.close()
    }
  }, [open])

  useEffect(() => {
    const node = ref.current
    if (!node) return
    function onClose() {
      onOpenChange?.(false)
    }
    function onCancel(e) {
      e.preventDefault()
      onOpenChange?.(false)
    }
    node.addEventListener('close', onClose)
    node.addEventListener('cancel', onCancel)
    return () => {
      node.removeEventListener('close', onClose)
      node.removeEventListener('cancel', onCancel)
    }
  }, [onOpenChange])

  function onBackdropClick(e) {
    if (e.target === ref.current) onOpenChange?.(false)
  }

  return (
    <dialog
      ref={ref}
      onClick={onBackdropClick}
      className="m-auto w-[min(92vw,520px)] rounded-xl border border-border/60 bg-card p-0 text-card-foreground shadow-2xl backdrop:bg-black/60 backdrop:backdrop-blur-sm"
    >
      <div className="relative">
        <Button
          variant="ghost"
          size="icon"
          onClick={() => onOpenChange?.(false)}
          aria-label="Close"
          className="absolute right-2 top-2 h-8 w-8 text-muted-foreground"
        >
          <X className="h-4 w-4" />
        </Button>
        {children}
      </div>
    </dialog>
  )
}

export function DialogHeader({ className, ...props }) {
  return (
    <div
      className={cn(
        'flex flex-col space-y-1.5 px-6 pb-4 pt-6 pr-12',
        className,
      )}
      {...props}
    />
  )
}

export function DialogTitle({ className, ...props }) {
  return (
    <h2
      className={cn(
        'text-lg font-semibold leading-none tracking-tight',
        className,
      )}
      {...props}
    />
  )
}

export function DialogDescription({ className, ...props }) {
  return (
    <p
      className={cn('text-sm text-muted-foreground', className)}
      {...props}
    />
  )
}

export function DialogBody({ className, ...props }) {
  return <div className={cn('px-6 pb-6', className)} {...props} />
}

export function DialogFooter({ className, ...props }) {
  return (
    <div
      className={cn(
        'flex flex-col-reverse gap-2 px-6 pb-6 sm:flex-row sm:justify-end',
        className,
      )}
      {...props}
    />
  )
}
