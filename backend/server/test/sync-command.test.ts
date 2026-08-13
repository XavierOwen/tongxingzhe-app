import assert from "node:assert/strict";
import test from "node:test";

import {
  handleSyncCommandBatch,
  handleSyncCommand,
  type SyncCommandHttpDependencies,
} from "../src/sync-command.js";
import { syncContractV1Fixture } from "./fixtures/sync-contract-v1.js";
import type { VerifiedIdentity } from "../src/identity.js";
import type { SessionContext } from "../src/session-context.js";
import type {
  SyncCommand,
  SyncCommandResult,
} from "../src/sync-store.js";

const identity: VerifiedIdentity = {
  issuer: "https://synthetic.supabase.co/auth/v1",
  subject: "synthetic-subject",
};

const context: SessionContext = {
  appUserId: "11111111-1111-4111-8111-111111111111",
  current: {
    workspace: {
      id: "22222222-2222-4222-8222-222222222222",
      kind: "personal",
      name: "个人空间",
    },
    project: {
      id: "33333333-3333-4333-8333-333333333333",
      name: "我的推广项目",
    },
    questionnaireVersion: {
      id: "44444444-4444-4444-8444-444444444444",
      versionNumber: 1,
    },
  },
  capabilities: ["record_contact"],
};

test("verified command uses internal context and returns accepted cursor", async () => {
  var storedContext: SessionContext | undefined;
  var storedCommand: SyncCommand | undefined;
  const dependencies = fakeDependencies({
    apply: async (resolvedContext, command) => {
      storedContext = resolvedContext;
      storedCommand = command;
      return { result: "accepted", serverCursor: "opaque-1" };
    },
  });

  const response = await handleSyncCommand(
    "Bearer synthetic-token",
    validCommandBody(),
    dependencies,
  );

  assert.equal(response.status, 200);
  assert.deepEqual(response.body, {
    result: "accepted",
    server_cursor: "opaque-1",
  });
  assert.equal(storedContext, context);
  assert.equal(storedCommand?.commandId, "command-1");
  assert.equal(storedCommand?.type, "contact.submit.v1");
  if (storedCommand?.type === "contact.submit.v1") {
    assert.equal(storedCommand.payload.reachCount, 2);
  }
  assert.equal("appUserId" in (storedCommand ?? {}), false);
});

test("captured location source round-trips from snake_case wire payload", async () => {
  let storedCommand: SyncCommand | undefined;
  const body = validCommandBody();
  (body.typed_payload as Record<string, unknown>).location = {
    kind: "resolved",
    place_name: "University of Chicago",
    smallest_region_id: "uchicago",
    region_tree_version: "synthetic-v1",
  };
  (body.typed_payload as Record<string, unknown>).location_source = {
    kind: "captured_coordinates",
    latitude: 41.7897,
    longitude: -87.5997,
    accuracy_meters: 8.5,
    resolver_contract_version: "canonical-region-resolution:v1",
    region_tree_content_fingerprint:
      "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
  };

  const response = await handleSyncCommand(
    "Bearer synthetic-token",
    body,
    fakeDependencies({
      apply: async (_resolvedContext, command) => {
        storedCommand = command;
        return { result: "accepted", serverCursor: "opaque-source" };
      },
    }),
  );

  assert.equal(response.status, 200);
  assert.equal(storedCommand?.type, "contact.submit.v1");
  if (storedCommand?.type === "contact.submit.v1") {
    assert.deepEqual(storedCommand.payload.location, {
      kind: "resolved",
      placeName: "University of Chicago",
      smallestRegionId: "uchicago",
      regionTreeVersion: "synthetic-v1",
    });
    assert.deepEqual(storedCommand.payload.locationSource, {
      kind: "captured_coordinates",
      latitude: 41.7897,
      longitude: -87.5997,
      accuracyMeters: 8.5,
      resolverContractVersion: "canonical-region-resolution:v1",
      regionTreeContentFingerprint:
        "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    });
  }
});

test("location source rejects unknown keys without echoing coordinates", async () => {
  const body = validCommandBody();
  (body.typed_payload as Record<string, unknown>).location = {
    kind: "resolved",
    place_name: "University of Chicago",
    smallest_region_id: "uchicago",
    region_tree_version: "synthetic-v1",
  };
  (body.typed_payload as Record<string, unknown>).location_source = {
    kind: "captured_coordinates",
    latitude: 41.7897,
    longitude: -87.5997,
    accuracy_meters: 8.5,
    resolver_contract_version: "canonical-region-resolution:v1",
    region_tree_content_fingerprint:
      "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    unexpected: "must-reject",
  };

  const response = await handleSyncCommand(
    "Bearer synthetic-token",
    body,
    fakeDependencies(),
  );

  assert.deepEqual(response.body, {
    result: "rejected",
    error: { code: "invalid_location_source_shape" },
  });
  assert.equal(JSON.stringify(response.body).includes("41.7897"), false);
  assert.equal(JSON.stringify(response.body).includes("-87.5997"), false);
});

test("pending and not-applicable locations cannot carry a captured source", async () => {
  const source = {
    kind: "captured_coordinates",
    latitude: 41.7897,
    longitude: -87.5997,
    accuracy_meters: null,
    resolver_contract_version: "canonical-region-resolution:v1",
    region_tree_content_fingerprint:
      "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
  };
  const pending = validCommandBody();
  const pendingPayload = pending.typed_payload as Record<string, unknown>;
  pendingPayload.location = {
    kind: "pending_resolution",
    latitude: 41.7897,
    longitude: -87.5997,
    accuracy_meters: 8.5,
  };
  pendingPayload.location_source = source;
  const pendingResponse = await handleSyncCommand(
    "Bearer synthetic-token",
    pending,
    fakeDependencies(),
  );
  assert.deepEqual(pendingResponse.body, {
    result: "rejected",
    error: { code: "location_source_forbidden" },
  });

  const notApplicable = validCommandBody();
  const notApplicablePayload = notApplicable.typed_payload as Record<string, unknown>;
  notApplicablePayload.location_source = source;
  const notApplicableResponse = await handleSyncCommand(
    "Bearer synthetic-token",
    notApplicable,
    fakeDependencies(),
  );
  assert.deepEqual(notApplicableResponse.body, {
    result: "rejected",
    error: { code: "location_source_forbidden" },
  });
});

test("non-finite source coordinates are rejected without leaking their values", async () => {
  const body = validCommandBody();
  const payload = body.typed_payload as Record<string, unknown>;
  payload.location = {
    kind: "resolved",
    place_name: "University of Chicago",
    smallest_region_id: "uchicago",
    region_tree_version: "synthetic-v1",
  };
  payload.location_source = {
    kind: "captured_coordinates",
    latitude: Number.POSITIVE_INFINITY,
    longitude: -87.5997,
    accuracy_meters: 8.5,
    resolver_contract_version: "canonical-region-resolution:v1",
    region_tree_content_fingerprint:
      "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
  };

  const response = await handleSyncCommand(
    "Bearer synthetic-token",
    body,
    fakeDependencies(),
  );

  assert.deepEqual(response.body, {
    result: "rejected",
    error: { code: "invalid_location_source_coordinates" },
  });
  assert.equal(JSON.stringify(response.body).includes("Infinity"), false);
  assert.equal(JSON.stringify(response.body).includes("-87.5997"), false);
});

test("location rejects unknown keys even when the source is absent", async () => {
  const body = validCommandBody();
  const payload = body.typed_payload as Record<string, unknown>;
  payload.location = {
    kind: "resolved",
    place_name: "University of Chicago",
    smallest_region_id: "uchicago",
    region_tree_version: "synthetic-v1",
    latitude: null,
    longitude: null,
    accuracy_meters: null,
    undocumented: "must-reject",
  };
  const response = await handleSyncCommand(
    "Bearer synthetic-token",
    body,
    fakeDependencies(),
  );
  assert.deepEqual(response.body, {
    result: "rejected",
    error: { code: "invalid_location_shape" },
  });
});

test("pending location rejects resolved-region fields", async () => {
  const body = validCommandBody();
  const payload = body.typed_payload as Record<string, unknown>;
  payload.location = {
    kind: "pending_resolution",
    latitude: 41.7897,
    longitude: -87.5997,
    accuracy_meters: 8.5,
    place_name: "must-not-be-ignored",
    smallest_region_id: "must-not-be-ignored",
    region_tree_version: "must-not-be-ignored",
  };

  const response = await handleSyncCommand(
    "Bearer synthetic-token",
    body,
    fakeDependencies(),
  );

  assert.deepEqual(response.body, {
    result: "rejected",
    error: { code: "invalid_location" },
  });
});

test("sync parser preserves all controlled answer value shapes", async () => {
  let storedCommand: SyncCommand | undefined;
  const body = validCommandBody();
  const typedAnswers = [
    { question_id: "boolean", state: "answered", type: "boolean", value: true },
    { question_id: "single", state: "answered", type: "single_choice", value: "one" },
    { question_id: "ordinal", state: "answered", type: "ordinal_choice", value: "high" },
    { question_id: "multi", state: "answered", type: "multi_choice", value: ["one", "two"] },
    { question_id: "number", state: "answered", type: "number", value: 2.5 },
    { question_id: "date", state: "answered", type: "date", value: "2030-02-28" },
    { question_id: "short", state: "answered", type: "short_text", value: "short" },
    { question_id: "long", state: "refused", type: "long_text", value: null },
    { question_id: "skipped", state: "not_applicable", state_reason: "rule_skipped", type: "long_text", value: null },
  ];
  (body.typed_payload as Record<string, unknown>).answers = typedAnswers;

  const response = await handleSyncCommand(
    "Bearer synthetic-token",
    body,
    fakeDependencies({
      apply: async (_resolvedContext, command) => {
        storedCommand = command;
        return { result: "accepted", serverCursor: "opaque-typed" };
      },
    }),
  );

  assert.equal(response.status, 200);
  assert.equal(storedCommand?.type, "contact.submit.v1");
  if (storedCommand?.type === "contact.submit.v1") {
    assert.deepEqual(storedCommand.payload.answers, typedAnswers.map((answer) => ({
      questionId: answer.question_id,
      state: answer.state,
      stateReason: "state_reason" in answer ? answer.state_reason : null,
      type: answer.type,
      value: answer.value,
    })));
  }
});

test("target links require target access and preserve controlled facts", async () => {
  let storedCommand: SyncCommand | undefined;
  const body = validCommandBody();
  (body.typed_payload as Record<string, unknown>).target_links = [
    {
      target_id: "55555555-5555-4555-8555-555555555555",
      target_type: "institution",
      response_level: 4,
      follow_up_consent: "yes",
      institution_representative_confirmed: true,
      confirm_stage_zero: true,
    },
  ];

  const forbidden = await handleSyncCommand(
    "Bearer synthetic-token",
    body,
    fakeDependencies(),
  );
  assert.equal(forbidden.status, 403);
  assert.deepEqual(forbidden.body, {
    result: "forbidden",
    error: { code: "target_capability_forbidden" },
  });

  const accepted = await handleSyncCommand(
    "Bearer synthetic-token",
    body,
    fakeDependencies({
      context: {
        ...context,
        capabilities: ["record_contact", "view_assigned_target_pii"],
      },
      apply: async (_resolvedContext, command) => {
        storedCommand = command;
        return { result: "accepted", serverCursor: "opaque-target" };
      },
    }),
  );

  assert.equal(accepted.status, 200);
  assert.equal(storedCommand?.type, "contact.submit.v1");
  if (storedCommand?.type === "contact.submit.v1") {
    assert.deepEqual(storedCommand.payload.targetLinks, [
      {
        targetId: "55555555-5555-4555-8555-555555555555",
        targetType: "institution",
        responseLevel: 4,
        followUpConsent: "yes",
        institutionRepresentativeConfirmed: true,
        confirmStageZero: true,
      },
    ]);
  }
});

test("invalid or duplicate target links fail before store", async () => {
  var storeCalls = 0;
  const body = validCommandBody();
  const invalidLink = {
    target_id: "55555555-5555-4555-8555-555555555555",
    target_type: "institution",
    response_level: 4,
    follow_up_consent: "unknown",
    institution_representative_confirmed: false,
    confirm_stage_zero: false,
  };
  (body.typed_payload as Record<string, unknown>).target_links = [invalidLink];
  const invalid = await handleSyncCommand(
    "Bearer synthetic-token",
    body,
    fakeDependencies({
      context: {
        ...context,
        capabilities: ["record_contact", "view_assigned_target_pii"],
      },
      apply: async () => {
        storeCalls += 1;
        return { result: "accepted", serverCursor: "unused" };
      },
    }),
  );
  assert.deepEqual(invalid.body, {
    result: "rejected",
    error: { code: "institution_response_requires_representative" },
  });

  (body.typed_payload as Record<string, unknown>).target_links = [
    { ...invalidLink, response_level: null },
    { ...invalidLink, response_level: null },
  ];
  const duplicate = await handleSyncCommand(
    "Bearer synthetic-token",
    body,
    fakeDependencies({
      context: {
        ...context,
        capabilities: ["record_contact", "view_assigned_target_pii"],
      },
    }),
  );
  assert.deepEqual(duplicate.body, {
    result: "rejected",
    error: { code: "duplicate_contact_target" },
  });
  assert.equal(storeCalls, 0);
});

test("duplicate command returns its original cursor", async () => {
  const dependencies = fakeDependencies({
    apply: async () => ({
      result: "duplicate",
      serverCursor: "opaque-original",
    }),
  });

  const response = await handleSyncCommand(
    "Bearer synthetic-token",
    validCommandBody(),
    dependencies,
  );

  assert.deepEqual(response.body, {
    result: "duplicate",
    server_cursor: "opaque-original",
  });
});

test("forged project and missing capability fail before store", async () => {
  var storeCalls = 0;
  const apply = async (): Promise<SyncCommandResult> => {
    storeCalls += 1;
    return { result: "accepted", serverCursor: "unused" };
  };
  const forged = validCommandBody();
  const forgedPayload = forged.typed_payload as Record<string, unknown>;
  forgedPayload.project_id = "99999999-9999-4999-8999-999999999999";

  const forgedResponse = await handleSyncCommand(
    "Bearer synthetic-token",
    forged,
    fakeDependencies({ apply }),
  );
  assert.equal(forgedResponse.status, 403);
  assert.deepEqual(forgedResponse.body, {
    result: "forbidden",
    error: { code: "project_forbidden" },
  });

  const noCapabilityResponse = await handleSyncCommand(
    "Bearer synthetic-token",
    validCommandBody(),
    fakeDependencies({
      context: { ...context, capabilities: [] },
      apply,
    }),
  );
  assert.equal(noCapabilityResponse.status, 403);
  assert.equal(storeCalls, 0);
});

test("malformed contact payload returns stable rejected result", async () => {
  const body = validCommandBody();
  const payload = body.typed_payload as Record<string, unknown>;
  payload.interest_level = 9;

  const response = await handleSyncCommand(
    "Bearer synthetic-token",
    body,
    fakeDependencies(),
  );

  assert.equal(response.status, 422);
  assert.deepEqual(response.body, {
    result: "rejected",
    error: { code: "invalid_interest_level" },
  });
});

test("private draft upsert keeps trusted owner outside the client payload", async () => {
  let storedCommand: SyncCommand | undefined;
  const response = await handleSyncCommand(
    "Bearer synthetic-token",
    validDraftCommandBody(),
    fakeDependencies({
      apply: async (_resolvedContext, command) => {
        storedCommand = command;
        return { result: "accepted", serverCursor: "opaque-draft-1" };
      },
    }),
  );

  assert.equal(response.status, 200);
  assert.equal(storedCommand?.type, "draft.upsert.v1");
  assert.equal(storedCommand?.baseRevision, 0);
  assert.equal(storedCommand?.payload.projectId, context.current.project.id);
  assert.equal(
    storedCommand?.payload.upgradedFromDraftId,
    "source-draft-1",
  );
  assert.equal("appUserId" in (storedCommand?.payload ?? {}), false);
});

test("draft upsert preserves a resolved location source and normalizes null", async () => {
  let storedCommand: SyncCommand | undefined;
  const body = validDraftCommandBody();
  const payload = body.typed_payload as Record<string, unknown>;
  payload.location = {
    kind: "resolved",
    place_name: "University of Chicago",
    smallest_region_id: "uchicago",
    region_tree_version: "synthetic-v1",
  };
  payload.location_source = {
    kind: "captured_coordinates",
    latitude: 41.7897,
    longitude: -87.5997,
    accuracy_meters: null,
    resolver_contract_version: "canonical-region-resolution:v1",
    region_tree_content_fingerprint:
      "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
  };
  const response = await handleSyncCommand(
    "Bearer synthetic-token",
    body,
    fakeDependencies({
      apply: async (_resolvedContext, command) => {
        storedCommand = command;
        return { result: "accepted", serverCursor: "opaque-draft-source" };
      },
    }),
  );
  assert.equal(response.status, 200);
  assert.equal(storedCommand?.type, "draft.upsert.v1");
  if (storedCommand?.type === "draft.upsert.v1") {
    assert.deepEqual(storedCommand.payload.locationSource, {
      kind: "captured_coordinates",
      latitude: 41.7897,
      longitude: -87.5997,
      accuracyMeters: null,
      resolverContractVersion: "canonical-region-resolution:v1",
      regionTreeContentFingerprint:
        "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    });
  }

  const nullSource = validDraftCommandBody();
  const nullPayload = nullSource.typed_payload as Record<string, unknown>;
  nullPayload.location_source = null;
  const nullResponse = await handleSyncCommand(
    "Bearer synthetic-token",
    nullSource,
    fakeDependencies({
      apply: async (_resolvedContext, command) => {
        storedCommand = command;
        return { result: "accepted", serverCursor: "opaque-draft-null-source" };
      },
    }),
  );
  assert.equal(nullResponse.status, 200);
  assert.equal(storedCommand?.type, "draft.upsert.v1");
  if (storedCommand?.type === "draft.upsert.v1") {
    assert.equal("locationSource" in storedCommand.payload, false);
  }
});

test("draft upgrade source cannot point to the new draft itself", async () => {
  const body = validDraftCommandBody();
  const payload = body.typed_payload as Record<string, unknown>;
  payload.upgraded_from_draft_id = payload.draft_id;

  const response = await handleSyncCommand(
    "Bearer synthetic-token",
    body,
    fakeDependencies(),
  );

  assert.deepEqual(response.body, {
    result: "rejected",
    error: { code: "invalid_draft_upgrade_source" },
  });
});

test("contact attempt has no reach, interest, or questionnaire facts", async () => {
  let storedCommand: SyncCommand | undefined;
  const response = await handleSyncCommand(
    "Bearer synthetic-token",
    validAttemptCommandBody(),
    fakeDependencies({
      apply: async (_resolvedContext, command) => {
        storedCommand = command;
        return { result: "accepted", serverCursor: "opaque-attempt-1" };
      },
    }),
  );

  assert.equal(response.status, 200);
  assert.equal(storedCommand?.type, "contact.attempt.submit.v1");
  assert.deepEqual(storedCommand?.payload, {
    attemptId: "attempt-1",
    workspaceId: context.current.workspace.id,
    projectId: context.current.project.id,
    occurredAtUtc: "2030-01-08T18:00:00.000Z",
    occurredTimeZone: "America/Chicago",
    channel: "voice_call",
    channelDetail: null,
  });
});

test("contact attempt rejects contact metric fields", async () => {
  const body = validAttemptCommandBody();
  (body.typed_payload as Record<string, unknown>).reach_count = 0;

  const response = await handleSyncCommand(
    "Bearer synthetic-token",
    body,
    fakeDependencies(),
  );

  assert.deepEqual(response.body, {
    result: "rejected",
    error: { code: "contact_attempt_forbidden_field" },
  });
});

test("contact revision requires a reason and keeps its base revision", async () => {
  let storedCommand: SyncCommand | undefined;
  const response = await handleSyncCommand(
    "Bearer synthetic-token",
    validRevisionCommandBody(),
    fakeDependencies({
      apply: async (_resolvedContext, command) => {
        storedCommand = command;
        return { result: "accepted", serverCursor: "opaque-revision-2" };
      },
    }),
  );

  assert.equal(response.status, 200);
  assert.equal(storedCommand?.type, "contact.revise.v1");
  assert.equal(storedCommand?.baseRevision, 1);
  if (storedCommand?.type === "contact.revise.v1") {
    assert.equal(storedCommand.payload.reason, "修正发生日期");
    assert.equal(storedCommand.payload.reachCount, 3);
  }

  const withoutReason = validRevisionCommandBody();
  (withoutReason.typed_payload as Record<string, unknown>).reason = "   ";
  const rejected = await handleSyncCommand(
    "Bearer synthetic-token",
    withoutReason,
    fakeDependencies(),
  );
  assert.deepEqual(rejected.body, {
    result: "rejected",
    error: { code: "contact_reason_required" },
  });
});

test("revise and conflict-resolution commands share the location source codec", async () => {
  const source = {
    kind: "captured_coordinates",
    latitude: 41.7897,
    longitude: -87.5997,
    accuracy_meters: 8.5,
    resolver_contract_version: "canonical-region-resolution:v1",
    region_tree_content_fingerprint:
      "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
  };
  for (const commandType of ["contact.revise.v1", "contact.resolve.v1"] as const) {
    let storedCommand: SyncCommand | undefined;
    const body = commandType === "contact.revise.v1"
      ? validRevisionCommandBody()
      : validResolutionCommandBody();
    const payload = body.typed_payload as Record<string, unknown>;
    payload.location = {
      kind: "resolved",
      place_name: "University of Chicago",
      smallest_region_id: "uchicago",
      region_tree_version: "synthetic-v1",
    };
    payload.location_source = source;
    const response = await handleSyncCommand(
      "Bearer synthetic-token",
      body,
      fakeDependencies({
        apply: async (_resolvedContext, command) => {
          storedCommand = command;
          return {
            result: "accepted",
            serverCursor: `opaque-${commandType}`,
          };
        },
      }),
    );
    assert.equal(response.status, 200);
    assert.equal(storedCommand?.type, commandType);
    assert.deepEqual(
      storedCommand?.payload.locationSource,
      {
        kind: "captured_coordinates",
        latitude: 41.7897,
        longitude: -87.5997,
        accuracyMeters: 8.5,
        resolverContractVersion: "canonical-region-resolution:v1",
        regionTreeContentFingerprint:
          "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
      },
    );
  }
});

test("same-field conflict returns only the authorized comparison contract", async () => {
  const conflict = {
    conflictId: "55555555-5555-4555-8555-555555555555",
    contactId: "contact-1",
    baseRevision: 1,
    currentRevision: 2,
    conflictingFields: ["reachCount"],
    questionnaireVersionId: context.current.questionnaireVersion.id,
    currentRevisionKind: "corrected" as const,
    currentRevisedAtUtc: "2030-01-08T19:00:00.000Z",
    currentReason: "另一台设备修正人数",
    currentSnapshot: {
      occurredAtUtc: "2030-01-08T18:00:00.000Z",
      occurredTimeZone: "America/Chicago",
      channel: "video_call" as const,
      channelDetail: null,
      location: { kind: "not_applicable" as const },
      reachCount: 4,
      interestLevel: 3,
      answers: [],
    },
    proposedSnapshot: {
      occurredAtUtc: "2030-01-08T18:00:00.000Z",
      occurredTimeZone: "America/Chicago",
      channel: "video_call" as const,
      channelDetail: null,
      location: { kind: "not_applicable" as const },
      reachCount: 3,
      interestLevel: 3,
      answers: [],
    },
  };
  const response = await handleSyncCommand(
    "Bearer synthetic-token",
    validRevisionCommandBody(),
    fakeDependencies({
      apply: async () => ({
        result: "conflict",
        failureCode: "contact_revision_conflict",
        conflict,
      }),
    }),
  );

  assert.equal(response.status, 409);
  assert.deepEqual(response.body, {
    result: "conflict",
    error: { code: "contact_revision_conflict" },
    conflict: {
      conflict_id: conflict.conflictId,
      contact_id: "contact-1",
      base_revision: 1,
      current_revision: 2,
      conflicting_fields: ["reachCount"],
      questionnaire_version_id: context.current.questionnaireVersion.id,
      current_revision_kind: "corrected",
      current_revised_at_utc: "2030-01-08T19:00:00.000Z",
      current_reason: "另一台设备修正人数",
      current_snapshot: conflict.currentSnapshot,
      proposed_snapshot: conflict.proposedSnapshot,
    },
  });
  assert.equal(JSON.stringify(response.body).includes("app_user_id"), false);
});

test("conflict resolution is a new typed revision command", async () => {
  let storedCommand: SyncCommand | undefined;
  const response = await handleSyncCommand(
    "Bearer synthetic-token",
    validResolutionCommandBody(),
    fakeDependencies({
      apply: async (_resolvedContext, command) => {
        storedCommand = command;
        return { result: "accepted", serverCursor: "opaque-resolution-3" };
      },
    }),
  );

  assert.equal(response.status, 200);
  assert.equal(storedCommand?.type, "contact.resolve.v1");
  assert.equal(storedCommand?.baseRevision, 2);
  if (storedCommand?.type === "contact.resolve.v1") {
    assert.equal(
      storedCommand.payload.conflictId,
      "55555555-5555-4555-8555-555555555555",
    );
    assert.equal(storedCommand.payload.reachCount, 3);
  }
});

test("contact void accepts only a positive base revision", async () => {
  let storedCommand: SyncCommand | undefined;
  const response = await handleSyncCommand(
    "Bearer synthetic-token",
    validVoidCommandBody(),
    fakeDependencies({
      apply: async (_resolvedContext, command) => {
        storedCommand = command;
        return { result: "accepted", serverCursor: "opaque-void-2" };
      },
    }),
  );

  assert.equal(response.status, 200);
  assert.equal(storedCommand?.type, "contact.void.v1");
  if (storedCommand?.type === "contact.void.v1") {
    assert.equal(storedCommand.payload.reason, "重复录入");
  }

  const invalidBase = validVoidCommandBody();
  invalidBase.base_revision = 0;
  const rejected = await handleSyncCommand(
    "Bearer synthetic-token",
    invalidBase,
    fakeDependencies(),
  );
  assert.deepEqual(rejected.body, {
    result: "rejected",
    error: { code: "invalid_base_revision" },
  });
});

test("contact void rejects a client-supplied location or location source", async () => {
  const body = validVoidCommandBody();
  const payload = body.typed_payload as Record<string, unknown>;
  payload.location_source = {
    kind: "captured_coordinates",
    latitude: 41.7897,
    longitude: -87.5997,
    accuracy_meters: null,
    resolver_contract_version: "canonical-region-resolution:v1",
    region_tree_content_fingerprint:
      "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
  };

  const response = await handleSyncCommand(
    "Bearer synthetic-token",
    body,
    fakeDependencies(),
  );

  assert.deepEqual(response.body, {
    result: "rejected",
    error: { code: "contact_void_location_forbidden" },
  });
  assert.equal(JSON.stringify(response.body).includes("41.7897"), false);
  assert.equal(JSON.stringify(response.body).includes("-87.5997"), false);
});

test("legacy v1 fixture stays accepted and unsupported protocol is stable", async () => {
  const unsupported: Record<string, unknown> = {
    ...structuredClone(syncContractV1Fixture),
  };
  unsupported.command_id = "future-command-1";
  unsupported.protocol_version = 2;

  const accepted = await handleSyncCommand(
    "Bearer synthetic-token",
    syncContractV1Fixture,
    fakeDependencies({
      apply: async (_resolvedContext, command) => ({
        result: "accepted",
        serverCursor: `cursor-${command.commandId}`,
      }),
    }),
  );
  const rejected = await handleSyncCommand(
    "Bearer synthetic-token",
    unsupported,
    fakeDependencies(),
  );

  assert.deepEqual(accepted.body, {
    result: "accepted",
    server_cursor: "cursor-legacy-command-1",
  });
  assert.deepEqual(rejected.body, {
    result: "rejected",
    error: { code: "unsupported_protocol" },
  });
});

test("batch returns accepted and retryable results independently", async () => {
  const second = {
    ...structuredClone(syncContractV1Fixture),
    command_id: "legacy-command-2",
    aggregate_id: "legacy-contact-2",
    typed_payload: {
      ...structuredClone(syncContractV1Fixture.typed_payload as object),
      contact_id: "legacy-contact-2",
    },
  };
  const response = await handleSyncCommandBatch(
    "Bearer synthetic-token",
    { commands: [syncContractV1Fixture, second] },
    fakeDependencies({
      apply: async (_resolvedContext, command) => {
        if (command.commandId === "legacy-command-2") {
          throw new Error("synthetic store outage");
        }
        return { result: "accepted", serverCursor: "cursor-legacy-1" };
      },
    }),
  );

  assert.deepEqual(response.body, {
    results: [
      {
        command_id: "legacy-command-1",
        result: "accepted",
        server_cursor: "cursor-legacy-1",
      },
      {
        command_id: "legacy-command-2",
        result: "retryable",
        error: { code: "sync_unavailable" },
      },
    ],
  });
});

function validCommandBody(): Record<string, unknown> {
  return {
    protocol_version: 1,
    command_id: "command-1",
    device_id: "device-1",
    aggregate_id: "contact-1",
    base_revision: 0,
    type: "contact.submit.v1",
    typed_payload: {
      contact_id: "contact-1",
      workspace_id: context.current.workspace.id,
      project_id: context.current.project.id,
      questionnaire_version_id: context.current.questionnaireVersion.id,
      occurred_at_utc: "2030-01-08T18:00:00.000Z",
      occurred_time_zone: "America/Chicago",
      channel: "video_call",
      channel_detail: null,
      location: {
        kind: "not_applicable",
        place_name: null,
        smallest_region_id: null,
        latitude: null,
        longitude: null,
        accuracy_meters: null,
      },
      reach_count: 2,
      interest_level: 3,
      answers: [],
    },
  };
}

function validDraftCommandBody(): Record<string, unknown> {
  return {
    protocol_version: 1,
    command_id: "draft-1:upsert:1",
    device_id: "device-1",
    aggregate_id: "draft-1",
    base_revision: 0,
    type: "draft.upsert.v1",
    typed_payload: {
      draft_id: "draft-1",
      workspace_id: context.current.workspace.id,
      project_id: context.current.project.id,
      questionnaire_version_id: context.current.questionnaireVersion.id,
      upgraded_from_draft_id: "source-draft-1",
      created_at_utc: "2030-01-08T18:00:00.000Z",
      updated_at_utc: "2030-01-08T18:30:00.000Z",
      occurred_at_utc: null,
      occurred_time_zone: null,
      channel: "video_call",
      channel_detail: null,
      location: null,
      reach_count: null,
      interest_level: null,
      answers: [],
    },
  };
}

function validAttemptCommandBody(): Record<string, unknown> {
  return {
    protocol_version: 1,
    command_id: "attempt-command-1",
    device_id: "device-1",
    aggregate_id: "attempt-1",
    base_revision: 0,
    type: "contact.attempt.submit.v1",
    typed_payload: {
      attempt_id: "attempt-1",
      workspace_id: context.current.workspace.id,
      project_id: context.current.project.id,
      occurred_at_utc: "2030-01-08T18:00:00.000Z",
      occurred_time_zone: "America/Chicago",
      channel: "voice_call",
      channel_detail: null,
    },
  };
}

function validRevisionCommandBody(): Record<string, unknown> {
  const body = validCommandBody();
  body.command_id = "revision-command-2";
  body.base_revision = 1;
  body.type = "contact.revise.v1";
  const payload = body.typed_payload as Record<string, unknown>;
  delete payload.questionnaire_version_id;
  payload.reason = "修正发生日期";
  payload.reach_count = 3;
  return body;
}

function validVoidCommandBody(): Record<string, unknown> {
  return {
    protocol_version: 1,
    command_id: "void-command-2",
    device_id: "device-1",
    aggregate_id: "contact-1",
    base_revision: 1,
    type: "contact.void.v1",
    typed_payload: {
      contact_id: "contact-1",
      workspace_id: context.current.workspace.id,
      project_id: context.current.project.id,
      reason: "重复录入",
    },
  };
}

function validResolutionCommandBody(): Record<string, unknown> {
  const body = validRevisionCommandBody();
  body.command_id = "resolution-command-3";
  body.base_revision = 2;
  body.type = "contact.resolve.v1";
  const payload = body.typed_payload as Record<string, unknown>;
  payload.conflict_id = "55555555-5555-4555-8555-555555555555";
  payload.reason = "解决跨设备冲突";
  return body;
}

function fakeDependencies(options?: {
  readonly context?: SessionContext;
  readonly apply?: (
    context: SessionContext,
    command: SyncCommand,
  ) => Promise<SyncCommandResult>;
}): SyncCommandHttpDependencies {
  return {
    identityVerifier: { verify: async () => identity },
    contextStore: {
      loadOrCreate: async () => options?.context ?? context,
    },
    commandStore: {
      apply:
        options?.apply ??
        (async () => ({ result: "accepted", serverCursor: "opaque-1" })),
      pull: async () => ({ changes: [], nextCursor: null }),
    },
  };
}
