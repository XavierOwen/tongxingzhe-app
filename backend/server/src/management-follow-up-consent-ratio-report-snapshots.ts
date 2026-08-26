import {bearerToken} from "./authorization.js";
import {
  IdentityVerificationError,
  type IdentityVerifier,
  type VerifiedIdentity,
} from "./identity.js";

export type ManagementFollowUpConsentRatioReportSnapshotRead = {
  readonly status: "completed";
  readonly accessEventId: string;
  readonly requestedSnapshotId: string;
  readonly resolvedSnapshotId: string;
  readonly protectedReport: Readonly<Record<string, unknown>>;
} | {
  readonly status: "not_found";
  readonly accessEventId: string;
  readonly requestedSnapshotId: string;
  readonly resolvedSnapshotId: null;
} | {
  readonly status: "untrusted_provenance";
  readonly accessEventId: string;
  readonly requestedSnapshotId: string;
  readonly resolvedSnapshotId: string;
};

export interface ManagementFollowUpConsentRatioReportSnapshotStore {
  read(
    identity: VerifiedIdentity,
    projectId: string,
    snapshotId: string,
  ): Promise<ManagementFollowUpConsentRatioReportSnapshotRead>;
}

export interface ManagementFollowUpConsentRatioReportSnapshotHttpRequest {
  readonly authorization: string | undefined;
  readonly projectId: string;
  readonly snapshotId: string;
  readonly hasQuery: boolean;
  readonly hasBody: boolean;
}

export interface ManagementFollowUpConsentRatioReportSnapshotHttpDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly snapshotStore?: ManagementFollowUpConsentRatioReportSnapshotStore;
}

export interface ManagementFollowUpConsentRatioReportSnapshotHttpResult {
  readonly status: number;
  readonly body: Readonly<Record<string, unknown>>;
}

export type ManagementFollowUpConsentRatioReportSnapshotQuery = (
  text: string,
  values: readonly unknown[],
) => Promise<{readonly rows: readonly unknown[]}>;

/**
 * Calls the fixed 0077 runtime bridge once and accepts only the 0076
 * follow-up consent-ratio snapshot contract. Identity resolution,
 * authorization, provenance checks, validation and auditing remain in
 * PostgreSQL; this adapter does not recalculate a report or access
 * app_private directly.
 */
export class PostgresManagementFollowUpConsentRatioReportSnapshotStore
implements ManagementFollowUpConsentRatioReportSnapshotStore {
  constructor(
    private readonly query: ManagementFollowUpConsentRatioReportSnapshotQuery,
  ) {}

  async read(
    identity: VerifiedIdentity,
    projectId: string,
    snapshotId: string,
  ): Promise<ManagementFollowUpConsentRatioReportSnapshotRead> {
    try {
      const result = await this.query(
        `SELECT app_data.read_authorized_management_follow_up_consent_report_snapshot_v1(
           $1::text, $2::text, $3::uuid, $4::uuid
         ) AS access_result`,
        [identity.issuer, identity.subject, projectId, snapshotId],
      );
      if (result.rows.length !== 1) throw invalidAccessResult();
      return parseAccessResult(
        rowField(result.rows[0], "access_result"),
        snapshotId,
        projectId,
      );
    } catch (error) {
      throw mapPostgresError(error);
    }
  }
}

export class ManagementFollowUpConsentRatioReportSnapshotStoreError
extends Error {
  constructor(readonly code: "forbidden") {
    super(code);
    this.name =
      "ManagementFollowUpConsentRatioReportSnapshotStoreError";
  }
}

/**
 * Authenticates and reads one fixed follow-up consent-ratio snapshot through
 * the 6BS store. Route validation follows authentication so malformed
 * resource identifiers cannot reveal protected project or snapshot state.
 */
export async function readManagementFollowUpConsentRatioReportSnapshot(
  request: ManagementFollowUpConsentRatioReportSnapshotHttpRequest,
  dependencies: ManagementFollowUpConsentRatioReportSnapshotHttpDependencies,
): Promise<ManagementFollowUpConsentRatioReportSnapshotHttpResult> {
  const accessToken = bearerToken(request.authorization);
  if (accessToken === null) return failure(401, "unauthenticated");

  let identity: VerifiedIdentity;
  try {
    identity = await dependencies.identityVerifier.verify(accessToken);
  } catch (error) {
    return error instanceof IdentityVerificationError
      ? failure(401, "unauthenticated")
      : failure(
        503,
        "management_follow_up_consent_ratio_report_snapshot_unavailable",
      );
  }

  if (
    !uuidPattern.test(request.projectId) ||
    !uuidPattern.test(request.snapshotId) ||
    request.hasQuery ||
    request.hasBody
  ) {
    return failure(
      400,
      "invalid_management_follow_up_consent_ratio_report_snapshot_request",
    );
  }
  if (dependencies.snapshotStore === undefined) {
    return failure(
      503,
      "management_follow_up_consent_ratio_report_snapshot_unavailable",
    );
  }

  try {
    const result = await dependencies.snapshotStore.read(
      identity,
      request.projectId,
      request.snapshotId,
    );
    if (result.status === "completed") {
      return {
        status: 200,
        body: {
          access_event_id: result.accessEventId,
          snapshot_id: result.resolvedSnapshotId,
          report: result.protectedReport,
        },
      };
    }
    if (result.status === "not_found") {
      return auditedFailure(
        404,
        "management_follow_up_consent_ratio_report_snapshot_not_found",
        result.accessEventId,
      );
    }
    return auditedFailure(
      409,
      "management_follow_up_consent_ratio_report_snapshot_untrusted",
      result.accessEventId,
    );
  } catch (error) {
    if (
      error instanceof ManagementFollowUpConsentRatioReportSnapshotStoreError &&
      error.code === "forbidden"
    ) {
      return failure(
        403,
        "management_follow_up_consent_ratio_report_snapshot_forbidden",
      );
    }
    return failure(
      503,
      "management_follow_up_consent_ratio_report_snapshot_unavailable",
    );
  }
}

function failure(
  status: number,
  code: string,
): ManagementFollowUpConsentRatioReportSnapshotHttpResult {
  return {status, body: {error: {code}}};
}

function auditedFailure(
  status: number,
  code: string,
  accessEventId: string,
): ManagementFollowUpConsentRatioReportSnapshotHttpResult {
  return {
    status,
    body: {error: {code, access_event_id: accessEventId}},
  };
}

function parseAccessResult(
  value: unknown,
  expectedSnapshotId: string,
  expectedProjectId: string,
): ManagementFollowUpConsentRatioReportSnapshotRead {
  const root = object(value);
  const status = root.result_status;
  const accessEventId = uuid(root.access_event_id);
  const requestedSnapshotId = uuid(root.requested_snapshot_id);
  if (
    root.access_contract_id !==
      "authorized_follow_up_consent_ratio_management_report_snapshot_read_v1" ||
    requestedSnapshotId !== expectedSnapshotId.toLowerCase()
  ) {
    throw invalidAccessResult();
  }

  const commonKeys = [
    "access_contract_id",
    "access_event_id",
    "reason_code",
    "requested_snapshot_id",
    "resolved_snapshot_id",
    "result_status",
  ];
  if (status === "completed") {
    requireExactKeys(root, [...commonKeys, "protected_report"]);
    const resolvedSnapshotId = uuid(root.resolved_snapshot_id);
    if (
      resolvedSnapshotId !== expectedSnapshotId.toLowerCase() ||
      root.reason_code !== null
    ) {
      throw invalidAccessResult();
    }
    const protectedReport = object(root.protected_report);
    assertProtectedReport(
      protectedReport,
      expectedProjectId.toLowerCase(),
    );
    return {
      status,
      accessEventId,
      requestedSnapshotId,
      resolvedSnapshotId,
      protectedReport,
    };
  }

  requireExactKeys(root, commonKeys);
  if (
    status === "not_found" &&
    root.reason_code === "snapshot_not_available" &&
    root.resolved_snapshot_id === null
  ) {
    return {
      status,
      accessEventId,
      requestedSnapshotId,
      resolvedSnapshotId: null,
    };
  }
  if (
    status === "untrusted_provenance" &&
    root.reason_code === "snapshot_provenance_untrusted"
  ) {
    const resolvedSnapshotId = uuid(root.resolved_snapshot_id);
    if (resolvedSnapshotId !== expectedSnapshotId.toLowerCase()) {
      throw invalidAccessResult();
    }
    return {
      status,
      accessEventId,
      requestedSnapshotId,
      resolvedSnapshotId,
    };
  }
  throw invalidAccessResult();
}

function assertProtectedReport(
  value: Record<string, unknown>,
  expectedProjectId: string,
): void {
  requireExactKeys(value, [
    "contract_id",
    "report_id",
    "report_version",
    "metric_id",
    "metric_version",
    "statistical_unit",
    "dimension",
    "period_grain",
    "comparison_period_count",
    "period_boundary_id",
    "privacy_policy",
    "query_fingerprint",
    "source_scope",
    "project_id",
    "status",
    "periods",
    "period_results",
  ]);
  if (
    value.contract_id !== "management_follow_up_consent_ratio_candidate_v1" ||
    value.report_id !==
      "contact_target_follow_up_consent_ratio_two_periods" ||
    value.report_version !== 1 ||
    value.metric_id !== "follow_up_consent_ratio" ||
    value.metric_version !== 1 ||
    value.statistical_unit !== "contact_target_link" ||
    value.dimension !== "consent_state" ||
    value.period_grain !== "week" ||
    value.comparison_period_count !== 2 ||
    value.period_boundary_id !== "iso_week_monday_v1" ||
    value.privacy_policy !== "management_follow_up_consent_ratio_privacy_v1" ||
    value.query_fingerprint !==
      "management-report:contact_target_follow_up_consent_ratio_two_periods:v1" ||
    value.source_scope !==
      "backend_accepted_active_contact_target_links_current_revision" ||
    value.status !== "completed" ||
    typeof value.project_id !== "string" ||
    !uuidPattern.test(value.project_id) ||
    value.project_id.toLowerCase() !== expectedProjectId ||
    !isSafeNonnegativeInteger(value.report_version) ||
    !isSafeNonnegativeInteger(value.metric_version) ||
    !isSafeNonnegativeInteger(value.comparison_period_count) ||
    !Array.isArray(value.period_results)
  ) {
    throw invalidAccessResult();
  }
  assertPeriods(value.periods);
  assertPeriodResults(value.period_results);
  assertNoSensitiveFacts(value);
}

function assertPeriods(value: unknown): void {
  const periods = object(value);
  requireExactKeys(periods, [
    "period_boundary_id",
    "reporting_time_zone",
    "data_cutoff_utc",
    "previous_period",
    "current_period",
  ]);
  if (
    periods.period_boundary_id !== "iso_week_monday_v1" ||
    typeof periods.reporting_time_zone !== "string" ||
    !validReportingTimeZone(periods.reporting_time_zone) ||
    !finiteTimestamp(periods.data_cutoff_utc)
  ) {
    throw invalidAccessResult();
  }

  const previous = object(periods.previous_period);
  const current = object(periods.current_period);
  requireExactKeys(previous, ["start_utc", "until_utc"]);
  requireExactKeys(current, ["start_utc", "until_utc"]);
  if (
    !finiteTimestamp(previous.start_utc) ||
    !finiteTimestamp(previous.until_utc) ||
    !finiteTimestamp(current.start_utc) ||
    !finiteTimestamp(current.until_utc) ||
    Date.parse(previous.start_utc) >= Date.parse(previous.until_utc) ||
    previous.until_utc !== current.start_utc ||
    Date.parse(current.start_utc) >= Date.parse(current.until_utc) ||
    Date.parse(current.until_utc) > Date.parse(periods.data_cutoff_utc)
  ) {
    throw invalidAccessResult();
  }

  const previousStartDay = isoWeekBoundaryLocalDay(
    previous.start_utc,
    periods.reporting_time_zone,
  );
  const previousUntilDay = isoWeekBoundaryLocalDay(
    previous.until_utc,
    periods.reporting_time_zone,
  );
  const currentStartDay = isoWeekBoundaryLocalDay(
    current.start_utc,
    periods.reporting_time_zone,
  );
  const currentUntilDay = isoWeekBoundaryLocalDay(
    current.until_utc,
    periods.reporting_time_zone,
  );
  const sevenDays = 7 * 24 * 60 * 60 * 1000;
  if (
    previousStartDay === null ||
    previousUntilDay === null ||
    currentStartDay === null ||
    currentUntilDay === null ||
    previousUntilDay - previousStartDay !== sevenDays ||
    currentUntilDay - currentStartDay !== sevenDays
  ) {
    throw invalidAccessResult();
  }
}

function isoWeekBoundaryLocalDay(
  value: string,
  reportingTimeZone: string,
): number | null {
  if (!canonicalUtcTimestamp(value)) return null;
  const parts = new Intl.DateTimeFormat("en-US-u-ca-iso8601-nu-latn", {
    timeZone: reportingTimeZone,
    weekday: "short",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23",
  }).formatToParts(new Date(value));
  const fields = new Map(parts.map((part) => [part.type, part.value]));
  if (
    fields.get("weekday") !== "Mon" ||
    fields.get("hour") !== "00" ||
    fields.get("minute") !== "00" ||
    fields.get("second") !== "00"
  ) {
    return null;
  }
  const year = Number(fields.get("year"));
  const month = Number(fields.get("month"));
  const day = Number(fields.get("day"));
  if (
    !Number.isInteger(year) ||
    !Number.isInteger(month) ||
    !Number.isInteger(day)
  ) {
    return null;
  }
  return Date.UTC(year, month - 1, day);
}

function assertPeriodResults(value: unknown[]): void {
  if (value.length !== 2) throw invalidAccessResult();
  for (let index = 0; index < value.length; index += 1) {
    const period = object(value[index]);
    requireExactKeys(period, [
      "period_key",
      "period_order",
      "ratio",
      "coverage",
      "unknown_count",
      "excluded_count",
    ]);
    if (
      period.period_key !== (index === 0 ? "previous" : "current") ||
      period.period_order !== index ||
      !isSafeNonnegativeInteger(period.period_order) ||
      period.unknown_count !== 0 ||
      period.excluded_count !== 0
    ) {
      throw invalidAccessResult();
    }
    assertRatio(period.ratio);
    assertCoverage(period.coverage, index);
  }
}

function assertRatio(value: unknown): void {
  const ratio = object(value);
  requireExactKeys(ratio, [
    "privacy_status",
    "yes_count",
    "no_count",
    "numerator",
    "denominator",
    "percentage_basis_points",
  ]);
  if (ratio.privacy_status === "suppressed") {
    if (
      ratio.yes_count !== null ||
      ratio.no_count !== null ||
      ratio.numerator !== null ||
      ratio.denominator !== null ||
      ratio.percentage_basis_points !== null
    ) {
      throw invalidAccessResult();
    }
    return;
  }
  if (ratio.privacy_status !== "displayed") throw invalidAccessResult();
  if (
    !isSafePositiveInteger(ratio.yes_count) ||
    !isSafePositiveInteger(ratio.no_count) ||
    !isSafePositiveInteger(ratio.numerator) ||
    !isSafePositiveInteger(ratio.denominator) ||
    !isSafeNonnegativeInteger(ratio.percentage_basis_points) ||
    Number(ratio.yes_count) < 10 ||
    Number(ratio.no_count) < 10 ||
    Number(ratio.percentage_basis_points) > 10000
  ) {
    throw invalidAccessResult();
  }
  const yesCount = BigInt(ratio.yes_count as number);
  const noCount = BigInt(ratio.no_count as number);
  const numerator = BigInt(ratio.numerator as number);
  const denominator = BigInt(ratio.denominator as number);
  const expectedBasisPoints = Number(
    (yesCount * 10000n + denominator / 2n) / denominator,
  );
  if (
    numerator !== yesCount ||
    denominator !== yesCount + noCount ||
    denominator > BigInt(Number.MAX_SAFE_INTEGER) ||
    BigInt(ratio.percentage_basis_points as number) !==
      BigInt(expectedBasisPoints)
  ) {
    throw invalidAccessResult();
  }
}

function assertCoverage(value: unknown, periodOrder: number): void {
  if (!Array.isArray(value) || value.length !== 3) {
    throw invalidAccessResult();
  }
  const expectedStates = ["unanswered", "refused", "not_applicable"];
  for (let index = 0; index < value.length; index += 1) {
    const cell = object(value[index]);
    requireExactKeys(cell, [
      "consent_state",
      "cell_order",
      "value_count",
      "privacy_status",
    ]);
    if (
      cell.consent_state !== expectedStates[index] ||
      cell.cell_order !== periodOrder * 3 + index ||
      !isSafeNonnegativeInteger(cell.cell_order) ||
      (cell.privacy_status !== "displayed" &&
        cell.privacy_status !== "suppressed")
    ) {
      throw invalidAccessResult();
    }
    if (cell.privacy_status === "suppressed") {
      if (cell.value_count !== null) throw invalidAccessResult();
    } else if (
      !isSafePositiveInteger(cell.value_count) ||
      Number(cell.value_count) < 10
    ) {
      throw invalidAccessResult();
    }
  }
}

function validReportingTimeZone(value: string): boolean {
  if (value === "UTC") return true;
  if (
    !value.includes("/") ||
    value.startsWith("posix/") ||
    value.startsWith("right/")
  ) {
    return false;
  }
  try {
    new Intl.DateTimeFormat("en-US", {timeZone: value}).format();
    return true;
  } catch {
    return false;
  }
}

const sensitiveFactKeys = new Set([
  "app_user",
  "app_user_id",
  "contact",
  "contact_id",
  "contact_key",
  "target",
  "target_id",
  "promotion_target",
  "promotion_target_id",
  "contributor",
  "contributor_id",
  "contributor_key",
  "email",
  "phone",
  "raw_answer",
  "raw_value",
  "answer",
  "place_name",
  "placeName",
  "latitude",
  "longitude",
  "location",
  "location_source",
  "locationSource",
  "source",
  "source_id",
  "source_key",
  "revision",
  "revision_id",
  "canonical_name",
  "city_name",
  "cityName",
  "region_name",
  "regionName",
  "boundary",
  "geometry",
  "coordinates",
  "organization_membership_id",
  "project_membership_id",
  "capability_grant_id",
]);

function assertNoSensitiveFacts(value: unknown): void {
  if (Array.isArray(value)) {
    for (const item of value) assertNoSensitiveFacts(item);
    return;
  }
  if (typeof value !== "object" || value === null) return;
  for (const [key, item] of Object.entries(value)) {
    if (sensitiveFactKeys.has(key)) throw invalidAccessResult();
    assertNoSensitiveFacts(item);
  }
}

function rowField(value: unknown, name: string): unknown {
  const row = object(value);
  if (!(name in row)) throw invalidAccessResult();
  return row[name];
}

function object(value: unknown): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw invalidAccessResult();
  }
  return value as Record<string, unknown>;
}

function uuid(value: unknown): string {
  if (typeof value !== "string" || !uuidPattern.test(value)) {
    throw invalidAccessResult();
  }
  return value.toLowerCase();
}

function requireExactKeys(
  value: Record<string, unknown>,
  expected: readonly string[],
): void {
  const actual = Object.keys(value).sort();
  const sortedExpected = [...expected].sort();
  if (
    actual.length !== sortedExpected.length ||
    actual.some((key, index) => key !== sortedExpected[index])
  ) {
    throw invalidAccessResult();
  }
}

function isSafeNonnegativeInteger(value: unknown): value is number {
  return typeof value === "number" &&
    Number.isSafeInteger(value) &&
    value >= 0;
}

function isSafePositiveInteger(value: unknown): value is number {
  return typeof value === "number" &&
    Number.isSafeInteger(value) &&
    value > 0;
}

function finiteTimestamp(value: unknown): value is string {
  return typeof value === "string" && Number.isFinite(Date.parse(value));
}

function canonicalUtcTimestamp(value: string): boolean {
  return /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(value) &&
    new Date(value).toISOString() === value;
}

function mapPostgresError(error: unknown): Error {
  const code = typeof error === "object" && error !== null && "code" in error
    ? String(error.code)
    : "";
  if (code === "42501") {
    return new ManagementFollowUpConsentRatioReportSnapshotStoreError(
      "forbidden",
    );
  }
  return error instanceof Error ? error : new Error(String(error));
}

function invalidAccessResult(): Error {
  return new Error(
    "invalid follow-up consent-ratio management report snapshot access result",
  );
}

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
