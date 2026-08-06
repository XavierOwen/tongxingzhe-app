import { bearerToken } from "./authorization.js";
import {
  IdentityVerificationError,
  type IdentityVerifier,
} from "./identity.js";
import {
  parseQuestionnaireVersion,
  serializeQuestionnaireVersion,
  type QuestionnaireVersion,
} from "./questionnaire-validator.js";
import type {
  SessionContext,
  SessionContextStore,
} from "./session-context.js";

export interface QuestionnaireStore {
  readPublishedVersion(
    context: SessionContext,
    versionId: string,
  ): Promise<QuestionnaireVersion | null>;
}

export interface QuestionnaireHttpDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly contextStore: SessionContextStore;
  readonly questionnaireStore: QuestionnaireStore;
}

export interface QuestionnaireHttpResult {
  readonly status: number;
  readonly body: Readonly<Record<string, unknown>>;
}

/** Read one immutable definition only inside the trusted current project. */
export async function readPublishedQuestionnaire(
  authorization: string | undefined,
  versionId: string,
  dependencies: QuestionnaireHttpDependencies,
): Promise<QuestionnaireHttpResult> {
  const accessToken = bearerToken(authorization);
  if (accessToken === null) return failure(401, "unauthenticated");
  if (!uuidPattern.test(versionId)) {
    return failure(400, "invalid_questionnaire_version_id");
  }
  try {
    const identity = await dependencies.identityVerifier.verify(accessToken);
    const context = await dependencies.contextStore.loadOrCreate(identity);
    if (!context.capabilities.includes("record_contact")) {
      return failure(403, "capability_forbidden");
    }
    const version = await dependencies.questionnaireStore.readPublishedVersion(
      context,
      versionId,
    );
    if (version === null) return failure(404, "questionnaire_not_found");
    if (
      version.id !== versionId ||
      version.projectId !== context.current.project.id
    ) {
      return failure(404, "questionnaire_not_found");
    }
    return {
      status: 200,
      body: { questionnaire: serializeQuestionnaireVersion(version) },
    };
  } catch (error) {
    if (error instanceof IdentityVerificationError) {
      return failure(401, "unauthenticated");
    }
    return failure(503, "questionnaire_unavailable");
  }
}

export type QuestionnaireQuery = (
  text: string,
  values: readonly unknown[],
) => Promise<{ readonly rows: readonly unknown[] }>;

export class PostgresQuestionnaireStore implements QuestionnaireStore {
  constructor(private readonly query: QuestionnaireQuery) {}

  async readPublishedVersion(
    context: SessionContext,
    versionId: string,
  ): Promise<QuestionnaireVersion | null> {
    const result = await this.query(
      `SELECT questionnaire_definition
       FROM app_data.read_published_questionnaire(
         $1::uuid,
         $2::uuid,
         $3::uuid,
         $4::uuid
       )`,
      [
        context.appUserId,
        context.current.workspace.id,
        context.current.project.id,
        versionId,
      ],
    );
    if (result.rows.length === 0) return null;
    if (result.rows.length !== 1) {
      throw new Error("Questionnaire reader returned more than one row");
    }
    const row = result.rows[0];
    if (typeof row !== "object" || row === null) {
      throw new Error("Questionnaire reader returned an invalid row");
    }
    return parseQuestionnaireVersion(
      (row as { questionnaire_definition?: unknown }).questionnaire_definition,
    );
  }
}

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function failure(status: number, code: string): QuestionnaireHttpResult {
  return { status, body: { error: { code } } };
}
