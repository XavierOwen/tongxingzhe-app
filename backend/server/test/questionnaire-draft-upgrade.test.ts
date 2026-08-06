import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import { planQuestionnaireDraftUpgrade } from "../src/questionnaire-draft-upgrade.js";
import {
  parseQuestionnaireVersion,
  serializeQuestionnaireAnswer,
} from "../src/questionnaire-validator.js";

test("Backend upgrade planner agrees with the shared audited fixture", async () => {
  const fixture = JSON.parse(
    await readFile(
      new URL(
        "../../../../fixtures/questionnaire/questionnaire-draft-upgrade-contract-v1.json",
        import.meta.url,
      ),
      "utf8",
    ),
  ) as Fixture;

  const plan = planQuestionnaireDraftUpgrade({
    source: parseQuestionnaireVersion(fixture.source),
    target: parseQuestionnaireVersion(fixture.target),
    sourceAnswers: fixture.source_answers,
    compatibilities: fixture.audited_compatibilities.map((item) => ({
      decisionId: item.decision_id,
      sourceQuestionId: item.source_question_id,
      targetQuestionId: item.target_question_id,
    })),
  });

  assert.deepEqual(
    plan.retained.map((item) => ({
      decision_id: item.decisionId,
      source_question_id: item.sourceQuestionId,
      target_question_id: item.targetQuestionId,
    })),
    fixture.expected.retained,
  );
  assert.deepEqual(
    plan.requiresConfirmationQuestionIds,
    fixture.expected.requires_confirmation_question_ids,
  );
  assert.deepEqual(
    plan.cannotCopySourceQuestionIds,
    fixture.expected.cannot_copy_source_question_ids,
  );
  assert.deepEqual(
    plan.copiedAnswers.map(serializeQuestionnaireAnswer),
    fixture.expected.copied_answers,
  );
});

interface Fixture {
  readonly source: unknown;
  readonly target: unknown;
  readonly source_answers: readonly unknown[];
  readonly audited_compatibilities: readonly {
    readonly decision_id: string;
    readonly source_question_id: string;
    readonly target_question_id: string;
  }[];
  readonly expected: {
    readonly retained: readonly unknown[];
    readonly requires_confirmation_question_ids: readonly string[];
    readonly cannot_copy_source_question_ids: readonly string[];
    readonly copied_answers: readonly unknown[];
  };
}
