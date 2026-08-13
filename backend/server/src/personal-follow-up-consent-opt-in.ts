import {bearerToken} from "./authorization.js";
import {
  IdentityVerificationError,
  type IdentityVerifier,
  type VerifiedIdentity,
} from "./identity.js";
import type {SessionContextStore} from "./session-context.js";

export const personalFollowUpConsentOptInMetric =
  "follow_up_consent_ratio@1";
export const personalFollowUpConsentOptInStateContract =
  "project_follow_up_consent_opt_in_state_v1";
export const personalFollowUpConsentOptInConfigurationContract =
  "project_follow_up_consent_opt_in_configuration_v1";

export interface PersonalFollowUpConsentOptInConfiguration {
  readonly configurationContractId:
    typeof personalFollowUpConsentOptInConfigurationContract;
  readonly metricId: typeof personalFollowUpConsentOptInMetric;
  readonly projectId: string;
  readonly versionNumber: number;
  readonly expectedVersion: number;
  readonly enabled: boolean;
  /** Validated database audit metadata; never serialized to the HTTP client. */
  readonly actorAppUserId: string;
  readonly requestId: string;
  readonly recordedAtUtc: string;
}

export type PersonalFollowUpConsentOptInState = {
  readonly stateContractId: typeof personalFollowUpConsentOptInStateContract;
  readonly metricId: typeof personalFollowUpConsentOptInMetric;
  readonly projectId: string;
} & (
  | {
      readonly status: "not_enabled";
      readonly configuration: PersonalFollowUpConsentOptInConfiguration | null;
    }
  | {
      readonly status: "enabled";
      readonly configuration: PersonalFollowUpConsentOptInConfiguration;
    }
);

export interface PersonalFollowUpConsentOptInInput {
  readonly expectedVersion: number;
  readonly enabled: boolean;
  readonly requestId: string;
}

export interface PersonalFollowUpConsentOptInStore {
  read(
    identity: VerifiedIdentity,
    projectId: string,
  ): Promise<PersonalFollowUpConsentOptInState>;
  configure(
    identity: VerifiedIdentity,
    projectId: string,
    input: PersonalFollowUpConsentOptInInput,
  ): Promise<PersonalFollowUpConsentOptInConfiguration>;
}

export interface PersonalFollowUpConsentOptInDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly contextStore: SessionContextStore;
  readonly optInStore?: PersonalFollowUpConsentOptInStore;
}

export interface PersonalFollowUpConsentOptInRequest {
  readonly method: "GET" | "PUT";
  readonly authorization: string | undefined;
  readonly hasQuery: boolean;
  readonly hasBody: boolean;
  /** Read the PUT body only after authentication and route validation. */
  readonly readBody: () => Promise<unknown>;
}

export interface PersonalFollowUpConsentOptInHttpResult {
  readonly status: number;
  readonly body: Readonly<Record<string, unknown>>;
}

export async function handlePersonalFollowUpConsentOptIn(
  request: PersonalFollowUpConsentOptInRequest,
  dependencies: PersonalFollowUpConsentOptInDependencies,
): Promise<PersonalFollowUpConsentOptInHttpResult> {
  const accessToken = bearerToken(request.authorization);
  if (accessToken === null) return failure(401, "unauthenticated");

  let identity: VerifiedIdentity;
  try {
    identity = await dependencies.identityVerifier.verify(accessToken);
  } catch (error) {
    return error instanceof IdentityVerificationError
      ? failure(401, "unauthenticated")
      : failure(503, "personal_follow_up_consent_opt_in_unavailable");
  }

  if (
    request.hasQuery ||
    (request.method === "GET" && request.hasBody) ||
    (request.method === "PUT" && !request.hasBody)
  ) {
    return failure(400, "invalid_personal_follow_up_consent_opt_in_request");
  }
  if (dependencies.optInStore === undefined) {
    return failure(503, "personal_follow_up_consent_opt_in_unavailable");
  }

  let input: PersonalFollowUpConsentOptInInput | null = null;
  if (request.method === "PUT") {
    input = parseInput(await request.readBody());
    if (input === null) {
      return failure(400, "invalid_personal_follow_up_consent_opt_in_request");
    }
  }

  try {
    const context = await dependencies.contextStore.loadOrCreate(identity);
    const projectId = context.current.project.id;
    if (request.method === "GET") {
      const state = await dependencies.optInStore.read(identity, projectId);
      if (!stateMatchesActor(state, context.appUserId)) throw invalidResult();
      return {status: 200, body: {state: serializeState(state)}};
    }
    if (input === null) {
      return failure(400, "invalid_personal_follow_up_consent_opt_in_request");
    }
    const configuration = await dependencies.optInStore.configure(
      identity,
      projectId,
      input,
    );
    if (!configurationMatchesActor(configuration, context.appUserId)) {
      throw invalidResult();
    }
    return {
      status: 200,
      body: {configuration: serializeConfiguration(configuration)},
    };
  } catch (error) {
    return storeFailure(error);
  }
}

export type PersonalFollowUpConsentOptInQuery = (
  text: string,
  values: readonly unknown[],
) => Promise<{readonly rows: readonly unknown[]}>;

export class PostgresPersonalFollowUpConsentOptInStore
implements PersonalFollowUpConsentOptInStore {
  constructor(private readonly query: PersonalFollowUpConsentOptInQuery) {}

  async read(
    identity: VerifiedIdentity,
    projectId: string,
  ): Promise<PersonalFollowUpConsentOptInState> {
    try {
      const result = await this.query(
        `SELECT app_data.read_project_follow_up_consent_opt_in_v1(
           $1::text, $2::text, $3::uuid, $4::text
         ) AS opt_in_state`,
        [
          identity.issuer,
          identity.subject,
          projectId,
          personalFollowUpConsentOptInMetric,
        ],
      );
      if (result.rows.length !== 1) throw invalidResult();
      return parseState(rowField(result.rows[0], "opt_in_state"), projectId);
    } catch (error) {
      throw mapPostgresError(error, "read");
    }
  }

  async configure(
    identity: VerifiedIdentity,
    projectId: string,
    input: PersonalFollowUpConsentOptInInput,
  ): Promise<PersonalFollowUpConsentOptInConfiguration> {
    try {
      const result = await this.query(
        `SELECT app_data.configure_project_follow_up_consent_opt_in_v1(
           $1::text, $2::text, $3::uuid, $4::text, $5::uuid, $6::integer, $7::boolean
         ) AS opt_in_configuration`,
        [
          identity.issuer,
          identity.subject,
          projectId,
          personalFollowUpConsentOptInMetric,
          input.requestId,
          input.expectedVersion,
          input.enabled,
        ],
      );
      if (result.rows.length !== 1) throw invalidResult();
      const configuration = parseConfiguration(
        rowField(result.rows[0], "opt_in_configuration"),
        projectId,
      );
      if (
        configuration.expectedVersion !== input.expectedVersion ||
        configuration.enabled !== input.enabled ||
        configuration.requestId !== input.requestId.toLowerCase()
      ) {
        throw invalidResult();
      }
      return configuration;
    } catch (error) {
      throw mapPostgresError(error, "configure");
    }
  }
}

export class PersonalFollowUpConsentOptInStoreError extends Error {
  constructor(readonly code: "forbidden" | "conflict" | "invalid") {
    super(code);
    this.name = "PersonalFollowUpConsentOptInStoreError";
  }
}

function parseInput(value: unknown): PersonalFollowUpConsentOptInInput | null {
  if (!isObject(value)) return null;
  if (!hasExactKeys(value, ["expected_version", "enabled", "request_id"])) {
    return null;
  }
  const expectedVersion = postgresNonnegativeInteger(value.expected_version);
  const requestId = nullableUuid(value.request_id);
  if (
    expectedVersion === null ||
    typeof value.enabled !== "boolean" ||
    requestId === null
  ) {
    return null;
  }
  return {expectedVersion, enabled: value.enabled, requestId};
}

function parseState(
  value: unknown,
  expectedProjectId: string,
): PersonalFollowUpConsentOptInState {
  const root = object(value);
  requireExactKeys(root, stateKeys);
  const projectId = uuid(root.project_id);
  if (
    root.state_contract_id !== personalFollowUpConsentOptInStateContract ||
    root.metric_id !== personalFollowUpConsentOptInMetric ||
    projectId !== expectedProjectId.toLowerCase()
  ) {
    throw invalidResult();
  }

  if (root.configuration === null) {
    if (root.status !== "not_enabled") throw invalidResult();
    return {
      stateContractId: personalFollowUpConsentOptInStateContract,
      metricId: personalFollowUpConsentOptInMetric,
      projectId,
      status: "not_enabled",
      configuration: null,
    };
  }
  const configuration = parseConfiguration(root.configuration, projectId);
  if (root.status === "enabled" && configuration.enabled) {
    return {
      stateContractId: personalFollowUpConsentOptInStateContract,
      metricId: personalFollowUpConsentOptInMetric,
      projectId,
      status: "enabled",
      configuration,
    };
  }
  if (root.status === "not_enabled" && !configuration.enabled) {
    return {
      stateContractId: personalFollowUpConsentOptInStateContract,
      metricId: personalFollowUpConsentOptInMetric,
      projectId,
      status: "not_enabled",
      configuration,
    };
  }
  throw invalidResult();
}

function parseConfiguration(
  value: unknown,
  expectedProjectId: string,
): PersonalFollowUpConsentOptInConfiguration {
  const root = object(value);
  requireExactKeys(root, configurationKeys);
  const projectId = uuid(root.project_id);
  const versionNumber = positiveInteger(root.version_number);
  const expectedVersion = postgresNonnegativeInteger(root.expected_version);
  const actorAppUserId = uuid(root.actor_app_user_id);
  const requestId = uuid(root.request_id);
  const recordedAtUtc = utcTimestamp(root.recorded_at_utc);
  if (
    root.configuration_contract_id !==
      personalFollowUpConsentOptInConfigurationContract ||
    root.metric_id !== personalFollowUpConsentOptInMetric ||
    projectId !== expectedProjectId.toLowerCase() ||
    versionNumber !== (expectedVersion ?? -1) + 1 ||
    typeof root.enabled !== "boolean"
  ) {
    throw invalidResult();
  }
  return {
    configurationContractId:
      personalFollowUpConsentOptInConfigurationContract,
    metricId: personalFollowUpConsentOptInMetric,
    projectId,
    versionNumber,
    expectedVersion: expectedVersion as number,
    enabled: root.enabled,
    actorAppUserId,
    requestId,
    recordedAtUtc,
  };
}

function serializeState(
  state: PersonalFollowUpConsentOptInState,
): Readonly<Record<string, unknown>> {
  return {
    state_contract_id: state.stateContractId,
    metric_id: state.metricId,
    project_id: state.projectId,
    status: state.status,
    configuration: state.configuration === null
      ? null
      : serializeConfiguration(state.configuration),
  };
}

function serializeConfiguration(
  value: PersonalFollowUpConsentOptInConfiguration,
): Readonly<Record<string, unknown>> {
  return {
    configuration_contract_id: value.configurationContractId,
    metric_id: value.metricId,
    project_id: value.projectId,
    version_number: value.versionNumber,
    expected_version: value.expectedVersion,
    enabled: value.enabled,
    request_id: value.requestId,
    recorded_at_utc: value.recordedAtUtc,
  };
}

function stateMatchesActor(
  state: PersonalFollowUpConsentOptInState,
  expectedActorAppUserId: string,
): boolean {
  return state.configuration === null ||
    configurationMatchesActor(state.configuration, expectedActorAppUserId);
}

function configurationMatchesActor(
  configuration: PersonalFollowUpConsentOptInConfiguration,
  expectedActorAppUserId: string,
): boolean {
  return configuration.actorAppUserId === expectedActorAppUserId.toLowerCase();
}

function storeFailure(
  error: unknown,
): PersonalFollowUpConsentOptInHttpResult {
  if (error instanceof PersonalFollowUpConsentOptInStoreError) {
    if (error.code === "forbidden") {
      return failure(403, "personal_follow_up_consent_opt_in_forbidden");
    }
    if (error.code === "conflict") {
      return failure(409, "personal_follow_up_consent_opt_in_conflict");
    }
  }
  if (
    errorCode(error) === "42501" &&
    contextForbiddenMessages.has(errorMessage(error))
  ) {
    return failure(403, "personal_follow_up_consent_opt_in_forbidden");
  }
  return failure(503, "personal_follow_up_consent_opt_in_unavailable");
}

function mapPostgresError(error: unknown, operation: "read" | "configure"): Error {
  if (error instanceof PersonalFollowUpConsentOptInStoreError) return error;
  const code = errorCode(error);
  const message = errorMessage(error);
  if (
    code === "42501" &&
    (message === "project follow-up consent opt-in scope is forbidden" ||
      message ===
        "project follow-up consent opt-in insert scope is forbidden")
  ) {
    return new PersonalFollowUpConsentOptInStoreError("forbidden");
  }
  if (
    operation === "configure" &&
    (
      (code === "22023" && message ===
        "project follow-up consent opt-in idempotency conflict") ||
      (code === "40001" && message ===
        "project follow-up consent opt-in version conflict")
    )
  ) {
    return new PersonalFollowUpConsentOptInStoreError("conflict");
  }
  return error instanceof Error ? error : new Error(String(error));
}

function rowField(row: unknown, field: string): unknown {
  const root = object(row);
  if (!(field in root)) throw invalidResult();
  return root[field];
}

function object(value: unknown): Record<string, unknown> {
  if (!isObject(value)) throw invalidResult();
  return value;
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function record(value: unknown): Record<string, unknown> {
  return isObject(value) ? value : {};
}

function errorCode(value: unknown): unknown {
  return record(value).code;
}

function errorMessage(value: unknown): unknown {
  return value instanceof Error ? value.message : record(value).message;
}

function hasExactKeys(
  value: Readonly<Record<string, unknown>>,
  expected: readonly string[],
): boolean {
  const actual = Object.keys(value).sort();
  const sortedExpected = [...expected].sort();
  return actual.length === sortedExpected.length &&
    actual.every((key, index) => key === sortedExpected[index]);
}

function requireExactKeys(
  value: Readonly<Record<string, unknown>>,
  expected: readonly string[],
): void {
  if (!hasExactKeys(value, expected)) throw invalidResult();
}

function uuid(value: unknown): string {
  const parsed = nullableUuid(value);
  if (parsed === null) throw invalidResult();
  return parsed;
}

function nullableUuid(value: unknown): string | null {
  return typeof value === "string" && uuidPattern.test(value)
    ? value.toLowerCase()
    : null;
}

function positiveInteger(value: unknown): number {
  const parsed = postgresNonnegativeInteger(value);
  if (parsed === null || parsed === 0) throw invalidResult();
  return parsed;
}

function postgresNonnegativeInteger(value: unknown): number | null {
  return Number.isInteger(value) && Number(value) >= 0 &&
      Number(value) <= 2147483647
    ? Number(value)
    : null;
}

function utcTimestamp(value: unknown): string {
  if (typeof value !== "string") {
    throw invalidResult();
  }
  const match = value.match(databaseUtcPattern);
  if (match === null || value.startsWith("0000-")) throw invalidResult();
  const dateAndTime = match[1] as string;
  const microseconds = match[2] as string;
  const timestamp = new Date(
    `${dateAndTime}.${microseconds.slice(0, 3)}Z`,
  );
  if (!Number.isFinite(timestamp.valueOf())) throw invalidResult();
  const normalized = timestamp.toISOString();
  if (
    normalized.slice(0, 19) !== dateAndTime ||
    normalized.slice(20, 23) !== microseconds.slice(0, 3)
  ) {
    throw invalidResult();
  }
  return value;
}

function invalidResult(): PersonalFollowUpConsentOptInStoreError {
  return new PersonalFollowUpConsentOptInStoreError("invalid");
}

function failure(
  status: number,
  code: string,
): PersonalFollowUpConsentOptInHttpResult {
  return {status, body: {error: {code}}};
}

const stateKeys = [
  "state_contract_id",
  "metric_id",
  "project_id",
  "status",
  "configuration",
];
const configurationKeys = [
  "configuration_contract_id",
  "metric_id",
  "project_id",
  "version_number",
  "expected_version",
  "enabled",
  "actor_app_user_id",
  "request_id",
  "recorded_at_utc",
];
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const databaseUtcPattern =
  /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\.(\d{6})Z$/;
const contextForbiddenMessages = new Set<unknown>([
  "mapped app user is not active",
  "trusted identity is not mapped to an active app user",
]);
