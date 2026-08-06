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
}

interface ParsedAnswer {
  readonly questionId: string;
  readonly state: QuestionnaireAnswerState;
  readonly type: QuestionnaireQuestionType;
  readonly value: unknown;
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
    if (question.required && !answers.has(question.id)) {
      errors.push(`required_answer_missing:${question.id}`);
    }
  }
  return { valid: errors.length === 0, errors };
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
  };
}

function parseAnswer(value: unknown): ParsedAnswer {
  const root = object(value, "invalid_answer");
  return {
    questionId: string(root.question_id, "invalid_question_id"),
    state: answerState(root.state),
    type: questionType(root.type),
    value: root.value,
  };
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
