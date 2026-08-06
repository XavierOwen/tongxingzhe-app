import 'questionnaire_contract.dart';

/// 由可信兼容目录返回的一条当前有效审计决定。
final class AuditedQuestionnaireAnswerCompatibility {
  const AuditedQuestionnaireAnswerCompatibility({
    required this.decisionId,
    required this.sourceQuestionId,
    required this.targetQuestionId,
  });

  final String decisionId;
  final String sourceQuestionId;
  final String targetQuestionId;
}

final class RetainedQuestionnaireAnswer {
  const RetainedQuestionnaireAnswer({
    required this.decisionId,
    required this.sourceQuestionId,
    required this.targetQuestionId,
  });

  final String decisionId;
  final String sourceQuestionId;
  final String targetQuestionId;
}

/// 升级确认页使用的稳定分类。这里只规划复制，不修改任何草稿。
final class QuestionnaireDraftUpgradePlan {
  QuestionnaireDraftUpgradePlan({
    required Iterable<RetainedQuestionnaireAnswer> retained,
    required Iterable<String> requiresConfirmationQuestionIds,
    required Iterable<String> cannotCopySourceQuestionIds,
    required Iterable<QuestionnaireAnswer> copiedAnswers,
  }) : retained = List.unmodifiable(retained),
       requiresConfirmationQuestionIds = List.unmodifiable(
         requiresConfirmationQuestionIds,
       ),
       cannotCopySourceQuestionIds = List.unmodifiable(
         cannotCopySourceQuestionIds,
       ),
       copiedAnswers = List.unmodifiable(copiedAnswers);

  final List<RetainedQuestionnaireAnswer> retained;
  final List<String> requiresConfirmationQuestionIds;
  final List<String> cannotCopySourceQuestionIds;
  final List<QuestionnaireAnswer> copiedAnswers;
}

/// 只复制明确审计且在目标定义中仍有效的答案。缺少兼容证据时默认不复制。
final class QuestionnaireDraftUpgradePlanner {
  const QuestionnaireDraftUpgradePlanner._();

  static QuestionnaireDraftUpgradePlan plan({
    required QuestionnaireVersion source,
    required QuestionnaireVersion target,
    required Iterable<QuestionnaireAnswer> sourceAnswers,
    required Iterable<AuditedQuestionnaireAnswerCompatibility> compatibilities,
  }) {
    if (source.projectId != target.projectId || source.id == target.id) {
      throw const FormatException('questionnaire upgrade scope is invalid');
    }
    final sourceQuestions = {
      for (final question in source.questions) question.id: question,
    };
    final targetQuestions = {
      for (final question in target.questions) question.id: question,
    };
    final mappings = <String, AuditedQuestionnaireAnswerCompatibility>{};
    final targetMappingIds = <String>{};
    for (final compatibility in compatibilities) {
      if (compatibility.decisionId.trim().isEmpty ||
          compatibility.sourceQuestionId.trim().isEmpty ||
          compatibility.targetQuestionId.trim().isEmpty ||
          mappings.containsKey(compatibility.sourceQuestionId) ||
          !targetMappingIds.add(compatibility.targetQuestionId)) {
        throw const FormatException('questionnaire compatibility is invalid');
      }
      mappings[compatibility.sourceQuestionId] = compatibility;
    }

    final candidates = <String, QuestionnaireAnswer>{};
    final sourceByTarget = <String, String>{};
    final decisionByTarget = <String, String>{};
    final cannotCopy = <String>{};
    for (final answer in sourceAnswers) {
      if (answer.state == QuestionnaireAnswerState.unanswered ||
          answer.stateReason == questionnaireRuleSkippedReason) {
        continue;
      }
      final compatibility = mappings[answer.questionId];
      final sourceQuestion = sourceQuestions[answer.questionId];
      final targetQuestion = compatibility == null
          ? null
          : targetQuestions[compatibility.targetQuestionId];
      if (compatibility == null ||
          sourceQuestion == null ||
          targetQuestion == null ||
          sourceQuestion.type != answer.type ||
          targetQuestion.type != answer.type) {
        cannotCopy.add(answer.questionId);
        continue;
      }
      candidates[targetQuestion.id] = QuestionnaireAnswerFactory.create(
        question: targetQuestion,
        state: answer.state,
        value: answer.value,
      );
      sourceByTarget[targetQuestion.id] = answer.questionId;
      decisionByTarget[targetQuestion.id] = compatibility.decisionId;
    }

    final evaluation = QuestionnaireCatalog.evaluate(target, candidates.values);
    final invalidTargets = {
      for (final error in evaluation.errors)
        if (candidates.containsKey(error.questionId)) error.questionId,
    };
    final visibleTargets = evaluation.visibleQuestionIds.toSet();
    final copiedById = {
      for (final answer in evaluation.answers)
        if (candidates.containsKey(answer.questionId) &&
            visibleTargets.contains(answer.questionId) &&
            !invalidTargets.contains(answer.questionId) &&
            answer.stateReason != questionnaireRuleSkippedReason)
          answer.questionId: answer,
    };
    for (final targetId in candidates.keys) {
      if (!copiedById.containsKey(targetId)) {
        cannotCopy.add(sourceByTarget[targetId]!);
      }
    }

    final retained = [
      for (final question in target.questions)
        if (copiedById.containsKey(question.id))
          RetainedQuestionnaireAnswer(
            decisionId: decisionByTarget[question.id]!,
            sourceQuestionId: sourceByTarget[question.id]!,
            targetQuestionId: question.id,
          ),
    ];
    return QuestionnaireDraftUpgradePlan(
      retained: retained,
      requiresConfirmationQuestionIds: [
        for (final question in target.questions)
          if (!copiedById.containsKey(question.id)) question.id,
      ],
      cannotCopySourceQuestionIds: [
        for (final question in source.questions)
          if (cannotCopy.contains(question.id)) question.id,
      ],
      copiedAnswers: [
        for (final question in target.questions) ?copiedById[question.id],
      ],
    );
  }
}
