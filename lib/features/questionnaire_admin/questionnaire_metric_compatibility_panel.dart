import 'dart:async';

import 'package:flutter/material.dart';

import '../../foundation/runtime_values.dart';
import '../../l10n/app_strings.dart';
import '../../questionnaires/questionnaire_administration.dart';
import '../../questionnaires/questionnaire_metric_compatibility.dart';

final class QuestionnaireMetricCompatibilityPanel extends StatefulWidget {
  const QuestionnaireMetricCompatibilityPanel({
    super.key,
    required this.text,
    required this.gateway,
    required this.idGenerator,
  });

  final AppStrings text;
  final QuestionnaireMetricCompatibilityGateway gateway;
  final IdGenerator idGenerator;

  @override
  State<QuestionnaireMetricCompatibilityPanel> createState() =>
      _QuestionnaireMetricCompatibilityPanelState();
}

final class _QuestionnaireMetricCompatibilityPanelState
    extends State<QuestionnaireMetricCompatibilityPanel> {
  QuestionnaireMetricCompatibilitySnapshot? _snapshot;
  QuestionnaireAdministrationFailureCode? _failure;
  var _busy = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 40),
        Text(
          text.t('questionnaireMetrics'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(text.t('questionnaireMetricsHelp')),
        const SizedBox(height: 12),
        if (_busy)
          const Center(child: CircularProgressIndicator())
        else if (_snapshot == null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.cloud_off_outlined),
              title: Text(text.t('questionnaireMetricsLoadFailed')),
              trailing: IconButton(
                onPressed: _load,
                icon: const Icon(Icons.refresh_outlined),
              ),
            ),
          )
        else ...[
          if (_snapshot!.metrics.isEmpty)
            Text(text.t('questionnaireMetricsEmpty')),
          for (final metric in _snapshot!.metrics)
            Card(
              key: ValueKey('questionnaire-metric-${metric.id}'),
              child: ListTile(
                leading: const Icon(Icons.query_stats_outlined),
                title: Text(metric.label),
                subtitle: Text(
                  '${_operationLabel(text, metric.analysisOperation)} · '
                  '${metric.activeMembers.length} '
                  '${text.t('questionnaireMetricVersions')}',
                ),
              ),
            ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const ValueKey('audit-questionnaire-metric'),
            onPressed: _snapshot!.availableQuestions.length < 2 || _busy
                ? null
                : _openDecision,
            icon: const Icon(Icons.fact_check_outlined),
            label: Text(text.t('questionnaireMetricAudit')),
          ),
          if (_snapshot!.events.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              text.t('questionnaireMetricAuditHistory'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            for (final event in _snapshot!.events) _eventCard(text, event),
          ],
        ],
        if (_failure != null && _snapshot != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              text.t('questionnaireMetricOperationFailed'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }

  Widget _eventCard(
    AppStrings text,
    QuestionnaireMetricCompatibilityEvent event,
  ) {
    final revoked = _snapshot!.events.any(
      (candidate) => candidate.targetEventId == event.id,
    );
    final canRevoke =
        event.action == QuestionnaireMetricCompatibilityAction.decided &&
        event.decision == QuestionnaireMetricDecision.compatible &&
        !revoked;
    return Card(
      key: ValueKey('questionnaire-metric-event-${event.id}'),
      child: ListTile(
        leading: Icon(
          event.action == QuestionnaireMetricCompatibilityAction.revoked
              ? Icons.link_off_outlined
              : event.decision == QuestionnaireMetricDecision.compatible
              ? Icons.link_outlined
              : Icons.call_split_outlined,
        ),
        title: Text(
          event.action == QuestionnaireMetricCompatibilityAction.revoked
              ? text.t('questionnaireMetricRevoked')
              : event.decision == QuestionnaireMetricDecision.compatible
              ? text.t('questionnaireMetricCompatible')
              : text.t('questionnaireMetricIncompatible'),
        ),
        subtitle: Text(
          '${event.reference.questionId} → ${event.candidate.questionId}\n'
          '${event.reason}\n'
          '${text.t('questionnaireMetricSamples')}: '
          '${event.impact.referenceSampleCount} + '
          '${event.impact.candidateSampleCount}',
        ),
        isThreeLine: true,
        trailing: canRevoke
            ? TextButton(
                onPressed: _busy ? null : () => _revoke(event),
                child: Text(text.t('questionnaireMetricRevoke')),
              )
            : null,
      ),
    );
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    final result = await widget.gateway.loadMetricCompatibility();
    if (!mounted) return;
    switch (result) {
      case QuestionnaireAdministrationSuccess(:final value):
        setState(() {
          _snapshot = value;
          _busy = false;
        });
      case QuestionnaireAdministrationRejected(:final code):
        setState(() {
          _failure = code;
          _busy = false;
        });
    }
  }

  Future<void> _openDecision() async {
    final input = await showDialog<_MetricDecisionInput>(
      context: context,
      builder: (context) =>
          _MetricDecisionDialog(text: widget.text, snapshot: _snapshot!),
    );
    if (input == null || !mounted) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    final result = await widget.gateway.recordMetricCompatibility(
      metricId: input.metric?.id ?? widget.idGenerator.next(),
      metricLabel: input.metric?.label ?? input.metricLabel,
      analysisOperation:
          input.metric?.analysisOperation ?? input.analysisOperation,
      reference: input.reference.reference,
      candidate: input.candidate.reference,
      decision: input.decision,
      reason: input.reason,
      requestId: widget.idGenerator.next(),
    );
    if (!mounted) return;
    if (result case QuestionnaireAdministrationRejected(:final code)) {
      setState(() {
        _failure = code;
        _busy = false;
      });
      return;
    }
    await _load();
  }

  Future<void> _revoke(QuestionnaireMetricCompatibilityEvent event) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => _MetricRevocationDialog(text: widget.text),
    );
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    final result = await widget.gateway.revokeMetricCompatibility(
      eventId: event.id,
      reason: reason,
      requestId: widget.idGenerator.next(),
    );
    if (!mounted) return;
    if (result case QuestionnaireAdministrationRejected(:final code)) {
      setState(() {
        _failure = code;
        _busy = false;
      });
      return;
    }
    await _load();
  }
}

final class _MetricRevocationDialog extends StatefulWidget {
  const _MetricRevocationDialog({required this.text});

  final AppStrings text;

  @override
  State<_MetricRevocationDialog> createState() =>
      _MetricRevocationDialogState();
}

final class _MetricRevocationDialogState
    extends State<_MetricRevocationDialog> {
  final _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.text.t('questionnaireMetricRevoke')),
    content: TextField(
      key: const ValueKey('questionnaire-metric-revoke-reason'),
      controller: _reasonController,
      maxLength: 1000,
      maxLines: 3,
      decoration: InputDecoration(
        labelText: widget.text.t('questionnaireMetricReason'),
      ),
      onChanged: (_) => setState(() {}),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(widget.text.t('cancel')),
      ),
      FilledButton(
        key: const ValueKey('confirm-questionnaire-metric-revocation'),
        onPressed: _reasonController.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, _reasonController.text.trim()),
        child: Text(widget.text.t('confirm')),
      ),
    ],
  );
}

final class _MetricDecisionDialog extends StatefulWidget {
  const _MetricDecisionDialog({required this.text, required this.snapshot});

  final AppStrings text;
  final QuestionnaireMetricCompatibilitySnapshot snapshot;

  @override
  State<_MetricDecisionDialog> createState() => _MetricDecisionDialogState();
}

final class _MetricDecisionDialogState extends State<_MetricDecisionDialog> {
  static const _newMetric = '__new_metric__';
  late String _metricChoice;
  QuestionnaireMetricQuestionCandidate? _reference;
  QuestionnaireMetricQuestionCandidate? _candidate;
  QuestionnaireMetricAnalysisOperation _operation =
      QuestionnaireMetricAnalysisOperation.distribution;
  QuestionnaireMetricDecision _decision =
      QuestionnaireMetricDecision.compatible;
  final _labelController = TextEditingController();
  final _reasonController = TextEditingController();

  QuestionnaireMetricDefinition? get _metric => _metricChoice == _newMetric
      ? null
      : widget.snapshot.metrics.firstWhere(
          (metric) => metric.id == _metricChoice,
        );

  @override
  void initState() {
    super.initState();
    _metricChoice = widget.snapshot.metrics.isEmpty
        ? _newMetric
        : widget.snapshot.metrics.first.id;
    _resetQuestions();
  }

  @override
  void dispose() {
    _labelController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    final references = _referenceCandidates;
    final candidates = _candidateCandidates;
    return AlertDialog(
      title: Text(text.t('questionnaireMetricAudit')),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                key: const ValueKey('questionnaire-metric-choice'),
                initialValue: _metricChoice,
                decoration: InputDecoration(
                  labelText: text.t('questionnaireMetricStableId'),
                ),
                items: [
                  DropdownMenuItem(
                    value: _newMetric,
                    child: Text(text.t('questionnaireMetricNew')),
                  ),
                  for (final metric in widget.snapshot.metrics)
                    DropdownMenuItem(
                      value: metric.id,
                      child: Text(metric.label),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _metricChoice = value;
                    _resetQuestions();
                  });
                },
              ),
              if (_metric == null) ...[
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('questionnaire-metric-label'),
                  controller: _labelController,
                  maxLength: 200,
                  decoration: InputDecoration(
                    labelText: text.t('questionnaireMetricLabel'),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                DropdownButtonFormField<QuestionnaireMetricAnalysisOperation>(
                  key: const ValueKey('questionnaire-metric-operation'),
                  initialValue: _operation,
                  decoration: InputDecoration(
                    labelText: text.t('questionnaireMetricOperation'),
                  ),
                  items: [
                    for (final operation
                        in QuestionnaireMetricAnalysisOperation.values)
                      DropdownMenuItem(
                        value: operation,
                        child: Text(_operationLabel(text, operation)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _operation = value);
                  },
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<QuestionnaireMetricQuestionCandidate>(
                key: const ValueKey('questionnaire-metric-reference'),
                initialValue: references.contains(_reference)
                    ? _reference
                    : null,
                decoration: InputDecoration(
                  labelText: text.t('questionnaireMetricReference'),
                ),
                items: [
                  for (final question in references)
                    DropdownMenuItem(
                      value: question,
                      child: Text(_questionLabel(text, question)),
                    ),
                ],
                onChanged: (value) => setState(() {
                  _reference = value;
                  if (!_candidateCandidates.contains(_candidate)) {
                    _candidate = _candidateCandidates.firstOrNull;
                  }
                }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<QuestionnaireMetricQuestionCandidate>(
                key: const ValueKey('questionnaire-metric-candidate'),
                initialValue: candidates.contains(_candidate)
                    ? _candidate
                    : null,
                decoration: InputDecoration(
                  labelText: text.t('questionnaireMetricCandidate'),
                ),
                items: [
                  for (final question in candidates)
                    DropdownMenuItem(
                      value: question,
                      child: Text(_questionLabel(text, question)),
                    ),
                ],
                onChanged: (value) => setState(() => _candidate = value),
              ),
              if (_reference != null && _candidate != null) ...[
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) => constraints.maxWidth < 600
                      ? Column(
                          children: [
                            _comparisonCard(text, _reference!),
                            _comparisonCard(text, _candidate!),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _comparisonCard(text, _reference!)),
                            Expanded(child: _comparisonCard(text, _candidate!)),
                          ],
                        ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${text.t('questionnaireMetricImpact')}: '
                  '${_reference!.sampleCount} + ${_candidate!.sampleCount} = '
                  '${_reference!.sampleCount + _candidate!.sampleCount}',
                ),
                if (_trendPreview(_reference!, _candidate!).isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(text.t('questionnaireMetricTrendImpact')),
                  for (final point in _trendPreview(_reference!, _candidate!))
                    Text(
                      '${point.periodStart}: ${point.referenceSampleCount} + '
                      '${point.candidateSampleCount} = '
                      '${point.referenceSampleCount + point.candidateSampleCount}',
                    ),
                ],
              ],
              const SizedBox(height: 12),
              SegmentedButton<QuestionnaireMetricDecision>(
                key: const ValueKey('questionnaire-metric-decision'),
                segments: [
                  ButtonSegment(
                    value: QuestionnaireMetricDecision.compatible,
                    label: Text(text.t('questionnaireMetricCompatible')),
                  ),
                  ButtonSegment(
                    value: QuestionnaireMetricDecision.incompatible,
                    label: Text(text.t('questionnaireMetricIncompatible')),
                  ),
                ],
                selected: {_decision},
                onSelectionChanged: (values) =>
                    setState(() => _decision = values.single),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('questionnaire-metric-reason'),
                controller: _reasonController,
                maxLength: 1000,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: text.t('questionnaireMetricReason'),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(text.t('cancel')),
        ),
        FilledButton(
          key: const ValueKey('confirm-questionnaire-metric-decision'),
          onPressed: _canSubmit
              ? () => Navigator.pop(
                  context,
                  _MetricDecisionInput(
                    metric: _metric,
                    metricLabel: _labelController.text.trim(),
                    analysisOperation: _operation,
                    reference: _reference!,
                    candidate: _candidate!,
                    decision: _decision,
                    reason: _reasonController.text.trim(),
                  ),
                )
              : null,
          child: Text(text.t('confirm')),
        ),
      ],
    );
  }

  List<QuestionnaireMetricQuestionCandidate> get _referenceCandidates {
    final metric = _metric;
    if (metric == null) {
      final active = {
        for (final existing in widget.snapshot.metrics)
          ...existing.activeMembers,
      };
      return [
        for (final question in widget.snapshot.availableQuestions)
          if (!active.contains(question.reference)) question,
      ];
    }
    return [
      for (final question in widget.snapshot.availableQuestions)
        if (metric.activeMembers.contains(question.reference)) question,
    ];
  }

  List<QuestionnaireMetricQuestionCandidate> get _candidateCandidates {
    final active = {
      for (final metric in widget.snapshot.metrics) ...metric.activeMembers,
    };
    return [
      for (final question in widget.snapshot.availableQuestions)
        if (question.reference.questionnaireVersionId !=
                _reference?.reference.questionnaireVersionId &&
            !active.contains(question.reference))
          question,
    ];
  }

  bool get _canSubmit =>
      _reference != null &&
      _candidate != null &&
      (_metric != null || _labelController.text.trim().isNotEmpty) &&
      _reasonController.text.trim().isNotEmpty;

  void _resetQuestions() {
    _reference = _referenceCandidates.firstOrNull;
    _candidate = _candidateCandidates.firstOrNull;
    final metric = _metric;
    if (metric != null) _operation = metric.analysisOperation;
  }
}

final class _MetricDecisionInput {
  const _MetricDecisionInput({
    required this.metric,
    required this.metricLabel,
    required this.analysisOperation,
    required this.reference,
    required this.candidate,
    required this.decision,
    required this.reason,
  });

  final QuestionnaireMetricDefinition? metric;
  final String metricLabel;
  final QuestionnaireMetricAnalysisOperation analysisOperation;
  final QuestionnaireMetricQuestionCandidate reference;
  final QuestionnaireMetricQuestionCandidate candidate;
  final QuestionnaireMetricDecision decision;
  final String reason;
}

Widget _comparisonCard(
  AppStrings text,
  QuestionnaireMetricQuestionCandidate question,
) {
  final comparison = question.comparison;
  final options = comparison.options.isEmpty
      ? text.t('questionnaireMetricNoOptions')
      : comparison.options
            .map(
              (option) => '${option.position}. ${option.id}: ${option.label}',
            )
            .join(' · ');
  final states = [
    comparison.required
        ? text.t('questionnaireRequired')
        : text.t('questionnaireOptional'),
    if (comparison.allowUnknown) text.t('questionnaireAnswerUnknown'),
    if (comparison.allowRefused) text.t('questionnaireAnswerRefused'),
    if (comparison.allowNotApplicable)
      text.t('questionnaireAnswerNotApplicable'),
  ].join(' · ');
  final constraints = [
    if (comparison.minimumSelections != null ||
        comparison.maximumSelections != null)
      '${text.t('questionnaireMetricSelectionRange')}: '
          '${comparison.minimumSelections ?? 0}–'
          '${comparison.maximumSelections ?? '∞'}',
    if (comparison.numberKind != null)
      '${text.t('questionnaireNumberKind')}: ${comparison.numberKind}',
    if (comparison.unit != null)
      '${text.t('questionnaireUnit')}: ${comparison.unit}',
    if (comparison.minimum != null || comparison.maximum != null)
      '${text.t('questionnaireMetricValueRange')}: '
          '${comparison.minimum ?? '−∞'}–${comparison.maximum ?? '∞'}',
    if (comparison.maximumLength != null)
      '${text.t('questionnaireMaximumLength')}: ${comparison.maximumLength}',
  ];
  return Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _questionLabel(text, question),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(comparison.prompt),
          Text(
            '${text.t('questionnaireQuestionType')}: ${comparison.questionType}',
          ),
          Text('${text.t('questionnaireOptions')}: $options'),
          Text(
            '${text.t('questionnaireMetricTimeScope')}: ${comparison.timeScope}',
          ),
          Text('${text.t('questionnaireMetricAnswerMode')}: $states'),
          for (final constraint in constraints) Text(constraint),
          if (comparison.displayRuleJson != null)
            Text(
              '${text.t('questionnaireDisplayRule')}: '
              '${comparison.displayRuleJson}',
            ),
          Text(
            '${text.t('questionnaireMetricSamples')}: ${question.sampleCount}',
          ),
        ],
      ),
    ),
  );
}

String _questionLabel(
  AppStrings text,
  QuestionnaireMetricQuestionCandidate question,
) =>
    '${text.t('questionnaireVersion')} ${question.versionNumber} · '
    '${question.reference.questionId}';

String _operationLabel(
  AppStrings text,
  QuestionnaireMetricAnalysisOperation operation,
) => switch (operation) {
  QuestionnaireMetricAnalysisOperation.count => text.t(
    'questionnaireMetricOperationCount',
  ),
  QuestionnaireMetricAnalysisOperation.distribution => text.t(
    'questionnaireMetricOperationDistribution',
  ),
  QuestionnaireMetricAnalysisOperation.proportion => text.t(
    'questionnaireMetricOperationProportion',
  ),
};

List<({String periodStart, int referenceSampleCount, int candidateSampleCount})>
_trendPreview(
  QuestionnaireMetricQuestionCandidate reference,
  QuestionnaireMetricQuestionCandidate candidate,
) {
  final referenceByPeriod = {
    for (final point in reference.trendSeries)
      point.periodStart: point.sampleCount,
  };
  final candidateByPeriod = {
    for (final point in candidate.trendSeries)
      point.periodStart: point.sampleCount,
  };
  final periods = {
    ...referenceByPeriod.keys,
    ...candidateByPeriod.keys,
  }.toList()..sort();
  return [
    for (final period in periods)
      (
        periodStart: period,
        referenceSampleCount: referenceByPeriod[period] ?? 0,
        candidateSampleCount: candidateByPeriod[period] ?? 0,
      ),
  ];
}
