import 'package:drift/drift.dart';

import '../data/local_database.dart';

/// 已发布场景问卷支持的八种受控题型。
enum QuestionnaireQuestionType {
  boolean('boolean'),
  singleChoice('single_choice'),
  ordinalChoice('ordinal_choice'),
  multiChoice('multi_choice'),
  number('number'),
  date('date'),
  shortText('short_text'),
  longText('long_text');

  const QuestionnaireQuestionType(this.storageValue);

  final String storageValue;

  static QuestionnaireQuestionType fromStorage(String value) {
    return values.singleWhere((type) => type.storageValue == value);
  }
}

/// 问卷回答的五种明确状态。
enum QuestionnaireAnswerState {
  answered('answered'),
  unknown('unknown'),
  refused('refused'),
  notApplicable('not_applicable'),
  unanswered('unanswered');

  const QuestionnaireAnswerState(this.storageValue);

  final String storageValue;

  static QuestionnaireAnswerState fromStorage(String value) {
    return values.singleWhere((state) => state.storageValue == value);
  }
}

/// 场景问卷答案的类型化领域基类。
///
/// 回答状态与真实值始终分开。具体子类型使持久化层可以选择确定的值列，而
/// 不必把所有答案压成无法约束的任意 JSON。
sealed class QuestionnaireAnswer {
  const QuestionnaireAnswer({required this.questionId, required this.state});

  final String questionId;
  final QuestionnaireAnswerState state;
  QuestionnaireQuestionType get type;
  Object? get value;
}

/// 从题目定义、回答状态和值建立对应的类型化答案。
///
/// UI 和导入边界共用这一入口，避免各自维护八题型乘五状态的构造分支。
final class QuestionnaireAnswerFactory {
  const QuestionnaireAnswerFactory._();

  static QuestionnaireAnswer create({
    required QuestionnaireQuestion question,
    required QuestionnaireAnswerState state,
    Object? value,
  }) {
    final answerValue = state == QuestionnaireAnswerState.answered
        ? value
        : null;
    return _createTypedAnswer(
      questionId: question.id,
      state: state,
      type: question.type,
      value: answerValue,
    );
  }
}

QuestionnaireAnswer _createTypedAnswer({
  required String questionId,
  required QuestionnaireAnswerState state,
  required QuestionnaireQuestionType type,
  required Object? value,
}) {
  if (state == QuestionnaireAnswerState.answered && value == null) {
    throw const FormatException('answered questionnaire value is missing');
  }
  if (state != QuestionnaireAnswerState.answered && value != null) {
    throw const FormatException('non-answer state carries a value');
  }
  return switch (type) {
    QuestionnaireQuestionType.boolean => switch (state) {
      QuestionnaireAnswerState.answered => BooleanQuestionnaireAnswer(
        questionId: questionId,
        value: value as bool,
      ),
      QuestionnaireAnswerState.unknown => BooleanQuestionnaireAnswer.unknown(
        questionId: questionId,
      ),
      QuestionnaireAnswerState.refused => BooleanQuestionnaireAnswer.refused(
        questionId: questionId,
      ),
      QuestionnaireAnswerState.notApplicable =>
        BooleanQuestionnaireAnswer.notApplicable(questionId: questionId),
      QuestionnaireAnswerState.unanswered =>
        BooleanQuestionnaireAnswer.unanswered(questionId: questionId),
    },
    QuestionnaireQuestionType.singleChoice => switch (state) {
      QuestionnaireAnswerState.answered => SingleChoiceQuestionnaireAnswer(
        questionId: questionId,
        value: value as String,
      ),
      QuestionnaireAnswerState.unknown =>
        SingleChoiceQuestionnaireAnswer.unknown(questionId: questionId),
      QuestionnaireAnswerState.refused =>
        SingleChoiceQuestionnaireAnswer.refused(questionId: questionId),
      QuestionnaireAnswerState.notApplicable =>
        SingleChoiceQuestionnaireAnswer.notApplicable(questionId: questionId),
      QuestionnaireAnswerState.unanswered =>
        SingleChoiceQuestionnaireAnswer.unanswered(questionId: questionId),
    },
    QuestionnaireQuestionType.ordinalChoice => switch (state) {
      QuestionnaireAnswerState.answered => OrdinalChoiceQuestionnaireAnswer(
        questionId: questionId,
        value: value as String,
      ),
      QuestionnaireAnswerState.unknown =>
        OrdinalChoiceQuestionnaireAnswer.unknown(questionId: questionId),
      QuestionnaireAnswerState.refused =>
        OrdinalChoiceQuestionnaireAnswer.refused(questionId: questionId),
      QuestionnaireAnswerState.notApplicable =>
        OrdinalChoiceQuestionnaireAnswer.notApplicable(questionId: questionId),
      QuestionnaireAnswerState.unanswered =>
        OrdinalChoiceQuestionnaireAnswer.unanswered(questionId: questionId),
    },
    QuestionnaireQuestionType.multiChoice => switch (state) {
      QuestionnaireAnswerState.answered => MultiChoiceQuestionnaireAnswer(
        questionId: questionId,
        value: (value as List<Object?>).cast<String>(),
      ),
      QuestionnaireAnswerState.unknown =>
        MultiChoiceQuestionnaireAnswer.unknown(questionId: questionId),
      QuestionnaireAnswerState.refused =>
        MultiChoiceQuestionnaireAnswer.refused(questionId: questionId),
      QuestionnaireAnswerState.notApplicable =>
        MultiChoiceQuestionnaireAnswer.notApplicable(questionId: questionId),
      QuestionnaireAnswerState.unanswered =>
        MultiChoiceQuestionnaireAnswer.unanswered(questionId: questionId),
    },
    QuestionnaireQuestionType.number => switch (state) {
      QuestionnaireAnswerState.answered => NumberQuestionnaireAnswer(
        questionId: questionId,
        value: value as num,
      ),
      QuestionnaireAnswerState.unknown => NumberQuestionnaireAnswer.unknown(
        questionId: questionId,
      ),
      QuestionnaireAnswerState.refused => NumberQuestionnaireAnswer.refused(
        questionId: questionId,
      ),
      QuestionnaireAnswerState.notApplicable =>
        NumberQuestionnaireAnswer.notApplicable(questionId: questionId),
      QuestionnaireAnswerState.unanswered =>
        NumberQuestionnaireAnswer.unanswered(questionId: questionId),
    },
    QuestionnaireQuestionType.date => switch (state) {
      QuestionnaireAnswerState.answered => DateQuestionnaireAnswer(
        questionId: questionId,
        value: value as String,
      ),
      QuestionnaireAnswerState.unknown => DateQuestionnaireAnswer.unknown(
        questionId: questionId,
      ),
      QuestionnaireAnswerState.refused => DateQuestionnaireAnswer.refused(
        questionId: questionId,
      ),
      QuestionnaireAnswerState.notApplicable =>
        DateQuestionnaireAnswer.notApplicable(questionId: questionId),
      QuestionnaireAnswerState.unanswered => DateQuestionnaireAnswer.unanswered(
        questionId: questionId,
      ),
    },
    QuestionnaireQuestionType.shortText => switch (state) {
      QuestionnaireAnswerState.answered => ShortTextQuestionnaireAnswer(
        questionId: questionId,
        value: value as String,
      ),
      QuestionnaireAnswerState.unknown => ShortTextQuestionnaireAnswer.unknown(
        questionId: questionId,
      ),
      QuestionnaireAnswerState.refused => ShortTextQuestionnaireAnswer.refused(
        questionId: questionId,
      ),
      QuestionnaireAnswerState.notApplicable =>
        ShortTextQuestionnaireAnswer.notApplicable(questionId: questionId),
      QuestionnaireAnswerState.unanswered =>
        ShortTextQuestionnaireAnswer.unanswered(questionId: questionId),
    },
    QuestionnaireQuestionType.longText => switch (state) {
      QuestionnaireAnswerState.answered => LongTextQuestionnaireAnswer(
        questionId: questionId,
        value: value as String,
      ),
      QuestionnaireAnswerState.unknown => LongTextQuestionnaireAnswer.unknown(
        questionId: questionId,
      ),
      QuestionnaireAnswerState.refused => LongTextQuestionnaireAnswer.refused(
        questionId: questionId,
      ),
      QuestionnaireAnswerState.notApplicable =>
        LongTextQuestionnaireAnswer.notApplicable(questionId: questionId),
      QuestionnaireAnswerState.unanswered =>
        LongTextQuestionnaireAnswer.unanswered(questionId: questionId),
    },
  };
}

final class BooleanQuestionnaireAnswer extends QuestionnaireAnswer {
  const BooleanQuestionnaireAnswer({
    required super.questionId,
    required bool this.value,
  }) : super(state: QuestionnaireAnswerState.answered);

  const BooleanQuestionnaireAnswer.unknown({required super.questionId})
    : value = null,
      super(state: QuestionnaireAnswerState.unknown);
  const BooleanQuestionnaireAnswer.refused({required super.questionId})
    : value = null,
      super(state: QuestionnaireAnswerState.refused);
  const BooleanQuestionnaireAnswer.notApplicable({required super.questionId})
    : value = null,
      super(state: QuestionnaireAnswerState.notApplicable);
  const BooleanQuestionnaireAnswer.unanswered({required super.questionId})
    : value = null,
      super(state: QuestionnaireAnswerState.unanswered);

  @override
  QuestionnaireQuestionType get type => QuestionnaireQuestionType.boolean;
  @override
  final bool? value;

  @override
  bool operator ==(Object other) =>
      other is BooleanQuestionnaireAnswer &&
      _sameAnswer(this, other) &&
      other.value == value;
  @override
  int get hashCode => Object.hash(questionId, state, type, value);
}

final class SingleChoiceQuestionnaireAnswer extends QuestionnaireAnswer {
  const SingleChoiceQuestionnaireAnswer({
    required super.questionId,
    required String this.value,
  }) : super(state: QuestionnaireAnswerState.answered);
  const SingleChoiceQuestionnaireAnswer.unknown({required super.questionId})
    : value = null,
      super(state: QuestionnaireAnswerState.unknown);
  const SingleChoiceQuestionnaireAnswer.refused({required super.questionId})
    : value = null,
      super(state: QuestionnaireAnswerState.refused);
  const SingleChoiceQuestionnaireAnswer.notApplicable({
    required super.questionId,
  }) : value = null,
       super(state: QuestionnaireAnswerState.notApplicable);
  const SingleChoiceQuestionnaireAnswer.unanswered({required super.questionId})
    : value = null,
      super(state: QuestionnaireAnswerState.unanswered);

  @override
  QuestionnaireQuestionType get type => QuestionnaireQuestionType.singleChoice;
  @override
  final String? value;

  @override
  bool operator ==(Object other) =>
      other is SingleChoiceQuestionnaireAnswer &&
      _sameAnswer(this, other) &&
      other.value == value;
  @override
  int get hashCode => Object.hash(questionId, state, type, value);
}

final class OrdinalChoiceQuestionnaireAnswer extends QuestionnaireAnswer {
  const OrdinalChoiceQuestionnaireAnswer({
    required super.questionId,
    required String this.value,
  }) : super(state: QuestionnaireAnswerState.answered);
  const OrdinalChoiceQuestionnaireAnswer.unknown({required super.questionId})
    : value = null,
      super(state: QuestionnaireAnswerState.unknown);
  const OrdinalChoiceQuestionnaireAnswer.refused({required super.questionId})
    : value = null,
      super(state: QuestionnaireAnswerState.refused);
  const OrdinalChoiceQuestionnaireAnswer.notApplicable({
    required super.questionId,
  }) : value = null,
       super(state: QuestionnaireAnswerState.notApplicable);
  const OrdinalChoiceQuestionnaireAnswer.unanswered({required super.questionId})
    : value = null,
      super(state: QuestionnaireAnswerState.unanswered);

  @override
  QuestionnaireQuestionType get type => QuestionnaireQuestionType.ordinalChoice;
  @override
  final String? value;

  @override
  bool operator ==(Object other) =>
      other is OrdinalChoiceQuestionnaireAnswer &&
      _sameAnswer(this, other) &&
      other.value == value;
  @override
  int get hashCode => Object.hash(questionId, state, type, value);
}

final class MultiChoiceQuestionnaireAnswer extends QuestionnaireAnswer {
  MultiChoiceQuestionnaireAnswer({
    required super.questionId,
    required Iterable<String> value,
  }) : value = List.unmodifiable(value),
       super(state: QuestionnaireAnswerState.answered);
  const MultiChoiceQuestionnaireAnswer.unknown({required super.questionId})
    : value = null,
      super(state: QuestionnaireAnswerState.unknown);
  const MultiChoiceQuestionnaireAnswer.refused({required super.questionId})
    : value = null,
      super(state: QuestionnaireAnswerState.refused);
  const MultiChoiceQuestionnaireAnswer.notApplicable({
    required super.questionId,
  }) : value = null,
       super(state: QuestionnaireAnswerState.notApplicable);
  const MultiChoiceQuestionnaireAnswer.unanswered({required super.questionId})
    : value = null,
      super(state: QuestionnaireAnswerState.unanswered);

  @override
  QuestionnaireQuestionType get type => QuestionnaireQuestionType.multiChoice;
  @override
  final List<String>? value;

  @override
  bool operator ==(Object other) =>
      other is MultiChoiceQuestionnaireAnswer &&
      _sameAnswer(this, other) &&
      _listEquals(other.value, value);
  @override
  int get hashCode =>
      Object.hash(questionId, state, type, Object.hashAll(value ?? const []));
}

final class NumberQuestionnaireAnswer extends QuestionnaireAnswer {
  const NumberQuestionnaireAnswer({
    required super.questionId,
    required num this.value,
  }) : super(state: QuestionnaireAnswerState.answered);
  const NumberQuestionnaireAnswer.unknown({required super.questionId})
    : value = null,
      super(state: QuestionnaireAnswerState.unknown);
  const NumberQuestionnaireAnswer.refused({required super.questionId})
    : value = null,
      super(state: QuestionnaireAnswerState.refused);
  const NumberQuestionnaireAnswer.notApplicable({required super.questionId})
    : value = null,
      super(state: QuestionnaireAnswerState.notApplicable);
  const NumberQuestionnaireAnswer.unanswered({required super.questionId})
    : value = null,
      super(state: QuestionnaireAnswerState.unanswered);

  @override
  QuestionnaireQuestionType get type => QuestionnaireQuestionType.number;
  @override
  final num? value;

  @override
  bool operator ==(Object other) =>
      other is NumberQuestionnaireAnswer &&
      _sameAnswer(this, other) &&
      other.value == value;
  @override
  int get hashCode => Object.hash(questionId, state, type, value);
}

final class DateQuestionnaireAnswer extends QuestionnaireAnswer {
  const DateQuestionnaireAnswer({
    required super.questionId,
    required String this.value,
  }) : super(state: QuestionnaireAnswerState.answered);
  const DateQuestionnaireAnswer.unknown({required super.questionId})
    : value = null,
      super(state: QuestionnaireAnswerState.unknown);
  const DateQuestionnaireAnswer.refused({required super.questionId})
    : value = null,
      super(state: QuestionnaireAnswerState.refused);
  const DateQuestionnaireAnswer.notApplicable({required super.questionId})
    : value = null,
      super(state: QuestionnaireAnswerState.notApplicable);
  const DateQuestionnaireAnswer.unanswered({required super.questionId})
    : value = null,
      super(state: QuestionnaireAnswerState.unanswered);

  @override
  QuestionnaireQuestionType get type => QuestionnaireQuestionType.date;
  @override
  final String? value;

  @override
  bool operator ==(Object other) =>
      other is DateQuestionnaireAnswer &&
      _sameAnswer(this, other) &&
      other.value == value;
  @override
  int get hashCode => Object.hash(questionId, state, type, value);
}

final class ShortTextQuestionnaireAnswer extends QuestionnaireAnswer {
  const ShortTextQuestionnaireAnswer({
    required super.questionId,
    required String this.value,
  }) : super(state: QuestionnaireAnswerState.answered);
  const ShortTextQuestionnaireAnswer.unknown({required super.questionId})
    : value = null,
      super(state: QuestionnaireAnswerState.unknown);
  const ShortTextQuestionnaireAnswer.refused({required super.questionId})
    : value = null,
      super(state: QuestionnaireAnswerState.refused);
  const ShortTextQuestionnaireAnswer.notApplicable({required super.questionId})
    : value = null,
      super(state: QuestionnaireAnswerState.notApplicable);
  const ShortTextQuestionnaireAnswer.unanswered({required super.questionId})
    : value = null,
      super(state: QuestionnaireAnswerState.unanswered);

  @override
  QuestionnaireQuestionType get type => QuestionnaireQuestionType.shortText;
  @override
  final String? value;

  @override
  bool operator ==(Object other) =>
      other is ShortTextQuestionnaireAnswer &&
      _sameAnswer(this, other) &&
      other.value == value;
  @override
  int get hashCode => Object.hash(questionId, state, type, value);
}

final class LongTextQuestionnaireAnswer extends QuestionnaireAnswer {
  const LongTextQuestionnaireAnswer({
    required super.questionId,
    required String this.value,
  }) : super(state: QuestionnaireAnswerState.answered);
  const LongTextQuestionnaireAnswer.unknown({required super.questionId})
    : value = null,
      super(state: QuestionnaireAnswerState.unknown);
  const LongTextQuestionnaireAnswer.refused({required super.questionId})
    : value = null,
      super(state: QuestionnaireAnswerState.refused);
  const LongTextQuestionnaireAnswer.notApplicable({required super.questionId})
    : value = null,
      super(state: QuestionnaireAnswerState.notApplicable);
  const LongTextQuestionnaireAnswer.unanswered({required super.questionId})
    : value = null,
      super(state: QuestionnaireAnswerState.unanswered);

  @override
  QuestionnaireQuestionType get type => QuestionnaireQuestionType.longText;
  @override
  final String? value;

  @override
  bool operator ==(Object other) =>
      other is LongTextQuestionnaireAnswer &&
      _sameAnswer(this, other) &&
      other.value == value;
  @override
  int get hashCode => Object.hash(questionId, state, type, value);
}

/// 只用于在合同边界保留形状错误，以便 evaluator 返回稳定错误码。
final class _RawQuestionnaireAnswer extends QuestionnaireAnswer {
  const _RawQuestionnaireAnswer({
    required super.questionId,
    required super.state,
    required this.type,
    required this.value,
  });

  @override
  final QuestionnaireQuestionType type;
  @override
  final Object? value;
}

enum QuestionnaireNumberKind {
  integer('integer'),
  decimal('decimal');

  const QuestionnaireNumberKind(this.storageValue);
  final String storageValue;

  static QuestionnaireNumberKind fromStorage(String value) {
    return values.singleWhere((kind) => kind.storageValue == value);
  }
}

final class QuestionnaireOption {
  const QuestionnaireOption({
    required this.id,
    required this.position,
    required this.label,
  });

  final String id;
  final int position;
  final String label;
}

/// 一个不可变已发布问卷版本中的受控问题。
final class QuestionnaireQuestion {
  QuestionnaireQuestion({
    required this.id,
    required this.position,
    required this.prompt,
    required this.type,
    required this.required,
    required this.allowUnknown,
    required this.allowRefused,
    required this.allowNotApplicable,
    Iterable<QuestionnaireOption> options = const [],
    this.minimumSelections,
    this.maximumSelections,
    this.numberKind,
    this.unit,
    this.minimum,
    this.maximum,
    this.maximumLength,
  }) : options = List.unmodifiable(options);

  final String id;
  final int position;
  final String prompt;
  final QuestionnaireQuestionType type;
  final bool required;
  final bool allowUnknown;
  final bool allowRefused;
  final bool allowNotApplicable;
  final List<QuestionnaireOption> options;
  final int? minimumSelections;
  final int? maximumSelections;
  final QuestionnaireNumberKind? numberKind;
  final String? unit;
  final num? minimum;
  final num? maximum;
  final int? maximumLength;
}

final class QuestionnaireVersion {
  QuestionnaireVersion({
    required this.id,
    required this.projectId,
    required this.versionNumber,
    required Iterable<QuestionnaireQuestion> questions,
  }) : questions = List.unmodifiable(questions);

  final String id;
  final String projectId;
  final int versionNumber;
  final List<QuestionnaireQuestion> questions;
}

final class QuestionnaireValidationError {
  const QuestionnaireValidationError(this.code, this.questionId);

  final String code;
  final String questionId;
  String get contractCode => '$code:$questionId';
}

final class QuestionnaireEvaluation {
  QuestionnaireEvaluation(Iterable<QuestionnaireValidationError> errors)
    : errors = List.unmodifiable(errors);

  final List<QuestionnaireValidationError> errors;
  bool get isValid => errors.isEmpty;
}

abstract interface class QuestionnaireRemoteSource {
  Future<QuestionnaireVersion?> fetchPublishedVersion(String versionId);

  Future<void> close();
}

/// 问卷执行的窄外部接口：解析发布合同、缓存不可变版本并离线评估答案。
final class QuestionnaireCatalog {
  factory QuestionnaireCatalog({
    required LocalDatabase database,
    QuestionnaireRemoteSource? remoteSource,
  }) => QuestionnaireCatalog._(database, remoteSource);

  const QuestionnaireCatalog._(this._database, this._remoteSource);

  final LocalDatabase _database;
  final QuestionnaireRemoteSource? _remoteSource;

  /// 优先读取本机不可变缓存；首次联网取得后即可在离线时重复使用。
  Future<QuestionnaireVersion?> resolvePublishedVersion({
    required String projectId,
    required String versionId,
  }) async {
    final cached = await cachedVersion(
      projectId: projectId,
      versionId: versionId,
    );
    if (cached != null) {
      return cached;
    }
    final remote = await _remoteSource?.fetchPublishedVersion(versionId);
    if (remote == null) {
      return null;
    }
    if (remote.id != versionId || remote.projectId != projectId) {
      throw const QuestionnaireCatalogException('questionnaire_scope_mismatch');
    }
    await installPublishedVersion(remote);
    return cachedVersion(projectId: projectId, versionId: versionId);
  }

  Future<void> installPublishedVersion(QuestionnaireVersion version) async {
    final existing = await cachedVersion(
      projectId: version.projectId,
      versionId: version.id,
    );
    if (existing != null) {
      if (!_sameVersion(existing, version)) {
        throw const QuestionnaireCatalogException(
          'published_questionnaire_changed',
        );
      }
      return;
    }
    await _database.transaction(() async {
      await _database
          .into(_database.dbQuestionnaireVersions)
          .insert(
            DbQuestionnaireVersionsCompanion.insert(
              questionnaireVersionId: version.id,
              projectId: version.projectId,
              versionNumber: version.versionNumber,
              status: 'published',
              installedAtUtc: DateTime.now().toUtc(),
            ),
          );
      for (final question in version.questions) {
        await _database
            .into(_database.dbQuestionnaireQuestions)
            .insert(
              DbQuestionnaireQuestionsCompanion.insert(
                questionnaireVersionId: version.id,
                questionId: question.id,
                position: question.position,
                prompt: question.prompt,
                questionType: question.type.storageValue,
                isRequired: question.required,
                allowUnknown: question.allowUnknown,
                allowRefused: question.allowRefused,
                allowNotApplicable: question.allowNotApplicable,
                minimumSelections: Value(question.minimumSelections),
                maximumSelections: Value(question.maximumSelections),
                numberKind: Value(question.numberKind?.storageValue),
                unit: Value(question.unit),
                minimum: Value(question.minimum?.toDouble()),
                maximum: Value(question.maximum?.toDouble()),
                maximumLength: Value(question.maximumLength),
              ),
            );
        for (final option in question.options) {
          await _database
              .into(_database.dbQuestionnaireOptions)
              .insert(
                DbQuestionnaireOptionsCompanion.insert(
                  questionnaireVersionId: version.id,
                  questionId: question.id,
                  optionId: option.id,
                  position: option.position,
                  label: option.label,
                ),
              );
        }
      }
    });
  }

  Future<QuestionnaireVersion?> cachedVersion({
    required String projectId,
    required String versionId,
  }) async {
    final versionQuery = _database.select(_database.dbQuestionnaireVersions)
      ..where(
        (row) =>
            row.questionnaireVersionId.equals(versionId) &
            row.projectId.equals(projectId) &
            row.status.equals('published'),
      );
    final row = await versionQuery.getSingleOrNull();
    if (row == null) {
      return null;
    }
    final questionQuery = _database.select(_database.dbQuestionnaireQuestions)
      ..where((question) => question.questionnaireVersionId.equals(versionId));
    final optionQuery = _database.select(_database.dbQuestionnaireOptions)
      ..where((option) => option.questionnaireVersionId.equals(versionId));
    final questionRows = await questionQuery.get();
    final optionRows = await optionQuery.get();
    questionRows.sort((left, right) => left.position.compareTo(right.position));
    return QuestionnaireVersion(
      id: row.questionnaireVersionId,
      projectId: row.projectId,
      versionNumber: row.versionNumber,
      questions: [
        for (final question in questionRows)
          QuestionnaireQuestion(
            id: question.questionId,
            position: question.position,
            prompt: question.prompt,
            type: QuestionnaireQuestionType.fromStorage(question.questionType),
            required: question.isRequired,
            allowUnknown: question.allowUnknown,
            allowRefused: question.allowRefused,
            allowNotApplicable: question.allowNotApplicable,
            options: [
              for (final option in optionRows)
                if (option.questionId == question.questionId)
                  QuestionnaireOption(
                    id: option.optionId,
                    position: option.position,
                    label: option.label,
                  ),
            ]..sort((left, right) => left.position.compareTo(right.position)),
            minimumSelections: question.minimumSelections,
            maximumSelections: question.maximumSelections,
            numberKind: question.numberKind == null
                ? null
                : QuestionnaireNumberKind.fromStorage(question.numberKind!),
            unit: question.unit,
            minimum: question.minimum,
            maximum: question.maximum,
            maximumLength: question.maximumLength,
          ),
      ],
    );
  }

  Future<void> close() async => _remoteSource?.close();

  static QuestionnaireEvaluation evaluate(
    QuestionnaireVersion version,
    Iterable<QuestionnaireAnswer> answers,
  ) {
    final errors = <QuestionnaireValidationError>[];
    final questions = {
      for (final question in version.questions) question.id: question,
    };
    final answersByQuestion = <String, QuestionnaireAnswer>{};

    for (final answer in answers) {
      final question = questions[answer.questionId];
      if (question == null) {
        errors.add(
          QuestionnaireValidationError('unknown_question', answer.questionId),
        );
        continue;
      }
      if (answersByQuestion.containsKey(answer.questionId)) {
        errors.add(
          QuestionnaireValidationError('duplicate_answer', answer.questionId),
        );
        continue;
      }
      answersByQuestion[answer.questionId] = answer;
      if (answer.type != question.type) {
        errors.add(
          QuestionnaireValidationError('answer_type_mismatch', question.id),
        );
        continue;
      }
      if (answer.state != QuestionnaireAnswerState.answered) {
        if (answer.value != null) {
          errors.add(
            QuestionnaireValidationError(
              'answer_value_shape_invalid',
              question.id,
            ),
          );
          continue;
        }
        if (answer.state == QuestionnaireAnswerState.unanswered &&
            question.required) {
          errors.add(
            QuestionnaireValidationError(
              'required_answer_missing',
              question.id,
            ),
          );
        } else if (!_stateAllowed(question, answer.state)) {
          errors.add(
            QuestionnaireValidationError(
              'answer_state_not_allowed',
              question.id,
            ),
          );
        }
        continue;
      }
      if (!_validValue(question, answer.value)) {
        errors.add(
          QuestionnaireValidationError('answer_value_invalid', question.id),
        );
      }
    }

    for (final question in version.questions) {
      if (question.required && !answersByQuestion.containsKey(question.id)) {
        errors.add(
          QuestionnaireValidationError('required_answer_missing', question.id),
        );
      }
    }
    return QuestionnaireEvaluation(errors);
  }

  static bool _stateAllowed(
    QuestionnaireQuestion question,
    QuestionnaireAnswerState state,
  ) => switch (state) {
    QuestionnaireAnswerState.answered => true,
    QuestionnaireAnswerState.unknown => question.allowUnknown,
    QuestionnaireAnswerState.refused => question.allowRefused,
    QuestionnaireAnswerState.notApplicable => question.allowNotApplicable,
    QuestionnaireAnswerState.unanswered => !question.required,
  };

  static bool _validValue(QuestionnaireQuestion question, Object? value) {
    return switch (question.type) {
      QuestionnaireQuestionType.boolean => value is bool,
      QuestionnaireQuestionType.singleChoice ||
      QuestionnaireQuestionType.ordinalChoice =>
        value is String && question.options.any((option) => option.id == value),
      QuestionnaireQuestionType.multiChoice =>
        value is List<String> &&
            value.length >= question.minimumSelections! &&
            value.length <= question.maximumSelections! &&
            value.toSet().length == value.length &&
            value.every(
              (id) => question.options.any((option) => option.id == id),
            ),
      QuestionnaireQuestionType.number =>
        value is num &&
            value.isFinite &&
            (question.numberKind != QuestionnaireNumberKind.integer ||
                value is int ||
                value == value.roundToDouble()) &&
            (question.minimum == null || value >= question.minimum!) &&
            (question.maximum == null || value <= question.maximum!),
      QuestionnaireQuestionType.date =>
        value is String && _isCalendarDate(value),
      QuestionnaireQuestionType.shortText ||
      QuestionnaireQuestionType.longText =>
        value is String &&
            value.trim().isNotEmpty &&
            value.runes.length <= question.maximumLength!,
    };
  }

  static bool _sameVersion(
    QuestionnaireVersion left,
    QuestionnaireVersion right,
  ) {
    return QuestionnaireContract.versionToJson(left).toString() ==
        QuestionnaireContract.versionToJson(right).toString();
  }
}

final class QuestionnaireCatalogException implements Exception {
  const QuestionnaireCatalogException(this.code);

  final String code;
}

/// JSON 边界只接受受控字段；任意脚本、公式、SQL 或上传类型没有解析入口。
final class QuestionnaireContract {
  const QuestionnaireContract._();

  static QuestionnaireVersion parseVersion(Object? value) {
    final root = _object(value);
    if (_string(root['status']) != 'published') {
      throw const FormatException('questionnaire must be published');
    }
    final questions = _list(root['questions']).map(_parseQuestion).toList();
    if (questions.map((question) => question.id).toSet().length !=
            questions.length ||
        questions.map((question) => question.position).toSet().length !=
            questions.length) {
      throw const FormatException('question IDs and positions must be unique');
    }
    questions.sort((left, right) => left.position.compareTo(right.position));
    return QuestionnaireVersion(
      id: _string(root['questionnaire_version_id']),
      projectId: _string(root['project_id']),
      versionNumber: _positiveInt(root['version_number']),
      questions: questions,
    );
  }

  static QuestionnaireAnswer parseAnswer(Object? value) {
    final root = _object(value);
    return _RawQuestionnaireAnswer(
      questionId: _string(root['question_id']),
      state: QuestionnaireAnswerState.fromStorage(_string(root['state'])),
      type: QuestionnaireQuestionType.fromStorage(_string(root['type'])),
      value: _normalizeValue(root['value']),
    );
  }

  static Map<String, Object?> versionToJson(QuestionnaireVersion version) => {
    'questionnaire_version_id': version.id,
    'project_id': version.projectId,
    'version_number': version.versionNumber,
    'status': 'published',
    'questions': [
      for (final question in version.questions)
        {
          'question_id': question.id,
          'position': question.position,
          'prompt': question.prompt,
          'type': question.type.storageValue,
          'required': question.required,
          'allow_unknown': question.allowUnknown,
          'allow_refused': question.allowRefused,
          'allow_not_applicable': question.allowNotApplicable,
          if (question.options.isNotEmpty)
            'options': [
              for (final option in question.options)
                {
                  'option_id': option.id,
                  'position': option.position,
                  'label': option.label,
                },
            ],
          if (question.minimumSelections != null)
            'minimum_selections': question.minimumSelections,
          if (question.maximumSelections != null)
            'maximum_selections': question.maximumSelections,
          if (question.numberKind != null)
            'number_kind': question.numberKind!.storageValue,
          if (question.unit != null) 'unit': question.unit,
          if (question.minimum != null) 'minimum': question.minimum,
          if (question.maximum != null) 'maximum': question.maximum,
          if (question.maximumLength != null)
            'maximum_length': question.maximumLength,
        },
    ],
  };

  static QuestionnaireQuestion _parseQuestion(Object? value) {
    final root = _object(value);
    final type = QuestionnaireQuestionType.fromStorage(_string(root['type']));
    final options = root['options'] == null
        ? const <QuestionnaireOption>[]
        : _list(root['options']).map((rawOption) {
            final option = _object(rawOption);
            return QuestionnaireOption(
              id: _string(option['option_id']),
              position: _positiveInt(option['position']),
              label: _string(option['label']),
            );
          }).toList();
    final optionIds = options.map((option) => option.id).toSet();
    if (optionIds.length != options.length ||
        options.map((option) => option.position).toSet().length !=
            options.length) {
      throw const FormatException('option IDs and positions must be unique');
    }
    final choiceType =
        type == QuestionnaireQuestionType.singleChoice ||
        type == QuestionnaireQuestionType.ordinalChoice ||
        type == QuestionnaireQuestionType.multiChoice;
    if (choiceType != options.isNotEmpty) {
      throw const FormatException('choice questions require options only');
    }
    final minimumSelections = type == QuestionnaireQuestionType.multiChoice
        ? _positiveInt(root['minimum_selections'])
        : null;
    final maximumSelections = type == QuestionnaireQuestionType.multiChoice
        ? _positiveInt(root['maximum_selections'])
        : null;
    if (minimumSelections != null &&
        (maximumSelections! < minimumSelections ||
            maximumSelections > options.length)) {
      throw const FormatException('multi-choice selection bounds are invalid');
    }
    final numberKind = type == QuestionnaireQuestionType.number
        ? QuestionnaireNumberKind.fromStorage(_string(root['number_kind']))
        : null;
    final minimum = type == QuestionnaireQuestionType.number
        ? _nullableNum(root['minimum'])
        : null;
    final maximum = type == QuestionnaireQuestionType.number
        ? _nullableNum(root['maximum'])
        : null;
    if (minimum != null && maximum != null && minimum > maximum) {
      throw const FormatException('number range is invalid');
    }
    final textType =
        type == QuestionnaireQuestionType.shortText ||
        type == QuestionnaireQuestionType.longText;
    return QuestionnaireQuestion(
      id: _string(root['question_id']),
      position: _positiveInt(root['position']),
      prompt: _string(root['prompt']),
      type: type,
      required: _bool(root['required']),
      allowUnknown: _bool(root['allow_unknown']),
      allowRefused: _bool(root['allow_refused']),
      allowNotApplicable: _bool(root['allow_not_applicable']),
      options: options,
      minimumSelections: minimumSelections,
      maximumSelections: maximumSelections,
      numberKind: numberKind,
      unit: type == QuestionnaireQuestionType.number
          ? _nullableString(root['unit'])
          : null,
      minimum: minimum,
      maximum: maximum,
      maximumLength: textType ? _positiveInt(root['maximum_length']) : null,
    );
  }
}

bool _sameAnswer(QuestionnaireAnswer left, QuestionnaireAnswer right) =>
    left.questionId == right.questionId &&
    left.state == right.state &&
    left.type == right.type;

bool _listEquals(List<Object?>? left, List<Object?>? right) {
  if (identical(left, right)) {
    return true;
  }
  if (left == null || right == null || left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

bool _isCalendarDate(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) {
    return false;
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  if (month < 1 || month > 12 || day < 1 || day > 31) {
    return false;
  }
  final parsed = DateTime.utc(year, month, day);
  return parsed.year == year && parsed.month == month && parsed.day == day;
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('expected object');
  }
  return value;
}

List<Object?> _list(Object? value) {
  if (value is! List<Object?>) {
    throw const FormatException('expected list');
  }
  return value;
}

String _string(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('expected string');
  }
  return value.trim();
}

String? _nullableString(Object? value) => value == null ? null : _string(value);

int _positiveInt(Object? value) {
  if (value is! int || value < 1) {
    throw const FormatException('expected positive integer');
  }
  return value;
}

bool _bool(Object? value) {
  if (value is! bool) {
    throw const FormatException('expected boolean');
  }
  return value;
}

num? _nullableNum(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! num || !value.isFinite) {
    throw const FormatException('expected finite number');
  }
  return value;
}

Object? _normalizeValue(Object? value) {
  if (value is List<Object?> && value.every((item) => item is String)) {
    return value.cast<String>();
  }
  return value;
}
