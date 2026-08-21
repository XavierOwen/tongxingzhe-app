import {bearerToken} from "./authorization.js";
import {
  IdentityVerificationError,
  type IdentityVerifier,
  type VerifiedIdentity,
} from "./identity.js";

export interface ManagementCurrentCityReportSnapshotDirectoryItem {
  readonly snapshotId: string;
  readonly reportId: "contact_sessions_by_current_city_two_periods";
  readonly reportVersion: 1;
  readonly reportingTimeZone: string;
  readonly dataCutoffUtc: string;
  readonly releasedAtUtc: string;
}

export interface ManagementCurrentCityReportSnapshotDirectoryRead {
  readonly accessEventId: string;
  readonly projectId: string;
  readonly snapshots: readonly ManagementCurrentCityReportSnapshotDirectoryItem[];
}

export interface ManagementCurrentCityReportSnapshotDirectoryStore {
  list(
    identity: VerifiedIdentity,
    projectId: string,
  ): Promise<ManagementCurrentCityReportSnapshotDirectoryRead>;
}

export interface ManagementCurrentCityReportSnapshotDirectoryRequest {
  readonly authorization: string | undefined;
  readonly projectId: string;
  readonly hasQuery: boolean;
  readonly hasBody: boolean;
}

export interface ManagementCurrentCityReportSnapshotDirectoryDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly directoryStore?: ManagementCurrentCityReportSnapshotDirectoryStore;
}

export interface ManagementCurrentCityReportSnapshotDirectoryHttpResult {
  readonly status: number;
  readonly body: Readonly<Record<string, unknown>>;
}

export async function listManagementCurrentCityReportSnapshotDirectory(
  request: ManagementCurrentCityReportSnapshotDirectoryRequest,
  dependencies: ManagementCurrentCityReportSnapshotDirectoryDependencies,
): Promise<ManagementCurrentCityReportSnapshotDirectoryHttpResult> {
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
        "management_current_city_report_snapshot_directory_unavailable",
      );
  }

  if (
    !uuidPattern.test(request.projectId) ||
    request.hasQuery ||
    request.hasBody
  ) {
    return failure(
      400,
      "invalid_management_current_city_report_snapshot_directory_request",
    );
  }
  if (dependencies.directoryStore === undefined) {
    return failure(
      503,
      "management_current_city_report_snapshot_directory_unavailable",
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
      error instanceof ManagementCurrentCityReportSnapshotDirectoryStoreError &&
      error.code === "forbidden"
    ) {
      return failure(
        403,
        "management_current_city_report_snapshot_directory_forbidden",
      );
    }
    return failure(
      503,
      "management_current_city_report_snapshot_directory_unavailable",
    );
  }
}

export type ManagementCurrentCityReportSnapshotDirectoryQuery = (
  text: string,
  values: readonly unknown[],
) => Promise<{readonly rows: readonly unknown[]}>;

export class PostgresManagementCurrentCityReportSnapshotDirectoryStore
implements ManagementCurrentCityReportSnapshotDirectoryStore {
  constructor(
    private readonly query: ManagementCurrentCityReportSnapshotDirectoryQuery,
  ) {}

  async list(
    identity: VerifiedIdentity,
    projectId: string,
  ): Promise<ManagementCurrentCityReportSnapshotDirectoryRead> {
    try {
      const result = await this.query(
        `SELECT app_data.list_authorized_management_current_city_report_snapshots_v1(
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

export class ManagementCurrentCityReportSnapshotDirectoryStoreError
extends Error {
  constructor(readonly code: "forbidden") {
    super(code);
    this.name = "ManagementCurrentCityReportSnapshotDirectoryStoreError";
  }
}

function parseDirectoryResult(
  value: unknown,
  expectedProjectId: string,
): ManagementCurrentCityReportSnapshotDirectoryRead {
  const root = object(value);
  requireExactKeys(root, [
    "access_contract_id",
    "access_event_id",
    "project_id",
    "snapshots",
  ]);
  if (
    root.access_contract_id !==
      "authorized_current_city_management_report_snapshot_directory_v1"
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
    accessEventId: uuid(root.access_event_id),
    projectId,
    snapshots,
  };
}

function parseDirectoryItem(
  value: unknown,
): ManagementCurrentCityReportSnapshotDirectoryItem {
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
    row.report_id !== "contact_sessions_by_current_city_two_periods" ||
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
  left: ManagementCurrentCityReportSnapshotDirectoryItem,
  right: ManagementCurrentCityReportSnapshotDirectoryItem,
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
    return new ManagementCurrentCityReportSnapshotDirectoryStoreError(
      "forbidden",
    );
  }
  return error instanceof Error ? error : new Error(String(error));
}

function failure(
  status: number,
  code: string,
): ManagementCurrentCityReportSnapshotDirectoryHttpResult {
  return {status, body: {error: {code}}};
}

function invalidDirectoryResult(): Error {
  return new Error(
    "invalid current-city management report snapshot directory result",
  );
}

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const timeZonePattern = /^[A-Za-z0-9._+/-]+$/;
const rfc3339Pattern =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/;
