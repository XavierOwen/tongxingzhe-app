import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/features/contact_entry/questionnaire_form.dart';
import 'package:tongxingzhe_app/l10n/app_strings.dart';
import 'package:tongxingzhe_app/questionnaires/questionnaire_contract.dart';

void main() {
  testWidgets('shared fixture 的八种受控题型都可填写', (tester) async {
    final version = _fixtureVersion();
    final values = <String, Object>{};
    await _pumpForm(
      tester,
      version: version,
      onValueChanged: (question, value) => values[question.id] = value,
    );

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('question-follow_up_consent-true')),
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('question-primary_interest-study')),
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('question-readiness-high')),
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('question-topics-events')),
    );
    await _enterVisible(
      tester,
      find.byKey(const ValueKey('question-value-household_size')),
      '4',
    );
    await _enterVisible(
      tester,
      find.byKey(const ValueKey('question-value-available_hours')),
      '2.5',
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('question-value-preferred_date')),
    );
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await _enterVisible(
      tester,
      find.byKey(const ValueKey('question-value-short_note')),
      '简短备注',
    );
    await _enterVisible(
      tester,
      find.byKey(const ValueKey('question-value-long_note')),
      '较长的受控问卷回答',
    );

    expect(values['follow_up_consent'], isTrue);
    expect(values['primary_interest'], 'study');
    expect(values['readiness'], 'high');
    expect(values['topics'], ['events']);
    expect(values['household_size'], 4);
    expect(values['available_hours'], 2.5);
    expect(values['preferred_date'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    expect(values['short_note'], '简短备注');
    expect(values['long_note'], '较长的受控问卷回答');
  });

  testWidgets('未知、拒答、不适用和未回答保持为独立状态', (tester) async {
    final states = <String, QuestionnaireAnswerState>{};
    await _pumpForm(
      tester,
      version: _fixtureVersion(),
      onStateChanged: (question, state) => states[question.id] = state,
    );

    await _selectState(tester, 'primary_interest', '不知道');
    await _selectState(tester, 'follow_up_consent', '拒绝回答');
    await _selectState(tester, 'topics', '不适用');
    await _selectState(tester, 'household_size', '未回答');

    expect(states['primary_interest'], QuestionnaireAnswerState.unknown);
    expect(states['follow_up_consent'], QuestionnaireAnswerState.refused);
    expect(states['topics'], QuestionnaireAnswerState.notApplicable);
    expect(states['household_size'], QuestionnaireAnswerState.unanswered);
  });
}

QuestionnaireVersion _fixtureVersion() {
  final root =
      jsonDecode(
            File(
              'fixtures/questionnaire/questionnaire-contract-v1.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;
  return QuestionnaireContract.parseVersion(root['questionnaire']);
}

Future<void> _pumpForm(
  WidgetTester tester, {
  required QuestionnaireVersion version,
  void Function(QuestionnaireQuestion, Object)? onValueChanged,
  void Function(QuestionnaireQuestion, QuestionnaireAnswerState)?
  onStateChanged,
}) async {
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            QuestionnaireForm(
              text: const AppStrings('zh'),
              version: version,
              answers: const [],
              errors: const [],
              onValueChanged: onValueChanged ?? (_, _) {},
              onStateChanged: onStateChanged ?? (_, _) {},
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _enterVisible(
  WidgetTester tester,
  Finder finder,
  String value,
) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.enterText(finder, value);
  await tester.pump();
}

Future<void> _selectState(
  WidgetTester tester,
  String questionId,
  String label,
) async {
  final dropdown = find.byKey(
    ValueKey('question-state-$questionId-unanswered'),
  );
  await tester.ensureVisible(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}
