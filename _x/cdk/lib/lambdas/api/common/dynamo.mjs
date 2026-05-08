import { DynamoDBClient } from "@aws-sdk/client-dynamodb"
import { DynamoDBDocumentClient } from "@aws-sdk/lib-dynamodb"

/**
 * Shared DynamoDB document client. Re-uses the same connection across
 * warm invocations of a lambda instance so we don't pay the TLS
 * handshake cost on every request.
 */
let cachedDoc = null

export const getDocClient = () => {
  if (cachedDoc) return cachedDoc
  const ddb = new DynamoDBClient({})
  cachedDoc = DynamoDBDocumentClient.from(ddb, {
    marshallOptions: { removeUndefinedValues: true },
  })
  return cachedDoc
}

export const EVENT_CACHE_TABLE = () => {
  const name = process.env.EVENT_CACHE_TABLE
  if (!name) throw new Error("EVENT_CACHE_TABLE env var is not set")
  return name
}
