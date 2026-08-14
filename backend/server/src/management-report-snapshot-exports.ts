import {bearerToken} from "./authorization.js";
import {
  IdentityVerificationError,
  type IdentityVerifier,
  type VerifiedIdentity,
} from "./identity.js";
import {
  serializeManagementReportSnapshotExport,
} from "./management-report-export-contract.js";

export type ManagementReportSnapshotExport = {
  readonly status: "completed";
  readonly exportEventId: string;
  readonly requestedSnapshotId: string;
  readonly resolvedSnapshotId: string;
  readonly content: string;
} | {
  readonly status: "not_found";
  readonly exportEventId: string;
  readonly requestedSnapshotId: string;
  readonly resolvedSnapshotId: null;
} | {
  readonly status: "untrusted_provenance";
  readonly exportEventId: string;
  readonly requestedSnapshotId: string;
  readonly resolvedSnapshotId: string;
};

export interface ManagementReportSnapshotExportStore {
  export(
    identity: VerifiedIdentity,
    projectId: string,
    snapshotId: string,
  ): Promise<ManagementReportSnapshotExport>;
}

export interface ManagementReportSnapshotExportRequest {
  readonly authorization: string | undefined;
  readonly projectId: string;
  readonly snapshotId: string;
  readonly hasQuery: boolean;
  readonly hasBody: boolean;
}

export interface ManagementReportSnapshotExportDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly exportStore?: ManagementReportSnapshotExportStore;
}

export type ManagementReportSnapshotExportHttpResult = {
  readonly status: 200;
  readonly exportEventId: string;
  readonly content: string;
} | {
  readonly status: number;
  readonly body: Readonly<Record<string, unknown>>;
};

export async function exportManagementReportSnapshot(
  request: ManagementReportSnapshotExportRequest,
  dependencies: ManagementReportSnapshotExportDependencies,
): Promise<ManagementReportSnapshotExportHttpResult> {
  const accessToken = bearerToken(request.authorization);
  if (accessToken === null) return failure(401, "unauthenticated");

  let identity: VerifiedIdentity;
  try {
    identity = await dependencies.identityVerifier.verify(accessToken);
  } catch (error) {
    return error instanceof IdentityVerificationError
      ? failure(401, "unauthenticated")
      : failure(503, "management_report_snapshot_export_unavailable");
  }

  if (
    !uuidPattern.test(request.projectId) ||
    !uuidPattern.test(request.snapshotId) ||
    request.hasQuery ||
    request.hasBody
  ) {
    return failure(400, "invalid_management_report_snapshot_export_request");
  }
  if (dependencies.exportStore === undefined) {
    return failure(503, "management_report_snapshot_export_unavailable");
  }

  try {
    const result = await dependencies.exportStore.export(
      identity,
      request.projectId,
      request.snapshotId,
    );
    if (result.status === "completed") {
      return {
        status: 200,
        exportEventId: result.exportEventId,
        content: result.content,
      };
    }
    if (result.status === "not_found") {
      return auditedFailure(
        404,
        "management_report_snapshot_export_not_found",
        result.exportEventId,
      );
    }
    return auditedFailure(
      409,
      "management_report_snapshot_export_untrusted",
      result.exportEventId,
    );
  } catch (error) {
    if (
      error instanceof ManagementReportSnapshotExportStoreError &&
      error.code === "forbidden"
    ) {
      return failure(403, "management_report_snapshot_export_forbidden");
    }
    return failure(503, "management_report_snapshot_export_unavailable");
  }
}

export type ManagementReportSnapshotExportQuery = (
  text: string,
  values: readonly unknown[],
) => Promise<{readonly rows: readonly unknown[]}>;

export class PostgresManagementReportSnapshotExportStore
implements ManagementReportSnapshotExportStore {
  constructor(private readonly query: ManagementReportSnapshotExportQuery) {}

  async export(
    identity: VerifiedIdentity,
    projectId: string,
    snapshotId: string,
  ): Promise<ManagementReportSnapshotExport> {
    try {
      const result = await this.query(
        `SELECT app_data.export_authorized_management_report_snapshot_v1(
           $1::text, $2::text, $3::uuid, $4::uuid
         ) AS export_result`,
        [identity.issuer, identity.subject, projectId, snapshotId],
      );
      if (result.rows.length !== 1) throw invalidExportResult();
      return parseExportResult(
        rowField(result.rows[0], "export_result"),
        projectId,
        snapshotId,
      );
    } catch (error) {
      throw mapPostgresError(error);
    }
  }
}

export class ManagementReportSnapshotExportStoreError extends Error {
  constructor(readonly code: "forbidden") {
    super(code);
    this.name = "ManagementReportSnapshotExportStoreError";
  }
}

function parseExportResult(
  value: unknown,
  expectedProjectId: string,
  expectedSnapshotId: string,
): ManagementReportSnapshotExport {
  const root = object(value);
  const commonKeys = [
    "export_access_contract_id",
    "export_event_id",
    "requested_snapshot_id",
    "resolved_snapshot_id",
    "result_status",
    "reason_code",
  ];
  if (
    root.export_access_contract_id !==
      "authorized_management_report_snapshot_export_v1" ||
    uuid(root.requested_snapshot_id) !== expectedSnapshotId.toLowerCase()
  ) {
    throw invalidExportResult();
  }

  const exportEventId = uuid(root.export_event_id);
  const resultStatus = root.result_status;
  if (resultStatus === "completed") {
    requireExactKeys(root, [...commonKeys, "export_document"]);
    const resolvedSnapshotId = uuid(root.resolved_snapshot_id);
    const exportDocument = object(root.export_document);
    const report = object(exportDocument.report);
    if (
      root.reason_code !== null ||
      resolvedSnapshotId !== expectedSnapshotId.toLowerCase() ||
      exportDocument.snapshot_id !== resolvedSnapshotId ||
      report.project_id !== expectedProjectId.toLowerCase()
    ) {
      throw invalidExportResult();
    }
    return {
      status: resultStatus,
      exportEventId,
      requestedSnapshotId: expectedSnapshotId.toLowerCase(),
      resolvedSnapshotId,
      content: serializeManagementReportSnapshotExport(exportDocument),
    };
  }

  requireExactKeys(root, commonKeys);
  if (
    resultStatus === "not_found" &&
    root.reason_code === "snapshot_not_available" &&
    root.resolved_snapshot_id === null
  ) {
    return {
      status: resultStatus,
      exportEventId,
      requestedSnapshotId: expectedSnapshotId.toLowerCase(),
      resolvedSnapshotId: null,
    };
  }
  if (
    resultStatus === "untrusted_provenance" &&
    root.reason_code === "snapshot_provenance_untrusted"
  ) {
    const resolvedSnapshotId = uuid(root.resolved_snapshot_id);
    if (resolvedSnapshotId !== expectedSnapshotId.toLowerCase()) {
      throw invalidExportResult();
    }
    return {
      status: resultStatus,
      exportEventId,
      requestedSnapshotId: expectedSnapshotId.toLowerCase(),
      resolvedSnapshotId,
    };
  }
  throw invalidExportResult();
}

function rowField(value: unknown, name: string): unknown {
  const row = object(value);
  if (!(name in row)) throw invalidExportResult();
  return row[name];
}

function object(value: unknown): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw invalidExportResult();
  }
  return value as Record<string, unknown>;
}

function uuid(value: unknown): string {
  if (typeof value !== "string" || !uuidPattern.test(value)) {
    throw invalidExportResult();
  }
  return value.toLowerCase();
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
    throw invalidExportResult();
  }
}

function mapPostgresError(error: unknown): Error {
  const code = typeof error === "object" && error !== null && "code" in error
    ? String(error.code)
    : "";
  if (code === "42501") {
    return new ManagementReportSnapshotExportStoreError("forbidden");
  }
  return error instanceof Error ? error : new Error(String(error));
}

function failure(status: number, code: string) {
  return {status, body: {error: {code}}};
}

function auditedFailure(status: number, code: string, exportEventId: string) {
  return {
    status,
    body: {error: {code, export_event_id: exportEventId}},
  };
}

function invalidExportResult(): Error {
  return new Error("invalid management report snapshot export result");
}

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
