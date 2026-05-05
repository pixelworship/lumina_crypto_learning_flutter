import { Activity, Calendar, Clock } from 'lucide-react'

import { Card, CardContent } from '@/components/ui/card'
import { dayKey, formatAbsolute, formatRelative } from '@/lib/time'

export function StatsRow({ events, asset }) {
  const total = events.length
  const latest = events[0]?.timestamp ?? null
  const distinctDays = new Set(events.map((e) => dayKey(e.timestamp))).size

  return (
    <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
      <StatCard
        label={`Events for ${asset}`}
        value={total.toLocaleString()}
        icon={<Activity className="h-4 w-4" />}
      />
      <StatCard
        label="Latest event"
        value={latest ? formatRelative(latest) : '—'}
        sub={latest ? formatAbsolute(latest) : 'No data yet'}
        icon={<Clock className="h-4 w-4" />}
      />
      <StatCard
        label="Active days (in window)"
        value={distinctDays.toLocaleString()}
        icon={<Calendar className="h-4 w-4" />}
      />
    </div>
  )
}

function StatCard({ label, value, sub, icon }) {
  return (
    <Card>
      <CardContent className="flex items-start justify-between gap-3 p-5">
        <div>
          <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
            {label}
          </p>
          <p className="mt-2 text-2xl font-semibold leading-none">{value}</p>
          {sub ? (
            <p className="mt-1.5 text-xs text-muted-foreground">{sub}</p>
          ) : null}
        </div>
        <div className="rounded-md bg-muted p-2 text-muted-foreground">
          {icon}
        </div>
      </CardContent>
    </Card>
  )
}
