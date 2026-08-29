import { bearerToken } from "./authorization.js";
import {
  OrganizationCreationIdentityError,
  type OrganizationCreationEligibility,
  type OrganizationCreationIdentityVerifier,
} from "./organization-creation-identity.js";

const creationContractId = "organization-creation:v1" as const;
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const timestampPattern =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/;

export interface OrganizationCreationRequest {
  readonly authorization: string | undefined;
  readonly hasQuery: boolean;
  readonly readBody: () => Promise<unknown>;
}

export interface OrganizationCreationDependencies {
  readonly identityVerifier: OrganizationCreationIdentityVerifier | undefined;
  readonly creationStore: OrganizationCreationStore | undefined;
}

export interface OrganizationCreationInput {
  readonly requestId: string;
  readonly displayName: string;
}

export interface OrganizationCreationResult {
  readonly creationContractId: typeof creationContractId;
  readonly organizationWorkspaceId: string;
  readonly organizationMembershipId: string;
  readonly organizationOwnerAssignmentId: string;
  readonly createdAtUtc: string;
}

export interface OrganizationCreationStore {
  create(
    identity: OrganizationCreationEligibility,
    requestId: string,
    displayName: string,
  ): Promise<OrganizationCreationResult>;
}

export type OrganizationCreationQuery = (
  text: string,
  values: readonly unknown[],
) => Promise<{ readonly rows: readonly unknown[] }>;

export type OrganizationCreationStoreErrorCode =
  | "organization_creation_unavailable"
  | "invalid_organization_creation_request"
  | "organization_creation_forbidden"
  | "organization_creation_conflict";

export class OrganizationCreationStoreError extends Error {
  readonly code: OrganizationCreationStoreErrorCode;

  constructor(code: OrganizationCreationStoreErrorCode) {
    super(code);
    this.name = "OrganizationCreationStoreError";
    this.code = code;
  }
}

export interface OrganizationCreationHttpResult {
  readonly status: number;
  readonly body: Readonly<Record<string, unknown>>;
}

export async function handleOrganizationCreation(
  request: OrganizationCreationRequest,
  dependencies: OrganizationCreationDependencies,
): Promise<OrganizationCreationHttpResult> {
  const accessToken = bearerToken(request.authorization);
  if (accessToken === null) {
    return failure(401, "unauthenticated");
  }

  if (dependencies.identityVerifier === undefined) {
    return failure(503, "organization_creation_unavailable");
  }

  let identity: OrganizationCreationEligibility;
  try {
    identity = await dependencies.identityVerifier.verify(accessToken);
  } catch (error) {
    if (error instanceof OrganizationCreationIdentityError) {
      return identityFailure(error.category);
    }
    return failure(503, "organization_creation_unavailable");
  }

  if (request.hasQuery) {
    return failure(400, "invalid_organization_creation_request");
  }

  if (dependencies.creationStore === undefined) {
    return failure(503, "organization_creation_unavailable");
  }

  const body = await request.readBody();
  const input = parseOrganizationCreationBody(body);
  if (input === null) {
    return failure(400, "invalid_organization_creation_request");
  }

  try {
    const result = await dependencies.creationStore.create(
      identity,
      input.requestId,
      input.displayName,
    );
    return success(result);
  } catch (error) {
    return storeFailure(error);
  }
}

export function parseOrganizationCreationBody(
  value: unknown,
): OrganizationCreationInput | null {
  const body = object(value);
  if (body === null || !hasExactKeys(body, ["display_name", "request_id"])) {
    return null;
  }

  const requestId = body.request_id;
  const displayName = body.display_name;
  if (typeof requestId !== "string" || !uuidPattern.test(requestId)) {
    return null;
  }
  if (typeof displayName !== "string") {
    return null;
  }

  return { requestId, displayName };
}

export class PostgresOrganizationCreationStore
  implements OrganizationCreationStore
{
  constructor(private readonly query: OrganizationCreationQuery) {}

  async create(
    identity: OrganizationCreationEligibility,
    requestId: string,
    displayName: string,
  ): Promise<OrganizationCreationResult> {
    try {
      const result = await this.query(
        `SELECT
           creation_contract_id,
           organization_workspace_id,
           organization_membership_id,
           organization_owner_assignment_id,
           created_at_utc
         FROM app_data.create_organization_for_identity_v1(
           $1::text,
           $2::text,
           $3::uuid,
           $4::text
         )`,
        [identity.issuer, identity.subject, requestId, displayName],
      );

      if (result.rows.length !== 1) {
        throw new Error("invalid organization creation result");
      }
      return parseOrganizationCreationResult(result.rows[0]);
    } catch (error) {
      throw mapStoreError(error);
    }
  }
}

function parseOrganizationCreationResult(
  value: unknown,
): OrganizationCreationResult {
  const row = object(value);
  if (
    row === null ||
    !hasExactKeys(row, [
      "created_at_utc",
      "creation_contract_id",
      "organization_membership_id",
      "organization_owner_assignment_id",
      "organization_workspace_id",
    ])
  ) {
    throw new Error("invalid organization creation result");
  }

  if (row.creation_contract_id !== creationContractId) {
    throw new Error("invalid organization creation result");
  }

  const workspaceId = uuid(row.organization_workspace_id);
  const membershipId = uuid(row.organization_membership_id);
  const ownerAssignmentId = uuid(row.organization_owner_assignment_id);
  const createdAtUtc = utcTimestamp(row.created_at_utc);
  if (
    workspaceId === null ||
    membershipId === null ||
    ownerAssignmentId === null ||
    createdAtUtc === null
  ) {
    throw new Error("invalid organization creation result");
  }

  return {
    creationContractId,
    organizationWorkspaceId: workspaceId,
    organizationMembershipId: membershipId,
    organizationOwnerAssignmentId: ownerAssignmentId,
    createdAtUtc,
  };
}

function mapStoreError(error: unknown): Error {
  if (error instanceof OrganizationCreationStoreError) {
    return error;
  }

  const code = propertyString(error, "code");
  const message = propertyString(error, "message");
  if (code === "22023" && message === "invalid organization creation identity") {
    return new OrganizationCreationStoreError(
      "organization_creation_unavailable",
    );
  }
  if (code === "22023" && message === "invalid organization creation request") {
    return new OrganizationCreationStoreError(
      "invalid_organization_creation_request",
    );
  }
  if (code === "42501" && message === "organization creation forbidden") {
    return new OrganizationCreationStoreError("organization_creation_forbidden");
  }
  if (code === "22023" && message === "organization creation idempotency conflict") {
    return new OrganizationCreationStoreError("organization_creation_conflict");
  }

  return new Error("organization creation store unavailable");
}

function storeFailure(error: unknown): OrganizationCreationHttpResult {
  if (!(error instanceof OrganizationCreationStoreError)) {
    return failure(503, "organization_creation_unavailable");
  }

  switch (error.code) {
    case "invalid_organization_creation_request":
      return failure(400, error.code);
    case "organization_creation_forbidden":
      return failure(403, error.code);
    case "organization_creation_conflict":
      return failure(409, error.code);
    case "organization_creation_unavailable":
      return failure(503, error.code);
  }
}

function identityFailure(
  category: OrganizationCreationIdentityError["category"],
): OrganizationCreationHttpResult {
  switch (category) {
    case "unauthenticated":
      return failure(401, "unauthenticated");
    case "forbidden":
      return failure(403, "organization_creation_forbidden");
    case "unavailable":
      return failure(503, "organization_creation_unavailable");
  }
}

function success(result: OrganizationCreationResult): OrganizationCreationHttpResult {
  return {
    status: 200,
    body: {
      creation_contract_id: result.creationContractId,
      organization_workspace_id: result.organizationWorkspaceId,
      organization_membership_id: result.organizationMembershipId,
      organization_owner_assignment_id: result.organizationOwnerAssignmentId,
      created_at_utc: result.createdAtUtc,
    },
  };
}

function failure(status: number, code: string): OrganizationCreationHttpResult {
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
  return actual.length === expected.length && actual.every((key, index) => key === expected[index]);
}

function uuid(value: unknown): string | null {
  return typeof value === "string" && uuidPattern.test(value) ? value : null;
}

function utcTimestamp(value: unknown): string | null {
  const candidate = value instanceof Date ? value.toISOString() : value;
  if (typeof candidate !== "string" || !timestampPattern.test(candidate)) {
    return null;
  }

  const timestamp = new Date(candidate);
  return Number.isFinite(timestamp.getTime()) ? timestamp.toISOString() : null;
}

function propertyString(value: unknown, property: string): string | null {
  if (typeof value !== "object" || value === null) {
    return null;
  }
  const candidate = (value as Record<string, unknown>)[property];
  return typeof candidate === "string" ? candidate : null;
}
