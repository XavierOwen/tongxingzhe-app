import { bearerToken } from "./authorization.js";
import {
  IdentityVerificationError,
  type IdentityVerifier,
} from "./identity.js";
import {
  parseQuestionnaireVersion,
  QuestionnaireContractError,
  serializeQuestionnaireVersion,
  type QuestionnaireVersion,
} from "./questionnaire-validator.js";
import type {
  SessionContext,
  SessionContextStore,
} from "./session-context.js";

export const questionnaireManagementCapability =
  "manage_analysis_definitions";

export interface QuestionnairePublishedVersionSummary {
  readonly id: string;
  readonly versionNumber: number;
  readonly isCurrent: boolean;
  readonly publishedAt: string;
  readonly publishedByAppUserId: string | null;
  readonly publicationNote: string | null;
}

export interface QuestionnaireDesignDraft {
  readonly id: string;
  readonly projectId: string;
  readonly sourceVersionId: string | null;
  readonly revision: number;
  readonly updatedAt: string;
  readonly definition: QuestionnaireVersion;
}

export interface QuestionnaireAdministrationSnapshot {
  readonly currentVersionId: string;
  readonly versions: readonly QuestionnairePublishedVersionSummary[];
  readonly drafts: readonly QuestionnaireDesignDraft[];
}

export interface QuestionnairePublication {
  readonly summary: QuestionnairePublishedVersionSummary;
  readonly version: QuestionnaireVersion;
}

export interface QuestionnaireAdministrationStore {
  list(context: SessionContext): Promise<QuestionnaireAdministrationSnapshot>;
  createDraft(
    context: SessionContext,
    sourceVersionId: string | null,
  ): Promise<QuestionnaireDesignDraft>;
  readDraft(
    context: SessionContext,
    draftId: string,
  ): Promise<QuestionnaireDesignDraft | null>;
  updateDraft(
    context: SessionContext,
    draftId: string,
    expectedRevision: number,
    definition: QuestionnaireVersion,
  ): Promise<QuestionnaireDesignDraft>;
  publishDraft(
    context: SessionContext,
    draftId: string,
    expectedRevision: number,
    requestId: string,
    publicationNote: string,
  ): Promise<QuestionnairePublication>;
}

export interface QuestionnaireAdministrationDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly contextStore: SessionContextStore;
  readonly administrationStore: QuestionnaireAdministrationStore;
}

export interface QuestionnaireAdministrationHttpResult {
  readonly status: number;
  readonly body: Readonly<Record<string, unknown>>;
}

export async function listQuestionnaireAdministration(
  authorization: string | undefined,
  dependencies: QuestionnaireAdministrationDependencies,
): Promise<QuestionnaireAdministrationHttpResult> {
  const context = await authorizedContext(authorization, dependencies);
  if (!(context instanceof AuthorizedContext)) return context;
  try {
    const snapshot = await dependencies.administrationStore.list(context.value);
    return { status: 200, body: serializeSnapshot(snapshot) };
  } catch (error) {
    return storeFailure(error);
  }
}

export async function createQuestionnaireDraft(
  authorization: string | undefined,
  body: unknown,
  dependencies: QuestionnaireAdministrationDependencies,
): Promise<QuestionnaireAdministrationHttpResult> {
  const sourceVersionId = nullableUuidField(body, "source_version_id");
  if (sourceVersionId === invalidField) {
    return failure(400, "invalid_source_version_id");
  }
  const context = await authorizedContext(authorization, dependencies);
  if (!(context instanceof AuthorizedContext)) return context;
  try {
    const draft = await dependencies.administrationStore.createDraft(
      context.value,
      sourceVersionId,
    );
    return { status: 201, body: { draft: serializeDraft(draft) } };
  } catch (error) {
    return storeFailure(error);
  }
}

export async function readQuestionnaireDraft(
  authorization: string | undefined,
  draftId: string,
  dependencies: QuestionnaireAdministrationDependencies,
): Promise<QuestionnaireAdministrationHttpResult> {
  if (!uuidPattern.test(draftId)) return failure(400, "invalid_draft_id");
  const context = await authorizedContext(authorization, dependencies);
  if (!(context instanceof AuthorizedContext)) return context;
  try {
    const draft = await dependencies.administrationStore.readDraft(
      context.value,
      draftId,
    );
    return draft === null
      ? failure(404, "questionnaire_draft_not_found")
      : { status: 200, body: { draft: serializeDraft(draft) } };
  } catch (error) {
    return storeFailure(error);
  }
}

export async function updateQuestionnaireDraft(
  authorization: string | undefined,
  draftId: string,
  body: unknown,
  dependencies: QuestionnaireAdministrationDependencies,
): Promise<QuestionnaireAdministrationHttpResult> {
  if (!uuidPattern.test(draftId)) return failure(400, "invalid_draft_id");
  const root = record(body);
  const expectedRevision = positiveIntegerField(root, "expected_revision");
  if (expectedRevision === null || !("definition" in root)) {
    return failure(400, "invalid_questionnaire_draft_update");
  }
  const context = await authorizedContext(authorization, dependencies);
  if (!(context instanceof AuthorizedContext)) return context;
  let definition: QuestionnaireVersion;
  try {
    definition = parseDraftDefinition(
      root.definition,
      draftId,
      context.value.current.project.id,
      expectedRevision,
    );
  } catch (error) {
    return contractFailure(error);
  }
  try {
    const draft = await dependencies.administrationStore.updateDraft(
      context.value,
      draftId,
      expectedRevision,
      definition,
    );
    return { status: 200, body: { draft: serializeDraft(draft) } };
  } catch (error) {
    return storeFailure(error);
  }
}

export async function publishQuestionnaireDraft(
  authorization: string | undefined,
  draftId: string,
  body: unknown,
  dependencies: QuestionnaireAdministrationDependencies,
): Promise<QuestionnaireAdministrationHttpResult> {
  if (!uuidPattern.test(draftId)) return failure(400, "invalid_draft_id");
  const root = record(body);
  const expectedRevision = positiveIntegerField(root, "expected_revision");
  const requestId = stringField(root, "request_id");
  const publicationNote = stringField(root, "publication_note")?.trim();
  if (
    expectedRevision === null ||
    requestId === null ||
    requestId.trim().length < 1 ||
    requestId.trim().length > 120 ||
    publicationNote === undefined ||
    publicationNote.length < 1 ||
    publicationNote.length > 500
  ) {
    return failure(400, "invalid_questionnaire_publication");
  }
  const context = await authorizedContext(authorization, dependencies);
  if (!(context instanceof AuthorizedContext)) return context;
  try {
    const currentDraft = await dependencies.administrationStore.readDraft(
      context.value,
      draftId,
    );
    if (currentDraft === null) {
      return failure(404, "questionnaire_draft_not_found");
    }
    if (currentDraft.revision !== expectedRevision) {
      return failure(409, "questionnaire_draft_revision_conflict");
    }
    if (currentDraft.definition.questions.length === 0) {
      return failure(400, "questionnaire_questions_required");
    }
    parseQuestionnaireVersion(
      serializeQuestionnaireVersion(currentDraft.definition),
    );
    const publication = await dependencies.administrationStore.publishDraft(
      context.value,
      draftId,
      expectedRevision,
      requestId.trim(),
      publicationNote,
    );
    return {
      status: 200,
      body: { publication: serializePublication(publication) },
    };
  } catch (error) {
    if (error instanceof QuestionnaireContractError) {
      return contractFailure(error);
    }
    return storeFailure(error);
  }
}

export type QuestionnaireAdministrationQuery = (
  text: string,
  values: readonly unknown[],
) => Promise<{ readonly rows: readonly unknown[] }>;

export class PostgresQuestionnaireAdministrationStore
  implements QuestionnaireAdministrationStore {
  constructor(private readonly query: QuestionnaireAdministrationQuery) {}

  async list(
    context: SessionContext,
  ): Promise<QuestionnaireAdministrationSnapshot> {
    const value = await this.oneJson(
      `SELECT administration
       FROM app_data.list_questionnaire_administration(
         $1::uuid, $2::uuid, $3::uuid
       )`,
      contextValues(context),
      "administration",
    );
    return parseSnapshot(value);
  }

  async createDraft(
    context: SessionContext,
    sourceVersionId: string | null,
  ): Promise<QuestionnaireDesignDraft> {
    const value = await this.oneJson(
      `SELECT draft
       FROM app_data.create_questionnaire_draft(
         $1::uuid, $2::uuid, $3::uuid, $4::uuid
       )`,
      [...contextValues(context), sourceVersionId],
      "draft",
    );
    return parseDraft(value);
  }

  async readDraft(
    context: SessionContext,
    draftId: string,
  ): Promise<QuestionnaireDesignDraft | null> {
    try {
      const result = await this.query(
        `SELECT draft
         FROM app_data.read_questionnaire_draft(
           $1::uuid, $2::uuid, $3::uuid, $4::uuid
         )`,
        [...contextValues(context), draftId],
      );
      if (result.rows.length === 0) return null;
      return parseDraft(rowField(result.rows[0], "draft"));
    } catch (error) {
      throw mapPostgresError(error);
    }
  }

  async updateDraft(
    context: SessionContext,
    draftId: string,
    expectedRevision: number,
    definition: QuestionnaireVersion,
  ): Promise<QuestionnaireDesignDraft> {
    const serialized = serializeQuestionnaireVersion(definition);
    const value = await this.oneJson(
      `SELECT draft
       FROM app_data.update_questionnaire_draft(
         $1::uuid, $2::uuid, $3::uuid, $4::uuid, $5::integer, $6::jsonb
       )`,
      [
        ...contextValues(context),
        draftId,
        expectedRevision,
        JSON.stringify(serialized.questions),
      ],
      "draft",
    );
    return parseDraft(value);
  }

  async publishDraft(
    context: SessionContext,
    draftId: string,
    expectedRevision: number,
    requestId: string,
    publicationNote: string,
  ): Promise<QuestionnairePublication> {
    const value = await this.oneJson(
      `SELECT publication
       FROM app_data.publish_questionnaire_draft(
         $1::uuid, $2::uuid, $3::uuid, $4::uuid,
         $5::integer, $6::text, $7::text
       )`,
      [
        ...contextValues(context),
        draftId,
        expectedRevision,
        requestId,
        publicationNote,
      ],
      "publication",
    );
    return parsePublication(value);
  }

  private async oneJson(
    sql: string,
    values: readonly unknown[],
    field: string,
  ): Promise<unknown> {
    try {
      const result = await this.query(sql, values);
      if (result.rows.length !== 1) {
        throw new Error(`${field} function must return exactly one row`);
      }
      return rowField(result.rows[0], field);
    } catch (error) {
      throw mapPostgresError(error);
    }
  }
}

export class QuestionnaireAdministrationStoreError extends Error {
  constructor(readonly code: string) {
    super(code);
    this.name = "QuestionnaireAdministrationStoreError";
  }
}

function parseDraftDefinition(
  value: unknown,
  draftId: string,
  projectId: string,
  revision: number,
): QuestionnaireVersion {
  const root = record(value);
  return parseQuestionnaireVersion({
    questionnaire_version_id: draftId,
    project_id: projectId,
    version_number: revision,
    status: "published",
    questions: root.questions,
  });
}

async function authorizedContext(
  authorization: string | undefined,
  dependencies: QuestionnaireAdministrationDependencies,
): Promise<AuthorizedContext | QuestionnaireAdministrationHttpResult> {
  const accessToken = bearerToken(authorization);
  if (accessToken === null) return failure(401, "unauthenticated");
  try {
    const identity = await dependencies.identityVerifier.verify(accessToken);
    const context = await dependencies.contextStore.loadOrCreate(identity);
    return context.capabilities.includes(questionnaireManagementCapability)
      ? new AuthorizedContext(context)
      : failure(403, "capability_forbidden");
  } catch (error) {
    return error instanceof IdentityVerificationError
      ? failure(401, "unauthenticated")
      : failure(503, "questionnaire_administration_unavailable");
  }
}

class AuthorizedContext {
  constructor(readonly value: SessionContext) {}
}

function serializeSnapshot(
  value: QuestionnaireAdministrationSnapshot,
): Readonly<Record<string, unknown>> {
  return {
    current_version_id: value.currentVersionId,
    versions: value.versions.map(serializeSummary),
    drafts: value.drafts.map(serializeDraft),
  };
}

function serializeDraft(
  value: QuestionnaireDesignDraft,
): Readonly<Record<string, unknown>> {
  const serialized = serializeQuestionnaireVersion(value.definition);
  return {
    draft_id: value.id,
    project_id: value.projectId,
    source_version_id: value.sourceVersionId,
    revision: value.revision,
    updated_at: value.updatedAt,
    definition: { questions: serialized.questions },
  };
}

function serializeSummary(
  value: QuestionnairePublishedVersionSummary,
): Readonly<Record<string, unknown>> {
  return {
    questionnaire_version_id: value.id,
    version_number: value.versionNumber,
    is_current: value.isCurrent,
    published_at: value.publishedAt,
    published_by_app_user_id: value.publishedByAppUserId,
    publication_note: value.publicationNote,
  };
}

function serializePublication(
  value: QuestionnairePublication,
): Readonly<Record<string, unknown>> {
  return {
    summary: serializeSummary(value.summary),
    questionnaire: serializeQuestionnaireVersion(value.version),
  };
}

function parseSnapshot(value: unknown): QuestionnaireAdministrationSnapshot {
  const root = record(value);
  return {
    currentVersionId: requiredString(root.current_version_id),
    versions: requiredArray(root.versions).map(parseSummary),
    drafts: requiredArray(root.drafts).map(parseDraft),
  };
}

function parseDraft(value: unknown): QuestionnaireDesignDraft {
  const root = record(value);
  const id = requiredString(root.draft_id);
  const projectId = requiredString(root.project_id);
  const revision = requiredPositiveInteger(root.revision);
  const definition = record(root.definition);
  return {
    id,
    projectId,
    sourceVersionId: optionalString(root.source_version_id),
    revision,
    updatedAt: requiredString(root.updated_at),
    definition: parseDraftDefinition(definition, id, projectId, revision),
  };
}

function parseSummary(value: unknown): QuestionnairePublishedVersionSummary {
  const root = record(value);
  return {
    id: requiredString(root.questionnaire_version_id),
    versionNumber: requiredPositiveInteger(root.version_number),
    isCurrent: root.is_current === true,
    publishedAt: requiredString(root.published_at),
    publishedByAppUserId: optionalString(root.published_by_app_user_id),
    publicationNote: optionalString(root.publication_note),
  };
}

function parsePublication(value: unknown): QuestionnairePublication {
  const root = record(value);
  return {
    summary: parseSummary(root.summary),
    version: parseQuestionnaireVersion(root.questionnaire),
  };
}

function contextValues(context: SessionContext): readonly string[] {
  return [
    context.appUserId,
    context.current.workspace.id,
    context.current.project.id,
  ];
}

function storeFailure(error: unknown): QuestionnaireAdministrationHttpResult {
  if (error instanceof QuestionnaireAdministrationStoreError) {
    switch (error.code) {
      case "forbidden":
        return failure(403, "capability_forbidden");
      case "not_found":
        return failure(404, "questionnaire_draft_not_found");
      case "revision_conflict":
        return failure(409, "questionnaire_draft_revision_conflict");
      case "invalid_definition":
        return failure(400, "invalid_questionnaire_definition");
    }
  }
  return failure(503, "questionnaire_administration_unavailable");
}

function contractFailure(error: unknown): QuestionnaireAdministrationHttpResult {
  return error instanceof QuestionnaireContractError
    ? {
      status: 400,
      body: {
        error: {
          code: "invalid_questionnaire_definition",
          reason: error.code,
        },
      },
    }
    : failure(400, "invalid_questionnaire_definition");
}

function mapPostgresError(error: unknown): Error {
  const code = typeof error === "object" && error !== null && "code" in error
    ? (error as {code?: unknown}).code
    : null;
  if (code === "42501") {
    return new QuestionnaireAdministrationStoreError("forbidden");
  }
  if (code === "P0002") {
    return new QuestionnaireAdministrationStoreError("not_found");
  }
  if (code === "40001" || code === "23505") {
    return new QuestionnaireAdministrationStoreError("revision_conflict");
  }
  if (code === "22023") {
    return new QuestionnaireAdministrationStoreError("invalid_definition");
  }
  return error instanceof Error ? error : new Error("database request failed");
}

const invalidField = Symbol("invalid-field");
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function nullableUuidField(
  value: unknown,
  field: string,
): string | null | typeof invalidField {
  const root = record(value);
  const candidate = root[field];
  if (candidate === undefined || candidate === null) return null;
  return typeof candidate === "string" && uuidPattern.test(candidate)
    ? candidate
    : invalidField;
}

function positiveIntegerField(
  value: Readonly<Record<string, unknown>>,
  field: string,
): number | null {
  const candidate = value[field];
  return typeof candidate === "number" &&
      Number.isInteger(candidate) && candidate > 0
    ? candidate
    : null;
}

function stringField(
  value: Readonly<Record<string, unknown>>,
  field: string,
): string | null {
  return typeof value[field] === "string" ? value[field] : null;
}

function record(value: unknown): Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function rowField(value: unknown, field: string): unknown {
  const root = record(value);
  if (!(field in root)) throw new Error(`database row omitted ${field}`);
  return root[field];
}

function requiredArray(value: unknown): readonly unknown[] {
  if (!Array.isArray(value)) throw new Error("database returned invalid array");
  return value;
}

function requiredString(value: unknown): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error("database returned invalid string");
  }
  return value;
}

function optionalString(value: unknown): string | null {
  return value === null || value === undefined ? null : requiredString(value);
}

function requiredPositiveInteger(value: unknown): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 1) {
    throw new Error("database returned invalid positive integer");
  }
  return value;
}

function failure(
  status: number,
  code: string,
): QuestionnaireAdministrationHttpResult {
  return { status, body: { error: { code } } };
}
