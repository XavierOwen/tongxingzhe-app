import {bearerToken} from "./authorization.js";
import {
  IdentityVerificationError,
  type IdentityVerifier,
  type VerifiedIdentity,
} from "./identity.js";

export interface ManagementOriginalRegionReportSnapshotDirectoryItem {
  readonly snapshotId: string;
  readonly reportId: "contact_sessions_by_original_region_two_periods";
  readonly reportVersion: 1;
  readonly reportingTimeZone: string;
  readonly dataCutoffUtc: string;
  readonly releasedAtUtc: string;
}

export interface ManagementOriginalRegionReportSnapshotDirectoryRead {
  readonly accessContractId:
    "authorized_original_region_management_report_snapshot_directory_v1";
  readonly accessEventId: string;
  readonly projectId: string;
  readonly snapshots: readonly ManagementOriginalRegionReportSnapshotDirectoryItem[];
}

export interface ManagementOriginalRegionReportSnapshotDirectoryStore {
  list(
    identity: VerifiedIdentity,
    projectId: string,
  ): Promise<ManagementOriginalRegionReportSnapshotDirectoryRead>;
}

export interface ManagementOriginalRegionReportSnapshotDirectoryRequest {
  readonly authorization: string | undefined;
  readonly projectId: string;
  readonly hasQuery: boolean;
  readonly hasBody: boolean;
}

export interface ManagementOriginalRegionReportSnapshotDirectoryDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly directoryStore?: ManagementOriginalRegionReportSnapshotDirectoryStore;
}

export interface ManagementOriginalRegionReportSnapshotDirectoryHttpResult {
  readonly status: number;
  readonly body: Readonly<Record<string, unknown>>;
}

/**
 * Authenticates and lists fixed original-region snapshot metadata through the
 * dedicated 6BK directory store. Route validation follows authentication so
 * malformed project identifiers cannot reveal protected project state.
 */
export async function listManagementOriginalRegionReportSnapshotDirectory(
  request: ManagementOriginalRegionReportSnapshotDirectoryRequest,
  dependencies: ManagementOriginalRegionReportSnapshotDirectoryDependencies,
): Promise<ManagementOriginalRegionReportSnapshotDirectoryHttpResult> {
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
        "management_original_region_report_snapshot_directory_unavailable",
      );
  }

  if (
    !uuidPattern.test(request.projectId) ||
    request.hasQuery ||
    request.hasBody
  ) {
    return failure(
      400,
      "invalid_management_original_region_report_snapshot_directory_request",
    );
  }
  if (dependencies.directoryStore === undefined) {
    return failure(
      503,
      "management_original_region_report_snapshot_directory_unavailable",
    );
  }

  try {
    const result = await dependencies.directoryStore.list(
      identity,
      request.projectId,
    );
    return {
      status: 200,
      body: {
        access_event_id: result.accessEventId,
        project_id: result.projectId,
        snapshots: result.snapshots.map((snapshot) => ({
          snapshot_id: snapshot.snapshotId,
          report_id: snapshot.reportId,
          report_version: snapshot.reportVersion,
          reporting_time_zone: snapshot.reportingTimeZone,
          data_cutoff_utc: snapshot.dataCutoffUtc,
          released_at_utc: snapshot.releasedAtUtc,
        })),
      },
    };
  } catch (error) {
    if (
      error instanceof ManagementOriginalRegionReportSnapshotDirectoryStoreError &&
      error.code === "forbidden"
    ) {
      return failure(
        403,
        "management_original_region_report_snapshot_directory_forbidden",
      );
    }
    return failure(
      503,
      "management_original_region_report_snapshot_directory_unavailable",
    );
  }
}

export type ManagementOriginalRegionReportSnapshotDirectoryQuery = (
  text: string,
  values: readonly unknown[],
) => Promise<{readonly rows: readonly unknown[]}>;

/**
 * Calls only the 0071 runtime bridge. Authorization, original-region
 * provenance filtering, locking and the value-free audit remain inside
 * PostgreSQL; this adapter does not open a transaction or read app_private.
 */
export class PostgresManagementOriginalRegionReportSnapshotDirectoryStore
implements ManagementOriginalRegionReportSnapshotDirectoryStore {
  constructor(
    private readonly query: ManagementOriginalRegionReportSnapshotDirectoryQuery,
  ) {}

  async list(
    identity: VerifiedIdentity,
    projectId: string,
  ): Promise<ManagementOriginalRegionReportSnapshotDirectoryRead> {
    try {
      const result = await this.query(
        `SELECT app_data.list_authorized_management_original_region_report_snapshots_v1(
           $1::text, $2::text, $3::uuid
         ) AS directory_result`,
        [identity.issuer, identity.subject, projectId],
      );
      if (result.rows.length !== 1) throw invalidDirectoryResult();
      return parseDirectoryResult(
        rowField(result.rows[0], "directory_result"),
        projectId,
      );
    } catch (error) {
      throw mapPostgresError(error);
    }
  }
}

export class ManagementOriginalRegionReportSnapshotDirectoryStoreError
extends Error {
  constructor(readonly code: "forbidden") {
    super(code);
    this.name = "ManagementOriginalRegionReportSnapshotDirectoryStoreError";
  }
}

function parseDirectoryResult(
  value: unknown,
  expectedProjectId: string,
): ManagementOriginalRegionReportSnapshotDirectoryRead {
  const root = object(value);
  requireExactKeys(root, [
    "access_contract_id",
    "access_event_id",
    "project_id",
    "snapshots",
  ]);
  if (
    root.access_contract_id !==
      "authorized_original_region_management_report_snapshot_directory_v1"
  ) {
    throw invalidDirectoryResult();
  }

  const projectId = uuid(root.project_id);
  if (projectId !== expectedProjectId.toLowerCase()) {
    throw invalidDirectoryResult();
  }
  if (!Array.isArray(root.snapshots) || root.snapshots.length > 20) {
    throw invalidDirectoryResult();
  }

  const snapshots = root.snapshots.map(parseDirectoryItem);
  const snapshotIds = new Set<string>();
  for (let index = 0; index < snapshots.length; index += 1) {
    const snapshot = snapshots[index]!;
    if (snapshotIds.has(snapshot.snapshotId)) {
      throw invalidDirectoryResult();
    }
    snapshotIds.add(snapshot.snapshotId);
    if (
      index > 0 &&
      compareDirectoryItems(snapshots[index - 1]!, snapshot) <= 0
    ) {
      throw invalidDirectoryResult();
    }
  }

  return {
    accessContractId:
      "authorized_original_region_management_report_snapshot_directory_v1",
    accessEventId: uuid(root.access_event_id),
    projectId,
    snapshots,
  };
}

function parseDirectoryItem(
  value: unknown,
): ManagementOriginalRegionReportSnapshotDirectoryItem {
  const row = object(value);
  requireExactKeys(row, [
    "snapshot_id",
    "report_id",
    "report_version",
    "reporting_time_zone",
    "data_cutoff_utc",
    "released_at_utc",
  ]);
  if (
    row.report_id !== "contact_sessions_by_original_region_two_periods" ||
    row.report_version !== 1
  ) {
    throw invalidDirectoryResult();
  }
  const dataCutoffUtc = utcTimestamp(row.data_cutoff_utc);
  const releasedAtUtc = utcTimestamp(row.released_at_utc);
  if (releasedAtUtc < dataCutoffUtc) throw invalidDirectoryResult();
  return {
    snapshotId: uuid(row.snapshot_id),
    reportId: row.report_id,
    reportVersion: row.report_version,
    reportingTimeZone: controlledText(
      row.reporting_time_zone,
      timeZonePattern,
      255,
    ),
    dataCutoffUtc,
    releasedAtUtc,
  };
}

function compareDirectoryItems(
  left: ManagementOriginalRegionReportSnapshotDirectoryItem,
  right: ManagementOriginalRegionReportSnapshotDirectoryItem,
): number {
  return left.dataCutoffUtc.localeCompare(right.dataCutoffUtc) ||
    left.releasedAtUtc.localeCompare(right.releasedAtUtc) ||
    left.snapshotId.localeCompare(right.snapshotId);
}

function rowField(value: unknown, name: string): unknown {
  const row = object(value);
  if (!(name in row)) throw invalidDirectoryResult();
  return row[name];
}

function object(value: unknown): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw invalidDirectoryResult();
  }
  return value as Record<string, unknown>;
}

function uuid(value: unknown): string {
  if (typeof value !== "string" || !uuidPattern.test(value)) {
    throw invalidDirectoryResult();
  }
  return value.toLowerCase();
}

function controlledText(
  value: unknown,
  pattern: RegExp,
  maximumLength: number,
): string {
  if (
    typeof value !== "string" ||
    value.length === 0 ||
    value.length > maximumLength ||
    !pattern.test(value)
  ) {
    throw invalidDirectoryResult();
  }
  return value;
}

function utcTimestamp(value: unknown): string {
  if (typeof value !== "string" || !rfc3339Pattern.test(value)) {
    throw invalidDirectoryResult();
  }
  const timestamp = new Date(value);
  if (
    !Number.isFinite(timestamp.getTime()) ||
    timestamp.toISOString() !== value
  ) {
    throw invalidDirectoryResult();
  }
  return value;
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
    throw invalidDirectoryResult();
  }
}

function mapPostgresError(error: unknown): Error {
  const code = typeof error === "object" && error !== null && "code" in error
    ? String(error.code)
    : "";
  if (code === "42501") {
    return new ManagementOriginalRegionReportSnapshotDirectoryStoreError(
      "forbidden",
    );
  }
  return error instanceof Error ? error : new Error(String(error));
}

function failure(
  status: number,
  code: string,
): ManagementOriginalRegionReportSnapshotDirectoryHttpResult {
  return {status, body: {error: {code}}};
}

function invalidDirectoryResult(): Error {
  return new Error(
    "invalid original-region management report snapshot directory result",
  );
}

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const timeZonePattern = /^[A-Za-z0-9._+/-]+$/;
const rfc3339Pattern =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/;
