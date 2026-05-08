import { formatResponse } from "./common/formatResponse.mjs"

/**
 * GET /health
 *
 * Liveness probe. Doesn't touch Supabase — answering 200 here just means
 * the lambda + API Gateway plumbing is wired up. For a deeper check,
 * call any /v1/* endpoint (those will fail loudly if Supabase auth is
 * misconfigured at boot).
 */
export const handler = async (event) => {
  return formatResponse(
    200,
    { status: "ok", service: "lumina-events-api" },
    { event },
  )
}
