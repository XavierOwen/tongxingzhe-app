import {bearerToken} from "./authorization.js";
import {
  IdentityVerificationError,
  type IdentityVerifier,
  type VerifiedIdentity,
} from "./identity.js";

export type ManagementReportSnapshotRead = {
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

export interface ManagementReportSnapshotStore {
  read(
    identity: VerifiedIdentity,
    projectId: string,
    snapshotId: string,
  ): Promise<ManagementReportSnapshotRead>;
}

export interface ManagementReportSnapshotDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly snapshotStore: ManagementReportSnapshotStore;
}

export interface ManagementReportSnapshotHttpResult {
  readonly status: number;
  readonly body: Readonly<Record<string, unknown>>;
}

export async function readManagementReportSnapshot(
  authorization: string | undefined,
  projectId: string,
  snapshotId: string,
  dependencies: ManagementReportSnapshotDependencies,
): Promise<ManagementReportSnapshotHttpResult> {
  const accessToken = bearerToken(authorization);
  if (accessToken === null) return failure(401, "unauthenticated");
  if (!uuidPattern.test(projectId) || !uuidPattern.test(snapshotId)) {
    return failure(400, "invalid_management_report_snapshot_request");
  }

  try {
    const identity = await dependencies.identityVerifier.verify(accessToken);
    const result = await dependencies.snapshotStore.read(
      identity,
      projectId,
      snapshotId,
    );
    if (result.status === "completed") {
      assertNoExactLocationFacts(result.protectedReport);
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
        "management_report_snapshot_not_found",
        result.accessEventId,
      );
    }
    return auditedFailure(
      409,
      "management_report_snapshot_untrusted",
      result.accessEventId,
    );
  } catch (error) {
    if (error instanceof IdentityVerificationError) {
      return failure(401, "unauthenticated");
    }
    if (
      error instanceof ManagementReportSnapshotStoreError &&
      error.code === "forbidden"
    ) {
      return failure(403, "management_report_snapshot_forbidden");
    }
    return failure(503, "management_report_snapshot_unavailable");
  }
}

export type ManagementReportSnapshotQuery = (
  text: string,
  values: readonly unknown[],
) => Promise<{readonly rows: readonly unknown[]}>;

export class PostgresManagementReportSnapshotStore
implements ManagementReportSnapshotStore {
  constructor(private readonly query: ManagementReportSnapshotQuery) {}

  async read(
    identity: VerifiedIdentity,
    projectId: string,
    snapshotId: string,
  ): Promise<ManagementReportSnapshotRead> {
    try {
      const result = await this.query(
        `SELECT app_data.read_authorized_management_report_snapshot_v1(
           $1::text, $2::text, $3::uuid, $4::uuid
         ) AS access_result`,
        [identity.issuer, identity.subject, projectId, snapshotId],
      );
      if (result.rows.length !== 1) {
        throw invalidAccessResult();
      }
      return parseAccessResult(
        rowField(result.rows[0], "access_result"),
        snapshotId,
      );
    } catch (error) {
      throw mapPostgresError(error);
    }
  }
}

export class ManagementReportSnapshotStoreError extends Error {
  constructor(readonly code: "forbidden") {
    super(code);
    this.name = "ManagementReportSnapshotStoreError";
  }
}

function parseAccessResult(
  value: unknown,
  expectedSnapshotId: string,
): ManagementReportSnapshotRead {
  const root = object(value);
  const status = root.result_status;
  const accessEventId = uuid(root.access_event_id);
  const requestedSnapshotId = uuid(root.requested_snapshot_id);
  if (
    root.access_contract_id !==
      "authorized_management_report_snapshot_read_v1" ||
    requestedSnapshotId !== expectedSnapshotId
  ) {
    throw invalidAccessResult();
  }

  if (status === "completed") {
    requireExactKeys(root, [...commonKeys, "protected_report"]);
    const resolvedSnapshotId = uuid(root.resolved_snapshot_id);
    if (
      resolvedSnapshotId !== expectedSnapshotId ||
      root.reason_code !== null
    ) {
      throw invalidAccessResult();
    }
    return {
      status,
      accessEventId,
      requestedSnapshotId,
      resolvedSnapshotId,
      protectedReport: object(root.protected_report),
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
    if (resolvedSnapshotId !== expectedSnapshotId) {
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

const commonKeys = [
  "access_contract_id",
  "access_event_id",
  "reason_code",
  "requested_snapshot_id",
  "resolved_snapshot_id",
  "result_status",
];

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
    throw invalidAccessResult();
  }
}

const exactLocationFactKeys = new Set([
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

function mapPostgresError(error: unknown): Error {
  const code = typeof error === "object" && error !== null && "code" in error
    ? String(error.code)
    : "";
  if (code === "42501") {
    return new ManagementReportSnapshotStoreError("forbidden");
  }
  return error instanceof Error ? error : new Error(String(error));
}

function failure(
  status: number,
  code: string,
): ManagementReportSnapshotHttpResult {
  return {status, body: {error: {code}}};
}

function auditedFailure(
  status: number,
  code: string,
  accessEventId: string,
): ManagementReportSnapshotHttpResult {
  return {
    status,
    body: {error: {code, access_event_id: accessEventId}},
  };
}

function invalidAccessResult(): Error {
  return new Error("invalid management report snapshot access result");
}

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
