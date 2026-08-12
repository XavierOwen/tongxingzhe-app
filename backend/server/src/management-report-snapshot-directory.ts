import {bearerToken} from "./authorization.js";
import {
  IdentityVerificationError,
  type IdentityVerifier,
  type VerifiedIdentity,
} from "./identity.js";

export interface ManagementReportSnapshotDirectoryItem {
  readonly snapshotId: string;
  readonly reportId: string;
  readonly reportVersion: number;
  readonly reportingTimeZone: string;
  readonly dataCutoffUtc: string;
  readonly releasedAtUtc: string;
}

export interface ManagementReportSnapshotDirectoryResult {
  readonly accessEventId: string;
  readonly projectId: string;
  readonly snapshots: readonly ManagementReportSnapshotDirectoryItem[];
}

export interface ManagementReportSnapshotDirectoryStore {
  list(
    identity: VerifiedIdentity,
    projectId: string,
  ): Promise<ManagementReportSnapshotDirectoryResult>;
}

export interface ManagementReportSnapshotDirectoryRequest {
  readonly authorization: string | undefined;
  readonly projectId: string;
  readonly hasQuery: boolean;
  readonly hasBody: boolean;
}

export interface ManagementReportSnapshotDirectoryDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly directoryStore: ManagementReportSnapshotDirectoryStore | undefined;
}

export interface ManagementReportSnapshotDirectoryHttpResult {
  readonly status: number;
  readonly body: Readonly<Record<string, unknown>>;
}

export async function listManagementReportSnapshotDirectory(
  request: ManagementReportSnapshotDirectoryRequest,
  dependencies: ManagementReportSnapshotDirectoryDependencies,
): Promise<ManagementReportSnapshotDirectoryHttpResult> {
  const accessToken = bearerToken(request.authorization);
  if (accessToken === null) return failure(401, "unauthenticated");

  let identity: VerifiedIdentity;
  try {
    identity = await dependencies.identityVerifier.verify(accessToken);
  } catch (error) {
    return error instanceof IdentityVerificationError
      ? failure(401, "unauthenticated")
      : failure(503, "management_report_snapshot_directory_unavailable");
  }

  if (
    !uuidPattern.test(request.projectId) ||
    request.hasQuery ||
    request.hasBody
  ) {
    return failure(400, "invalid_management_report_snapshot_directory_request");
  }
  if (dependencies.directoryStore === undefined) {
    return failure(503, "management_report_snapshot_directory_unavailable");
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
      error instanceof ManagementReportSnapshotDirectoryStoreError &&
      error.code === "forbidden"
    ) {
      return failure(403, "management_report_snapshot_directory_forbidden");
    }
    return failure(503, "management_report_snapshot_directory_unavailable");
  }
}

export class ManagementReportSnapshotDirectoryStoreError extends Error {
  constructor(readonly code: "forbidden") {
    super(code);
    this.name = "ManagementReportSnapshotDirectoryStoreError";
  }
}

export type ManagementReportSnapshotDirectoryQuery = (
  text: string,
  values: readonly unknown[],
) => Promise<{readonly rows: readonly unknown[]}>;

export class PostgresManagementReportSnapshotDirectoryStore
implements ManagementReportSnapshotDirectoryStore {
  constructor(private readonly query: ManagementReportSnapshotDirectoryQuery) {}

  async list(
    identity: VerifiedIdentity,
    projectId: string,
  ): Promise<ManagementReportSnapshotDirectoryResult> {
    try {
      const result = await this.query(
        `SELECT app_data.list_authorized_management_report_snapshots_v1(
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

function parseDirectoryResult(
  value: unknown,
  expectedProjectId: string,
): ManagementReportSnapshotDirectoryResult {
  const root = object(value);
  requireExactKeys(root, [
    "access_contract_id",
    "access_event_id",
    "project_id",
    "snapshots",
  ]);
  if (
    root.access_contract_id !==
      "authorized_management_report_snapshot_directory_v1"
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
    if (snapshotIds.has(snapshot.snapshotId)) throw invalidDirectoryResult();
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

function parseDirectoryItem(value: unknown): ManagementReportSnapshotDirectoryItem {
  const row = object(value);
  requireExactKeys(row, [
    "snapshot_id",
    "report_id",
    "report_version",
    "reporting_time_zone",
    "data_cutoff_utc",
    "released_at_utc",
  ]);
  const reportId = controlledText(row.report_id, reportIdPattern, 128);
  const reportVersion = row.report_version;
  if (!Number.isInteger(reportVersion) || Number(reportVersion) <= 0) {
    throw invalidDirectoryResult();
  }
  const dataCutoffUtc = utcTimestamp(row.data_cutoff_utc);
  const releasedAtUtc = utcTimestamp(row.released_at_utc);
  if (releasedAtUtc < dataCutoffUtc) throw invalidDirectoryResult();
  return {
    snapshotId: uuid(row.snapshot_id),
    reportId,
    reportVersion: Number(reportVersion),
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
  left: ManagementReportSnapshotDirectoryItem,
  right: ManagementReportSnapshotDirectoryItem,
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
  if (!Number.isFinite(timestamp.getTime())) throw invalidDirectoryResult();
  return timestamp.toISOString();
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
    return new ManagementReportSnapshotDirectoryStoreError("forbidden");
  }
  return error instanceof Error ? error : new Error(String(error));
}

function invalidDirectoryResult(): Error {
  return new Error("invalid management report snapshot directory result");
}

function failure(
  status: number,
  code: string,
): ManagementReportSnapshotDirectoryHttpResult {
  return {status, body: {error: {code}}};
}

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const reportIdPattern = /^[a-z][a-z0-9_]*$/;
const timeZonePattern = /^[A-Za-z0-9._+/-]+$/;
const rfc3339Pattern =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/;
