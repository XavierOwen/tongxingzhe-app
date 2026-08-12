import {bearerToken} from "./authorization.js";
import {
  IdentityVerificationError,
  type IdentityVerifier,
  type VerifiedIdentity,
} from "./identity.js";

export interface ManagementAnalysisContext {
  readonly organization: {readonly id: string; readonly name: string};
  readonly project: {readonly id: string; readonly name: string};
}

export interface ManagementAnalysisContextSnapshot {
  readonly current: ManagementAnalysisContext | null;
  readonly available: readonly ManagementAnalysisContext[];
}

export interface ManagementAnalysisContextStore {
  load(identity: VerifiedIdentity): Promise<ManagementAnalysisContextSnapshot>;
  select(
    identity: VerifiedIdentity,
    projectId: string,
  ): Promise<ManagementAnalysisContextSnapshot>;
}

export interface ManagementAnalysisContextDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly contextStore: ManagementAnalysisContextStore;
}

export interface ManagementAnalysisContextHttpResult {
  readonly status: number;
  readonly body: Readonly<Record<string, unknown>>;
}

export type ManagementAnalysisContextAuthentication = {
  readonly status: "verified";
  readonly identity: VerifiedIdentity;
} | {
  readonly status: "rejected";
  readonly result: ManagementAnalysisContextHttpResult;
};

export async function authenticateManagementAnalysisContext(
  authorization: string | undefined,
  identityVerifier: IdentityVerifier,
): Promise<ManagementAnalysisContextAuthentication> {
  const accessToken = bearerToken(authorization);
  if (accessToken === null) {
    return {status: "rejected", result: failure(401, "unauthenticated")};
  }
  try {
    return {
      status: "verified",
      identity: await identityVerifier.verify(accessToken),
    };
  } catch (error) {
    return {
      status: "rejected",
      result: error instanceof IdentityVerificationError
        ? failure(401, "unauthenticated")
        : failure(503, "management_analysis_context_unavailable"),
    };
  }
}

export async function getManagementAnalysisContext(
  authorization: string | undefined,
  dependencies: ManagementAnalysisContextDependencies,
): Promise<ManagementAnalysisContextHttpResult> {
  const authentication = await authenticateManagementAnalysisContext(
    authorization,
    dependencies.identityVerifier,
  );
  return authentication.status === "rejected"
    ? authentication.result
    : loadManagementAnalysisContextForIdentity(
      authentication.identity,
      dependencies.contextStore,
    );
}

export async function selectManagementAnalysisContext(
  authorization: string | undefined,
  body: unknown,
  dependencies: ManagementAnalysisContextDependencies,
): Promise<ManagementAnalysisContextHttpResult> {
  const authentication = await authenticateManagementAnalysisContext(
    authorization,
    dependencies.identityVerifier,
  );
  if (authentication.status === "rejected") return authentication.result;
  return selectManagementAnalysisContextForIdentity(
    authentication.identity,
    body,
    dependencies.contextStore,
  );
}

export async function loadManagementAnalysisContextForIdentity(
  identity: VerifiedIdentity,
  contextStore: ManagementAnalysisContextStore,
): Promise<ManagementAnalysisContextHttpResult> {
  try {
    return success(await contextStore.load(identity));
  } catch (error) {
    return mappedFailure(error);
  }
}

export async function selectManagementAnalysisContextForIdentity(
  identity: VerifiedIdentity,
  body: unknown,
  contextStore: ManagementAnalysisContextStore,
): Promise<ManagementAnalysisContextHttpResult> {
  const projectId = selectionProjectId(body);
  if (projectId === null) {
    return failure(400, "invalid_management_analysis_context");
  }

  try {
    return success(await contextStore.select(identity, projectId));
  } catch (error) {
    return mappedFailure(error);
  }
}

export type ManagementAnalysisContextQuery = (
  text: string,
  values: readonly unknown[],
) => Promise<{readonly rows: readonly unknown[]}>;

export class PostgresManagementAnalysisContextStore
implements ManagementAnalysisContextStore {
  constructor(private readonly query: ManagementAnalysisContextQuery) {}

  async load(
    identity: VerifiedIdentity,
  ): Promise<ManagementAnalysisContextSnapshot> {
    try {
      const result = await this.query(
        `SELECT
           organization_workspace_id,
           organization_name,
           project_id,
           project_name,
           is_current
         FROM app_data.list_management_analysis_contexts_v1($1, $2)`,
        [identity.issuer, identity.subject],
      );
      return parseRows(result.rows, false);
    } catch (error) {
      throw mapPostgresError(error);
    }
  }

  async select(
    identity: VerifiedIdentity,
    projectId: string,
  ): Promise<ManagementAnalysisContextSnapshot> {
    try {
      const result = await this.query(
        `SELECT
           organization_workspace_id,
           organization_name,
           project_id,
           project_name,
           is_current
         FROM app_data.select_management_analysis_context_v1(
           $1, $2, $3::uuid
         )`,
        [identity.issuer, identity.subject, projectId],
      );
      return parseRows(result.rows, true);
    } catch (error) {
      throw mapPostgresError(error);
    }
  }
}

export class ManagementAnalysisContextStoreError extends Error {
  constructor(readonly code: "forbidden") {
    super(code);
    this.name = "ManagementAnalysisContextStoreError";
  }
}

function parseRows(
  values: readonly unknown[],
  selectionResult: boolean,
): ManagementAnalysisContextSnapshot {
  if (selectionResult && values.length !== 1) throw invalidContext();
  const available: ManagementAnalysisContext[] = [];
  let current: ManagementAnalysisContext | null = null;
  const projectIds = new Set<string>();

  for (const value of values) {
    const row = object(value);
    requireExactKeys(row, rowKeys);
    const context = {
      organization: {
        id: uuid(row.organization_workspace_id),
        name: nonEmptyString(row.organization_name),
      },
      project: {
        id: uuid(row.project_id),
        name: nonEmptyString(row.project_name),
      },
    };
    if (projectIds.has(context.project.id)) throw invalidContext();
    projectIds.add(context.project.id);
    if (typeof row.is_current !== "boolean") throw invalidContext();
    if (row.is_current) {
      if (current !== null) throw invalidContext();
      current = context;
    }
    available.push(context);
  }

  if (selectionResult && current === null) throw invalidContext();
  return {current, available};
}

function success(
  snapshot: ManagementAnalysisContextSnapshot,
): ManagementAnalysisContextHttpResult {
  return {
    status: 200,
    body: {
      current_context: snapshot.current === null
        ? null
        : serializeContext(snapshot.current),
      available_contexts: snapshot.available.map(serializeContext),
      authorization: "must_reauthorize",
    },
  };
}

function serializeContext(
  context: ManagementAnalysisContext,
): Readonly<Record<string, unknown>> {
  return {
    organization: {
      workspace_id: context.organization.id,
      name: context.organization.name,
    },
    project: {
      project_id: context.project.id,
      name: context.project.name,
    },
  };
}

function selectionProjectId(body: unknown): string | null {
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return null;
  }
  const record = body as Record<string, unknown>;
  if (
    Object.keys(record).length !== 1 ||
    !("project_id" in record) ||
    typeof record.project_id !== "string" ||
    !uuidPattern.test(record.project_id)
  ) {
    return null;
  }
  return record.project_id;
}

function mappedFailure(error: unknown): ManagementAnalysisContextHttpResult {
  if (
    error instanceof ManagementAnalysisContextStoreError &&
    error.code === "forbidden"
  ) {
    return failure(403, "management_analysis_context_forbidden");
  }
  return failure(503, "management_analysis_context_unavailable");
}

function mapPostgresError(error: unknown): Error {
  const code = typeof error === "object" && error !== null && "code" in error
    ? String(error.code)
    : "";
  if (code === "42501") {
    return new ManagementAnalysisContextStoreError("forbidden");
  }
  return error instanceof Error ? error : new Error(String(error));
}

function object(value: unknown): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw invalidContext();
  }
  return value as Record<string, unknown>;
}

function requireExactKeys(
  value: Record<string, unknown>,
  expected: readonly string[],
): void {
  const actual = Object.keys(value).sort();
  const sortedExpected = [...expected].sort();
  if (
    actual.length !== sortedExpected.length ||
    actual.some((key, index) => key !== sortedExpected[index])
  ) {
    throw invalidContext();
  }
}

function uuid(value: unknown): string {
  if (typeof value !== "string" || !uuidPattern.test(value)) {
    throw invalidContext();
  }
  return value;
}

function nonEmptyString(value: unknown): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw invalidContext();
  }
  return value;
}

function failure(
  status: number,
  code: string,
): ManagementAnalysisContextHttpResult {
  return {status, body: {error: {code}}};
}

function invalidContext(): Error {
  return new Error("invalid management analysis context result");
}

const rowKeys = [
  "organization_workspace_id",
  "organization_name",
  "project_id",
  "project_name",
  "is_current",
];

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
