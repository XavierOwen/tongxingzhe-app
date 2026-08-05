import assert from "node:assert/strict";
import test from "node:test";

import { PostgresSessionContextStore } from "../src/session-context.js";

const identity = {
  issuer: "https://synthetic.supabase.co/auth/v1",
  subject: "synthetic-subject",
};

const validRow = {
  app_user_id: "11111111-1111-4111-8111-111111111111",
  workspace_id: "22222222-2222-4222-8222-222222222222",
  workspace_kind: "personal",
  workspace_name: "个人空间",
  project_id: "33333333-3333-4333-8333-333333333333",
  project_name: "我的推广项目",
  questionnaire_version_id: "44444444-4444-4444-8444-444444444444",
  questionnaire_version_number: 1,
  capabilities: ["record_contact"],
};

test("context query passes only verified issuer and subject", async () => {
  var queryValues: readonly string[] | undefined;
  const store = new PostgresSessionContextStore(async (_text, values) => {
    queryValues = values;
    return { rows: [validRow] };
  });

  const context = await store.loadOrCreate(identity);

  assert.deepEqual(queryValues, [identity.issuer, identity.subject]);
  assert.equal(context.appUserId, validRow.app_user_id);
  assert.equal(context.current.workspace.id, validRow.workspace_id);
  assert.equal(context.current.project.id, validRow.project_id);
  assert.equal(
    context.current.questionnaireVersion.id,
    validRow.questionnaire_version_id,
  );
});

test("missing context row fails closed", async () => {
  const store = new PostgresSessionContextStore(async () => ({ rows: [] }));

  await assert.rejects(
    store.loadOrCreate(identity),
    /must return exactly one row/,
  );
});

test("invalid questionnaire version fails closed", async () => {
  const store = new PostgresSessionContextStore(async () => ({
    rows: [{ ...validRow, questionnaire_version_number: 0 }],
  }));

  await assert.rejects(
    store.loadOrCreate(identity),
    /invalid questionnaire_version_number/,
  );
});
