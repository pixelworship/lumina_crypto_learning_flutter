/**
 * Standard API Gateway (REST API + Lambda Proxy) response formatter.
 *
 * Basic usage:
 *   return formatResponse(200, { ok: true })
 *   return formatResponse(400, { error: "bad request" })
 *
 * Pass `event` (or `origin`) so the response carries the correct
 * `Access-Control-Allow-Origin` header. Browsers reject `*` together with
 * `Access-Control-Allow-Credentials: true`, so we echo the request origin
 * back when it matches the configured allowlist.
 *
 * When `ALLOWED_WEB_ORIGINS` is empty we default to `*` and drop the
 * `Access-Control-Allow-Credentials` header — which is the right shape for
 * an API that doesn't use cookies and is consumed by a Flutter mobile
 * client + a public dashboard.
 */

const parseAllowedOrigins = () => {
  const list = process.env.ALLOWED_WEB_ORIGINS || ""
  return list
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean)
}

export const resolveAllowedOrigin = (requestOrigin) => {
  const allowed = parseAllowedOrigins()
  // Empty list OR a literal `*` in the allowlist ⇒ wide-open CORS.
  // Returning `*` from here makes the caller drop the credentials
  // header (browsers reject `*` + credentials together).
  if (!allowed.length || allowed.includes("*")) return "*"
  if (requestOrigin && allowed.includes(requestOrigin)) return requestOrigin
  return allowed[0]
}

const originFromEvent = (event) => {
  if (!event) return null
  const headers = event.headers || {}
  return headers.origin || headers.Origin || null
}

export const formatResponse = (statusCode, body, opts = {}) => {
  const {
    cookies = [],
    redirect = null,
    extraHeaders = {},
    origin = null,
    event = null,
  } = opts

  if (statusCode >= 200 && statusCode < 400) {
    console.log(`Status: ${statusCode}, Body: ${JSON.stringify(body, 0, 2)}`)
  } else {
    console.error(`Status: ${statusCode}, Body: ${JSON.stringify(body, 0, 2)}`)
  }

  const requestOrigin = origin || originFromEvent(event)
  const allowOrigin = resolveAllowedOrigin(requestOrigin)
  const credentialed = allowOrigin !== "*"

  const headers = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Headers":
      "Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token,Cookie",
    "Access-Control-Allow-Origin": allowOrigin,
    "Access-Control-Allow-Methods": "OPTIONS,GET,POST,PUT,DELETE",
    "X-XSS-Protection": "1; mode=block",
    "X-Content-Type-Options": "nosniff",
    "Strict-Transport-Security":
      "max-age=31536000; includeSubDomains; preload",
    "Vary": "Origin",
    ...extraHeaders,
  }

  if (credentialed) {
    headers["Access-Control-Allow-Credentials"] = "true"
  }

  if (redirect) {
    headers.Location = redirect
  }

  const response = {
    statusCode,
    headers,
    body: body == null ? "" : JSON.stringify(body),
  }

  if (cookies.length > 0) {
    response.multiValueHeaders = {
      "Set-Cookie": cookies,
    }
  }

  return response
}

export const delay = (ms) => {
  return new Promise((resolve) => setTimeout(resolve, ms))
}
