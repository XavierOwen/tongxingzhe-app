import {
  IdentityVerificationError,
  type IdentityVerifier,
} from "./identity.js";
import { bearerToken } from "./authorization.js";
import type {
  SessionContext,
  SessionContextStore,
} from "./session-context.js";
import type {
  ContactAnswer,
  ContactAttemptSubmitPayload,
  ContactChannel,
  ContactConflictResolutionPayload,
  ContactLocation,
  ContactLocationSource,
  ContactRevisionPayload,
  ContactSubmitPayload,
  ContactTargetLink,
  ContactVoidPayload,
  DraftDeletePayload,
  DraftUpsertPayload,
  SyncCommand,
  SyncCommandResult,
  SyncCommandStore,
} from "./sync-store.js";

export interface SyncCommandHttpResult {
  readonly status: number;
  readonly body: Readonly<Record<string, unknown>>;
}

export interface SyncCommandHttpDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly contextStore: SessionContextStore;
  readonly commandStore: SyncCommandStore;
}

export async function handleSyncCommand(
  authorization: string | undefined,
  body: unknown,
  dependencies: SyncCommandHttpDependencies,
): Promise<SyncCommandHttpResult> {
  const accessToken = bearerToken(authorization);
  if (accessToken === null) {
    return failure(401, "unauthenticated");
  }

  let context: SessionContext;
  try {
    const identity = await dependencies.identityVerifier.verify(accessToken);
    context = await dependencies.contextStore.loadOrCreate(identity);
  } catch (error) {
    if (error instanceof IdentityVerificationError) {
      return failure(401, "unauthenticated");
    }
    return failure(503, "context_unavailable");
  }

  return handleTrustedSyncCommand(context, body, dependencies);
}

export async function handleSyncCommandBatch(
  authorization: string | undefined,
  body: unknown,
  dependencies: SyncCommandHttpDependencies,
): Promise<SyncCommandHttpResult> {
  const accessToken = bearerToken(authorization);
  if (accessToken === null) {
    return failure(401, "unauthenticated");
  }

  let context: SessionContext;
  try {
    const identity = await dependencies.identityVerifier.verify(accessToken);
    context = await dependencies.contextStore.loadOrCreate(identity);
  } catch (error) {
    if (error instanceof IdentityVerificationError) {
      return failure(401, "unauthenticated");
    }
    return failure(503, "context_unavailable");
  }

  let commands: readonly unknown[];
  try {
    const root = object(body, "invalid_batch");
    if (!Array.isArray(root.commands) || root.commands.length < 1) {
      throw new CommandValidationError("invalid_batch");
    }
    if (root.commands.length > 20) {
      throw new CommandValidationError("batch_too_large");
    }
    commands = root.commands;
  } catch (error) {
    const code = error instanceof CommandValidationError
      ? error.code
      : "invalid_batch";
    return commandFailure(422, "rejected", code);
  }

  let commandIds: string[];
  try {
    commandIds = commands.map(batchCommandId);
  } catch (error) {
    const code = error instanceof CommandValidationError
      ? error.code
      : "invalid_batch_command_id";
    return commandFailure(422, "rejected", code);
  }
  if (new Set(commandIds).size !== commandIds.length) {
    return commandFailure(422, "rejected", "duplicate_batch_command_id");
  }

  const results: Readonly<Record<string, unknown>>[] = [];
  for (let index = 0; index < commands.length; index += 1) {
    const commandId = commandIds[index];
    const command = commands[index];
    if (commandId === undefined || command === undefined) {
      return commandFailure(422, "rejected", "invalid_batch_command_id");
    }
    const result = await handleTrustedSyncCommand(
      context,
      command,
      dependencies,
    );
    if (result.status >= 500) {
      results.push({
        command_id: commandId,
        result: "retryable",
        error: result.body.error ?? { code: "sync_unavailable" },
      });
    } else {
      results.push({ command_id: commandId, ...result.body });
    }
  }
  return { status: 200, body: { results } };
}

async function handleTrustedSyncCommand(
  context: SessionContext,
  body: unknown,
  dependencies: SyncCommandHttpDependencies,
): Promise<SyncCommandHttpResult> {
  let command: SyncCommand;
  try {
    command = parseSyncCommand(body);
  } catch (error) {
    if (error instanceof CommandValidationError) {
      return commandFailure(422, "rejected", error.code);
    }
    return commandFailure(422, "rejected", "invalid_command");
  }

  if (!context.capabilities.includes("record_contact")) {
    return commandFailure(403, "forbidden", "capability_forbidden");
  }
  if (
    "targetLinks" in command.payload &&
    (command.payload.targetLinks?.length ?? 0) > 0 &&
    !context.capabilities.includes("view_assigned_target_pii")
  ) {
    return commandFailure(403, "forbidden", "target_capability_forbidden");
  }
  if (
    command.payload.workspaceId !== context.current.workspace.id ||
    command.payload.projectId !== context.current.project.id
  ) {
    return commandFailure(403, "forbidden", "project_forbidden");
  }

  try {
    return serializeStoreResult(
      await dependencies.commandStore.apply(context, command),
    );
  } catch {
    return failure(503, "sync_unavailable");
  }
}

function batchCommandId(value: unknown): string {
  const root = object(value, "invalid_batch_command_id");
  return string(root.command_id, "invalid_batch_command_id");
}

class CommandValidationError extends Error {
  constructor(readonly code: string) {
    super(code);
    this.name = "CommandValidationError";
  }
}

function parseSyncCommand(value: unknown): SyncCommand {
  const root = object(value, "invalid_command");
  const protocolVersion = integer(root.protocol_version, "invalid_protocol");
  if (protocolVersion !== 1) {
    throw new CommandValidationError("unsupported_protocol");
  }
  const type = string(root.type, "invalid_command_type");
  const baseRevision = integer(root.base_revision, "invalid_base_revision");
  if (baseRevision < 0) {
    throw new CommandValidationError("invalid_base_revision");
  }
  const aggregateId = string(root.aggregate_id, "invalid_aggregate_id");
  const common = {
    protocolVersion: 1 as const,
    commandId: string(root.command_id, "invalid_command_id"),
    deviceId: string(root.device_id, "invalid_device_id"),
    aggregateId,
  };
  if (type === "contact.submit.v1") {
    if (baseRevision !== 0) {
      throw new CommandValidationError("invalid_base_revision");
    }
    const payload = parseContactPayload(root.typed_payload);
    if (payload.contactId !== aggregateId) {
      throw new CommandValidationError("aggregate_id_mismatch");
    }
    return {
      ...common,
      baseRevision: 0,
      type,
      payload,
    };
  }
  if (type === "contact.revise.v1") {
    if (baseRevision < 1) {
      throw new CommandValidationError("invalid_base_revision");
    }
    const payload = parseContactRevisionPayload(root.typed_payload);
    if (payload.contactId !== aggregateId) {
      throw new CommandValidationError("aggregate_id_mismatch");
    }
    return { ...common, baseRevision, type, payload };
  }
  if (type === "contact.resolve.v1") {
    if (baseRevision < 1) {
      throw new CommandValidationError("invalid_base_revision");
    }
    const payload = parseContactConflictResolutionPayload(root.typed_payload);
    if (payload.contactId !== aggregateId) {
      throw new CommandValidationError("aggregate_id_mismatch");
    }
    return { ...common, baseRevision, type, payload };
  }
  if (type === "contact.void.v1") {
    if (baseRevision < 1) {
      throw new CommandValidationError("invalid_base_revision");
    }
    const payload = parseContactVoidPayload(root.typed_payload);
    if (payload.contactId !== aggregateId) {
      throw new CommandValidationError("aggregate_id_mismatch");
    }
    return { ...common, baseRevision, type, payload };
  }
  if (type === "contact.attempt.submit.v1") {
    if (baseRevision !== 0) {
      throw new CommandValidationError("invalid_base_revision");
    }
    const payload = parseContactAttemptPayload(root.typed_payload);
    if (payload.attemptId !== aggregateId) {
      throw new CommandValidationError("aggregate_id_mismatch");
    }
    return { ...common, baseRevision: 0, type, payload };
  }
  if (type === "draft.upsert.v1") {
    const payload = parseDraftUpsertPayload(root.typed_payload);
    if (payload.draftId !== aggregateId) {
      throw new CommandValidationError("aggregate_id_mismatch");
    }
    return { ...common, baseRevision, type, payload };
  }
  if (type === "draft.delete.v1") {
    const payload = parseDraftDeletePayload(root.typed_payload);
    if (payload.draftId !== aggregateId) {
      throw new CommandValidationError("aggregate_id_mismatch");
    }
    return { ...common, baseRevision, type, payload };
  }
  throw new CommandValidationError("unsupported_command_type");
}

function parseDraftUpsertPayload(value: unknown): DraftUpsertPayload {
  const payload = object(value, "invalid_draft_payload");
  const draftId = string(payload.draft_id, "invalid_draft_id");
  const upgradedFromDraftId = nullableString(
    payload.upgraded_from_draft_id,
  );
  if (upgradedFromDraftId === draftId) {
    throw new CommandValidationError("invalid_draft_upgrade_source");
  }
  const createdAtUtc = utcDateString(
    payload.created_at_utc,
    "invalid_created_at",
  );
  const updatedAtUtc = utcDateString(
    payload.updated_at_utc,
    "invalid_updated_at",
  );
  if (Date.parse(updatedAtUtc) < Date.parse(createdAtUtc)) {
    throw new CommandValidationError("invalid_draft_time_order");
  }
  const occurredAtUtc = nullableUtcDateString(payload.occurred_at_utc);
  const occurredTimeZone = nullableString(payload.occurred_time_zone);
  if ((occurredAtUtc === null) !== (occurredTimeZone === null)) {
    throw new CommandValidationError("draft_occurrence_incomplete");
  }
  if (occurredTimeZone !== null) {
    validateTimeZone(occurredTimeZone);
  }
  const rawChannel = payload.channel;
  const channel = rawChannel === null || rawChannel === undefined
    ? null
    : contactChannel(rawChannel);
  const locationResult = payload.location === null || payload.location === undefined
    ? parseNullableDraftLocationSource(payload.location_source)
    : parseLocationWithSource(payload.location, payload.location_source);
  const reachCount = nullableInteger(payload.reach_count, "invalid_reach_count");
  const interestLevel = nullableInteger(
    payload.interest_level,
    "invalid_interest_level",
  );
  if (reachCount !== null && reachCount < 1) {
    throw new CommandValidationError("invalid_reach_count");
  }
  if (interestLevel !== null && (interestLevel < 0 || interestLevel > 4)) {
    throw new CommandValidationError("invalid_interest_level");
  }
  if (!Array.isArray(payload.answers)) {
    throw new CommandValidationError("invalid_answers");
  }
  const answers = payload.answers.map(parseAnswer);
  if (new Set(answers.map((answer) => answer.questionId)).size !== answers.length) {
    throw new CommandValidationError("duplicate_question_answer");
  }
  const targetLinks = parseTargetLinks(payload.target_links);
  return {
    draftId,
    workspaceId: uuid(payload.workspace_id, "invalid_workspace_id"),
    projectId: uuid(payload.project_id, "invalid_project_id"),
    questionnaireVersionId: uuid(
      payload.questionnaire_version_id,
      "invalid_questionnaire_version_id",
    ),
    sourceAttemptId: nullableString(payload.source_attempt_id),
    upgradedFromDraftId,
    createdAtUtc,
    updatedAtUtc,
    occurredAtUtc,
    occurredTimeZone,
    channel,
    channelDetail: nullableString(payload.channel_detail),
    location: locationResult.location,
    ...(locationResult.locationSource === undefined
      ? {}
      : { locationSource: locationResult.locationSource }),
    reachCount,
    interestLevel,
    answers,
    targetLinks,
  };
}

function parseDraftDeletePayload(value: unknown): DraftDeletePayload {
  const payload = object(value, "invalid_draft_payload");
  return {
    draftId: string(payload.draft_id, "invalid_draft_id"),
    workspaceId: uuid(payload.workspace_id, "invalid_workspace_id"),
    projectId: uuid(payload.project_id, "invalid_project_id"),
  };
}

function parseContactPayload(value: unknown): ContactSubmitPayload {
  const payload = object(value, "invalid_contact_payload");
  const facts = parseContactFacts(payload);
  return {
    contactId: string(payload.contact_id, "invalid_contact_id"),
    workspaceId: uuid(payload.workspace_id, "invalid_workspace_id"),
    projectId: uuid(payload.project_id, "invalid_project_id"),
    questionnaireVersionId: uuid(
      payload.questionnaire_version_id,
      "invalid_questionnaire_version_id",
    ),
    ...facts,
    sourceAttemptId: nullableString(payload.source_attempt_id),
  };
}

function parseContactFacts(
  payload: Record<string, unknown>,
): Omit<
  ContactRevisionPayload,
  "contactId" | "workspaceId" | "projectId" | "reason"
> {
  const channel = contactChannel(payload.channel);
  const channelDetail = nullableString(payload.channel_detail);
  if (channel === "other_direct" && channelDetail === null) {
    throw new CommandValidationError("other_channel_detail_required");
  }
  const occurredAtUtc = utcDateString(
    payload.occurred_at_utc,
    "invalid_occurred_at",
  );
  const occurredTimeZone = string(
    payload.occurred_time_zone,
    "invalid_occurred_time_zone",
  );
  validateTimeZone(occurredTimeZone);
  const reachCount = integer(payload.reach_count, "invalid_reach_count");
  if (reachCount < 1) {
    throw new CommandValidationError("invalid_reach_count");
  }
  const interestLevel = integer(
    payload.interest_level,
    "invalid_interest_level",
  );
  if (interestLevel < 0 || interestLevel > 4) {
    throw new CommandValidationError("invalid_interest_level");
  }
  const locationResult = parseLocationWithSource(
    payload.location,
    payload.location_source,
  );
  const location = locationResult.location;
  if (channel === "face_to_face" && location.kind === "not_applicable") {
    throw new CommandValidationError("face_to_face_location_required");
  }
  if (!Array.isArray(payload.answers)) {
    throw new CommandValidationError("invalid_answers");
  }
  const answers = payload.answers.map(parseAnswer);
  if (new Set(answers.map((answer) => answer.questionId)).size !== answers.length) {
    throw new CommandValidationError("duplicate_question_answer");
  }
  const targetLinks = parseTargetLinks(payload.target_links);

  return {
    occurredAtUtc,
    occurredTimeZone,
    channel,
    channelDetail,
    location,
    ...(locationResult.locationSource === undefined
      ? {}
      : { locationSource: locationResult.locationSource }),
    reachCount,
    interestLevel,
    answers,
    targetLinks,
  };
}

function parseTargetLinks(value: unknown): readonly ContactTargetLink[] {
  if (value === undefined) return [];
  if (!Array.isArray(value)) {
    throw new CommandValidationError("invalid_target_links");
  }
  const links = value.map((candidate) => {
    const link = object(candidate, "invalid_target_link");
    const targetType = enumValue(
      link.target_type,
      ["person", "institution"] as const,
    );
    const followUpConsent = enumValue(
      link.follow_up_consent,
      ["yes", "no", "unknown", "refused", "not_applicable"] as const,
    );
    if (targetType === null || followUpConsent === null) {
      throw new CommandValidationError("invalid_target_link");
    }
    const responseLevel = nullableInteger(
      link.response_level,
      "invalid_target_response_level",
    );
    if (responseLevel !== null && (responseLevel < 0 || responseLevel > 4)) {
      throw new CommandValidationError("invalid_target_response_level");
    }
    const institutionRepresentativeConfirmed = boolean(
      link.institution_representative_confirmed,
      "invalid_institution_representative_confirmation",
    );
    const confirmStageZero = boolean(
      link.confirm_stage_zero,
      "invalid_stage_zero_confirmation",
    );
    if (targetType === "person" && institutionRepresentativeConfirmed) {
      throw new CommandValidationError(
        "person_representative_confirmation_forbidden",
      );
    }
    if (
      targetType === "institution" && responseLevel !== null &&
      !institutionRepresentativeConfirmed
    ) {
      throw new CommandValidationError(
        "institution_response_requires_representative",
      );
    }
    return {
      targetId: uuid(link.target_id, "invalid_target_id"),
      targetType,
      responseLevel,
      followUpConsent,
      institutionRepresentativeConfirmed,
      confirmStageZero,
    };
  });
  if (new Set(links.map((link) => link.targetId)).size !== links.length) {
    throw new CommandValidationError("duplicate_contact_target");
  }
  return links;
}

function parseContactRevisionPayload(value: unknown): ContactRevisionPayload {
  const payload = object(value, "invalid_contact_revision_payload");
  const facts = parseContactFacts(payload);
  return {
    contactId: string(payload.contact_id, "invalid_contact_id"),
    workspaceId: uuid(payload.workspace_id, "invalid_workspace_id"),
    projectId: uuid(payload.project_id, "invalid_project_id"),
    reason: string(payload.reason, "contact_reason_required"),
    ...facts,
  };
}

function parseContactConflictResolutionPayload(
  value: unknown,
): ContactConflictResolutionPayload {
  const payload = object(value, "invalid_contact_resolution_payload");
  return {
    ...parseContactRevisionPayload(payload),
    conflictId: uuid(payload.conflict_id, "invalid_conflict_id"),
  };
}

function parseContactVoidPayload(value: unknown): ContactVoidPayload {
  const payload = object(value, "invalid_contact_void_payload");
  if ("location" in payload || "location_source" in payload) {
    throw new CommandValidationError("contact_void_location_forbidden");
  }
  return {
    contactId: string(payload.contact_id, "invalid_contact_id"),
    workspaceId: uuid(payload.workspace_id, "invalid_workspace_id"),
    projectId: uuid(payload.project_id, "invalid_project_id"),
    reason: string(payload.reason, "contact_reason_required"),
  };
}

function parseContactAttemptPayload(
  value: unknown,
): ContactAttemptSubmitPayload {
  const payload = object(value, "invalid_contact_attempt_payload");
  if (
    "reach_count" in payload ||
    "interest_level" in payload ||
    "answers" in payload ||
    "relationship_stage" in payload
  ) {
    throw new CommandValidationError("contact_attempt_forbidden_field");
  }
  const channel = contactChannel(payload.channel);
  const channelDetail = nullableString(payload.channel_detail);
  if (channel === "other_direct" && channelDetail === null) {
    throw new CommandValidationError("other_channel_detail_required");
  }
  const occurredAtUtc = utcDateString(
    payload.occurred_at_utc,
    "invalid_occurred_at",
  );
  const occurredTimeZone = string(
    payload.occurred_time_zone,
    "invalid_occurred_time_zone",
  );
  validateTimeZone(occurredTimeZone);
  return {
    attemptId: string(payload.attempt_id, "invalid_attempt_id"),
    workspaceId: uuid(payload.workspace_id, "invalid_workspace_id"),
    projectId: uuid(payload.project_id, "invalid_project_id"),
    occurredAtUtc,
    occurredTimeZone,
    channel,
    channelDetail,
  };
}

const wireLocationKeys = new Set([
  "kind",
  "place_name",
  "smallest_region_id",
  "region_tree_version",
  "latitude",
  "longitude",
  "accuracy_meters",
]);

function parseLocationWithSource(
  locationValue: unknown,
  sourceValue: unknown,
): {
  readonly location: ContactLocation;
  readonly locationSource: ContactLocationSource | undefined;
} {
  const location = parseWireLocation(locationValue);
  const locationSource = parseWireLocationSource(sourceValue);
  if (locationSource !== undefined && location.kind !== "resolved") {
    throw new CommandValidationError("location_source_forbidden");
  }
  return { location, locationSource };
}

function parseNullableDraftLocationSource(value: unknown): {
  readonly location: null;
  readonly locationSource: undefined;
} {
  if (value !== undefined && value !== null) {
    throw new CommandValidationError("location_source_forbidden");
  }
  return { location: null, locationSource: undefined };
}

function parseWireLocation(value: unknown): ContactLocation {
  const location = object(value, "invalid_location");
  assertExactKeys(location, wireLocationKeys, "invalid_location_shape");
  if (location.kind === "not_applicable") {
    assertNullOrMissingLocationFields(location, [
      "place_name",
      "smallest_region_id",
      "region_tree_version",
      "latitude",
      "longitude",
      "accuracy_meters",
    ]);
    return { kind: "not_applicable" };
  }
  if (location.kind === "resolved") {
    assertNullOrMissingLocationFields(location, [
      "latitude",
      "longitude",
      "accuracy_meters",
    ]);
    return {
      kind: "resolved",
      placeName: string(location.place_name, "invalid_place_name"),
      smallestRegionId: string(
        location.smallest_region_id,
        "invalid_region_id",
      ),
      regionTreeVersion: string(
        location.region_tree_version,
        "invalid_region_tree_version",
      ),
    };
  }
  if (location.kind === "pending_resolution") {
    const latitude = finiteNumber(location.latitude, "invalid_latitude");
    const longitude = finiteNumber(location.longitude, "invalid_longitude");
    const accuracy = nullableFiniteNumber(
      location.accuracy_meters,
      "invalid_location_accuracy",
    );
    if (
      latitude < -90 ||
      latitude > 90 ||
      longitude < -180 ||
      longitude > 180 ||
      (accuracy !== null && accuracy < 0)
    ) {
      throw new CommandValidationError("invalid_location");
    }
    return {
      kind: "pending_resolution",
      latitude,
      longitude,
      accuracyMeters: accuracy,
    };
  }
  throw new CommandValidationError("invalid_location_kind");
}

function parseWireLocationSource(value: unknown): ContactLocationSource | undefined {
  if (value === null || value === undefined) {
    return undefined;
  }
  const source = object(value, "invalid_location_source");
  assertExactKeys(
    source,
    new Set([
      "kind",
      "latitude",
      "longitude",
      "accuracy_meters",
      "resolver_contract_version",
      "region_tree_content_fingerprint",
    ]),
    "invalid_location_source_shape",
  );
  if (source.kind !== "captured_coordinates") {
    throw new CommandValidationError("invalid_location_source_kind");
  }
  const latitude = finiteNumber(
    source.latitude,
    "invalid_location_source_coordinates",
  );
  const longitude = finiteNumber(
    source.longitude,
    "invalid_location_source_coordinates",
  );
  const accuracy = nullableFiniteNumber(
    source.accuracy_meters,
    "invalid_location_source_accuracy",
  );
  if (
    latitude < -90 ||
    latitude > 90 ||
    longitude < -180 ||
    longitude > 180 ||
    (accuracy !== null && accuracy < 0)
  ) {
    throw new CommandValidationError("invalid_location_source_coordinates");
  }
  const resolverContractVersion = string(
    source.resolver_contract_version,
    "invalid_location_source_contract",
  );
  if (resolverContractVersion !== "canonical-region-resolution:v1") {
    throw new CommandValidationError("invalid_location_source_contract");
  }
  const fingerprint = string(
    source.region_tree_content_fingerprint,
    "invalid_location_source_fingerprint",
  );
  if (!/^[0-9a-f]{64}$/.test(fingerprint)) {
    throw new CommandValidationError("invalid_location_source_fingerprint");
  }
  return {
    kind: "captured_coordinates",
    latitude,
    longitude,
    accuracyMeters: accuracy,
    resolverContractVersion,
    regionTreeContentFingerprint: fingerprint,
  };
}

function assertExactKeys(
  value: Record<string, unknown>,
  allowed: ReadonlySet<string>,
  message: string,
): void {
  for (const key of Object.keys(value)) {
    if (!allowed.has(key)) {
      throw new CommandValidationError(message);
    }
  }
}

function assertNullOrMissingLocationFields(
  value: Record<string, unknown>,
  fields: readonly string[],
): void {
  for (const field of fields) {
    const candidate = value[field];
    if (candidate !== undefined && candidate !== null) {
      throw new CommandValidationError("invalid_location");
    }
  }
}

function parseAnswer(value: unknown): ContactAnswer {
  const answer = object(value, "invalid_answer");
  const type = answer.type;
  if (
    type !== "boolean" &&
    type !== "single_choice" &&
    type !== "ordinal_choice" &&
    type !== "multi_choice" &&
    type !== "number" &&
    type !== "date" &&
    type !== "short_text" &&
    type !== "long_text"
  ) {
    throw new CommandValidationError("unsupported_answer_type");
  }
  const state = answer.state;
  if (
    state !== "answered" &&
    state !== "unknown" &&
    state !== "refused" &&
    state !== "not_applicable" &&
    state !== "unanswered"
  ) {
    throw new CommandValidationError("invalid_answer_state");
  }
  const rawValue = answer.value;
  const stateReason = answer.state_reason === undefined ||
      answer.state_reason === null
    ? null
    : answer.state_reason === "rule_skipped"
    ? "rule_skipped"
    : (() => {
      throw new CommandValidationError("invalid_answer_state_reason");
    })();
  if (state !== "answered") {
    if (
      rawValue !== null ||
      (stateReason !== null && state !== "not_applicable")
    ) {
      throw new CommandValidationError("invalid_answer_value_shape");
    }
    return {
      questionId: string(answer.question_id, "invalid_question_id"),
      state,
      stateReason,
      type,
      value: null,
    };
  }
  const parsedValue = type === "boolean"
    ? typeof rawValue === "boolean"
      ? rawValue
      : null
    : type === "number"
    ? typeof rawValue === "number" && Number.isFinite(rawValue)
      ? rawValue
      : null
    : type === "multi_choice"
    ? Array.isArray(rawValue) &&
        rawValue.every((item): item is string => typeof item === "string")
      ? rawValue
      : null
    : typeof rawValue === "string"
    ? rawValue
    : null;
  if (parsedValue === null) {
    throw new CommandValidationError("invalid_answer_value_shape");
  }
  if (stateReason !== null) {
    throw new CommandValidationError("invalid_answer_state_reason");
  }
  return {
    questionId: string(answer.question_id, "invalid_question_id"),
    state,
    stateReason,
    type,
    value: parsedValue,
  };
}

function serializeStoreResult(result: SyncCommandResult): SyncCommandHttpResult {
  if (result.result === "accepted" || result.result === "duplicate") {
    return {
      status: 200,
      body: {
        result: result.result,
        server_cursor: result.serverCursor,
      },
    };
  }
  const status = result.result === "conflict" ? 409 : result.result === "forbidden" ? 403 : 422;
  const serialized = commandFailure(status, result.result, result.failureCode);
  if (result.result !== "conflict" || result.conflict === undefined) {
    return serialized;
  }
  return {
    status,
    body: {
      ...serialized.body,
      conflict: {
        conflict_id: result.conflict.conflictId,
        contact_id: result.conflict.contactId,
        base_revision: result.conflict.baseRevision,
        current_revision: result.conflict.currentRevision,
        conflicting_fields: result.conflict.conflictingFields,
        questionnaire_version_id: result.conflict.questionnaireVersionId,
        current_revision_kind: result.conflict.currentRevisionKind,
        current_revised_at_utc: result.conflict.currentRevisedAtUtc,
        current_reason: result.conflict.currentReason,
        current_snapshot: result.conflict.currentSnapshot,
        proposed_snapshot: result.conflict.proposedSnapshot,
      },
    },
  };
}

function failure(status: number, code: string): SyncCommandHttpResult {
  return { status, body: { error: { code } } };
}

function commandFailure(
  status: number,
  result: "conflict" | "rejected" | "forbidden",
  code: string,
): SyncCommandHttpResult {
  return { status, body: { result, error: { code } } };
}

function object(value: unknown, code: string): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new CommandValidationError(code);
  }
  return value as Record<string, unknown>;
}

function string(value: unknown, code: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new CommandValidationError(code);
  }
  return value.trim();
}

function nullableString(value: unknown): string | null {
  if (value === null || value === undefined) {
    return null;
  }
  return string(value, "invalid_optional_string");
}

function integer(value: unknown, code: string): number {
  if (typeof value !== "number" || !Number.isInteger(value)) {
    throw new CommandValidationError(code);
  }
  return value;
}

function nullableInteger(value: unknown, code: string): number | null {
  return value === null || value === undefined ? null : integer(value, code);
}

function boolean(value: unknown, code: string): boolean {
  if (typeof value !== "boolean") {
    throw new CommandValidationError(code);
  }
  return value;
}

function enumValue<T extends string>(
  value: unknown,
  values: readonly T[],
): T | null {
  return typeof value === "string" && values.includes(value as T)
    ? value as T
    : null;
}

function utcDateString(value: unknown, code: string): string {
  const parsed = string(value, code);
  if (!parsed.endsWith("Z") || Number.isNaN(Date.parse(parsed))) {
    throw new CommandValidationError(code);
  }
  return parsed;
}

function nullableUtcDateString(value: unknown): string | null {
  return value === null || value === undefined
    ? null
    : utcDateString(value, "invalid_occurred_at");
}

function validateTimeZone(value: string): void {
  try {
    new Intl.DateTimeFormat("en", { timeZone: value }).format();
  } catch {
    throw new CommandValidationError("invalid_occurred_time_zone");
  }
}

function finiteNumber(value: unknown, code: string): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new CommandValidationError(code);
  }
  return value;
}

function nullableFiniteNumber(value: unknown, code: string): number | null {
  if (value === null || value === undefined) {
    return null;
  }
  return finiteNumber(value, code);
}

function uuid(value: unknown, code: string): string {
  const parsed = string(value, code);
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(parsed)) {
    throw new CommandValidationError(code);
  }
  return parsed;
}

function contactChannel(value: unknown): ContactChannel {
  if (
    value === "face_to_face" ||
    value === "voice_call" ||
    value === "video_call" ||
    value === "instant_text" ||
    value === "asynchronous_message" ||
    value === "mixed" ||
    value === "other_direct"
  ) {
    return value;
  }
  throw new CommandValidationError("invalid_channel");
}
