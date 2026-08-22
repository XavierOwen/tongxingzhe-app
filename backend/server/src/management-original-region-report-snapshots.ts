import type {VerifiedIdentity} from "./identity.js";

export type ManagementOriginalRegionReportSnapshotRead = {
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

export interface ManagementOriginalRegionReportSnapshotStore {
  read(
    identity: VerifiedIdentity,
    projectId: string,
    snapshotId: string,
  ): Promise<ManagementOriginalRegionReportSnapshotRead>;
}

export type ManagementOriginalRegionReportSnapshotQuery = (
  text: string,
  values: readonly unknown[],
) => Promise<{readonly rows: readonly unknown[]}>;

/**
 * Calls the fixed 6BI runtime bridge once and accepts only the original-region
 * report contract. Identity resolution, authorization, provenance checks, and
 * value-free auditing remain in PostgreSQL; this adapter does not recalculate
 * a report or access app_private directly.
 */
export class PostgresManagementOriginalRegionReportSnapshotStore
implements ManagementOriginalRegionReportSnapshotStore {
  constructor(
    private readonly query: ManagementOriginalRegionReportSnapshotQuery,
  ) {}

  async read(
    identity: VerifiedIdentity,
    projectId: string,
    snapshotId: string,
  ): Promise<ManagementOriginalRegionReportSnapshotRead> {
    try {
      const result = await this.query(
        `SELECT app_data.read_authorized_management_original_region_report_snapshot_v1(
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

export class ManagementOriginalRegionReportSnapshotStoreError extends Error {
  constructor(readonly code: "forbidden") {
    super(code);
    this.name = "ManagementOriginalRegionReportSnapshotStoreError";
  }
}

function parseAccessResult(
  value: unknown,
  expectedSnapshotId: string,
  expectedProjectId: string,
): ManagementOriginalRegionReportSnapshotRead {
  const root = object(value);
  const status = root.result_status;
  const accessEventId = uuid(root.access_event_id);
  const requestedSnapshotId = uuid(root.requested_snapshot_id);
  if (
    root.access_contract_id !==
      "authorized_original_region_management_report_snapshot_read_v1" ||
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
    assertOriginalRegionReport(
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

function assertOriginalRegionReport(
  value: Record<string, unknown>,
  expectedProjectId: string,
): void {
  requireExactKeys(value, [
    "report_id",
    "report_version",
    "metric_id",
    "metric_version",
    "dimension",
    "view_mode",
    "region_granularity",
    "query_fingerprint",
    "privacy_policy",
    "source_scope",
    "project_id",
    "periods",
    "data_cutoff_utc",
    "source_change_sequence",
    "source_tree_context",
    "result_status",
    "cells",
  ]);
  if (
    value.report_id !== "contact_sessions_by_original_region_two_periods" ||
    value.report_version !== 1 ||
    value.metric_id !== "contact_sessions" ||
    value.metric_version !== 1 ||
    value.dimension !== "original_region" ||
    value.view_mode !== "original" ||
    value.region_granularity !== "city" ||
    value.query_fingerprint !==
      "management-report:contact_sessions_by_original_region_two_periods:v1" ||
    value.privacy_policy !==
      "management_original_region_contact_session_privacy_v1" ||
    value.source_scope !==
      "backend_accepted_active_contacts_original_current_revision" ||
    value.result_status !== "completed" ||
    typeof value.project_id !== "string" ||
    !uuidPattern.test(value.project_id) ||
    value.project_id !== expectedProjectId ||
    !Number.isSafeInteger(value.source_change_sequence) ||
    Number(value.source_change_sequence) < 0 ||
    !Array.isArray(value.cells)
  ) {
    throw invalidAccessResult();
  }
  if (
    typeof value.data_cutoff_utc !== "string" ||
    !finiteTimestamp(value.data_cutoff_utc)
  ) {
    throw invalidAccessResult();
  }
  assertPeriods(value.periods, value.data_cutoff_utc);
  assertSourceTreeContext(value.source_tree_context);
  assertOriginalRegionGrid(value.cells);
  assertNoSensitiveFacts(value);
}

function assertPeriods(value: unknown, dataCutoffUtc: string): void {
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
    periods.data_cutoff_utc !== dataCutoffUtc
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
    Date.parse(current.until_utc) > Date.parse(dataCutoffUtc)
  ) {
    throw invalidAccessResult();
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

function assertSourceTreeContext(value: unknown): void {
  const sourceTreeContext = object(value);
  requireExactKeys(sourceTreeContext, [
    "source_tree_context_contract_id",
    "result_status",
    "reason_code",
    "source_tree_version",
    "source_content_fingerprint",
  ]);
  if (
    sourceTreeContext.source_tree_context_contract_id !==
      "management-original-region-source-tree:v1" ||
    sourceTreeContext.result_status !== "selected" ||
    sourceTreeContext.reason_code !== "single_original_source_tree" ||
    typeof sourceTreeContext.source_tree_version !== "string" ||
    sourceTreeContext.source_tree_version.trim().length === 0 ||
    sourceTreeContext.source_tree_version.length > 200 ||
    typeof sourceTreeContext.source_content_fingerprint !== "string" ||
    !/^[0-9a-f]{64}$/.test(sourceTreeContext.source_content_fingerprint)
  ) {
    throw invalidAccessResult();
  }
}

function assertOriginalRegionGrid(value: unknown[]): void {
  if (value.length === 0 || value.length % 2 !== 0) {
    throw invalidAccessResult();
  }
  const cityCount = value.length / 2;
  const previousCities: string[] = [];
  const currentCities: string[] = [];
  for (let index = 0; index < value.length; index += 1) {
    const cell = object(value[index]);
    requireExactKeys(cell, [
      "period_key",
      "city_id",
      "cell_order",
      "value_count",
      "privacy_status",
    ]);
    const expectedPeriod = index < cityCount ? "previous" : "current";
    if (
      cell.period_key !== expectedPeriod ||
      typeof cell.city_id !== "string" ||
      cell.city_id.trim().length === 0 ||
      cell.city_id.length > 120 ||
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
    const cityId = cell.city_id;
    if (index < cityCount) {
      const previousCity = previousCities[previousCities.length - 1];
      if (previousCity !== undefined && previousCity >= cityId) {
        throw invalidAccessResult();
      }
      previousCities.push(cityId);
    } else {
      const currentCity = currentCities[currentCities.length - 1];
      if (currentCity !== undefined && currentCity >= cityId) {
        throw invalidAccessResult();
      }
      currentCities.push(cityId);
    }
  }
  if (
    previousCities.length !== currentCities.length ||
    previousCities.some((cityId, index) => cityId !== currentCities[index])
  ) {
    throw invalidAccessResult();
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
  "placeName",
  "latitude",
  "longitude",
  "location",
  "location_source",
  "locationSource",
  "location_kind",
  "locationKind",
  "source",
  "source_id",
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
  "smallest_region_id",
  "smallestRegionId",
  "region_tree_version",
  "regionTreeVersion",
  "accuracy_meters",
  "accuracyMeters",
  "resolver_contract_version",
  "resolverContractVersion",
  "region_tree_content_fingerprint",
  "regionTreeContentFingerprint",
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
    return new ManagementOriginalRegionReportSnapshotStoreError("forbidden");
  }
  return error instanceof Error ? error : new Error(String(error));
}

function invalidAccessResult(): Error {
  return new Error(
    "invalid original-region management report snapshot access result",
  );
}

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
