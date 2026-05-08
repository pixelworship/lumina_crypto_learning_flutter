// Per-asset "latest event timestamp" cache.
//
// The polling endpoint (`GET /v1/events/since`) is the hot path: every
// mounted chart re-asks "anything new for BTC since 12:34:56?" once a
// second, and the answer is almost always "no". Caching that answer
// turns the steady-state cost from one Supabase query per poll into
// either a single DynamoDB GetItem (~5ms, batched per warm container)
// or — for repeat hits inside the same container — zero network calls.
//
// Two layers stacked together:
//
//   1. In-memory `memo` map on the lambda container, ~2s TTL. This
//      catches multiple invocations of the same container hammering
//      the same asset. Bounded to ~9 entries (one per supported
//      ticker), so memory pressure is irrelevant.
//
//   2. DynamoDB `EventCache` table, configurable TTL (`EVENT_CACHE_
//      TTL_SECONDS`, default 60s). Shared across all warm containers.
//      Last-writer-wins on conflict — the value is monotonically
//      increasing in practice, so collisions just mean one updater's
//      bump is overwritten by another's equal-or-greater bump.
//
// Semantics: `latestEventTimestamp` is "the newest `created_at` we are
// aware of for this asset". Cache is considered FRESH if `refreshedAt`
// is within the TTL window, STALE otherwise. Stale entries are still
// returned — callers decide whether to trust them. The TTL is the
// safety net for out-of-band Supabase writes (manual SQL editor
// inserts) that never go through our lambdas; without TTL such inserts
// would be invisible to readers forever.

import { GetCommand, UpdateCommand } from "@aws-sdk/lib-dynamodb"
import { EVENT_CACHE_TABLE, getDocClient } from "./dynamo.mjs"

const MEMO_TTL_MS = 2_000

const ttlMs = () => {
  const raw = Number(process.env.EVENT_CACHE_TTL_SECONDS || "60")
  return Number.isFinite(raw) && raw > 0 ? raw * 1000 : 60_000
}

/** asset → { latestEventTimestamp, refreshedAt, fetchedAt } */
const memo = new Map()

const memoGet = (asset) => {
  const hit = memo.get(asset)
  if (!hit) return null
  if (Date.now() - hit.fetchedAt >= MEMO_TTL_MS) {
    memo.delete(asset)
    return null
  }
  return hit
}

const memoSet = (asset, latestEventTimestamp, refreshedAt) => {
  memo.set(asset, {
    latestEventTimestamp,
    refreshedAt,
    fetchedAt: Date.now(),
  })
}

/**
 * Returns `{ latestEventTimestamp, refreshedAt, isFresh }` for the
 * given asset, or `null` if no entry exists. `isFresh` is whether
 * `refreshedAt` is within `EVENT_CACHE_TTL_SECONDS` of now — callers
 * use this to decide whether to trust the cached value or fall through
 * to Supabase.
 *
 * Never throws. DynamoDB blips return `null` so the calling lambda
 * just degrades to "no cache" for that request.
 */
export async function getCacheEntry(asset) {
  const memoHit = memoGet(asset)
  if (memoHit) {
    return {
      latestEventTimestamp: memoHit.latestEventTimestamp,
      refreshedAt: memoHit.refreshedAt,
      isFresh: Date.now() - memoHit.refreshedAt < ttlMs(),
    }
  }

  try {
    const res = await getDocClient().send(
      new GetCommand({
        TableName: EVENT_CACHE_TABLE(),
        Key: { asset },
      }),
    )
    if (!res.Item) return null
    const latestEventTimestamp = res.Item.latestEventTimestamp
    const refreshedAt = Number(res.Item.refreshedAt) || 0
    if (typeof latestEventTimestamp !== "string" || !latestEventTimestamp) {
      return null
    }
    memoSet(asset, latestEventTimestamp, refreshedAt)
    return {
      latestEventTimestamp,
      refreshedAt,
      isFresh: Date.now() - refreshedAt < ttlMs(),
    }
  } catch (err) {
    console.error("[eventCache:get] failed:", err)
    return null
  }
}

/**
 * Bumps the cached `latestEventTimestamp` for `asset` to
 * `max(current, isoTimestamp)` and refreshes the TTL.
 *
 * Implementation note: DynamoDB's UpdateExpression has no `max()`
 * function. We use a ConditionExpression that only writes when the new
 * value is greater-or-equal to the existing one. ConditionalCheck
 * failures are silently ignored — they mean another container already
 * wrote a newer value, which is the outcome we wanted anyway.
 *
 * Never throws — telemetry only. The caller's response shape doesn't
 * change whether the cache write succeeded or not.
 */
export async function recordLatestTimestamp(asset, isoTimestamp) {
  if (typeof isoTimestamp !== "string" || !isoTimestamp) return

  const now = Date.now()

  // Update the in-memory layer optimistically. Subsequent invocations
  // on the same warm container see this without a DDB round-trip.
  const memoHit = memo.get(asset)
  if (!memoHit || isoTimestamp > memoHit.latestEventTimestamp) {
    memoSet(asset, isoTimestamp, now)
  } else {
    memoHit.refreshedAt = now
    memoHit.fetchedAt = now
  }

  try {
    await getDocClient().send(
      new UpdateCommand({
        TableName: EVENT_CACHE_TABLE(),
        Key: { asset },
        UpdateExpression:
          "SET latestEventTimestamp = :ts, refreshedAt = :now",
        ConditionExpression:
          "attribute_not_exists(latestEventTimestamp) OR latestEventTimestamp <= :ts",
        ExpressionAttributeValues: {
          ":ts": isoTimestamp,
          ":now": now,
        },
      }),
    )
  } catch (err) {
    if (err?.name === "ConditionalCheckFailedException") {
      // A concurrent writer already pushed the watermark past us.
      // Bump just `refreshedAt` so the stored entry stays "fresh"
      // and other containers can keep using it without re-querying.
      try {
        await getDocClient().send(
          new UpdateCommand({
            TableName: EVENT_CACHE_TABLE(),
            Key: { asset },
            UpdateExpression: "SET refreshedAt = :now",
            ExpressionAttributeValues: { ":now": now },
          }),
        )
      } catch (err2) {
        console.error("[eventCache:put] refreshedAt bump failed:", err2)
      }
      return
    }
    console.error("[eventCache:put] failed:", err)
  }
}

/**
 * Convenience: should `getEventsSince` skip Supabase entirely for this
 * `since` cursor? True iff the cache entry is fresh AND the caller's
 * cursor is at or past the cached high-watermark.
 */
export function canSkipSupabase(entry, since) {
  if (!entry || !entry.isFresh) return false
  if (!(since instanceof Date) || !Number.isFinite(since.getTime())) {
    return false
  }
  const cachedAt = Date.parse(entry.latestEventTimestamp)
  if (!Number.isFinite(cachedAt)) return false
  return since.getTime() >= cachedAt
}
