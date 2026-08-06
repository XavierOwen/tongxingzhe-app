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
