import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import {
  parseQuestionnaireVersion,
  previewQuestionnaireAnswerChange,
  serializeQuestionnaireVersion,
  validateQuestionnaireAnswers,
} from "../src/questionnaire-validator.js";

const fixture = JSON.parse(readFileSync(
  new URL(
    "../../../../fixtures/questionnaire/questionnaire-visibility-contract-v1.json",
    import.meta.url,
  ),
  "utf8",
)) as Record<string, unknown>;
const questionnaire = parseQuestionnaireVersion(fixture.questionnaire);

test("published visibility definition round-trips without executable fields", () => {
  assert.deepEqual(
    serializeQuestionnaireVersion(questionnaire),
    fixture.questionnaire,
  );
});

test("Backend validator agrees with every shared visibility case", () => {
  const questions = (fixture.questionnaire as {
    questions: Record<string, unknown>[];
  }).questions;
  const coveredOperators = new Set(questions.flatMap((question) => {
    const rule = question.display_rule as {
      conditions: Record<string, unknown>[];
    } | undefined;
    return rule?.conditions.map((condition) => condition.operator) ?? [];
  }));
  assert.deepEqual([...coveredOperators].sort(), [
    "between",
    "contains",
    "equals",
    "greater_than",
    "greater_than_or_equal",
    "in",
    "is_answered",
    "is_unanswered",
    "less_than",
    "less_than_or_equal",
    "not_contains",
    "not_equals",
  ]);
  for (const rawCase of fixture.evaluation_cases as Record<string, unknown>[]) {
    const result = validateQuestionnaireAnswers(
      questionnaire,
      rawCase.answers as readonly unknown[],
    );
    assert.deepEqual(result.visibleQuestionIds, rawCase.visible_question_ids,
      rawCase.name as string);
    assert.deepEqual(
      result.ruleSkippedQuestionIds,
      rawCase.rule_skipped_question_ids,
      rawCase.name as string,
    );
    assert.equal(result.valid, rawCase.valid, rawCase.name as string);
    assert.deepEqual(result.errors, rawCase.errors, rawCase.name as string);
  }
});

test("Backend transition computes the same confirmed clear set", () => {
  const rawCase = fixture.transition_case as Record<string, unknown>;
  const transition = previewQuestionnaireAnswerChange(
    questionnaire,
    rawCase.answers as readonly unknown[],
    rawCase.next_answer,
  );
  assert.deepEqual(
    transition.answersToClear.map((answer) => answer.questionId),
    rawCase.clear_question_ids,
  );
  for (const questionId of rawCase.clear_question_ids as string[]) {
    const answer = transition.answers.find(
      (answer) => answer.questionId === questionId,
    );
    assert.deepEqual(answer, {
      questionId,
      state: "not_applicable",
      stateReason: "rule_skipped",
      type: answer?.type,
      value: null,
    });
  }
});

test("definition rejects forward references and incompatible operators", () => {
  const forwardReference = structuredClone(fixture.questionnaire) as {
    questions: Record<string, unknown>[];
  };
  forwardReference.questions[0]!.display_rule = {
    match: "all",
    conditions: [{
      source_question_id: "interest",
      operator: "equals",
      operand: "study",
    }],
  };
  assert.throws(() => parseQuestionnaireVersion(forwardReference), {
    name: "QuestionnaireContractError",
    message: "visibility_source_must_precede_question",
  });

  const invalidOperator = structuredClone(fixture.questionnaire) as {
    questions: Record<string, unknown>[];
  };
  invalidOperator.questions[6]!.display_rule = {
    match: "all",
    conditions: [{
      source_question_id: "consent",
      operator: "greater_than",
      operand: true,
    }],
  };
  assert.throws(() => parseQuestionnaireVersion(invalidOperator), {
    name: "QuestionnaireContractError",
    message: "visibility_operator_not_allowed",
  });

  const nestedRule = structuredClone(fixture.questionnaire) as {
    questions: Record<string, unknown>[];
  };
  nestedRule.questions[6]!.display_rule = {
    match: "all",
    conditions: [{
      source_question_id: "consent",
      operator: "equals",
      operand: true,
      conditions: [],
    }],
  };
  assert.throws(() => parseQuestionnaireVersion(nestedRule), {
    name: "QuestionnaireContractError",
    message: "unsupported_visibility_rule_field",
  });
});
