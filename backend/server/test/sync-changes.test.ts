import assert from "node:assert/strict";
import test from "node:test";

import { handleSyncChanges } from "../src/sync-changes.js";
import type { VerifiedIdentity } from "../src/identity.js";
import type { SessionContext } from "../src/session-context.js";
import {
  InvalidSyncCursorError,
  type SyncPullBatch,
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

test("verified pull uses trusted current context and returns an opaque cursor", async () => {
  let receivedCursor: string | null | undefined;
  let receivedLimit: number | undefined;
  const batch: SyncPullBatch = {
    changes: [
      {
        changeType: "contact.submitted",
        revisionNumber: 1,
        payload: { contactId: "contact-remote-1" },
      },
    ],
    nextCursor: "opaque-after",
  };

  const result = await handleSyncChanges(
    "Bearer synthetic-token",
    new URLSearchParams({
      workspace_id: context.current.workspace.id,
      project_id: context.current.project.id,
      cursor: "opaque-before",
      limit: "25",
    }),
    {
      identityVerifier: { verify: async () => identity },
      contextStore: { loadOrCreate: async () => context },
      commandStore: {
        apply: async () => {
          throw new Error("push must not run while pulling");
        },
        pull: async (_context, cursor, limit) => {
          receivedCursor = cursor;
          receivedLimit = limit;
          return batch;
        },
      },
    },
  );

  assert.equal(result.status, 200);
  assert.equal(receivedCursor, "opaque-before");
  assert.equal(receivedLimit, 25);
  assert.deepEqual(result.body, {
    changes: [
      {
        change_type: "contact.submitted",
        revision_number: 1,
        payload: { contactId: "contact-remote-1" },
      },
    ],
    next_cursor: "opaque-after",
  });
});

test("forged scope and invalid limit fail before the store", async () => {
  let storeCalls = 0;
  const dependencies = {
    identityVerifier: { verify: async () => identity },
    contextStore: { loadOrCreate: async () => context },
    commandStore: {
      apply: async () => ({ result: "accepted" as const, serverCursor: "unused" }),
      pull: async () => {
        storeCalls += 1;
        return { changes: [], nextCursor: null };
      },
    },
  };

  const forged = await handleSyncChanges(
    "Bearer synthetic-token",
    new URLSearchParams({
      workspace_id: context.current.workspace.id,
      project_id: "99999999-9999-4999-8999-999999999999",
    }),
    dependencies,
  );
  assert.equal(forged.status, 403);
  assert.deepEqual(forged.body, { error: { code: "project_forbidden" } });

  const invalidLimit = await handleSyncChanges(
    "Bearer synthetic-token",
    new URLSearchParams({
      workspace_id: context.current.workspace.id,
      project_id: context.current.project.id,
      limit: "1000",
    }),
    dependencies,
  );
  assert.equal(invalidLimit.status, 400);
  assert.deepEqual(invalidLimit.body, { error: { code: "invalid_limit" } });
  assert.equal(storeCalls, 0);
});

test("a cursor rejected by PostgreSQL remains a stable client error", async () => {
  const result = await handleSyncChanges(
    "Bearer synthetic-token",
    new URLSearchParams({
      workspace_id: context.current.workspace.id,
      project_id: context.current.project.id,
      cursor: "cursor-from-another-scope",
    }),
    {
      identityVerifier: { verify: async () => identity },
      contextStore: { loadOrCreate: async () => context },
      commandStore: {
        apply: async () => {
          throw new Error("push must not run while pulling");
        },
        pull: async () => {
          throw new InvalidSyncCursorError();
        },
      },
    },
  );

  assert.equal(result.status, 400);
  assert.deepEqual(result.body, { error: { code: "invalid_cursor" } });
});
