# Trial Decisions

This document records the key architectural decisions made during the
Lumina trial build and the reasoning behind each one. It is meant as
the companion to [`LIVE_DATA_AND_EVENTS.md`](./LIVE_DATA_AND_EVENTS.md):
that file describes _what_ the system does and _how_ it works today;
this file describes _why_ each substantial choice was made and what
alternatives were considered.

Each section ends with a short list of the alternatives that were
rejected so the reasoning stays auditable.

---

## Table of Contents

1. [Chart Rendering: `CustomPainter` vs `fl_chart`](#1-chart-rendering-custompainter-vs-fl_chart)
2. [Data Architecture: Caching, Storage, and Live Merge](#2-data-architecture-caching-storage-and-live-merge)
3. [Sharing Data & Logic Between Main Chart and Mini Charts](#3-sharing-data--logic-between-main-chart-and-mini-charts)
4. [Extensible Event System](#4-extensible-event-system)
5. [UX for Time Intervals, Errors, and Loading States](#5-ux-for-time-intervals-errors-and-loading-states)
6. [Schemas: Fills and Events](#6-schemas-fills-and-events)

---

## 1. Chart Rendering: `CustomPainter` vs `fl_chart`

### Decision

The candlestick chart is built **directly on `CustomPainter`** with a
small family of cooperating painters. The sparkline used in cards
(`PriceSparkline`) uses **`fl_chart`'s `LineChart`** because the
visual is line-only and we get curve smoothing and axis handling for
free. The list-row mini-graphs (`AssetSparkline`) are also
`CustomPainter` because they live in long lists with strict per-row
paint budgets.

| Surface                                | Renderer                | Why                                                                |
| -------------------------------------- | ----------------------- | ------------------------------------------------------------------ |
| Main candlestick chart                 | `CustomPainter` (×5)    | Need OHLC bodies, wicks, glow, gap stripes, axes, crosshair, glow. |
| Card sparkline (Home, Portfolio)       | `fl_chart` `LineChart`  | Simple line + gradient; `fl_chart` is the cheapest way to ship it. |
| List-row sparkline (Markets, Watchlist) | `CustomPainter` polyline | One paint per row × N rows; must be the smallest possible cost.   |
| Donut allocation (Portfolio)           | `fl_chart` `PieChart`   | Categorical breakdown; no custom interaction.                      |
| Chart minimap                          | `CustomPainter`         | Reads the same `candles` list as the main chart.                   |

### Why not `fl_chart` for the candlestick chart

`fl_chart` doesn't ship a candlestick renderer; the community
candlestick packages on pub.dev are unmaintained, don't support the
gestures we need (pinch-zoom with focal anchoring, scroll-wheel zoom,
long-press crosshair with snapping + haptics), and would have forced
us to drag in a heavy dependency that we'd then have to fork.
`CustomPainter` is the native Flutter primitive for "draw a chart your
way" — and once the painter exists, the candlestick painter (≤ 200
LoC) is comparable in size to the wrapper code we'd need around a
third-party package.

### Why a family of cooperating painters

Splitting paint responsibilities makes each painter cheap to
`shouldRepaint`:

- `ChartAxesPainter` — repaints when grid lines / labels change.
- `CandlePainter` — repaints when the visible window or price range
  changes.
- `CrosshairPainter` — repaints _only_ during long-press.
- `MissingDataPainter` — repaints during a live pause (driven by a
  ticker).
- Volume area + event markers + fill markers — separate `CustomPaint`
  layers in a `Stack`, each behind a `RepaintBoundary` so they don't
  drag siblings into a paint.

This is the same pattern Flutter's own `RenderObject` framework uses
internally: small, layered painters with tight `shouldRepaint`
predicates are dramatically cheaper than one big painter that
re-touches everything every frame.

### Why `fl_chart` for the card sparkline

`PriceSparkline` is purely a smoothed line + gradient + optional dot
grid overlay. `fl_chart` gives us:

- Curve smoothing (`curveSmoothness: 0.32`) with the same result we'd
  spend a chunk of `CustomPainter` time reproducing.
- Below-line gradient handling.
- Aspect-correct min/max padding.

The dot-grid + open-price reference line _are_ a `CustomPainter`
(`_SparklineDotGridPainter`), layered on top via `Stack`. This is the
deliberate hybrid: take what the library does well, paint everything
else by hand.

### Why hand-rolled for the list-row sparkline

`AssetSparkline` paints inside a 64×28 px box, sometimes 20+ on screen
at once, and ticks on every `LivePriceUpdate`. Spinning up `LineChart`
× 20 every tick is measurably more expensive than 20 polylines. Once
the per-row cost matters, a thirty-line polyline painter (with no
axes, no animations) wins.

### Rejected alternatives

- **`charts_flutter` / `syncfusion_flutter_charts`** — both ship a
  candlestick widget but are heavyweight (Syncfusion is commercial),
  and integration with our pan/zoom/crosshair gesture stack would
  require fighting their hit-test model.
- **`chart_sparkline`** — fine for trivial sparklines but our list
  sparkline needs the open-line + dot-grid treatment that's already a
  custom painter; the package would only own ~10 lines of code in
  exchange for adding a dependency.
- **One mega-painter for the candlestick chart** — discarded because
  every gesture (long-press, pan, zoom) would force a full repaint
  of the candle bodies, even when only the crosshair moved.

---

## 2. Data Architecture: Caching, Storage, and Live Merge

### Decision

Three distinct data planes, each owning the layer it's good at:

| Plane          | Source                  | Storage                        | Update model              |
| -------------- | ----------------------- | ------------------------------ | ------------------------- |
| **Live**       | `LivePriceFeed`         | None (broadcast stream)        | Push                      |
| **Historical** | `HistoricalPriceApi`    | `HistoricalTickCache` (in-RAM) | Pull `[start, end)`       |
| **Events**    | Express `/v1/events`    | Server (Supabase)              | Window + 1 s delta poll   |
| **Fills**     | `FillRepository`        | Hive box (on disk)             | Per-trade write           |

The merge happens inside `ChartBloc`. The three contracts that make
it seamless are documented in `LIVE_DATA_AND_EVENTS.md` but the
condensed version is:

1. Both live and historical derive prices from **the same
   deterministic `PriceNoise` curve**, so the boundary between
   "synthesized history" and "live tick" is bit-for-bit continuous.
2. The same step-function offset model applies to both planes — the
   debug "price pump" dial appends `OffsetEvent`s and historical
   synthesis reads them at the timestamp it's emitting for, so cached
   ticks never need to be invalidated.
3. A single `CandleAggregator` does both `rebuild(...)` (full history
   → candles) and `foldTick(...)` (extend the latest candle from a
   live tick), so they share bucket-flooring logic.

### Caching: two layered eviction policies

`HistoricalTickCache` is in-memory only today and uses two policies
in series:

- **Outer (cross-symbol):** LRU over the symbol map with
  `maxSymbols = 50`. Touched on lookup or store.
- **Inner (per-symbol):** time-based retention of
  `retentionPerSymbol = 2 days`. Oldest covered ranges + their ticks
  drop first when over budget.

Memory is therefore bounded by roughly
`maxSymbols × retentionPerSymbol`, independent of usage pattern.

The cache's `lookup()` returns a `CacheLookup` record with `hits` +
`missing` sub-ranges, so the repository can fetch _only_ the gaps. A
prior 24 h fetch lets a subsequent 12 h pan-right resolve entirely
from RAM, and a 48 h history-extend only triggers a single 24 h
fetch.

### Storage decisions per plane

- **Live ticks → no persistent storage.** The live feed is mocked
  in-process and deterministic; replaying the noise curve at startup
  is always cheaper than reading a write-heavy on-disk log. In
  production this is where you'd plug in a WebSocket.
- **Historical ticks → in-memory cache only.** Disk persistence is
  listed as efficiency opportunity #3 in `LIVE_DATA_AND_EVENTS.md` but
  was deliberately deferred — the warm-cache UX gain isn't worth the
  Hive box bytes for a trial.
- **Events → server-authoritative, never cached locally.** The
  dashboard is the only writer and the 1 s delta poll is cheap. A
  local cache would have to deal with deletions, which the poll
  channel doesn't surface today.
- **Fills → Hive box, hand-written `TypeAdapter`s.** No build-step
  dependency, append-only field-id schema for forward/backward
  compatibility. See [§ 6](#6-schemas-fills-and-events).

### Where each piece "lives" architecturally

```
                 ┌─────────────────────────────────────────┐
                 │              ChartBloc                  │
                 │  (per-AssetDetailScreen, isolated)      │
                 └─────────────────────────────────────────┘
                          ▲          ▲          ▲
        ┌─────────────────┘          │          └──────────────────┐
        │                            │                             │
TickRepository           HistoricalTickRepository           ChartEventsRepository
(LivePriceFeed)          (HistoricalTickCache + API)        (HttpChartEventsApi)
        ▲                            ▲                             ▲
        └──── shared singletons at app root (MultiRepositoryProvider) ───┘

   Fills (cross-cutting): FillRepository (Hive) is also a shared singleton;
   ChartBloc and TradeBloc both read it.
```

Every repository is provided at app root via
`MultiRepositoryProvider`. Each pushed `AssetDetailScreen` instantiates
its own `ChartBloc` and `TradeBloc` so two simultaneous detail pages
never share live tick state. The repositories underneath are shared,
so the cache + Hive box benefits accrue across screens.

### How live updates merge with cached history

Live ticks flow through `ChartBloc._onTickReceived`, which:

1. Appends to an in-memory deque (`_tickHistory`, bounded by
   `_maxTickHistory`).
2. Calls `CandleAggregator.foldTick(currentCandle, tick, tf)`.
3. Emits a new `ChartState` with the updated tail candle.

A timeframe change does **not** re-fetch; it calls `rebuild(...)` on
the same deque (off-main when over the threshold) and emits the new
candles.

### Rejected alternatives

- **Single unified "ticks stream" that interleaves history and
  live** — rejected because clients need different access patterns
  (point-in-time pull for history, push subscription for live). The
  abstraction would have leaked.
- **SQLite for the historical cache** — rejected for the trial; Hive
  is already a dependency for fills and a future warm-start cache
  would reuse it.
- **Server-side WebSocket for live ticks** — out of scope for a mock,
  but the `TickRepository` interface is shaped (`watchTicks(symbol)`
  returns `Stream<Tick>`) so the live feed implementation can be
  swapped without touching the bloc.

---

## 3. Sharing Data & Logic Between Main Chart and Mini Charts

### Decision

The main chart and the mini charts deliberately share **the
`HistoricalPriceApi` warehouse + `LivePriceFeed`** but not anything
above that. Above the warehouse, the two surfaces diverge sharply:

| Concern                | Main chart                          | Mini chart                                              |
| ---------------------- | ----------------------------------- | ------------------------------------------------------- |
| State holder           | `ChartBloc` (per screen)            | `SparklineFeed` (singleton)                             |
| Per-symbol cost        | Full tick deque + candles + events  | One ring buffer (32 doubles ≈ 256 B)                    |
| Reactive surface       | `bloc.stream`                       | `ValueListenable<SparklineSnapshot>` per symbol         |
| Live-tick fold         | Append to deque + `foldTick`        | In-place replace of rightmost ring slot                 |
| Tick-rate cost         | One bloc emit → tree rebuild        | One `ValueNotifier.notify` → only the row's `RepaintBoundary` |
| Historical fetch shape | `fetchTicks(...)` → `List<Tick>`    | `fetchSparklineSamples(...)` → `List<double>` (synth + downsample on isolate) |

### Why a `SparklineFeed` service instead of one mini-bloc per row

Routing every visible markets-list row through a bloc would mean a
bloc emit + tree rebuild per row per tick. At 30 rows × 1 Hz this is
already enough to put the markets list in the red on a low-end
device. The `SparklineFeed` design (single subscription to the live
feed, one buffer per symbol, `ValueListenable` per buffer,
`RepaintBoundary` around each widget) keeps per-tick work
proportional to "rows that actually had a price change", not "rows on
screen".

### Why a specialised `fetchSparklineSamples` warehouse call

The naive approach — `fetchTicks(24h)` then downsample on the main
thread — would materialise a ~30 k `Tick` array per visible row and
ship it across the isolate boundary. That tanks the markets list on
tab-switch. The specialised call **synthesizes _and_ downsamples
inside the same isolate hop** and ships back only the final 32-double
`List<double>`.

### What _is_ shared between main and mini

- The same `PriceNoise` curve. A live tick that nudges the main
  chart's last candle and the corresponding markets-list row's
  rightmost sparkline value are mathematically the same number.
- The same `OffsetEvent` step model. A debug dial event jumps the
  rightmost sparkline value and the next candle's close at the same
  moment.
- The same warehouse interface. `MockHistoricalPriceApi` is the only
  thing that knows how to synthesise ticks; both surfaces go through
  it. If we ever swap to a real warehouse, both surfaces switch
  together.

### Why ring buffers, not lists

`_SparklineBuffer` is a fixed-capacity ring (Dart `Queue` under the
hood) with two distinct push semantics:

- `push(p)` — append + trim head. Used to fill the buffer with the
  warehouse seed during hydration.
- `pushLive(p)` — replace the rightmost slot in place. Used for every
  live tick once seeded.

The two-method split exists because pushing _every_ live tick would
cycle through the 32 seed slots in ~20 s and degrade the sparkline
from "trailing 24 h shape" to "last 32 live ticks". Replace-in-place
preserves the macro shape; a freshly-dialed offset shows up as a
sharp right-edge jump, which is the desired affordance.

### Rejected alternatives

- **One `SparklineBloc` per row** — already discussed: tree-rebuild
  cost.
- **Shared `ChartBloc` between main and mini for the same symbol** —
  rejected because the lifecycles disagree: the main chart's bloc is
  per-screen and short-lived; the mini chart's data wants to be hot
  before the user enters the screen.
- **`InheritedNotifier` instead of `ValueListenable`** — equivalent
  in cost but `ValueListenable` is the lighter idiomatic choice and
  composes with `ValueListenableBuilder` out of the box.

---

## 4. Extensible Event System

### Decision

`MarketEvent` is the single Flutter-side type for "annotation on the
chart". The server schema (`chart_events` in Supabase) keeps only
**content** fields; **presentation** fields (`label`, `color`,
`icon`) are computed at the API boundary inside Flutter. This split
is the extensibility seam.

### Schema (server)

```sql
create table chart_events (
  id          bigint generated by default as identity primary key,
  asset       text   not null check (asset ~ '^[A-Z0-9]{1,16}$'),
  title       text   not null,
  body        text,
  link        text,
  created_at  timestamptz not null default now()
);

create index chart_events_asset_created_at_idx
  on chart_events (asset, created_at desc);
```

- `asset` is the only join key — no foreign key into a symbols table,
  so the table is decoupled from the asset catalog and a new symbol
  doesn't require a schema change.
- The single composite index covers both read shapes (window query +
  delta query) — the index column order is intentional.
- `created_at` is server-set so the dashboard can't cause cursor
  regressions with clock skew. (See `LIVE_DATA_AND_EVENTS.md`
  efficiency opportunity #9 for the eventual move to `id > cursor`.)

### Schema (Flutter)

```dart
class MarketEvent {
  final String   id;         // stringified chart_events.id
  final DateTime timestamp;  // server's created_at
  final String   title;
  final String?  body;
  final String?  link;

  // Presentation-only — filled by the API client, NOT stored on the
  // server. This is the extensibility seam: a future "event kind"
  // column on the server flips these from neutral defaults to
  // kind-specific values without changing this type's shape.
  final String   label;      // single-char badge text
  final Color    color;      // badge background
  final IconData? icon;      // overrides `label` when set
}
```

### How extensibility works

1. **Adding a field to events:** add a nullable column on
   `chart_events`, add an optional field on `MarketEvent` (defaulting
   to `null`), update the API client's `_parseEvent` to read it.
   Older clients are forward-compatible because they ignore unknown
   JSON keys.
2. **Adding a new "kind" of event (e.g. earnings vs tweet vs
   regulator filing):** introduce a `kind` text column on the server
   side (nullable, default `'note'`). On the Flutter side, the API
   client's `_BadgeGlyph` helper picks the icon/color based on
   `kind` — `MarketEvent`'s public shape doesn't change.
3. **Adding a new write surface (e.g. mobile users adding their own
   notes):** the server already validates `asset` /`title` /optional
   URL /optional `created_at`. A second client doesn't need any
   schema change; just hit `POST /v1/events`.

### Two intentional read shapes (already in production)

The split between window-fetch and delta-poll is the kernel of the
extensibility story. New event sources can plug into either shape
without disturbing the bloc:

| Endpoint               | Order  | Bound                | Used by                           |
| ---------------------- | ------ | -------------------- | --------------------------------- |
| `GET /v1/events`       | `desc` | `[from, to]`         | Dashboard list, Flutter init load |
| `GET /v1/events/since` | `asc`  | `created_at > since` | Flutter 1 s delta poll            |

The delta endpoint is **strict-greater-than** so the cursor is just
"the timestamp of the last event we've seen" — no off-by-one fudging.

### Bloc-level merge contract

`ChartBloc` owns `_eventCursor` and dedupes by `id` on every poll.
Three guards keep the system honest:

- If the symbol switched while a poll was in flight, the response is
  dropped.
- If the bloc was closed between timer-fire and handler-run,
  `isClosed` short-circuits before any `add`.
- Events list is capped at `_maxEvents = 200` so a runaway publisher
  can't bloat the bloc state.

### Rejected alternatives

- **One row in `chart_events` per `(asset, kind)` matrix** — over-
  normalisation for the trial; the single neutral table is fine until
  we have ≥ 3 distinct kinds.
- **Realtime push via Supabase Realtime instead of polling** — listed
  as efficiency opportunity #4. Rejected for the trial because the
  poll is already empty-payload when nothing changed; the work to
  wire push semantics is concentrated in cancellation/reconnect
  edge-cases that aren't interesting until we have real traffic.
- **Server-side presentation fields** — explicitly avoided. The
  badge/icon/colour decisions should belong to the client because
  theming (light/dark, accessible contrast) is a client concern.

---

## 5. UX for Time Intervals, Errors, and Loading States

### Time intervals (timeframes)

`Timeframe` is a fixed enum: `1s, 10s, 30s, 1m, 5m, 10m, 15m, 30m,
1h`. Each value carries both its `Duration` and its display label.
The set is intentionally limited so the timeframe selector remains a
horizontal scroller of small pills rather than a dropdown.

Rules driving the UX:

- **Timeframe selector is always visible** above the chart. Tapping
  a new timeframe never re-fetches history — it just rebuilds candles
  off the same `_tickHistory` deque, so the visual is "instant"
  (modulo the off-main hop on > 2000 ticks).
- **History-extend is automatic** when the user pans/zooms to the
  left edge — no "load more" button. A small loading badge appears
  in the top-left of the chart while older ticks are fetched.
- **"LIVE" pill** appears in the top-right whenever the user has
  panned away from the right edge and auto-follow is off. Tap to
  snap back to the live tick. The pill pulses, so it reads as
  "actionable" rather than "decorative status".
- **The pill is hidden during long-press** so it never overlaps the
  OHLC tooltip.

### Loading states (chart-level)

The chart has **four distinct loading affordances**, picked based on
the situation:

| Situation                                     | Affordance                                                       |
| --------------------------------------------- | ---------------------------------------------------------------- |
| Cold cache (`candles.isEmpty`)                | Centered `LuminaLoadingIndicator` filling the panel              |
| Warm cache, fresh fetch still in flight       | Cached candles render normally + small "Loading" badge top-right |
| History extend in flight                      | Existing candles render normally + small badge top-left          |
| Live feed paused                              | Red "DATA UNAVAILABLE" stripe grows in place where the gap is    |

The distinction matters because cold-cache and history-extend are
both technically "history fetch in flight", but the user's
expectation is wildly different — they should never block on
history-extend, only on cold-cache.

### Loading states (mini-chart / markets list)

- **Sparkline hydration:** rows render a `LuminaSkeleton` shimmer of
  the _exact same footprint_ as the painted polyline so the column
  width never jumps when the snapshot resolves.
- **Failed sparkline seed:** the buffer flips to "loaded but empty"
  rather than staying in shimmer forever. Live ticks (if any arrive)
  populate the buffer naturally. The row degrades to a blank line,
  not a broken UI.

### Loading states (purchase / sale)

- The buy/sell buttons render `isLoading` spinners while the trade
  bloc's request is in flight. The amount field is left enabled — a
  user who taps once and starts editing should keep their typing.

### Error UX

A blanket rule: **transport errors never throw to the UI.** Three
concrete implementations of this:

1. `HttpChartEventsApi` catches every exception, logs it, returns an
   empty list. The chart degrades to "no events overlay" rather than
   crashing.
2. `SparklineFeed._seedFromWarehouse` catches and flips the buffer
   to `markLoaded()` instead of throwing — the row stops shimmering
   even on warehouse failure.
3. `TradeBloc` surfaces purchase/sale failures via a `SnackBar`
   triggered by a `BlocListener` watching `lastPurchaseSucceeded`
   and `lastSaleSucceeded`. The two flags are deliberately separate
   so a buy landing while a sale's result is still pending doesn't
   clobber the sale snackbar.

For surfaces where there's a sensible empty state, that's preferred
over an error banner. The principle is: **users should never have to
dismiss an error message just to keep using the app.**

### Rejected alternatives

- **A single global error toast bus** — rejected because most errors
  are surface-local (a sparkline failure shouldn't darken the chart).
- **Infinite-scroll history with no visual feedback** — rejected
  because users genuinely need to know "older data is still
  loading"; without the loading badge, a slow extend feels like the
  app froze.
- **Modal loading overlay on every transition** — rejected for the
  warm-cache case. Watching a cached chart blank out and reload on
  symbol-switch is jarring; cached data should render instantly with
  only a small "refreshing" cue.

---

## 6. Schemas: Fills and Events

### Fills (local, persisted)

A `Fill` represents one user trade execution. Persisted to a Hive
box with hand-written `TypeAdapter`s (no `build_runner` dependency).

```dart
class Fill {
  final String   id;          // globally unique, generated at insert
  final String   symbol;      // base asset, upper-cased (e.g. "BTC")
  final FillSide side;        // buy | sell
  final double   price;       // execution price in `quoteSymbol`
  final double   sizeBase;    // size in base units (e.g. 0.10 BTC)
  final double   costQuote;   // pre-computed = price * sizeBase
  final String   quoteSymbol; // e.g. "USDT"
  final DateTime timestamp;
}
```

**On-disk wire format (Hive `TypeAdapter`):**

```
byte: numberOfFields (N)
N × (
  byte: fieldId,
  any : value
)
```

Forward/backward-compat rules — the schema is **append-only by field
id**:

- To **add** a field: pick the next unused `fieldId`, bump
  `numberOfFields`. Older readers that don't recognise the id will
  pass over it (the read is by id, not position).
- To **remove** a field: leave the id reserved, stop writing it.
- **Never** reorder or repurpose an existing id — that corrupts
  every row on disk.

`FillSide` is its own type (`kFillSideTypeId = 2`) with a single-byte
on-disk representation (the enum index). Unknown future values fall
back to `FillSide.buy` rather than throwing, so a forward-compat read
on an older client degrades gracefully.

The `quoteSymbol` field on the fill (rather than inferring it from
the current asset detail screen's pair) means the inspect modal stays
correct even if the app later supports per-asset multi-quote (e.g.
BTC/USDT _and_ BTC/USDC).

**Why `costQuote` is stored even though it's derivable:** every paint
of `FillMarkerOverlay` would otherwise have to redo the
multiplication. Pre-computing once at insert time keeps the marker
overlay's hot path branch-free.

### Events (server, mirrored on client)

Server table (Supabase Postgres):

```sql
create table chart_events (
  id          bigint generated by default as identity primary key,
  asset       text   not null check (asset ~ '^[A-Z0-9]{1,16}$'),
  title       text   not null,
  body        text,
  link        text,
  created_at  timestamptz not null default now()
);

create index chart_events_asset_created_at_idx
  on chart_events (asset, created_at desc);
```

Client type (`MarketEvent`):

```dart
class MarketEvent {
  // Content (mirror of chart_events) ---------------------------------
  final String   id;          // stringified chart_events.id
  final DateTime timestamp;   // chart_events.created_at
  final String   title;
  final String?  body;
  final String?  link;

  // Presentation (computed at the API boundary, never persisted) -----
  final String   label;       // single-char badge text
  final Color    color;       // badge background
  final IconData? icon;       // overrides `label` when set
}
```

API JSON shape (window query, delta poll, write — same envelope):

```json
{
  "events": [
    {
      "id": 42,
      "asset": "BTC",
      "title": "Spot ETF inflow exceeds $500M",
      "body": "BlackRock IBIT logged...",
      "link": "https://example.com/article",
      "created_at": "2026-05-10T19:14:23.811Z"
    }
  ]
}
```

The `events:` envelope (rather than a bare top-level array) leaves
room to add sibling fields (pagination cursor, next-since hint,
warnings) without breaking the client parser.

### Side-by-side: Fills vs Events

| Property             | `Fill`                              | `MarketEvent`                        |
| -------------------- | ----------------------------------- | ------------------------------------ |
| Authoritative source | Local (Hive)                        | Remote (Supabase)                    |
| Anchored at          | `(timestamp, price)` — XY on chart  | `timestamp` only — X on chart (badge rides over candles) |
| Lifetime             | Forever (no delete UI today)        | Server controls; client polls inserts only |
| Schema evolution     | Append-only field IDs               | Append-only JSON keys                |
| Presentation         | Side-driven (buy = green, sell = red) | Neutral by default; computed at API boundary |
| Modal on tap         | Yes (inspect: price, size, P&L)     | Yes (title, body, optional `link`)   |

### Rejected alternatives

- **Storing fills on the server too.** Out of scope for the trial.
  The hand-written Hive adapter is the smallest possible solution
  with no codegen dependency.
- **JSON column on `chart_events` for arbitrary extra fields.**
  Tempting but unsafe — once one client starts writing arbitrary
  shapes, every other client has to defend against them. Append a
  typed column instead.
- **`Fill.pnl` cached on the row.** Rejected because P&L depends on
  the _current_ mark price, not the fill price; caching it would
  immediately go stale. P&L is computed fresh in the inspect modal.
- **One unified `ChartAnnotation` base class with `Fill` and
  `MarketEvent` as subtypes.** Considered, rejected. They look
  similar in the chart but have completely different lifecycles
  (local-write-once vs server-poll), persistence layers, and
  presentation models. Sharing the base class would force every
  consumer to type-test on every read.
