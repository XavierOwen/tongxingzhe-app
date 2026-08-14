import {bearerToken} from "./authorization.js";
import {
  IdentityVerificationError,
  type IdentityVerifier,
  type VerifiedIdentity,
} from "./identity.js";

export const personalRelationshipStageChangeSummaryContract =
  "personal_relationship_stage_change_summary_result_v1";
export const relationshipStageChangeTimeBasis =
  "relationshipChangedAtUtc";

export interface PersonalRelationshipStageChangePeriod {
  readonly fromUtc: string;
  readonly untilUtc: string;
}

export interface PersonalRelationshipStageChangeValue {
  readonly eventCount: number;
  readonly distinctRelationshipCount: number;
  readonly upwardCount: number;
  readonly downwardCount: number;
}

export interface PersonalRelationshipStageChangeSummary {
  readonly contractId: typeof personalRelationshipStageChangeSummaryContract;
  readonly projectId: string;
  readonly timeBasis: typeof relationshipStageChangeTimeBasis;
  readonly period: PersonalRelationshipStageChangePeriod;
  readonly dataCutoffUtc: string;
  readonly authorizedAtUtc: string;
  readonly value: PersonalRelationshipStageChangeValue;
}

export interface PersonalRelationshipStageChangeSummaryStore {
  read(
    identity: VerifiedIdentity,
    period: PersonalRelationshipStageChangePeriod,
  ): Promise<PersonalRelationshipStageChangeSummary>;
}

export interface PersonalRelationshipStageChangeSummaryDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly summaryStore?: PersonalRelationshipStageChangeSummaryStore;
}

export interface PersonalRelationshipStageChangeSummaryRequest {
  readonly authorization: string | undefined;
  readonly query: URLSearchParams;
  readonly hasBody: boolean;
}

export interface PersonalRelationshipStageChangeSummaryHttpResult {
  readonly status: number;
  readonly body: Readonly<Record<string, unknown>>;
}

export async function readPersonalRelationshipStageChangeSummary(
  request: PersonalRelationshipStageChangeSummaryRequest,
  dependencies: PersonalRelationshipStageChangeSummaryDependencies,
): Promise<PersonalRelationshipStageChangeSummaryHttpResult> {
  const accessToken = bearerToken(request.authorization);
  if (accessToken === null) return failure(401, "unauthenticated");

  let identity: VerifiedIdentity;
  try {
    identity = await dependencies.identityVerifier.verify(accessToken);
  } catch (error) {
    return error instanceof IdentityVerificationError
      ? failure(401, "unauthenticated")
      : failure(503, "personal_relationship_stage_change_summary_unavailable");
  }

  const period = parsePeriod(request.query, request.hasBody);
  if (period === null) {
    return failure(
      400,
      "invalid_personal_relationship_stage_change_summary_request",
    );
  }
  if (dependencies.summaryStore === undefined) {
    return failure(503, "personal_relationship_stage_change_summary_unavailable");
  }

  try {
    const result = await dependencies.summaryStore.read(identity, period);
    return {status: 200, body: {result: serializeSummary(result)}};
  } catch (error) {
    if (
      error instanceof PersonalRelationshipStageChangeSummaryStoreError &&
      error.code === "forbidden"
    ) {
      return failure(403, "personal_relationship_stage_change_summary_forbidden");
    }
    return failure(503, "personal_relationship_stage_change_summary_unavailable");
  }
}

export type PersonalRelationshipStageChangeSummaryQuery = (
  text: string,
  values: readonly unknown[],
) => Promise<{readonly rows: readonly unknown[]}>;

export class PostgresPersonalRelationshipStageChangeSummaryStore
implements PersonalRelationshipStageChangeSummaryStore {
  constructor(
    private readonly query: PersonalRelationshipStageChangeSummaryQuery,
  ) {}

  async read(
    identity: VerifiedIdentity,
    period: PersonalRelationshipStageChangePeriod,
  ): Promise<PersonalRelationshipStageChangeSummary> {
    try {
      const queryResult = await this.query(
        `SELECT app_data.read_personal_relationship_stage_change_summary_v1(
           $1::text, $2::text, $3::timestamptz, $4::timestamptz
         ) AS summary`,
        [identity.issuer, identity.subject, period.fromUtc, period.untilUtc],
      );
      if (queryResult.rows.length !== 1) throw invalidResult();
      return parseSummary(
        rowField(queryResult.rows[0], "summary"),
        period,
        Date.now(),
      );
    } catch (error) {
      throw mapPostgresError(error);
    }
  }
}

export class PersonalRelationshipStageChangeSummaryStoreError extends Error {
  constructor(readonly code: "forbidden" | "invalid") {
    super(code);
    this.name = "PersonalRelationshipStageChangeSummaryStoreError";
  }
}

function parsePeriod(
  query: URLSearchParams,
  hasBody: boolean,
): PersonalRelationshipStageChangePeriod | null {
  if (hasBody || [...query.keys()].length !== 2) return null;
  const fromValues = query.getAll("from_utc");
  const untilValues = query.getAll("until_utc");
  if (fromValues.length !== 1 || untilValues.length !== 1) return null;
  const fromUtc = canonicalUtcTimestamp(fromValues[0]);
  const untilUtc = canonicalUtcTimestamp(untilValues[0]);
  if (
    fromUtc === null ||
    untilUtc === null ||
    Date.parse(fromUtc) >= Date.parse(untilUtc)
  ) {
    return null;
  }
  return {fromUtc, untilUtc};
}

function parseSummary(
  value: unknown,
  expectedPeriod: PersonalRelationshipStageChangePeriod,
  receivedAtMilliseconds: number,
): PersonalRelationshipStageChangeSummary {
  const root = object(value);
  requireExactKeys(root, [
    "contract_id",
    "project_id",
    "time_basis",
    "period",
    "data_cutoff_utc",
    "authorized_at_utc",
    "value",
  ]);
  if (
    root.contract_id !== personalRelationshipStageChangeSummaryContract ||
    root.time_basis !== relationshipStageChangeTimeBasis
  ) {
    throw invalidResult();
  }
  const projectId = uuid(root.project_id);

  const periodRoot = object(root.period);
  requireExactKeys(periodRoot, ["from_utc", "until_utc"]);
  const period = {
    fromUtc: utcTimestamp(periodRoot.from_utc),
    untilUtc: utcTimestamp(periodRoot.until_utc),
  };
  if (
    period.fromUtc !== expectedPeriod.fromUtc ||
    period.untilUtc !== expectedPeriod.untilUtc
  ) {
    throw invalidResult();
  }

  const dataCutoffUtc = utcTimestamp(root.data_cutoff_utc);
  const authorizedAtUtc = utcTimestamp(root.authorized_at_utc);
  if (
    authorizedAtUtc !== dataCutoffUtc ||
    Date.parse(dataCutoffUtc) > receivedAtMilliseconds
  ) {
    throw invalidResult();
  }

  const valueRoot = object(root.value);
  requireExactKeys(valueRoot, [
    "event_count",
    "distinct_relationship_count",
    "upward_count",
    "downward_count",
  ]);
  const eventCount = safeCount(valueRoot.event_count);
  const distinctRelationshipCount = safeCount(
    valueRoot.distinct_relationship_count,
  );
  const upwardCount = safeCount(valueRoot.upward_count);
  const downwardCount = safeCount(valueRoot.downward_count);
  if (
    !Number.isSafeInteger(upwardCount + downwardCount) ||
    eventCount !== upwardCount + downwardCount ||
    distinctRelationshipCount > eventCount
  ) {
    throw invalidResult();
  }

  return {
    contractId: personalRelationshipStageChangeSummaryContract,
    projectId,
    timeBasis: relationshipStageChangeTimeBasis,
    period,
    dataCutoffUtc,
    authorizedAtUtc,
    value: {
      eventCount,
      distinctRelationshipCount,
      upwardCount,
      downwardCount,
    },
  };
}

function serializeSummary(
  summary: PersonalRelationshipStageChangeSummary,
): Readonly<Record<string, unknown>> {
  return {
    contract_id: summary.contractId,
    project_id: summary.projectId,
    time_basis: summary.timeBasis,
    period: {
      from_utc: summary.period.fromUtc,
      until_utc: summary.period.untilUtc,
    },
    data_cutoff_utc: summary.dataCutoffUtc,
    authorized_at_utc: summary.authorizedAtUtc,
    value: {
      event_count: summary.value.eventCount,
      distinct_relationship_count: summary.value.distinctRelationshipCount,
      upward_count: summary.value.upwardCount,
      downward_count: summary.value.downwardCount,
    },
  };
}

function canonicalUtcTimestamp(value: string | undefined): string | null {
  if (value === undefined) return null;
  const match = value.match(utcInputPattern);
  if (match === null || value.startsWith("0000-")) return null;
  const timestamp = new Date(value);
  if (!Number.isFinite(timestamp.valueOf())) return null;
  const normalized = timestamp.toISOString();
  const dateAndTime = match[1];
  const fraction = match[2] ?? "";
  const expectedMilliseconds = fraction.padEnd(3, "0").slice(0, 3);
  return normalized.slice(0, 19) === dateAndTime &&
      normalized.slice(20, 23) === expectedMilliseconds
    ? normalized
    : null;
}

function utcTimestamp(value: unknown): string {
  if (typeof value !== "string") throw invalidResult();
  const normalized = canonicalUtcTimestamp(value);
  if (normalized === null) throw invalidResult();
  return normalized;
}

function safeCount(value: unknown): number {
  if (!Number.isSafeInteger(value) || Number(value) < 0) throw invalidResult();
  return Number(value);
}

function uuid(value: unknown): string {
  if (typeof value !== "string" || !uuidPattern.test(value)) {
    throw invalidResult();
  }
  return value.toLowerCase();
}

function rowField(row: unknown, field: string): unknown {
  const root = object(row);
  if (!(field in root)) throw invalidResult();
  return root[field];
}

function object(value: unknown): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw invalidResult();
  }
  return value as Record<string, unknown>;
}

function requireExactKeys(
  value: Readonly<Record<string, unknown>>,
  expected: readonly string[],
): void {
  const actual = Object.keys(value).sort();
  const sortedExpected = [...expected].sort();
  if (
    actual.length !== sortedExpected.length ||
    actual.some((key, index) => key !== sortedExpected[index])
  ) {
    throw invalidResult();
  }
}

function mapPostgresError(error: unknown): Error {
  const code = record(error).code;
  if (code === "42501") {
    return new PersonalRelationshipStageChangeSummaryStoreError("forbidden");
  }
  if (code === "22023" || code === "23514") {
    return new PersonalRelationshipStageChangeSummaryStoreError("invalid");
  }
  return error instanceof Error ? error : new Error(String(error));
}

function record(value: unknown): Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function invalidResult(): PersonalRelationshipStageChangeSummaryStoreError {
  return new PersonalRelationshipStageChangeSummaryStoreError("invalid");
}

function failure(
  status: number,
  code: string,
): PersonalRelationshipStageChangeSummaryHttpResult {
  return {status, body: {error: {code}}};
}

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const utcInputPattern =
  /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d{1,6}))?Z$/;
