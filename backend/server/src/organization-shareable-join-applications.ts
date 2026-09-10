import {bearerToken} from "./authorization.js";
import {
  IdentityVerificationError,
  type IdentityVerifier,
  type VerifiedIdentity,
} from "./identity.js";

const applicationContractId =
  "organization-shareable-join-application:v1" as const;
const applicationLifetimeSeconds = 168 * 60 * 60;
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const timestampPattern =
  /^(\d{4})-(\d{2})-(\d{2})[Tt](\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?([Zz]|[+-]\d{2}:\d{2})$/;

interface OrganizationShareableJoinApplicationRequestBase {
  readonly authorization: string | undefined;
  readonly readBody: () => Promise<unknown>;
}

export interface OrganizationShareableJoinApplicationSubmitRouteMatch {
  readonly operation: "submit";
  readonly linkId: string;
  readonly hasQuery: boolean;
}

export interface OrganizationShareableJoinApplicationApproveRouteMatch {
  readonly operation: "approve";
  readonly workspaceId: string;
  readonly applicationId: string;
  readonly hasQuery: boolean;
}

export type OrganizationShareableJoinApplicationRouteMatch =
  | OrganizationShareableJoinApplicationSubmitRouteMatch
  | OrganizationShareableJoinApplicationApproveRouteMatch;

export type OrganizationShareableJoinApplicationRequest =
  OrganizationShareableJoinApplicationRequestBase &
    OrganizationShareableJoinApplicationRouteMatch;

export interface OrganizationShareableJoinApplicationDependencies {
  readonly identityVerifier: IdentityVerifier | undefined;
  readonly applicationStore:
    | OrganizationShareableJoinApplicationStore
    | undefined;
}

export interface OrganizationShareableJoinApplicationSubmitInput {
  readonly applicationId: string;
}

export type OrganizationShareableJoinApplicationApproveInput = Readonly<
  Record<string, never>
>;

export interface OrganizationShareableJoinApplicationSubmitResult {
  readonly organizationShareableJoinApplicationContractId:
    typeof applicationContractId;
  readonly applicationId: string;
  readonly linkId: string;
  readonly organizationWorkspaceId: string;
  readonly submittedAtUtc: string;
  readonly expiresAtUtc: string;
}

export interface OrganizationShareableJoinApplicationApproveResult {
  readonly organizationShareableJoinApplicationContractId:
    typeof applicationContractId;
  readonly applicationId: string;
  readonly organizationWorkspaceId: string;
  readonly organizationMembershipId: string;
  readonly approvedAtUtc: string;
}

/** Store 只接收已验证的 exact identity，并只调用 0093/0094 runtime bridge。 */
export interface OrganizationShareableJoinApplicationStore {
  submit(
    identity: VerifiedIdentity,
    applicationId: string,
    linkId: string,
  ): Promise<OrganizationShareableJoinApplicationSubmitResult>;

  approve(
    identity: VerifiedIdentity,
    applicationId: string,
    organizationWorkspaceId: string,
  ): Promise<OrganizationShareableJoinApplicationApproveResult>;
}

export type OrganizationShareableJoinApplicationQuery = (
  text: string,
  values: readonly unknown[],
) => Promise<{readonly rows: readonly unknown[]}>;

export type OrganizationShareableJoinApplicationStoreErrorCode =
  | "organization_shareable_join_unavailable"
  | "invalid_organization_shareable_join_request"
  | "organization_shareable_join_forbidden"
  | "organization_shareable_join_conflict";

export class OrganizationShareableJoinApplicationStoreError extends Error {
  readonly code: OrganizationShareableJoinApplicationStoreErrorCode;

  constructor(code: OrganizationShareableJoinApplicationStoreErrorCode) {
    super(code);
    this.name = "OrganizationShareableJoinApplicationStoreError";
    this.code = code;
  }
}

export interface OrganizationShareableJoinApplicationHttpResult {
  readonly status: number;
  readonly body: Readonly<Record<string, unknown>>;
}

/** 必须在 URL 归一化前匹配，防止 alias 落入另一路由。 */
export function matchOrganizationShareableJoinApplicationRequestTarget(
  requestTarget: string | undefined,
): OrganizationShareableJoinApplicationRouteMatch | null {
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

  const submitMatch =
    /^\/v1\/organization-shareable-join-links\/([^/]+)\/applications$/
      .exec(pathname);
  const linkId = submitMatch?.[1];
  if (linkId !== undefined) {
    return linkId === "." || linkId === ".."
      ? null
      : {operation: "submit", linkId, hasQuery: queryIndex >= 0};
  }

  const approveMatch =
    /^\/v1\/organizations\/([^/]+)\/shareable-join-applications\/([^/]+)\/approve$/
      .exec(pathname);
  const workspaceId = approveMatch?.[1];
  const applicationId = approveMatch?.[2];
  if (
    workspaceId === undefined ||
    applicationId === undefined ||
    workspaceId === "." ||
    workspaceId === ".." ||
    applicationId === "." ||
    applicationId === ".."
  ) {
    return null;
  }
  return {
    operation: "approve",
    workspaceId,
    applicationId,
    hasQuery: queryIndex >= 0,
  };
}

export async function handleOrganizationShareableJoinApplication(
  request: OrganizationShareableJoinApplicationRequest,
  dependencies: OrganizationShareableJoinApplicationDependencies,
): Promise<OrganizationShareableJoinApplicationHttpResult> {
  const accessToken = bearerToken(request.authorization);
  if (accessToken === null) {
    return failure(401, "unauthenticated");
  }
  if (dependencies.identityVerifier === undefined) {
    return failure(503, "organization_shareable_join_unavailable");
  }

  let identity: VerifiedIdentity;
  try {
    identity = await dependencies.identityVerifier.verify(accessToken);
  } catch (error) {
    if (error instanceof IdentityVerificationError) {
      return error.category === "unauthenticated"
        ? failure(401, "unauthenticated")
        : failure(503, "organization_shareable_join_unavailable");
    }
    return failure(503, "organization_shareable_join_unavailable");
  }

  if (request.hasQuery) {
    return failure(400, "invalid_organization_shareable_join_request");
  }
  const selectedId = uuid(
    request.operation === "submit" ? request.linkId : request.applicationId,
  );
  const selectedWorkspaceId = request.operation === "approve"
    ? uuid(request.workspaceId)
    : undefined;
  if (
    selectedId === null ||
    (request.operation === "approve" && selectedWorkspaceId === null)
  ) {
    return failure(400, "invalid_organization_shareable_join_request");
  }
  if (dependencies.applicationStore === undefined) {
    return failure(503, "organization_shareable_join_unavailable");
  }

  const body = await request.readBody();
  if (request.operation === "submit") {
    const input = parseOrganizationShareableJoinApplicationSubmitBody(body);
    if (input === null) {
      return failure(400, "invalid_organization_shareable_join_request");
    }
    try {
      return submitSuccess(await dependencies.applicationStore.submit(
        identity,
        input.applicationId,
        selectedId,
      ));
    } catch (error) {
      return storeFailure(error);
    }
  }

  if (parseOrganizationShareableJoinApplicationApproveBody(body) === null) {
    return failure(400, "invalid_organization_shareable_join_request");
  }
  try {
    return approveSuccess(await dependencies.applicationStore.approve(
      identity,
      selectedId,
      selectedWorkspaceId as string,
    ));
  } catch (error) {
    return storeFailure(error);
  }
}

export function parseOrganizationShareableJoinApplicationSubmitBody(
  value: unknown,
): OrganizationShareableJoinApplicationSubmitInput | null {
  const body = object(value);
  if (body === null || !hasExactKeys(body, ["application_id"])) {
    return null;
  }
  const applicationId = uuid(body.application_id);
  return applicationId === null ? null : {applicationId};
}

export function parseOrganizationShareableJoinApplicationApproveBody(
  value: unknown,
): OrganizationShareableJoinApplicationApproveInput | null {
  const body = object(value);
  return body !== null && hasExactKeys(body, []) ? {} : null;
}

export class PostgresOrganizationShareableJoinApplicationStore
  implements OrganizationShareableJoinApplicationStore
{
  constructor(private readonly query: OrganizationShareableJoinApplicationQuery) {}

  async submit(
    identity: VerifiedIdentity,
    applicationId: string,
    linkId: string,
  ): Promise<OrganizationShareableJoinApplicationSubmitResult> {
    try {
      const result = await this.query(
        `SELECT
           organization_shareable_join_application_contract_id,
           application_id,
           link_id,
           organization_workspace_id,
           submitted_at_utc,
           expires_at_utc
         FROM app_data.submit_organization_shareable_join_application_for_identity_v1(
           $1::text,
           $2::text,
           $3::uuid,
           $4::uuid
         )`,
        [identity.issuer, identity.subject, applicationId, linkId],
      );
      if (result.rows.length !== 1) {
        throw invalidSubmitResult();
      }
      return parseOrganizationShareableJoinApplicationSubmitResult(
        result.rows[0],
        applicationId,
        linkId,
      );
    } catch (error) {
      throw mapStoreError(error);
    }
  }

  async approve(
    identity: VerifiedIdentity,
    applicationId: string,
    organizationWorkspaceId: string,
  ): Promise<OrganizationShareableJoinApplicationApproveResult> {
    try {
      const result = await this.query(
        `SELECT
           organization_shareable_join_application_contract_id,
           application_id,
           organization_workspace_id,
           organization_membership_id,
           approved_at_utc
         FROM app_data.approve_organization_shareable_join_application_for_identity_v1(
           $1::text,
           $2::text,
           $3::uuid,
           $4::uuid
         )`,
        [
          identity.issuer,
          identity.subject,
          applicationId,
          organizationWorkspaceId,
        ],
      );
      if (result.rows.length !== 1) {
        throw invalidApproveResult();
      }
      return parseOrganizationShareableJoinApplicationApproveResult(
        result.rows[0],
        applicationId,
        organizationWorkspaceId,
      );
    } catch (error) {
      throw mapStoreError(error);
    }
  }
}

export function parseOrganizationShareableJoinApplicationSubmitResult(
  value: unknown,
  expectedApplicationId: string,
  expectedLinkId: string,
): OrganizationShareableJoinApplicationSubmitResult {
  const row = object(value);
  if (
    row === null ||
    !hasExactKeys(row, [
      "application_id",
      "expires_at_utc",
      "link_id",
      "organization_shareable_join_application_contract_id",
      "organization_workspace_id",
      "submitted_at_utc",
    ]) ||
    row.organization_shareable_join_application_contract_id !==
      applicationContractId
  ) {
    throw invalidSubmitResult();
  }

  const applicationId = uuid(row.application_id);
  const linkId = uuid(row.link_id);
  const organizationWorkspaceId = uuid(row.organization_workspace_id);
  const submittedAt = utcTimestamp(row.submitted_at_utc);
  const expiresAt = utcTimestamp(row.expires_at_utc);
  if (
    applicationId === null ||
    linkId === null ||
    applicationId !== uuid(expectedApplicationId) ||
    linkId !== uuid(expectedLinkId) ||
    organizationWorkspaceId === null ||
    submittedAt === null ||
    expiresAt === null ||
    expiresAt.epochSecond - submittedAt.epochSecond !==
      applicationLifetimeSeconds ||
    expiresAt.fraction !== submittedAt.fraction
  ) {
    throw invalidSubmitResult();
  }
  return {
    organizationShareableJoinApplicationContractId: applicationContractId,
    applicationId,
    linkId,
    organizationWorkspaceId,
    submittedAtUtc: submittedAt.wire,
    expiresAtUtc: expiresAt.wire,
  };
}

export function parseOrganizationShareableJoinApplicationApproveResult(
  value: unknown,
  expectedApplicationId: string,
  expectedWorkspaceId: string,
): OrganizationShareableJoinApplicationApproveResult {
  const row = object(value);
  if (
    row === null ||
    !hasExactKeys(row, [
      "application_id",
      "approved_at_utc",
      "organization_membership_id",
      "organization_shareable_join_application_contract_id",
      "organization_workspace_id",
    ]) ||
    row.organization_shareable_join_application_contract_id !==
      applicationContractId
  ) {
    throw invalidApproveResult();
  }

  const applicationId = uuid(row.application_id);
  const organizationWorkspaceId = uuid(row.organization_workspace_id);
  const organizationMembershipId = uuid(row.organization_membership_id);
  const approvedAt = utcTimestamp(row.approved_at_utc);
  if (
    applicationId === null ||
    organizationWorkspaceId === null ||
    applicationId !== uuid(expectedApplicationId) ||
    organizationWorkspaceId !== uuid(expectedWorkspaceId) ||
    organizationMembershipId === null ||
    approvedAt === null
  ) {
    throw invalidApproveResult();
  }
  return {
    organizationShareableJoinApplicationContractId: applicationContractId,
    applicationId,
    organizationWorkspaceId,
    organizationMembershipId,
    approvedAtUtc: approvedAt.wire,
  };
}

function mapStoreError(error: unknown): Error {
  if (error instanceof OrganizationShareableJoinApplicationStoreError) {
    return error;
  }
  const code = propertyString(error, "code");
  const message = propertyString(error, "message");
  if (
    code === "22023" &&
    message === "invalid organization shareable join identity"
  ) {
    return new OrganizationShareableJoinApplicationStoreError(
      "organization_shareable_join_unavailable",
    );
  }
  if (
    code === "22023" &&
    message === "invalid organization shareable join request"
  ) {
    return new OrganizationShareableJoinApplicationStoreError(
      "invalid_organization_shareable_join_request",
    );
  }
  if (
    code === "42501" &&
    message === "organization shareable join forbidden"
  ) {
    return new OrganizationShareableJoinApplicationStoreError(
      "organization_shareable_join_forbidden",
    );
  }
  if (
    code === "22023" &&
    message === "organization shareable join idempotency conflict"
  ) {
    return new OrganizationShareableJoinApplicationStoreError(
      "organization_shareable_join_conflict",
    );
  }
  return new Error("organization shareable join application store unavailable");
}

function storeFailure(
  error: unknown,
): OrganizationShareableJoinApplicationHttpResult {
  if (!(error instanceof OrganizationShareableJoinApplicationStoreError)) {
    return failure(503, "organization_shareable_join_unavailable");
  }
  switch (error.code) {
    case "invalid_organization_shareable_join_request":
      return failure(400, error.code);
    case "organization_shareable_join_forbidden":
      return failure(403, error.code);
    case "organization_shareable_join_conflict":
      return failure(409, error.code);
    case "organization_shareable_join_unavailable":
      return failure(503, error.code);
  }
}

function submitSuccess(
  result: OrganizationShareableJoinApplicationSubmitResult,
): OrganizationShareableJoinApplicationHttpResult {
  return {
    status: 200,
    body: {
      organization_shareable_join_application_contract_id:
        result.organizationShareableJoinApplicationContractId,
      application_id: result.applicationId,
      link_id: result.linkId,
      organization_workspace_id: result.organizationWorkspaceId,
      submitted_at_utc: result.submittedAtUtc,
      expires_at_utc: result.expiresAtUtc,
    },
  };
}

function approveSuccess(
  result: OrganizationShareableJoinApplicationApproveResult,
): OrganizationShareableJoinApplicationHttpResult {
  return {
    status: 200,
    body: {
      organization_shareable_join_application_contract_id:
        result.organizationShareableJoinApplicationContractId,
      application_id: result.applicationId,
      organization_workspace_id: result.organizationWorkspaceId,
      organization_membership_id: result.organizationMembershipId,
      approved_at_utc: result.approvedAtUtc,
    },
  };
}

function failure(
  status: number,
  code: string,
): OrganizationShareableJoinApplicationHttpResult {
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
  const actual = Object.keys(value);
  return actual.length === expected.length &&
    expected.every((key) => Object.hasOwn(value, key));
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

function invalidSubmitResult(): Error {
  return new Error("invalid organization shareable join application submit result");
}

function invalidApproveResult(): Error {
  return new Error("invalid organization shareable join application approve result");
}
