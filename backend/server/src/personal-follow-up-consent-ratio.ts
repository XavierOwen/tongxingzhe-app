import {bearerToken} from "./authorization.js";
import {
  IdentityVerificationError,
  type IdentityVerifier,
  type VerifiedIdentity,
} from "./identity.js";
import type {SessionContextStore} from "./session-context.js";

export const personalFollowUpConsentRatioContract =
  "personal_follow_up_consent_ratio_result_v1";
export const personalFollowUpConsentRatioMetric =
  "follow_up_consent_ratio@1";

export interface PersonalFollowUpConsentRatioPeriod {
  readonly fromUtc: string;
  readonly untilUtc: string;
}

export interface PersonalFollowUpConsentRatioValue {
  readonly yesCount: number;
  readonly noCount: number;
  readonly numerator: number;
  readonly unknownCount: number;
  readonly refusedCount: number;
  readonly notApplicableCount: number;
  readonly unansweredCount: number;
  readonly excludedCount: number;
  readonly denominator: number;
  readonly percentageBasisPoints: number | null;
}

interface PersonalFollowUpConsentRatioResultBase {
  readonly contractId: typeof personalFollowUpConsentRatioContract;
  readonly metricId: typeof personalFollowUpConsentRatioMetric;
  readonly projectId: string;
}

export type PersonalFollowUpConsentRatioResult =
  | PersonalFollowUpConsentRatioResultBase & {
      readonly status: "not_enabled";
    }
  | PersonalFollowUpConsentRatioResultBase & {
      readonly status: "ready";
      readonly period: PersonalFollowUpConsentRatioPeriod;
      readonly value: PersonalFollowUpConsentRatioValue;
    };

export interface PersonalFollowUpConsentRatioStore {
  read(
    identity: VerifiedIdentity,
    projectId: string,
    period: PersonalFollowUpConsentRatioPeriod,
  ): Promise<PersonalFollowUpConsentRatioResult>;
}

export interface PersonalFollowUpConsentRatioDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly contextStore: SessionContextStore;
  readonly ratioStore?: PersonalFollowUpConsentRatioStore;
}

export interface PersonalFollowUpConsentRatioRequest {
  readonly authorization: string | undefined;
  readonly query: URLSearchParams;
  readonly hasBody: boolean;
}

export interface PersonalFollowUpConsentRatioHttpResult {
  readonly status: number;
  readonly body: Readonly<Record<string, unknown>>;
}

export async function readPersonalFollowUpConsentRatio(
  request: PersonalFollowUpConsentRatioRequest,
  dependencies: PersonalFollowUpConsentRatioDependencies,
): Promise<PersonalFollowUpConsentRatioHttpResult> {
  const accessToken = bearerToken(request.authorization);
  if (accessToken === null) return failure(401, "unauthenticated");

  let identity: VerifiedIdentity;
  try {
    identity = await dependencies.identityVerifier.verify(accessToken);
  } catch (error) {
    return error instanceof IdentityVerificationError
      ? failure(401, "unauthenticated")
      : failure(503, "personal_follow_up_consent_ratio_unavailable");
  }

  const period = parsePeriod(request.query, request.hasBody);
  if (period === null) {
    return failure(400, "invalid_personal_follow_up_consent_ratio_request");
  }
  if (dependencies.ratioStore === undefined) {
    return failure(503, "personal_follow_up_consent_ratio_unavailable");
  }

  try {
    const context = await dependencies.contextStore.loadOrCreate(identity);
    const result = await dependencies.ratioStore.read(
      identity,
      context.current.project.id,
      period,
    );
    return {status: 200, body: {result: serializeResult(result)}};
  } catch (error) {
    if (
      error instanceof PersonalFollowUpConsentRatioStoreError &&
      error.code === "forbidden"
    ) {
      return failure(403, "personal_follow_up_consent_ratio_forbidden");
    }
    return failure(503, "personal_follow_up_consent_ratio_unavailable");
  }
}

export type PersonalFollowUpConsentRatioQuery = (
  text: string,
  values: readonly unknown[],
) => Promise<{readonly rows: readonly unknown[]}>;

export class PostgresPersonalFollowUpConsentRatioStore
implements PersonalFollowUpConsentRatioStore {
  constructor(private readonly query: PersonalFollowUpConsentRatioQuery) {}

  async read(
    identity: VerifiedIdentity,
    projectId: string,
    period: PersonalFollowUpConsentRatioPeriod,
  ): Promise<PersonalFollowUpConsentRatioResult> {
    try {
      const queryResult = await this.query(
        `SELECT app_data.read_personal_follow_up_consent_ratio_v1(
           $1::text, $2::text, $3::uuid, $4::text, $5::timestamptz, $6::timestamptz
         ) AS ratio_result`,
        [
          identity.issuer,
          identity.subject,
          projectId,
          personalFollowUpConsentRatioMetric,
          period.fromUtc,
          period.untilUtc,
        ],
      );
      if (queryResult.rows.length !== 1) throw invalidResult();
      return parseResult(
        rowField(queryResult.rows[0], "ratio_result"),
        projectId,
        period,
      );
    } catch (error) {
      throw mapPostgresError(error);
    }
  }
}

export class PersonalFollowUpConsentRatioStoreError extends Error {
  constructor(readonly code: "forbidden" | "invalid") {
    super(code);
    this.name = "PersonalFollowUpConsentRatioStoreError";
  }
}

function parsePeriod(
  query: URLSearchParams,
  hasBody: boolean,
): PersonalFollowUpConsentRatioPeriod | null {
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

function parseResult(
  value: unknown,
  expectedProjectId: string,
  expectedPeriod: PersonalFollowUpConsentRatioPeriod,
): PersonalFollowUpConsentRatioResult {
  const root = object(value);
  const common = ["contract_id", "metric_id", "project_id", "status"];
  if (
    root.contract_id !== personalFollowUpConsentRatioContract ||
    root.metric_id !== personalFollowUpConsentRatioMetric ||
    uuid(root.project_id) !== expectedProjectId.toLowerCase()
  ) {
    throw invalidResult();
  }

  if (root.status === "not_enabled") {
    requireExactKeys(root, common);
    return {
      contractId: personalFollowUpConsentRatioContract,
      metricId: personalFollowUpConsentRatioMetric,
      projectId: expectedProjectId.toLowerCase(),
      status: "not_enabled",
    };
  }
  if (root.status !== "ready") throw invalidResult();
  requireExactKeys(root, [...common, "period", "value"]);

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

  const valueRoot = object(root.value);
  requireExactKeys(valueRoot, valueKeys);
  const yesCount = safeCount(valueRoot.yes_count);
  const noCount = safeCount(valueRoot.no_count);
  const numerator = safeCount(valueRoot.numerator);
  const denominator = safeCount(valueRoot.denominator);
  const unknownCount = safeCount(valueRoot.unknown_count);
  const excludedCount = safeCount(valueRoot.excluded_count);
  const percentageBasisPoints = nullableBasisPoints(
    valueRoot.percentage_basis_points,
  );
  if (
    numerator !== yesCount ||
    !Number.isSafeInteger(yesCount + noCount) ||
    denominator !== yesCount + noCount ||
    unknownCount !== 0 ||
    excludedCount !== 0 ||
    percentageBasisPoints !== expectedBasisPoints(yesCount, denominator)
  ) {
    throw invalidResult();
  }

  return {
    contractId: personalFollowUpConsentRatioContract,
    metricId: personalFollowUpConsentRatioMetric,
    projectId: expectedProjectId.toLowerCase(),
    status: "ready",
    period,
    value: {
      yesCount,
      noCount,
      numerator,
      unknownCount,
      refusedCount: safeCount(valueRoot.refused_count),
      notApplicableCount: safeCount(valueRoot.not_applicable_count),
      unansweredCount: safeCount(valueRoot.unanswered_count),
      excludedCount,
      denominator,
      percentageBasisPoints,
    },
  };
}

function serializeResult(
  result: PersonalFollowUpConsentRatioResult,
): Readonly<Record<string, unknown>> {
  const common = {
    contract_id: result.contractId,
    metric_id: result.metricId,
    project_id: result.projectId,
    status: result.status,
  };
  if (result.status === "not_enabled") return common;
  return {
    ...common,
    period: {
      from_utc: result.period.fromUtc,
      until_utc: result.period.untilUtc,
    },
    value: {
      yes_count: result.value.yesCount,
      no_count: result.value.noCount,
      numerator: result.value.numerator,
      unknown_count: result.value.unknownCount,
      refused_count: result.value.refusedCount,
      not_applicable_count: result.value.notApplicableCount,
      unanswered_count: result.value.unansweredCount,
      excluded_count: result.value.excludedCount,
      denominator: result.value.denominator,
      percentage_basis_points: result.value.percentageBasisPoints,
    },
  };
}

function expectedBasisPoints(
  numerator: number,
  denominator: number,
): number | null {
  if (denominator === 0) return null;
  return Number(
    (BigInt(numerator) * 10000n + BigInt(denominator) / 2n) /
      BigInt(denominator),
  );
}

function canonicalUtcTimestamp(value: string | undefined): string | null {
  if (value === undefined) return null;
  const match = value.match(utcInputPattern);
  if (match === null || value.startsWith("0000-")) {
    return null;
  }
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
  if (typeof value !== "string" || !rfc3339Pattern.test(value)) {
    throw invalidResult();
  }
  const timestamp = new Date(value);
  if (!Number.isFinite(timestamp.valueOf())) throw invalidResult();
  return timestamp.toISOString();
}

function nullableBasisPoints(value: unknown): number | null {
  if (value === null) return null;
  if (!Number.isInteger(value) || Number(value) < 0 || Number(value) > 10000) {
    throw invalidResult();
  }
  return Number(value);
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
  if (error instanceof PersonalFollowUpConsentRatioStoreError) return error;
  const code = record(error).code;
  if (code === "42501") {
    return new PersonalFollowUpConsentRatioStoreError("forbidden");
  }
  if (code === "22023" || code === "23514") return invalidResult();
  return error instanceof Error ? error : new Error(String(error));
}

function record(value: unknown): Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function invalidResult(): PersonalFollowUpConsentRatioStoreError {
  return new PersonalFollowUpConsentRatioStoreError("invalid");
}

function failure(
  status: number,
  code: string,
): PersonalFollowUpConsentRatioHttpResult {
  return {status, body: {error: {code}}};
}

const valueKeys = [
  "yes_count",
  "no_count",
  "numerator",
  "unknown_count",
  "refused_count",
  "not_applicable_count",
  "unanswered_count",
  "excluded_count",
  "denominator",
  "percentage_basis_points",
];
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const utcInputPattern =
  /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d{1,9}))?Z$/;
const rfc3339Pattern =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/;
