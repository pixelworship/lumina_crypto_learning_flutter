import { forwardRef } from 'react'

import { cn } from '@/lib/cn'

export const Label = forwardRef(function Label(
  { className, ...props },
  ref,
) {
  return (
    <label
      ref={ref}
      className={cn(
        'text-xs font-medium uppercase tracking-wide text-muted-foreground',
        className,
      )}
      {...props}
    />
  )
})
