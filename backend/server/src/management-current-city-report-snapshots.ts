import {bearerToken} from "./authorization.js";
import {
  IdentityVerificationError,
  type IdentityVerifier,
} from "./identity.js";
import type {VerifiedIdentity} from "./identity.js";

export type ManagementCurrentCityReportSnapshotRead = {
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

export interface ManagementCurrentCityReportSnapshotStore {
  read(
    identity: VerifiedIdentity,
    projectId: string,
    snapshotId: string,
  ): Promise<ManagementCurrentCityReportSnapshotRead>;
}

export interface ManagementCurrentCityReportSnapshotHttpRequest {
  readonly authorization: string | undefined;
  readonly projectId: string;
  readonly snapshotId: string;
  readonly hasQuery: boolean;
  readonly hasBody: boolean;
}

export interface ManagementCurrentCityReportSnapshotHttpDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly snapshotStore?: ManagementCurrentCityReportSnapshotStore;
}

export interface ManagementCurrentCityReportSnapshotHttpResult {
  readonly status: number;
  readonly body: Readonly<Record<string, unknown>>;
}

/**
 * Reads one current-city snapshot after authentication and strict route checks.
 *
 * The adapter is responsible for the fixed 6AP report contract. This boundary
 * only serializes its value-free outcomes and maps implementation failures to
 * stable HTTP responses.
 */
export async function readManagementCurrentCityReportSnapshot(
  request: ManagementCurrentCityReportSnapshotHttpRequest,
  dependencies: ManagementCurrentCityReportSnapshotHttpDependencies,
): Promise<ManagementCurrentCityReportSnapshotHttpResult> {
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
        "management_current_city_report_snapshot_unavailable",
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
      "invalid_management_current_city_report_snapshot_request",
    );
  }
  if (dependencies.snapshotStore === undefined) {
    return failure(
      503,
      "management_current_city_report_snapshot_unavailable",
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
        "management_current_city_report_snapshot_not_found",
        result.accessEventId,
      );
    }
    return auditedFailure(
      409,
      "management_current_city_report_snapshot_untrusted",
      result.accessEventId,
    );
  } catch (error) {
    if (
      error instanceof ManagementCurrentCityReportSnapshotStoreError &&
      error.code === "forbidden"
    ) {
      return failure(
        403,
        "management_current_city_report_snapshot_forbidden",
      );
    }
    return failure(
      503,
      "management_current_city_report_snapshot_unavailable",
    );
  }
}

export type ManagementCurrentCityReportSnapshotQuery = (
  text: string,
  values: readonly unknown[],
) => Promise<{readonly rows: readonly unknown[]}>;

export class PostgresManagementCurrentCityReportSnapshotStore
implements ManagementCurrentCityReportSnapshotStore {
  constructor(
    private readonly query: ManagementCurrentCityReportSnapshotQuery,
  ) {}

  async read(
    identity: VerifiedIdentity,
    projectId: string,
    snapshotId: string,
  ): Promise<ManagementCurrentCityReportSnapshotRead> {
    try {
      const result = await this.query(
        `SELECT app_data.read_authorized_management_current_city_report_snapshot_v1(
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

export class ManagementCurrentCityReportSnapshotStoreError extends Error {
  constructor(readonly code: "forbidden") {
    super(code);
    this.name = "ManagementCurrentCityReportSnapshotStoreError";
  }
}

function failure(
  status: number,
  code: string,
): ManagementCurrentCityReportSnapshotHttpResult {
  return {status, body: {error: {code}}};
}

function auditedFailure(
  status: number,
  code: string,
  accessEventId: string,
): ManagementCurrentCityReportSnapshotHttpResult {
  return {
    status,
    body: {error: {code, access_event_id: accessEventId}},
  };
}

function parseAccessResult(
  value: unknown,
  expectedSnapshotId: string,
  expectedProjectId: string,
): ManagementCurrentCityReportSnapshotRead {
  const root = object(value);
  const status = root.result_status;
  const accessEventId = uuid(root.access_event_id);
  const requestedSnapshotId = uuid(root.requested_snapshot_id);
  if (
    root.access_contract_id !==
      "authorized_current_city_management_report_snapshot_read_v1" ||
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
    assertCurrentCityReport(protectedReport, expectedProjectId.toLowerCase());
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

function assertCurrentCityReport(
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
    "target_context",
    "result_status",
    "cells",
  ]);
  if (
    value.report_id !== "contact_sessions_by_current_city_two_periods" ||
    value.report_version !== 1 ||
    value.metric_id !== "contact_sessions" ||
    value.metric_version !== 1 ||
    value.dimension !== "current_city" ||
    value.view_mode !== "current" ||
    value.region_granularity !== "city" ||
    value.query_fingerprint !==
      "management-report:contact_sessions_by_current_city_two_periods:v1" ||
    value.privacy_policy !== "management_current_city_contact_session_privacy_v1" ||
    value.source_scope !==
      "backend_accepted_active_contacts_current_revision" ||
    value.result_status !== "completed" ||
    !Array.isArray(value.cells) ||
    typeof value.project_id !== "string" ||
    !uuidPattern.test(value.project_id) ||
    value.project_id !== expectedProjectId.toLowerCase() ||
    !Number.isSafeInteger(value.source_change_sequence) ||
    Number(value.source_change_sequence) < 0
  ) {
    throw invalidAccessResult();
  }
  if (
    typeof value.data_cutoff_utc !== "string" ||
    !finiteTimestamp(value.data_cutoff_utc)
  ) {
    throw invalidAccessResult();
  }
  const dataCutoffUtc = value.data_cutoff_utc;
  assertPeriods(value.periods, dataCutoffUtc);
  assertTargetContext(value.target_context, dataCutoffUtc);
  assertCurrentCityGrid(value.cells);
  assertNoExactLocationFacts(value);
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
    periods.reporting_time_zone.length === 0 ||
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

function assertTargetContext(value: unknown, dataCutoffUtc: string): void {
  const targetContext = object(value);
  requireExactKeys(targetContext, [
    "target_context_contract_id",
    "result_status",
    "reason_code",
    "data_cutoff_utc",
    "target_tree_version",
    "target_content_fingerprint",
    "selection_sequence",
    "selection_source",
    "selection_evidence_at_utc",
    "tree_published_at_utc",
  ]);
  const validSelectionEvidence =
    (targetContext.reason_code === "publication_selection" &&
      targetContext.selection_source === "publication") ||
    (targetContext.reason_code === "migration_baseline_observation" &&
      targetContext.selection_source === "migration_baseline");
  if (
    targetContext.target_context_contract_id !==
      "management-region-target-context:v1" ||
    targetContext.result_status !== "selected" ||
    !validSelectionEvidence ||
    targetContext.data_cutoff_utc !== dataCutoffUtc ||
    typeof targetContext.target_tree_version !== "string" ||
    targetContext.target_tree_version.trim().length === 0 ||
    typeof targetContext.target_content_fingerprint !== "string" ||
    !/^[0-9a-f]{64}$/.test(targetContext.target_content_fingerprint) ||
    !positiveInteger(targetContext.selection_sequence) ||
    !finiteTimestamp(targetContext.selection_evidence_at_utc) ||
    !finiteTimestamp(targetContext.tree_published_at_utc) ||
    Date.parse(targetContext.selection_evidence_at_utc) >
      Date.parse(dataCutoffUtc) ||
    Date.parse(targetContext.tree_published_at_utc) > Date.parse(dataCutoffUtc)
  ) {
    throw invalidAccessResult();
  }
}

function assertCurrentCityGrid(value: unknown[]): void {
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
    const expectedOrder = index;
    if (
      cell.period_key !== expectedPeriod ||
      typeof cell.city_id !== "string" ||
      cell.city_id.trim().length === 0 ||
      cell.cell_order !== expectedOrder ||
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

function positiveInteger(value: unknown): value is number {
  return Number.isSafeInteger(value) && Number(value) > 0;
}

function finiteTimestamp(value: unknown): value is string {
  return typeof value === "string" && Number.isFinite(Date.parse(value));
}

const exactLocationFactKeys = new Set([
  "contact",
  "contact_id",
  "source",
  "source_id",
  "contributor",
  "contributor_id",
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
  "name",
  "email",
  "phone",
  "location",
  "location_source",
  "locationSource",
  "location_kind",
  "locationKind",
  "place_name",
  "placeName",
  "smallest_region_id",
  "smallestRegionId",
  "region_tree_version",
  "regionTreeVersion",
  "latitude",
  "longitude",
  "accuracy_meters",
  "accuracyMeters",
  "resolver_contract_version",
  "resolverContractVersion",
  "region_tree_content_fingerprint",
  "regionTreeContentFingerprint",
]);

function assertNoExactLocationFacts(value: unknown): void {
  if (Array.isArray(value)) {
    for (const item of value) assertNoExactLocationFacts(item);
    return;
  }
  if (typeof value !== "object" || value === null) return;
  for (const [key, item] of Object.entries(value)) {
    if (exactLocationFactKeys.has(key)) throw invalidAccessResult();
    assertNoExactLocationFacts(item);
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

function mapPostgresError(error: unknown): Error {
  const code = typeof error === "object" && error !== null && "code" in error
    ? String(error.code)
    : "";
  if (code === "42501") {
    return new ManagementCurrentCityReportSnapshotStoreError("forbidden");
  }
  return error instanceof Error ? error : new Error(String(error));
}

function invalidAccessResult(): Error {
  return new Error(
    "invalid current-city management report snapshot access result",
  );
}

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
