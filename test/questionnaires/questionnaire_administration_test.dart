import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/questionnaires/questionnaire_administration.dart';
import 'package:tongxingzhe_app/questionnaires/questionnaire_contract.dart';

void main() {
  test('shared fixture classifies every publication difference', () {
    final fixture =
        jsonDecode(
              File(
                'fixtures/questionnaire/questionnaire-design-contract-v1.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final current = QuestionnaireContract.parseVersion(fixture['current']);
    final candidate = QuestionnaireContract.parseVersion(fixture['candidate']);

    final actual = QuestionnaireDesign.differences(current, candidate)
        .map(
          (difference) => {
            'question_id': difference.questionId,
            'kind': difference.kind.name,
            'fields': difference.fields
                .map((field) => field.storageValue)
                .toList(),
          },
        )
        .toList();

    expect(actual, fixture['expected_differences']);
  });

  test('publication rejects an empty draft but accepts a valid definition', () {
    final empty = QuestionnaireVersion(
      id: 'draft-id',
      projectId: 'project-id',
      versionNumber: 1,
      questions: const [],
    );
    expect(
      () => QuestionnaireDesign.validateForPublication(empty),
      throwsFormatException,
    );

    final fixture =
        jsonDecode(
              File(
                'fixtures/questionnaire/questionnaire-design-contract-v1.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final candidate = QuestionnaireContract.parseVersion(fixture['candidate']);
    expect(
      QuestionnaireDesign.validateForPublication(candidate).questions,
      hasLength(4),
    );
  });
}
