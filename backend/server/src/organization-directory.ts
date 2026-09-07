import { bearerToken } from "./authorization.js";
import {
  IdentityVerificationError,
  type IdentityVerifier,
  type VerifiedIdentity,
} from "./identity.js";

const organizationDirectoryContractId = "organization-directory:v1" as const;
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

export interface OrganizationDirectoryItem {
  readonly organizationWorkspaceId: string;
  readonly organizationName: string;
}

/** Store 只接收已验证外部身份，且只交付当前组织的 ID 与原名称。 */
export interface OrganizationDirectoryStore {
  list(identity: VerifiedIdentity): Promise<readonly OrganizationDirectoryItem[]>;
}

export interface OrganizationDirectoryRequest {
  readonly authorization: string | undefined;
  readonly hasQuery: boolean;
  readonly hasBody: boolean;
}

export interface OrganizationDirectoryDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly organizationDirectoryStore?: OrganizationDirectoryStore;
}

export interface OrganizationDirectoryHttpResult {
  readonly status: number;
  readonly body: Readonly<Record<string, unknown>>;
}

/** 认证先于请求形状检查；失败时不暴露 identity、SQL 或目录内容。 */
export async function listOrganizationDirectory(
  request: OrganizationDirectoryRequest,
  dependencies: OrganizationDirectoryDependencies,
): Promise<OrganizationDirectoryHttpResult> {
  const accessToken = bearerToken(request.authorization);
  if (accessToken === null) {
    return failure(401, "unauthenticated");
  }

  let identity: VerifiedIdentity;
  try {
    identity = await dependencies.identityVerifier.verify(accessToken);
  } catch (error) {
    if (error instanceof IdentityVerificationError) {
      return error.category === "unauthenticated"
        ? failure(401, "unauthenticated")
        : failure(503, "organization_directory_unavailable");
    }
    return failure(503, "organization_directory_unavailable");
  }

  if (request.hasQuery || request.hasBody) {
    return failure(400, "invalid_organization_directory_request");
  }
  if (dependencies.organizationDirectoryStore === undefined) {
    return failure(503, "organization_directory_unavailable");
  }

  try {
    const organizations = await dependencies.organizationDirectoryStore.list(
      identity,
    );
    return {
      status: 200,
      body: {
        organization_directory_contract_id: organizationDirectoryContractId,
        organizations: organizations.map((organization) => ({
          organization_workspace_id: organization.organizationWorkspaceId,
          organization_name: organization.organizationName,
        })),
      },
    };
  } catch (error) {
    return error instanceof OrganizationDirectoryStoreError &&
        error.code === "organization_directory_forbidden"
      ? failure(403, error.code)
      : failure(503, "organization_directory_unavailable");
  }
}

export type OrganizationDirectoryQuery = (
  text: string,
  values: readonly unknown[],
) => Promise<{ readonly rows: readonly unknown[] }>;

export class OrganizationDirectoryStoreError extends Error {
  constructor(
    readonly code:
      | "organization_directory_forbidden"
      | "organization_directory_unavailable",
  ) {
    super(code);
    this.name = "OrganizationDirectoryStoreError";
  }
}

export class PostgresOrganizationDirectoryStore
  implements OrganizationDirectoryStore
{
  constructor(private readonly query: OrganizationDirectoryQuery) {}

  async list(
    identity: VerifiedIdentity,
  ): Promise<readonly OrganizationDirectoryItem[]> {
    try {
      const result = await this.query(
        `SELECT
           organization_workspace_id,
           organization_name
         FROM app_data.list_organizations_for_identity_v1($1::text, $2::text)`,
        [identity.issuer, identity.subject],
      );

      // ponytail: 当前合同要求完整目录；只有真实资源证据表明需要时才增加分页。
      const organizations = result.rows.map(parseOrganizationDirectoryItem);
      const workspaceIds = new Set<string>();
      for (const organization of organizations) {
        if (workspaceIds.has(organization.organizationWorkspaceId)) {
          throw invalidDirectoryResult();
        }
        workspaceIds.add(organization.organizationWorkspaceId);
      }
      return organizations;
    } catch (error) {
      throw mapStoreError(error);
    }
  }
}

function parseOrganizationDirectoryItem(
  value: unknown,
): OrganizationDirectoryItem {
  const row = object(value);
  if (
    row === null ||
    !hasExactKeys(row, ["organization_name", "organization_workspace_id"])
  ) {
    throw invalidDirectoryResult();
  }

  const workspaceId = uuid(row.organization_workspace_id);
  const name = row.organization_name;
  if (
    workspaceId === null ||
    typeof name !== "string" ||
    name.replace(/^ +| +$/g, "").length === 0
  ) {
    throw invalidDirectoryResult();
  }
  return {
    organizationWorkspaceId: workspaceId,
    organizationName: name,
  };
}

function mapStoreError(error: unknown): OrganizationDirectoryStoreError {
  if (error instanceof OrganizationDirectoryStoreError) {
    return error;
  }

  const code = propertyString(error, "code");
  const message = propertyString(error, "message");
  if (code === "42501" && message === "organization directory forbidden") {
    return new OrganizationDirectoryStoreError(
      "organization_directory_forbidden",
    );
  }
  return new OrganizationDirectoryStoreError(
    "organization_directory_unavailable",
  );
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
  return typeof value === "string" && uuidPattern.test(value) ? value : null;
}

function propertyString(value: unknown, property: string): string | null {
  if (typeof value !== "object" || value === null) {
    return null;
  }
  const candidate = (value as Record<string, unknown>)[property];
  return typeof candidate === "string" ? candidate : null;
}

function invalidDirectoryResult(): Error {
  return new Error("invalid organization directory result");
}

function failure(
  status: number,
  code: string,
): OrganizationDirectoryHttpResult {
  return { status, body: { error: { code } } };
}
