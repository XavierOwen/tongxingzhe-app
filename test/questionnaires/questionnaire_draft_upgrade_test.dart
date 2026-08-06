import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/questionnaires/questionnaire_contract.dart';
import 'package:tongxingzhe_app/questionnaires/questionnaire_draft_upgrade.dart';

void main() {
  test('升级规划只复制 fixture 中有审计兼容证据的有效答案', () {
    final fixture =
        jsonDecode(
              File(
                'fixtures/questionnaire/questionnaire-draft-upgrade-contract-v1.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final compatibilities = [
      for (final rawValue
          in fixture['audited_compatibilities']! as List<Object?>)
        if (rawValue case final Map<String, Object?> raw)
          AuditedQuestionnaireAnswerCompatibility(
            decisionId: raw['decision_id']! as String,
            sourceQuestionId: raw['source_question_id']! as String,
            targetQuestionId: raw['target_question_id']! as String,
          ),
    ];

    final plan = QuestionnaireDraftUpgradePlanner.plan(
      source: QuestionnaireContract.parseVersion(fixture['source']),
      target: QuestionnaireContract.parseVersion(fixture['target']),
      sourceAnswers: (fixture['source_answers']! as List<Object?>).map(
        QuestionnaireContract.parseAnswer,
      ),
      compatibilities: compatibilities,
    );
    final expected = fixture['expected']! as Map<String, Object?>;

    expect(
      plan.retained
          .map(
            (item) => {
              'decision_id': item.decisionId,
              'source_question_id': item.sourceQuestionId,
              'target_question_id': item.targetQuestionId,
            },
          )
          .toList(),
      expected['retained'],
    );
    expect(
      plan.requiresConfirmationQuestionIds,
      expected['requires_confirmation_question_ids'],
    );
    expect(
      plan.cannotCopySourceQuestionIds,
      expected['cannot_copy_source_question_ids'],
    );
    expect(
      plan.copiedAnswers.map(_answerJson).toList(),
      expected['copied_answers'],
    );
  });

  test('没有审计关系时安全地不复制答案', () {
    final fixture =
        jsonDecode(
              File(
                'fixtures/questionnaire/questionnaire-draft-upgrade-contract-v1.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;

    final plan = QuestionnaireDraftUpgradePlanner.plan(
      source: QuestionnaireContract.parseVersion(fixture['source']),
      target: QuestionnaireContract.parseVersion(fixture['target']),
      sourceAnswers: (fixture['source_answers']! as List<Object?>).map(
        QuestionnaireContract.parseAnswer,
      ),
      compatibilities: const [],
    );

    expect(plan.copiedAnswers, isEmpty);
    expect(plan.retained, isEmpty);
    expect(plan.requiresConfirmationQuestionIds, [
      'consent_v2',
      'topics',
      'age',
      'follow_up_date',
    ]);
    expect(plan.cannotCopySourceQuestionIds, [
      'consent',
      'topics',
      'age',
      'legacy_note',
    ]);
  });
}

Map<String, Object?> _answerJson(QuestionnaireAnswer answer) => {
  'question_id': answer.questionId,
  'state': answer.state.storageValue,
  'type': answer.type.storageValue,
  'value': answer.value,
};
