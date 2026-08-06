import {bearerToken} from "./authorization.js";
import {
  IdentityVerificationError,
  type IdentityVerifier,
} from "./identity.js";
import type {
  SessionContext,
  SessionContextStore,
} from "./session-context.js";

export const createPromotionTargetCapability = "create_target";
export const viewAssignedTargetPiiCapability = "view_assigned_target_pii";

export type PromotionTargetType = "person" | "institution";

export interface PromotionTargetProfile {
  readonly id: string;
  readonly type: PromotionTargetType;
  readonly displayName: string;
  readonly phone: string | null;
  readonly email: string | null;
  readonly createdAt: string;
}

export interface CreatePromotionTargetInput {
  readonly type: PromotionTargetType;
  readonly displayName: string;
  readonly phone: string | null;
  readonly email: string | null;
  readonly requestId: string;
}

export interface PromotionTargetStore {
  listAssigned(context: SessionContext): Promise<readonly PromotionTargetProfile[]>;
  create(
    context: SessionContext,
    input: CreatePromotionTargetInput,
  ): Promise<PromotionTargetProfile>;
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
  const accessToken = bearerToken(authorization);
  if (accessToken === null) return failure(401, "unauthenticated");
  try {
    const identity = await dependencies.identityVerifier.verify(accessToken);
    const context = await dependencies.contextStore.loadOrCreate(identity);
    return requiredCapabilities.every((capability) =>
      context.capabilities.includes(capability)
    )
      ? new AuthorizedContext(context)
      : failure(403, "capability_forbidden");
  } catch (error) {
    return error instanceof IdentityVerificationError
      ? failure(401, "unauthenticated")
      : failure(503, "promotion_targets_unavailable");
  }
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

function serializeTarget(target: PromotionTargetProfile) {
  return {
    target_id: target.id,
    target_type: target.type,
    display_name: target.displayName,
    phone: target.phone,
    email: target.email,
    created_at: target.createdAt,
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

function storeFailure(error: unknown): PromotionTargetHttpResult {
  if (error instanceof PromotionTargetStoreError) {
    switch (error.code) {
      case "forbidden": return failure(403, "capability_forbidden");
      case "conflict": return failure(409, "promotion_target_conflict");
      case "invalid": return failure(400, "invalid_promotion_target");
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

function nullableRequiredString(value: unknown): string | null {
  return value === null ? null : requiredString(value);
}
