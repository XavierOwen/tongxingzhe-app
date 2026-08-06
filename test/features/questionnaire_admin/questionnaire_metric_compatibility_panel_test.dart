import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/features/questionnaire_admin/questionnaire_metric_compatibility_panel.dart';
import 'package:tongxingzhe_app/foundation/runtime_values.dart';
import 'package:tongxingzhe_app/l10n/app_strings.dart';
import 'package:tongxingzhe_app/questionnaires/questionnaire_administration.dart';
import 'package:tongxingzhe_app/questionnaires/questionnaire_metric_compatibility.dart';

void main() {
  testWidgets('管理员并排比较定义和样本影响后明确确认兼容', (tester) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = _MetricGateway();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: QuestionnaireMetricCompatibilityPanel(
              text: const AppStrings('zh'),
              gateway: gateway,
              idGenerator: _Ids(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('audit-questionnaire-metric')));
    await tester.pumpAndSettle();
    expect(find.text('兴趣程度（第一版）'), findsOneWidget);
    expect(find.text('兴趣程度（第二版）'), findsOneWidget);
    expect(find.textContaining('必填 · 不知道 · 拒绝回答'), findsNWidgets(2));
    expect(find.textContaining('1. low: 较低'), findsNWidgets(2));
    expect(find.text('合并后的样本影响: 12 + 8 = 20'), findsOneWidget);
    expect(find.textContaining('2026-07-01: 12 + 8 = 20'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('questionnaire-metric-label')),
      '接触兴趣',
    );
    await tester.enterText(
      find.byKey(const ValueKey('questionnaire-metric-reason')),
      '定义、选项、时间范围和回答方式均未改变',
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('confirm-questionnaire-metric-decision')),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(
      find.byKey(const ValueKey('confirm-questionnaire-metric-decision')),
    );
    await tester.pumpAndSettle();

    expect(gateway.recordedDecision, QuestionnaireMetricDecision.compatible);
    expect(gateway.recordedReason, '定义、选项、时间范围和回答方式均未改变');
    expect(find.text('接触兴趣'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('questionnaire-metric-revoke-reason')),
      '复核发现时间范围已经改变',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('confirm-questionnaire-metric-revocation')),
    );
    await tester.pumpAndSettle();
    expect(gateway.revokedReason, '复核发现时间范围已经改变');
    expect(find.text('已撤销兼容'), findsOneWidget);
  });
}

final class _MetricGateway implements QuestionnaireMetricCompatibilityGateway {
  QuestionnaireMetricDecision? recordedDecision;
  String? recordedReason;
  String? revokedReason;
  var _recorded = false;
  QuestionnaireMetricCompatibilityEvent? _event;
  QuestionnaireMetricCompatibilityEvent? _revocation;

  @override
  Future<
    QuestionnaireAdministrationResult<QuestionnaireMetricCompatibilitySnapshot>
  >
  loadMetricCompatibility() async => QuestionnaireAdministrationSuccess(
    QuestionnaireMetricCompatibilitySnapshot(
      metrics: _recorded
          ? [
              QuestionnaireMetricDefinition(
                id: 'metric-id',
                label: '接触兴趣',
                analysisOperation:
                    QuestionnaireMetricAnalysisOperation.distribution,
                activeMembers: _revocation == null
                    ? [_questions[0].reference, _questions[1].reference]
                    : [_questions[0].reference],
              ),
            ]
          : const [],
      availableQuestions: _questions,
      events: [?_revocation, ?_event],
    ),
  );

  @override
  Future<
    QuestionnaireAdministrationResult<QuestionnaireMetricCompatibilityEvent>
  >
  recordMetricCompatibility({
    required String metricId,
    required String metricLabel,
    required QuestionnaireMetricAnalysisOperation analysisOperation,
    required QuestionnaireMetricQuestionReference reference,
    required QuestionnaireMetricQuestionReference candidate,
    required QuestionnaireMetricDecision decision,
    required String reason,
    required String requestId,
  }) async {
    recordedDecision = decision;
    recordedReason = reason;
    _recorded = true;
    _event = QuestionnaireMetricCompatibilityEvent(
      id: 'event-id',
      metricId: metricId,
      action: QuestionnaireMetricCompatibilityAction.decided,
      decision: decision,
      targetEventId: null,
      reference: reference,
      candidate: candidate,
      actorAppUserId: 'user-id',
      reason: reason,
      impact: QuestionnaireMetricImpactSnapshot(
        referenceSampleCount: 12,
        candidateSampleCount: 8,
        combinedSampleCount: 20,
        separateSeries: const [],
      ),
      createdAtUtc: DateTime.utc(2026, 8, 6),
    );
    return QuestionnaireAdministrationSuccess(_event!);
  }

  @override
  Future<
    QuestionnaireAdministrationResult<QuestionnaireMetricCompatibilityEvent>
  >
  revokeMetricCompatibility({
    required String eventId,
    required String reason,
    required String requestId,
  }) async {
    revokedReason = reason;
    final target = _event!;
    _revocation = QuestionnaireMetricCompatibilityEvent(
      id: 'revocation-id',
      metricId: target.metricId,
      action: QuestionnaireMetricCompatibilityAction.revoked,
      decision: QuestionnaireMetricDecision.compatible,
      targetEventId: target.id,
      reference: target.reference,
      candidate: target.candidate,
      actorAppUserId: 'user-id',
      reason: reason,
      impact: target.impact,
      createdAtUtc: DateTime.utc(2026, 8, 6, 1),
    );
    return QuestionnaireAdministrationSuccess(_revocation!);
  }
}

final _questions = [
  _candidate('version-1', 1, 'interest', '兴趣程度（第一版）', 12),
  _candidate('version-2', 2, 'interest-v2', '兴趣程度（第二版）', 8),
];

QuestionnaireMetricQuestionCandidate _candidate(
  String versionId,
  int versionNumber,
  String questionId,
  String prompt,
  int sampleCount,
) => QuestionnaireMetricQuestionCandidate(
  reference: QuestionnaireMetricQuestionReference(
    questionnaireVersionId: versionId,
    questionId: questionId,
  ),
  versionNumber: versionNumber,
  comparison: QuestionnaireMetricQuestionComparison(
    prompt: prompt,
    questionType: 'single_choice',
    options: const [
      QuestionnaireMetricOptionComparison(id: 'low', label: '较低', position: 1),
      QuestionnaireMetricOptionComparison(id: 'high', label: '较高', position: 2),
    ],
    timeScope: 'all_recorded_contacts',
    required: true,
    allowUnknown: true,
    allowRefused: true,
    allowNotApplicable: false,
  ),
  sampleCount: sampleCount,
  trendSeries: [
    QuestionnaireMetricQuestionTrendPoint(
      periodStart: '2026-07-01',
      sampleCount: sampleCount,
    ),
  ],
);

final class _Ids implements IdGenerator {
  var _value = 0;

  @override
  String next() =>
      '00000000-0000-4000-8000-${(++_value).toString().padLeft(12, '0')}';
}
