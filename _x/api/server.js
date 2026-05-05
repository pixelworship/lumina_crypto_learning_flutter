// Lumina events API — Express entry point.
//
// Reads / writes Supabase `chart_events` and exposes a small JSON
// surface used by the Flutter app and the `_x/web` dashboard.
//
// Run locally:
//
//   yarn install
//   yarn dev      # node --watch, restarts on file changes
//   yarn start    # production-ish: plain `node server.js`
//
// Configuration via env vars (loaded from `_x/api/.env`):
//
//   PORT                           default 4001
//   HOST                           default 0.0.0.0
//   SUPABASE_URL                   required
//   SUPABASE_SERVICE_ROLE_KEY      required
//
// All routes are versioned under `/v1/...`; `/health` is unversioned
// for trivial liveness checks.

import "dotenv/config"

import express from "express"

import { assetsRouter } from "./routes/assets.js"
import { eventsRouter } from "./routes/events.js"

const app = express()

app.disable("x-powered-by")

// Permissive CORS — dev-only mock server. Lock down behind a reverse
// proxy if this ever gets exposed beyond a local machine.
app.use((req, res, next) => {
  res.setHeader("Access-Control-Allow-Origin", "*")
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
  res.setHeader("Access-Control-Allow-Headers", "Content-Type")
  if (req.method === "OPTIONS") {
    return res.status(204).end()
  }
  return next()
})

app.use(express.json({ limit: "32kb" }))

// Lightweight access log — one line per request, no deps.
app.use((req, res, next) => {
  const startedAt = process.hrtime.bigint()
  res.on("finish", () => {
    const dtMs = Number(process.hrtime.bigint() - startedAt) / 1e6
    process.stdout.write(
      `[${new Date().toISOString()}] ${req.method} ${req.originalUrl} ` +
        `→ ${res.statusCode} (${dtMs.toFixed(1)}ms)\n`,
    )
  })
  next()
})

app.get("/health", (_req, res) => {
  res.json({ status: "ok", service: "lumina-events-api" })
})

app.get("/", (_req, res) => {
  res.json({
    service: "lumina-events-api",
    version: "0.3.0",
    routes: [
      "GET    /health",
      "GET    /v1/assets",
      "GET    /v1/events?asset=BTC&from=ISO&to=ISO&limit=200",
      "GET    /v1/events/since?asset=BTC&since=ISO&limit=500",
      "GET    /v1/events/:asset",
      "POST   /v1/events            { asset, title, body?, link? }",
      "DELETE /v1/events/:id",
    ],
  })
})

app.use("/v1/assets", assetsRouter)
app.use("/v1/events", eventsRouter)

app.use((_req, res) => {
  res.status(404).json({
    error: "not_found",
    message: "No route. See GET / for available endpoints.",
  })
})

app.use((err, _req, res, _next) => {
  if (err?.type === "entity.parse.failed") {
    return res.status(400).json({
      error: "invalid_json",
      message: "Request body is not valid JSON.",
    })
  }
  process.stderr.write(`[server:error] ${err?.stack ?? err}\n`)
  return res.status(500).json({
    error: "internal_error",
    message: "Unhandled server error.",
  })
})

const PORT = Number(process.env.PORT ?? 4001)
const HOST = process.env.HOST ?? "0.0.0.0"

app.listen(PORT, HOST, () => {
  process.stdout.write(
    `[lumina-events-api] listening on http://${HOST}:${PORT}\n`,
  )
})
