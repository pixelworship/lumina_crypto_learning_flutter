import { Stack, StackProps, CfnOutput, Duration, RemovalPolicy } from "aws-cdk-lib"
import { Construct } from "constructs"
import {
  Architecture,
  Code,
  Function,
  Runtime,
} from "aws-cdk-lib/aws-lambda"
import { join } from "path"
import {
  Cors,
  LambdaIntegration,
  MethodLoggingLevel,
  RestApi,
} from "aws-cdk-lib/aws-apigateway"
import { ManagedPolicy, Role, ServicePrincipal } from "aws-cdk-lib/aws-iam"
import {
  AttributeType,
  BillingMode,
  Table,
  TableEncryption,
} from "aws-cdk-lib/aws-dynamodb"

interface Props extends StackProps {}

export class APIStack extends Stack {
  private roleName: string

  constructor(scope: Construct, id: string, props: Props) {
    super(scope, id, props)

    this.roleName = `${this.stackName}Role`
    const role = this.createLambdaRole(this.roleName)

    const {
      SUPABASE_URL,
      SUPABASE_SERVICE_ROLE_KEY,
      SUPABASE_JWT_SECRET,
      ALLOWED_WEB_ORIGINS,
    } = process.env

    if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
      throw new Error(
        "Please set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in _x/cdk/.env"
      )
    }

    // Origins allowed to call the API. Empty list (or a literal `*`) ⇒
    // permissive `*` for the API Gateway preflight, no credentials. Set
    // ALLOWED_WEB_ORIGINS to a comma-separated list when you're ready to
    // lock down the dashboard. Mixing `*` with `Access-Control-Allow-
    // Credentials: true` is a browser-rejected combo, so the
    // explicit-allowlist branch is the only one that turns credentials on.
    const rawOrigins = (ALLOWED_WEB_ORIGINS || "")
      .split(",")
      .map((o) => o.trim())
      .filter(Boolean)
    const wildcardOrigin = rawOrigins.includes("*")
    const allowedOrigins = wildcardOrigin
      ? []
      : rawOrigins

    // Per-asset "latest event timestamp" cache. The polling endpoint
    // (`GET /v1/events/since`) hammers Supabase once per second per
    // mounted chart even when nothing's changed — this table lets us
    // short-circuit those calls with an empty array when we already
    // know there's been no new event for the asset.
    //
    // The shape is intentionally tiny so we never have to scan or
    // paginate: PK = asset symbol, attributes = `latestEventTimestamp`
    // (ISO string) + `refreshedAt` (epoch ms). Updates are last-writer-
    // wins, monotonically increasing in practice — readers and writers
    // both bump the value to `max(seen, current)`.
    const eventCacheTable = new Table(this, "EventCacheTable", {
      tableName: `${this.stackName}-EventCache`,
      partitionKey: { name: "asset", type: AttributeType.STRING },
      billingMode: BillingMode.PAY_PER_REQUEST,
      encryption: TableEncryption.AWS_MANAGED,
      removalPolicy: RemovalPolicy.DESTROY,
    })

    const lambdaEnv = {
      SUPABASE_URL,
      SUPABASE_SERVICE_ROLE_KEY,
      SUPABASE_JWT_SECRET: SUPABASE_JWT_SECRET || "",
      ALLOWED_WEB_ORIGINS: allowedOrigins.join(","),
      EVENT_CACHE_TABLE: eventCacheTable.tableName,
      // How long to trust a cached `latestEventTimestamp` before falling
      // back to Supabase. Out-of-band SQL inserts (manual backfill via
      // the Supabase console) are invisible to the cache, so this TTL
      // is the worst-case staleness window for those.
      EVENT_CACHE_TTL_SECONDS: process.env.EVENT_CACHE_TTL_SECONDS || "60",
    }

    const healthFunction = this.createFunction(
      "Health",
      role,
      "health",
      lambdaEnv
    )

    const getAssetsFunction = this.createFunction(
      "GetAssets",
      role,
      "getAssets",
      lambdaEnv
    )

    const listEventsFunction = this.createFunction(
      "ListEvents",
      role,
      "listEvents",
      lambdaEnv
    )

    const getEventsSinceFunction = this.createFunction(
      "GetEventsSince",
      role,
      "getEventsSince",
      lambdaEnv
    )

    const getEventsByAssetFunction = this.createFunction(
      "GetEventsByAsset",
      role,
      "getEventsByAsset",
      lambdaEnv
    )

    const createEventFunction = this.createFunction(
      "CreateEvent",
      role,
      "createEvent",
      lambdaEnv
    )

    const deleteEventFunction = this.createFunction(
      "DeleteEvent",
      role,
      "deleteEvent",
      lambdaEnv
    )

    // Every lambda that reads or writes events also touches the
    // EventCache table — readers do `GetItem` to find the cached
    // high-watermark, and writers do `UpdateItem` to bump it after
    // either a successful insert or a fresh Supabase query. Skip the
    // assets/health lambdas; they don't query `chart_events`.
    const eventLambdas = [
      listEventsFunction,
      getEventsSinceFunction,
      getEventsByAssetFunction,
      createEventFunction,
    ]
    for (const fn of eventLambdas) {
      eventCacheTable.grantReadWriteData(fn)
    }

    const STAGE_NAME = "prod"

    const api = new RestApi(this, `${this.stackName}Api`, {
      defaultCorsPreflightOptions: {
        allowOrigins:
          allowedOrigins.length > 0 ? allowedOrigins : Cors.ALL_ORIGINS,
        allowMethods: Cors.ALL_METHODS,
        allowCredentials: allowedOrigins.length > 0,
        allowHeaders: Cors.DEFAULT_HEADERS,
      },
      restApiName: `lumina-events-rest-api`,
      deployOptions: {
        stageName: STAGE_NAME,
        metricsEnabled: true,
        loggingLevel: MethodLoggingLevel.INFO,
        dataTraceEnabled: true,
      },
      cloudWatchRole: true,
    })

    // Unversioned liveness probe.
    api.root
      .addResource("health")
      .addMethod("GET", new LambdaIntegration(healthFunction), {
        apiKeyRequired: false,
      })

    // Versioned routes — everything user-facing lives under /v1/*.
    const v1 = api.root.addResource("v1")

    v1.addResource("assets").addMethod(
      "GET",
      new LambdaIntegration(getAssetsFunction),
      { apiKeyRequired: false }
    )

    const eventsResource = v1.addResource("events")
    eventsResource.addMethod(
      "GET",
      new LambdaIntegration(listEventsFunction),
      { apiKeyRequired: false }
    )
    eventsResource.addMethod(
      "POST",
      new LambdaIntegration(createEventFunction),
      { apiKeyRequired: false }
    )

    // Literal `/v1/events/since` — registered as a sibling of `/{key}` so
    // API Gateway picks the literal over the path variable on exact matches.
    eventsResource
      .addResource("since")
      .addMethod("GET", new LambdaIntegration(getEventsSinceFunction), {
        apiKeyRequired: false,
      })

    // Single dynamic resource shared by GET (24h shortcut, key=asset) and
    // DELETE (key=id). Each handler interprets `pathParameters.key`
    // accordingly.
    const eventsByKey = eventsResource.addResource("{key}")
    eventsByKey.addMethod(
      "GET",
      new LambdaIntegration(getEventsByAssetFunction),
      { apiKeyRequired: false }
    )
    eventsByKey.addMethod(
      "DELETE",
      new LambdaIntegration(deleteEventFunction),
      { apiKeyRequired: false }
    )

    const apiBaseUrl = `https://${api.restApiId}.execute-api.${this.region}.amazonaws.com/${STAGE_NAME}`

    new CfnOutput(this, `${this.stackName}ApiUrl`, {
      value: `${apiBaseUrl}/`,
      description:
        "Base URL of the Lumina events REST API. Use as `LUMINA_API_BASE_URL` in the Flutter / web app.",
    })
    new CfnOutput(this, `${this.stackName}HealthUrl`, {
      value: `${apiBaseUrl}/health`,
    })
    new CfnOutput(this, `${this.stackName}EventCacheTable`, {
      value: eventCacheTable.tableName,
      description:
        "DynamoDB table that caches the latest known event timestamp per asset. Lets `/v1/events/since` short-circuit polls when nothing has changed.",
    })
  }

  createLambdaRole(roleName: string): Role {
    const role = new Role(this, `${roleName}Role`, {
      assumedBy: new ServicePrincipal("lambda.amazonaws.com"),
      roleName: roleName,
    })

    role.addManagedPolicy(
      ManagedPolicy.fromAwsManagedPolicyName("AWSLambdaExecute")
    )
    role.addManagedPolicy(
      ManagedPolicy.fromAwsManagedPolicyName("service-role/AWSLambdaRole")
    )

    return role
  }

  createFunction(
    name: String,
    role: Role,
    handlerFileName: String,
    environment: { [key: string]: string },
    memorySize: number = 256,
    timeout: number = 15
  ): Function {
    const functionName = `${this.stackName}-${name}Function`
    const lambda = new Function(this, functionName, {
      functionName: functionName,
      runtime: Runtime.NODEJS_22_X,
      handler: `${handlerFileName}.handler`,
      code: Code.fromAsset(join(__dirname, "lambdas", "api")),
      memorySize: memorySize,
      architecture: Architecture.X86_64,
      timeout: Duration.seconds(timeout),
      environment,
      role: role,
    })

    new CfnOutput(this, `${functionName}FunctionName`, {
      value: lambda.functionName,
    })

    new CfnOutput(this, `${functionName}FunctionArn`, {
      value: lambda.functionArn,
    })

    return lambda
  }
}
