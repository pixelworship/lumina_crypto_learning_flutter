# Chart Events Dashboard

React + Vite + Tailwind v4 dashboard for the Supabase `chart_events`
table. Talks to the Express API in [`_x/api`](../api), never to
Supabase directly.

## Run

```bash
# from repo root, in two terminals:
cd _x/api && yarn install && yarn dev    # http://localhost:4001
cd _x/web && yarn install && yarn dev    # http://localhost:5173
```

## Configuration

| Var                   | Default                  | Notes                              |
| --------------------- | ------------------------ | ---------------------------------- |
| `VITE_API_BASE_URL`   | `http://localhost:4001`  | Base URL of the Express API.       |

`.env` (already created) and `.env.example` live at the project root.

## What's in here

- **`src/App.jsx`** — header (asset selector, refresh, "New event"),
  stats row, event list. Asset selection is mirrored to the URL
  (`?asset=BTC`) so reloads keep state.
- **`src/components/NewEventDialog.jsx`** — modal form for creating
  an event (asset, title, body, link). POSTs through `lib/api.js`.
- **`src/components/EventList.jsx`** — list view with skeleton +
  empty + populated states.
- **`src/components/StatsRow.jsx`** — total / latest / active days.
- **`src/components/ui/`** — small shadcn-style primitives
  (`Button`, `Input`, `Textarea`, `Label`, `Card`, `Select`, `Badge`,
  `Dialog`). Driven by `class-variance-authority` + `clsx` +
  `tailwind-merge`. The `Dialog` wraps the native `<dialog>` element
  to avoid pulling Radix for a single modal.
- **`src/lib/api.js`** — typed-ish fetch wrapper around the API.
- **`src/lib/cn.js`** — `cn()` utility used by every primitive.
- **`src/index.css`** — Tailwind v4 import + dark/light HSL tokens
  exposed via `@theme inline { ... }` so utilities like
  `bg-background`, `text-muted-foreground`, etc. resolve.

## Adding a new event

1. Click **New event** in the header.
2. Pick an asset (defaults to whatever's currently filtered).
3. Fill `title` (required), and optionally `body` and `link`.
4. Submit → POST `/v1/events` → list refreshes.

## Styling notes

- Dark theme is the default (`<html class="dark">`).
- Tokens follow the shadcn naming convention so swapping in real
  shadcn/Radix components later is a drop-in.
