import {bearerToken} from "./authorization.js";
import {
  IdentityVerificationError,
  type IdentityVerifier,
  type VerifiedIdentity,
} from "./identity.js";
import type {
  SessionContextStore,
} from "./session-context.js";

const exportCapability = "export_target_pii";
const viewCapability = "view_assigned_target_pii";

export interface PersonalTargetPiiExportStore {
  prepare(
    identity: VerifiedIdentity,
    projectId: string,
    passwordAuthenticatedAtUnixSeconds: number,
  ): Promise<Buffer>;
}

export interface PersonalTargetPiiExportRequest {
  readonly authorization: string | undefined;
  readonly hasQuery: boolean;
  readonly hasBody: boolean;
}

export interface PersonalTargetPiiExportDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly contextStore: SessionContextStore;
  readonly exportStore?: PersonalTargetPiiExportStore;
  readonly now?: () => Date;
}

export type PersonalTargetPiiExportHttpResult = {
  readonly status: 200;
  readonly bytes: Buffer;
} | {
  readonly status: number;
  readonly body: Readonly<Record<string, unknown>>;
};

export async function exportPersonalTargetPii(
  request: PersonalTargetPiiExportRequest,
  dependencies: PersonalTargetPiiExportDependencies,
): Promise<PersonalTargetPiiExportHttpResult> {
  const accessToken = bearerToken(request.authorization);
  if (accessToken === null) return failure(401, "unauthenticated");

  let identity: VerifiedIdentity;
  try {
    identity = await dependencies.identityVerifier.verify(accessToken);
  } catch (error) {
    if (
      error instanceof IdentityVerificationError &&
      error.category === "unauthenticated"
    ) {
      return failure(401, "unauthenticated");
    }
    return failure(503, "personal_target_pii_export_unavailable");
  }

  const authenticatedAt = identity.passwordAuthenticatedAtUnixSeconds;
  if (!isRecentPasswordAuthentication(
    authenticatedAt,
    dependencies.now?.() ?? new Date(),
  )) {
    return failure(403, "reauthentication_required");
  }
  if (request.hasQuery || request.hasBody) {
    return failure(400, "invalid_personal_target_pii_export_request");
  }

  let projectId: string;
  try {
    const context = await dependencies.contextStore.loadOrCreate(identity);
    if (
      context.current.workspace.kind !== "personal" ||
      !context.capabilities.includes(exportCapability) ||
      !context.capabilities.includes(viewCapability)
    ) {
      return failure(403, "personal_target_pii_export_forbidden");
    }
    projectId = context.current.project.id;
  } catch {
    return failure(503, "personal_target_pii_export_unavailable");
  }

  if (dependencies.exportStore === undefined) {
    return failure(503, "personal_target_pii_export_unavailable");
  }
  try {
    return {
      status: 200,
      bytes: await dependencies.exportStore.prepare(
        identity,
        projectId,
        authenticatedAt,
      ),
    };
  } catch (error) {
    if (error instanceof PersonalTargetPiiExportStoreError) {
      return error.code === "reauthentication_required"
        ? failure(403, "reauthentication_required")
        : failure(403, "personal_target_pii_export_forbidden");
    }
    return failure(503, "personal_target_pii_export_unavailable");
  }
}

function isRecentPasswordAuthentication(
  authenticatedAt: number | undefined,
  now: Date,
): authenticatedAt is number {
  if (
    !Number.isSafeInteger(authenticatedAt) ||
    authenticatedAt === undefined ||
    authenticatedAt < 0
  ) {
    return false;
  }
  const nowSeconds = now.getTime() / 1000;
  const ageSeconds = nowSeconds - authenticatedAt;
  return Number.isFinite(nowSeconds) &&
    ageSeconds >= -60 && ageSeconds < 15 * 60;
}

export type PersonalTargetPiiExportQuery = (
  text: string,
  values: readonly unknown[],
) => Promise<{readonly rows: readonly unknown[]}>;

export class PostgresPersonalTargetPiiExportStore
implements PersonalTargetPiiExportStore {
  constructor(private readonly query: PersonalTargetPiiExportQuery) {}

  async prepare(
    identity: VerifiedIdentity,
    projectId: string,
    passwordAuthenticatedAtUnixSeconds: number,
  ): Promise<Buffer> {
    try {
      const result = await this.query(
        `SELECT app_data.prepare_personal_target_pii_export_v1(
           $1::text, $2::text, $3::uuid,
           pg_catalog.to_timestamp($4::double precision)
         ) AS export_bytes`,
        [
          identity.issuer,
          identity.subject,
          projectId,
          passwordAuthenticatedAtUnixSeconds,
        ],
      );
      if (result.rows.length !== 1) throw invalidResult();
      const row = result.rows[0];
      if (typeof row !== "object" || row === null || Array.isArray(row)) {
        throw invalidResult();
      }
      const bytes = (row as Record<string, unknown>).export_bytes;
      if (!Buffer.isBuffer(bytes)) throw invalidResult();
      return bytes;
    } catch (error) {
      throw mapPostgresError(error);
    }
  }
}

export class PersonalTargetPiiExportStoreError extends Error {
  constructor(readonly code: "reauthentication_required" | "forbidden") {
    super(code);
    this.name = "PersonalTargetPiiExportStoreError";
  }
}

function mapPostgresError(error: unknown): Error {
  const code = field(error, "code");
  const message = field(error, "message");
  if (
    code === "22023" &&
    message === "invalid personal target PII export authentication evidence"
  ) {
    return new PersonalTargetPiiExportStoreError("reauthentication_required");
  }
  if (
    code === "42501" &&
    message === "personal target PII export scope is forbidden"
  ) {
    return new PersonalTargetPiiExportStoreError("forbidden");
  }
  return error instanceof Error ? error : new Error(String(error));
}

function field(value: unknown, name: string): string {
  return typeof value === "object" && value !== null && name in value
    ? String((value as Record<string, unknown>)[name])
    : "";
}

function invalidResult(): Error {
  return new Error("invalid personal target PII export result");
}

function failure(
  status: number,
  code: string,
): PersonalTargetPiiExportHttpResult {
  return {status, body: {error: {code}}};
}
