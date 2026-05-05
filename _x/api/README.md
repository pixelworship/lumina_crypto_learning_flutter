# Lumina Events API

Small Express server in front of the Supabase `chart_events` table.
The Flutter app and the `_x/web` dashboard both go through it — the
service-role key never leaves this process.

The response shape mirrors the Flutter `MarketEvent` model
(`lib/data/models/market_event.dart`) so dropping these into
`ChartState.events` is a straight field-for-field map.

## Setup

Requires Node 18.17+.

```bash
cd _x/api
yarn install
```

Create `_x/api/.env` (already present in this repo) with:

| Var                         | Required | Notes                                                |
| --------------------------- | -------- | ---------------------------------------------------- |
| `SUPABASE_URL`              | yes      | `https://<ref>.supabase.co`                          |
| `SUPABASE_SERVICE_ROLE_KEY` | yes      | Service-role JWT — bypasses RLS, **never** ship to the browser. |
| `PORT`                      | no       | Default `4001`.                                      |
| `HOST`                      | no       | Default `0.0.0.0` (LAN-reachable for simulators).    |

## Run

```bash
yarn dev      # node --watch, restarts on file changes
yarn start    # plain node server.js
```

## Schema

`chart_events` (Supabase, public schema):

| Column       | Type          | Notes                                                |
| ------------ | ------------- | ---------------------------------------------------- |
| `id`         | int8 PK       | Auto-incremented.                                    |
| `created_at` | timestamptz   | `default now()` — used as the canonical event time.  |
| `asset`      | text          | Symbol, uppercased (`BTC`, `ETH`, ...).              |
| `title`      | text          | Required when inserting.                             |
| `body`       | text \| null  | Optional.                                            |
| `link`       | text \| null  | Optional; validated as `http(s)://` on POST.         |

## Endpoints

### `GET /health`

```json
{ "status": "ok", "service": "lumina-events-api" }
```

### `GET /v1/assets`

Static catalog of recommended asset symbols (BTC, ETH, SOL, …).
Surfaced in the dashboard's dropdown for one-click selection.

> The catalog is **not** an authorization list. The events endpoints
> below accept any string matching `^[A-Z0-9]{1,16}$` so callers can
> create / fetch events for ad-hoc tickers (e.g. `CYAN`) without
> updating the catalog. Use `/v1/assets` only for UI population.

The reads are split into two intentional shapes:

- **window** (`/v1/events`, `/v1/events/:asset`) — "give me everything
  inside `[from, to]`". Used for the initial chart load, history
  extension, and the dashboard's list view.
- **delta** (`/v1/events/since`) — "give me everything created
  strictly after `since`". Used by the Flutter chart's 1s poll. Strict
  greater-than means the client can use the latest event timestamp
  it's seen as the next `since` cursor without an off-by-one fudge.

### `GET /v1/events`  (window)

Query params:

| Param   | Type            | Default      | Notes                                       |
| ------- | --------------- | ------------ | ------------------------------------------- |
| `asset` | string          | **required** | Asset symbol (case-insensitive).            |
| `from`  | ISO-8601 \| ms  | none         | Inclusive lower bound on `created_at`.      |
| `to`    | ISO-8601 \| ms  | none         | Inclusive upper bound on `created_at`.      |
| `limit` | int             | `200`        | Max returned events (capped at 1000).       |

Returns rows ordered by `created_at` DESC.

### `GET /v1/events/since`  (delta)

Query params:

| Param   | Type            | Default      | Notes                                                          |
| ------- | --------------- | ------------ | -------------------------------------------------------------- |
| `asset` | string          | **required** | Asset symbol (case-insensitive).                               |
| `since` | ISO-8601 \| ms  | **required** | Strict lower bound: returns rows with `created_at > since`.    |
| `limit` | int             | `500`        | Higher default than `/v1/events` so a backgrounded client can  |
|         |                 |              | catch up in one round-trip. Capped at 1000.                    |

Returns rows ordered by `created_at` ASC, so the client can merge
directly into its in-memory list without re-sorting:

```bash
curl 'http://localhost:4001/v1/events/since?asset=BTC&since=2026-05-04T18:00:00Z'
```

Response envelope swaps `from`/`to` for `since`:

```json
{
  "asset":  "BTC",
  "since":  "2026-05-04T18:00:00.000Z",
  "count":  3,
  "events": [ { "id": 12, "...": "..." } ]
}
```

### `GET /v1/events/:asset`  (window shortcut)

Same as `/v1/events` but the symbol is in the path. Defaults to **the
last 24h** if `from`/`to` aren't supplied:

```bash
curl http://localhost:4001/v1/events/BTC
curl 'http://localhost:4001/v1/events/ETH?limit=50'
curl 'http://localhost:4001/v1/events/SOL?from=2026-05-01T00:00:00Z&to=2026-05-04T00:00:00Z'
```

### `POST /v1/events`

JSON body:

```json
{
  "asset":      "BTC",
  "title":      "Spot ETF inflow",
  "body":       "...",
  "link":       "https://...",
  "created_at": "2026-05-04T15:30:00Z"
}
```

- `asset`, `title` required.
- `body`, `link` optional. `link` must be a valid `http(s)://` URL.
- `created_at` optional. ISO-8601 string or epoch milliseconds
  (number or numeric string). Useful for backdating events to
  annotate historical chart moves. When omitted, Supabase fills in
  the column default `now()`.
- `id` is always assigned by Supabase.

Returns the inserted row in the same envelope shape:

```json
{
  "asset": "BTC",
  "from": null, "to": null,
  "count": 1,
  "events": [
    { "id": 42, "asset": "BTC", "timestamp": "2026-05-04T22:14:08.000Z",
      "title": "Spot ETF inflow", "body": "...", "link": "https://..." }
  ]
}
```

## Response envelope

Every list/create endpoint returns:

```json
{
  "asset":  "BTC",
  "from":   "..." | null,    // window queries
  "to":     "..." | null,    // window queries
  "since":  "..." | null,    // delta queries
  "count":  N,
  "events": [
    { "id": 1, "asset": "BTC", "timestamp": "...",
      "title": "...", "body": "..." | null, "link": "..." | null }
  ]
}
```

`timestamp` is `created_at` re-aliased so existing client code parsing
`event.timestamp` keeps working.

## Notes

- The service-role key bypasses RLS. This server is a dev tool — do
  not expose it publicly without a real auth layer.
- CORS is wide open (`*`) for `GET, POST, OPTIONS` so the Vite dev
  server (`_x/web`) and the Flutter app can both hit it from any
  origin during development.
