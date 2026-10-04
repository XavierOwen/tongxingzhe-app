import { bearerToken } from "./authorization.js";
import {
  IdentityVerificationError,
  type IdentityVerifier,
  type VerifiedIdentity,
} from "./identity.js";

const deletionContractId = "organization-deletion-request:v1" as const;
const restorationContractId = "organization-deletion-restore:v1" as const;
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const utcMicrosecondTimestampPattern =
  /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})\.(\d{6})Z$/;

export interface OrganizationDeletionLifecycleRequest {
  readonly authorization: string | undefined;
  readonly workspaceId: string;
  readonly hasQuery: boolean;
  readonly operation: "request" | "restore";
  readonly readBody: () => Promise<unknown>;
}

export interface OrganizationDeletionLifecycleDependencies {
  readonly identityVerifier: IdentityVerifier | undefined;
  readonly store: OrganizationDeletionLifecycleStore | undefined;
}

export interface OrganizationDeletionRequestReceipt {
  readonly organizationDeletionContractId: typeof deletionContractId;
  readonly organizationWorkspaceId: string;
  readonly deletionRequestId: string;
  readonly effectiveAtUtc: string;
  readonly purgeAfterUtc: string;
}

export interface OrganizationDeletionRestoreReceipt {
  readonly organizationDeletionRestoreContractId: typeof restorationContractId;
  readonly organizationWorkspaceId: string;
  readonly deletionRequestId: string;
  readonly restoredAtUtc: string;
}

export interface OrganizationDeletionLifecycleStore {
  requestDeletion(
    identity: VerifiedIdentity,
    requestId: string,
    organizationWorkspaceId: string,
  ): Promise<OrganizationDeletionRequestReceipt>;
  restore(
    identity: VerifiedIdentity,
    requestId: string,
    organizationWorkspaceId: string,
    deletionRequestId: string,
  ): Promise<OrganizationDeletionRestoreReceipt>;
}

export type OrganizationDeletionLifecycleQuery = (
  text: string,
  values: readonly unknown[],
) => Promise<{ readonly rows: readonly unknown[] }>;

export type OrganizationDeletionLifecycleErrorCode =
  | "invalid_organization_deletion_request"
  | "organization_deletion_forbidden"
  | "organization_deletion_conflict"
  | "organization_deletion_unavailable"
  | "invalid_organization_restoration_request"
  | "organization_restoration_forbidden"
  | "organization_restoration_conflict"
  | "organization_restoration_unavailable";

export class OrganizationDeletionLifecycleStoreError extends Error {
  constructor(readonly code: OrganizationDeletionLifecycleErrorCode) {
    super(code);
    this.name = "OrganizationDeletionLifecycleStoreError";
  }
}

export interface OrganizationDeletionLifecycleHttpResult {
  readonly status: number;
  readonly body: Readonly<Record<string, unknown>>;
}

export interface OrganizationDeletionLifecycleRouteMatch {
  readonly workspaceId: string;
  readonly hasQuery: boolean;
  readonly operation: "request" | "restore";
}

export function matchOrganizationDeletionLifecycleRequestTarget(
  requestTarget: string | undefined,
): OrganizationDeletionLifecycleRouteMatch | null {
  if (requestTarget === undefined) return null;

  const queryIndex = requestTarget.indexOf("?");
  const pathname = queryIndex < 0
    ? requestTarget
    : requestTarget.slice(0, queryIndex);
  if (pathname.includes("%")) return null;

  const match =
    /^\/v1\/organizations\/([^/]+)\/(deletion-requests|restorations)$/.exec(
      pathname,
    );
  const workspaceId = match?.[1];
  if (
    workspaceId === undefined || workspaceId === "." || workspaceId === ".."
  ) {
    return null;
  }

  return {
    workspaceId,
    hasQuery: queryIndex >= 0,
    operation: match?.[2] === "restorations" ? "restore" : "request",
  };
}

export async function handleOrganizationDeletionLifecycle(
  request: OrganizationDeletionLifecycleRequest,
  dependencies: OrganizationDeletionLifecycleDependencies,
): Promise<OrganizationDeletionLifecycleHttpResult> {
  const code = request.operation === "request"
    ? "organization_deletion_unavailable"
    : "organization_restoration_unavailable";
  const accessToken = bearerToken(request.authorization);
  if (accessToken === null) return failure(401, "unauthenticated");
  if (dependencies.identityVerifier === undefined) return failure(503, code);

  let identity: VerifiedIdentity;
  try {
    identity = await dependencies.identityVerifier.verify(accessToken);
  } catch (error) {
    if (error instanceof IdentityVerificationError) {
      return error.category === "unauthenticated"
        ? failure(401, "unauthenticated")
        : failure(503, code);
    }
    return failure(503, code);
  }

  const invalidCode = request.operation === "request"
    ? "invalid_organization_deletion_request"
    : "invalid_organization_restoration_request";
  if (request.hasQuery) return failure(400, invalidCode);

  const organizationWorkspaceId = uuid(request.workspaceId);
  if (organizationWorkspaceId === null) return failure(400, invalidCode);
  if (dependencies.store === undefined) return failure(503, code);

  const input = parseBody(request.operation, await request.readBody());
  if (input === null) return failure(400, invalidCode);

  try {
    const result = request.operation === "request"
      ? await dependencies.store.requestDeletion(
        identity,
        input.requestId,
        organizationWorkspaceId,
      )
      : await dependencies.store.restore(
        identity,
        input.requestId,
        organizationWorkspaceId,
        input.deletionRequestId!,
      );
    return success(request.operation, result);
  } catch (error) {
    return storeFailure(request.operation, error);
  }
}

export function parseOrganizationDeletionLifecycleBody(
  operation: "request" | "restore",
  value: unknown,
): { readonly requestId: string; readonly deletionRequestId?: string } | null {
  return parseBody(operation, value);
}

export class PostgresOrganizationDeletionLifecycleStore
  implements OrganizationDeletionLifecycleStore
{
  constructor(private readonly query: OrganizationDeletionLifecycleQuery) {}

  async requestDeletion(
    identity: VerifiedIdentity,
    requestId: string,
    organizationWorkspaceId: string,
  ): Promise<OrganizationDeletionRequestReceipt> {
    try {
      const result = await this.query(
        `SELECT organization_deletion_contract_id,
           organization_workspace_id,
           deletion_request_id,
           to_char(effective_at_utc AT TIME ZONE 'UTC',
             'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS effective_at_utc,
           to_char(purge_after_utc AT TIME ZONE 'UTC',
             'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS purge_after_utc
         FROM app_data.request_organization_deletion_for_identity_v1(
           $1::text, $2::text, $3::uuid, $4::uuid
         )`,
        [identity.issuer, identity.subject, requestId, organizationWorkspaceId],
      );
      if (result.rows.length !== 1) {
        throw new Error("invalid organization deletion request result");
      }
      return parseRequestReceipt(
        result.rows[0],
        organizationWorkspaceId,
        requestId,
      );
    } catch (error) {
      throw mapStoreError("request", error);
    }
  }

  async restore(
    identity: VerifiedIdentity,
    requestId: string,
    organizationWorkspaceId: string,
    deletionRequestId: string,
  ): Promise<OrganizationDeletionRestoreReceipt> {
    try {
      const result = await this.query(
        `SELECT organization_deletion_restore_contract_id,
           organization_workspace_id,
           deletion_request_id,
           to_char(restored_at_utc AT TIME ZONE 'UTC',
             'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS restored_at_utc
         FROM app_data.restore_organization_for_identity_v1(
           $1::text, $2::text, $3::uuid, $4::uuid, $5::uuid
         )`,
        [
          identity.issuer,
          identity.subject,
          requestId,
          organizationWorkspaceId,
          deletionRequestId,
        ],
      );
      if (result.rows.length !== 1) {
        throw new Error("invalid organization restoration result");
      }
      return parseRestoreReceipt(
        result.rows[0],
        organizationWorkspaceId,
        deletionRequestId,
      );
    } catch (error) {
      throw mapStoreError("restore", error);
    }
  }
}

function parseBody(
  operation: "request" | "restore",
  value: unknown,
): { readonly requestId: string; readonly deletionRequestId?: string } | null {
  const body = object(value);
  const keys = operation === "request"
    ? ["request_id"]
    : ["deletion_request_id", "request_id"];
  if (body === null || !hasExactKeys(body, keys)) return null;

  const requestId = uuid(body.request_id);
  const deletionRequestId = operation === "restore"
    ? uuid(body.deletion_request_id)
    : undefined;
  if (requestId === null || (operation === "restore" && deletionRequestId === null)) {
    return null;
  }
  return operation === "restore"
    ? {requestId, deletionRequestId: deletionRequestId!}
    : {requestId};
}

function parseRequestReceipt(
  value: unknown,
  expectedWorkspaceId: string,
  expectedDeletionRequestId: string,
): OrganizationDeletionRequestReceipt {
  const row = object(value);
  if (
    row === null || !hasExactKeys(row, [
      "deletion_request_id",
      "effective_at_utc",
      "organization_deletion_contract_id",
      "organization_workspace_id",
      "purge_after_utc",
    ]) || row.organization_deletion_contract_id !== deletionContractId
  ) {
    throw new Error("invalid organization deletion request result");
  }

  const workspaceId = uuid(row.organization_workspace_id);
  const deletionRequestId = uuid(row.deletion_request_id);
  const effectiveAtUtc = utcMicrosecondTimestamp(row.effective_at_utc);
  const purgeAfterUtc = utcMicrosecondTimestamp(row.purge_after_utc);
  if (
    workspaceId === null || workspaceId !== uuid(expectedWorkspaceId) ||
    deletionRequestId === null ||
    deletionRequestId !== uuid(expectedDeletionRequestId) ||
    effectiveAtUtc === null || purgeAfterUtc === null
  ) {
    throw new Error("invalid organization deletion request result");
  }

  return {
    organizationDeletionContractId: deletionContractId,
    organizationWorkspaceId: workspaceId,
    deletionRequestId,
    effectiveAtUtc,
    purgeAfterUtc,
  };
}

function parseRestoreReceipt(
  value: unknown,
  expectedWorkspaceId: string,
  expectedDeletionRequestId: string,
): OrganizationDeletionRestoreReceipt {
  const row = object(value);
  if (
    row === null || !hasExactKeys(row, [
      "deletion_request_id",
      "organization_deletion_restore_contract_id",
      "organization_workspace_id",
      "restored_at_utc",
    ]) || row.organization_deletion_restore_contract_id !== restorationContractId
  ) {
    throw new Error("invalid organization restoration result");
  }

  const workspaceId = uuid(row.organization_workspace_id);
  const deletionRequestId = uuid(row.deletion_request_id);
  const restoredAtUtc = utcMicrosecondTimestamp(row.restored_at_utc);
  if (
    workspaceId === null || workspaceId !== uuid(expectedWorkspaceId) ||
    deletionRequestId === null ||
    deletionRequestId !== uuid(expectedDeletionRequestId) ||
    restoredAtUtc === null
  ) {
    throw new Error("invalid organization restoration result");
  }

  return {
    organizationDeletionRestoreContractId: restorationContractId,
    organizationWorkspaceId: workspaceId,
    deletionRequestId,
    restoredAtUtc,
  };
}

function mapStoreError(
  operation: "request" | "restore",
  error: unknown,
): OrganizationDeletionLifecycleStoreError {
  if (error instanceof OrganizationDeletionLifecycleStoreError) return error;
  const code = propertyString(error, "code");
  const message = propertyString(error, "message");
  const prefix = operation === "request"
    ? "organization deletion"
    : "organization restoration";
  if (code === "22023" && message === `invalid ${prefix} request`) {
    return new OrganizationDeletionLifecycleStoreError(
      operation === "request"
        ? "invalid_organization_deletion_request"
        : "invalid_organization_restoration_request",
    );
  }
  if (code === "42501" && message === `${prefix} forbidden`) {
    return new OrganizationDeletionLifecycleStoreError(
      operation === "request"
        ? "organization_deletion_forbidden"
        : "organization_restoration_forbidden",
    );
  }
  if (
    code === "22023" && message === `${prefix} idempotency conflict`
  ) {
    return new OrganizationDeletionLifecycleStoreError(
      operation === "request"
        ? "organization_deletion_conflict"
        : "organization_restoration_conflict",
    );
  }
  return new OrganizationDeletionLifecycleStoreError(
    operation === "request"
      ? "organization_deletion_unavailable"
      : "organization_restoration_unavailable",
  );
}

function storeFailure(
  operation: "request" | "restore",
  error: unknown,
): OrganizationDeletionLifecycleHttpResult {
  const unavailableCode = operation === "request"
    ? "organization_deletion_unavailable"
    : "organization_restoration_unavailable";
  const storeError = error instanceof OrganizationDeletionLifecycleStoreError
    ? error
    : new OrganizationDeletionLifecycleStoreError(unavailableCode);
  switch (storeError.code) {
    case "invalid_organization_deletion_request":
    case "invalid_organization_restoration_request":
      return failure(400, storeError.code);
    case "organization_deletion_forbidden":
    case "organization_restoration_forbidden":
      return failure(403, storeError.code);
    case "organization_deletion_conflict":
    case "organization_restoration_conflict":
      return failure(409, storeError.code);
    case "organization_deletion_unavailable":
    case "organization_restoration_unavailable":
      return failure(503, storeError.code);
  }
}

function success(
  operation: "request" | "restore",
  result: OrganizationDeletionRequestReceipt | OrganizationDeletionRestoreReceipt,
): OrganizationDeletionLifecycleHttpResult {
  if (operation === "request") {
    const receipt = result as OrganizationDeletionRequestReceipt;
    return {
      status: 200,
      body: {
        organization_deletion_contract_id: receipt.organizationDeletionContractId,
        organization_workspace_id: receipt.organizationWorkspaceId,
        deletion_request_id: receipt.deletionRequestId,
        effective_at_utc: receipt.effectiveAtUtc,
        purge_after_utc: receipt.purgeAfterUtc,
      },
    };
  }
  const receipt = result as OrganizationDeletionRestoreReceipt;
  return {
    status: 200,
    body: {
      organization_deletion_restore_contract_id:
        receipt.organizationDeletionRestoreContractId,
      organization_workspace_id: receipt.organizationWorkspaceId,
      deletion_request_id: receipt.deletionRequestId,
      restored_at_utc: receipt.restoredAtUtc,
    },
  };
}

function failure(
  status: number,
  code: string,
): OrganizationDeletionLifecycleHttpResult {
  return {status, body: {error: {code}}};
}

function object(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
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

function uuid(value: unknown): string | null {
  return typeof value === "string" && uuidPattern.test(value)
    ? value.toLowerCase()
    : null;
}

function utcMicrosecondTimestamp(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const match = utcMicrosecondTimestampPattern.exec(value);
  if (match === null) return null;
  const [year, month, day, hour, minute, second, micros] = match.slice(1)
    .map(Number);
  if (
    year === undefined || month === undefined || day === undefined ||
    hour === undefined || minute === undefined || second === undefined ||
    micros === undefined || year < 1 || month < 1 || month > 12 ||
    hour > 23 || minute > 59 || second > 59
  ) return null;
  const milliseconds = Math.floor(micros / 1000);
  const date = new Date(Date.UTC(year, month - 1, day, hour, minute, second, milliseconds));
  if (
    date.getUTCFullYear() !== year || date.getUTCMonth() + 1 !== month ||
    date.getUTCDate() !== day || date.getUTCHours() !== hour ||
    date.getUTCMinutes() !== minute || date.getUTCSeconds() !== second ||
    date.getUTCMilliseconds() !== milliseconds
  ) return null;
  return value;
}

function propertyString(value: unknown, key: string): string | null {
  const record = object(value);
  const property = record?.[key];
  return typeof property === "string" ? property : null;
}
