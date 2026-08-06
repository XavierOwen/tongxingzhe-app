import 'questionnaire_contract.dart';

const questionnaireManagementCapability = 'manage_analysis_definitions';

enum QuestionnaireDifferenceKind { added, removed, changed }

enum QuestionnaireDifferenceField {
  definition('definition'),
  options('options'),
  valueBounds('value_bounds'),
  answerMode('answer_mode'),
  displayRule('display_rule');

  const QuestionnaireDifferenceField(this.storageValue);

  final String storageValue;
}

final class QuestionnaireDifference {
  QuestionnaireDifference({
    required this.questionId,
    required this.kind,
    required Iterable<QuestionnaireDifferenceField> fields,
  }) : fields = List.unmodifiable(fields);

  final String questionId;
  final QuestionnaireDifferenceKind kind;
  final List<QuestionnaireDifferenceField> fields;
}

final class QuestionnairePublishedVersionSummary {
  const QuestionnairePublishedVersionSummary({
    required this.id,
    required this.versionNumber,
    required this.isCurrent,
    required this.publishedAtUtc,
    required this.publishedByAppUserId,
    required this.publicationNote,
  });

  final String id;
  final int versionNumber;
  final bool isCurrent;
  final DateTime publishedAtUtc;
  final String? publishedByAppUserId;
  final String? publicationNote;
}

final class QuestionnaireDesignDraft {
  const QuestionnaireDesignDraft({
    required this.id,
    required this.projectId,
    required this.sourceVersionId,
    required this.revision,
    required this.updatedAtUtc,
    required this.definition,
    this.hasLocalChanges = false,
  });

  final String id;
  final String projectId;
  final String? sourceVersionId;
  final int revision;
  final DateTime updatedAtUtc;
  final QuestionnaireVersion definition;
  final bool hasLocalChanges;
}

final class QuestionnaireAdministrationSnapshot {
  QuestionnaireAdministrationSnapshot({
    required this.currentVersionId,
    required Iterable<QuestionnairePublishedVersionSummary> versions,
    required Iterable<QuestionnaireDesignDraft> drafts,
  }) : versions = List.unmodifiable(versions),
       drafts = List.unmodifiable(drafts);

  final String currentVersionId;
  final List<QuestionnairePublishedVersionSummary> versions;
  final List<QuestionnaireDesignDraft> drafts;
}

final class QuestionnairePublication {
  const QuestionnairePublication({
    required this.summary,
    required this.version,
  });

  final QuestionnairePublishedVersionSummary summary;
  final QuestionnaireVersion version;
}

enum QuestionnaireAdministrationFailureCode {
  unauthorized,
  forbidden,
  invalidDefinition,
  notFound,
  revisionConflict,
  networkUnavailable,
  serverRejected,
}

sealed class QuestionnaireAdministrationResult<T> {
  const QuestionnaireAdministrationResult();
}

final class QuestionnaireAdministrationSuccess<T>
    extends QuestionnaireAdministrationResult<T> {
  const QuestionnaireAdministrationSuccess(this.value);

  final T value;
}

final class QuestionnaireAdministrationRejected<T>
    extends QuestionnaireAdministrationResult<T> {
  const QuestionnaireAdministrationRejected(this.code);

  final QuestionnaireAdministrationFailureCode code;
}

abstract interface class QuestionnaireAdministrationGateway {
  Future<QuestionnaireAdministrationResult<QuestionnaireAdministrationSnapshot>>
  load();

  Future<QuestionnaireAdministrationResult<QuestionnaireDesignDraft>>
  createDraft({String? sourceVersionId});

  Future<QuestionnaireAdministrationResult<QuestionnaireDesignDraft>>
  saveDraft({
    required QuestionnaireDesignDraft draft,
    required QuestionnaireVersion definition,
  });

  Future<QuestionnaireAdministrationResult<QuestionnairePublication>> publish({
    required QuestionnaireDesignDraft draft,
    required String requestId,
    required String publicationNote,
  });

  Future<QuestionnaireVersion?> readPublishedVersion(String versionId);

  Future<void> close();
}

final class QuestionnaireDesign {
  const QuestionnaireDesign._();

  static List<QuestionnaireDifference> differences(
    QuestionnaireVersion current,
    QuestionnaireVersion candidate,
  ) {
    final currentById = {
      for (final question in current.questions) question.id: question,
    };
    final candidateById = {
      for (final question in candidate.questions) question.id: question,
    };
    final orderedIds = <String>[
      ...current.questions.map((question) => question.id),
      ...candidate.questions
          .map((question) => question.id)
          .where((id) => !currentById.containsKey(id)),
    ];
    return [
      for (final id in orderedIds)
        if (currentById[id] == null)
          QuestionnaireDifference(
            questionId: id,
            kind: QuestionnaireDifferenceKind.added,
            fields: const [QuestionnaireDifferenceField.definition],
          )
        else if (candidateById[id] == null)
          QuestionnaireDifference(
            questionId: id,
            kind: QuestionnaireDifferenceKind.removed,
            fields: const [QuestionnaireDifferenceField.definition],
          )
        else if (_changedFields(currentById[id]!, candidateById[id]!)
            case final fields when fields.isNotEmpty)
          QuestionnaireDifference(
            questionId: id,
            kind: QuestionnaireDifferenceKind.changed,
            fields: fields,
          ),
    ];
  }

  static QuestionnaireVersion validateForPublication(
    QuestionnaireVersion candidate,
  ) {
    if (candidate.questions.isEmpty) {
      throw const FormatException(
        'a published questionnaire requires at least one question',
      );
    }
    return QuestionnaireContract.parseVersion(
      QuestionnaireContract.versionToJson(candidate),
    );
  }

  static List<QuestionnaireDifferenceField> _changedFields(
    QuestionnaireQuestion current,
    QuestionnaireQuestion candidate,
  ) {
    final fields = <QuestionnaireDifferenceField>[];
    if (current.position != candidate.position ||
        current.prompt != candidate.prompt ||
        current.type != candidate.type ||
        current.required != candidate.required) {
      fields.add(QuestionnaireDifferenceField.definition);
    }
    if (!_sameOptions(current.options, candidate.options)) {
      fields.add(QuestionnaireDifferenceField.options);
    }
    if (current.minimumSelections != candidate.minimumSelections ||
        current.maximumSelections != candidate.maximumSelections ||
        current.numberKind != candidate.numberKind ||
        current.unit != candidate.unit ||
        current.minimum != candidate.minimum ||
        current.maximum != candidate.maximum ||
        current.maximumLength != candidate.maximumLength) {
      fields.add(QuestionnaireDifferenceField.valueBounds);
    }
    if (current.allowUnknown != candidate.allowUnknown ||
        current.allowRefused != candidate.allowRefused ||
        current.allowNotApplicable != candidate.allowNotApplicable) {
      fields.add(QuestionnaireDifferenceField.answerMode);
    }
    if (!_sameDisplayRule(current.displayRule, candidate.displayRule)) {
      fields.add(QuestionnaireDifferenceField.displayRule);
    }
    return fields;
  }

  static bool _sameOptions(
    List<QuestionnaireOption> current,
    List<QuestionnaireOption> candidate,
  ) {
    if (current.length != candidate.length) return false;
    for (var index = 0; index < current.length; index += 1) {
      final left = current[index];
      final right = candidate[index];
      if (left.id != right.id ||
          left.position != right.position ||
          left.label != right.label) {
        return false;
      }
    }
    return true;
  }

  static bool _sameDisplayRule(
    QuestionnaireVisibilityRule? current,
    QuestionnaireVisibilityRule? candidate,
  ) {
    if (current == null || candidate == null) return current == candidate;
    if (current.match != candidate.match ||
        current.conditions.length != candidate.conditions.length) {
      return false;
    }
    for (var index = 0; index < current.conditions.length; index += 1) {
      final left = current.conditions[index];
      final right = candidate.conditions[index];
      if (left.sourceQuestionId != right.sourceQuestionId ||
          left.operator != right.operator ||
          left.operand.toString() != right.operand.toString()) {
        return false;
      }
    }
    return true;
  }
}
