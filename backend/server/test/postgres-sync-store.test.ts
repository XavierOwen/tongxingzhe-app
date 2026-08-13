import assert from "node:assert/strict";
import test from "node:test";

import type { SessionContext } from "../src/session-context.js";
import {
  InvalidSyncCursorError,
  PostgresSyncCommandStore,
  type SyncCommand,
} from "../src/sync-store.js";

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

const command: SyncCommand = {
  protocolVersion: 1,
  commandId: "command-1",
  deviceId: "device-1",
  aggregateId: "contact-1",
  baseRevision: 0,
  type: "contact.submit.v1",
  payload: {
    contactId: "contact-1",
    workspaceId: context.current.workspace.id,
    projectId: context.current.project.id,
    questionnaireVersionId: context.current.questionnaireVersion.id,
    occurredAtUtc: "2030-01-08T18:00:00.000Z",
    occurredTimeZone: "America/Chicago",
    channel: "video_call",
    channelDetail: null,
    location: { kind: "not_applicable" },
    reachCount: 2,
    interestLevel: 3,
    answers: [],
  },
};

test("Postgres store sends trusted app user separately from client payload", async () => {
  var values: readonly unknown[] | undefined;
  const store = new PostgresSyncCommandStore(async (_text, queryValues) => {
    values = queryValues;
    return {
      rows: [
        {
          result_code: "accepted",
          server_cursor: "opaque-1",
          failure_code: null,
        },
      ],
    };
  });

  const result = await store.apply(context, command);

  assert.deepEqual(result, { result: "accepted", serverCursor: "opaque-1" });
  assert.equal(values?.[0], context.appUserId);
  assert.equal(values?.[1], command.commandId);
  assert.equal(values?.[7], JSON.stringify(command.payload));
  assert.equal(JSON.stringify(command.payload).includes("appUserId"), false);
});

test("Postgres store parses stable conflict without exposing SQL error", async () => {
  const store = new PostgresSyncCommandStore(async () => ({
    rows: [
      {
        result_code: "conflict",
        server_cursor: null,
        failure_code: "aggregate_exists",
      },
    ],
  }));

  assert.deepEqual(await store.apply(context, command), {
    result: "conflict",
    failureCode: "aggregate_exists",
  });
});

test("Postgres store loads the authorized conflict after a revision collision", async () => {
  const queries: string[] = [];
  const reviseCommand: SyncCommand = {
    protocolVersion: 1,
    commandId: "revision-conflict-command",
    deviceId: "device-2",
    aggregateId: "contact-1",
    baseRevision: 1,
    type: "contact.revise.v1",
    payload: {
      contactId: "contact-1",
      workspaceId: context.current.workspace.id,
      projectId: context.current.project.id,
      reason: "修正人数",
      occurredAtUtc: "2030-01-08T18:00:00.000Z",
      occurredTimeZone: "America/Chicago",
      channel: "video_call",
      channelDetail: null,
      location: { kind: "not_applicable" },
      reachCount: 3,
      interestLevel: 3,
      answers: [],
    },
  };
  const store = new PostgresSyncCommandStore(async (queryText) => {
    queries.push(queryText);
    if (queryText.includes("read_contact_revision_conflict")) {
      return {
        rows: [{
          conflict_payload: {
            conflictId: "55555555-5555-4555-8555-555555555555",
            contactId: "contact-1",
            baseRevision: 1,
            currentRevision: 2,
            conflictingFields: ["reachCount"],
            questionnaireVersionId: context.current.questionnaireVersion.id,
            currentRevisionKind: "corrected",
            currentRevisedAtUtc: "2030-01-08T19:00:00.000Z",
            currentReason: "另一台设备修正人数",
            currentSnapshot: {
              occurredAtUtc: "2030-01-08T18:00:00.000Z",
              occurredTimeZone: "America/Chicago",
              channel: "video_call",
              channelDetail: null,
              location: {
                kind: "resolved",
                placeName: "University of Chicago",
                smallestRegionId: "uchicago",
                regionTreeVersion: "synthetic-v1",
              },
              locationSource: {
                kind: "captured_coordinates",
                latitude: 41.7897,
                longitude: -87.5997,
                accuracyMeters: 8.5,
                resolverContractVersion: "canonical-region-resolution:v1",
                regionTreeContentFingerprint:
                  "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
              },
              reachCount: 4,
              interestLevel: 3,
              answers: [],
            },
            proposedSnapshot: {
              occurredAtUtc: "2030-01-08T18:00:00.000Z",
              occurredTimeZone: "America/Chicago",
              channel: "video_call",
              channelDetail: null,
              location: {
                kind: "resolved",
                placeName: "University of Chicago",
                smallestRegionId: "uchicago",
                regionTreeVersion: "synthetic-v1",
              },
              locationSource: {
                kind: "captured_coordinates",
                latitude: 41.7901,
                longitude: -87.5991,
                accuracyMeters: 9.1,
                resolverContractVersion: "canonical-region-resolution:v1",
                regionTreeContentFingerprint:
                  "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
              },
              reachCount: 3,
              interestLevel: 3,
              answers: [],
            },
          },
        }],
      };
    }
    return {
      rows: [{
        result_code: "conflict",
        server_cursor: null,
        failure_code: "contact_revision_conflict",
      }],
    };
  });

  const result = await store.apply(context, reviseCommand);

  assert.equal(result.result, "conflict");
  if (result.result === "conflict") {
    assert.equal(result.conflict?.currentSnapshot.reachCount, 4);
    assert.deepEqual(result.conflict?.conflictingFields, ["reachCount"]);
    assert.equal(
      result.conflict?.currentSnapshot.locationSource?.latitude,
      41.7897,
    );
    assert.equal(
      result.conflict?.proposedSnapshot.locationSource?.longitude,
      -87.5991,
    );
  }
  assert.equal(queries.length, 2);
  assert.match(queries[1]!, /read_contact_revision_conflict/);
});

test("Postgres store rejects malformed conflict source without exposing coordinates", async () => {
  const store = new PostgresSyncCommandStore(async (queryText) => {
    if (queryText.includes("read_contact_revision_conflict")) {
      return {
        rows: [{
          conflict_payload: {
            conflictId: "55555555-5555-4555-8555-555555555555",
            contactId: "contact-1",
            baseRevision: 1,
            currentRevision: 2,
            conflictingFields: ["location"],
            questionnaireVersionId: context.current.questionnaireVersion.id,
            currentRevisionKind: "corrected",
            currentRevisedAtUtc: "2030-01-08T19:00:00.000Z",
            currentReason: "另一台设备修正地点",
            currentSnapshot: {
              occurredAtUtc: "2030-01-08T18:00:00.000Z",
              occurredTimeZone: "America/Chicago",
              channel: "video_call",
              channelDetail: null,
              location: {
                kind: "resolved",
                placeName: "University of Chicago",
                smallestRegionId: "uchicago",
                regionTreeVersion: "synthetic-v1",
              },
              locationSource: {
                kind: "captured_coordinates",
                latitude: 41.7897,
                longitude: -87.5997,
                accuracyMeters: 8.5,
                resolverContractVersion: "canonical-region-resolution:v1",
                regionTreeContentFingerprint:
                  "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
                extra: "reject",
              },
              reachCount: 4,
              interestLevel: 3,
              answers: [],
            },
            proposedSnapshot: {
              occurredAtUtc: "2030-01-08T18:00:00.000Z",
              occurredTimeZone: "America/Chicago",
              channel: "video_call",
              channelDetail: null,
              location: { kind: "not_applicable" },
              reachCount: 3,
              interestLevel: 3,
              answers: [],
            },
          },
        }],
      };
    }
    return {
      rows: [{
        result_code: "conflict",
        server_cursor: null,
        failure_code: "contact_revision_conflict",
      }],
    };
  });

  await assert.rejects(
    store.apply(context, {
      ...command,
      commandId: "malformed-location-conflict",
      baseRevision: 1,
      type: "contact.revise.v1",
      payload: {
        contactId: "contact-1",
        workspaceId: context.current.workspace.id,
        projectId: context.current.project.id,
        reason: "修正地点",
        occurredAtUtc: "2030-01-08T18:00:00.000Z",
        occurredTimeZone: "America/Chicago",
        channel: "video_call",
        channelDetail: null,
        location: { kind: "not_applicable" },
        reachCount: 3,
        interestLevel: 3,
        answers: [],
      },
    }),
    (error: unknown) => {
      assert.equal(error instanceof Error, true);
      const message = error instanceof Error ? error.message : "";
      assert.equal(message.includes("41.7897"), false);
      assert.equal(message.includes("-87.5997"), false);
      return message.includes("location source shape is invalid");
    },
  );
});

test("Postgres store rejects pending conflict locations with resolved fields", async () => {
  const store = new PostgresSyncCommandStore(async (queryText) => {
    if (queryText.includes("read_contact_revision_conflict")) {
      return {
        rows: [{
          conflict_payload: {
            conflictId: "55555555-5555-4555-8555-555555555555",
            contactId: "contact-1",
            baseRevision: 1,
            currentRevision: 2,
            conflictingFields: ["location"],
            questionnaireVersionId: context.current.questionnaireVersion.id,
            currentRevisionKind: "corrected",
            currentRevisedAtUtc: "2030-01-08T19:00:00.000Z",
            currentReason: "另一台设备修正地点",
            currentSnapshot: {
              occurredAtUtc: "2030-01-08T18:00:00.000Z",
              occurredTimeZone: "America/Chicago",
              channel: "video_call",
              channelDetail: null,
              location: {
                kind: "pending_resolution",
                latitude: 41.7897,
                longitude: -87.5997,
                accuracyMeters: 8.5,
                placeName: "must-not-be-ignored",
              },
              reachCount: 4,
              interestLevel: 3,
              answers: [],
            },
            proposedSnapshot: {
              occurredAtUtc: "2030-01-08T18:00:00.000Z",
              occurredTimeZone: "America/Chicago",
              channel: "video_call",
              channelDetail: null,
              location: { kind: "not_applicable" },
              reachCount: 3,
              interestLevel: 3,
              answers: [],
            },
          },
        }],
      };
    }
    return {
      rows: [{
        result_code: "conflict",
        server_cursor: null,
        failure_code: "contact_revision_conflict",
      }],
    };
  });

  await assert.rejects(
    store.apply(context, {
      ...command,
      commandId: "malformed-pending-location-conflict",
      baseRevision: 1,
      type: "contact.revise.v1",
      payload: {
        contactId: "contact-1",
        workspaceId: context.current.workspace.id,
        projectId: context.current.project.id,
        reason: "修正地点",
        occurredAtUtc: "2030-01-08T18:00:00.000Z",
        occurredTimeZone: "America/Chicago",
        channel: "video_call",
        channelDetail: null,
        location: { kind: "not_applicable" },
        reachCount: 3,
        interestLevel: 3,
        answers: [],
      },
    }),
    /Revision conflict location shape is invalid/,
  );
});

test("Postgres store routes private draft commands to the draft function", async () => {
  let text = "";
  const store = new PostgresSyncCommandStore(async (queryText) => {
    text = queryText;
    return {
      rows: [{
        result_code: "accepted",
        server_cursor: "opaque-draft-1",
        failure_code: null,
      }],
    };
  });
  const draftCommand: SyncCommand = {
    protocolVersion: 1,
    commandId: "draft-command-1",
    deviceId: "device-1",
    aggregateId: "draft-1",
    baseRevision: 0,
    type: "draft.upsert.v1",
    payload: {
      draftId: "draft-1",
      workspaceId: context.current.workspace.id,
      projectId: context.current.project.id,
      questionnaireVersionId: context.current.questionnaireVersion.id,
      createdAtUtc: "2030-01-08T18:00:00.000Z",
      updatedAtUtc: "2030-01-08T18:30:00.000Z",
      occurredAtUtc: null,
      occurredTimeZone: null,
      channel: "video_call",
      channelDetail: null,
      location: null,
      reachCount: null,
      interestLevel: null,
      answers: [],
    },
  };

  await store.apply(context, draftCommand);

  assert.match(text, /apply_draft_upsert/);
});

test("Postgres store routes contact attempts to the attempt function", async () => {
  let text = "";
  const store = new PostgresSyncCommandStore(async (queryText) => {
    text = queryText;
    return {
      rows: [{
        result_code: "accepted",
        server_cursor: "opaque-attempt-1",
        failure_code: null,
      }],
    };
  });
  const attemptCommand: SyncCommand = {
    protocolVersion: 1,
    commandId: "attempt-command-1",
    deviceId: "device-1",
    aggregateId: "attempt-1",
    baseRevision: 0,
    type: "contact.attempt.submit.v1",
    payload: {
      attemptId: "attempt-1",
      workspaceId: context.current.workspace.id,
      projectId: context.current.project.id,
      occurredAtUtc: "2030-01-08T18:00:00.000Z",
      occurredTimeZone: "America/Chicago",
      channel: "voice_call",
      channelDetail: null,
    },
  };

  await store.apply(context, attemptCommand);

  assert.match(text, /apply_contact_attempt_submit/);
});

test("Postgres store routes contact revision commands to distinct functions", async () => {
  const queries: string[] = [];
  const store = new PostgresSyncCommandStore(async (queryText) => {
    queries.push(queryText);
    return {
      rows: [{
        result_code: "accepted",
        server_cursor: `opaque-${queries.length}`,
        failure_code: null,
      }],
    };
  });
  const reviseCommand: SyncCommand = {
    protocolVersion: 1,
    commandId: "revision-command-2",
    deviceId: "device-1",
    aggregateId: "contact-1",
    baseRevision: 1,
    type: "contact.revise.v1",
    payload: {
      contactId: "contact-1",
      workspaceId: context.current.workspace.id,
      projectId: context.current.project.id,
      reason: "修正人数",
      occurredAtUtc: "2030-01-08T18:00:00.000Z",
      occurredTimeZone: "America/Chicago",
      channel: "video_call",
      channelDetail: null,
      location: { kind: "not_applicable" },
      reachCount: 3,
      interestLevel: 3,
      answers: [],
    },
  };
  const voidCommand: SyncCommand = {
    protocolVersion: 1,
    commandId: "void-command-3",
    deviceId: "device-1",
    aggregateId: "contact-1",
    baseRevision: 2,
    type: "contact.void.v1",
    payload: {
      contactId: "contact-1",
      workspaceId: context.current.workspace.id,
      projectId: context.current.project.id,
      reason: "重复录入",
    },
  };
  const resolveCommand: SyncCommand = {
    protocolVersion: 1,
    commandId: "resolution-command-4",
    deviceId: "device-1",
    aggregateId: "contact-1",
    baseRevision: 2,
    type: "contact.resolve.v1",
    payload: {
      conflictId: "00000000-0000-4000-8000-000000000099",
      contactId: "contact-1",
      workspaceId: context.current.workspace.id,
      projectId: context.current.project.id,
      reason: "确认两台设备的结果",
      occurredAtUtc: "2030-01-08T18:00:00.000Z",
      occurredTimeZone: "America/Chicago",
      channel: "video_call",
      channelDetail: null,
      location: { kind: "not_applicable" },
      reachCount: 3,
      interestLevel: 3,
      answers: [],
    },
  };

  await store.apply(context, reviseCommand);
  await store.apply(context, voidCommand);
  await store.apply(context, resolveCommand);

  assert.match(queries[0]!, /apply_contact_revise/);
  assert.match(queries[1]!, /apply_contact_void/);
  assert.match(queries[2]!, /apply_contact_conflict_resolution/);
});

test("Postgres store passes trusted scope and opaque cursor to pull function", async () => {
  var text = "";
  var values: readonly unknown[] | undefined;
  const store = new PostgresSyncCommandStore(async (queryText, queryValues) => {
    text = queryText;
    values = queryValues;
    return {
      rows: [
        {
          server_cursor: "opaque-after",
          change_type: "contact.submitted",
          revision_number: 1,
          typed_payload: { contactId: "contact-remote-1" },
        },
      ],
    };
  });

  const result = await store.pull(context, "opaque-before", 25);

  assert.match(text, /pull_sync_changes/);
  assert.deepEqual(values, [
    context.appUserId,
    context.current.workspace.id,
    context.current.project.id,
    "opaque-before",
    25,
  ]);
  assert.deepEqual(result, {
    changes: [
      {
        changeType: "contact.submitted",
        revisionNumber: 1,
        payload: { contactId: "contact-remote-1" },
      },
    ],
    nextCursor: "opaque-after",
  });
});

test("Postgres store translates an invalid pull cursor from PostgreSQL", async () => {
  const store = new PostgresSyncCommandStore(async () => {
    throw Object.assign(new Error("cursor does not belong to scope"), {
      code: "22023",
    });
  });

  await assert.rejects(
    store.pull(context, "foreign-cursor", 100),
    InvalidSyncCursorError,
  );
});
