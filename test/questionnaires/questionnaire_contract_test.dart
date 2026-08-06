import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/questionnaires/questionnaire_contract.dart';

void main() {
  final fixture =
      jsonDecode(
            File(
              'fixtures/questionnaire/questionnaire-contract-v1.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;

  test('shared questionnaire fixture covers all eight controlled types', () {
    final questionnaire = QuestionnaireContract.parseVersion(
      fixture['questionnaire'],
    );

    expect(
      questionnaire.questions.map((question) => question.type).toSet(),
      QuestionnaireQuestionType.values.toSet(),
    );
  });

  test('offline evaluator agrees with every shared contract case', () {
    final questionnaire = QuestionnaireContract.parseVersion(
      fixture['questionnaire'],
    );
    final cases = fixture['cases']! as List<Object?>;

    for (final rawCase in cases) {
      final caseValue = rawCase! as Map<String, Object?>;
      final answers = (caseValue['answers']! as List<Object?>)
          .map(QuestionnaireContract.parseAnswer)
          .toList(growable: false);
      final result = QuestionnaireCatalog.evaluate(questionnaire, answers);

      expect(
        result.isValid,
        caseValue['valid'],
        reason: caseValue['name']! as String,
      );
      expect(
        result.errors.map((error) => error.contractCode).toList(),
        (caseValue['errors']! as List<Object?>).cast<String>(),
        reason: caseValue['name']! as String,
      );
    }
  });
}
