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
      const workspaceId = parseMergeContext(contextResult.rows, projectId);

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

export type PersonalTargetMergeSplitPlan = Readonly<Record<string, unknown>>;
export type PersonalTargetMergeSplitPlanRequest = PersonalTargetMergeProjectionRequest;
export type PersonalTargetMergeSplitPlanHttpResult = PersonalTargetMergeProjectionHttpResult;
export type PersonalTargetMergeSplitPlanQuery = PersonalTargetMergeProjectionQuery;

export interface PersonalTargetMergeSplitPlanStore {
  read(identity: VerifiedIdentity, projectId: string, generationId: string): Promise<PersonalTargetMergeSplitPlan>;
}

export interface PersonalTargetMergeSplitPlanDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly splitPlanStore?: PersonalTargetMergeSplitPlanStore;
}

export async function readPersonalTargetMergeSplitPlan(
  request: PersonalTargetMergeSplitPlanRequest,
  dependencies: PersonalTargetMergeSplitPlanDependencies,
): Promise<PersonalTargetMergeSplitPlanHttpResult> {
  const accessToken = bearerToken(request.authorization);
  if (accessToken === null) return splitPlanFailure(401, "unauthenticated");
  let identity: VerifiedIdentity;
  try {
    identity = await dependencies.identityVerifier.verify(accessToken);
  } catch (error) {
    return error instanceof IdentityVerificationError && error.category === "unauthenticated"
      ? splitPlanFailure(401, "unauthenticated") : splitPlanFailure(503, "unavailable");
  }
  if (!uuidPattern.test(request.projectId) || !uuidPattern.test(request.generationId) ||
      request.hasQuery || request.hasBody) {
    return splitPlanFailure(400, "invalid_request");
  }
  if (dependencies.splitPlanStore === undefined) return splitPlanFailure(503, "unavailable");
  try {
    const splitPlan = await dependencies.splitPlanStore.read(identity, request.projectId, request.generationId);
    return {status: 200, body: {split_plan: splitPlan}};
  } catch (error) {
    return error instanceof PersonalTargetMergeSplitPlanStoreError && error.code === "forbidden"
      ? splitPlanFailure(403, "forbidden") : splitPlanFailure(503, "unavailable");
  }
}

export class PostgresPersonalTargetMergeSplitPlanStore implements PersonalTargetMergeSplitPlanStore {
  constructor(private readonly query: PersonalTargetMergeSplitPlanQuery) {}

  async read(identity: VerifiedIdentity, projectId: string, generationId: string): Promise<PersonalTargetMergeSplitPlan> {
    const {issuer, subject} = identity;
    try {
      const context = await this.query(
        `SELECT app_data.read_personal_merge_projection_context_v1(
           $1::text, $2::text, $3::uuid
         ) AS context_result`,
        [issuer, subject, projectId],
      );
      const workspaceId = parseMergeContext(context.rows, projectId);
      const result = await this.query(
        `SELECT app_data.read_personal_known_source_merge_split_plan_v1(
           $1::text, $2::text, $3::uuid, $4::uuid
         ) AS split_plan`,
        [issuer, subject, projectId, generationId],
      );
      return parseSplitPlan(singleResult(result.rows, "split_plan"), projectId, generationId, workspaceId);
    } catch (error) {
      const forbidden = error instanceof PersonalTargetMergeProjectionStoreError && error.code === "forbidden" ||
        typeof error === "object" && error !== null && "code" in error && error.code === "42501";
      throw new PersonalTargetMergeSplitPlanStoreError(forbidden ? "forbidden" : "unavailable");
    }
  }
}

export class PersonalTargetMergeSplitPlanStoreError extends Error {
  constructor(readonly code: "forbidden" | "unavailable") {
    super(code);
    this.name = "PersonalTargetMergeSplitPlanStoreError";
  }
}

export type PersonalTargetMergeDirectory = Readonly<Record<string, unknown>>;
export type PersonalTargetMergeDirectoryHttpResult = PersonalTargetMergeProjectionHttpResult;
export type PersonalTargetMergeDirectoryQuery = PersonalTargetMergeProjectionQuery;

export interface PersonalTargetMergeDirectoryStore {
  read(identity: VerifiedIdentity, projectId: string, afterGenerationId: string | null): Promise<PersonalTargetMergeDirectory>;
}

export interface PersonalTargetMergeDirectoryRequest {
  readonly authorization: string | undefined;
  readonly projectId: string;
  readonly query: URLSearchParams;
  readonly hasBody: boolean;
}

export interface PersonalTargetMergeDirectoryDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly directoryStore?: PersonalTargetMergeDirectoryStore;
}

export async function readPersonalTargetMergeDirectory(
  request: PersonalTargetMergeDirectoryRequest,
  dependencies: PersonalTargetMergeDirectoryDependencies,
): Promise<PersonalTargetMergeDirectoryHttpResult> {
  const accessToken = bearerToken(request.authorization);
  if (accessToken === null) return directoryFailure(401, "unauthenticated");
  let identity: VerifiedIdentity;
  try {
    identity = await dependencies.identityVerifier.verify(accessToken);
  } catch (error) {
    return error instanceof IdentityVerificationError && error.category === "unauthenticated"
      ? directoryFailure(401, "unauthenticated") : directoryFailure(503, "unavailable");
  }
  const parameters = [...request.query];
  const afterGenerationId = parameters[0]?.[1] ?? null;
  if (!directoryUuidPattern.test(request.projectId) || request.hasBody || parameters.length > 1 ||
      parameters.some(([key, value]) => key !== "after" || !directoryUuidPattern.test(value))) {
    return directoryFailure(400, "invalid_request");
  }
  if (dependencies.directoryStore === undefined) return directoryFailure(503, "unavailable");
  try {
    const directory = await dependencies.directoryStore.read(identity, request.projectId, afterGenerationId);
    return {status: 200, body: {directory}};
  } catch (error) {
    return error instanceof PersonalTargetMergeDirectoryStoreError && error.code === "forbidden"
      ? directoryFailure(403, "forbidden") : directoryFailure(503, "unavailable");
  }
}

export class PersonalTargetMergeDirectoryStoreError extends Error {
  constructor(readonly code: "forbidden" | "unavailable") {
    super(code);
    this.name = "PersonalTargetMergeDirectoryStoreError";
  }
}

export class PostgresPersonalTargetMergeDirectoryStore implements PersonalTargetMergeDirectoryStore {
  constructor(private readonly query: PersonalTargetMergeDirectoryQuery) {}

  async read(identity: VerifiedIdentity, projectId: string, afterGenerationId: string | null): Promise<PersonalTargetMergeDirectory> {
    const {issuer, subject} = identity;
    try {
      const context = await this.query(
        `SELECT app_data.read_personal_merge_projection_context_v1(
           $1::text, $2::text, $3::uuid
         ) AS context_result`,
        [issuer, subject, projectId],
      );
      const workspaceId = parseMergeContext(context.rows, projectId, directoryUuid);
      const result = await this.query(
        `SELECT app_data.read_personal_merge_directory_v1(
           $1::text, $2::text, $3::uuid, $4::uuid
         ) AS directory`,
        [issuer, subject, projectId, afterGenerationId],
      );
      return parseMergeDirectory(singleResult(result.rows, "directory"), projectId, workspaceId, afterGenerationId);
    } catch (error) {
      const forbidden = error instanceof PersonalTargetMergeProjectionStoreError && error.code === "forbidden" ||
        typeof error === "object" && error !== null && "code" in error && error.code === "42501";
      throw new PersonalTargetMergeDirectoryStoreError(forbidden ? "forbidden" : "unavailable");
    }
  }
}

function parseMergeDirectory(
  root: Record<string, unknown>, projectId: string, workspaceId: string, afterGenerationId: string | null,
): PersonalTargetMergeDirectory {
  exactKeys(root, ["workspace_id", "project_id", "items", "next_cursor"]);
  if (directoryUuid(root.workspace_id) !== workspaceId || directoryUuid(root.project_id) !== projectId.toLowerCase() ||
      !Array.isArray(root.items) || root.items.length > 20) throw unavailable();
  let previous = afterGenerationId === null ? null : directoryUuid(afterGenerationId);
  for (const value of root.items) {
    const item = object(value);
    exactKeys(item, ["generation_id", "target_type", "retained_target_id", "member_target_ids", "review_due_at_utc"]);
    const generation = directoryUuid(item.generation_id);
    if (previous !== null && generation <= previous || !oneOf(item.target_type, ["person", "institution"]) ||
        !Array.isArray(item.member_target_ids) || item.member_target_ids.length !== 2) throw unavailable();
    const members = item.member_target_ids.map(directoryUuid);
    if (members[0]! >= members[1]! || !members.includes(directoryUuid(item.retained_target_id))) throw unavailable();
    dueTimestamp(item.review_due_at_utc);
    previous = generation;
  }
  if (root.next_cursor !== null && (root.items.length !== 20 || directoryUuid(root.next_cursor) !== previous)) throw unavailable();
  return root;
}

function directoryFailure(status: number, suffix: string): PersonalTargetMergeDirectoryHttpResult {
  return {status, body: {error: {code: `personal_target_merge_directory_${suffix}`}}};
}

function parseMergeContext(rows: readonly unknown[], projectId: string, readUuid = uuid): string {
  const context = singleResult(rows, "context_result");
  exactKeys(context, ["app_user_id", "workspace_id", "workspace_kind", "project_id", "capabilities"]);
  readUuid(context.app_user_id);
  const workspaceId = readUuid(context.workspace_id);
  if (context.workspace_kind !== "personal" || readUuid(context.project_id) !== projectId.toLowerCase() ||
      !Array.isArray(context.capabilities) || context.capabilities.some((capability) => typeof capability !== "string")) {
    throw unavailable();
  }
  if (!context.capabilities.includes("view_assigned_target_pii") ||
      !context.capabilities.includes("manage_assigned_target_merges")) {
    throw new PersonalTargetMergeProjectionStoreError("forbidden");
  }
  return workspaceId;
}

function parseSplitPlan(
  root: Record<string, unknown>, projectId: string, generationId: string, workspaceId: string,
): PersonalTargetMergeSplitPlan {
  exactKeys(root, ["generation_id", "workspace_id", "project_id", "target_type", "member_target_ids",
    "review_due_at_utc", "fact_count", "fact_fingerprint", "facts"]);
  if (uuid(root.project_id) !== projectId.toLowerCase() || uuid(root.generation_id) !== generationId.toLowerCase() ||
      uuid(root.workspace_id) !== workspaceId || !oneOf(root.target_type, ["person", "institution"]) ||
      !Array.isArray(root.member_target_ids) || root.member_target_ids.length !== 2 ||
      !Number.isSafeInteger(root.fact_count) || Number(root.fact_count) < 0 ||
      !Array.isArray(root.facts) || root.fact_count !== root.facts.length ||
      typeof root.fact_fingerprint !== "string" || !/^[0-9a-f]{64}$/.test(root.fact_fingerprint)) {
    throw unavailable();
  }
  const members = root.member_target_ids.map(uuid);
  if (members[0]! >= members[1]!) throw unavailable();
  dueTimestamp(root.review_due_at_utc);
  const keys = new Set<string>();
  for (const value of root.facts) {
    const fact = object(value);
    exactKeys(fact, ["source_target_id", "metadata"]);
    const source = uuid(fact.source_target_id);
    if (!members.includes(source) || !Array.isArray(fact.metadata)) throw unavailable();
    // A structured tuple preserves arbitrary TEXT contact IDs without delimiter collisions.
    const key = JSON.stringify(splitFactKey(fact.metadata, source, members, root.target_type));
    if (keys.has(key)) throw unavailable();
    keys.add(key);
  }
  return root;
}

function splitFactKey(metadata: unknown[], source: string, members: readonly string[], targetType: unknown): readonly unknown[] {
  const tag = metadata[0];
  if (tag === "contact_link") {
    if (metadata.length !== 4 || typeof metadata[1] !== "string" || uuid(metadata[3]) !== source) throw unavailable();
    positiveInteger(metadata[2]);
    return [tag, metadata[1], metadata[2], source];
  }
  if (tag === "project_relationship" || tag === "project_revision") {
    if (metadata.length !== (tag === "project_relationship" ? 5 : 4) || uuid(metadata[1]) !== source) throw unavailable();
    const factProject = uuid(metadata[2]);
    positiveInteger(metadata[3]);
    if (tag === "project_relationship") {
      dueTimestamp(metadata[4]);
      return [tag, source, factProject];
    }
    return [tag, source, factProject, metadata[3]];
  }
  if (!oneOf(tag, ["institution_relationship_person", "institution_relationship_institution",
    "institution_revision_person", "institution_revision_institution"])) throw unavailable();
  const isRevision = String(tag).startsWith("institution_revision_");
  const personSide = String(tag).endsWith("_person");
  if (metadata.length !== (isRevision ? 6 : 7) || targetType !== (personSide ? "person" : "institution")) throw unavailable();
  const relationshipId = uuid(metadata[1]);
  const personId = uuid(metadata[isRevision ? 3 : 2]);
  const institutionId = uuid(metadata[isRevision ? 4 : 3]);
  const otherEndpoint = personSide ? institutionId : personId;
  if ((personSide ? personId : institutionId) !== source || members.includes(otherEndpoint)) throw unavailable();
  positiveInteger(metadata[isRevision ? 2 : 4]);
  if (!isRevision) dueTimestamp(metadata[5]);
  const otherBinding = metadata[isRevision ? 5 : 6];
  if (otherBinding !== null) uuid(otherBinding);
  return isRevision ? [tag, relationshipId, metadata[2]] : [tag, relationshipId];
}

function splitPlanFailure(status: number, suffix: string): PersonalTargetMergeSplitPlanHttpResult {
  return {status, body: {error: {code: `personal_target_merge_split_plan_${suffix}`}}};
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

function directoryUuid(value: unknown): string {
  if (typeof value !== "string" || !directoryUuidPattern.test(value)) throw unavailable();
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
const directoryUuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const timestampPattern = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.(\d{1,6}))?(?:Z|[+-]\d{2}:\d{2})$/;
const duePattern = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$/;
