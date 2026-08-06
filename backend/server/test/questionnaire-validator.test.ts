import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  parseQuestionnaireVersion,
  validateQuestionnaireAnswers,
} from "../src/questionnaire-validator.js";

interface FixtureCase {
  readonly name: string;
  readonly answers: readonly unknown[];
  readonly valid: boolean;
  readonly errors: readonly string[];
}

interface QuestionnaireFixture {
  readonly questionnaire: unknown;
  readonly cases: readonly FixtureCase[];
}

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
) as QuestionnaireFixture;

test("Backend validator agrees with every shared contract case", () => {
  const questionnaire = parseQuestionnaireVersion(fixture.questionnaire);

  for (const fixtureCase of fixture.cases) {
    const result = validateQuestionnaireAnswers(
      questionnaire,
      fixtureCase.answers,
    );
    assert.equal(result.valid, fixtureCase.valid, fixtureCase.name);
    assert.deepEqual(result.errors, fixtureCase.errors, fixtureCase.name);
  }
});
