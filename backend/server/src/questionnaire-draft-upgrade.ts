import {
  parseQuestionnaireAnswer,
  serializeQuestionnaireAnswer,
  validateQuestionnaireAnswers,
  type ParsedAnswer,
  type QuestionnaireVersion,
} from "./questionnaire-validator.js";

export interface AuditedQuestionnaireAnswerCompatibility {
  readonly decisionId: string;
  readonly sourceQuestionId: string;
  readonly targetQuestionId: string;
}

export interface RetainedQuestionnaireAnswer {
  readonly decisionId: string;
  readonly sourceQuestionId: string;
  readonly targetQuestionId: string;
}

export interface QuestionnaireDraftUpgradePlan {
  readonly retained: readonly RetainedQuestionnaireAnswer[];
  readonly requiresConfirmationQuestionIds: readonly string[];
  readonly cannotCopySourceQuestionIds: readonly string[];
  readonly copiedAnswers: readonly ParsedAnswer[];
}

/**
 * Copy only answers backed by a current audited compatibility decision.
 * An absent decision is an explicit fail-closed result, not a name match.
 */
export function planQuestionnaireDraftUpgrade(args: {
  readonly source: QuestionnaireVersion;
  readonly target: QuestionnaireVersion;
  readonly sourceAnswers: readonly unknown[];
  readonly compatibilities: readonly AuditedQuestionnaireAnswerCompatibility[];
}): QuestionnaireDraftUpgradePlan {
  const { source, target } = args;
  if (source.projectId !== target.projectId || source.id === target.id) {
    throw new Error("questionnaire_upgrade_scope_invalid");
  }
  const sourceQuestions = new Map(
    source.questions.map((question) => [question.id, question]),
  );
  const targetQuestions = new Map(
    target.questions.map((question) => [question.id, question]),
  );
  const mappings = new Map<
    string,
    AuditedQuestionnaireAnswerCompatibility
  >();
  const mappedTargets = new Set<string>();
  for (const compatibility of args.compatibilities) {
    if (
      compatibility.decisionId.trim().length === 0 ||
      compatibility.sourceQuestionId.trim().length === 0 ||
      compatibility.targetQuestionId.trim().length === 0 ||
      mappings.has(compatibility.sourceQuestionId) ||
      mappedTargets.has(compatibility.targetQuestionId)
    ) {
      throw new Error("questionnaire_compatibility_invalid");
    }
    mappings.set(compatibility.sourceQuestionId, compatibility);
    mappedTargets.add(compatibility.targetQuestionId);
  }

  const candidates = new Map<string, ParsedAnswer>();
  const sourceByTarget = new Map<string, string>();
  const decisionByTarget = new Map<string, string>();
  const cannotCopy = new Set<string>();
  for (const rawAnswer of args.sourceAnswers) {
    const answer = parseQuestionnaireAnswer(rawAnswer);
    if (
      answer.state === "unanswered" ||
      answer.stateReason === "rule_skipped"
    ) {
      continue;
    }
    const compatibility = mappings.get(answer.questionId);
    const sourceQuestion = sourceQuestions.get(answer.questionId);
    const targetQuestion = compatibility === undefined
      ? undefined
      : targetQuestions.get(compatibility.targetQuestionId);
    if (
      compatibility === undefined ||
      sourceQuestion === undefined ||
      targetQuestion === undefined ||
      sourceQuestion.type !== answer.type ||
      targetQuestion.type !== answer.type
    ) {
      cannotCopy.add(answer.questionId);
      continue;
    }
    candidates.set(targetQuestion.id, {
      questionId: targetQuestion.id,
      state: answer.state,
      stateReason: answer.stateReason,
      type: targetQuestion.type,
      value: answer.value,
    });
    sourceByTarget.set(targetQuestion.id, answer.questionId);
    decisionByTarget.set(targetQuestion.id, compatibility.decisionId);
  }

  const evaluation = validateQuestionnaireAnswers(
    target,
    [...candidates.values()].map(serializeQuestionnaireAnswer),
  );
  const invalidTargets = new Set(
    evaluation.errors
      .map((error) => error.slice(error.indexOf(":") + 1))
      .filter((questionId) => candidates.has(questionId)),
  );
  const visibleTargets = new Set(evaluation.visibleQuestionIds);
  const copiedById = new Map(
    evaluation.answers
      .filter((answer) =>
        candidates.has(answer.questionId) &&
        visibleTargets.has(answer.questionId) &&
        !invalidTargets.has(answer.questionId) &&
        answer.stateReason !== "rule_skipped"
      )
      .map((answer) => [answer.questionId, answer]),
  );
  for (const targetId of candidates.keys()) {
    if (!copiedById.has(targetId)) {
      cannotCopy.add(sourceByTarget.get(targetId)!);
    }
  }

  return {
    retained: target.questions.flatMap((question) =>
      copiedById.has(question.id)
        ? [{
          decisionId: decisionByTarget.get(question.id)!,
          sourceQuestionId: sourceByTarget.get(question.id)!,
          targetQuestionId: question.id,
        }]
        : []
    ),
    requiresConfirmationQuestionIds: target.questions
      .filter((question) => !copiedById.has(question.id))
      .map((question) => question.id),
    cannotCopySourceQuestionIds: source.questions
      .filter((question) => cannotCopy.has(question.id))
      .map((question) => question.id),
    copiedAnswers: target.questions.flatMap((question) => {
      const answer = copiedById.get(question.id);
      return answer === undefined ? [] : [answer];
    }),
  };
}
