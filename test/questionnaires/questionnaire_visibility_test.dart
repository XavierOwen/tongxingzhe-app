import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/questionnaires/questionnaire_answer_codec.dart';
import 'package:tongxingzhe_app/questionnaires/questionnaire_contract.dart';

void main() {
  final fixture =
      jsonDecode(
            File(
              'fixtures/questionnaire/questionnaire-visibility-contract-v1.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;
  final version = QuestionnaireContract.parseVersion(fixture['questionnaire']);

  test('Flutter evaluator agrees with every shared visibility case', () {
    final fixtureOperators =
        (fixture['questionnaire']! as Map<String, Object?>)['questions']!
            as List<Object?>;
    final coveredOperators = {
      for (final rawQuestion in fixtureOperators)
        for (final rawCondition
            in (((rawQuestion! as Map<String, Object?>)['display_rule']
                        as Map<String, Object?>?)?['conditions']
                    as List<Object?>?) ??
                const [])
          (rawCondition! as Map<String, Object?>)['operator'],
    };
    expect(
      coveredOperators,
      QuestionnaireVisibilityOperator.values
          .map((operator) => operator.storageValue)
          .toSet(),
    );
    for (final rawCase in fixture['evaluation_cases']! as List<Object?>) {
      final contractCase = rawCase! as Map<String, Object?>;
      final answers = (contractCase['answers']! as List<Object?>)
          .map(QuestionnaireContract.parseAnswer)
          .toList();
      final evaluation = QuestionnaireCatalog.evaluate(version, answers);

      expect(
        evaluation.visibleQuestionIds,
        contractCase['visible_question_ids'],
        reason: contractCase['name']! as String,
      );
      expect(
        evaluation.ruleSkippedQuestionIds,
        contractCase['rule_skipped_question_ids'],
        reason: contractCase['name']! as String,
      );
      expect(evaluation.isValid, contractCase['valid']);
      expect(
        evaluation.errors.map((error) => error.contractCode),
        contractCase['errors'],
        reason: contractCase['name']! as String,
      );
    }
  });

  test(
    'answer transition reports every answered question that would clear',
    () {
      final contractCase = fixture['transition_case']! as Map<String, Object?>;
      final answers = (contractCase['answers']! as List<Object?>)
          .map(QuestionnaireContract.parseAnswer)
          .toList();
      final nextAnswer = QuestionnaireContract.parseAnswer(
        contractCase['next_answer'],
      );

      final transition = QuestionnaireCatalog.previewAnswerChange(
        version,
        answers,
        nextAnswer,
      );

      expect(
        transition.answersToClear.map((answer) => answer.questionId),
        contractCase['clear_question_ids'],
      );
      for (final questionId in contractCase['clear_question_ids']! as List) {
        final answer = transition.answers.singleWhere(
          (answer) => answer.questionId == questionId,
        );
        expect(answer.state, QuestionnaireAnswerState.notApplicable);
        expect(answer.stateReason, 'rule_skipped');
        expect(answer.value, isNull);
      }
    },
  );

  test('definition rejects forward references and incompatible operators', () {
    final rawVersion =
        jsonDecode(jsonEncode(fixture['questionnaire']))
            as Map<String, Object?>;
    final questions = rawVersion['questions']! as List<Object?>;
    final first = questions.first! as Map<String, Object?>;
    first['display_rule'] = {
      'match': 'all',
      'conditions': [
        {
          'source_question_id': 'interest',
          'operator': 'equals',
          'operand': 'study',
        },
      ],
    };
    expect(
      () => QuestionnaireContract.parseVersion(rawVersion),
      throwsFormatException,
    );

    final invalidOperator =
        jsonDecode(jsonEncode(fixture['questionnaire']))
            as Map<String, Object?>;
    final invalidQuestions = invalidOperator['questions']! as List<Object?>;
    final target = invalidQuestions[6]! as Map<String, Object?>;
    target['display_rule'] = {
      'match': 'all',
      'conditions': [
        {
          'source_question_id': 'consent',
          'operator': 'greater_than',
          'operand': true,
        },
      ],
    };
    expect(
      () => QuestionnaireContract.parseVersion(invalidOperator),
      throwsFormatException,
    );

    final nestedRule =
        jsonDecode(jsonEncode(fixture['questionnaire']))
            as Map<String, Object?>;
    final nestedQuestions = nestedRule['questions']! as List<Object?>;
    final nestedTarget = nestedQuestions[6]! as Map<String, Object?>;
    nestedTarget['display_rule'] = {
      'match': 'all',
      'conditions': [
        {
          'source_question_id': 'consent',
          'operator': 'equals',
          'operand': true,
          'conditions': <Object?>[],
        },
      ],
    };
    expect(
      () => QuestionnaireContract.parseVersion(nestedRule),
      throwsFormatException,
    );
  });

  test('rule skipped reason survives typed columns and sync JSON', () {
    const skipped = RuleSkippedQuestionnaireAnswer(
      questionId: 'event_detail',
      type: QuestionnaireQuestionType.shortText,
    );
    final columns = QuestionnaireAnswerCodec.toColumns(skipped);

    expect(
      QuestionnaireAnswerCodec.fromColumns(
        questionId: columns.questionId,
        state: columns.state,
        stateReason: columns.stateReason,
        type: columns.type,
        booleanValue: columns.booleanValue,
        textValue: columns.textValue,
        numberValue: columns.numberValue,
        multiChoiceValueJson: columns.multiChoiceValueJson,
      ),
      skipped,
    );
    expect(
      QuestionnaireAnswerCodec.fromJson(
        QuestionnaireAnswerCodec.toJson(skipped),
      ),
      skipped,
    );
  });
}
