import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/questionnaires/questionnaire_metric_compatibility.dart';

void main() {
  test('active mappings include compatible current members', () {
    final snapshot = _snapshot();

    final mappings = snapshot.activeMappings(
      sourceVersionId: 'version-1',
      targetVersionId: 'version-2',
    );

    expect(mappings, hasLength(1));
    expect(mappings.single.decisionId, 'decision-1');
    expect(mappings.single.source.questionId, 'question-1');
    expect(mappings.single.target.questionId, 'question-2');
  });

  test('active mappings exclude revoked compatibility decisions', () {
    final snapshot = _snapshot(revoked: true);

    final mappings = snapshot.activeMappings(
      sourceVersionId: 'version-1',
      targetVersionId: 'version-2',
    );

    expect(mappings, isEmpty);
  });
}

QuestionnaireMetricCompatibilitySnapshot _snapshot({bool revoked = false}) {
  const source = QuestionnaireMetricQuestionReference(
    questionnaireVersionId: 'version-1',
    questionId: 'question-1',
  );
  const target = QuestionnaireMetricQuestionReference(
    questionnaireVersionId: 'version-2',
    questionId: 'question-2',
  );
  const unrelated = QuestionnaireMetricQuestionReference(
    questionnaireVersionId: 'version-3',
    questionId: 'question-3',
  );
  final impact = QuestionnaireMetricImpactSnapshot(
    referenceSampleCount: 1,
    candidateSampleCount: 2,
    combinedSampleCount: 3,
    separateSeries: [],
  );
  final decision = QuestionnaireMetricCompatibilityEvent(
    id: 'decision-1',
    metricId: 'metric-1',
    action: QuestionnaireMetricCompatibilityAction.decided,
    decision: QuestionnaireMetricDecision.compatible,
    targetEventId: null,
    reference: source,
    candidate: target,
    actorAppUserId: 'user-1',
    reason: 'Definitions match.',
    impact: impact,
    createdAtUtc: DateTime.utc(2026),
  );
  return QuestionnaireMetricCompatibilitySnapshot(
    metrics: [
      QuestionnaireMetricDefinition(
        id: 'metric-1',
        label: 'Stable metric',
        analysisOperation: QuestionnaireMetricAnalysisOperation.count,
        activeMembers: const [source, target, unrelated],
      ),
    ],
    availableQuestions: const [],
    events: [
      QuestionnaireMetricCompatibilityEvent(
        id: 'decision-unrelated',
        metricId: 'metric-1',
        action: QuestionnaireMetricCompatibilityAction.decided,
        decision: QuestionnaireMetricDecision.compatible,
        targetEventId: null,
        reference: target,
        candidate: unrelated,
        actorAppUserId: 'user-1',
        reason: 'A later unrelated decision.',
        impact: impact,
        createdAtUtc: DateTime.utc(2026, 1, 3),
      ),
      decision,
      if (revoked)
        QuestionnaireMetricCompatibilityEvent(
          id: 'revoke-1',
          metricId: 'metric-1',
          action: QuestionnaireMetricCompatibilityAction.revoked,
          decision: QuestionnaireMetricDecision.compatible,
          targetEventId: decision.id,
          reference: source,
          candidate: target,
          actorAppUserId: 'user-1',
          reason: 'The definitions diverged.',
          impact: impact,
          createdAtUtc: DateTime.utc(2026, 1, 2),
        ),
    ],
  );
}
