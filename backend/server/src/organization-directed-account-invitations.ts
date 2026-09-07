import { bearerToken } from "./authorization.js";
import {
  IdentityVerificationError,
  type IdentityVerifier,
  type VerifiedIdentity,
} from "./identity.js";

const invitationContractId =
  "organization-directed-account-invitation:v1" as const;
const invitationPreviewContractId =
  "organization-directed-account-invitation-preview:v1" as const;
const invitationLifetimeSeconds = 168 * 60 * 60;
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const timestampPattern =
  /^(\d{4})-(\d{2})-(\d{2})[Tt](\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?([Zz]|[+-]\d{2}:\d{2})$/;

interface OrganizationDirectedAccountInvitationRequestBase {
  readonly authorization: string | undefined;
  readonly hasBody: boolean;
  readonly readBody: () => Promise<unknown>;
}

export interface OrganizationDirectedAccountInvitationCreateRouteMatch {
  readonly operation: "create";
  readonly workspaceId: string;
  readonly hasQuery: boolean;
}

export interface OrganizationDirectedAccountInvitationAcceptRouteMatch {
  readonly operation: "accept";
  readonly invitationId: string;
  readonly hasQuery: boolean;
}

export interface OrganizationDirectedAccountInvitationPreviewRouteMatch {
  readonly operation: "preview";
  readonly invitationId: string;
  readonly hasQuery: boolean;
}

export type OrganizationDirectedAccountInvitationRouteMatch =
  | OrganizationDirectedAccountInvitationCreateRouteMatch
  | OrganizationDirectedAccountInvitationAcceptRouteMatch
  | OrganizationDirectedAccountInvitationPreviewRouteMatch;

export type OrganizationDirectedAccountInvitationRequest =
  OrganizationDirectedAccountInvitationRequestBase &
    OrganizationDirectedAccountInvitationRouteMatch;

export interface OrganizationDirectedAccountInvitationDependencies {
  readonly identityVerifier: IdentityVerifier | undefined;
  readonly invitationStore: OrganizationDirectedAccountInvitationStore | undefined;
}

export interface OrganizationDirectedAccountInvitationCreateInput {
  readonly invitationId: string;
  readonly targetAppUserId: string;
}

export type OrganizationDirectedAccountInvitationAcceptInput = Readonly<
  Record<string, never>
>;

export interface OrganizationDirectedAccountInvitationCreateResult {
  readonly organizationInvitationContractId: typeof invitationContractId;
  readonly invitationId: string;
  readonly organizationWorkspaceId: string;
  readonly issuedAtUtc: string;
  readonly expiresAtUtc: string;
}

export interface OrganizationDirectedAccountInvitationAcceptResult {
  readonly organizationInvitationContractId: typeof invitationContractId;
  readonly invitationId: string;
  readonly organizationWorkspaceId: string;
  readonly organizationMembershipId: string;
  readonly acceptedAtUtc: string;
}

export interface OrganizationDirectedAccountInvitationPreviewResult {
  readonly organizationInvitationPreviewContractId:
    typeof invitationPreviewContractId;
  readonly invitationId: string;
  readonly organizationName: string;
  readonly expiresAtUtc: string;
}

/**
 * identity 来自已验证的 exact issuer／subject，UUID 仍是不可信 selector。
 * 创建写 claim／审计，接受写 membership／claim／审计；授权与精确重放由数据库决定。
 * 预览只读绑定收件人可见的名称与期限，不保留接受资格。
 * 创建与接受是独立 receipt，不含账号资料；失败只抛稳定分类。
 */
export interface OrganizationDirectedAccountInvitationStore {
  create(
    identity: VerifiedIdentity,
    invitationId: string,
    organizationWorkspaceId: string,
    targetAppUserId: string,
  ): Promise<OrganizationDirectedAccountInvitationCreateResult>;

  accept(
    identity: VerifiedIdentity,
    invitationId: string,
  ): Promise<OrganizationDirectedAccountInvitationAcceptResult>;

  preview(
    identity: VerifiedIdentity,
    invitationId: string,
  ): Promise<OrganizationDirectedAccountInvitationPreviewResult>;
}

export type OrganizationDirectedAccountInvitationQuery = (
  text: string,
  values: readonly unknown[],
) => Promise<{ readonly rows: readonly unknown[] }>;

export type OrganizationDirectedAccountInvitationStoreErrorCode =
  | "organization_invitation_unavailable"
  | "invalid_organization_invitation_request"
  | "organization_invitation_forbidden"
  | "organization_invitation_conflict";

export class OrganizationDirectedAccountInvitationStoreError extends Error {
  readonly code: OrganizationDirectedAccountInvitationStoreErrorCode;

  constructor(code: OrganizationDirectedAccountInvitationStoreErrorCode) {
    super(code);
    this.name = "OrganizationDirectedAccountInvitationStoreError";
    this.code = code;
  }
}

export interface OrganizationDirectedAccountInvitationHttpResult {
  readonly status: number;
  readonly body: Readonly<Record<string, unknown>>;
}

/** 必须在 URL 归一化前匹配，否则 dot segment 可能把请求改送到另一入口。 */
export function matchOrganizationDirectedAccountInvitationRequestTarget(
  requestTarget: string | undefined,
): OrganizationDirectedAccountInvitationRouteMatch | null {
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

  const createMatch =
    /^\/v1\/organizations\/([^/]+)\/directed-account-invitations$/.exec(
      pathname,
    );
  const workspaceId = createMatch?.[1];
  if (workspaceId !== undefined) {
    return workspaceId === "." || workspaceId === ".."
      ? null
      : { operation: "create", workspaceId, hasQuery: queryIndex >= 0 };
  }

  const invitationMatch =
    /^\/v1\/organization-directed-account-invitations\/([^/]+)(\/accept)?$/.exec(
      pathname,
    );
  const invitationId = invitationMatch?.[1];
  if (invitationId === undefined || invitationId === "." || invitationId === "..") {
    return null;
  }

  return {
    operation: invitationMatch?.[2] === undefined ? "preview" : "accept",
    invitationId,
    hasQuery: queryIndex >= 0,
  };
}

export async function handleOrganizationDirectedAccountInvitation(
  request: OrganizationDirectedAccountInvitationRequest,
  dependencies: OrganizationDirectedAccountInvitationDependencies,
): Promise<OrganizationDirectedAccountInvitationHttpResult> {
  const accessToken = bearerToken(request.authorization);
  if (accessToken === null) {
    return failure(401, "unauthenticated");
  }

  if (dependencies.identityVerifier === undefined) {
    return failure(503, "organization_invitation_unavailable");
  }

  let identity: VerifiedIdentity;
  try {
    identity = await dependencies.identityVerifier.verify(accessToken);
  } catch (error) {
    if (error instanceof IdentityVerificationError) {
      return identityFailure(error.category);
    }
    return failure(503, "organization_invitation_unavailable");
  }

  if (request.hasQuery || (request.operation === "preview" && request.hasBody)) {
    return failure(400, "invalid_organization_invitation_request");
  }

  const pathId = uuid(
    request.operation === "create" ? request.workspaceId : request.invitationId,
  );
  if (pathId === null) {
    return failure(400, "invalid_organization_invitation_request");
  }

  if (dependencies.invitationStore === undefined) {
    return failure(503, "organization_invitation_unavailable");
  }

  if (request.operation === "preview") {
    try {
      const result = await dependencies.invitationStore.preview(identity, pathId);
      return previewSuccess(result);
    } catch (error) {
      return storeFailure(error);
    }
  }

  const body = await request.readBody();
  try {
    if (request.operation === "create") {
      const input = parseOrganizationDirectedAccountInvitationCreateBody(body);
      if (input === null) {
        return failure(400, "invalid_organization_invitation_request");
      }
      const result = await dependencies.invitationStore.create(
        identity,
        input.invitationId,
        pathId,
        input.targetAppUserId,
      );
      return createSuccess(result);
    }

    if (parseOrganizationDirectedAccountInvitationAcceptBody(body) === null) {
      return failure(400, "invalid_organization_invitation_request");
    }
    const result = await dependencies.invitationStore.accept(identity, pathId);
    return acceptSuccess(result);
  } catch (error) {
    return storeFailure(error);
  }
}

export function parseOrganizationDirectedAccountInvitationCreateBody(
  value: unknown,
): OrganizationDirectedAccountInvitationCreateInput | null {
  const body = object(value);
  if (
    body === null ||
    !hasExactKeys(body, ["invitation_id", "target_app_user_id"])
  ) {
    return null;
  }

  const invitationId = uuid(body.invitation_id);
  const targetAppUserId = uuid(body.target_app_user_id);
  return invitationId === null || targetAppUserId === null
    ? null
    : { invitationId, targetAppUserId };
}

export function parseOrganizationDirectedAccountInvitationAcceptBody(
  value: unknown,
): OrganizationDirectedAccountInvitationAcceptInput | null {
  const body = object(value);
  return body !== null && hasExactKeys(body, []) ? {} : null;
}

export class PostgresOrganizationDirectedAccountInvitationStore
  implements OrganizationDirectedAccountInvitationStore
{
  constructor(private readonly query: OrganizationDirectedAccountInvitationQuery) {}

  async preview(
    identity: VerifiedIdentity,
    invitationId: string,
  ): Promise<OrganizationDirectedAccountInvitationPreviewResult> {
    try {
      const result = await this.query(
        `SELECT
           organization_invitation_preview_contract_id,
           invitation_id,
           organization_name,
           expires_at_utc
         FROM app_data.preview_organization_directed_invitation_for_identity_v1(
           $1::text,
           $2::text,
           $3::uuid
         )`,
        [identity.issuer, identity.subject, invitationId],
      );
      if (result.rows.length !== 1) {
        throw new Error("invalid organization invitation preview result");
      }
      return parseOrganizationDirectedAccountInvitationPreviewResult(
        result.rows[0],
        invitationId,
      );
    } catch (error) {
      throw mapStoreError(error);
    }
  }

  async create(
    identity: VerifiedIdentity,
    invitationId: string,
    organizationWorkspaceId: string,
    targetAppUserId: string,
  ): Promise<OrganizationDirectedAccountInvitationCreateResult> {
    try {
      const result = await this.query(
        `SELECT
           organization_invitation_contract_id,
           invitation_id,
           organization_workspace_id,
           issued_at_utc,
           expires_at_utc
         FROM app_data.create_organization_directed_account_invitation_for_identity_v1(
           $1::text,
           $2::text,
           $3::uuid,
           $4::uuid,
           $5::uuid
         )`,
        [
          identity.issuer,
          identity.subject,
          invitationId,
          organizationWorkspaceId,
          targetAppUserId,
        ],
      );
      if (result.rows.length !== 1) {
        throw new Error("invalid organization invitation create result");
      }
      return parseOrganizationDirectedAccountInvitationCreateResult(
        result.rows[0],
        invitationId,
        organizationWorkspaceId,
      );
    } catch (error) {
      throw mapStoreError(error);
    }
  }

  async accept(
    identity: VerifiedIdentity,
    invitationId: string,
  ): Promise<OrganizationDirectedAccountInvitationAcceptResult> {
    try {
      const result = await this.query(
        `SELECT
           organization_invitation_contract_id,
           invitation_id,
           organization_workspace_id,
           organization_membership_id,
           accepted_at_utc
         FROM app_data.accept_organization_directed_account_invitation_for_identity_v1(
           $1::text,
           $2::text,
           $3::uuid
         )`,
        [identity.issuer, identity.subject, invitationId],
      );
      if (result.rows.length !== 1) {
        throw new Error("invalid organization invitation accept result");
      }
      return parseOrganizationDirectedAccountInvitationAcceptResult(
        result.rows[0],
        invitationId,
      );
    } catch (error) {
      throw mapStoreError(error);
    }
  }
}

export function parseOrganizationDirectedAccountInvitationPreviewResult(
  value: unknown,
  expectedInvitationId: string,
): OrganizationDirectedAccountInvitationPreviewResult {
  const row = object(value);
  if (
    row === null ||
    !hasExactKeys(row, [
      "organization_invitation_preview_contract_id",
      "invitation_id",
      "organization_name",
      "expires_at_utc",
    ]) ||
    row.organization_invitation_preview_contract_id !== invitationPreviewContractId
  ) {
    throw new Error("invalid organization invitation preview result");
  }

  const expectedInvitation = uuid(expectedInvitationId);
  const invitationId = uuid(row.invitation_id);
  const name = row.organization_name;
  const expiresAt = utcTimestamp(row.expires_at_utc);
  if (
    expectedInvitation === null ||
    invitationId !== expectedInvitation ||
    typeof name !== "string" ||
    name.replace(/^ +| +$/g, "").length === 0 ||
    expiresAt === null
  ) {
    throw new Error("invalid organization invitation preview result");
  }
  return {
    organizationInvitationPreviewContractId: invitationPreviewContractId,
    invitationId,
    organizationName: name,
    expiresAtUtc: expiresAt.wire,
  };
}

export function parseOrganizationDirectedAccountInvitationCreateResult(
  value: unknown,
  expectedInvitationId: string,
  expectedWorkspaceId: string,
): OrganizationDirectedAccountInvitationCreateResult {
  const row = object(value);
  if (
    row === null ||
    !hasExactKeys(row, [
      "expires_at_utc",
      "invitation_id",
      "issued_at_utc",
      "organization_invitation_contract_id",
      "organization_workspace_id",
    ]) ||
    row.organization_invitation_contract_id !== invitationContractId
  ) {
    throw new Error("invalid organization invitation create result");
  }

  const expectedInvitation = uuid(expectedInvitationId);
  const expectedWorkspace = uuid(expectedWorkspaceId);
  const invitationId = uuid(row.invitation_id);
  const workspaceId = uuid(row.organization_workspace_id);
  const issuedAt = utcTimestamp(row.issued_at_utc);
  const expiresAt = utcTimestamp(row.expires_at_utc);
  if (
    expectedInvitation === null ||
    invitationId !== expectedInvitation ||
    expectedWorkspace === null ||
    workspaceId !== expectedWorkspace ||
    issuedAt === null ||
    expiresAt === null ||
    expiresAt.epochSecond - issuedAt.epochSecond !== invitationLifetimeSeconds ||
    expiresAt.fraction !== issuedAt.fraction
  ) {
    throw new Error("invalid organization invitation create result");
  }

  return {
    organizationInvitationContractId: invitationContractId,
    invitationId,
    organizationWorkspaceId: workspaceId,
    issuedAtUtc: issuedAt.wire,
    expiresAtUtc: expiresAt.wire,
  };
}

export function parseOrganizationDirectedAccountInvitationAcceptResult(
  value: unknown,
  expectedInvitationId: string,
): OrganizationDirectedAccountInvitationAcceptResult {
  const row = object(value);
  if (
    row === null ||
    !hasExactKeys(row, [
      "accepted_at_utc",
      "invitation_id",
      "organization_invitation_contract_id",
      "organization_membership_id",
      "organization_workspace_id",
    ]) ||
    row.organization_invitation_contract_id !== invitationContractId
  ) {
    throw new Error("invalid organization invitation accept result");
  }

  const expectedInvitation = uuid(expectedInvitationId);
  const invitationId = uuid(row.invitation_id);
  const workspaceId = uuid(row.organization_workspace_id);
  const membershipId = uuid(row.organization_membership_id);
  const acceptedAt = utcTimestamp(row.accepted_at_utc);
  if (
    expectedInvitation === null ||
    invitationId !== expectedInvitation ||
    workspaceId === null ||
    membershipId === null ||
    acceptedAt === null
  ) {
    throw new Error("invalid organization invitation accept result");
  }

  return {
    organizationInvitationContractId: invitationContractId,
    invitationId,
    organizationWorkspaceId: workspaceId,
    organizationMembershipId: membershipId,
    acceptedAtUtc: acceptedAt.wire,
  };
}

function mapStoreError(error: unknown): Error {
  if (error instanceof OrganizationDirectedAccountInvitationStoreError) {
    return error;
  }

  const code = propertyString(error, "code");
  const message = propertyString(error, "message");
  if (code === "22023" && message === "invalid organization invitation identity") {
    return new OrganizationDirectedAccountInvitationStoreError(
      "organization_invitation_unavailable",
    );
  }
  if (code === "22023" && message === "invalid organization invitation request") {
    return new OrganizationDirectedAccountInvitationStoreError(
      "invalid_organization_invitation_request",
    );
  }
  if (code === "42501" && message === "organization invitation forbidden") {
    return new OrganizationDirectedAccountInvitationStoreError(
      "organization_invitation_forbidden",
    );
  }
  if (
    code === "22023" &&
    message === "organization invitation idempotency conflict"
  ) {
    return new OrganizationDirectedAccountInvitationStoreError(
      "organization_invitation_conflict",
    );
  }

  return new Error("organization invitation store unavailable");
}

function storeFailure(
  error: unknown,
): OrganizationDirectedAccountInvitationHttpResult {
  if (!(error instanceof OrganizationDirectedAccountInvitationStoreError)) {
    return failure(503, "organization_invitation_unavailable");
  }

  switch (error.code) {
    case "invalid_organization_invitation_request":
      return failure(400, error.code);
    case "organization_invitation_forbidden":
      return failure(403, error.code);
    case "organization_invitation_conflict":
      return failure(409, error.code);
    case "organization_invitation_unavailable":
      return failure(503, error.code);
  }
}

function identityFailure(
  category: IdentityVerificationError["category"],
): OrganizationDirectedAccountInvitationHttpResult {
  switch (category) {
    case "unauthenticated":
      return failure(401, "unauthenticated");
    case "unavailable":
      return failure(503, "organization_invitation_unavailable");
  }
}

function previewSuccess(
  result: OrganizationDirectedAccountInvitationPreviewResult,
): OrganizationDirectedAccountInvitationHttpResult {
  return {
    status: 200,
    body: {
      organization_invitation_preview_contract_id:
        result.organizationInvitationPreviewContractId,
      invitation_id: result.invitationId,
      organization_name: result.organizationName,
      expires_at_utc: result.expiresAtUtc,
    },
  };
}

function createSuccess(
  result: OrganizationDirectedAccountInvitationCreateResult,
): OrganizationDirectedAccountInvitationHttpResult {
  return {
    status: 200,
    body: {
      organization_invitation_contract_id:
        result.organizationInvitationContractId,
      invitation_id: result.invitationId,
      organization_workspace_id: result.organizationWorkspaceId,
      issued_at_utc: result.issuedAtUtc,
      expires_at_utc: result.expiresAtUtc,
    },
  };
}

function acceptSuccess(
  result: OrganizationDirectedAccountInvitationAcceptResult,
): OrganizationDirectedAccountInvitationHttpResult {
  return {
    status: 200,
    body: {
      organization_invitation_contract_id:
        result.organizationInvitationContractId,
      invitation_id: result.invitationId,
      organization_workspace_id: result.organizationWorkspaceId,
      organization_membership_id: result.organizationMembershipId,
      accepted_at_utc: result.acceptedAtUtc,
    },
  };
}

function failure(
  status: number,
  code: string,
): OrganizationDirectedAccountInvitationHttpResult {
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

function utcTimestamp(value: unknown): {
  readonly wire: string;
  readonly epochSecond: number;
  readonly fraction: string;
} | null {
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

  const offset = match[8];
  if (
    offset === undefined ||
    (offset.toUpperCase() !== "Z" &&
      (Number(offset.slice(1, 3)) > 23 || Number(offset.slice(4, 6)) > 59))
  ) {
    return null;
  }

  const timestamp = new Date(candidate);
  if (!Number.isFinite(timestamp.getTime())) {
    return null;
  }
  return {
    wire: timestamp.toISOString(),
    epochSecond: Math.floor(timestamp.getTime() / 1_000),
    // 先保留小数秒比较 168 小时，避免毫秒序列化掩盖数据库结果的更小漂移。
    fraction: (match[7] ?? "").replace(/0+$/, ""),
  };
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
