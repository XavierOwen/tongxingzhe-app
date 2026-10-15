import {bearerToken} from "./authorization.js";
import {
  IdentityVerificationError,
  type IdentityVerifier,
  type VerifiedIdentity,
} from "./identity.js";

export type PersonalTargetMergeProjection = Readonly<Record<string, unknown>>;

export interface PersonalTargetMergeProjectionStore {
  read(
    identity: VerifiedIdentity,
    projectId: string,
    generationId: string,
  ): Promise<PersonalTargetMergeProjection>;
}

export interface PersonalTargetMergeProjectionRequest {
  readonly authorization: string | undefined;
  readonly projectId: string;
  readonly generationId: string;
  readonly hasQuery: boolean;
  readonly hasBody: boolean;
}

export interface PersonalTargetMergeProjectionDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly projectionStore?: PersonalTargetMergeProjectionStore;
}

export interface PersonalTargetMergeProjectionHttpResult {
  readonly status: number;
  readonly body: Readonly<Record<string, unknown>>;
}

export async function readPersonalTargetMergeProjection(
  request: PersonalTargetMergeProjectionRequest,
  dependencies: PersonalTargetMergeProjectionDependencies,
): Promise<PersonalTargetMergeProjectionHttpResult> {
  const accessToken = bearerToken(request.authorization);
  if (accessToken === null) return failure(401, "unauthenticated");

  let identity: VerifiedIdentity;
  try {
    identity = await dependencies.identityVerifier.verify(accessToken);
  } catch (error) {
    return error instanceof IdentityVerificationError &&
        error.category === "unauthenticated"
      ? failure(401, "unauthenticated")
      : failure(503, "unavailable");
  }

  if (
    !uuidPattern.test(request.projectId) ||
    !uuidPattern.test(request.generationId) ||
    request.hasQuery || request.hasBody
  ) {
    return failure(400, "invalid_request");
  }
  if (dependencies.projectionStore === undefined) {
    return failure(503, "unavailable");
  }

  try {
    const projection = await dependencies.projectionStore.read(
      identity, request.projectId, request.generationId,
    );
    return {status: 200, body: {projection}};
  } catch (error) {
    return error instanceof PersonalTargetMergeProjectionStoreError &&
        error.code === "forbidden"
      ? failure(403, "forbidden")
      : failure(503, "unavailable");
  }
}

export type PersonalTargetMergeProjectionQuery = (
  text: string,
  values: readonly unknown[],
) => Promise<{readonly rows: readonly unknown[]}>;

export class PostgresPersonalTargetMergeProjectionStore
implements PersonalTargetMergeProjectionStore {
  constructor(private readonly query: PersonalTargetMergeProjectionQuery) {}

  async read(
    identity: VerifiedIdentity,
    projectId: string,
    generationId: string,
  ): Promise<PersonalTargetMergeProjection> {
    const {issuer, subject} = identity;
    try {
      const contextResult = await this.query(
        `SELECT app_data.read_personal_merge_projection_context_v1(
           $1::text, $2::text, $3::uuid
         ) AS context_result`,
        [issuer, subject, projectId],
      );
      const context = singleResult(contextResult.rows, "context_result");
      exactKeys(context, [
        "app_user_id", "workspace_id", "workspace_kind", "project_id", "capabilities",
      ]);
      uuid(context.app_user_id);
      const workspaceId = uuid(context.workspace_id);
      if (context.workspace_kind !== "personal" ||
          uuid(context.project_id) !== projectId.toLowerCase() ||
          !Array.isArray(context.capabilities) ||
          context.capabilities.some((capability) => typeof capability !== "string")) {
        throw unavailable();
      }
      if (!context.capabilities.includes("view_assigned_target_pii") ||
          !context.capabilities.includes("manage_assigned_target_merges")) {
        throw new PersonalTargetMergeProjectionStoreError("forbidden");
      }

      // The eligibility result is not a credential; the bridge rechecks the same raw identity.
      const result = await this.query(
        `SELECT app_data.read_personal_known_source_merge_projection_v1(
           $1::text, $2::text, $3::uuid, $4::uuid
         ) AS projection`,
        [issuer, subject, projectId, generationId],
      );
      return parseProjection(
        singleResult(result.rows, "projection"), projectId, generationId, workspaceId,
      );
    } catch (error) {
      if (error instanceof PersonalTargetMergeProjectionStoreError) throw error;
      if (typeof error === "object" && error !== null &&
          "code" in error && error.code === "42501") {
        throw new PersonalTargetMergeProjectionStoreError("forbidden");
      }
      throw unavailable();
    }
  }
}

export class PersonalTargetMergeProjectionStoreError extends Error {
  constructor(readonly code: "forbidden" | "unavailable") {
    super(code);
    this.name = "PersonalTargetMergeProjectionStoreError";
  }
}

function parseProjection(
  root: Record<string, unknown>,
  projectId: string,
  generationId: string,
  workspaceId: string,
): PersonalTargetMergeProjection {
  exactKeys(root, [
    "generation_id", "workspace_id", "project_id", "target_type", "retained_target_id",
    "display_name", "phone", "email", "display_name_source_target_id",
    "phone_source_target_id", "email_source_target_id", "review_due_at_utc", "sources",
  ]);
  if (uuid(root.project_id) !== projectId.toLowerCase() ||
      uuid(root.generation_id) !== generationId.toLowerCase() ||
      uuid(root.workspace_id) !== workspaceId ||
      (root.target_type !== "person" && root.target_type !== "institution") ||
      !Array.isArray(root.sources) || root.sources.length !== 2) {
    throw unavailable();
  }
  const sources = root.sources.map((source) => parseSource(source, root.target_type, projectId));
  const first = sources[0]!;
  const second = sources[1]!;
  if (first.id >= second.id ||
      !sources.some((source) => source.id === uuid(root.retained_target_id)) ||
      dueTimestamp(root.review_due_at_utc) !== (first.due < second.due ? first.due : second.due)) {
    throw unavailable();
  }
  for (const field of ["display_name", "phone", "email"] as const) {
    const sourceId = uuid(root[`${field}_source_target_id`]);
    const source = sources.find((candidate) => candidate.id === sourceId);
    if (source === undefined || root[field] !== source.profile[field]) throw unavailable();
  }
  return root;
}

function parseSource(value: unknown, targetType: unknown, projectId: string) {
  const source = object(value);
  exactKeys(source, [
    "target_id", "profile", "review_due_at_utc", "project_relationship",
    "contact_links", "institution_relationships",
  ]);
  const id = uuid(source.target_id);
  const due = dueTimestamp(source.review_due_at_utc);
  const profile = object(source.profile);
  exactKeys(profile, ["target_id", "target_type", "display_name", "phone", "email", "created_at"]);
  if (uuid(profile.target_id) !== id || profile.target_type !== targetType) throw unavailable();
  text(profile.display_name, 200);
  nullableText(profile.phone, 80);
  nullableText(profile.email, 320);
  timestamp(profile.created_at);

  if (source.project_relationship !== null) {
    parseProjectRelationship(source.project_relationship, id, projectId);
  }
  if (!Array.isArray(source.contact_links) || !Array.isArray(source.institution_relationships)) {
    throw unavailable();
  }
  for (const link of source.contact_links) parseContactLink(link, id);
  for (const relation of source.institution_relationships) {
    parseInstitutionRelationship(relation, id, targetType);
  }
  return {id, due, profile};
}

function parseProjectRelationship(value: unknown, targetId: string, projectId: string): void {
  const relationship = object(value);
  exactKeys(relationship, [
    "target_id", "project_id", "stage", "display_stage", "lifecycle_status",
    "follow_up_note", "revision_number", "updated_at", "stage_aliases", "history",
  ]);
  if (uuid(relationship.target_id) !== targetId ||
      uuid(relationship.project_id) !== projectId.toLowerCase() ||
      !level(relationship.stage) || relationship.display_stage !== Number(relationship.stage) * 2 ||
      !oneOf(relationship.lifecycle_status, ["active", "paused", "ended"]) ||
      !Array.isArray(relationship.history) || relationship.history.length !== 0 ||
      !Array.isArray(relationship.stage_aliases) || relationship.stage_aliases.length !== 5) {
    throw unavailable();
  }
  positiveInteger(relationship.revision_number);
  nullableText(relationship.follow_up_note, 4000);
  timestamp(relationship.updated_at);
  for (let stage = 0; stage < 5; stage += 1) {
    const alias = object(relationship.stage_aliases[stage]);
    exactKeys(alias, ["stage", "display_stage", "display_name"]);
    if (alias.stage !== stage || alias.display_stage !== stage * 2) throw unavailable();
    nullableText(alias.display_name, 80);
  }
}

function parseContactLink(value: unknown, targetId: string): void {
  const link = object(value);
  exactKeys(link, [
    "contact_id", "revision_number", "promotion_target_id", "response_level", "follow_up_consent",
    "institution_representative_confirmed", "confirmed_project_entry", "merge_generation_id",
  ]);
  if (typeof link.contact_id !== "string" ||
      uuid(link.promotion_target_id) !== targetId ||
      (link.response_level !== null && !level(link.response_level)) ||
      !oneOf(link.follow_up_consent, ["yes", "no", "unknown", "refused", "not_applicable"]) ||
      typeof link.institution_representative_confirmed !== "boolean" ||
      typeof link.confirmed_project_entry !== "boolean") {
    throw unavailable();
  }
  positiveInteger(link.revision_number);
  if (link.merge_generation_id !== null) uuid(link.merge_generation_id);
}

function parseInstitutionRelationship(value: unknown, targetId: string, targetType: unknown): void {
  const relationship = object(value);
  exactKeys(relationship, [
    "relationship_id", "person_target_id", "institution_target_id", "relationship_kind",
    "role_description", "started_at", "ended_at", "status", "revision_number",
  ]);
  uuid(relationship.relationship_id);
  const personId = uuid(relationship.person_target_id);
  const institutionId = uuid(relationship.institution_target_id);
  if (personId === institutionId ||
      (targetType === "person" ? personId : institutionId) !== targetId ||
      !oneOf(relationship.relationship_kind, ["employment_representative", "ownership_governance", "learning_participation",
        "membership_affiliation", "partnership_service", "other"]) ||
      relationship.status !== (relationship.ended_at === null ? "active" : "ended") ||
      (relationship.relationship_kind === "other" && relationship.role_description === null)) {
    throw unavailable();
  }
  positiveInteger(relationship.revision_number);
  nullableText(relationship.role_description, 500);
  const startedAt = timestamp(relationship.started_at);
  if (relationship.ended_at !== null) {
    if (timestamp(relationship.ended_at) < startedAt) {
      throw unavailable();
    }
  }
}

function singleResult(rows: readonly unknown[], field: string): Record<string, unknown> {
  if (rows.length !== 1) throw unavailable();
  const row = object(rows[0]);
  exactKeys(row, [field]);
  return object(row[field]);
}

function object(value: unknown): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) throw unavailable();
  return value as Record<string, unknown>;
}

function exactKeys(value: Record<string, unknown>, expected: readonly string[]): void {
  const keys = Object.keys(value);
  if (keys.length !== expected.length || expected.some((key) => !Object.hasOwn(value, key))) {
    throw unavailable();
  }
}

function uuid(value: unknown): string {
  if (typeof value !== "string" || !uuidPattern.test(value)) throw unavailable();
  return value.toLowerCase();
}

function text(value: unknown, maxLength: number): void {
  if (typeof value !== "string") throw unavailable();
  const length = [...value.replace(/^ +| +$/g, "")].length;
  if (length === 0 || length > maxLength) throw unavailable();
}

function nullableText(value: unknown, maxLength: number): void {
  if (value !== null) text(value, maxLength);
}

function positiveInteger(value: unknown): void {
  if (!Number.isSafeInteger(value) || Number(value) < 1) throw unavailable();
}

function level(value: unknown): boolean {
  return Number.isSafeInteger(value) && Number(value) >= 0 && Number(value) <= 4;
}

function oneOf(value: unknown, allowed: readonly string[]): boolean {
  return typeof value === "string" && allowed.includes(value);
}

function timestamp(value: unknown): string {
  if (typeof value !== "string" || value.startsWith("0000-")) {
    throw unavailable();
  }
  const match = timestampPattern.exec(value);
  if (match === null) throw unavailable();
  const local = new Date(`${value.slice(0, 19)}Z`);
  if (!Number.isFinite(Date.parse(value)) || !Number.isFinite(local.getTime()) ||
      local.toISOString().slice(0, 19) !== value.slice(0, 19)) {
    throw unavailable();
  }
  const seconds = Date.parse(value.replace(/\.\d+(?=Z|[+-])/, ""));
  return `${new Date(seconds).toISOString().slice(0, 19)}.${(match[1] ?? "").padEnd(6, "0")}Z`;
}

function dueTimestamp(value: unknown): string {
  if (typeof value !== "string" || !duePattern.test(value)) throw unavailable();
  timestamp(value);
  return value;
}

function unavailable(): PersonalTargetMergeProjectionStoreError {
  return new PersonalTargetMergeProjectionStoreError("unavailable");
}

function failure(status: number, suffix: string): PersonalTargetMergeProjectionHttpResult {
  return {status, body: {error: {code: `personal_target_merge_projection_${suffix}`}}};
}

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const timestampPattern = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.(\d{1,6}))?(?:Z|[+-]\d{2}:\d{2})$/;
const duePattern = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$/;
