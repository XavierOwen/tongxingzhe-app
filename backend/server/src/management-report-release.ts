import {bearerToken} from "./authorization.js";
import {
  IdentityVerificationError,
  type IdentityVerifier,
  type VerifiedIdentity,
} from "./identity.js";

export type ManagementReportReleaseStatus =
  | "approved_baseline"
  | "approved"
  | "blocked";

export interface ManagementReportReleaseResult {
  readonly releaseContractId:
    "trusted_management_report_snapshot_release_v2";
  readonly releaseRequestId: string;
  readonly projectId: string;
  readonly releaseLineageId:
    "management-report:contact_sessions_by_channel_two_periods";
  readonly reportId: "contact_sessions_by_channel_two_periods";
  readonly reportVersion: 1;
  readonly queryFingerprint:
    "management-report:contact_sessions_by_channel_two_periods:v1";
  readonly reportingTimeZoneVersionNumber: number;
  readonly reportingTimeZone: string;
  readonly dataCutoffUtc: string;
  readonly comparedSnapshotId: string | null;
  readonly releasedSnapshotId: string | null;
  readonly resultStatus: ManagementReportReleaseStatus;
  readonly reasonCodes: readonly string[];
}

export interface ManagementReportReleaseStore {
  release(
    identity: VerifiedIdentity,
    projectId: string,
    releaseRequestId: string,
  ): Promise<ManagementReportReleaseResult>;
}

export interface ManagementReportReleaseDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly releaseStore: ManagementReportReleaseStore | undefined;
}

export interface ManagementReportReleaseRequest {
  readonly authorization: string | undefined;
  readonly projectId: string;
  readonly hasQuery: boolean;
  /** Read the JSON body only after authentication and route validation. */
  readonly readBody: () => Promise<unknown>;
}

export interface ManagementReportReleaseHttpResult {
  readonly status: number;
  readonly body: Readonly<Record<string, unknown>>;
}

export type ManagementReportReleaseAuthentication = {
  readonly status: "verified";
  readonly identity: VerifiedIdentity;
} | {
  readonly status: "rejected";
  readonly result: ManagementReportReleaseHttpResult;
};

/** Authenticate without reading a release body or touching the release store. */
export async function authenticateManagementReportRelease(
  authorization: string | undefined,
  identityVerifier: IdentityVerifier,
): Promise<ManagementReportReleaseAuthentication> {
  const accessToken = bearerToken(authorization);
  if (accessToken === null) {
    return {status: "rejected", result: failure(401, "unauthenticated")};
  }
  try {
    return {
      status: "verified",
      identity: await identityVerifier.verify(accessToken),
    };
  } catch (error) {
    return {
      status: "rejected",
      result: error instanceof IdentityVerificationError
        ? failure(401, "unauthenticated")
        : failure(503, "management_report_release_unavailable"),
    };
  }
}

export async function releaseManagementReportSnapshot(
  request: ManagementReportReleaseRequest,
  dependencies: ManagementReportReleaseDependencies,
): Promise<ManagementReportReleaseHttpResult> {
  const authentication = await authenticateManagementReportRelease(
    request.authorization,
    dependencies.identityVerifier,
  );
  if (authentication.status === "rejected") return authentication.result;

  if (!uuidPattern.test(request.projectId) || request.hasQuery) {
    return failure(400, "invalid_management_report_release_request");
  }
  if (dependencies.releaseStore === undefined) {
    return failure(503, "management_report_release_unavailable");
  }

  const body = await request.readBody();
  const parsedBody = parseManagementReportReleaseBody(body);
  if (parsedBody === null) {
    return failure(400, "invalid_management_report_release_request");
  }

  try {
    const result = await dependencies.releaseStore.release(
      authentication.identity,
      request.projectId,
      parsedBody.releaseRequestId,
    );
    return {status: 200, body: serializeReleaseResult(result)};
  } catch (error) {
    return releaseStoreFailure(error);
  }
}

export interface ManagementReportReleaseBody {
  readonly releaseRequestId: string;
}

/** Parse the only client-controlled field accepted by the release endpoint. */
export function parseManagementReportReleaseBody(
  value: unknown,
): ManagementReportReleaseBody | null {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return null;
  }
  const root = value as Record<string, unknown>;
  if (!hasExactKeys(root, ["release_request_id"])) return null;
  const releaseRequestId = uuid(root.release_request_id);
  return releaseRequestId === null ? null : {releaseRequestId};
}

export type ManagementReportReleaseQuery = (
  text: string,
  values: readonly unknown[],
) => Promise<{readonly rows: readonly unknown[]}>;

export class PostgresManagementReportReleaseStore
implements ManagementReportReleaseStore {
  constructor(private readonly query: ManagementReportReleaseQuery) {}

  async release(
    identity: VerifiedIdentity,
    projectId: string,
    releaseRequestId: string,
  ): Promise<ManagementReportReleaseResult> {
    try {
      const result = await this.query(
        `SELECT app_data.release_management_report_snapshot_v1(
           $1::text, $2::text, $3::uuid, $4::uuid
         ) AS release_result`,
        [identity.issuer, identity.subject, releaseRequestId, projectId],
      );
      if (result.rows.length !== 1) {
        throw invalidReleaseResult();
      }
      return parseReleaseResult(
        rowField(result.rows[0], "release_result"),
        projectId,
        releaseRequestId,
      );
    } catch (error) {
      throw mapPostgresError(error);
    }
  }
}

export class ManagementReportReleaseStoreError extends Error {
  constructor(readonly code: "forbidden" | "conflict") {
    super(code);
    this.name = "ManagementReportReleaseStoreError";
  }
}

function parseReleaseResult(
  value: unknown,
  expectedProjectId: string,
  expectedReleaseRequestId: string,
): ManagementReportReleaseResult {
  const root = object(value);
  requireExactKeys(root, releaseResultKeys);

  if (
    root.release_contract_id !==
      "trusted_management_report_snapshot_release_v2" ||
    root.release_lineage_id !==
      "management-report:contact_sessions_by_channel_two_periods" ||
    root.report_id !== "contact_sessions_by_channel_two_periods" ||
    root.report_version !== 1 ||
    root.query_fingerprint !==
      "management-report:contact_sessions_by_channel_two_periods:v1"
  ) {
    throw invalidReleaseResult();
  }

  const releaseRequestId = uuid(root.release_request_id);
  const projectId = uuid(root.project_id);
  if (
    releaseRequestId === null ||
    projectId === null ||
    releaseRequestId !== expectedReleaseRequestId.toLowerCase() ||
    projectId !== expectedProjectId.toLowerCase()
  ) {
    throw invalidReleaseResult();
  }

  const reportingTimeZoneVersionNumber = positiveInteger(
    root.reporting_time_zone_version_number,
  );
  const reportingTimeZone = ianaTimeZone(root.reporting_time_zone);
  const dataCutoffUtc = utcTimestamp(root.data_cutoff_utc);
  if (
    reportingTimeZoneVersionNumber === null ||
    reportingTimeZone === null ||
    dataCutoffUtc === null
  ) {
    throw invalidReleaseResult();
  }

  const comparedSnapshotId = nullableUuid(root.compared_snapshot_id);
  const releasedSnapshotId = nullableUuid(root.released_snapshot_id);
  if (
    comparedSnapshotId === undefined ||
    releasedSnapshotId === undefined
  ) {
    throw invalidReleaseResult();
  }

  const resultStatus = releaseStatus(root.result_status);
  const reasonCodes = reasonCodeArray(root.reason_codes);
  if (resultStatus === null || reasonCodes === null) {
    throw invalidReleaseResult();
  }
  if (
    resultStatus === "approved_baseline" &&
    (comparedSnapshotId !== null || releasedSnapshotId === null ||
      reasonCodes.length !== 0)
  ) {
    throw invalidReleaseResult();
  }
  if (
    resultStatus === "approved" &&
    (comparedSnapshotId === null || releasedSnapshotId === null ||
      reasonCodes.length !== 0)
  ) {
    throw invalidReleaseResult();
  }
  if (
    resultStatus === "blocked" &&
    (comparedSnapshotId === null || releasedSnapshotId !== null ||
      reasonCodes.length === 0)
  ) {
    throw invalidReleaseResult();
  }

  return {
    releaseContractId: "trusted_management_report_snapshot_release_v2",
    releaseRequestId,
    projectId,
    releaseLineageId:
      "management-report:contact_sessions_by_channel_two_periods",
    reportId: "contact_sessions_by_channel_two_periods",
    reportVersion: 1,
    queryFingerprint:
      "management-report:contact_sessions_by_channel_two_periods:v1",
    reportingTimeZoneVersionNumber,
    reportingTimeZone,
    dataCutoffUtc,
    comparedSnapshotId,
    releasedSnapshotId,
    resultStatus,
    reasonCodes,
  };
}

function serializeReleaseResult(
  result: ManagementReportReleaseResult,
): Readonly<Record<string, unknown>> {
  return {
    release_contract_id: result.releaseContractId,
    release_request_id: result.releaseRequestId,
    project_id: result.projectId,
    release_lineage_id: result.releaseLineageId,
    report_id: result.reportId,
    report_version: result.reportVersion,
    query_fingerprint: result.queryFingerprint,
    reporting_time_zone_version_number: result.reportingTimeZoneVersionNumber,
    reporting_time_zone: result.reportingTimeZone,
    data_cutoff_utc: result.dataCutoffUtc,
    compared_snapshot_id: result.comparedSnapshotId,
    released_snapshot_id: result.releasedSnapshotId,
    result_status: result.resultStatus,
    reason_codes: result.reasonCodes,
  };
}

function releaseStoreFailure(
  error: unknown,
): ManagementReportReleaseHttpResult {
  if (error instanceof ManagementReportReleaseStoreError) {
    return error.code === "forbidden"
      ? failure(403, "management_report_release_forbidden")
      : failure(409, "management_report_release_conflict");
  }
  return failure(503, "management_report_release_unavailable");
}

function mapPostgresError(error: unknown): Error {
  if (error instanceof ManagementReportReleaseStoreError) return error;
  const code = errorCode(error);
  if (code === "42501") {
    return new ManagementReportReleaseStoreError("forbidden");
  }
  if (
    code === "22023" ||
    code === "23505" ||
    code === "40001" ||
    code === "55000"
  ) {
    return new ManagementReportReleaseStoreError("conflict");
  }
  return error instanceof Error ? error : new Error(String(error));
}

function parseReleaseResultValue(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function rowField(value: unknown, name: string): unknown {
  if (!parseReleaseResultValue(value)) throw invalidReleaseResult();
  if (!(name in value)) throw invalidReleaseResult();
  return value[name];
}

function object(value: unknown): Record<string, unknown> {
  if (!parseReleaseResultValue(value)) throw invalidReleaseResult();
  return value;
}

function hasExactKeys(
  value: Record<string, unknown>,
  expected: readonly string[],
): boolean {
  const actual = Object.keys(value).sort();
  const sortedExpected = [...expected].sort();
  return actual.length === sortedExpected.length &&
    actual.every((key, index) => key === sortedExpected[index]);
}

function requireExactKeys(
  value: Record<string, unknown>,
  expected: readonly string[],
): void {
  if (!hasExactKeys(value, expected)) throw invalidReleaseResult();
}

function uuid(value: unknown): string | null {
  return typeof value === "string" && uuidPattern.test(value)
    ? value.toLowerCase()
    : null;
}

function nullableUuid(value: unknown): string | null | undefined {
  if (value === null) return null;
  const parsed = uuid(value);
  return parsed === null ? undefined : parsed;
}

function positiveInteger(value: unknown): number | null {
  return Number.isInteger(value) && Number(value) > 0 ? Number(value) : null;
}

function releaseStatus(value: unknown): ManagementReportReleaseStatus | null {
  return value === "approved_baseline" || value === "approved" ||
      value === "blocked"
    ? value
    : null;
}

function reasonCodeArray(value: unknown): readonly string[] | null {
  if (!Array.isArray(value) || value.some((item) =>
    typeof item !== "string" || !releaseReasonCodes.has(item)
  )) {
    return null;
  }
  const reasonCodes = value as string[];
  return new Set(reasonCodes).size === reasonCodes.length ? reasonCodes : null;
}

function ianaTimeZone(value: unknown): string | null {
  if (
    typeof value !== "string" ||
    value.length === 0 ||
    value.length > 100 ||
    value !== value.trim() ||
    (
      value !== "UTC" &&
      (!value.includes("/") || value.startsWith("posix/") ||
        value.startsWith("right/"))
    )
  ) {
    return null;
  }
  try {
    new Intl.DateTimeFormat("en", {timeZone: value}).format(new Date(0));
    return value;
  } catch {
    return null;
  }
}

function utcTimestamp(value: unknown): string | null {
  if (typeof value !== "string" || !rfc3339Pattern.test(value)) return null;
  const timestamp = new Date(value);
  return Number.isFinite(timestamp.getTime()) && timestamp.toISOString() === value
    ? value
    : null;
}

function errorCode(error: unknown): string {
  return typeof error === "object" && error !== null && "code" in error
    ? String(error.code)
    : "";
}

function invalidReleaseResult(): Error {
  return new Error("invalid management report release result");
}

function failure(
  status: number,
  code: string,
): ManagementReportReleaseHttpResult {
  return {status, body: {error: {code}}};
}

const releaseResultKeys = [
  "compared_snapshot_id",
  "data_cutoff_utc",
  "project_id",
  "query_fingerprint",
  "reason_codes",
  "release_contract_id",
  "release_lineage_id",
  "release_request_id",
  "released_snapshot_id",
  "report_id",
  "report_version",
  "reporting_time_zone",
  "reporting_time_zone_version_number",
  "result_status",
] as const;

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const rfc3339Pattern =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;
const releaseReasonCodes = new Set([
  "no_shared_period",
  "release_cutoff_not_advanced",
  "release_lineage_context_changed",
  "release_lineage_missing_v2_provenance",
  "release_time_zone_revision_changed",
  "shared_cell_privacy_status_changed",
  "shared_displayed_value_changed",
]);
