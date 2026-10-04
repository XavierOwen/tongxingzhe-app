import { bearerToken } from "./authorization.js";
import {
  IdentityVerificationError,
  type IdentityVerifier,
  type VerifiedIdentity,
} from "./identity.js";

const contractId = "organization-deletion-recovery-directory:v1" as const;
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const timestampPattern =
  /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?Z$/;

export interface OrganizationDeletionRecoveryDirectoryItem {
  readonly organizationWorkspaceId: string;
  readonly deletionRequestId: string;
  readonly displayName: string;
  readonly observedAtUtc: string;
  readonly effectiveAtUtc: string;
  readonly purgeAfterUtc: string;
  readonly status: "deletion_pending";
}

export interface OrganizationDeletionRecoveryDirectoryWireItem {
  readonly organization_workspace_id: string;
  readonly deletion_request_id: string;
  readonly display_name: string;
  readonly observed_at_utc: string;
  readonly effective_at_utc: string;
  readonly purge_after_utc: string;
  readonly status: "deletion_pending";
}

export interface OrganizationDeletionRecoveryDirectoryWire {
  readonly organization_deletion_recovery_directory_contract_id: typeof contractId;
  readonly items: readonly OrganizationDeletionRecoveryDirectoryWireItem[];
}

interface ParsedOrganizationDeletionRecoveryDirectoryItem
  extends OrganizationDeletionRecoveryDirectoryItem {
  readonly observedAtInstant: bigint;
}

export interface OrganizationDeletionRecoveryDirectoryStore {
  list(identity: VerifiedIdentity): Promise<readonly OrganizationDeletionRecoveryDirectoryItem[]>;
}

export interface OrganizationDeletionRecoveryDirectoryRequest {
  readonly authorization: string | undefined;
  readonly hasQuery: boolean;
  readonly hasBody: boolean;
}

export interface OrganizationDeletionRecoveryDirectoryDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly organizationDeletionRecoveryDirectoryStore?: OrganizationDeletionRecoveryDirectoryStore;
}

export interface OrganizationDeletionRecoveryDirectoryHttpResult {
  readonly status: number;
  readonly body: OrganizationDeletionRecoveryDirectoryWire | {
    readonly error: { readonly code: string };
  };
}

/** 身份验证先于请求形状检查；目录只报告 SQL 已授权的当前 owner 结果。 */
export async function listOrganizationDeletionRecoveryDirectory(
  request: OrganizationDeletionRecoveryDirectoryRequest,
  dependencies: OrganizationDeletionRecoveryDirectoryDependencies,
): Promise<OrganizationDeletionRecoveryDirectoryHttpResult> {
  const accessToken = bearerToken(request.authorization);
  if (accessToken === null) return failure(401, "unauthenticated");

  let identity: VerifiedIdentity;
  try {
    identity = await dependencies.identityVerifier.verify(accessToken);
  } catch (error) {
    if (error instanceof IdentityVerificationError && error.category === "unauthenticated") {
      return failure(401, "unauthenticated");
    }
    return failure(503, "organization_deletion_recovery_directory_unavailable");
  }

  if (request.hasQuery || request.hasBody) {
    return failure(400, "invalid_organization_deletion_recovery_directory_request");
  }
  const store = dependencies.organizationDeletionRecoveryDirectoryStore;
  if (store === undefined) {
    return failure(503, "organization_deletion_recovery_directory_unavailable");
  }

  try {
    const items = await store.list(identity);
    return {
      status: 200,
      body: {
        organization_deletion_recovery_directory_contract_id: contractId,
        items: items.map((item) => ({
          organization_workspace_id: item.organizationWorkspaceId,
          deletion_request_id: item.deletionRequestId,
          display_name: item.displayName,
          observed_at_utc: item.observedAtUtc,
          effective_at_utc: item.effectiveAtUtc,
          purge_after_utc: item.purgeAfterUtc,
          status: item.status,
        })),
      },
    };
  } catch (error) {
    if (error instanceof OrganizationDeletionRecoveryDirectoryStoreError &&
      error.code === "organization_deletion_recovery_directory_forbidden") {
      return failure(403, error.code);
    }
    return failure(503, "organization_deletion_recovery_directory_unavailable");
  }
}

export type OrganizationDeletionRecoveryDirectoryQuery = (
  text: string,
  values: readonly unknown[],
) => Promise<{ readonly rows: readonly unknown[] }>;

export class OrganizationDeletionRecoveryDirectoryStoreError extends Error {
  constructor(readonly code:
    | "organization_deletion_recovery_directory_forbidden"
    | "organization_deletion_recovery_directory_unavailable") {
    super(code);
    this.name = "OrganizationDeletionRecoveryDirectoryStoreError";
  }
}

export class PostgresOrganizationDeletionRecoveryDirectoryStore
  implements OrganizationDeletionRecoveryDirectoryStore {
  constructor(private readonly query: OrganizationDeletionRecoveryDirectoryQuery) {}

  async list(
    identity: VerifiedIdentity,
  ): Promise<readonly OrganizationDeletionRecoveryDirectoryItem[]> {
    try {
      const result = await this.query(
        `SELECT
           organization_deletion_recovery_directory_contract_id,
           to_char(observed_at_utc AT TIME ZONE 'UTC',
             'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS observed_at_utc,
           organization_workspace_id,
           deletion_request_id,
           display_name,
           to_char(effective_at_utc AT TIME ZONE 'UTC',
             'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS effective_at_utc,
           to_char(purge_after_utc AT TIME ZONE 'UTC',
             'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS purge_after_utc,
           status
         FROM app_data.list_organization_deletion_recovery_for_identity_v1($1::text, $2::text)`,
        [identity.issuer, identity.subject],
      );
      const parsedItems = result.rows.map(parseItem);
      const organizationIds = new Set<string>();
      let observedAtInstant: bigint | undefined;
      for (const item of parsedItems) {
        if (organizationIds.has(item.organizationWorkspaceId) ||
          (observedAtInstant !== undefined &&
            item.observedAtInstant !== observedAtInstant)) {
          throw invalidResult();
        }
        organizationIds.add(item.organizationWorkspaceId);
        observedAtInstant = item.observedAtInstant;
      }
      return parsedItems.map((item) => ({
        organizationWorkspaceId: item.organizationWorkspaceId,
        deletionRequestId: item.deletionRequestId,
        displayName: item.displayName,
        observedAtUtc: item.observedAtUtc,
        effectiveAtUtc: item.effectiveAtUtc,
        purgeAfterUtc: item.purgeAfterUtc,
        status: item.status,
      }));
    } catch (error) {
      throw mapStoreError(error);
    }
  }
}

function parseItem(value: unknown): ParsedOrganizationDeletionRecoveryDirectoryItem {
  const row = object(value);
  if (row === null || !hasExactKeys(row, [
    "organization_deletion_recovery_directory_contract_id",
    "observed_at_utc",
    "organization_workspace_id",
    "deletion_request_id",
    "display_name",
    "effective_at_utc",
    "purge_after_utc",
    "status",
  ]) || row.organization_deletion_recovery_directory_contract_id !== contractId ||
    row.status !== "deletion_pending") {
    throw invalidResult();
  }
  const organizationWorkspaceId = uuid(row.organization_workspace_id);
  const deletionRequestId = uuid(row.deletion_request_id);
  const observedAt = utcTimestamp(row.observed_at_utc);
  const effectiveAt = utcTimestamp(row.effective_at_utc);
  const purgeAfter = utcTimestamp(row.purge_after_utc);
  if (organizationWorkspaceId === null || deletionRequestId === null ||
    observedAt === null || effectiveAt === null || purgeAfter === null ||
    typeof row.display_name !== "string" || row.display_name.trim().length === 0 ||
    effectiveAt.instant >= purgeAfter.instant ||
    observedAt.instant < effectiveAt.instant ||
    observedAt.instant >= purgeAfter.instant) {
    throw invalidResult();
  }
  return {
    organizationWorkspaceId,
    deletionRequestId,
    displayName: row.display_name,
    observedAtUtc: observedAt.wire,
    effectiveAtUtc: effectiveAt.wire,
    purgeAfterUtc: purgeAfter.wire,
    status: "deletion_pending",
    observedAtInstant: observedAt.instant,
  };
}

function mapStoreError(error: unknown): OrganizationDeletionRecoveryDirectoryStoreError {
  if (error instanceof OrganizationDeletionRecoveryDirectoryStoreError) return error;
  const code = propertyString(error, "code");
  const message = propertyString(error, "message");
  if (code === "42501" && message === "organization deletion recovery directory forbidden") {
    return new OrganizationDeletionRecoveryDirectoryStoreError(
      "organization_deletion_recovery_directory_forbidden",
    );
  }
  return new OrganizationDeletionRecoveryDirectoryStoreError(
    "organization_deletion_recovery_directory_unavailable",
  );
}

function object(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function hasExactKeys(value: Record<string, unknown>, expected: readonly string[]): boolean {
  const actual = Object.keys(value);
  return actual.length === expected.length && expected.every((key) => Object.hasOwn(value, key));
}

function uuid(value: unknown): string | null {
  return typeof value === "string" && uuidPattern.test(value) ? value : null;
}

function utcTimestamp(value: unknown): { readonly wire: string; readonly instant: bigint } | null {
  let candidate: string;
  if (value instanceof Date) {
    if (!Number.isFinite(value.getTime())) return null;
    candidate = value.toISOString();
  } else if (typeof value === "string") {
    candidate = value;
  } else {
    return null;
  }
  const match = timestampPattern.exec(candidate);
  if (match === null) return null;
  const [year, month, day, hour, minute, second] = match.slice(1, 7).map(Number);
  const fraction = (match[7] ?? "").padEnd(6, "0");
  const timestamp = new Date(0);
  timestamp.setUTCFullYear(year!, month! - 1, day!);
  timestamp.setUTCHours(hour!, minute!, second!, 0);
  if (!Number.isFinite(timestamp.getTime()) ||
    timestamp.getUTCFullYear() !== year || timestamp.getUTCMonth() !== month! - 1 ||
    timestamp.getUTCDate() !== day || timestamp.getUTCHours() !== hour ||
    timestamp.getUTCMinutes() !== minute || timestamp.getUTCSeconds() !== second) {
    return null;
  }
  const epochSecond = BigInt(Math.floor(timestamp.getTime() / 1000));
  return {
    wire: candidate,
    instant: epochSecond * 1_000_000n + BigInt(fraction),
  };
}

function propertyString(value: unknown, property: string): string | null {
  if (typeof value !== "object" || value === null) return null;
  const candidate = (value as Record<string, unknown>)[property];
  return typeof candidate === "string" ? candidate : null;
}

function invalidResult(): Error {
  return new Error("invalid organization deletion recovery directory result");
}

function failure(status: number, code: string): OrganizationDeletionRecoveryDirectoryHttpResult {
  return { status, body: { error: { code } } };
}
