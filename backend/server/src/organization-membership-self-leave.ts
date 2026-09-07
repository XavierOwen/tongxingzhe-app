import { bearerToken } from "./authorization.js";
import {
  IdentityVerificationError,
  type IdentityVerifier,
  type VerifiedIdentity,
} from "./identity.js";

const membershipSelfLeaveContractId =
  "organization-membership-self-leave:v1" as const;
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const timestampPattern =
  /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(Z|[+-]\d{2}:\d{2})$/;

export interface OrganizationMembershipSelfLeaveRequest {
  readonly authorization: string | undefined;
  readonly workspaceId: string;
  readonly hasQuery: boolean;
  readonly readBody: () => Promise<unknown>;
}

export interface OrganizationMembershipSelfLeaveDependencies {
  readonly identityVerifier: IdentityVerifier | undefined;
  readonly leaveStore: OrganizationMembershipSelfLeaveStore | undefined;
}

export interface OrganizationMembershipSelfLeaveInput {
  readonly requestId: string;
}

export interface OrganizationMembershipSelfLeaveResult {
  readonly membershipSelfLeaveContractId: typeof membershipSelfLeaveContractId;
  readonly organizationWorkspaceId: string;
  readonly organizationMembershipId: string;
  readonly effectiveAtUtc: string;
}

export interface OrganizationMembershipSelfLeaveStore {
  leave(
    identity: VerifiedIdentity,
    requestId: string,
    organizationWorkspaceId: string,
  ): Promise<OrganizationMembershipSelfLeaveResult>;
}

export type OrganizationMembershipSelfLeaveQuery = (
  text: string,
  values: readonly unknown[],
) => Promise<{ readonly rows: readonly unknown[] }>;

export type OrganizationMembershipSelfLeaveStoreErrorCode =
  | "organization_membership_self_leave_unavailable"
  | "invalid_organization_membership_self_leave_request"
  | "organization_membership_self_leave_forbidden"
  | "organization_membership_self_leave_conflict";

export class OrganizationMembershipSelfLeaveStoreError extends Error {
  readonly code: OrganizationMembershipSelfLeaveStoreErrorCode;

  constructor(code: OrganizationMembershipSelfLeaveStoreErrorCode) {
    super(code);
    this.name = "OrganizationMembershipSelfLeaveStoreError";
    this.code = code;
  }
}

export interface OrganizationMembershipSelfLeaveHttpResult {
  readonly status: number;
  readonly body: Readonly<Record<string, unknown>>;
}

export interface OrganizationMembershipSelfLeaveRouteMatch {
  readonly workspaceId: string;
  readonly hasQuery: boolean;
}

export function matchOrganizationMembershipSelfLeaveRequestTarget(
  requestTarget: string | undefined,
): OrganizationMembershipSelfLeaveRouteMatch | null {
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
    /^\/v1\/organizations\/([^/]+)\/membership-self-leave$/.exec(pathname);
  const workspaceId = match?.[1];
  if (workspaceId === undefined || workspaceId === "." || workspaceId === "..") {
    return null;
  }

  return { workspaceId, hasQuery: queryIndex >= 0 };
}

export async function handleOrganizationMembershipSelfLeave(
  request: OrganizationMembershipSelfLeaveRequest,
  dependencies: OrganizationMembershipSelfLeaveDependencies,
): Promise<OrganizationMembershipSelfLeaveHttpResult> {
  const accessToken = bearerToken(request.authorization);
  if (accessToken === null) {
    return failure(401, "unauthenticated");
  }

  if (dependencies.identityVerifier === undefined) {
    return failure(503, "organization_membership_self_leave_unavailable");
  }

  let identity: VerifiedIdentity;
  try {
    identity = await dependencies.identityVerifier.verify(accessToken);
  } catch (error) {
    if (error instanceof IdentityVerificationError) {
      return identityFailure(error.category);
    }
    return failure(503, "organization_membership_self_leave_unavailable");
  }

  if (request.hasQuery) {
    return failure(400, "invalid_organization_membership_self_leave_request");
  }

  const organizationWorkspaceId = uuid(request.workspaceId);
  if (organizationWorkspaceId === null) {
    return failure(400, "invalid_organization_membership_self_leave_request");
  }

  if (dependencies.leaveStore === undefined) {
    return failure(503, "organization_membership_self_leave_unavailable");
  }

  const input = parseOrganizationMembershipSelfLeaveBody(await request.readBody());
  if (input === null) {
    return failure(400, "invalid_organization_membership_self_leave_request");
  }

  try {
    return success(await dependencies.leaveStore.leave(
      identity,
      input.requestId,
      organizationWorkspaceId,
    ));
  } catch (error) {
    return storeFailure(error);
  }
}

export function parseOrganizationMembershipSelfLeaveBody(
  value: unknown,
): OrganizationMembershipSelfLeaveInput | null {
  const body = object(value);
  if (body === null || !hasExactKeys(body, ["request_id"])) {
    return null;
  }
  const requestId = uuid(body.request_id);
  return requestId === null ? null : { requestId };
}

export class PostgresOrganizationMembershipSelfLeaveStore
  implements OrganizationMembershipSelfLeaveStore
{
  constructor(private readonly query: OrganizationMembershipSelfLeaveQuery) {}

  async leave(
    identity: VerifiedIdentity,
    requestId: string,
    organizationWorkspaceId: string,
  ): Promise<OrganizationMembershipSelfLeaveResult> {
    try {
      const result = await this.query(
        `SELECT
           membership_self_leave_contract_id,
           organization_workspace_id,
           organization_membership_id,
           effective_at_utc
         FROM app_data.leave_organization_membership_for_identity_v1(
           $1::text,
           $2::text,
           $3::uuid,
           $4::uuid
         )`,
        [identity.issuer, identity.subject, requestId, organizationWorkspaceId],
      );
      if (result.rows.length !== 1) {
        throw new Error("invalid organization membership self-leave result");
      }
      return parseOrganizationMembershipSelfLeaveResult(
        result.rows[0],
        organizationWorkspaceId,
      );
    } catch (error) {
      throw mapStoreError(error);
    }
  }
}

export function parseOrganizationMembershipSelfLeaveResult(
  value: unknown,
  expectedWorkspaceId: string,
): OrganizationMembershipSelfLeaveResult {
  const row = object(value);
  if (
    row === null ||
    !hasExactKeys(row, [
      "effective_at_utc",
      "membership_self_leave_contract_id",
      "organization_membership_id",
      "organization_workspace_id",
    ]) ||
    row.membership_self_leave_contract_id !== membershipSelfLeaveContractId
  ) {
    throw new Error("invalid organization membership self-leave result");
  }

  const expectedWorkspace = uuid(expectedWorkspaceId);
  const organizationWorkspaceId = lowercaseUuid(row.organization_workspace_id);
  const organizationMembershipId = lowercaseUuid(row.organization_membership_id);
  const effectiveAtUtc = utcTimestamp(row.effective_at_utc);
  if (
    expectedWorkspace === null ||
    organizationWorkspaceId !== expectedWorkspace ||
    organizationMembershipId === null ||
    effectiveAtUtc === null
  ) {
    throw new Error("invalid organization membership self-leave result");
  }

  return {
    membershipSelfLeaveContractId,
    organizationWorkspaceId,
    organizationMembershipId,
    effectiveAtUtc,
  };
}

function mapStoreError(error: unknown): Error {
  if (error instanceof OrganizationMembershipSelfLeaveStoreError) {
    return error;
  }

  const code = propertyString(error, "code");
  const message = propertyString(error, "message");
  if (code === "22023" && message === "invalid organization membership self-leave identity") {
    return new OrganizationMembershipSelfLeaveStoreError(
      "organization_membership_self_leave_unavailable",
    );
  }
  if (code === "22023" && message === "invalid organization membership self-leave request") {
    return new OrganizationMembershipSelfLeaveStoreError(
      "invalid_organization_membership_self_leave_request",
    );
  }
  if (code === "42501" && message === "organization membership self-leave forbidden") {
    return new OrganizationMembershipSelfLeaveStoreError(
      "organization_membership_self_leave_forbidden",
    );
  }
  if (
    code === "22023" &&
    message === "organization membership self-leave idempotency conflict"
  ) {
    return new OrganizationMembershipSelfLeaveStoreError(
      "organization_membership_self_leave_conflict",
    );
  }
  return new Error("organization membership self-leave store unavailable");
}

function storeFailure(error: unknown): OrganizationMembershipSelfLeaveHttpResult {
  if (!(error instanceof OrganizationMembershipSelfLeaveStoreError)) {
    return failure(503, "organization_membership_self_leave_unavailable");
  }
  switch (error.code) {
    case "invalid_organization_membership_self_leave_request":
      return failure(400, error.code);
    case "organization_membership_self_leave_forbidden":
      return failure(403, error.code);
    case "organization_membership_self_leave_conflict":
      return failure(409, error.code);
    case "organization_membership_self_leave_unavailable":
      return failure(503, error.code);
  }
}

function identityFailure(
  category: IdentityVerificationError["category"],
): OrganizationMembershipSelfLeaveHttpResult {
  return category === "unauthenticated"
    ? failure(401, "unauthenticated")
    : failure(503, "organization_membership_self_leave_unavailable");
}

function success(
  result: OrganizationMembershipSelfLeaveResult,
): OrganizationMembershipSelfLeaveHttpResult {
  return {
    status: 200,
    body: {
      membership_self_leave_contract_id: result.membershipSelfLeaveContractId,
      organization_workspace_id: result.organizationWorkspaceId,
      organization_membership_id: result.organizationMembershipId,
      effective_at_utc: result.effectiveAtUtc,
    },
  };
}

function failure(status: number, code: string): OrganizationMembershipSelfLeaveHttpResult {
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

function lowercaseUuid(value: unknown): string | null {
  const parsed = uuid(value);
  return parsed === value ? parsed : null;
}

function utcTimestamp(value: unknown): string | null {
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
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const hour = Number(match[4]);
  const minute = Number(match[5]);
  const second = Number(match[6]);
  if (
    month < 1 || month > 12 || day < 1 || day > daysInMonth(year, month) ||
    hour > 23 || minute > 59 || second > 59
  ) return null;

  const offset = match[7];
  if (
    offset === undefined ||
    (offset !== "Z" &&
      (Number(offset.slice(1, 3)) > 23 || Number(offset.slice(4, 6)) > 59))
  ) return null;

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
  if (typeof value !== "object" || value === null) return null;
  const candidate = (value as Record<string, unknown>)[property];
  return typeof candidate === "string" ? candidate : null;
}
