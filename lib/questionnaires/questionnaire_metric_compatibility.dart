import 'questionnaire_administration.dart';

enum QuestionnaireMetricAnalysisOperation {
  count('count'),
  distribution('distribution'),
  proportion('proportion');

  const QuestionnaireMetricAnalysisOperation(this.storageValue);

  final String storageValue;
}

enum QuestionnaireMetricDecision {
  compatible('compatible'),
  incompatible('incompatible');

  const QuestionnaireMetricDecision(this.storageValue);

  final String storageValue;
}

enum QuestionnaireMetricCompatibilityAction { decided, revoked }

final class QuestionnaireMetricQuestionReference {
  const QuestionnaireMetricQuestionReference({
    required this.questionnaireVersionId,
    required this.questionId,
  });

  final String questionnaireVersionId;
  final String questionId;

  @override
  bool operator ==(Object other) =>
      other is QuestionnaireMetricQuestionReference &&
      questionnaireVersionId == other.questionnaireVersionId &&
      questionId == other.questionId;

  @override
  int get hashCode => Object.hash(questionnaireVersionId, questionId);
}

final class QuestionnaireMetricOptionComparison {
  const QuestionnaireMetricOptionComparison({
    required this.id,
    required this.label,
    this.position = 1,
  });

  final String id;
  final String label;
  final int position;
}

final class QuestionnaireMetricQuestionComparison {
  QuestionnaireMetricQuestionComparison({
    required this.prompt,
    required this.questionType,
    required Iterable<QuestionnaireMetricOptionComparison> options,
    required this.timeScope,
    required this.required,
    required this.allowUnknown,
    required this.allowRefused,
    required this.allowNotApplicable,
    this.minimumSelections,
    this.maximumSelections,
    this.numberKind,
    this.unit,
    this.minimum,
    this.maximum,
    this.maximumLength,
    this.displayRuleJson,
  }) : options = List.unmodifiable(options);

  final String prompt;
  final String questionType;
  final List<QuestionnaireMetricOptionComparison> options;
  final String timeScope;
  final bool required;
  final bool allowUnknown;
  final bool allowRefused;
  final bool allowNotApplicable;
  final int? minimumSelections;
  final int? maximumSelections;
  final String? numberKind;
  final String? unit;
  final num? minimum;
  final num? maximum;
  final int? maximumLength;
  final String? displayRuleJson;
}

final class QuestionnaireMetricQuestionCandidate {
  QuestionnaireMetricQuestionCandidate({
    required this.reference,
    required this.versionNumber,
    required this.comparison,
    required this.sampleCount,
    Iterable<QuestionnaireMetricQuestionTrendPoint> trendSeries = const [],
  }) : trendSeries = List.unmodifiable(trendSeries);

  final QuestionnaireMetricQuestionReference reference;
  final int versionNumber;
  final QuestionnaireMetricQuestionComparison comparison;
  final int sampleCount;
  final List<QuestionnaireMetricQuestionTrendPoint> trendSeries;
}

final class QuestionnaireMetricQuestionTrendPoint {
  const QuestionnaireMetricQuestionTrendPoint({
    required this.periodStart,
    required this.sampleCount,
  });

  final String periodStart;
  final int sampleCount;
}

final class QuestionnaireMetricDefinition {
  QuestionnaireMetricDefinition({
    required this.id,
    required this.label,
    required this.analysisOperation,
    required Iterable<QuestionnaireMetricQuestionReference> activeMembers,
  }) : activeMembers = List.unmodifiable(activeMembers);

  final String id;
  final String label;
  final QuestionnaireMetricAnalysisOperation analysisOperation;
  final List<QuestionnaireMetricQuestionReference> activeMembers;
}

final class QuestionnaireMetricImpactSeries {
  const QuestionnaireMetricImpactSeries({
    required this.questionnaireVersionId,
    required this.sampleCount,
  });

  final String questionnaireVersionId;
  final int sampleCount;
}

final class QuestionnaireMetricImpactSnapshot {
  QuestionnaireMetricImpactSnapshot({
    required this.referenceSampleCount,
    required this.candidateSampleCount,
    required this.combinedSampleCount,
    required Iterable<QuestionnaireMetricImpactSeries> separateSeries,
    Iterable<QuestionnaireMetricImpactTrendPoint> trendSeries = const [],
  }) : separateSeries = List.unmodifiable(separateSeries),
       trendSeries = List.unmodifiable(trendSeries);

  final int referenceSampleCount;
  final int candidateSampleCount;
  final int combinedSampleCount;
  final List<QuestionnaireMetricImpactSeries> separateSeries;
  final List<QuestionnaireMetricImpactTrendPoint> trendSeries;
}

final class QuestionnaireMetricImpactTrendPoint {
  const QuestionnaireMetricImpactTrendPoint({
    required this.periodStart,
    required this.referenceSampleCount,
    required this.candidateSampleCount,
    required this.combinedSampleCount,
  });

  final String periodStart;
  final int referenceSampleCount;
  final int candidateSampleCount;
  final int combinedSampleCount;
}

final class QuestionnaireMetricCompatibilityEvent {
  const QuestionnaireMetricCompatibilityEvent({
    required this.id,
    required this.metricId,
    required this.action,
    required this.decision,
    required this.targetEventId,
    required this.reference,
    required this.candidate,
    required this.actorAppUserId,
    required this.reason,
    required this.impact,
    required this.createdAtUtc,
  });

  final String id;
  final String metricId;
  final QuestionnaireMetricCompatibilityAction action;
  final QuestionnaireMetricDecision decision;
  final String? targetEventId;
  final QuestionnaireMetricQuestionReference reference;
  final QuestionnaireMetricQuestionReference candidate;
  final String actorAppUserId;
  final String reason;
  final QuestionnaireMetricImpactSnapshot impact;
  final DateTime createdAtUtc;
}

final class QuestionnaireMetricCompatibilitySnapshot {
  QuestionnaireMetricCompatibilitySnapshot({
    required Iterable<QuestionnaireMetricDefinition> metrics,
    required Iterable<QuestionnaireMetricQuestionCandidate> availableQuestions,
    required Iterable<QuestionnaireMetricCompatibilityEvent> events,
  }) : metrics = List.unmodifiable(metrics),
       availableQuestions = List.unmodifiable(availableQuestions),
       events = List.unmodifiable(events);

  final List<QuestionnaireMetricDefinition> metrics;
  final List<QuestionnaireMetricQuestionCandidate> availableQuestions;
  final List<QuestionnaireMetricCompatibilityEvent> events;

  List<QuestionnaireMetricActiveMapping> activeMappings({
    required String sourceVersionId,
    required String targetVersionId,
  }) {
    final revokedEventIds = {
      for (final event in events)
        if (event.action == QuestionnaireMetricCompatibilityAction.revoked)
          ?event.targetEventId,
    };
    final mappings = <QuestionnaireMetricActiveMapping>[];
    for (final metric in metrics) {
      QuestionnaireMetricQuestionReference? source;
      QuestionnaireMetricQuestionReference? target;
      for (final member in metric.activeMembers) {
        if (member.questionnaireVersionId == sourceVersionId) source = member;
        if (member.questionnaireVersionId == targetVersionId) target = member;
      }
      if (source == null || target == null) continue;

      QuestionnaireMetricCompatibilityEvent? evidence;
      for (final event in events) {
        if (event.metricId == metric.id &&
            event.action == QuestionnaireMetricCompatibilityAction.decided &&
            event.decision == QuestionnaireMetricDecision.compatible &&
            !revokedEventIds.contains(event.id) &&
            ((event.reference == source && event.candidate == target) ||
                (event.reference == target && event.candidate == source))) {
          evidence = event;
          break;
        }
      }
      if (evidence == null) continue;
      mappings.add(
        QuestionnaireMetricActiveMapping(
          decisionId: evidence.id,
          source: source,
          target: target,
        ),
      );
    }
    return List.unmodifiable(mappings);
  }
}

final class QuestionnaireMetricActiveMapping {
  const QuestionnaireMetricActiveMapping({
    required this.decisionId,
    required this.source,
    required this.target,
  });

  final String decisionId;
  final QuestionnaireMetricQuestionReference source;
  final QuestionnaireMetricQuestionReference target;
}

abstract interface class QuestionnaireMetricCompatibilityGateway {
  Future<
    QuestionnaireAdministrationResult<QuestionnaireMetricCompatibilitySnapshot>
  >
  loadMetricCompatibility();

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
  });

  Future<
    QuestionnaireAdministrationResult<QuestionnaireMetricCompatibilityEvent>
  >
  revokeMetricCompatibility({
    required String eventId,
    required String reason,
    required String requestId,
  });
}
