import { bearerToken } from "./authorization.js";
import {
  IdentityVerificationError,
  type IdentityVerifier,
  type VerifiedIdentity,
} from "./identity.js";

const ownerTransferContractId = "organization-owner-transfer:v1" as const;
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const timestampPattern =
  /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(Z|[+-]\d{2}:\d{2})$/;

export interface OrganizationOwnerTransferRequest {
  readonly authorization: string | undefined;
  readonly workspaceId: string;
  readonly hasQuery: boolean;
  readonly readBody: () => Promise<unknown>;
}

export interface OrganizationOwnerTransferDependencies {
  readonly identityVerifier: IdentityVerifier | undefined;
  readonly transferStore: OrganizationOwnerTransferStore | undefined;
}

export interface OrganizationOwnerTransferInput {
  readonly requestId: string;
  readonly targetOrganizationMembershipId: string;
}

export interface OrganizationOwnerTransferResult {
  readonly ownerTransferContractId: typeof ownerTransferContractId;
  readonly organizationWorkspaceId: string;
  readonly previousOwnerAssignmentId: string;
  readonly organizationOwnerAssignmentId: string;
  readonly effectiveAtUtc: string;
}

export interface OrganizationOwnerTransferStore {
  transfer(
    identity: VerifiedIdentity,
    requestId: string,
    organizationWorkspaceId: string,
    targetOrganizationMembershipId: string,
  ): Promise<OrganizationOwnerTransferResult>;
}

export type OrganizationOwnerTransferQuery = (
  text: string,
  values: readonly unknown[],
) => Promise<{ readonly rows: readonly unknown[] }>;

export type OrganizationOwnerTransferStoreErrorCode =
  | "organization_owner_transfer_unavailable"
  | "invalid_organization_owner_transfer_request"
  | "organization_owner_transfer_forbidden"
  | "organization_owner_transfer_conflict"
  | "organization_owner_transfer_target_already_owner";

export class OrganizationOwnerTransferStoreError extends Error {
  readonly code: OrganizationOwnerTransferStoreErrorCode;

  constructor(code: OrganizationOwnerTransferStoreErrorCode) {
    super(code);
    this.name = "OrganizationOwnerTransferStoreError";
    this.code = code;
  }
}

export interface OrganizationOwnerTransferHttpResult {
  readonly status: number;
  readonly body: Readonly<Record<string, unknown>>;
}

export interface OrganizationOwnerTransferRouteMatch {
  readonly workspaceId: string;
  readonly hasQuery: boolean;
}

/**
 * Match the raw request-target before a WHATWG URL can normalize it.
 * The server still owns the method check; this helper only recognizes the
 * operation-specific path and preserves the query-presence bit.
 */
export function matchOrganizationOwnerTransferRequestTarget(
  requestTarget: string | undefined,
): OrganizationOwnerTransferRouteMatch | null {
  if (requestTarget === undefined) {
    return null;
  }

  const queryIndex = requestTarget.indexOf("?");
  const pathname = queryIndex < 0
    ? requestTarget
    : requestTarget.slice(0, queryIndex);
  if (pathname.includes("%")) {
    return null;
  }

  const match =
    /^\/v1\/organizations\/([^/]+)\/owner-transfer$/.exec(pathname);
  const workspaceId = match?.[1];
  if (workspaceId === undefined || workspaceId === "." || workspaceId === "..") {
    return null;
  }

  return { workspaceId, hasQuery: queryIndex >= 0 };
}

export async function handleOrganizationOwnerTransfer(
  request: OrganizationOwnerTransferRequest,
  dependencies: OrganizationOwnerTransferDependencies,
): Promise<OrganizationOwnerTransferHttpResult> {
  const accessToken = bearerToken(request.authorization);
  if (accessToken === null) {
    return failure(401, "unauthenticated");
  }

  if (dependencies.identityVerifier === undefined) {
    return failure(503, "organization_owner_transfer_unavailable");
  }

  let identity: VerifiedIdentity;
  try {
    identity = await dependencies.identityVerifier.verify(accessToken);
  } catch (error) {
    if (error instanceof IdentityVerificationError) {
      return identityFailure(error.category);
    }
    return failure(503, "organization_owner_transfer_unavailable");
  }

  if (request.hasQuery) {
    return failure(400, "invalid_organization_owner_transfer_request");
  }

  const organizationWorkspaceId = uuid(request.workspaceId);
  if (organizationWorkspaceId === null) {
    return failure(400, "invalid_organization_owner_transfer_request");
  }

  if (dependencies.transferStore === undefined) {
    return failure(503, "organization_owner_transfer_unavailable");
  }

  const body = await request.readBody();
  const input = parseOrganizationOwnerTransferBody(body);
  if (input === null) {
    return failure(400, "invalid_organization_owner_transfer_request");
  }

  try {
    const result = await dependencies.transferStore.transfer(
      identity,
      input.requestId,
      organizationWorkspaceId,
      input.targetOrganizationMembershipId,
    );
    return success(result);
  } catch (error) {
    return storeFailure(error);
  }
}

export function parseOrganizationOwnerTransferBody(
  value: unknown,
): OrganizationOwnerTransferInput | null {
  const body = object(value);
  if (
    body === null ||
    !hasExactKeys(body, ["request_id", "target_organization_membership_id"])
  ) {
    return null;
  }

  const requestId = uuid(body.request_id);
  const targetOrganizationMembershipId =
    uuid(body.target_organization_membership_id);
  if (requestId === null || targetOrganizationMembershipId === null) {
    return null;
  }

  return { requestId, targetOrganizationMembershipId };
}

export class PostgresOrganizationOwnerTransferStore
  implements OrganizationOwnerTransferStore
{
  constructor(private readonly query: OrganizationOwnerTransferQuery) {}

  async transfer(
    identity: VerifiedIdentity,
    requestId: string,
    organizationWorkspaceId: string,
    targetOrganizationMembershipId: string,
  ): Promise<OrganizationOwnerTransferResult> {
    try {
      const result = await this.query(
        `SELECT
           owner_transfer_contract_id,
           organization_workspace_id,
           previous_owner_assignment_id,
           organization_owner_assignment_id,
           effective_at_utc
         FROM app_data.transfer_organization_owner_for_identity_v1(
           $1::text,
           $2::text,
           $3::uuid,
           $4::uuid,
           $5::uuid
         )`,
        [
          identity.issuer,
          identity.subject,
          requestId,
          organizationWorkspaceId,
          targetOrganizationMembershipId,
        ],
      );

      if (result.rows.length !== 1) {
        throw new Error("invalid organization owner transfer result");
      }
      return parseOrganizationOwnerTransferResult(
        result.rows[0],
        organizationWorkspaceId,
      );
    } catch (error) {
      throw mapStoreError(error);
    }
  }
}

export function parseOrganizationOwnerTransferResult(
  value: unknown,
  expectedWorkspaceId: string,
): OrganizationOwnerTransferResult {
  const row = object(value);
  if (
    row === null ||
    !hasExactKeys(row, [
      "effective_at_utc",
      "organization_owner_assignment_id",
      "organization_workspace_id",
      "owner_transfer_contract_id",
      "previous_owner_assignment_id",
    ])
  ) {
    throw new Error("invalid organization owner transfer result");
  }

  if (row.owner_transfer_contract_id !== ownerTransferContractId) {
    throw new Error("invalid organization owner transfer result");
  }

  const expectedWorkspace = uuid(expectedWorkspaceId);
  const workspaceId = uuid(row.organization_workspace_id);
  const previousOwnerAssignmentId = uuid(row.previous_owner_assignment_id);
  const organizationOwnerAssignmentId = uuid(
    row.organization_owner_assignment_id,
  );
  const effectiveAtUtc = utcTimestamp(row.effective_at_utc);
  if (
    expectedWorkspace === null ||
    workspaceId === null ||
    workspaceId !== expectedWorkspace ||
    previousOwnerAssignmentId === null ||
    organizationOwnerAssignmentId === null ||
    effectiveAtUtc === null
  ) {
    throw new Error("invalid organization owner transfer result");
  }

  return {
    ownerTransferContractId,
    organizationWorkspaceId: workspaceId,
    previousOwnerAssignmentId,
    organizationOwnerAssignmentId,
    effectiveAtUtc,
  };
}

function mapStoreError(error: unknown): Error {
  if (error instanceof OrganizationOwnerTransferStoreError) {
    return error;
  }

  const code = propertyString(error, "code");
  const message = propertyString(error, "message");
  if (code === "22023" && message === "invalid organization owner transfer identity") {
    return new OrganizationOwnerTransferStoreError(
      "organization_owner_transfer_unavailable",
    );
  }
  if (code === "22023" && message === "invalid organization owner transfer request") {
    return new OrganizationOwnerTransferStoreError(
      "invalid_organization_owner_transfer_request",
    );
  }
  if (code === "42501" && message === "organization owner transfer forbidden") {
    return new OrganizationOwnerTransferStoreError(
      "organization_owner_transfer_forbidden",
    );
  }
  if (
    code === "22023" &&
    message === "organization owner transfer idempotency conflict"
  ) {
    return new OrganizationOwnerTransferStoreError(
      "organization_owner_transfer_conflict",
    );
  }
  if (
    code === "22023" &&
    message === "organization owner transfer target already owner"
  ) {
    return new OrganizationOwnerTransferStoreError(
      "organization_owner_transfer_target_already_owner",
    );
  }

  return new Error("organization owner transfer store unavailable");
}

function storeFailure(error: unknown): OrganizationOwnerTransferHttpResult {
  if (!(error instanceof OrganizationOwnerTransferStoreError)) {
    return failure(503, "organization_owner_transfer_unavailable");
  }

  switch (error.code) {
    case "invalid_organization_owner_transfer_request":
      return failure(400, error.code);
    case "organization_owner_transfer_forbidden":
      return failure(403, error.code);
    case "organization_owner_transfer_conflict":
      return failure(409, error.code);
    case "organization_owner_transfer_target_already_owner":
      return failure(409, error.code);
    case "organization_owner_transfer_unavailable":
      return failure(503, error.code);
  }
}

function identityFailure(
  category: IdentityVerificationError["category"],
): OrganizationOwnerTransferHttpResult {
  switch (category) {
    case "unauthenticated":
      return failure(401, "unauthenticated");
    case "unavailable":
      return failure(503, "organization_owner_transfer_unavailable");
  }
}

function success(
  result: OrganizationOwnerTransferResult,
): OrganizationOwnerTransferHttpResult {
  return {
    status: 200,
    body: {
      owner_transfer_contract_id: result.ownerTransferContractId,
      organization_workspace_id: result.organizationWorkspaceId,
      previous_owner_assignment_id: result.previousOwnerAssignmentId,
      organization_owner_assignment_id: result.organizationOwnerAssignmentId,
      effective_at_utc: result.effectiveAtUtc,
    },
  };
}

function failure(
  status: number,
  code: string,
): OrganizationOwnerTransferHttpResult {
  return { status, body: { error: { code } } };
}

function object(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as Record<string, unknown>)
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

function utcTimestamp(value: unknown): string | null {
  let candidate: string;
  if (value instanceof Date) {
    if (!Number.isFinite(value.getTime())) {
      return null;
    }
    candidate = value.toISOString();
  } else if (typeof value === "string") {
    candidate = value;
  } else {
    return null;
  }

  const match = timestampPattern.exec(candidate);
  if (match === null) {
    return null;
  }

  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const hour = Number(match[4]);
  const minute = Number(match[5]);
  const second = Number(match[6]);
  if (
    month < 1 ||
    month > 12 ||
    day < 1 ||
    day > daysInMonth(year, month) ||
    hour > 23 ||
    minute > 59 ||
    second > 59
  ) {
    return null;
  }

  const offset = match[7];
  if (offset === undefined) {
    return null;
  }
  if (
    offset !== "Z" &&
    (Number(offset.slice(1, 3)) > 23 || Number(offset.slice(4, 6)) > 59)
  ) {
    return null;
  }

  const timestamp = new Date(candidate);
  return Number.isFinite(timestamp.getTime()) ? timestamp.toISOString() : null;
}

function daysInMonth(year: number, month: number): number {
  if (month === 2) {
    return year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0) ? 29 : 28;
  }
  return [4, 6, 9, 11].includes(month) ? 30 : 31;
}

function propertyString(value: unknown, property: string): string | null {
  if (typeof value !== "object" || value === null) {
    return null;
  }
  const candidate = (value as Record<string, unknown>)[property];
  return typeof candidate === "string" ? candidate : null;
}
