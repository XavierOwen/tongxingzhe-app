import 'dart:convert';

import 'questionnaire_contract.dart';

/// 受控答案在 SQLite/PostgreSQL 协议间共用的确定值列。
final class QuestionnaireAnswerColumns {
  const QuestionnaireAnswerColumns({
    required this.questionId,
    required this.state,
    required this.type,
    this.booleanValue,
    this.textValue,
    this.numberValue,
    this.multiChoiceValueJson,
  });

  final String questionId;
  final String state;
  final String type;
  final bool? booleanValue;
  final String? textValue;
  final double? numberValue;
  final String? multiChoiceValueJson;
}

/// 集中答案的持久化和同步编码，防止草稿、提交、修订各自发明一种形状。
final class QuestionnaireAnswerCodec {
  const QuestionnaireAnswerCodec._();

  static QuestionnaireAnswerColumns toColumns(QuestionnaireAnswer answer) {
    final value = answer.state == QuestionnaireAnswerState.answered
        ? answer.value
        : null;
    return QuestionnaireAnswerColumns(
      questionId: answer.questionId,
      state: answer.state.storageValue,
      type: answer.type.storageValue,
      booleanValue: answer.type == QuestionnaireQuestionType.boolean
          ? value as bool?
          : null,
      textValue: switch (answer.type) {
        QuestionnaireQuestionType.singleChoice ||
        QuestionnaireQuestionType.ordinalChoice ||
        QuestionnaireQuestionType.date ||
        QuestionnaireQuestionType.shortText ||
        QuestionnaireQuestionType.longText => value as String?,
        _ => null,
      },
      numberValue: answer.type == QuestionnaireQuestionType.number
          ? (value as num?)?.toDouble()
          : null,
      multiChoiceValueJson:
          answer.type == QuestionnaireQuestionType.multiChoice && value != null
          ? jsonEncode(value)
          : null,
    );
  }

  static Map<String, Object?> toJson(QuestionnaireAnswer answer) => {
    'question_id': answer.questionId,
    'state': answer.state.storageValue,
    'type': answer.type.storageValue,
    'value': answer.state == QuestionnaireAnswerState.answered
        ? answer.value
        : null,
  };

  static QuestionnaireAnswer fromColumns({
    required String questionId,
    required String state,
    required String type,
    required bool? booleanValue,
    required String? textValue,
    required double? numberValue,
    required String? multiChoiceValueJson,
  }) {
    final parsedState = QuestionnaireAnswerState.fromStorage(state);
    final parsedType = QuestionnaireQuestionType.fromStorage(type);
    final value = switch (parsedType) {
      QuestionnaireQuestionType.boolean => booleanValue,
      QuestionnaireQuestionType.singleChoice ||
      QuestionnaireQuestionType.ordinalChoice ||
      QuestionnaireQuestionType.date ||
      QuestionnaireQuestionType.shortText ||
      QuestionnaireQuestionType.longText => textValue,
      QuestionnaireQuestionType.number => numberValue,
      QuestionnaireQuestionType.multiChoice =>
        multiChoiceValueJson == null
            ? null
            : _stringList(jsonDecode(multiChoiceValueJson)),
    };
    return _typedAnswer(
      questionId: questionId,
      state: parsedState,
      type: parsedType,
      value: value,
    );
  }

  static QuestionnaireAnswer fromJson(Object? raw) {
    if (raw is! Map<String, Object?>) {
      throw const FormatException('questionnaire answer must be an object');
    }
    final questionId = _string(raw['question_id'], 'question_id');
    final state = QuestionnaireAnswerState.fromStorage(
      _string(raw['state'], 'state'),
    );
    final type = QuestionnaireQuestionType.fromStorage(
      _string(raw['type'], 'type'),
    );
    return _typedAnswer(
      questionId: questionId,
      state: state,
      type: type,
      value: raw['value'],
    );
  }

  static QuestionnaireAnswer _typedAnswer({
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
          value: _bool(value),
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
          value: _string(value, 'value'),
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
          value: _string(value, 'value'),
        ),
        QuestionnaireAnswerState.unknown =>
          OrdinalChoiceQuestionnaireAnswer.unknown(questionId: questionId),
        QuestionnaireAnswerState.refused =>
          OrdinalChoiceQuestionnaireAnswer.refused(questionId: questionId),
        QuestionnaireAnswerState.notApplicable =>
          OrdinalChoiceQuestionnaireAnswer.notApplicable(
            questionId: questionId,
          ),
        QuestionnaireAnswerState.unanswered =>
          OrdinalChoiceQuestionnaireAnswer.unanswered(questionId: questionId),
      },
      QuestionnaireQuestionType.multiChoice => switch (state) {
        QuestionnaireAnswerState.answered => MultiChoiceQuestionnaireAnswer(
          questionId: questionId,
          value: _stringList(value),
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
          value: _number(value),
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
          value: _string(value, 'value'),
        ),
        QuestionnaireAnswerState.unknown => DateQuestionnaireAnswer.unknown(
          questionId: questionId,
        ),
        QuestionnaireAnswerState.refused => DateQuestionnaireAnswer.refused(
          questionId: questionId,
        ),
        QuestionnaireAnswerState.notApplicable =>
          DateQuestionnaireAnswer.notApplicable(questionId: questionId),
        QuestionnaireAnswerState.unanswered =>
          DateQuestionnaireAnswer.unanswered(questionId: questionId),
      },
      QuestionnaireQuestionType.shortText => switch (state) {
        QuestionnaireAnswerState.answered => ShortTextQuestionnaireAnswer(
          questionId: questionId,
          value: _string(value, 'value'),
        ),
        QuestionnaireAnswerState.unknown =>
          ShortTextQuestionnaireAnswer.unknown(questionId: questionId),
        QuestionnaireAnswerState.refused =>
          ShortTextQuestionnaireAnswer.refused(questionId: questionId),
        QuestionnaireAnswerState.notApplicable =>
          ShortTextQuestionnaireAnswer.notApplicable(questionId: questionId),
        QuestionnaireAnswerState.unanswered =>
          ShortTextQuestionnaireAnswer.unanswered(questionId: questionId),
      },
      QuestionnaireQuestionType.longText => switch (state) {
        QuestionnaireAnswerState.answered => LongTextQuestionnaireAnswer(
          questionId: questionId,
          value: _string(value, 'value'),
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
}

String _string(Object? value, String name) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$name must be a non-empty string');
  }
  return value;
}

bool _bool(Object? value) {
  if (value is! bool) {
    throw const FormatException('value must be a boolean');
  }
  return value;
}

num _number(Object? value) {
  if (value is! num || !value.isFinite) {
    throw const FormatException('value must be a finite number');
  }
  return value;
}

List<String> _stringList(Object? value) {
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    throw const FormatException('value must be a string list');
  }
  return List.unmodifiable(value.cast<String>());
}
