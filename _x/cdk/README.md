# Lumina Events CDK

AWS deployment for the Lumina events API — Supabase-backed CRUD for the
`chart_events` table that feeds the Flutter app's chart markers and the
`_x/web` dashboard.

This is the deployable counterpart to the local Express server in
`_x/api/server.js`. Same routes, same response shapes — just running on
API Gateway + Lambda + Supabase instead of `node --watch`.

## What gets deployed

A single CloudFormation stack (`LuminaEventsAPI` by default — controlled
by `AWS_PROJECT_NAME` in `.env`) with:

- **REST API Gateway** with permissive CORS (or an explicit origin
  allowlist when `ALLOWED_WEB_ORIGINS` is set).
- **7 Node.js 22 Lambdas** (sharing `lib/lambdas/api/` as their bundle):

  | Method | Route                  | Handler                    |
  | ------ | ---------------------- | -------------------------- |
  | GET    | `/health`              | `health.mjs`               |
  | GET    | `/v1/assets`           | `getAssets.mjs`            |
  | GET    | `/v1/events`           | `listEvents.mjs`           |
  | POST   | `/v1/events`           | `createEvent.mjs`          |
  | GET    | `/v1/events/since`     | `getEventsSince.mjs`       |
  | GET    | `/v1/events/{key}`     | `getEventsByAsset.mjs`     |
  | DELETE | `/v1/events/{key}`     | `deleteEvent.mjs`          |

  `{key}` is interpreted as the asset symbol on GET and as the event id
  on DELETE. API Gateway requires a single path-parameter name per
  resource, so we share `{key}` across both methods.

- **DynamoDB `EventCache` table** — per-asset high-watermark cache that
  lets the polling endpoints short-circuit Supabase entirely when
  nothing has changed. See [Caching](#caching) below.

## Caching

The Flutter chart polls `/v1/events/since` once per second per mounted
asset. ~99% of those calls return an empty array. To avoid burning a
Supabase query on every "no, nothing's new" answer, every event lambda
consults a tiny `EventCache` table before talking to Supabase.

**Schema** (`${AWS_PROJECT_NAME}-EventCache`):

| Attribute               | Type   | Notes                                            |
| ----------------------- | ------ | ------------------------------------------------ |
| `asset` (PK)            | String | `BTC`, `ETH`, etc.                               |
| `latestEventTimestamp`  | String | ISO of the newest `created_at` we know about     |
| `refreshedAt`           | Number | Epoch ms — when the entry was last touched       |

**Two cache layers** stacked together, in `common/eventCache.mjs`:

1. **In-memory** (per warm container, ~2s TTL). Catches bursts of
   identical polls hitting the same container — zero network calls
   for those.
2. **DynamoDB** (shared across containers, configurable TTL via
   `EVENT_CACHE_TTL_SECONDS`, default 60s). One `GetItem` per cold
   container per asset (~5ms).

**When does it fire?**

- `GET /v1/events/since?asset=X&since=T` — short-circuits when the
  cache is fresh AND `T >= latestEventTimestamp`. Hot path.
- `GET /v1/events?asset=X&from=T&...` — short-circuits when the cache
  is fresh AND `latestEventTimestamp < T` (window starts after the
  newest event).
- `GET /v1/events/{asset}` — same as above for the implicit 24h window.

When the cache fires, the response body includes `"cached": true` so
clients (and you) can see the path was taken. Look for
`[getEventsSince] cache hit asset=…` in CloudWatch logs.

**When does it invalidate?**

- `POST /v1/events` writes through to the cache after a successful
  Supabase insert, so newly-created events become visible to readers
  on the very next poll without waiting for the TTL.
- Successful `since` queries that return events bump the watermark to
  the newest event seen.
- Successful `since` queries that return zero events also bump the
  watermark to `since` itself — we just confirmed nothing exists past
  it. The TTL caps the staleness for this case.

**Out-of-band writes** (manual `INSERT` via the Supabase SQL editor)
are invisible to the cache. They become visible after at most
`EVENT_CACHE_TTL_SECONDS` thanks to the TTL refresh.

## Setup

Fill in `.env`:

```env
AWS_PROJECT_NAME=LuminaEventsAPI
CDK_ACCOUNT=123456789012
CDK_REGION=us-west-2
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=...

# Optional — leave blank for permissive `*` CORS, or set when locking
# the API down to specific frontends.
ALLOWED_WEB_ORIGINS=

# Required — copied from `_x/api/.env`. The deployed API uses the same
# Supabase project so the Flutter app and the deployed lambdas read the
# same `chart_events` rows.
SUPABASE_URL=https://<ref>.supabase.co
SUPABASE_SERVICE_ROLE_KEY=...
SUPABASE_JWT_SECRET=...
```

### Install + deploy

```bash
# CDK toolchain (yarn — per project convention)
yarn install

# Lambda runtime deps (npm — package.json drives the bundle that gets
# uploaded to AWS, so we keep node_modules colocated with the handlers).
cd lib/lambdas/api && npm install && cd -

# One-time per AWS account/region.
yarn bootstrap

# Deploy.
yarn deploy
```

## Outputs

After `yarn deploy`, CloudFormation prints:

- `LuminaEventsAPIApiUrl` — base URL of the REST API. Use as the
  Flutter app's `LUMINA_API_BASE_URL` (or wherever the dashboard reads
  its API base from).
- `LuminaEventsAPIHealthUrl` — quick `curl`-able liveness check.
- One pair of `FunctionName` / `FunctionArn` outputs per lambda.

## Layout

```
_x/cdk/
├── bin/
│   └── cdk.ts                       # entrypoint, loads .env via dotenv
├── lib/
│   ├── api-stack.ts                 # REST API + Lambdas + EventCache + IAM
│   └── lambdas/
│       └── api/                     # bundled into every lambda
│           ├── package.json         # lambda runtime deps (npm-managed)
│           ├── health.mjs
│           ├── getAssets.mjs
│           ├── listEvents.mjs
│           ├── getEventsSince.mjs
│           ├── getEventsByAsset.mjs
│           ├── createEvent.mjs
│           ├── deleteEvent.mjs
│           └── common/
│               ├── formatResponse.mjs
│               ├── supabase.mjs
│               ├── dynamo.mjs
│               ├── eventCache.mjs   # in-memory + DDB high-watermark cache
│               ├── assets.mjs
│               └── parsers.mjs
├── cdk.json
├── package.json                     # CDK deps (yarn-managed)
├── tsconfig.json
└── .env                             # gitignored
```

## Smoke testing

```bash
API_URL=$(aws cloudformation describe-stacks \
  --stack-name LuminaEventsAPI \
  --query 'Stacks[0].Outputs[?OutputKey==`LuminaEventsAPIApiUrl`].OutputValue' \
  --output text)

curl "${API_URL}health"
curl "${API_URL}v1/assets"
curl "${API_URL}v1/events?asset=BTC&limit=10"
curl "${API_URL}v1/events/BTC"

curl -X POST "${API_URL}v1/events" \
  -H "Content-Type: application/json" \
  -d '{"asset":"BTC","title":"Test event","body":"hello"}'
```
