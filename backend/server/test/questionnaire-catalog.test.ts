import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  PostgresQuestionnaireStore,
  readPublishedQuestionnaire,
} from "../src/questionnaire-catalog.js";
import type { SessionContext } from "../src/session-context.js";

const fixture = JSON.parse(
  readFileSync(
    fileURLToPath(
      new URL(
        "../../../../fixtures/questionnaire/questionnaire-contract-v1.json",
        import.meta.url,
      ),
    ),
    "utf8",
  ),
) as { readonly questionnaire: unknown };

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

test("authorized current project reads one immutable published definition", async () => {
  const result = await readPublishedQuestionnaire(
    "Bearer synthetic-token",
    context.current.questionnaireVersion.id,
    {
      identityVerifier: { verify: async () => ({ issuer: "i", subject: "s" }) },
      contextStore: { loadOrCreate: async () => context },
      questionnaireStore: new PostgresQuestionnaireStore(async () => ({
        rows: [{ questionnaire_definition: fixture.questionnaire }],
      })),
    },
  );

  assert.equal(result.status, 200);
  assert.deepEqual(result.body, { questionnaire: fixture.questionnaire });
});

test("definition from another project fails closed", async () => {
  const otherProjectDefinition = {
    ...(fixture.questionnaire as Record<string, unknown>),
    project_id: "99999999-9999-4999-8999-999999999999",
  };
  const result = await readPublishedQuestionnaire(
    "Bearer synthetic-token",
    context.current.questionnaireVersion.id,
    {
      identityVerifier: { verify: async () => ({ issuer: "i", subject: "s" }) },
      contextStore: { loadOrCreate: async () => context },
      questionnaireStore: new PostgresQuestionnaireStore(async () => ({
        rows: [{ questionnaire_definition: otherProjectDefinition }],
      })),
    },
  );

  assert.equal(result.status, 404);
  assert.deepEqual(result.body, {
    error: { code: "questionnaire_not_found" },
  });
});

test("PostgreSQL adapter sends trusted user and current scope separately", async () => {
  const calls: Array<{ text: string; values: readonly unknown[] }> = [];
  const store = new PostgresQuestionnaireStore(async (text, values) => {
    calls.push({ text, values });
    return { rows: [{ questionnaire_definition: fixture.questionnaire }] };
  });

  await store.readPublishedVersion(
    context,
    context.current.questionnaireVersion.id,
  );

  assert.deepEqual(calls[0]?.values, [
    context.appUserId,
    context.current.workspace.id,
    context.current.project.id,
    context.current.questionnaireVersion.id,
  ]);
  assert.match(calls[0]?.text ?? "", /read_published_questionnaire/);
});
