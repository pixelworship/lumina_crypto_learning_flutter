import * as cdk from "aws-cdk-lib"
import { APIStack } from "../lib/api-stack"
import "dotenv/config"

const app = new cdk.App()

// Treat empty strings the same as missing — `.env` defaults `CDK_ACCOUNT`
// to "" so callers using `--profile <name>` (or default credentials) can
// let CDK resolve the account/region from the active profile at deploy
// time instead of hardcoding it. Passing `account: ""` renders
// `aws:///us-west-2` which CDK rejects as malformed.
const env: cdk.Environment = {
  account: process.env.CDK_ACCOUNT || undefined,
  region: process.env.CDK_REGION || undefined,
}

const projectName = process.env.AWS_PROJECT_NAME || "LuminaEventsAPI"

logEnvSummary(projectName, env)

new APIStack(app, projectName, {
  env,
})

// Prints a one-shot summary of every env var the CDK + lambdas care about,
// masking secrets so the log is safe to paste into a screenshot. Anything
// "(missing)" is what's blocking the deploy.
function logEnvSummary(projectName: string, env: cdk.Environment): void {
  const mask = (v: string | undefined, keep = 4): string => {
    if (!v) return "(missing)"
    if (v.length <= keep) return "*".repeat(v.length)
    return `${v.slice(0, keep)}…${"*".repeat(Math.min(8, v.length - keep))}`
  }
  const show = (v: string | undefined): string => v || "(missing)"

  const rows: Array<[string, string]> = [
    ["AWS_PROJECT_NAME (resolved)", projectName],
    ["CDK_ACCOUNT", show(env.account)],
    ["CDK_REGION", show(env.region)],
    ["AWS_PROFILE", show(process.env.AWS_PROFILE)],
    ["AWS_ACCESS_KEY_ID", mask(process.env.AWS_ACCESS_KEY_ID)],
    ["AWS_SECRET_ACCESS_KEY", mask(process.env.AWS_SECRET_ACCESS_KEY)],
    ["AWS_SESSION_TOKEN", mask(process.env.AWS_SESSION_TOKEN)],
    ["ALLOWED_WEB_ORIGINS", show(process.env.ALLOWED_WEB_ORIGINS)],
    ["SUPABASE_URL", show(process.env.SUPABASE_URL)],
    ["SUPABASE_SERVICE_ROLE_KEY", mask(process.env.SUPABASE_SERVICE_ROLE_KEY)],
    ["SUPABASE_JWT_SECRET", mask(process.env.SUPABASE_JWT_SECRET)],
  ]

  const keyWidth = Math.max(...rows.map(([k]) => k.length))
  console.log("─── _x/cdk env summary ─────────────────────────────")
  for (const [k, v] of rows) {
    console.log(`  ${k.padEnd(keyWidth)}  ${v}`)
  }
  console.log("────────────────────────────────────────────────────")
}
