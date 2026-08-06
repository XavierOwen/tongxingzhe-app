import {authorizeContext} from "./authorized-context.js";
import type {IdentityVerifier} from "./identity.js";
import type {
  SessionContext,
  SessionContextStore,
} from "./session-context.js";

export const createPromotionTargetCapability = "create_target";
export const viewAssignedTargetPiiCapability = "view_assigned_target_pii";
export const manageAssignedTargetFollowUpCapability =
  "manage_assigned_target_follow_up";

export type PromotionTargetType = "person" | "institution";
export type PromotionTargetRelationshipLifecycle = "active" | "paused" | "ended";

export interface PromotionTargetStageAlias {
  readonly stage: number;
  readonly displayStage: number;
  readonly displayName: string | null;
}

export interface PromotionTargetRelationshipRevision {
  readonly revisionNumber: number;
  readonly oldStage: number | null;
  readonly newStage: number;
  readonly oldLifecycleStatus: PromotionTargetRelationshipLifecycle | null;
  readonly newLifecycleStatus: PromotionTargetRelationshipLifecycle;
  readonly followUpNote: string | null;
  readonly changedFields: readonly string[];
  readonly reasonCode: string;
  readonly reasonDetail: string | null;
  readonly changedByAppUserId: string;
  readonly changedAt: string;
}

export interface PromotionTargetRelationship {
  readonly targetId: string;
  readonly projectId: string;
  readonly stage: number;
  readonly displayStage: number;
  readonly lifecycleStatus: PromotionTargetRelationshipLifecycle;
  readonly followUpNote: string | null;
  readonly revisionNumber: number;
  readonly updatedAt: string;
  readonly stageAliases: readonly PromotionTargetStageAlias[];
  readonly history: readonly PromotionTargetRelationshipRevision[];
}

export interface PromotionTargetProfile {
  readonly id: string;
  readonly type: PromotionTargetType;
  readonly displayName: string;
  readonly phone: string | null;
  readonly email: string | null;
  readonly createdAt: string;
  readonly hasCurrentProjectRelationship?: boolean;
  readonly projectRelationship?: PromotionTargetRelationship | null;
}

export interface CreatePromotionTargetInput {
  readonly type: PromotionTargetType;
  readonly displayName: string;
  readonly phone: string | null;
  readonly email: string | null;
  readonly requestId: string;
}

export interface UpdatePromotionTargetRelationshipInput {
  readonly expectedRevision: number;
  readonly stage: number;
  readonly lifecycleStatus: PromotionTargetRelationshipLifecycle;
  readonly followUpNote: string | null;
  readonly reasonCode: string;
  readonly reasonDetail: string | null;
  readonly mutationId: string;
  readonly resolvedConflictId: string | null;
}

export interface PromotionTargetRelationshipProposal {
  readonly expectedRevision: number;
  readonly stage: number;
  readonly displayStage: number;
  readonly lifecycleStatus: PromotionTargetRelationshipLifecycle;
  readonly followUpNote: string | null;
  readonly reasonCode: string;
  readonly reasonDetail: string | null;
}

export type PromotionTargetRelationshipUpdate =
  | {
      readonly status: "accepted";
      readonly duplicate: boolean;
      readonly acceptedRevision: number;
      readonly relationship: PromotionTargetRelationship;
    }
  | {
      readonly status: "conflict";
      readonly conflictId: string;
      readonly conflictingFields: readonly string[];
      readonly current: PromotionTargetRelationship;
      readonly proposed: PromotionTargetRelationshipProposal;
    };

export interface PromotionTargetStore {
  listAssigned(context: SessionContext): Promise<readonly PromotionTargetProfile[]>;
  create(
    context: SessionContext,
    input: CreatePromotionTargetInput,
  ): Promise<PromotionTargetProfile>;
  updateRelationship(
    context: SessionContext,
    targetId: string,
    input: UpdatePromotionTargetRelationshipInput,
  ): Promise<PromotionTargetRelationshipUpdate>;
  configureStageAliases(
    context: SessionContext,
    aliases: readonly PromotionTargetStageAliasInput[],
  ): Promise<readonly PromotionTargetStageAlias[]>;
}

export interface PromotionTargetStageAliasInput {
  readonly stage: number;
  readonly displayName: string | null;
}

export interface PromotionTargetDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly contextStore: SessionContextStore;
  readonly targetStore: PromotionTargetStore;
}

export interface PromotionTargetHttpResult {
  readonly status: number;
  readonly body: Readonly<Record<string, unknown>>;
}

export async function listAssignedPromotionTargets(
  authorization: string | undefined,
  dependencies: PromotionTargetDependencies,
): Promise<PromotionTargetHttpResult> {
  const context = await authorizedContext(
    authorization,
    dependencies,
    [viewAssignedTargetPiiCapability],
  );
  if (!(context instanceof AuthorizedContext)) return context;
  try {
    const targets = await dependencies.targetStore.listAssigned(context.value);
    return {status: 200, body: {targets: targets.map(serializeTarget)}};
  } catch (error) {
    return storeFailure(error);
  }
}

export async function createPromotionTarget(
  authorization: string | undefined,
  body: unknown,
  dependencies: PromotionTargetDependencies,
): Promise<PromotionTargetHttpResult> {
  const input = parseCreateInput(body);
  if (input === null) return failure(400, "invalid_promotion_target");
  const context = await authorizedContext(
    authorization,
    dependencies,
    [createPromotionTargetCapability, viewAssignedTargetPiiCapability],
  );
  if (!(context instanceof AuthorizedContext)) return context;
  try {
    const target = await dependencies.targetStore.create(context.value, input);
    return {status: 201, body: {target: serializeTarget(target)}};
  } catch (error) {
    return storeFailure(error);
  }
}

export async function updatePromotionTargetRelationship(
  authorization: string | undefined,
  targetId: string,
  body: unknown,
  dependencies: PromotionTargetDependencies,
): Promise<PromotionTargetHttpResult> {
  const input = parseRelationshipUpdateInput(body);
  if (!uuid(targetId) || input === null) {
    return failure(400, "invalid_promotion_target_relationship");
  }
  const context = await authorizedContext(
    authorization,
    dependencies,
    [viewAssignedTargetPiiCapability, manageAssignedTargetFollowUpCapability],
  );
  if (!(context instanceof AuthorizedContext)) return context;
  try {
    const update = await dependencies.targetStore.updateRelationship(
      context.value,
      targetId,
      input,
    );
    if (update.status === "conflict") {
      return {
        status: 409,
        body: {
          error: {code: "promotion_target_relationship_conflict"},
          conflict_id: update.conflictId,
          conflicting_fields: update.conflictingFields,
          current: serializeRelationship(update.current),
          proposed: serializeRelationshipProposal(update.proposed),
        },
      };
    }
    return {
      status: 200,
      body: {
        relationship: serializeRelationship(update.relationship),
        duplicate: update.duplicate,
        accepted_revision: update.acceptedRevision,
      },
    };
  } catch (error) {
    return storeFailure(error, "invalid_promotion_target_relationship");
  }
}

export async function configurePromotionTargetStageAliases(
  authorization: string | undefined,
  body: unknown,
  dependencies: PromotionTargetDependencies,
): Promise<PromotionTargetHttpResult> {
  const aliases = parseStageAliasInput(body);
  if (aliases === null) {
    return failure(400, "invalid_promotion_target_stage_aliases");
  }
  const context = await authorizedContext(
    authorization,
    dependencies,
    ["manage_analysis_definitions"],
  );
  if (!(context instanceof AuthorizedContext)) return context;
  try {
    const updated = await dependencies.targetStore.configureStageAliases(
      context.value,
      aliases,
    );
    return {status: 200, body: {aliases: updated.map(serializeStageAlias)}};
  } catch (error) {
    return storeFailure(error, "invalid_promotion_target_stage_aliases");
  }
}

export type PromotionTargetQuery = (
  text: string,
  values: readonly unknown[],
) => Promise<{readonly rows: readonly unknown[]}>;

export class PostgresPromotionTargetStore implements PromotionTargetStore {
  constructor(private readonly query: PromotionTargetQuery) {}

  async listAssigned(
    context: SessionContext,
  ): Promise<readonly PromotionTargetProfile[]> {
    try {
      const result = await this.query(
        `SELECT target
         FROM app_data.list_assigned_promotion_targets(
           $1::uuid, $2::uuid, $3::uuid
         )`,
        contextValues(context),
      );
      return result.rows.map((row) => parseTarget(rowField(row, "target")));
    } catch (error) {
      throw mapPostgresError(error);
    }
  }

  async create(
    context: SessionContext,
    input: CreatePromotionTargetInput,
  ): Promise<PromotionTargetProfile> {
    try {
      const result = await this.query(
        `SELECT target
         FROM app_data.create_promotion_target(
           $1::uuid, $2::uuid, $3::uuid, $4::text,
           $5::text, $6::text, $7::text, $8::text
         )`,
        [
          ...contextValues(context),
          input.type,
          input.displayName,
          input.phone,
          input.email,
          input.requestId,
        ],
      );
      if (result.rows.length !== 1) {
        throw new Error("target function must return exactly one row");
      }
      return parseTarget(rowField(result.rows[0], "target"));
    } catch (error) {
      throw mapPostgresError(error);
    }
  }

  async updateRelationship(
    context: SessionContext,
    targetId: string,
    input: UpdatePromotionTargetRelationshipInput,
  ): Promise<PromotionTargetRelationshipUpdate> {
    try {
      const result = await this.query(
        `SELECT result
         FROM app_data.update_promotion_target_relationship(
           $1::uuid, $2::uuid, $3::uuid, $4::uuid, $5::integer,
           $6::integer, $7::text, $8::text, $9::text, $10::text, $11::text,
           $12::uuid
         )`,
        [
          ...contextValues(context),
          targetId,
          input.expectedRevision,
          input.stage,
          input.lifecycleStatus,
          input.followUpNote,
          input.reasonCode,
          input.reasonDetail,
          input.mutationId,
          input.resolvedConflictId,
        ],
      );
      if (result.rows.length !== 1) {
        throw new Error("relationship function must return exactly one row");
      }
      return parseRelationshipUpdate(rowField(result.rows[0], "result"));
    } catch (error) {
      throw mapPostgresError(error);
    }
  }

  async configureStageAliases(
    context: SessionContext,
    aliases: readonly PromotionTargetStageAliasInput[],
  ): Promise<readonly PromotionTargetStageAlias[]> {
    try {
      const result = await this.query(
        `SELECT aliases
         FROM app_data.configure_promotion_target_stage_aliases(
           $1::uuid, $2::uuid, $3::uuid, $4::jsonb
         )`,
        [
          ...contextValues(context),
          JSON.stringify(aliases.map((alias) => ({
            stage: alias.stage,
            display_name: alias.displayName,
          }))),
        ],
      );
      if (result.rows.length !== 1) {
        throw new Error("stage alias function must return exactly one row");
      }
      return parseStageAliases(rowField(result.rows[0], "aliases"));
    } catch (error) {
      throw mapPostgresError(error);
    }
  }
}

export class PromotionTargetStoreError extends Error {
  constructor(readonly code: string) {
    super(code);
    this.name = "PromotionTargetStoreError";
  }
}

async function authorizedContext(
  authorization: string | undefined,
  dependencies: PromotionTargetDependencies,
  requiredCapabilities: readonly string[],
): Promise<AuthorizedContext | PromotionTargetHttpResult> {
  const result = await authorizeContext(
    authorization,
    dependencies,
    requiredCapabilities,
    "promotion_targets_unavailable",
  );
  return result.status === "authorized"
    ? new AuthorizedContext(result.context)
    : failure(result.responseStatus, result.errorCode);
}

class AuthorizedContext {
  constructor(readonly value: SessionContext) {}
}

function parseCreateInput(value: unknown): CreatePromotionTargetInput | null {
  const root = record(value);
  if (!hasOnlyKeys(root, [
    "target_type",
    "display_name",
    "phone",
    "email",
    "request_id",
  ])) return null;
  const type = enumValue(root.target_type, ["person", "institution"] as const);
  const displayName = boundedString(root.display_name, 1, 200);
  const phone = nullableBoundedString(root.phone, 80);
  const email = nullableBoundedString(root.email, 320);
  const requestId = boundedString(root.request_id, 1, 120);
  if (
    type === null || displayName === null ||
    phone === invalidString || email === invalidString || requestId === null
  ) return null;
  return {type, displayName, phone, email, requestId};
}

const relationshipReasonCodes = [
  "progress_update",
  "contact_lost",
  "timing_changed",
  "requirements_changed",
  "target_request",
  "project_change",
  "correction",
  "other",
] as const;

function parseRelationshipUpdateInput(
  value: unknown,
): UpdatePromotionTargetRelationshipInput | null {
  const root = record(value);
  if (!hasOnlyKeys(root, [
    "expected_revision",
    "stage",
    "lifecycle_status",
    "follow_up_note",
    "reason_code",
    "reason_detail",
    "mutation_id",
    "resolved_conflict_id",
  ])) return null;
  const expectedRevision = boundedInteger(root.expected_revision, 1, 2147483647);
  const stage = boundedInteger(root.stage, 0, 4);
  const lifecycleStatus = enumValue(
    root.lifecycle_status,
    ["active", "paused", "ended"] as const,
  );
  const followUpNote = nullableBoundedStringAllowEmpty(root.follow_up_note, 4000);
  const reasonCode = enumValue(root.reason_code, relationshipReasonCodes);
  const reasonDetail = nullableBoundedStringAllowEmpty(root.reason_detail, 1000);
  const mutationId = boundedString(root.mutation_id, 1, 120);
  const resolvedConflictId = nullableUuid(root.resolved_conflict_id);
  if (
    expectedRevision === null || stage === null || lifecycleStatus === null ||
    followUpNote === invalidString || reasonCode === null ||
    reasonDetail === invalidString || mutationId === null ||
    resolvedConflictId === invalidString ||
    (reasonCode === "other" && reasonDetail === null)
  ) return null;
  return {
    expectedRevision,
    stage,
    lifecycleStatus,
    followUpNote,
    reasonCode,
    reasonDetail,
    mutationId,
    resolvedConflictId,
  };
}

function parseStageAliasInput(
  value: unknown,
): readonly PromotionTargetStageAliasInput[] | null {
  const root = record(value);
  if (!hasOnlyKeys(root, ["aliases"]) || !Array.isArray(root.aliases) ||
    root.aliases.length !== 5) return null;
  const parsed = root.aliases.map((candidate) => {
    const alias = record(candidate);
    if (!hasOnlyKeys(alias, ["stage", "display_name"])) return null;
    const stage = boundedInteger(alias.stage, 0, 4);
    const displayName = nullableBoundedStringAllowEmpty(alias.display_name, 80);
    return stage === null || displayName === invalidString
      ? null
      : {stage, displayName};
  });
  if (parsed.some((alias) => alias === null)) return null;
  const aliases = parsed as PromotionTargetStageAliasInput[];
  return new Set(aliases.map((alias) => alias.stage)).size === 5
    ? aliases.sort((left, right) => left.stage - right.stage)
    : null;
}

function serializeTarget(target: PromotionTargetProfile) {
  return {
    target_id: target.id,
    target_type: target.type,
    display_name: target.displayName,
    phone: target.phone,
    email: target.email,
    created_at: target.createdAt,
    has_current_project_relationship:
      target.hasCurrentProjectRelationship ?? false,
    project_relationship: target.projectRelationship === undefined ||
        target.projectRelationship === null
      ? null
      : serializeRelationship(target.projectRelationship),
  };
}

function parseTarget(value: unknown): PromotionTargetProfile {
  const root = record(value);
  return {
    id: requiredString(root.target_id),
    type: requiredEnum(root.target_type, ["person", "institution"] as const),
    displayName: requiredString(root.display_name),
    phone: nullableRequiredString(root.phone),
    email: nullableRequiredString(root.email),
    createdAt: requiredString(root.created_at),
    hasCurrentProjectRelationship: root.has_current_project_relationship ===
        undefined
      ? false
      : requiredBoolean(root.has_current_project_relationship),
    projectRelationship: root.project_relationship === undefined ||
        root.project_relationship === null
      ? null
      : parseRelationship(root.project_relationship),
  };
}

function serializeStageAlias(alias: PromotionTargetStageAlias) {
  return {
    stage: alias.stage,
    display_stage: alias.displayStage,
    display_name: alias.displayName,
  };
}

function serializeRelationship(relationship: PromotionTargetRelationship) {
  return {
    target_id: relationship.targetId,
    project_id: relationship.projectId,
    stage: relationship.stage,
    display_stage: relationship.displayStage,
    lifecycle_status: relationship.lifecycleStatus,
    follow_up_note: relationship.followUpNote,
    revision_number: relationship.revisionNumber,
    updated_at: relationship.updatedAt,
    stage_aliases: relationship.stageAliases.map(serializeStageAlias),
    history: relationship.history.map((revision) => ({
      revision_number: revision.revisionNumber,
      old_stage: revision.oldStage,
      new_stage: revision.newStage,
      old_lifecycle_status: revision.oldLifecycleStatus,
      new_lifecycle_status: revision.newLifecycleStatus,
      follow_up_note: revision.followUpNote,
      changed_fields: revision.changedFields,
      reason_code: revision.reasonCode,
      reason_detail: revision.reasonDetail,
      changed_by_app_user_id: revision.changedByAppUserId,
      changed_at: revision.changedAt,
    })),
  };
}

function serializeRelationshipProposal(
  proposal: PromotionTargetRelationshipProposal,
) {
  return {
    expected_revision: proposal.expectedRevision,
    stage: proposal.stage,
    display_stage: proposal.displayStage,
    lifecycle_status: proposal.lifecycleStatus,
    follow_up_note: proposal.followUpNote,
    reason_code: proposal.reasonCode,
    reason_detail: proposal.reasonDetail,
  };
}

function parseRelationship(value: unknown): PromotionTargetRelationship {
  const root = record(value);
  return {
    targetId: requiredString(root.target_id),
    projectId: requiredString(root.project_id),
    stage: requiredInteger(root.stage, 0, 4),
    displayStage: requiredInteger(root.display_stage, 0, 8),
    lifecycleStatus: requiredEnum(
      root.lifecycle_status,
      ["active", "paused", "ended"] as const,
    ),
    followUpNote: nullableRequiredString(root.follow_up_note),
    revisionNumber: requiredInteger(root.revision_number, 1, 2147483647),
    updatedAt: requiredString(root.updated_at),
    stageAliases: parseStageAliases(root.stage_aliases),
    history: requiredArray(root.history).map(parseRelationshipRevision),
  };
}

function parseRelationshipRevision(
  value: unknown,
): PromotionTargetRelationshipRevision {
  const root = record(value);
  return {
    revisionNumber: requiredInteger(root.revision_number, 1, 2147483647),
    oldStage: nullableRequiredInteger(root.old_stage, 0, 4),
    newStage: requiredInteger(root.new_stage, 0, 4),
    oldLifecycleStatus: root.old_lifecycle_status === null
      ? null
      : requiredEnum(
        root.old_lifecycle_status,
        ["active", "paused", "ended"] as const,
      ),
    newLifecycleStatus: requiredEnum(
      root.new_lifecycle_status,
      ["active", "paused", "ended"] as const,
    ),
    followUpNote: nullableRequiredString(root.follow_up_note),
    changedFields: requiredArray(root.changed_fields).map(requiredString),
    reasonCode: requiredString(root.reason_code),
    reasonDetail: nullableRequiredString(root.reason_detail),
    changedByAppUserId: requiredString(root.changed_by_app_user_id),
    changedAt: requiredString(root.changed_at),
  };
}

function parseStageAliases(value: unknown): readonly PromotionTargetStageAlias[] {
  const aliases = requiredArray(value).map((candidate) => {
    const root = record(candidate);
    return {
      stage: requiredInteger(root.stage, 0, 4),
      displayStage: requiredInteger(root.display_stage, 0, 8),
      displayName: nullableRequiredString(root.display_name),
    };
  });
  if (aliases.length !== 5 || new Set(aliases.map((alias) => alias.stage)).size !== 5) {
    throw new TypeError("stage aliases must contain stages 0 through 4");
  }
  return aliases;
}

function parseRelationshipUpdate(value: unknown): PromotionTargetRelationshipUpdate {
  const root = record(value);
  const status = requiredEnum(root.status, ["accepted", "conflict"] as const);
  if (status === "conflict") {
    return {
      status,
      conflictId: requiredString(root.conflict_id),
      conflictingFields: requiredArray(root.conflicting_fields).map(
        requiredString,
      ),
      current: parseRelationship(root.current),
      proposed: parseRelationshipProposal(root.proposed),
    };
  }
  return {
    status,
    duplicate: requiredBoolean(root.duplicate),
    acceptedRevision: requiredInteger(root.accepted_revision, 1, 2147483647),
    relationship: parseRelationship(root.relationship),
  };
}

function parseRelationshipProposal(
  value: unknown,
): PromotionTargetRelationshipProposal {
  const root = record(value);
  return {
    expectedRevision: requiredInteger(root.expected_revision, 1, 2147483647),
    stage: requiredInteger(root.stage, 0, 4),
    displayStage: requiredInteger(root.display_stage, 0, 8),
    lifecycleStatus: requiredEnum(
      root.lifecycle_status,
      ["active", "paused", "ended"] as const,
    ),
    followUpNote: nullableRequiredString(root.follow_up_note),
    reasonCode: requiredString(root.reason_code),
    reasonDetail: nullableRequiredString(root.reason_detail),
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
  if (error instanceof PromotionTargetStoreError) return error;
  const code = record(error).code;
  if (code === "42501") return new PromotionTargetStoreError("forbidden");
  if (code === "23505") return new PromotionTargetStoreError("conflict");
  if (code === "22023") return new PromotionTargetStoreError("invalid");
  return error;
}

function storeFailure(
  error: unknown,
  invalidCode = "invalid_promotion_target",
): PromotionTargetHttpResult {
  if (error instanceof PromotionTargetStoreError) {
    switch (error.code) {
      case "forbidden": return failure(403, "capability_forbidden");
      case "conflict": return failure(409, "promotion_target_conflict");
      case "invalid": return failure(400, invalidCode);
    }
  }
  return failure(503, "promotion_targets_unavailable");
}

function failure(status: number, code: string): PromotionTargetHttpResult {
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

function nullableBoundedString(
  value: unknown,
  maximum: number,
): string | null | typeof invalidString {
  if (value === null) return null;
  if (typeof value !== "string") return invalidString;
  const normalized = value.trim();
  return normalized.length === 0 || normalized.length > maximum
    ? invalidString
    : normalized;
}

function nullableBoundedStringAllowEmpty(
  value: unknown,
  maximum: number,
): string | null | typeof invalidString {
  if (value === null) return null;
  if (typeof value !== "string") return invalidString;
  const normalized = value.trim();
  if (normalized.length === 0) return null;
  return normalized.length <= maximum ? normalized : invalidString;
}

function boundedInteger(
  value: unknown,
  minimum: number,
  maximum: number,
): number | null {
  return Number.isInteger(value) && (value as number) >= minimum &&
      (value as number) <= maximum
    ? value as number
    : null;
}

function enumValue<const T extends readonly string[]>(
  value: unknown,
  allowed: T,
): T[number] | null {
  return typeof value === "string" && allowed.includes(value) ? value : null;
}

function requiredEnum<const T extends readonly string[]>(
  value: unknown,
  allowed: T,
): T[number] {
  const parsed = enumValue(value, allowed);
  if (parsed === null) throw new TypeError("invalid enum value");
  return parsed;
}

function requiredString(value: unknown): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new TypeError("expected non-empty string");
  }
  return value;
}

function requiredBoolean(value: unknown): boolean {
  if (typeof value !== "boolean") throw new TypeError("expected boolean");
  return value;
}

function requiredInteger(value: unknown, minimum: number, maximum: number): number {
  const parsed = boundedInteger(value, minimum, maximum);
  if (parsed === null) throw new TypeError("expected bounded integer");
  return parsed;
}

function nullableRequiredInteger(
  value: unknown,
  minimum: number,
  maximum: number,
): number | null {
  return value === null ? null : requiredInteger(value, minimum, maximum);
}

function requiredArray(value: unknown): readonly unknown[] {
  if (!Array.isArray(value)) throw new TypeError("expected array");
  return value;
}

function nullableRequiredString(value: unknown): string | null {
  return value === null ? null : requiredString(value);
}

function uuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value);
}

function nullableUuid(value: unknown): string | null | typeof invalidString {
  if (value === null) return null;
  return typeof value === "string" && uuid(value) ? value : invalidString;
}
