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
}

export interface SessionContextStore {
  loadOrCreate(identity: VerifiedIdentity): Promise<SessionContext>;
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

    return parseContextRow(result.rows[0]);
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
