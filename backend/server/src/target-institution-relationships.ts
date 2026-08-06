import {authorizeContext} from "./authorized-context.js";
import type {IdentityVerifier} from "./identity.js";
import type {
  SessionContext,
  SessionContextStore,
} from "./session-context.js";

export const manageAssignedTargetRelationsCapability =
  "manage_assigned_target_relations";
const viewAssignedTargetPiiCapability = "view_assigned_target_pii";

export type TargetInstitutionRelationshipKind =
  | "employment_representative"
  | "ownership_governance"
  | "learning_participation"
  | "membership_affiliation"
  | "partnership_service"
  | "other";

export interface TargetInstitutionRelationshipRevision {
  readonly revisionNumber: number;
  readonly eventType: "created" | "ended";
  readonly oldStatus: "active" | "ended" | null;
  readonly newStatus: "active" | "ended";
  readonly endedAt: string | null;
  readonly changedByAppUserId: string;
  readonly changedAt: string;
}

export interface TargetInstitutionRelationship {
  readonly id: string;
  readonly personTargetId: string;
  readonly institutionTargetId: string;
  readonly kind: TargetInstitutionRelationshipKind;
  readonly roleDescription: string | null;
  readonly startedAt: string;
  readonly endedAt: string | null;
  readonly status: "active" | "ended";
  readonly revisionNumber: number;
  readonly history: readonly TargetInstitutionRelationshipRevision[];
}

export interface CreateTargetInstitutionRelationshipInput {
  readonly personTargetId: string;
  readonly institutionTargetId: string;
  readonly kind: TargetInstitutionRelationshipKind;
  readonly roleDescription: string | null;
  readonly mutationId: string;
}

export interface EndTargetInstitutionRelationshipInput {
  readonly expectedRevision: number;
  readonly mutationId: string;
}

export interface TargetInstitutionRelationshipMutation {
  readonly duplicate: boolean;
  readonly relationship: TargetInstitutionRelationship;
}

export interface TargetInstitutionRelationshipStore {
  list(
    context: SessionContext,
  ): Promise<readonly TargetInstitutionRelationship[]>;
  create(
    context: SessionContext,
    input: CreateTargetInstitutionRelationshipInput,
  ): Promise<TargetInstitutionRelationshipMutation>;
  end(
    context: SessionContext,
    relationshipId: string,
    input: EndTargetInstitutionRelationshipInput,
  ): Promise<TargetInstitutionRelationshipMutation>;
}

export interface TargetInstitutionRelationshipDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly contextStore: SessionContextStore;
  readonly relationshipStore: TargetInstitutionRelationshipStore;
}

export interface TargetInstitutionRelationshipHttpResult {
  readonly status: number;
  readonly body: Readonly<Record<string, unknown>>;
}

export async function listTargetInstitutionRelationships(
  authorization: string | undefined,
  dependencies: TargetInstitutionRelationshipDependencies,
): Promise<TargetInstitutionRelationshipHttpResult> {
  const context = await authorizedContext(
    authorization,
    dependencies,
    [viewAssignedTargetPiiCapability],
  );
  if (context.status === "rejected") return context.result;
  try {
    const relationships = await dependencies.relationshipStore.list(
      context.value,
    );
    return {
      status: 200,
      body: {relationships: relationships.map(serializeRelationship)},
    };
  } catch (error) {
    return storeFailure(error);
  }
}

export async function createTargetInstitutionRelationship(
  authorization: string | undefined,
  body: unknown,
  dependencies: TargetInstitutionRelationshipDependencies,
): Promise<TargetInstitutionRelationshipHttpResult> {
  const input = parseCreateInput(body);
  if (input === null) {
    return failure(400, "invalid_target_institution_relationship");
  }
  const context = await authorizedContext(
    authorization,
    dependencies,
    [viewAssignedTargetPiiCapability, manageAssignedTargetRelationsCapability],
  );
  if (context.status === "rejected") return context.result;
  try {
    const mutation = await dependencies.relationshipStore.create(
      context.value,
      input,
    );
    return {
      status: mutation.duplicate ? 200 : 201,
      body: serializeMutation(mutation),
    };
  } catch (error) {
    return storeFailure(error);
  }
}

export async function endTargetInstitutionRelationship(
  authorization: string | undefined,
  relationshipId: string,
  body: unknown,
  dependencies: TargetInstitutionRelationshipDependencies,
): Promise<TargetInstitutionRelationshipHttpResult> {
  const input = parseEndInput(body);
  if (!uuid(relationshipId) || input === null) {
    return failure(400, "invalid_target_institution_relationship");
  }
  const context = await authorizedContext(
    authorization,
    dependencies,
    [viewAssignedTargetPiiCapability, manageAssignedTargetRelationsCapability],
  );
  if (context.status === "rejected") return context.result;
  try {
    const mutation = await dependencies.relationshipStore.end(
      context.value,
      relationshipId,
      input,
    );
    return {status: 200, body: serializeMutation(mutation)};
  } catch (error) {
    return storeFailure(error);
  }
}

export type TargetInstitutionRelationshipQuery = (
  text: string,
  values: readonly unknown[],
) => Promise<{readonly rows: readonly unknown[]}>;

export class PostgresTargetInstitutionRelationshipStore
  implements TargetInstitutionRelationshipStore {
  constructor(private readonly query: TargetInstitutionRelationshipQuery) {}

  async list(
    context: SessionContext,
  ): Promise<readonly TargetInstitutionRelationship[]> {
    try {
      const result = await this.query(
        `SELECT relationship
         FROM app_data.list_assigned_target_institution_relationships(
           $1::uuid, $2::uuid, $3::uuid
         )`,
        contextValues(context),
      );
      return result.rows.map((row) =>
        parseRelationship(rowField(row, "relationship"))
      );
    } catch (error) {
      throw mapPostgresError(error);
    }
  }

  async create(
    context: SessionContext,
    input: CreateTargetInstitutionRelationshipInput,
  ): Promise<TargetInstitutionRelationshipMutation> {
    try {
      const result = await this.query(
        `SELECT result
         FROM app_data.create_target_institution_relationship(
           $1::uuid, $2::uuid, $3::uuid, $4::uuid, $5::uuid,
           $6::text, $7::text, $8::text
         )`,
        [
          ...contextValues(context),
          input.personTargetId,
          input.institutionTargetId,
          input.kind,
          input.roleDescription,
          input.mutationId,
        ],
      );
      return parseSingleMutation(result.rows);
    } catch (error) {
      throw mapPostgresError(error);
    }
  }

  async end(
    context: SessionContext,
    relationshipId: string,
    input: EndTargetInstitutionRelationshipInput,
  ): Promise<TargetInstitutionRelationshipMutation> {
    try {
      const result = await this.query(
        `SELECT result
         FROM app_data.end_target_institution_relationship(
           $1::uuid, $2::uuid, $3::uuid, $4::uuid, $5::integer, $6::text
         )`,
        [
          ...contextValues(context),
          relationshipId,
          input.expectedRevision,
          input.mutationId,
        ],
      );
      return parseSingleMutation(result.rows);
    } catch (error) {
      throw mapPostgresError(error);
    }
  }
}

export class TargetInstitutionRelationshipStoreError extends Error {
  constructor(readonly code: "forbidden" | "conflict" | "invalid") {
    super(code);
    this.name = "TargetInstitutionRelationshipStoreError";
  }
}

type AuthorizedContextResult =
  | {readonly status: "authorized"; readonly value: SessionContext}
  | {
      readonly status: "rejected";
      readonly result: TargetInstitutionRelationshipHttpResult;
    };

async function authorizedContext(
  authorization: string | undefined,
  dependencies: TargetInstitutionRelationshipDependencies,
  requiredCapabilities: readonly string[],
): Promise<AuthorizedContextResult> {
  const result = await authorizeContext(
    authorization,
    dependencies,
    requiredCapabilities,
    "target_institution_relationships_unavailable",
  );
  return result.status === "authorized"
    ? {status: "authorized", value: result.context}
    : {
        status: "rejected",
        result: failure(result.responseStatus, result.errorCode),
      };
}

const relationshipKinds = [
  "employment_representative",
  "ownership_governance",
  "learning_participation",
  "membership_affiliation",
  "partnership_service",
  "other",
] as const;

function parseCreateInput(
  value: unknown,
): CreateTargetInstitutionRelationshipInput | null {
  const root = record(value);
  if (!hasOnlyKeys(root, [
    "person_target_id",
    "institution_target_id",
    "relationship_kind",
    "role_description",
    "mutation_id",
  ])) return null;
  const personTargetId = uuid(root.person_target_id);
  const institutionTargetId = uuid(root.institution_target_id);
  const kind = enumValue(root.relationship_kind, relationshipKinds);
  const roleDescription = nullableBoundedStringAllowEmpty(
    root.role_description,
    500,
  );
  const mutationId = boundedString(root.mutation_id, 1, 120);
  if (
    personTargetId === false || institutionTargetId === false || kind === null ||
    roleDescription === invalidString || mutationId === null ||
    (kind === "other" && roleDescription === null)
  ) return null;
  return {
    personTargetId: root.person_target_id as string,
    institutionTargetId: root.institution_target_id as string,
    kind,
    roleDescription,
    mutationId,
  };
}

function parseEndInput(
  value: unknown,
): EndTargetInstitutionRelationshipInput | null {
  const root = record(value);
  if (!hasOnlyKeys(root, ["expected_revision", "mutation_id"])) return null;
  const expectedRevision = boundedInteger(root.expected_revision, 1, 2147483647);
  const mutationId = boundedString(root.mutation_id, 1, 120);
  return expectedRevision === null || mutationId === null
    ? null
    : {expectedRevision, mutationId};
}

function serializeMutation(mutation: TargetInstitutionRelationshipMutation) {
  return {
    duplicate: mutation.duplicate,
    relationship: serializeRelationship(mutation.relationship),
  };
}

function serializeRelationship(relationship: TargetInstitutionRelationship) {
  return {
    relationship_id: relationship.id,
    person_target_id: relationship.personTargetId,
    institution_target_id: relationship.institutionTargetId,
    relationship_kind: relationship.kind,
    role_description: relationship.roleDescription,
    started_at: relationship.startedAt,
    ended_at: relationship.endedAt,
    status: relationship.status,
    revision_number: relationship.revisionNumber,
    history: relationship.history.map((revision) => ({
      revision_number: revision.revisionNumber,
      event_type: revision.eventType,
      old_status: revision.oldStatus,
      new_status: revision.newStatus,
      ended_at: revision.endedAt,
      changed_by_app_user_id: revision.changedByAppUserId,
      changed_at: revision.changedAt,
    })),
  };
}

function parseSingleMutation(
  rows: readonly unknown[],
): TargetInstitutionRelationshipMutation {
  if (rows.length !== 1) {
    throw new Error("institution relationship function must return one row");
  }
  const root = record(rowField(rows[0], "result"));
  return {
    duplicate: requiredBoolean(root.duplicate),
    relationship: parseRelationship(root.relationship),
  };
}

function parseRelationship(value: unknown): TargetInstitutionRelationship {
  const root = record(value);
  const status = requiredEnum(root.status, ["active", "ended"] as const);
  const endedAt = nullableRequiredString(root.ended_at);
  if ((status === "active") !== (endedAt === null)) {
    throw new TypeError("institution relationship status is inconsistent");
  }
  return {
    id: requiredString(root.relationship_id),
    personTargetId: requiredString(root.person_target_id),
    institutionTargetId: requiredString(root.institution_target_id),
    kind: requiredEnum(root.relationship_kind, relationshipKinds),
    roleDescription: nullableRequiredString(root.role_description),
    startedAt: requiredString(root.started_at),
    endedAt,
    status,
    revisionNumber: requiredInteger(root.revision_number, 1, 2147483647),
    history: requiredArray(root.history).map(parseRevision),
  };
}

function parseRevision(value: unknown): TargetInstitutionRelationshipRevision {
  const root = record(value);
  return {
    revisionNumber: requiredInteger(root.revision_number, 1, 2147483647),
    eventType: requiredEnum(root.event_type, ["created", "ended"] as const),
    oldStatus: root.old_status === null
      ? null
      : requiredEnum(root.old_status, ["active", "ended"] as const),
    newStatus: requiredEnum(root.new_status, ["active", "ended"] as const),
    endedAt: nullableRequiredString(root.ended_at),
    changedByAppUserId: requiredString(root.changed_by_app_user_id),
    changedAt: requiredString(root.changed_at),
  };
}

function contextValues(context: SessionContext): readonly string[] {
  return [
    context.appUserId,
    context.current.workspace.id,
    context.current.project.id,
  ];
}

function mapPostgresError(error: unknown): unknown {
  if (error instanceof TargetInstitutionRelationshipStoreError) return error;
  const code = record(error).code;
  if (code === "42501") {
    return new TargetInstitutionRelationshipStoreError("forbidden");
  }
  if (code === "23505") {
    return new TargetInstitutionRelationshipStoreError("conflict");
  }
  if (code === "22023") {
    return new TargetInstitutionRelationshipStoreError("invalid");
  }
  return error;
}

function storeFailure(error: unknown): TargetInstitutionRelationshipHttpResult {
  if (error instanceof TargetInstitutionRelationshipStoreError) {
    switch (error.code) {
      case "forbidden": return failure(403, "capability_forbidden");
      case "conflict": {
        return failure(409, "target_institution_relationship_conflict");
      }
      case "invalid": {
        return failure(400, "invalid_target_institution_relationship");
      }
    }
  }
  return failure(503, "target_institution_relationships_unavailable");
}

function failure(
  status: number,
  code: string,
): TargetInstitutionRelationshipHttpResult {
  return {status, body: {error: {code}}};
}

function record(value: unknown): Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function rowField(row: unknown, field: string): unknown {
  const value = record(row)[field];
  if (value === undefined) throw new TypeError(`missing ${field}`);
  return value;
}

function hasOnlyKeys(
  value: Readonly<Record<string, unknown>>,
  allowed: readonly string[],
): boolean {
  return Object.keys(value).every((key) => allowed.includes(key)) &&
    Object.keys(value).length === allowed.length;
}

function boundedString(
  value: unknown,
  minimum: number,
  maximum: number,
): string | null {
  if (typeof value !== "string") return null;
  const normalized = value.trim();
  return normalized.length >= minimum && normalized.length <= maximum
    ? normalized
    : null;
}

const invalidString = Symbol("invalid string");

function nullableBoundedStringAllowEmpty(
  value: unknown,
  maximum: number,
): string | null | typeof invalidString {
  if (value === null) return null;
  if (typeof value !== "string") return invalidString;
  const normalized = value.trim();
  return normalized.length === 0
    ? null
    : normalized.length <= maximum ? normalized : invalidString;
}

function boundedInteger(
  value: unknown,
  minimum: number,
  maximum: number,
): number | null {
  return typeof value === "number" && Number.isInteger(value) &&
      value >= minimum && value <= maximum
    ? value
    : null;
}

function uuid(value: unknown): boolean {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value);
}

function enumValue<const T extends string>(
  value: unknown,
  allowed: readonly T[],
): T | null {
  return typeof value === "string" && allowed.includes(value as T)
    ? value as T
    : null;
}

function requiredArray(value: unknown): readonly unknown[] {
  if (!Array.isArray(value)) throw new TypeError("expected array");
  return value;
}

function requiredString(value: unknown): string {
  if (typeof value !== "string") throw new TypeError("expected string");
  return value;
}

function nullableRequiredString(value: unknown): string | null {
  if (value === null) return null;
  return requiredString(value);
}

function requiredBoolean(value: unknown): boolean {
  if (typeof value !== "boolean") throw new TypeError("expected boolean");
  return value;
}

function requiredInteger(
  value: unknown,
  minimum: number,
  maximum: number,
): number {
  const parsed = boundedInteger(value, minimum, maximum);
  if (parsed === null) throw new TypeError("expected bounded integer");
  return parsed;
}

function requiredEnum<const T extends string>(
  value: unknown,
  allowed: readonly T[],
): T {
  const parsed = enumValue(value, allowed);
  if (parsed === null) throw new TypeError("expected enum value");
  return parsed;
}
