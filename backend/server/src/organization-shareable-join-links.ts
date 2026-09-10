import {bearerToken} from "./authorization.js";
import {
  IdentityVerificationError,
  type IdentityVerifier,
  type VerifiedIdentity,
} from "./identity.js";

const linkContractId = "organization-shareable-join-link:v1" as const;
const previewContractId =
  "organization-shareable-join-link-preview:v1" as const;
const linkLifetimeSeconds = 168 * 60 * 60;
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const timestampPattern =
  /^(\d{4})-(\d{2})-(\d{2})[Tt](\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?([Zz]|[+-]\d{2}:\d{2})$/;

interface OrganizationShareableJoinLinkRequestBase {
  readonly authorization: string | undefined;
  readonly hasBody: boolean;
  readonly readBody: () => Promise<unknown>;
}

export interface OrganizationShareableJoinLinkCreateRouteMatch {
  readonly operation: "create";
  readonly workspaceId: string;
  readonly hasQuery: boolean;
}

export interface OrganizationShareableJoinLinkPreviewRouteMatch {
  readonly operation: "preview";
  readonly linkId: string;
  readonly hasQuery: boolean;
}

export type OrganizationShareableJoinLinkRouteMatch =
  | OrganizationShareableJoinLinkCreateRouteMatch
  | OrganizationShareableJoinLinkPreviewRouteMatch;

export type OrganizationShareableJoinLinkRequest =
  OrganizationShareableJoinLinkRequestBase &
    OrganizationShareableJoinLinkRouteMatch;

export interface OrganizationShareableJoinLinkDependencies {
  readonly identityVerifier: IdentityVerifier | undefined;
  readonly linkStore: OrganizationShareableJoinLinkStore | undefined;
}

export interface OrganizationShareableJoinLinkCreateInput {
  readonly linkId: string;
}

export interface OrganizationShareableJoinLinkCreateResult {
  readonly organizationShareableJoinLinkContractId: typeof linkContractId;
  readonly linkId: string;
  readonly organizationWorkspaceId: string;
  readonly issuedAtUtc: string;
  readonly expiresAtUtc: string;
}

export interface OrganizationShareableJoinLinkPreviewResult {
  readonly organizationShareableJoinLinkPreviewContractId:
    typeof previewContractId;
  readonly linkId: string;
  readonly organizationName: string;
  readonly expiresAtUtc: string;
}

/** Store 只接收已验证的 exact identity，并只调用 0092 runtime bridge。 */
export interface OrganizationShareableJoinLinkStore {
  create(
    identity: VerifiedIdentity,
    linkId: string,
    organizationWorkspaceId: string,
  ): Promise<OrganizationShareableJoinLinkCreateResult>;

  preview(
    identity: VerifiedIdentity,
    linkId: string,
  ): Promise<OrganizationShareableJoinLinkPreviewResult>;
}

export type OrganizationShareableJoinLinkQuery = (
  text: string,
  values: readonly unknown[],
) => Promise<{readonly rows: readonly unknown[]}>;

export type OrganizationShareableJoinLinkStoreErrorCode =
  | "organization_shareable_join_unavailable"
  | "invalid_organization_shareable_join_request"
  | "organization_shareable_join_forbidden"
  | "organization_shareable_join_conflict";

export class OrganizationShareableJoinLinkStoreError extends Error {
  readonly code: OrganizationShareableJoinLinkStoreErrorCode;

  constructor(code: OrganizationShareableJoinLinkStoreErrorCode) {
    super(code);
    this.name = "OrganizationShareableJoinLinkStoreError";
    this.code = code;
  }
}

export interface OrganizationShareableJoinLinkHttpResult {
  readonly status: number;
  readonly body: Readonly<Record<string, unknown>>;
}

/** 必须在 URL 归一化前匹配，防止 alias 落入另一路由。 */
export function matchOrganizationShareableJoinLinkRequestTarget(
  requestTarget: string | undefined,
): OrganizationShareableJoinLinkRouteMatch | null {
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
    /^\/v1\/organizations\/([^/]+)\/shareable-join-links$/.exec(pathname);
  const workspaceId = createMatch?.[1];
  if (workspaceId !== undefined) {
    return workspaceId === "." || workspaceId === ".."
      ? null
      : {operation: "create", workspaceId, hasQuery: queryIndex >= 0};
  }

  const previewMatch =
    /^\/v1\/organization-shareable-join-links\/([^/]+)$/.exec(pathname);
  const linkId = previewMatch?.[1];
  if (linkId === undefined || linkId === "." || linkId === "..") {
    return null;
  }
  return {operation: "preview", linkId, hasQuery: queryIndex >= 0};
}

export async function handleOrganizationShareableJoinLink(
  request: OrganizationShareableJoinLinkRequest,
  dependencies: OrganizationShareableJoinLinkDependencies,
): Promise<OrganizationShareableJoinLinkHttpResult> {
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

  if (request.hasQuery || (request.operation === "preview" && request.hasBody)) {
    return failure(400, "invalid_organization_shareable_join_request");
  }
  const pathId = uuid(
    request.operation === "create" ? request.workspaceId : request.linkId,
  );
  if (pathId === null) {
    return failure(400, "invalid_organization_shareable_join_request");
  }
  if (dependencies.linkStore === undefined) {
    return failure(503, "organization_shareable_join_unavailable");
  }

  if (request.operation === "preview") {
    try {
      return previewSuccess(await dependencies.linkStore.preview(identity, pathId));
    } catch (error) {
      return storeFailure(error);
    }
  }

  const input = parseOrganizationShareableJoinLinkCreateBody(
    await request.readBody(),
  );
  if (input === null) {
    return failure(400, "invalid_organization_shareable_join_request");
  }
  try {
    return createSuccess(await dependencies.linkStore.create(
      identity,
      input.linkId,
      pathId,
    ));
  } catch (error) {
    return storeFailure(error);
  }
}

export function parseOrganizationShareableJoinLinkCreateBody(
  value: unknown,
): OrganizationShareableJoinLinkCreateInput | null {
  const body = object(value);
  if (body === null || !hasExactKeys(body, ["link_id"])) {
    return null;
  }
  const linkId = uuid(body.link_id);
  return linkId === null ? null : {linkId};
}

export class PostgresOrganizationShareableJoinLinkStore
  implements OrganizationShareableJoinLinkStore
{
  constructor(private readonly query: OrganizationShareableJoinLinkQuery) {}

  async create(
    identity: VerifiedIdentity,
    linkId: string,
    organizationWorkspaceId: string,
  ): Promise<OrganizationShareableJoinLinkCreateResult> {
    try {
      const result = await this.query(
        `SELECT
           organization_shareable_join_link_contract_id,
           link_id,
           organization_workspace_id,
           issued_at_utc,
           expires_at_utc
         FROM app_data.create_organization_shareable_join_link_for_identity_v1(
           $1::text,
           $2::text,
           $3::uuid,
           $4::uuid
         )`,
        [identity.issuer, identity.subject, linkId, organizationWorkspaceId],
      );
      if (result.rows.length !== 1) {
        throw invalidCreateResult();
      }
      return parseOrganizationShareableJoinLinkCreateResult(
        result.rows[0],
        linkId,
        organizationWorkspaceId,
      );
    } catch (error) {
      throw mapStoreError(error);
    }
  }

  async preview(
    identity: VerifiedIdentity,
    linkId: string,
  ): Promise<OrganizationShareableJoinLinkPreviewResult> {
    try {
      const result = await this.query(
        `SELECT
           organization_shareable_join_link_preview_contract_id,
           link_id,
           organization_name,
           expires_at_utc
         FROM app_data.preview_organization_shareable_join_link_for_identity_v1(
           $1::text,
           $2::text,
           $3::uuid
         )`,
        [identity.issuer, identity.subject, linkId],
      );
      if (result.rows.length !== 1) {
        throw invalidPreviewResult();
      }
      return parseOrganizationShareableJoinLinkPreviewResult(
        result.rows[0],
        linkId,
      );
    } catch (error) {
      throw mapStoreError(error);
    }
  }
}

export function parseOrganizationShareableJoinLinkCreateResult(
  value: unknown,
  expectedLinkId: string,
  expectedWorkspaceId: string,
): OrganizationShareableJoinLinkCreateResult {
  const row = object(value);
  if (
    row === null ||
    !hasExactKeys(row, [
      "expires_at_utc",
      "issued_at_utc",
      "link_id",
      "organization_shareable_join_link_contract_id",
      "organization_workspace_id",
    ]) ||
    row.organization_shareable_join_link_contract_id !== linkContractId
  ) {
    throw invalidCreateResult();
  }

  const expectedLink = uuid(expectedLinkId);
  const expectedWorkspace = uuid(expectedWorkspaceId);
  const linkId = uuid(row.link_id);
  const organizationWorkspaceId = uuid(row.organization_workspace_id);
  const issuedAt = utcTimestamp(row.issued_at_utc);
  const expiresAt = utcTimestamp(row.expires_at_utc);
  if (
    expectedLink === null ||
    linkId !== expectedLink ||
    expectedWorkspace === null ||
    organizationWorkspaceId !== expectedWorkspace ||
    issuedAt === null ||
    expiresAt === null ||
    expiresAt.epochSecond - issuedAt.epochSecond !== linkLifetimeSeconds ||
    expiresAt.fraction !== issuedAt.fraction
  ) {
    throw invalidCreateResult();
  }

  return {
    organizationShareableJoinLinkContractId: linkContractId,
    linkId,
    organizationWorkspaceId,
    issuedAtUtc: issuedAt.wire,
    expiresAtUtc: expiresAt.wire,
  };
}

export function parseOrganizationShareableJoinLinkPreviewResult(
  value: unknown,
  expectedLinkId: string,
): OrganizationShareableJoinLinkPreviewResult {
  const row = object(value);
  if (
    row === null ||
    !hasExactKeys(row, [
      "expires_at_utc",
      "link_id",
      "organization_name",
      "organization_shareable_join_link_preview_contract_id",
    ]) ||
    row.organization_shareable_join_link_preview_contract_id !== previewContractId
  ) {
    throw invalidPreviewResult();
  }

  const expectedLink = uuid(expectedLinkId);
  const linkId = uuid(row.link_id);
  const organizationName = row.organization_name;
  const expiresAt = utcTimestamp(row.expires_at_utc);
  if (
    expectedLink === null ||
    linkId !== expectedLink ||
    typeof organizationName !== "string" ||
    organizationName.replace(/^ +| +$/g, "").length === 0 ||
    expiresAt === null
  ) {
    throw invalidPreviewResult();
  }

  return {
    organizationShareableJoinLinkPreviewContractId: previewContractId,
    linkId,
    organizationName,
    expiresAtUtc: expiresAt.wire,
  };
}

function mapStoreError(error: unknown): Error {
  if (error instanceof OrganizationShareableJoinLinkStoreError) {
    return error;
  }

  const code = propertyString(error, "code");
  const message = propertyString(error, "message");
  if (
    code === "22023" &&
    message === "invalid organization shareable join identity"
  ) {
    return new OrganizationShareableJoinLinkStoreError(
      "organization_shareable_join_unavailable",
    );
  }
  if (
    code === "22023" &&
    message === "invalid organization shareable join request"
  ) {
    return new OrganizationShareableJoinLinkStoreError(
      "invalid_organization_shareable_join_request",
    );
  }
  if (
    code === "42501" &&
    message === "organization shareable join forbidden"
  ) {
    return new OrganizationShareableJoinLinkStoreError(
      "organization_shareable_join_forbidden",
    );
  }
  if (
    code === "22023" &&
    message === "organization shareable join idempotency conflict"
  ) {
    return new OrganizationShareableJoinLinkStoreError(
      "organization_shareable_join_conflict",
    );
  }
  return new Error("organization shareable join store unavailable");
}

function storeFailure(
  error: unknown,
): OrganizationShareableJoinLinkHttpResult {
  if (!(error instanceof OrganizationShareableJoinLinkStoreError)) {
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

function createSuccess(
  result: OrganizationShareableJoinLinkCreateResult,
): OrganizationShareableJoinLinkHttpResult {
  return {
    status: 200,
    body: {
      organization_shareable_join_link_contract_id:
        result.organizationShareableJoinLinkContractId,
      link_id: result.linkId,
      organization_workspace_id: result.organizationWorkspaceId,
      issued_at_utc: result.issuedAtUtc,
      expires_at_utc: result.expiresAtUtc,
    },
  };
}

function previewSuccess(
  result: OrganizationShareableJoinLinkPreviewResult,
): OrganizationShareableJoinLinkHttpResult {
  return {
    status: 200,
    body: {
      organization_shareable_join_link_preview_contract_id:
        result.organizationShareableJoinLinkPreviewContractId,
      link_id: result.linkId,
      organization_name: result.organizationName,
      expires_at_utc: result.expiresAtUtc,
    },
  };
}

function failure(
  status: number,
  code: string,
): OrganizationShareableJoinLinkHttpResult {
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

function invalidCreateResult(): Error {
  return new Error("invalid organization shareable join link create result");
}

function invalidPreviewResult(): Error {
  return new Error("invalid organization shareable join link preview result");
}
