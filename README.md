# Lumina Crypto

Lumina is a mock crypto trading and portfolio app. It is structured as
a **monorepo with three subprojects** that work together:

| Subproject       | Path        | Stack                          | Purpose                                                                      |
| ---------------- | ----------- | ------------------------------ | ---------------------------------------------------------------------------- |
| **Flutter app**  | `lib/`      | Flutter 3.x, BLoC              | Trader-facing app: candlestick chart, markets list, portfolio, paper trades. |
| **Events API**   | `_x/api/`   | Node 18+, Express, Supabase JS | Small REST surface in front of the Supabase `chart_events` table.            |
| **Web dashboard**| `_x/web/`   | React 19, Vite, Tailwind v4    | Authoring UI for chart events. Talks to the Events API only.                 |

The Flutter app generates its own price data in-process — there is no
external feed and no backend dependency for live or historical prices.
**The only piece that touches a real backend is the chart-event
annotation feature**, which the Events API and the Web dashboard exist
to support.

For the deeper architectural writeup (data flow, caching, and
diagrams), see [`docs/LIVE_DATA_AND_EVENTS.md`](./docs/LIVE_DATA_AND_EVENTS.md).

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Repository Layout](#repository-layout)
3. [Quick Start (TL;DR)](#quick-start-tldr)
4. [Step 1 — Supabase Setup](#step-1--supabase-setup)
5. [Step 2 — Events API (`_x/api`)](#step-2--events-api-_xapi)
6. [Step 3 — Web Dashboard (`_x/web`)](#step-3--web-dashboard-_xweb)
7. [Step 4 — Flutter App](#step-4--flutter-app)
8. [Running the Whole Stack](#running-the-whole-stack)
9. [Environment Variables Reference](#environment-variables-reference)
10. [Verifying Your Setup](#verifying-your-setup)
11. [Common Tasks](#common-tasks)
12. [Troubleshooting](#troubleshooting)

---

## Prerequisites

Install the following on your machine before starting. Versions listed
are minimums tested with this repo.

| Tool                | Version | Why                                                  | Install                                                                  |
| ------------------- | ------- | ---------------------------------------------------- | ------------------------------------------------------------------------ |
| **Flutter SDK**     | 3.11.5+ | Builds the mobile/desktop app.                       | <https://docs.flutter.dev/get-started/install>                            |
| **Dart SDK**        | 3.11.5+ | Bundled with Flutter — no separate install needed.   | (comes with Flutter)                                                      |
| **Xcode**           | 15+     | Needed only for iOS builds. macOS users only.        | Mac App Store                                                             |
| **CocoaPods**       | 1.14+   | iOS native dependency manager. macOS users only.     | `sudo gem install cocoapods`                                              |
| **Android Studio**  | latest  | Optional — needed only for Android builds + emulator.| <https://developer.android.com/studio>                                    |
| **Node.js**         | 18.17+  | Runs the Events API and the Vite dev server.         | <https://nodejs.org> or `nvm install 20`                                  |
| **Yarn**            | 1.22+   | Package manager used by both `_x/api` and `_x/web`.  | `npm install -g yarn`                                                     |
| **Supabase account**| free    | Hosts the `chart_events` table.                      | <https://supabase.com>                                                    |
| **Git**             | 2.x+    | Cloning the repo.                                    | `xcode-select --install` on macOS, or your distro's package manager.      |

After installing, verify the toolchain:

```bash
flutter doctor          # all green checkmarks for the platforms you want to target
node --version          # v18.17.0 or higher
yarn --version          # 1.22.x or higher
```

If `flutter doctor` reports issues for iOS or Android, follow its
suggestions before continuing — you do not need both platforms green
to develop, but you do need at least one (or use a desktop target like
macOS / Linux / Windows).

---

## Repository Layout

```
lumina_crypto_learning_flutter/
├── README.md                            ← you are here
├── docs/
│   └── LIVE_DATA_AND_EVENTS.md          ← architecture writeup with diagrams
├── pubspec.yaml                         ← Flutter dependencies
├── lib/                                 ← Flutter source
│   ├── main.dart
│   ├── app.dart
│   ├── core/                            ← clock, concurrency, diagnostics, utils
│   ├── data/
│   │   ├── models/                      ← Tick, Candle, MarketEvent, ...
│   │   ├── services/                    ← LivePriceFeed, HistoricalPriceApi, ...
│   │   └── repositories/                ← TickRepository, ChartEventsRepository, ...
│   ├── design_system/                   ← shared Lumina UI tokens & widgets
│   └── presentation/
│       ├── blocs/                       ← BLoC layer (chart, markets, portfolio, ...)
│       ├── screens/                     ← MainShell, AssetDetailScreen, ...
│       └── widgets/                     ← chart renderer, overlays, sparkline
├── test/                                ← Dart unit + widget tests
├── ios/  android/  macos/  linux/  windows/  web/   ← Flutter platform targets
└── _x/                                  ← non-Flutter sub-projects
    ├── api/                             ← Express server in front of Supabase
    │   ├── server.js
    │   ├── routes/                      ← assets.js, events.js
    │   ├── lib/supabaseClient.js
    │   └── package.json
    └── web/                             ← React + Vite dashboard
        ├── index.html
        ├── vite.config.js
        ├── src/
        └── package.json
```

The `_x/` prefix is deliberate — it sorts the non-Flutter
subprojects to the bottom of any directory listing so they don't
distract from the Flutter source.

---

## Quick Start (TL;DR)

If you already have Supabase credentials and the standard toolchain
installed, this is the entire setup:

```bash
# 1. Clone and install Flutter deps
git clone <this-repo-url> lumina && cd lumina
flutter pub get

# 2. Events API
cd _x/api
cat > .env <<'EOF'
SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
SUPABASE_SERVICE_ROLE_KEY=YOUR_SERVICE_ROLE_KEY
PORT=4001
EOF
yarn install && yarn dev          # http://localhost:4001

# 3. Web dashboard (separate terminal)
cd ../web
cat > .env <<'EOF'
VITE_API_BASE_URL=http://localhost:4001
EOF
yarn install && yarn dev          # http://localhost:5173

# 4. Flutter app (separate terminal)
cd ../..
flutter run --dart-define=EVENTS_API_BASE_URL=http://localhost:4001
```

Skip ahead to [Step 1 — Supabase Setup](#step-1--supabase-setup) if
you don't have credentials yet, then come back here.

---

## Step 1 — Supabase Setup

The Events API needs a Supabase project with one table.

### 1.1 Create a project

1. Sign in at <https://supabase.com>.
2. Click **New project**. Pick a name (e.g. `lumina-events`), a
   strong DB password, and any region close to you.
3. Wait ~2 minutes for the project to provision.

### 1.2 Create the `chart_events` table

Open the SQL editor (left sidebar → **SQL Editor** → **New query**)
and run:

```sql
create table public.chart_events (
  id          bigint generated by default as identity primary key,
  created_at  timestamptz not null default now(),
  asset       text   not null,
  title       text   not null,
  body        text,
  link        text
);

-- Index for the per-asset window query and the delta poll.
create index chart_events_asset_created_idx
  on public.chart_events (asset, created_at desc);

-- Optional: a CHECK constraint that mirrors the API's accepted shape.
alter table public.chart_events
  add constraint chart_events_asset_format
  check (asset ~ '^[A-Z0-9]{1,16}$');
```

> **Why no Row Level Security policy?** The API talks to Supabase
> using the **service-role key**, which bypasses RLS by design. The
> service-role key never leaves the API process. If you later expose
> the database directly to a browser (you should not), enable RLS and
> write policies appropriate to your auth model.

### 1.3 Grab your credentials

1. Go to **Project Settings** (gear icon) → **API**.
2. Copy the **Project URL**. It looks like `https://abcdwxyz.supabase.co`.
3. Copy the **`service_role` secret** (under **Project API keys**).
   This is a long JWT starting with `eyJ...`.

> **Never commit the service-role key.** It bypasses RLS. The Events
> API is the only place it should live, and `_x/api/.gitignore` is
> already configured to ignore `.env`.

You'll paste these into `_x/api/.env` in the next step.

---

## Step 2 — Events API (`_x/api`)

This is the small Express server that proxies the Supabase
`chart_events` table. The Flutter app and the Web dashboard both go
through it.

### 2.1 Install dependencies

```bash
cd _x/api
yarn install
```

> Per repo convention, **always use `yarn`** for this subproject (and
> the Web dashboard). Do not mix `npm` and `yarn` lockfiles.

### 2.2 Configure environment variables

Create `_x/api/.env` with the values from Supabase:

```bash
# _x/api/.env

# Required — both come from Supabase Project Settings → API.
SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOiJIUzI1NiIs...replace_me...

# Optional — defaults shown.
PORT=4001
HOST=0.0.0.0
```

| Var                         | Required | Default     | Notes                                                                  |
| --------------------------- | :------: | ----------- | ---------------------------------------------------------------------- |
| `SUPABASE_URL`              |   yes    | —           | Project URL.                                                            |
| `SUPABASE_SERVICE_ROLE_KEY` |   yes    | —           | Service-role JWT. **Never** ship to the browser.                        |
| `PORT`                      |    no    | `4001`      | Bind port.                                                              |
| `HOST`                      |    no    | `0.0.0.0`   | Bind host. Leave at `0.0.0.0` so iOS / Android emulators can reach it.  |

The server fails fast at boot if either Supabase variable is missing,
so a typo gives you a clear error rather than first-request 500s.

### 2.3 Run the server

```bash
yarn dev      # node --watch — restarts on file changes
yarn start    # plain `node server.js` — for production-like runs
```

You should see:

```
[lumina-events-api] listening on http://0.0.0.0:4001
```

Hit `http://localhost:4001/health` in a browser or with curl:

```bash
curl http://localhost:4001/health
# → {"status":"ok","service":"lumina-events-api"}
```

For the full endpoint reference (request/response shapes, query
parameters, validation rules), see
[`_x/api/README.md`](./_x/api/README.md).

---

## Step 3 — Web Dashboard (`_x/web`)

The dashboard is a React + Vite app for authoring and managing chart
events. It talks to the Events API only — it never reaches Supabase
directly.

### 3.1 Install dependencies

```bash
cd _x/web
yarn install
```

### 3.2 Configure environment variables

Copy the example file:

```bash
cp .env.example .env
```

The default value points at a locally-running API on port 4001:

```bash
# _x/web/.env
VITE_API_BASE_URL=http://localhost:4001
```

| Var                  | Required | Default                  | Notes                                                                |
| -------------------- | :------: | ------------------------ | -------------------------------------------------------------------- |
| `VITE_API_BASE_URL`  |   yes    | `http://localhost:4001`  | Base URL of the Events API. Override only if you bind it elsewhere. |

Vite only exposes variables prefixed with `VITE_` to the browser, so
no secrets can leak into the bundle from this file.

### 3.3 Run the dev server

```bash
yarn dev
```

Vite prints the local URL — usually:

```
  VITE v8.x  ready in ~200 ms

  ➜  Local:   http://localhost:5173/
```

Open it in any modern browser. You should see the Lumina dashboard
with an asset picker and an empty event list (until you create some).

### 3.4 Production build (optional)

```bash
yarn build      # outputs to _x/web/dist/
yarn preview    # serves dist/ for a quick local sanity check
```

---

## Step 4 — Flutter App

### 4.1 Install Flutter dependencies

From the repo root:

```bash
flutter pub get
```

This resolves and downloads everything in `pubspec.yaml` into
`.dart_tool/`. No additional setup is needed for the live or historical
data subsystems — they are 100% in-process mocks (see
[`docs/LIVE_DATA_AND_EVENTS.md`](./docs/LIVE_DATA_AND_EVENTS.md)).

### 4.2 (iOS only) Install CocoaPods

If you plan to run on iOS:

```bash
cd ios
pod install --repo-update
cd ..
```

This is automatic on the first `flutter run`, but running it manually
the first time gives you cleaner error messages if something goes
wrong.

### 4.3 Configure the Events API base URL

The Flutter app is configured at compile time via Dart defines. The
default is `http://localhost:4001`, which works for:

- macOS desktop builds
- iOS Simulator (it shares the host's loopback)
- Web builds running in the same browser as the API
- Linux / Windows desktop builds

It does **not** work for Android emulators or physical devices —
those need a different host. See the table below.

| Target                        | Recommended `EVENTS_API_BASE_URL`               |
| ----------------------------- | ----------------------------------------------- |
| macOS desktop                 | `http://localhost:4001`                         |
| Linux / Windows desktop       | `http://localhost:4001`                         |
| iOS Simulator                 | `http://localhost:4001`                         |
| iOS physical device           | `http://<your-mac-LAN-ip>:4001` *or* ngrok URL  |
| Android Emulator (AVD)        | `http://10.0.2.2:4001`                          |
| Android physical device       | `http://<your-machine-LAN-ip>:4001` *or* ngrok URL |
| Flutter Web (Chrome / Edge)   | `http://localhost:4001`                         |

To find your machine's LAN IP:

```bash
# macOS / Linux
ipconfig getifaddr en0      # macOS Wi-Fi
hostname -I | awk '{print $1}'   # Linux

# Windows
ipconfig | findstr IPv4
```

If a LAN IP isn't usable (phone on cellular, phone on a different
Wi-Fi network than your laptop, corporate Wi-Fi that blocks
peer-to-peer, App Transport Security complaining about cleartext HTTP
on iOS), skip ahead to [4.4 Using ngrok for any-network access](#44-using-ngrok-for-any-network-access).

### 4.4 Using ngrok for any-network access

[ngrok](https://ngrok.com) opens a public HTTPS tunnel to your
local Express server, so a physical device can reach the API
**regardless of network topology** — cellular, guest Wi-Fi,
or just-a-different-coffee-shop. As a bonus the tunnel terminates as
HTTPS, which sidesteps iOS App Transport Security entirely.

#### 4.4.1 Install and authenticate

```bash
# macOS (Homebrew)
brew install ngrok

# or download a binary for your OS from https://ngrok.com/download
```

Sign up for a free account, copy your authtoken from
<https://dashboard.ngrok.com/get-started/your-authtoken>, and register
it once per machine:

```bash
ngrok config add-authtoken YOUR_NGROK_AUTHTOKEN
```

#### 4.4.2 Open the tunnel

With the Events API already running on port 4001 (Step 2.3), in a
**new terminal**:

```bash
ngrok http 4001
```

ngrok prints a forwarding URL that looks like:

```
Forwarding   https://abc1-23-45-67-89.ngrok-free.app -> http://localhost:4001
```

Copy that HTTPS URL. Verify the tunnel:

```bash
curl https://abc1-23-45-67-89.ngrok-free.app/health
# → {"status":"ok","service":"lumina-events-api"}
```

#### 4.4.3 Point the Flutter app at the tunnel

Pass the ngrok URL via `--dart-define` instead of a LAN IP:

```bash
flutter run -d <device-id> \
  --dart-define=EVENTS_API_BASE_URL=https://abc1-23-45-67-89.ngrok-free.app
```

Done — the chart picks up events from your local Express server even
if the phone is on a totally different network from your laptop.

#### 4.4.4 Caveats and tips

- **The free-tier URL changes every time `ngrok http` restarts.** Each
  fresh tunnel needs a fresh `--dart-define` and a full Flutter
  rebuild. If you're iterating, leave the tunnel running and only
  restart Flutter; the URL stays stable for the lifetime of the
  ngrok process. For a permanent URL, use ngrok's static-domain
  feature (free tier offers one static domain per account).
- **Browsers see an interstitial warning page on the first request**
  to a free-tier ngrok URL. The Flutter `http` client doesn't trigger
  this because it sends a non-browser User-Agent (`Dart/3.x`), so the
  Flutter app is unaffected. If you want to point the Web dashboard
  at a teammate's ngrok URL, append the header
  `ngrok-skip-browser-warning: true` (any value works) to the
  dashboard's fetch calls, or upgrade the tunnel to a paid plan that
  removes the interstitial.
- **Treat the URL like a credential.** While the tunnel is open,
  anyone with the URL can hit your local API and, by extension, your
  Supabase service-role key's reach. Tear the tunnel down when you're
  done (`Ctrl-C` in the ngrok terminal) and don't paste the URL into
  public chat.
- **The tunnel works for the dashboard too.** If a teammate needs to
  poke the dashboard during a review, run a second `ngrok http 5173`
  tunnel and share that URL. Same caveats apply.

### 4.5 Run the app

Pick a device and run:

```bash
flutter devices   # list connected/simulated devices

# example: macOS desktop with the default API URL
flutter run -d macos

# example: iOS simulator
flutter run -d ios

# example: Android emulator (different API host!)
flutter run -d emulator-5554 \
  --dart-define=EVENTS_API_BASE_URL=http://10.0.2.2:4001
```

If your `EVENTS_API_BASE_URL` differs from the default, you must pass
it as a `--dart-define` flag every time you build or run. To avoid
typing it repeatedly, use the launch configuration in your IDE
(`.vscode/launch.json` or Android Studio run config) and add the
define there once.

> **Hot restart vs. hot reload:** changing `--dart-define` requires a
> full rebuild — neither hot-reload nor hot-restart picks up new
> compile-time constants. Stop the app and run `flutter run` again.

---

## Running the Whole Stack

For day-to-day development, open three terminal tabs:

```bash
# Terminal 1 — Events API
cd _x/api && yarn dev

# Terminal 2 — Web dashboard
cd _x/web && yarn dev

# Terminal 3 — Flutter app
flutter run -d macos
```

The recommended development loop:

1. Use the **Web dashboard** (`http://localhost:5173`) to create chart
   events for whatever symbol you want to test (e.g. BTC).
2. Open that asset in the **Flutter app**.
3. Within ~1 second the chart's 1-second delta poll picks up your new
   event and renders a marker on the candlestick.

If anything in the chain breaks, work from the bottom up:
`/health` → API logs → dashboard network tab → Flutter console.

---

## Environment Variables Reference

Consolidated list of every variable referenced anywhere in the repo,
with defaults and where to set them.

### Events API (`_x/api/.env`)

| Variable                    | Default     | Required | Notes                                              |
| --------------------------- | ----------- | :------: | -------------------------------------------------- |
| `SUPABASE_URL`              | —           |   yes    | `https://<project-ref>.supabase.co`                |
| `SUPABASE_SERVICE_ROLE_KEY` | —           |   yes    | Service-role JWT. Server-side only.                |
| `PORT`                      | `4001`      |    no    | TCP port for the Express server.                   |
| `HOST`                      | `0.0.0.0`   |    no    | Bind interface. Keep `0.0.0.0` for emulator reach. |

### Web Dashboard (`_x/web/.env`)

| Variable             | Default                  | Required | Notes                              |
| -------------------- | ------------------------ | :------: | ---------------------------------- |
| `VITE_API_BASE_URL`  | `http://localhost:4001`  |    no    | Base URL of the Events API.        |

### Flutter App (compile-time `--dart-define`)

| Variable                | Default                  | Required | Notes                                                    |
| ----------------------- | ------------------------ | :------: | -------------------------------------------------------- |
| `EVENTS_API_BASE_URL`   | `http://localhost:4001`  |    no    | Base URL of the Events API. See target-by-target table above. |

### Placeholders to remember

When copy-pasting from this README:

```
YOUR_PROJECT_REF        → the random ID before .supabase.co
YOUR_SERVICE_ROLE_KEY   → the long JWT under Project Settings → API
<your-mac-LAN-ip>       → e.g. 192.168.1.42
<your-machine-LAN-ip>   → same idea on Linux / Windows
```

---

## Verifying Your Setup

Three quick smoke tests. Run them in order — each builds on the
previous.

### A. API can reach Supabase

```bash
curl http://localhost:4001/health
# → {"status":"ok","service":"lumina-events-api"}

curl 'http://localhost:4001/v1/events/BTC?limit=1'
# → {"asset":"BTC","from":"...","to":"...","count":0,"events":[]}
```

A 200 response with `count: 0` means the server reached Supabase and
the table exists. A 502 means the credentials in `_x/api/.env` are
wrong.

### B. Dashboard can talk to the API

1. Open `http://localhost:5173/?asset=BTC` in your browser.
2. Click **New event**, fill in the form, submit.
3. The list should refresh to show your new event.
4. Re-run the curl above — `count` should now be `1`.

### C. Flutter app can pick up the new event

1. Launch the Flutter app and navigate to **Markets** → **BTC**.
2. The chart should render the candlestick within a few seconds.
3. Within 1 second of step B, a marker for your event appears on the
   chart at the timestamp you supplied (or "now" if you omitted it).

If all three pass, the stack is healthy.

---

## Common Tasks

### Run the Flutter test suite

```bash
flutter test
```

Tests live in `test/` and cover blocs, repositories, services, and
core utilities. The full suite runs in well under a minute.

### Run a single Flutter test file

```bash
flutter test test/blocs/chart_bloc_test.dart
```

### Lint the API or dashboard

```bash
cd _x/web && yarn lint     # eslint over the dashboard
```

(There is no separate linter for `_x/api` today — the codebase is
small enough that prettier's default rules suffice. Add one if the
project grows.)

### Reset Hive-backed local fills

The Flutter app persists user "fills" (paper trades) in a local Hive
box. To clear it without re-installing:

- **iOS Simulator:** Device menu → Erase All Content and Settings.
- **macOS:** delete `~/Library/Containers/<bundle-id>/Data/Documents/`.
- **Android:** Settings → Apps → Lumina → Storage → Clear data.

### Pull the latest changes

```bash
git pull
flutter pub get             # if pubspec.lock changed
(cd _x/api && yarn install) # if _x/api/yarn.lock changed
(cd _x/web && yarn install) # if _x/web/yarn.lock changed
```

---

## Troubleshooting

### `flutter doctor` fails iOS checks

Make sure Xcode and CocoaPods are installed and that you accepted the
Xcode license:

```bash
sudo xcodebuild -license accept
sudo gem install cocoapods
```

### Events API throws on boot

```
Error: Missing Supabase config. Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in _x/api/.env
```

You either don't have an `.env` file, the variable names are typo'd,
or you're running `yarn dev` from outside the `_x/api` directory.
`dotenv` reads `_x/api/.env` relative to where the process started.

### Dashboard shows "Failed to load events"

1. Open the browser DevTools Network tab and check the failing request.
2. Confirm the URL matches `VITE_API_BASE_URL` in `_x/web/.env`.
3. Confirm the API is up via `curl http://localhost:4001/health`.
4. If the URL is right but the request is blocked, check the API
   server's CORS headers — by default it returns `*`, so any origin is
   allowed.

### Flutter chart shows no event markers

This is almost always one of:

- **Wrong `EVENTS_API_BASE_URL` for your platform.** Re-check the
  target-by-target table in [Step 4](#step-4--flutter-app).
- **Stale build.** Compile-time defines need a full rebuild. Quit and
  re-run `flutter run` with the correct `--dart-define`.
- **Symbol mismatch.** The dashboard creates events with an uppercased
  symbol. The Flutter chart asks for events with the same uppercased
  symbol. Custom tickers (e.g. `cyan` typed lowercase in the
  dashboard) are normalised by the API, but worth verifying with
  `curl 'http://localhost:4001/v1/events?asset=BTC&limit=5'`.

### Android emulator can't reach the API

Use `http://10.0.2.2:4001` rather than `http://localhost:4001`. From
the emulator's perspective `localhost` is the emulator itself, not
your host machine. `10.0.2.2` is the special address the AVD uses to
reach the host loopback. An ngrok HTTPS URL also works (see
[4.4](#44-using-ngrok-for-any-network-access)) and avoids the need to
whitelist cleartext HTTP in `network_security_config.xml`.

### iOS physical device can't reach the API

`localhost` resolves to the phone, not your Mac. You have two options:

1. **Same Wi-Fi network:** find your Mac's LAN IP
   (`ipconfig getifaddr en0`) and use `http://<that-ip>:4001`. The
   phone and Mac must be on the same Wi-Fi network. If macOS blocks
   incoming connections (common on "public" network profiles or with
   the firewall on), either flip the network to "private" or
   temporarily disable the firewall.
2. **Any network (recommended when LAN doesn't work):** open an ngrok
   tunnel and use the resulting `https://...ngrok-free.app` URL —
   see [4.4 Using ngrok for any-network access](#44-using-ngrok-for-any-network-access).
   Bonus: HTTPS sidesteps iOS App Transport Security entirely, so you
   don't have to whitelist cleartext HTTP in `Info.plist`.

### "I made a code change but the Flutter app shows the old behavior"

- **Layout / widget tweaks:** hot reload (`r`).
- **State or static initializer changes:** hot restart (`R`).
- **`--dart-define` value changes, dependency changes, or native
  plugin changes:** full stop and `flutter run` again.

### Yarn vs npm

This repo's lockfiles are `yarn.lock`. **Use `yarn`, not `npm`.**
Mixing the two creates conflicting `package-lock.json` /
`yarn.lock` pairs that confuse later contributors and CI.

---

## Where to go next

- [`docs/LIVE_DATA_AND_EVENTS.md`](./docs/LIVE_DATA_AND_EVENTS.md) —
  architecture writeup with Mermaid diagrams covering the live ticker
  mock, the historical warehouse, the cache layer, and the events
  pipeline.
- [`_x/api/README.md`](./_x/api/README.md) — full Events API endpoint
  reference (request/response shapes, validation, examples).
- [`_x/web/README.md`](./_x/web/README.md) — dashboard internals
  (component tree, styling tokens).
- `lib/` — Flutter source, organised by `data/` (models, services,
  repositories), `presentation/` (BLoCs, screens, widgets), and
  `design_system/` (tokens, primitives).
