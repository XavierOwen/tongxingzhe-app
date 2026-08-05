import type { VerifiedIdentity } from "./identity.js";

export type WorkspaceKind = "personal" | "organization";

export interface SessionContext {
  readonly appUserId: string;
  readonly current: {
    readonly workspace: {
      readonly id: string;
      readonly kind: WorkspaceKind;
      readonly name: string;
    };
    readonly project: {
      readonly id: string;
      readonly name: string;
    };
    readonly questionnaireVersion: {
      readonly id: string;
      readonly versionNumber: number;
    };
  };
  readonly capabilities: readonly string[];
  readonly availableContexts?: readonly SessionContext[];
}

export interface SessionContextStore {
  loadOrCreate(identity: VerifiedIdentity): Promise<SessionContext>;
  selectProject?(
    identity: VerifiedIdentity,
    projectId: string,
  ): Promise<SessionContext>;
  createPersonalProject?(
    identity: VerifiedIdentity,
    displayName: string,
  ): Promise<SessionContext>;
}

export type ContextQuery = (
  text: string,
  values: readonly string[],
) => Promise<{ readonly rows: readonly unknown[] }>;

interface ContextRow {
  readonly app_user_id: unknown;
  readonly workspace_id: unknown;
  readonly workspace_kind: unknown;
  readonly workspace_name: unknown;
  readonly project_id: unknown;
  readonly project_name: unknown;
  readonly questionnaire_version_id: unknown;
  readonly questionnaire_version_number: unknown;
  readonly capabilities: unknown;
  readonly is_current?: unknown;
}

export class PostgresSessionContextStore implements SessionContextStore {
  constructor(private readonly query: ContextQuery) {}

  async loadOrCreate(identity: VerifiedIdentity): Promise<SessionContext> {
    const result = await this.query(
      `SELECT
         app_user_id,
         workspace_id,
         workspace_kind,
         workspace_name,
         project_id,
         project_name,
         questionnaire_version_id,
         questionnaire_version_number,
         capabilities
       FROM app_data.bootstrap_personal_context($1, $2)`,
      [identity.issuer, identity.subject],
    );

    if (result.rows.length !== 1) {
      throw new Error("Context bootstrap must return exactly one row");
    }

    const bootstrapContext = parseContextRow(result.rows[0]);
    return this.loadAvailableContexts(identity, bootstrapContext);
  }

  async selectProject(
    identity: VerifiedIdentity,
    projectId: string,
  ): Promise<SessionContext> {
    const result = await this.query(
      `SELECT
         app_user_id,
         workspace_id,
         workspace_kind,
         workspace_name,
         project_id,
         project_name,
         questionnaire_version_id,
         questionnaire_version_number,
         capabilities
       FROM app_data.select_personal_project_context($1, $2, $3::uuid)`,
      [identity.issuer, identity.subject, projectId],
    );
    if (result.rows.length !== 1) {
      throw new Error("Project selection must return exactly one row");
    }
    const selectedContext = parseContextRow(result.rows[0]);
    return this.loadAvailableContexts(identity, selectedContext);
  }

  async createPersonalProject(
    identity: VerifiedIdentity,
    displayName: string,
  ): Promise<SessionContext> {
    const result = await this.query(
      `SELECT
         app_user_id,
         workspace_id,
         workspace_kind,
         workspace_name,
         project_id,
         project_name,
         questionnaire_version_id,
         questionnaire_version_number,
         capabilities
       FROM app_data.create_personal_project_context($1, $2, $3)`,
      [identity.issuer, identity.subject, displayName],
    );
    if (result.rows.length !== 1) {
      throw new Error("Project creation must return exactly one row");
    }
    const createdContext = parseContextRow(result.rows[0]);
    return this.loadAvailableContexts(identity, createdContext);
  }

  private async loadAvailableContexts(
    identity: VerifiedIdentity,
    fallbackCurrent: SessionContext,
  ): Promise<SessionContext> {
    const result = await this.query(
      `SELECT
         app_user_id,
         workspace_id,
         workspace_kind,
         workspace_name,
         project_id,
         project_name,
         questionnaire_version_id,
         questionnaire_version_number,
         capabilities,
         is_current
       FROM app_data.list_personal_project_contexts($1, $2)`,
      [identity.issuer, identity.subject],
    );
    if (result.rows.length === 0) {
      return {...fallbackCurrent, availableContexts: [fallbackCurrent]};
    }
    const rows = result.rows.map((value) => {
      const row = value as ContextRow;
      return {context: parseContextRow(row), isCurrent: row.is_current === true};
    });
    const selected =
      rows.find((item) => item.isCurrent)?.context ??
      rows.find(
        (item) =>
          item.context.current.project.id ===
          fallbackCurrent.current.project.id,
      )?.context;
    if (selected === undefined) {
      throw new Error("Available projects do not contain a current context");
    }
    return {
      ...selected,
      availableContexts: rows.map((item) => item.context),
    };
  }
}

function parseContextRow(value: unknown): SessionContext {
  if (typeof value !== "object" || value === null) {
    throw new Error("Context bootstrap returned a non-object row");
  }
  const row = value as ContextRow;
  const workspaceKind = requireWorkspaceKind(row.workspace_kind);
  const versionNumber = requirePositiveInteger(
    row.questionnaire_version_number,
    "questionnaire_version_number",
  );

  if (!Array.isArray(row.capabilities)) {
    throw new Error("Context bootstrap returned invalid capabilities");
  }
  const capabilities = row.capabilities.map((capability) =>
    requireString(capability, "capability"),
  );

  return {
    appUserId: requireString(row.app_user_id, "app_user_id"),
    current: {
      workspace: {
        id: requireString(row.workspace_id, "workspace_id"),
        kind: workspaceKind,
        name: requireString(row.workspace_name, "workspace_name"),
      },
      project: {
        id: requireString(row.project_id, "project_id"),
        name: requireString(row.project_name, "project_name"),
      },
      questionnaireVersion: {
        id: requireString(
          row.questionnaire_version_id,
          "questionnaire_version_id",
        ),
        versionNumber,
      },
    },
    capabilities: Object.freeze([...new Set(capabilities)]),
  };
}

function requireString(value: unknown, name: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error(`Context bootstrap returned invalid ${name}`);
  }
  return value;
}

function requireWorkspaceKind(value: unknown): WorkspaceKind {
  if (value !== "personal" && value !== "organization") {
    throw new Error("Context bootstrap returned invalid workspace_kind");
  }
  return value;
}

function requirePositiveInteger(value: unknown, name: string): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 1) {
    throw new Error(`Context bootstrap returned invalid ${name}`);
  }
  return value;
}
