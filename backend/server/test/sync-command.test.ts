import assert from "node:assert/strict";
import test from "node:test";

import {
  handleSyncCommand,
  type SyncCommandHttpDependencies,
} from "../src/sync-command.js";
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
  assert.equal(storedCommand?.payload.reachCount, 2);
  assert.equal("appUserId" in (storedCommand ?? {}), false);
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
