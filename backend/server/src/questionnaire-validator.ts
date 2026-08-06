export type QuestionnaireQuestionType =
  | "boolean"
  | "single_choice"
  | "ordinal_choice"
  | "multi_choice"
  | "number"
  | "date"
  | "short_text"
  | "long_text";

export type QuestionnaireAnswerState =
  | "answered"
  | "unknown"
  | "refused"
  | "not_applicable"
  | "unanswered";

export interface QuestionnaireOption {
  readonly id: string;
  readonly position: number;
  readonly label: string;
}

export type QuestionnaireVisibilityMatch = "all" | "any";

export type QuestionnaireVisibilityOperator =
  | "equals"
  | "not_equals"
  | "in"
  | "contains"
  | "not_contains"
  | "greater_than"
  | "greater_than_or_equal"
  | "less_than"
  | "less_than_or_equal"
  | "between"
  | "is_answered"
  | "is_unanswered";

export interface QuestionnaireVisibilityCondition {
  readonly sourceQuestionId: string;
  readonly operator: QuestionnaireVisibilityOperator;
  readonly operand: unknown;
}

export interface QuestionnaireVisibilityRule {
  readonly match: QuestionnaireVisibilityMatch;
  readonly conditions: readonly QuestionnaireVisibilityCondition[];
}

export interface QuestionnaireQuestion {
  readonly id: string;
  readonly position: number;
  readonly prompt: string;
  readonly type: QuestionnaireQuestionType;
  readonly required: boolean;
  readonly allowUnknown: boolean;
  readonly allowRefused: boolean;
  readonly allowNotApplicable: boolean;
  readonly options: readonly QuestionnaireOption[];
  readonly minimumSelections: number | null;
  readonly maximumSelections: number | null;
  readonly numberKind: "integer" | "decimal" | null;
  readonly unit: string | null;
  readonly minimum: number | null;
  readonly maximum: number | null;
  readonly maximumLength: number | null;
  readonly displayRule: QuestionnaireVisibilityRule | null;
}

export interface QuestionnaireVersion {
  readonly id: string;
  readonly projectId: string;
  readonly versionNumber: number;
  readonly questions: readonly QuestionnaireQuestion[];
}

export interface QuestionnaireValidationResult {
  readonly valid: boolean;
  readonly errors: readonly string[];
  readonly visibleQuestionIds: readonly string[];
  readonly ruleSkippedQuestionIds: readonly string[];
  readonly answers: readonly ParsedAnswer[];
}

export interface ParsedAnswer {
  readonly questionId: string;
  readonly state: QuestionnaireAnswerState;
  readonly stateReason: string | null;
  readonly type: QuestionnaireQuestionType;
  readonly value: unknown;
}

export interface QuestionnaireAnswerTransition {
  readonly answers: readonly ParsedAnswer[];
  readonly answersToClear: readonly ParsedAnswer[];
}

/**
 * Parse the immutable, published questionnaire contract served to Flutter.
 * Unsupported executable or free-form definition fields have no execution path.
 */
export function parseQuestionnaireVersion(value: unknown): QuestionnaireVersion {
  const root = object(value, "invalid_questionnaire");
  if (string(root.status, "invalid_questionnaire_status") !== "published") {
    throw new QuestionnaireContractError("questionnaire_not_published");
  }
  const questions = array(root.questions, "invalid_questions")
    .map(parseQuestion)
    .sort((left, right) => left.position - right.position);
  unique(questions.map((question) => question.id), "duplicate_question_id");
  unique(
    questions.map((question) => question.position),
    "duplicate_question_position",
  );
  const questionsById = new Map(
    questions.map((question) => [question.id, question]),
  );
  for (const question of questions) {
    for (const condition of question.displayRule?.conditions ?? []) {
      const source = questionsById.get(condition.sourceQuestionId);
      if (source === undefined || source.position >= question.position) {
        throw new QuestionnaireContractError(
          "visibility_source_must_precede_question",
        );
      }
      validateVisibilityCondition(source, condition);
    }
  }
  return {
    id: string(root.questionnaire_version_id, "invalid_questionnaire_version_id"),
    projectId: string(root.project_id, "invalid_project_id"),
    versionNumber: positiveInteger(root.version_number, "invalid_version_number"),
    questions,
  };
}

export function serializeQuestionnaireVersion(
  version: QuestionnaireVersion,
): Readonly<Record<string, unknown>> {
  return {
    questionnaire_version_id: version.id,
    project_id: version.projectId,
    version_number: version.versionNumber,
    status: "published",
    questions: version.questions.map((question) => ({
      question_id: question.id,
      position: question.position,
      prompt: question.prompt,
      type: question.type,
      required: question.required,
      allow_unknown: question.allowUnknown,
      allow_refused: question.allowRefused,
      allow_not_applicable: question.allowNotApplicable,
      ...(question.options.length === 0
        ? {}
        : {
          options: question.options.map((option) => ({
            option_id: option.id,
            position: option.position,
            label: option.label,
          })),
        }),
      ...(question.minimumSelections === null
        ? {}
        : { minimum_selections: question.minimumSelections }),
      ...(question.maximumSelections === null
        ? {}
        : { maximum_selections: question.maximumSelections }),
      ...(question.numberKind === null
        ? {}
        : { number_kind: question.numberKind }),
      ...(question.unit === null ? {} : { unit: question.unit }),
      ...(question.minimum === null ? {} : { minimum: question.minimum }),
      ...(question.maximum === null ? {} : { maximum: question.maximum }),
      ...(question.maximumLength === null
        ? {}
        : { maximum_length: question.maximumLength }),
      ...(question.displayRule === null
        ? {}
        : {
          display_rule: {
            match: question.displayRule.match,
            conditions: question.displayRule.conditions.map((condition) => ({
              source_question_id: condition.sourceQuestionId,
              operator: condition.operator,
              ...(condition.operand === null
                ? {}
                : { operand: condition.operand }),
            })),
          },
        }),
    })),
  };
}

/** Independently validate answers. Callers must not trust Flutter evaluation. */
export function validateQuestionnaireAnswers(
  questionnaire: QuestionnaireVersion,
  rawAnswers: readonly unknown[],
): QuestionnaireValidationResult {
  const errors: string[] = [];
  const questions = new Map(
    questionnaire.questions.map((question) => [question.id, question]),
  );
  const answers = new Map<string, ParsedAnswer>();

  for (const rawAnswer of rawAnswers) {
    let answer: ParsedAnswer;
    try {
      answer = parseAnswer(rawAnswer);
    } catch (error) {
      const code = error instanceof QuestionnaireContractError
        ? error.code
        : "invalid_answer";
      errors.push(`${code}:?`);
      continue;
    }
    const question = questions.get(answer.questionId);
    if (question === undefined) {
      errors.push(`unknown_question:${answer.questionId}`);
      continue;
    }
    if (answers.has(answer.questionId)) {
      errors.push(`duplicate_answer:${answer.questionId}`);
      continue;
    }
    answers.set(answer.questionId, answer);
  }

  const visible = new Map<string, boolean>();
  for (const question of questionnaire.questions) {
    visible.set(
      question.id,
      questionIsVisible(question, questions, answers, visible),
    );
  }

  for (const [questionId, answer] of answers) {
    const question = questions.get(questionId)!;
    if (visible.get(questionId) !== true) {
      if (
        answer.type !== question.type ||
        answer.state !== "not_applicable" ||
        answer.stateReason !== "rule_skipped" ||
        answer.value !== null
      ) {
        errors.push(`hidden_answer_present:${question.id}`);
      }
      continue;
    }
    if (answer.stateReason !== null) {
      errors.push(`answer_state_reason_invalid:${question.id}`);
      continue;
    }
    if (answer.type !== question.type) {
      errors.push(`answer_type_mismatch:${question.id}`);
      continue;
    }
    if (answer.state !== "answered") {
      if (answer.value !== null) {
        errors.push(`answer_value_shape_invalid:${question.id}`);
        continue;
      }
      if (answer.state === "unanswered" && question.required) {
        errors.push(`required_answer_missing:${question.id}`);
      } else if (!stateAllowed(question, answer.state)) {
        errors.push(`answer_state_not_allowed:${question.id}`);
      }
      continue;
    }
    if (!validValue(question, answer.value)) {
      errors.push(`answer_value_invalid:${question.id}`);
    }
  }

  for (const question of questionnaire.questions) {
    if (
      visible.get(question.id) === true &&
      question.required &&
      !answers.has(question.id)
    ) {
      errors.push(`required_answer_missing:${question.id}`);
    }
  }
  const visibleQuestionIds = questionnaire.questions
    .filter((question) => visible.get(question.id) === true)
    .map((question) => question.id);
  const ruleSkippedQuestionIds = questionnaire.questions
    .filter((question) => visible.get(question.id) !== true)
    .map((question) => question.id);
  const normalizedAnswers = questionnaire.questions.flatMap((question) => {
    if (visible.get(question.id) !== true) {
      return [{
        questionId: question.id,
        state: "not_applicable" as const,
        stateReason: "rule_skipped",
        type: question.type,
        value: null,
      }];
    }
    const answer = answers.get(question.id);
    return answer === undefined || answer.stateReason === "rule_skipped"
      ? []
      : [answer];
  });
  return {
    valid: errors.length === 0,
    errors,
    visibleQuestionIds,
    ruleSkippedQuestionIds,
    answers: normalizedAnswers,
  };
}

export function previewQuestionnaireAnswerChange(
  questionnaire: QuestionnaireVersion,
  rawCurrentAnswers: readonly unknown[],
  rawNextAnswer: unknown,
): QuestionnaireAnswerTransition {
  const currentAnswers = rawCurrentAnswers.map(parseAnswer);
  const currentByQuestion = new Map(
    currentAnswers.map((answer) => [answer.questionId, answer]),
  );
  const nextAnswer = parseAnswer(rawNextAnswer);
  const proposed = new Map(currentByQuestion);
  proposed.set(nextAnswer.questionId, nextAnswer);
  const evaluation = validateQuestionnaireAnswers(
    questionnaire,
    [...proposed.values()].map(serializeAnswer),
  );
  const skipped = new Set(evaluation.ruleSkippedQuestionIds);
  return {
    answers: evaluation.answers,
    answersToClear: questionnaire.questions.flatMap((question) => {
      const answer = currentByQuestion.get(question.id);
      return skipped.has(question.id) &&
          answer !== undefined &&
          answer.state !== "unanswered" &&
          answer.stateReason !== "rule_skipped"
        ? [answer]
        : [];
    }),
  };
}

export class QuestionnaireContractError extends Error {
  constructor(readonly code: string) {
    super(code);
    this.name = "QuestionnaireContractError";
  }
}

function parseQuestion(value: unknown): QuestionnaireQuestion {
  const root = object(value, "invalid_question");
  const type = questionType(root.type);
  const options = root.options === undefined
    ? []
    : array(root.options, "invalid_options").map((value) => {
      const option = object(value, "invalid_option");
      return {
        id: string(option.option_id, "invalid_option_id"),
        position: positiveInteger(option.position, "invalid_option_position"),
        label: string(option.label, "invalid_option_label"),
      };
    });
  unique(options.map((option) => option.id), "duplicate_option_id");
  unique(options.map((option) => option.position), "duplicate_option_position");
  const choiceType = type === "single_choice" ||
    type === "ordinal_choice" ||
    type === "multi_choice";
  if (choiceType !== (options.length > 0)) {
    throw new QuestionnaireContractError("invalid_question_options");
  }
  const minimumSelections = type === "multi_choice"
    ? positiveInteger(root.minimum_selections, "invalid_minimum_selections")
    : null;
  const maximumSelections = type === "multi_choice"
    ? positiveInteger(root.maximum_selections, "invalid_maximum_selections")
    : null;
  if (
    minimumSelections !== null &&
    maximumSelections !== null &&
    (maximumSelections < minimumSelections || maximumSelections > options.length)
  ) {
    throw new QuestionnaireContractError("invalid_selection_bounds");
  }
  const numberKind = type === "number" ? parseNumberKind(root.number_kind) : null;
  const minimum = type === "number" ? nullableFiniteNumber(root.minimum) : null;
  const maximum = type === "number" ? nullableFiniteNumber(root.maximum) : null;
  if (minimum !== null && maximum !== null && minimum > maximum) {
    throw new QuestionnaireContractError("invalid_number_range");
  }
  const textType = type === "short_text" || type === "long_text";
  return {
    id: string(root.question_id, "invalid_question_id"),
    position: positiveInteger(root.position, "invalid_question_position"),
    prompt: string(root.prompt, "invalid_question_prompt"),
    type,
    required: boolean(root.required, "invalid_required"),
    allowUnknown: boolean(root.allow_unknown, "invalid_allow_unknown"),
    allowRefused: boolean(root.allow_refused, "invalid_allow_refused"),
    allowNotApplicable: boolean(
      root.allow_not_applicable,
      "invalid_allow_not_applicable",
    ),
    options,
    minimumSelections,
    maximumSelections,
    numberKind,
    unit: type === "number" ? nullableString(root.unit) : null,
    minimum,
    maximum,
    maximumLength: textType
      ? positiveInteger(root.maximum_length, "invalid_maximum_length")
      : null,
    displayRule: root.display_rule === undefined
      ? null
      : parseVisibilityRule(root.display_rule),
  };
}

function parseVisibilityRule(value: unknown): QuestionnaireVisibilityRule {
  const root = object(value, "invalid_visibility_rule");
  requireOnlyKeys(root, new Set(["match", "conditions"]));
  const match = root.match === "all" || root.match === "any"
    ? root.match
    : (() => {
      throw new QuestionnaireContractError("invalid_visibility_match");
    })();
  const conditions = array(
    root.conditions,
    "invalid_visibility_conditions",
  ).map((value) => {
    const condition = object(value, "invalid_visibility_condition");
    requireOnlyKeys(
      condition,
      new Set(["source_question_id", "operator", "operand"]),
    );
    return {
      sourceQuestionId: string(
        condition.source_question_id,
        "invalid_visibility_source",
      ),
      operator: visibilityOperator(condition.operator),
      operand: condition.operand ?? null,
    };
  });
  if (conditions.length === 0) {
    throw new QuestionnaireContractError("visibility_conditions_required");
  }
  return { match, conditions };
}

function validateVisibilityCondition(
  source: QuestionnaireQuestion,
  condition: QuestionnaireVisibilityCondition,
): void {
  const { operator, operand } = condition;
  let valid = false;
  switch (source.type) {
    case "boolean":
      valid = ((operator === "equals" || operator === "not_equals") &&
          typeof operand === "boolean") ||
        (operator === "in" && Array.isArray(operand) && operand.length > 0 &&
          operand.every((value) => typeof value === "boolean"));
      break;
    case "single_choice":
    case "ordinal_choice":
      valid = ((operator === "equals" || operator === "not_equals") &&
          typeof operand === "string" && optionExists(source, operand)) ||
        (operator === "in" && Array.isArray(operand) && operand.length > 0 &&
          operand.every((value) =>
            typeof value === "string" && optionExists(source, value)
          ));
      break;
    case "multi_choice":
      valid = (operator === "contains" || operator === "not_contains") &&
        typeof operand === "string" && optionExists(source, operand);
      break;
    case "number":
      valid = validComparableCondition(
        operator,
        operand,
        (value) => typeof value === "number" && Number.isFinite(value),
      );
      break;
    case "date":
      valid = validComparableCondition(
        operator,
        operand,
        (value) => typeof value === "string" && isCalendarDate(value),
      );
      break;
    case "short_text":
    case "long_text":
      valid = (operator === "is_answered" || operator === "is_unanswered") &&
        operand === null;
      break;
  }
  if (!valid) {
    throw new QuestionnaireContractError("visibility_operator_not_allowed");
  }
}

function optionExists(question: QuestionnaireQuestion, id: string): boolean {
  return question.options.some((option) => option.id === id);
}

function validComparableCondition(
  operator: QuestionnaireVisibilityOperator,
  operand: unknown,
  validValue: (value: unknown) => boolean,
): boolean {
  if (
    operator === "equals" ||
    operator === "not_equals" ||
    operator === "greater_than" ||
    operator === "greater_than_or_equal" ||
    operator === "less_than" ||
    operator === "less_than_or_equal"
  ) {
    return validValue(operand);
  }
  return operator === "between" &&
    Array.isArray(operand) &&
    operand.length === 2 &&
    operand.every(validValue) &&
    compareRuleValues(operand[0], operand[1]) <= 0;
}

function parseAnswer(value: unknown): ParsedAnswer {
  const root = object(value, "invalid_answer");
  return {
    questionId: string(root.question_id, "invalid_question_id"),
    state: answerState(root.state),
    stateReason: nullableString(root.state_reason),
    type: questionType(root.type),
    value: root.value,
  };
}

function serializeAnswer(answer: ParsedAnswer): Readonly<Record<string, unknown>> {
  return {
    question_id: answer.questionId,
    state: answer.state,
    ...(answer.stateReason === null
      ? {}
      : { state_reason: answer.stateReason }),
    type: answer.type,
    value: answer.value,
  };
}

function questionIsVisible(
  question: QuestionnaireQuestion,
  questions: ReadonlyMap<string, QuestionnaireQuestion>,
  answers: ReadonlyMap<string, ParsedAnswer>,
  visible: ReadonlyMap<string, boolean>,
): boolean {
  if (question.displayRule === null) return true;
  const results = question.displayRule.conditions.map((condition) => {
    const source = questions.get(condition.sourceQuestionId)!;
    if (visible.get(source.id) !== true) return false;
    return conditionMatches(source, answers.get(source.id), condition);
  });
  return question.displayRule.match === "all"
    ? results.every(Boolean)
    : results.some(Boolean);
}

function conditionMatches(
  source: QuestionnaireQuestion,
  answer: ParsedAnswer | undefined,
  condition: QuestionnaireVisibilityCondition,
): boolean {
  const answered = answer !== undefined &&
    answer.state === "answered" &&
    answer.stateReason === null &&
    answer.type === source.type &&
    validValue(source, answer.value);
  if (condition.operator === "is_answered") return answered;
  if (condition.operator === "is_unanswered") return !answered;
  if (!answered) return false;
  switch (condition.operator) {
    case "equals":
      return answer.value === condition.operand;
    case "not_equals":
      return answer.value !== condition.operand;
    case "in":
      return (condition.operand as readonly unknown[]).includes(answer.value);
    case "contains":
      return (answer.value as readonly string[]).includes(
        condition.operand as string,
      );
    case "not_contains":
      return !(answer.value as readonly string[]).includes(
        condition.operand as string,
      );
    case "greater_than":
      return compareRuleValues(answer.value, condition.operand) > 0;
    case "greater_than_or_equal":
      return compareRuleValues(answer.value, condition.operand) >= 0;
    case "less_than":
      return compareRuleValues(answer.value, condition.operand) < 0;
    case "less_than_or_equal":
      return compareRuleValues(answer.value, condition.operand) <= 0;
    case "between": {
      const bounds = condition.operand as readonly unknown[];
      return compareRuleValues(answer.value, bounds[0]) >= 0 &&
        compareRuleValues(answer.value, bounds[1]) <= 0;
    }
  }
}

function compareRuleValues(left: unknown, right: unknown): number {
  if (typeof left === "number" && typeof right === "number") {
    return left - right;
  }
  return (left as string).localeCompare(right as string);
}

function stateAllowed(
  question: QuestionnaireQuestion,
  state: QuestionnaireAnswerState,
): boolean {
  switch (state) {
    case "answered":
      return true;
    case "unknown":
      return question.allowUnknown;
    case "refused":
      return question.allowRefused;
    case "not_applicable":
      return question.allowNotApplicable;
    case "unanswered":
      return !question.required;
  }
}

function validValue(question: QuestionnaireQuestion, value: unknown): boolean {
  switch (question.type) {
    case "boolean":
      return typeof value === "boolean";
    case "single_choice":
    case "ordinal_choice":
      return typeof value === "string" &&
        question.options.some((option) => option.id === value);
    case "multi_choice":
      return Array.isArray(value) &&
        value.every((item): item is string => typeof item === "string") &&
        value.length >= (question.minimumSelections ?? 0) &&
        value.length <= (question.maximumSelections ?? 0) &&
        new Set(value).size === value.length &&
        value.every((id) => question.options.some((option) => option.id === id));
    case "number":
      return typeof value === "number" &&
        Number.isFinite(value) &&
        (question.numberKind !== "integer" || Number.isInteger(value)) &&
        (question.minimum === null || value >= question.minimum) &&
        (question.maximum === null || value <= question.maximum);
    case "date":
      return typeof value === "string" && isCalendarDate(value);
    case "short_text":
    case "long_text":
      return typeof value === "string" &&
        value.trim().length > 0 &&
        [...value].length <= (question.maximumLength ?? 0);
  }
}

function isCalendarDate(value: string): boolean {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (match === null) return false;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const parsed = new Date(Date.UTC(year, month - 1, day));
  return parsed.getUTCFullYear() === year &&
    parsed.getUTCMonth() === month - 1 &&
    parsed.getUTCDate() === day;
}

function questionType(value: unknown): QuestionnaireQuestionType {
  if (
    value === "boolean" ||
    value === "single_choice" ||
    value === "ordinal_choice" ||
    value === "multi_choice" ||
    value === "number" ||
    value === "date" ||
    value === "short_text" ||
    value === "long_text"
  ) {
    return value;
  }
  throw new QuestionnaireContractError("unsupported_answer_type");
}

function answerState(value: unknown): QuestionnaireAnswerState {
  if (
    value === "answered" ||
    value === "unknown" ||
    value === "refused" ||
    value === "not_applicable" ||
    value === "unanswered"
  ) {
    return value;
  }
  throw new QuestionnaireContractError("invalid_answer_state");
}

function visibilityOperator(value: unknown): QuestionnaireVisibilityOperator {
  if (
    value === "equals" ||
    value === "not_equals" ||
    value === "in" ||
    value === "contains" ||
    value === "not_contains" ||
    value === "greater_than" ||
    value === "greater_than_or_equal" ||
    value === "less_than" ||
    value === "less_than_or_equal" ||
    value === "between" ||
    value === "is_answered" ||
    value === "is_unanswered"
  ) {
    return value;
  }
  throw new QuestionnaireContractError("unsupported_visibility_operator");
}

function parseNumberKind(value: unknown): "integer" | "decimal" {
  if (value === "integer" || value === "decimal") return value;
  throw new QuestionnaireContractError("invalid_number_kind");
}

function object(value: unknown, code: string): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new QuestionnaireContractError(code);
  }
  return value as Record<string, unknown>;
}

function array(value: unknown, code: string): readonly unknown[] {
  if (!Array.isArray(value)) throw new QuestionnaireContractError(code);
  return value;
}

function string(value: unknown, code: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new QuestionnaireContractError(code);
  }
  return value.trim();
}

function nullableString(value: unknown): string | null {
  return value === null || value === undefined
    ? null
    : string(value, "invalid_optional_string");
}

function positiveInteger(value: unknown, code: string): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 1) {
    throw new QuestionnaireContractError(code);
  }
  return value;
}

function boolean(value: unknown, code: string): boolean {
  if (typeof value !== "boolean") throw new QuestionnaireContractError(code);
  return value;
}

function nullableFiniteNumber(value: unknown): number | null {
  if (value === null || value === undefined) return null;
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new QuestionnaireContractError("invalid_number_bound");
  }
  return value;
}

function unique(values: readonly unknown[], code: string): void {
  if (new Set(values).size !== values.length) {
    throw new QuestionnaireContractError(code);
  }
}

function requireOnlyKeys(
  value: Readonly<Record<string, unknown>>,
  allowedKeys: ReadonlySet<string>,
): void {
  if (Object.keys(value).some((key) => !allowedKeys.has(key))) {
    throw new QuestionnaireContractError("unsupported_visibility_rule_field");
  }
}
