import type { SessionContext } from "./session-context.js";

export type ContactChannel =
  | "face_to_face"
  | "voice_call"
  | "video_call"
  | "instant_text"
  | "asynchronous_message"
  | "mixed"
  | "other_direct";

export type ContactLocation =
  | { readonly kind: "not_applicable" }
  | {
      readonly kind: "pending_resolution";
      readonly latitude: number;
      readonly longitude: number;
      readonly accuracyMeters: number | null;
    }
  | {
      readonly kind: "resolved";
      readonly placeName: string;
      readonly smallestRegionId: string;
      readonly regionTreeVersion: string;
    };

export interface ContactAnswer {
  readonly questionId: string;
  readonly state:
    | "answered"
    | "unknown"
    | "refused"
    | "not_applicable"
    | "unanswered";
  readonly stateReason: "rule_skipped" | null;
  readonly type:
    | "boolean"
    | "single_choice"
    | "ordinal_choice"
    | "multi_choice"
    | "number"
    | "date"
    | "short_text"
    | "long_text";
  readonly value: boolean | string | number | readonly string[] | null;
}

export interface ContactSubmitPayload {
  readonly contactId: string;
  readonly workspaceId: string;
  readonly projectId: string;
  readonly questionnaireVersionId: string;
  readonly occurredAtUtc: string;
  readonly occurredTimeZone: string;
  readonly channel: ContactChannel;
  readonly channelDetail: string | null;
  readonly location: ContactLocation;
  readonly reachCount: number;
  readonly interestLevel: number;
  readonly answers: readonly ContactAnswer[];
  readonly sourceAttemptId?: string | null;
}

export interface ContactRevisionPayload {
  readonly contactId: string;
  readonly workspaceId: string;
  readonly projectId: string;
  readonly reason: string;
  readonly occurredAtUtc: string;
  readonly occurredTimeZone: string;
  readonly channel: ContactChannel;
  readonly channelDetail: string | null;
  readonly location: ContactLocation;
  readonly reachCount: number;
  readonly interestLevel: number;
  readonly answers: readonly ContactAnswer[];
}

export interface ContactConflictResolutionPayload
  extends ContactRevisionPayload {
  readonly conflictId: string;
}

export type ContactConflictSnapshot = Omit<
  ContactRevisionPayload,
  "contactId" | "workspaceId" | "projectId" | "reason"
>;

export interface ContactRevisionConflict {
  readonly conflictId: string;
  readonly contactId: string;
  readonly baseRevision: number;
  readonly currentRevision: number;
  readonly conflictingFields: readonly string[];
  readonly questionnaireVersionId: string;
  readonly currentRevisionKind: "corrected";
  readonly currentRevisedAtUtc: string;
  readonly currentReason: string;
  readonly currentSnapshot: ContactConflictSnapshot;
  readonly proposedSnapshot: ContactConflictSnapshot;
}

export interface ContactVoidPayload {
  readonly contactId: string;
  readonly workspaceId: string;
  readonly projectId: string;
  readonly reason: string;
}

export interface ContactAttemptSubmitPayload {
  readonly attemptId: string;
  readonly workspaceId: string;
  readonly projectId: string;
  readonly occurredAtUtc: string;
  readonly occurredTimeZone: string;
  readonly channel: ContactChannel;
  readonly channelDetail: string | null;
}

export interface DraftUpsertPayload {
  readonly draftId: string;
  readonly workspaceId: string;
  readonly projectId: string;
  readonly questionnaireVersionId: string;
  readonly createdAtUtc: string;
  readonly updatedAtUtc: string;
  readonly occurredAtUtc: string | null;
  readonly occurredTimeZone: string | null;
  readonly channel: ContactChannel | null;
  readonly channelDetail: string | null;
  readonly location: ContactLocation | null;
  readonly reachCount: number | null;
  readonly interestLevel: number | null;
  readonly answers: readonly ContactAnswer[];
  readonly sourceAttemptId?: string | null;
}

export interface DraftDeletePayload {
  readonly draftId: string;
  readonly workspaceId: string;
  readonly projectId: string;
  readonly reachCount?: never;
}

interface SyncCommandEnvelope {
  readonly protocolVersion: 1;
  readonly commandId: string;
  readonly deviceId: string;
  readonly aggregateId: string;
  readonly baseRevision: number;
}

export interface ContactSubmitCommand extends SyncCommandEnvelope {
  readonly baseRevision: 0;
  readonly type: "contact.submit.v1";
  readonly payload: ContactSubmitPayload;
}

export interface ContactAttemptSubmitCommand extends SyncCommandEnvelope {
  readonly baseRevision: 0;
  readonly type: "contact.attempt.submit.v1";
  readonly payload: ContactAttemptSubmitPayload;
}

export interface ContactReviseCommand extends SyncCommandEnvelope {
  readonly type: "contact.revise.v1";
  readonly payload: ContactRevisionPayload;
}

export interface ContactVoidCommand extends SyncCommandEnvelope {
  readonly type: "contact.void.v1";
  readonly payload: ContactVoidPayload;
}

export interface ContactConflictResolutionCommand extends SyncCommandEnvelope {
  readonly type: "contact.resolve.v1";
  readonly payload: ContactConflictResolutionPayload;
}

export interface DraftUpsertCommand extends SyncCommandEnvelope {
  readonly type: "draft.upsert.v1";
  readonly payload: DraftUpsertPayload;
}

export interface DraftDeleteCommand extends SyncCommandEnvelope {
  readonly type: "draft.delete.v1";
  readonly payload: DraftDeletePayload;
}

export type SyncCommand =
  | ContactSubmitCommand
  | ContactAttemptSubmitCommand
  | ContactReviseCommand
  | ContactConflictResolutionCommand
  | ContactVoidCommand
  | DraftUpsertCommand
  | DraftDeleteCommand;

export type SyncCommandResult =
  | { readonly result: "accepted"; readonly serverCursor: string }
  | { readonly result: "duplicate"; readonly serverCursor: string }
  | {
      readonly result: "conflict";
      readonly failureCode: string;
      readonly conflict?: ContactRevisionConflict;
    }
  | { readonly result: "rejected"; readonly failureCode: string }
  | { readonly result: "forbidden"; readonly failureCode: string };

export interface SyncCommandStore {
  apply(
    context: SessionContext,
    command: SyncCommand,
  ): Promise<SyncCommandResult>;

  pull(
    context: SessionContext,
    cursor: string | null,
    limit: number,
  ): Promise<SyncPullBatch>;
}

export interface SyncRemoteChange {
  readonly changeType: string;
  readonly revisionNumber: number;
  readonly payload: Readonly<Record<string, unknown>>;
}

export interface SyncPullBatch {
  readonly changes: readonly SyncRemoteChange[];
  readonly nextCursor: string | null;
}

/** PostgreSQL 已确认 cursor 不属于当前可信同步范围。 */
export class InvalidSyncCursorError extends Error {
  constructor() {
    super("Sync cursor is invalid for the trusted scope");
    this.name = "InvalidSyncCursorError";
  }
}

export type SyncQuery = (
  text: string,
  values: readonly unknown[],
) => Promise<{ readonly rows: readonly unknown[] }>;

interface SyncResultRow {
  readonly result_code: unknown;
  readonly server_cursor: unknown;
  readonly failure_code: unknown;
}

interface SyncChangeRow {
  readonly server_cursor: unknown;
  readonly change_type: unknown;
  readonly revision_number: unknown;
  readonly typed_payload: unknown;
}

export class PostgresSyncCommandStore implements SyncCommandStore {
  constructor(private readonly query: SyncQuery) {}

  async apply(
    context: SessionContext,
    command: SyncCommand,
  ): Promise<SyncCommandResult> {
    const functionName = command.type === "contact.submit.v1"
      ? "apply_contact_submit_v2"
      : command.type === "contact.attempt.submit.v1"
      ? "apply_contact_attempt_submit"
      : command.type === "contact.revise.v1"
      ? "apply_contact_revise_v2"
      : command.type === "contact.void.v1"
      ? "apply_contact_void_v2"
      : command.type === "contact.resolve.v1"
      ? "apply_contact_conflict_resolution_v2"
      : command.type === "draft.upsert.v1"
      ? "apply_draft_upsert_v2"
      : "apply_draft_delete";
    const result = await this.query(
      `SELECT result_code, server_cursor, failure_code
       FROM app_data.${functionName}(
         $1::uuid,
         $2::text,
         $3::integer,
         $4::text,
         $5::text,
         $6::text,
         $7::integer,
         $8::jsonb
       )`,
      [
        context.appUserId,
        command.commandId,
        command.protocolVersion,
        command.type,
        command.deviceId,
        command.aggregateId,
        command.baseRevision,
        JSON.stringify(command.payload),
      ],
    );
    if (result.rows.length !== 1) {
      throw new Error("Sync command function must return exactly one row");
    }
    const parsed = parseResultRow(result.rows[0]);
    if (
      parsed.result !== "conflict" ||
      command.type !== "contact.revise.v1" ||
      parsed.failureCode !== "contact_revision_conflict"
    ) {
      return parsed;
    }
    const conflictResult = await this.query(
      `SELECT conflict_payload
       FROM app_data.read_contact_revision_conflict(
         $1::uuid,
         $2::uuid,
         $3::uuid,
         $4::text
       )`,
      [
        context.appUserId,
        context.current.workspace.id,
        context.current.project.id,
        command.commandId,
      ],
    );
    if (conflictResult.rows.length !== 1) {
      throw new Error("Revision conflict must return one authorized record");
    }
    return {
      ...parsed,
      conflict: parseConflictPayload(conflictResult.rows[0]),
    };
  }

  async pull(
    context: SessionContext,
    cursor: string | null,
    limit: number,
  ): Promise<SyncPullBatch> {
    let result: { readonly rows: readonly unknown[] };
    try {
      result = await this.query(
        `SELECT server_cursor, change_type, revision_number, typed_payload
         FROM app_data.pull_sync_changes(
           $1::uuid,
           $2::uuid,
           $3::uuid,
           $4::text,
           $5::integer
         )`,
        [
          context.appUserId,
          context.current.workspace.id,
          context.current.project.id,
          cursor,
          limit,
        ],
      );
    } catch (error) {
      // HTTP 层已限定 scope 与 limit。此函数的 22023 因此表示
      // cursor 不存在，或属于另一个用户、空间或项目。
      if (postgresErrorCode(error) === "22023") {
        throw new InvalidSyncCursorError();
      }
      throw error;
    }
    const changes = result.rows.map(parseChangeRow);
    const lastRow = result.rows.at(-1);
    return {
      changes,
      nextCursor: lastRow === undefined
        ? cursor
        : (lastRow as SyncChangeRow).server_cursor as string,
    };
  }
}

function parseConflictPayload(value: unknown): ContactRevisionConflict {
  const row = record(value, "Revision conflict query returned a non-object row");
  const payload = record(
    row.conflict_payload,
    "Revision conflict payload is missing",
  );
  const fields = payload.conflictingFields;
  if (
    !Array.isArray(fields) ||
    fields.length === 0 ||
    fields.some((field) => typeof field !== "string" || field.length === 0)
  ) {
    throw new Error("Revision conflict fields are invalid");
  }
  return {
    conflictId: requiredString(payload.conflictId, "conflict ID"),
    contactId: requiredString(payload.contactId, "conflict contact ID"),
    baseRevision: positiveInteger(payload.baseRevision, "base revision"),
    currentRevision: positiveInteger(
      payload.currentRevision,
      "current revision",
    ),
    conflictingFields: fields as string[],
    questionnaireVersionId: requiredString(
      payload.questionnaireVersionId,
      "questionnaire version ID",
    ),
    currentRevisionKind: correctedRevisionKind(payload.currentRevisionKind),
    currentRevisedAtUtc: requiredString(
      payload.currentRevisedAtUtc,
      "current revised at",
    ),
    currentReason: requiredString(payload.currentReason, "current reason"),
    currentSnapshot: parseConflictSnapshot(payload.currentSnapshot),
    proposedSnapshot: parseConflictSnapshot(payload.proposedSnapshot),
  };
}

function correctedRevisionKind(value: unknown): "corrected" {
  if (value !== "corrected") {
    throw new Error("Revision conflict current kind is invalid");
  }
  return value;
}

function parseConflictSnapshot(value: unknown): ContactConflictSnapshot {
  const snapshot = record(value, "Revision conflict snapshot is invalid");
  const channel = snapshot.channel;
  const location = snapshot.location;
  const answers = snapshot.answers;
  if (
    !isContactChannel(channel) ||
    typeof location !== "object" ||
    location === null ||
    Array.isArray(location) ||
    !Array.isArray(answers)
  ) {
    throw new Error("Revision conflict snapshot facts are invalid");
  }
  return {
    occurredAtUtc: requiredString(snapshot.occurredAtUtc, "occurred at"),
    occurredTimeZone: requiredString(
      snapshot.occurredTimeZone,
      "occurred time zone",
    ),
    channel,
    channelDetail: nullableResultString(snapshot.channelDetail),
    location: location as ContactLocation,
    reachCount: positiveInteger(snapshot.reachCount, "reach count"),
    interestLevel: boundedInteger(snapshot.interestLevel, 0, 4, "interest"),
    answers: answers as ContactAnswer[],
  };
}

function record(value: unknown, message: string): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error(message);
  }
  return value as Record<string, unknown>;
}

function requiredString(value: unknown, label: string): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`Revision conflict ${label} is invalid`);
  }
  return value;
}

function nullableResultString(value: unknown): string | null {
  if (value === null) {
    return null;
  }
  return requiredString(value, "optional string");
}

function positiveInteger(value: unknown, label: string): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 1) {
    throw new Error(`Revision conflict ${label} is invalid`);
  }
  return value;
}

function boundedInteger(
  value: unknown,
  minimum: number,
  maximum: number,
  label: string,
): number {
  if (
    typeof value !== "number" ||
    !Number.isInteger(value) ||
    value < minimum ||
    value > maximum
  ) {
    throw new Error(`Revision conflict ${label} is invalid`);
  }
  return value;
}

function isContactChannel(value: unknown): value is ContactChannel {
  return value === "face_to_face" ||
    value === "voice_call" ||
    value === "video_call" ||
    value === "instant_text" ||
    value === "asynchronous_message" ||
    value === "mixed" ||
    value === "other_direct";
}

function postgresErrorCode(error: unknown): string | null {
  if (typeof error !== "object" || error === null || !("code" in error)) {
    return null;
  }
  return typeof error.code === "string" ? error.code : null;
}

function parseResultRow(value: unknown): SyncCommandResult {
  if (typeof value !== "object" || value === null) {
    throw new Error("Sync command function returned a non-object row");
  }
  const row = value as SyncResultRow;
  if (row.result_code === "accepted" || row.result_code === "duplicate") {
    if (typeof row.server_cursor !== "string" || row.server_cursor.length === 0) {
      throw new Error("Accepted sync result is missing its cursor");
    }
    return {
      result: row.result_code,
      serverCursor: row.server_cursor,
    };
  }
  if (
    row.result_code === "conflict" ||
    row.result_code === "rejected" ||
    row.result_code === "forbidden"
  ) {
    if (typeof row.failure_code !== "string" || row.failure_code.length === 0) {
      throw new Error("Failed sync result is missing its code");
    }
    return { result: row.result_code, failureCode: row.failure_code };
  }
  throw new Error("Sync command function returned an unsupported result");
}

function parseChangeRow(value: unknown): SyncRemoteChange {
  if (typeof value !== "object" || value === null) {
    throw new Error("Sync pull function returned a non-object row");
  }
  const row = value as SyncChangeRow;
  if (
    typeof row.server_cursor !== "string" ||
    row.server_cursor.length === 0 ||
    typeof row.change_type !== "string" ||
    row.change_type.length === 0 ||
    typeof row.revision_number !== "number" ||
    !Number.isInteger(row.revision_number) ||
    typeof row.typed_payload !== "object" ||
    row.typed_payload === null ||
    Array.isArray(row.typed_payload)
  ) {
    throw new Error("Sync pull function returned an invalid change row");
  }
  return {
    changeType: row.change_type,
    revisionNumber: row.revision_number,
    payload: row.typed_payload as Readonly<Record<string, unknown>>,
  };
}
