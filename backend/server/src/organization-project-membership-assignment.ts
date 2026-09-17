import { bearerToken } from "./authorization.js";
import {
  IdentityVerificationError,
  type IdentityVerifier,
  type VerifiedIdentity,
} from "./identity.js";

const contractId = "organization-project-membership-assignment:v1" as const;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const timestampPattern = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(Z|[+-]\d{2}:\d{2})$/;
const receiptKeys = [
  "active_from_utc",
  "inactive_from_utc",
  "organization_membership_id",
  "organization_workspace_id",
  "project_id",
  "project_membership_assignment_contract_id",
  "project_membership_id",
];

export interface OrganizationProjectMembershipAssignmentResult {
  readonly projectMembershipAssignmentContractId: typeof contractId;
  readonly organizationWorkspaceId: string;
  readonly projectId: string;
  readonly organizationMembershipId: string;
  readonly projectMembershipId: string;
  readonly activeFromUtc: string;
  readonly inactiveFromUtc: string | null;
}

export type OrganizationProjectMembershipAssignmentStoreErrorCode =
  | "organization_project_membership_assignment_unavailable"
  | "invalid_organization_project_membership_assignment_request"
  | "organization_project_membership_assignment_forbidden"
  | "organization_project_membership_assignment_conflict";

export class OrganizationProjectMembershipAssignmentStoreError extends Error {
  constructor(readonly code: OrganizationProjectMembershipAssignmentStoreErrorCode) {
    super(code);
    this.name = "OrganizationProjectMembershipAssignmentStoreError";
  }
}

export type OrganizationProjectMembershipAssignmentStore = Pick<
  PostgresOrganizationProjectMembershipAssignmentStore,
  "assign"
>;

export interface OrganizationProjectMembershipAssignmentRouteMatch {
  readonly workspaceId: string;
  readonly projectId: string;
  readonly hasQuery: boolean;
}

export interface OrganizationProjectMembershipAssignmentRequest
  extends OrganizationProjectMembershipAssignmentRouteMatch {
  readonly authorization: string | undefined;
  readonly readBody: () => Promise<unknown>;
}

export interface OrganizationProjectMembershipAssignmentDependencies {
  readonly identityVerifier: IdentityVerifier | undefined;
  readonly assignmentStore: OrganizationProjectMembershipAssignmentStore | undefined;
}

export interface OrganizationProjectMembershipAssignmentInput {
  readonly requestId: string;
  readonly targetOrganizationMembershipId: string;
}

export interface OrganizationProjectMembershipAssignmentHttpResult {
  readonly status: number;
  readonly body: Readonly<Record<string, unknown>>;
}

/** Match before WHATWG URL normalization; authentication follows raw routing. */
export function matchOrganizationProjectMembershipAssignmentRequestTarget(
  requestTarget: string | undefined,
): OrganizationProjectMembershipAssignmentRouteMatch | null {
  if (requestTarget === undefined) return null;
  const queryIndex = requestTarget.indexOf("?");
  const pathname = queryIndex < 0 ? requestTarget : requestTarget.slice(0, queryIndex);
  if (pathname.includes("%")) return null;
  const match = /^\/v1\/organizations\/([^/]+)\/projects\/([^/]+)\/memberships$/.exec(pathname);
  const workspaceId = match?.[1];
  const projectId = match?.[2];
  if (workspaceId === undefined || projectId === undefined ||
    workspaceId === "." || workspaceId === ".." || projectId === "." || projectId === "..") return null;
  return { workspaceId, projectId, hasQuery: queryIndex >= 0 };
}

export async function handleOrganizationProjectMembershipAssignment(
  request: OrganizationProjectMembershipAssignmentRequest,
  dependencies: OrganizationProjectMembershipAssignmentDependencies,
): Promise<OrganizationProjectMembershipAssignmentHttpResult> {
  const accessToken = bearerToken(request.authorization);
  if (accessToken === null) return failure(401, "unauthenticated");
  if (dependencies.identityVerifier === undefined) return unavailable();
  let identity: VerifiedIdentity;
  try {
    identity = await dependencies.identityVerifier.verify(accessToken);
  } catch (error) {
    return error instanceof IdentityVerificationError && error.category === "unauthenticated"
      ? failure(401, "unauthenticated") : unavailable();
  }
  if (request.hasQuery) return invalidRequest();
  const workspaceId = uuid(request.workspaceId);
  const projectId = uuid(request.projectId);
  if (workspaceId === null || projectId === null) return invalidRequest();
  if (dependencies.assignmentStore === undefined) return unavailable();
  // Keep the shared reader's invalid_json / payload_too_large outside store catch.
  const input = parseOrganizationProjectMembershipAssignmentBody(await request.readBody());
  if (input === null) return invalidRequest();
  try {
    const result = await dependencies.assignmentStore.assign(identity, input.requestId,
      workspaceId, projectId, input.targetOrganizationMembershipId);
    return {
      status: 200,
      body: {
        project_membership_assignment_contract_id: result.projectMembershipAssignmentContractId,
        organization_workspace_id: result.organizationWorkspaceId,
        project_id: result.projectId,
        organization_membership_id: result.organizationMembershipId,
        project_membership_id: result.projectMembershipId,
        active_from_utc: result.activeFromUtc,
        inactive_from_utc: result.inactiveFromUtc,
      },
    };
  } catch (error) {
    if (error instanceof OrganizationProjectMembershipAssignmentStoreError) {
      switch (error.code) {
        case "invalid_organization_project_membership_assignment_request": return invalidRequest();
        case "organization_project_membership_assignment_forbidden": return failure(403, error.code);
        case "organization_project_membership_assignment_conflict": return failure(409, error.code);
        case "organization_project_membership_assignment_unavailable": return unavailable();
      }
    }
    return unavailable();
  }
}

export function parseOrganizationProjectMembershipAssignmentBody(
  value: unknown,
): OrganizationProjectMembershipAssignmentInput | null {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return null;
  const body = value as Record<string, unknown>;
  const keys = Object.keys(body).sort();
  if (keys.length !== 2 || keys[0] !== "request_id" || keys[1] !== "target_organization_membership_id") return null;
  const requestId = uuid(body.request_id);
  const targetOrganizationMembershipId = uuid(body.target_organization_membership_id);
  return requestId === null || targetOrganizationMembershipId === null
    ? null : { requestId, targetOrganizationMembershipId };
}

function failure(status: number, code: string): OrganizationProjectMembershipAssignmentHttpResult {
  return { status, body: { error: { code } } };
}

function unavailable(): OrganizationProjectMembershipAssignmentHttpResult {
  return failure(503, "organization_project_membership_assignment_unavailable");
}

function invalidRequest(): OrganizationProjectMembershipAssignmentHttpResult {
  return failure(400, "invalid_organization_project_membership_assignment_request");
}

type AssignmentQuery = (
  text: string,
  values: readonly unknown[],
) => Promise<{ readonly rows: readonly unknown[] }>;

export class PostgresOrganizationProjectMembershipAssignmentStore {
  constructor(private readonly query: AssignmentQuery) {}

  async assign(
    identity: VerifiedIdentity,
    requestId: string,
    organizationWorkspaceId: string,
    projectId: string,
    targetOrganizationMembershipId: string,
  ): Promise<OrganizationProjectMembershipAssignmentResult> {
    try {
      const result = await this.query(
        `SELECT
           project_membership_assignment_contract_id,
           organization_workspace_id,
           project_id,
           organization_membership_id,
           project_membership_id,
           active_from_utc,
           inactive_from_utc
         FROM app_data.assign_organization_project_member_for_identity_v1(
           $1::text, $2::text, $3::uuid, $4::uuid, $5::uuid, $6::uuid
         )`,
        [
          identity.issuer,
          identity.subject,
          requestId,
          organizationWorkspaceId,
          projectId,
          targetOrganizationMembershipId,
        ],
      );
      if (result.rows.length !== 1) {
        throw new OrganizationProjectMembershipAssignmentStoreError(
          "organization_project_membership_assignment_unavailable",
        );
      }
      return parseOrganizationProjectMembershipAssignmentResult(
        result.rows[0],
        organizationWorkspaceId,
        projectId,
        targetOrganizationMembershipId,
      );
    } catch (error) {
      throw mapStoreError(error);
    }
  }
}

export function parseOrganizationProjectMembershipAssignmentResult(
  value: unknown,
  expectedWorkspaceId: string,
  expectedProjectId: string,
  expectedTargetMembershipId: string,
): OrganizationProjectMembershipAssignmentResult {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new OrganizationProjectMembershipAssignmentStoreError(
      "organization_project_membership_assignment_unavailable",
    );
  }
  const row = value as Record<string, unknown>;
  const keys = Object.keys(row).sort();
  if (keys.length !== receiptKeys.length ||
    !keys.every((key, index) => key === receiptKeys[index]) ||
    row.project_membership_assignment_contract_id !== contractId) {
    throw new OrganizationProjectMembershipAssignmentStoreError(
      "organization_project_membership_assignment_unavailable",
    );
  }

  const organizationWorkspaceId = uuid(row.organization_workspace_id);
  const projectId = uuid(row.project_id);
  const organizationMembershipId = uuid(row.organization_membership_id);
  const projectMembershipId = uuid(row.project_membership_id);
  const activeFromUtc = utcTimestamp(row.active_from_utc);
  const inactiveFromUtc = row.inactive_from_utc === null
    ? null : utcTimestamp(row.inactive_from_utc);
  if (organizationWorkspaceId === null || projectId === null ||
    organizationMembershipId === null || projectMembershipId === null ||
    organizationWorkspaceId !== uuid(expectedWorkspaceId) ||
    projectId !== uuid(expectedProjectId) ||
    organizationMembershipId !== uuid(expectedTargetMembershipId) ||
    activeFromUtc === null ||
    (row.inactive_from_utc !== null && inactiveFromUtc === null) ||
    // ponytail: SQL owns sub-ms interval validity; version receipts if full precision is needed.
    (inactiveFromUtc !== null && Date.parse(inactiveFromUtc) < Date.parse(activeFromUtc))) {
    throw new OrganizationProjectMembershipAssignmentStoreError(
      "organization_project_membership_assignment_unavailable",
    );
  }
  return {
    projectMembershipAssignmentContractId: contractId,
    organizationWorkspaceId,
    projectId,
    organizationMembershipId,
    projectMembershipId,
    activeFromUtc,
    inactiveFromUtc,
  };
}

const sqlErrors: readonly [string, string, OrganizationProjectMembershipAssignmentStoreErrorCode][] = [
  ["22023", "invalid organization project membership assignment identity", "organization_project_membership_assignment_unavailable"],
  ["22023", "invalid organization project membership assignment request", "invalid_organization_project_membership_assignment_request"],
  ["42501", "organization project membership assignment forbidden", "organization_project_membership_assignment_forbidden"],
  ["22023", "organization project membership assignment idempotency conflict", "organization_project_membership_assignment_conflict"],
  ["0A000", "organization project membership assignment requires read committed", "organization_project_membership_assignment_unavailable"],
];

function mapStoreError(error: unknown): OrganizationProjectMembershipAssignmentStoreError {
  if (error instanceof OrganizationProjectMembershipAssignmentStoreError) return error;
  const code = propertyString(error, "code");
  const message = propertyString(error, "message");
  const match = sqlErrors.find(([state, text]) => state === code && text === message);
  return new OrganizationProjectMembershipAssignmentStoreError(
    match?.[2] ?? "organization_project_membership_assignment_unavailable",
  );
}

function uuid(value: unknown): string | null {
  return typeof value === "string" && uuidPattern.test(value) ? value.toLowerCase() : null;
}

function utcTimestamp(value: unknown): string | null {
  const candidate = value instanceof Date
    ? Number.isFinite(value.getTime()) ? value.toISOString() : null
    : typeof value === "string" ? value : null;
  if (candidate === null) return null;
  const match = timestampPattern.exec(candidate);
  if (match === null) return null;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const offset = match[7];
  if (month < 1 || month > 12 || day < 1 || day > daysInMonth(year, month) ||
    Number(match[4]) > 23 || Number(match[5]) > 59 || Number(match[6]) > 59 ||
    offset === undefined || (offset !== "Z" &&
      (Number(offset.slice(1, 3)) > 23 || Number(offset.slice(4, 6)) > 59))) return null;
  const timestamp = new Date(candidate);
  return Number.isFinite(timestamp.getTime()) ? timestamp.toISOString() : null;
}

function daysInMonth(year: number, month: number): number {
  if (month === 2) return year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0) ? 29 : 28;
  return [4, 6, 9, 11].includes(month) ? 30 : 31;
}

function propertyString(value: unknown, property: string): string | null {
  if (typeof value !== "object" || value === null) return null;
  const candidate = (value as Record<string, unknown>)[property];
  return typeof candidate === "string" ? candidate : null;
}
