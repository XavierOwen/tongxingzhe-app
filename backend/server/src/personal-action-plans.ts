import {authorizeContext} from "./authorized-context.js";
import type {IdentityVerifier} from "./identity.js";
import type {
  SessionContext,
  SessionContextStore,
} from "./session-context.js";

export interface PersonalActionPlanVersion {
  readonly revision: number;
  readonly weeklyContactTarget: number | null;
  readonly statisticsTimeZone: string;
  readonly weekStartIsoDay: number;
  readonly effectiveFrom: string;
}

export interface PersonalActionPlanProgress {
  readonly cycleStart: string;
  readonly cycleUntil: string;
  readonly recordedContactSessions: number;
  readonly remainingContactSessions: number | null;
  readonly asOf: string;
}

export interface PersonalActionPlan {
  readonly planId: string;
  readonly revision: number;
  readonly current: PersonalActionPlanVersion;
  readonly pending: PersonalActionPlanVersion | null;
  readonly progress: PersonalActionPlanProgress;
}

export interface SavePersonalActionPlanInput {
  readonly expectedRevision: number;
  readonly weeklyContactTarget: number | null;
  readonly statisticsTimeZone: string;
  readonly weekStartIsoDay: number;
  readonly mutationId: string;
}

export interface PersonalActionPlanMutation {
  readonly plan: PersonalActionPlan;
  readonly duplicate: boolean;
  readonly acceptedRevision: number;
}

export interface PersonalActionPlanStore {
  read(
    context: SessionContext,
    referenceAt: string,
  ): Promise<PersonalActionPlan | null>;
  save(
    context: SessionContext,
    input: SavePersonalActionPlanInput,
    requestedAt: string,
  ): Promise<PersonalActionPlanMutation>;
}

export interface PersonalActionPlanDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly contextStore: SessionContextStore;
  readonly planStore: PersonalActionPlanStore;
  readonly now?: () => Date;
}

export interface PersonalActionPlanHttpResult {
  readonly status: number;
  readonly body: Readonly<Record<string, unknown>>;
}

export async function readPersonalActionPlan(
  authorization: string | undefined,
  dependencies: PersonalActionPlanDependencies,
): Promise<PersonalActionPlanHttpResult> {
  const context = await privateContext(authorization, dependencies);
  if (context.status === "rejected") return context.result;
  try {
    const plan = await dependencies.planStore.read(
      context.value,
      now(dependencies),
    );
    return {status: 200, body: {plan: plan === null ? null : serialize(plan)}};
  } catch (error) {
    return storeFailure(error);
  }
}

export async function savePersonalActionPlan(
  authorization: string | undefined,
  body: unknown,
  dependencies: PersonalActionPlanDependencies,
): Promise<PersonalActionPlanHttpResult> {
  const input = parseSaveInput(body);
  if (input === null) return failure(400, "invalid_personal_action_plan");
  const context = await privateContext(authorization, dependencies);
  if (context.status === "rejected") return context.result;
  try {
    const mutation = await dependencies.planStore.save(
      context.value,
      input,
      now(dependencies),
    );
    return {
      status: input.expectedRevision === 0 && !mutation.duplicate ? 201 : 200,
      body: {
        plan: serialize(mutation.plan),
        duplicate: mutation.duplicate,
        accepted_revision: mutation.acceptedRevision,
      },
    };
  } catch (error) {
    return storeFailure(error);
  }
}

export type PersonalActionPlanQuery = (
  text: string,
  values: readonly unknown[],
) => Promise<{readonly rows: readonly unknown[]}>;

export class PostgresPersonalActionPlanStore implements PersonalActionPlanStore {
  constructor(private readonly query: PersonalActionPlanQuery) {}

  async read(
    context: SessionContext,
    referenceAt: string,
  ): Promise<PersonalActionPlan | null> {
    try {
      const result = await this.query(
        `SELECT app_data.read_personal_action_plan(
           $1::uuid, $2::uuid, $3::uuid, $4::timestamptz
         ) AS plan`,
        [...contextValues(context), referenceAt],
      );
      if (result.rows.length !== 1) {
        throw new Error("personal plan read must return exactly one row");
      }
      const value = rowField(result.rows[0], "plan");
      return value === null ? null : parsePlan(value);
    } catch (error) {
      throw mapPostgresError(error);
    }
  }

  async save(
    context: SessionContext,
    input: SavePersonalActionPlanInput,
    requestedAt: string,
  ): Promise<PersonalActionPlanMutation> {
    try {
      const result = await this.query(
        `SELECT app_data.save_personal_action_plan(
           $1::uuid, $2::uuid, $3::uuid, $4::integer, $5::integer,
           $6::text, $7::integer, $8::text, $9::timestamptz
         ) AS plan`,
        [
          ...contextValues(context),
          input.expectedRevision,
          input.weeklyContactTarget,
          input.statisticsTimeZone,
          input.weekStartIsoDay,
          input.mutationId,
          requestedAt,
        ],
      );
      if (result.rows.length !== 1) {
        throw new Error("personal plan save must return exactly one row");
      }
      const root = object(rowField(result.rows[0], "plan"));
      return {
        plan: parsePlan(root),
        duplicate: boolean(root.duplicate),
        acceptedRevision: integer(root.accepted_revision, 1, 2147483647),
      };
    } catch (error) {
      throw mapPostgresError(error);
    }
  }
}

export class PersonalActionPlanStoreError extends Error {
  constructor(readonly code: "forbidden" | "conflict" | "pending" | "invalid") {
    super(code);
    this.name = "PersonalActionPlanStoreError";
  }
}

type PrivateContextResult =
  | {readonly status: "authorized"; readonly value: SessionContext}
  | {
      readonly status: "rejected";
      readonly result: PersonalActionPlanHttpResult;
    };

async function privateContext(
  authorization: string | undefined,
  dependencies: PersonalActionPlanDependencies,
): Promise<PrivateContextResult> {
  const result = await authorizeContext(
    authorization,
    dependencies,
    [],
    "personal_action_plan_unavailable",
  );
  return result.status === "authorized"
    ? {status: "authorized", value: result.context}
    : {
        status: "rejected",
        result: failure(result.responseStatus, result.errorCode),
      };
}

function parseSaveInput(value: unknown): SavePersonalActionPlanInput | null {
  const root = nullableObject(value);
  if (root === null || !hasOnlyKeys(root, [
    "expected_revision",
    "weekly_contact_target",
    "statistics_time_zone",
    "week_start_iso_day",
    "mutation_id",
  ])) return null;
  const expectedRevision = boundedInteger(root.expected_revision, 0, 2147483647);
  const targetValue = root.weekly_contact_target;
  const target = targetValue === null
    ? null
    : boundedInteger(targetValue, 1, 999);
  const timeZone = boundedString(root.statistics_time_zone, 1, 100);
  const weekStart = boundedInteger(root.week_start_iso_day, 1, 7);
  const mutationId = boundedString(root.mutation_id, 1, 120);
  if (
    expectedRevision === null || (targetValue !== null && target === null) ||
    timeZone === null ||
    weekStart === null || mutationId === null
  ) return null;
  return {
    expectedRevision,
    weeklyContactTarget: target,
    statisticsTimeZone: timeZone,
    weekStartIsoDay: weekStart,
    mutationId,
  };
}

function parsePlan(value: unknown): PersonalActionPlan {
  const root = object(value);
  return {
    planId: string(root.plan_id),
    revision: integer(root.revision, 1, 2147483647),
    current: parseVersion(root.current),
    pending: root.pending === null ? null : parseVersion(root.pending),
    progress: parseProgress(root.progress),
  };
}

function parseVersion(value: unknown): PersonalActionPlanVersion {
  const root = object(value);
  return {
    revision: integer(root.revision, 1, 2147483647),
    weeklyContactTarget: root.weekly_contact_target === null
      ? null
      : integer(root.weekly_contact_target, 1, 999),
    statisticsTimeZone: string(root.statistics_time_zone),
    weekStartIsoDay: integer(root.week_start_iso_day, 1, 7),
    effectiveFrom: timestamp(root.effective_from_utc),
  };
}

function parseProgress(value: unknown): PersonalActionPlanProgress {
  const root = object(value);
  return {
    cycleStart: timestamp(root.cycle_start_utc),
    cycleUntil: timestamp(root.cycle_until_utc),
    recordedContactSessions: integer(
      root.recorded_contact_sessions,
      0,
      Number.MAX_SAFE_INTEGER,
    ),
    remainingContactSessions: root.remaining_contact_sessions === null
      ? null
      : integer(root.remaining_contact_sessions, 0, 999),
    asOf: timestamp(root.as_of_utc),
  };
}

function serialize(plan: PersonalActionPlan): Readonly<Record<string, unknown>> {
  return {
    plan_id: plan.planId,
    revision: plan.revision,
    current: serializeVersion(plan.current),
    pending: plan.pending === null ? null : serializeVersion(plan.pending),
    progress: {
      cycle_start_utc: plan.progress.cycleStart,
      cycle_until_utc: plan.progress.cycleUntil,
      recorded_contact_sessions: plan.progress.recordedContactSessions,
      remaining_contact_sessions: plan.progress.remainingContactSessions,
      as_of_utc: plan.progress.asOf,
    },
  };
}

function serializeVersion(
  version: PersonalActionPlanVersion,
): Readonly<Record<string, unknown>> {
  return {
    revision: version.revision,
    weekly_contact_target: version.weeklyContactTarget,
    statistics_time_zone: version.statisticsTimeZone,
    week_start_iso_day: version.weekStartIsoDay,
    effective_from_utc: version.effectiveFrom,
  };
}

function storeFailure(error: unknown): PersonalActionPlanHttpResult {
  if (error instanceof PersonalActionPlanStoreError) {
    if (error.code === "forbidden") {
      return failure(403, "personal_action_plan_forbidden");
    }
    if (error.code === "conflict") {
      return failure(409, "personal_action_plan_conflict");
    }
    if (error.code === "pending") {
      return failure(409, "personal_action_plan_pending_change");
    }
    return failure(400, "invalid_personal_action_plan");
  }
  return failure(503, "personal_action_plan_unavailable");
}

function mapPostgresError(error: unknown): Error {
  const code = typeof error === "object" && error !== null && "code" in error
    ? String(error.code)
    : "";
  const message = error instanceof Error ? error.message : String(error);
  if (code === "42501") return new PersonalActionPlanStoreError("forbidden");
  if (code === "40001") return new PersonalActionPlanStoreError("conflict");
  if (
    code === "55000" &&
    message.includes("personal action plan already has a pending change")
  ) return new PersonalActionPlanStoreError("pending");
  if (code === "22023" || code === "23514") {
    return new PersonalActionPlanStoreError("invalid");
  }
  return error instanceof Error ? error : new Error(message);
}

function now(dependencies: PersonalActionPlanDependencies): string {
  return (dependencies.now?.() ?? new Date()).toISOString();
}

function contextValues(context: SessionContext): readonly string[] {
  return [context.appUserId, context.current.workspace.id, context.current.project.id];
}

function nullableObject(value: unknown): Record<string, unknown> | null {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return null;
  }
  return value as Record<string, unknown>;
}

function object(value: unknown): Record<string, unknown> {
  const result = nullableObject(value);
  if (result === null) throw new Error("invalid personal action plan document");
  return result;
}

function hasOnlyKeys(
  value: Record<string, unknown>,
  allowed: readonly string[],
): boolean {
  const keys = Object.keys(value);
  return keys.length === allowed.length && keys.every((key) => allowed.includes(key));
}

function boundedString(value: unknown, minimum: number, maximum: number): string | null {
  if (typeof value !== "string") return null;
  const normalized = value.trim();
  return normalized.length >= minimum && normalized.length <= maximum
    ? normalized
    : null;
}

function string(value: unknown): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new Error("invalid personal action plan string");
  }
  return value;
}

function boundedInteger(
  value: unknown,
  minimum: number,
  maximum: number,
): number | null {
  return Number.isInteger(value) && Number(value) >= minimum && Number(value) <= maximum
    ? Number(value)
    : null;
}

function integer(value: unknown, minimum: number, maximum: number): number {
  if (!Number.isSafeInteger(value) || Number(value) < minimum || Number(value) > maximum) {
    throw new Error("invalid personal action plan integer");
  }
  return Number(value);
}

function boolean(value: unknown): boolean {
  if (typeof value !== "boolean") {
    throw new Error("invalid personal action plan boolean");
  }
  return value;
}

function timestamp(value: unknown): string {
  const result = string(value);
  const date = new Date(result);
  if (Number.isNaN(date.valueOf())) {
    throw new Error("invalid personal action plan timestamp");
  }
  return date.toISOString();
}

function rowField(row: unknown, field: string): unknown {
  const root = object(row);
  if (!(field in root)) throw new Error(`missing ${field}`);
  return root[field];
}

function failure(status: number, code: string): PersonalActionPlanHttpResult {
  return {status, body: {error: {code}}};
}
