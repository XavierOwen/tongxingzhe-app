import {authorizeContext} from "./authorized-context.js";
import type {IdentityVerifier} from "./identity.js";
import type {
  SessionContext,
  SessionContextStore,
} from "./session-context.js";

export interface PersonalActionReminder {
  readonly reminderId: string;
  readonly revision: number;
  readonly localMinuteOfDay: number | null;
  readonly updatedAt: string;
}

export interface SavePersonalActionReminderInput {
  readonly expectedRevision: number;
  readonly localMinuteOfDay: number | null;
  readonly mutationId: string;
}

export interface PersonalActionReminderMutation {
  readonly reminder: PersonalActionReminder;
  readonly duplicate: boolean;
  readonly acceptedRevision: number;
}

export interface PersonalActionReminderStore {
  read(context: SessionContext): Promise<PersonalActionReminder | null>;
  save(
    context: SessionContext,
    input: SavePersonalActionReminderInput,
    requestedAt: string,
  ): Promise<PersonalActionReminderMutation>;
}

export interface PersonalActionReminderDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly contextStore: SessionContextStore;
  readonly reminderStore: PersonalActionReminderStore;
  readonly now?: () => Date;
}

export interface PersonalActionReminderHttpResult {
  readonly status: number;
  readonly body: Readonly<Record<string, unknown>>;
}

export async function readPersonalActionReminder(
  authorization: string | undefined,
  dependencies: PersonalActionReminderDependencies,
): Promise<PersonalActionReminderHttpResult> {
  const context = await privateContext(authorization, dependencies);
  if (context.status === "rejected") return context.result;
  try {
    const reminder = await dependencies.reminderStore.read(context.value);
    return {
      status: 200,
      body: {reminder: reminder === null ? null : serialize(reminder)},
    };
  } catch (error) {
    return storeFailure(error);
  }
}

export async function savePersonalActionReminder(
  authorization: string | undefined,
  body: unknown,
  dependencies: PersonalActionReminderDependencies,
): Promise<PersonalActionReminderHttpResult> {
  const input = parseSaveInput(body);
  if (input === null) return failure(400, "invalid_personal_action_reminder");
  const context = await privateContext(authorization, dependencies);
  if (context.status === "rejected") return context.result;
  try {
    const mutation = await dependencies.reminderStore.save(
      context.value,
      input,
      (dependencies.now?.() ?? new Date()).toISOString(),
    );
    return {
      status: input.expectedRevision === 0 && !mutation.duplicate ? 201 : 200,
      body: {
        reminder: serialize(mutation.reminder),
        duplicate: mutation.duplicate,
        accepted_revision: mutation.acceptedRevision,
      },
    };
  } catch (error) {
    return storeFailure(error);
  }
}

export type PersonalActionReminderQuery = (
  text: string,
  values: readonly unknown[],
) => Promise<{readonly rows: readonly unknown[]}>;

export class PostgresPersonalActionReminderStore
implements PersonalActionReminderStore {
  constructor(private readonly query: PersonalActionReminderQuery) {}

  async read(context: SessionContext): Promise<PersonalActionReminder | null> {
    try {
      const result = await this.query(
        `SELECT app_data.read_personal_action_reminder(
           $1::uuid, $2::uuid, $3::uuid
         ) AS reminder`,
        contextValues(context),
      );
      if (result.rows.length !== 1) {
        throw new Error("personal reminder read must return exactly one row");
      }
      const value = rowField(result.rows[0], "reminder");
      return value === null ? null : parseReminder(value);
    } catch (error) {
      throw mapPostgresError(error);
    }
  }

  async save(
    context: SessionContext,
    input: SavePersonalActionReminderInput,
    requestedAt: string,
  ): Promise<PersonalActionReminderMutation> {
    try {
      const result = await this.query(
        `SELECT app_data.save_personal_action_reminder(
           $1::uuid, $2::uuid, $3::uuid, $4::integer, $5::integer,
           $6::text, $7::timestamptz
         ) AS reminder`,
        [
          ...contextValues(context),
          input.expectedRevision,
          input.localMinuteOfDay,
          input.mutationId,
          requestedAt,
        ],
      );
      if (result.rows.length !== 1) {
        throw new Error("personal reminder save must return exactly one row");
      }
      const root = object(rowField(result.rows[0], "reminder"));
      return {
        reminder: parseReminder(root),
        duplicate: boolean(root.duplicate),
        acceptedRevision: integer(root.accepted_revision, 1, 2147483647),
      };
    } catch (error) {
      throw mapPostgresError(error);
    }
  }
}

export class PersonalActionReminderStoreError extends Error {
  constructor(readonly code: "forbidden" | "conflict" | "invalid") {
    super(code);
    this.name = "PersonalActionReminderStoreError";
  }
}

type PrivateContextResult =
  | {readonly status: "authorized"; readonly value: SessionContext}
  | {
      readonly status: "rejected";
      readonly result: PersonalActionReminderHttpResult;
    };

async function privateContext(
  authorization: string | undefined,
  dependencies: PersonalActionReminderDependencies,
): Promise<PrivateContextResult> {
  const result = await authorizeContext(
    authorization,
    dependencies,
    [],
    "personal_action_reminder_unavailable",
  );
  return result.status === "authorized"
    ? {status: "authorized", value: result.context}
    : {
        status: "rejected",
        result: failure(result.responseStatus, result.errorCode),
      };
}

function parseSaveInput(value: unknown): SavePersonalActionReminderInput | null {
  const root = nullableObject(value);
  if (root === null || !hasOnlyKeys(root, [
    "expected_revision",
    "local_minute_of_day",
    "mutation_id",
  ])) return null;
  const expectedRevision = boundedInteger(root.expected_revision, 0, 2147483647);
  const minuteValue = root.local_minute_of_day;
  const minute = minuteValue === null
    ? null
    : boundedInteger(minuteValue, 0, 1439);
  const mutationId = boundedString(root.mutation_id, 1, 120);
  if (
    expectedRevision === null ||
    (minuteValue !== null && minute === null) ||
    mutationId === null
  ) return null;
  return {
    expectedRevision,
    localMinuteOfDay: minute,
    mutationId,
  };
}

function parseReminder(value: unknown): PersonalActionReminder {
  const root = object(value);
  const minute = root.local_minute_of_day;
  return {
    reminderId: string(root.reminder_id),
    revision: integer(root.revision, 1, 2147483647),
    localMinuteOfDay: minute === null ? null : integer(minute, 0, 1439),
    updatedAt: timestamp(root.updated_at_utc),
  };
}

function serialize(value: PersonalActionReminder): Readonly<Record<string, unknown>> {
  return {
    reminder_id: value.reminderId,
    revision: value.revision,
    local_minute_of_day: value.localMinuteOfDay,
    updated_at_utc: value.updatedAt,
  };
}

function storeFailure(error: unknown): PersonalActionReminderHttpResult {
  if (error instanceof PersonalActionReminderStoreError) {
    return error.code === "forbidden"
      ? failure(403, "personal_action_reminder_forbidden")
      : error.code === "conflict"
      ? failure(409, "personal_action_reminder_conflict")
      : failure(400, "invalid_personal_action_reminder");
  }
  return failure(503, "personal_action_reminder_unavailable");
}

function mapPostgresError(error: unknown): Error {
  const code = typeof error === "object" && error !== null && "code" in error
    ? String(error.code)
    : "";
  const message = error instanceof Error ? error.message : String(error);
  if (code === "42501") return new PersonalActionReminderStoreError("forbidden");
  if (code === "40001") return new PersonalActionReminderStoreError("conflict");
  if (code === "22023" || code === "23514") {
    return new PersonalActionReminderStoreError("invalid");
  }
  return error instanceof Error ? error : new Error(message);
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
  if (result === null) throw new Error("invalid personal action reminder document");
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
    throw new Error("invalid personal action reminder string");
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
    throw new Error("invalid personal action reminder integer");
  }
  return Number(value);
}

function boolean(value: unknown): boolean {
  if (typeof value !== "boolean") {
    throw new Error("invalid personal action reminder boolean");
  }
  return value;
}

function timestamp(value: unknown): string {
  const result = string(value);
  const date = new Date(result);
  if (Number.isNaN(date.valueOf())) {
    throw new Error("invalid personal action reminder timestamp");
  }
  return date.toISOString();
}

function rowField(row: unknown, field: string): unknown {
  const root = object(row);
  if (!(field in root)) throw new Error(`missing ${field}`);
  return root[field];
}

function failure(status: number, code: string): PersonalActionReminderHttpResult {
  return {status, body: {error: {code}}};
}
