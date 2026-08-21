import {bearerToken} from "./authorization.js";
import {
  IdentityVerificationError,
  type IdentityVerifier,
  type VerifiedIdentity,
} from "./identity.js";

export type ManagementInterestReportSnapshotRead = {
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

export interface ManagementInterestReportSnapshotStore {
  read(
    identity: VerifiedIdentity,
    projectId: string,
    snapshotId: string,
  ): Promise<ManagementInterestReportSnapshotRead>;
}

export interface ManagementInterestReportSnapshotHttpRequest {
  readonly authorization: string | undefined;
  readonly projectId: string;
  readonly snapshotId: string;
  readonly hasQuery: boolean;
  readonly hasBody: boolean;
}

export interface ManagementInterestReportSnapshotHttpDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly snapshotStore?: ManagementInterestReportSnapshotStore;
}

export interface ManagementInterestReportSnapshotHttpResult {
  readonly status: number;
  readonly body: Readonly<Record<string, unknown>>;
}

/**
 * Authenticates and reads one fixed interest snapshot through the 6AY store.
 * Route validation follows authentication so malformed resource identifiers
 * cannot reveal whether a protected project or snapshot exists.
 */
export async function readManagementInterestReportSnapshot(
  request: ManagementInterestReportSnapshotHttpRequest,
  dependencies: ManagementInterestReportSnapshotHttpDependencies,
): Promise<ManagementInterestReportSnapshotHttpResult> {
  const accessToken = bearerToken(request.authorization);
  if (accessToken === null) return failure(401, "unauthenticated");

  let identity: VerifiedIdentity;
  try {
    identity = await dependencies.identityVerifier.verify(accessToken);
  } catch (error) {
    return error instanceof IdentityVerificationError
      ? failure(401, "unauthenticated")
      : failure(503, "management_interest_report_snapshot_unavailable");
  }

  if (
    !uuidPattern.test(request.projectId) ||
    !uuidPattern.test(request.snapshotId) ||
    request.hasQuery ||
    request.hasBody
  ) {
    return failure(
      400,
      "invalid_management_interest_report_snapshot_request",
    );
  }
  if (dependencies.snapshotStore === undefined) {
    return failure(503, "management_interest_report_snapshot_unavailable");
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
        "management_interest_report_snapshot_not_found",
        result.accessEventId,
      );
    }
    return auditedFailure(
      409,
      "management_interest_report_snapshot_untrusted",
      result.accessEventId,
    );
  } catch (error) {
    if (
      error instanceof ManagementInterestReportSnapshotStoreError &&
      error.code === "forbidden"
    ) {
      return failure(403, "management_interest_report_snapshot_forbidden");
    }
    return failure(503, "management_interest_report_snapshot_unavailable");
  }
}

export type ManagementInterestReportSnapshotQuery = (
  text: string,
  values: readonly unknown[],
) => Promise<{readonly rows: readonly unknown[]}>;

/**
 * Calls the fixed runtime bridge and rejects any result outside the 6AX
 * interest-snapshot contract. Authorization and audit remain in the private
 * database reader; this adapter neither starts a transaction nor recalculates
 * report values.
 */
export class PostgresManagementInterestReportSnapshotStore
implements ManagementInterestReportSnapshotStore {
  constructor(
    private readonly query: ManagementInterestReportSnapshotQuery,
  ) {}

  async read(
    identity: VerifiedIdentity,
    projectId: string,
    snapshotId: string,
  ): Promise<ManagementInterestReportSnapshotRead> {
    try {
      const result = await this.query(
        `SELECT app_data.read_authorized_management_interest_report_snapshot_v1(
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

export class ManagementInterestReportSnapshotStoreError extends Error {
  constructor(readonly code: "forbidden") {
    super(code);
    this.name = "ManagementInterestReportSnapshotStoreError";
  }
}

function failure(
  status: number,
  code: string,
): ManagementInterestReportSnapshotHttpResult {
  return {status, body: {error: {code}}};
}

function auditedFailure(
  status: number,
  code: string,
  accessEventId: string,
): ManagementInterestReportSnapshotHttpResult {
  return {
    status,
    body: {error: {code, access_event_id: accessEventId}},
  };
}

function parseAccessResult(
  value: unknown,
  expectedSnapshotId: string,
  expectedProjectId: string,
): ManagementInterestReportSnapshotRead {
  const root = object(value);
  const status = root.result_status;
  const accessEventId = uuid(root.access_event_id);
  const requestedSnapshotId = uuid(root.requested_snapshot_id);
  if (
    root.access_contract_id !==
      "authorized_interest_management_report_snapshot_read_v1" ||
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
    assertInterestReport(protectedReport, expectedProjectId.toLowerCase());
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

function assertInterestReport(
  value: Record<string, unknown>,
  expectedProjectId: string,
): void {
  requireExactKeys(value, [
    "report_id",
    "report_version",
    "metric_id",
    "metric_version",
    "statistical_unit",
    "dimension",
    "query_fingerprint",
    "privacy_policy",
    "source_scope",
    "project_id",
    "periods",
    "cells",
  ]);
  if (
    value.report_id !== "contact_sessions_by_interest_level_two_periods" ||
    value.report_version !== 1 ||
    value.metric_id !== "interest_distribution" ||
    value.metric_version !== 1 ||
    value.statistical_unit !== "contact_session" ||
    value.dimension !== "interest_level" ||
    value.query_fingerprint !==
      "management-report:contact_sessions_by_interest_level_two_periods:v1" ||
    value.privacy_policy !== "management_interest_distribution_privacy_v1" ||
    value.source_scope !==
      "backend_accepted_active_contacts_current_revision" ||
    typeof value.project_id !== "string" ||
    !uuidPattern.test(value.project_id) ||
    value.project_id !== expectedProjectId ||
    !Array.isArray(value.cells)
  ) {
    throw invalidAccessResult();
  }
  assertPeriods(value.periods);
  assertInterestGrid(value.cells);
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
    periods.reporting_time_zone.length === 0 ||
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
}

function assertInterestGrid(value: unknown[]): void {
  if (value.length !== 10) throw invalidAccessResult();
  const privacyByPeriod = new Map<string, string>();
  for (let index = 0; index < value.length; index += 1) {
    const cell = object(value[index]);
    requireExactKeys(cell, [
      "period_key",
      "interest_level",
      "cell_order",
      "value_count",
      "privacy_status",
    ]);
    const expectedPeriod = index < 5 ? "previous" : "current";
    const expectedInterestLevel = index % 5;
    if (
      cell.period_key !== expectedPeriod ||
      cell.interest_level !== expectedInterestLevel ||
      cell.cell_order !== index ||
      (cell.privacy_status !== "displayed" &&
        cell.privacy_status !== "suppressed")
    ) {
      throw invalidAccessResult();
    }
    if (cell.privacy_status === "suppressed") {
      if (cell.value_count !== null) throw invalidAccessResult();
    } else if (
      !Number.isSafeInteger(cell.value_count) ||
      Number(cell.value_count) < 10
    ) {
      throw invalidAccessResult();
    }
    const previousStatus = privacyByPeriod.get(expectedPeriod);
    if (previousStatus !== undefined && previousStatus !== cell.privacy_status) {
      throw invalidAccessResult();
    }
    privacyByPeriod.set(expectedPeriod, cell.privacy_status);
  }
}

const sensitiveFactKeys = new Set([
  "app_user",
  "app_user_id",
  "contact",
  "contact_id",
  "contributor",
  "contributor_id",
  "contributor_key",
  "email",
  "phone",
  "place_name",
  "latitude",
  "longitude",
  "location",
  "source_id",
  "revision_id",
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

function finiteTimestamp(value: unknown): value is string {
  return typeof value === "string" && Number.isFinite(Date.parse(value));
}

function mapPostgresError(error: unknown): Error {
  const code = typeof error === "object" && error !== null && "code" in error
    ? String(error.code)
    : "";
  if (code === "42501") {
    return new ManagementInterestReportSnapshotStoreError("forbidden");
  }
  return error instanceof Error ? error : new Error(String(error));
}

function invalidAccessResult(): Error {
  return new Error(
    "invalid interest management report snapshot access result",
  );
}

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
