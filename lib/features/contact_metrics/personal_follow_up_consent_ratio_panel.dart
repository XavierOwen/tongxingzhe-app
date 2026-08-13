import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import 'metric_contract.dart';
import 'personal_follow_up_consent_ratio.dart';

/// 个人分析页中的可选后续联系同意占比。
///
/// 该组件只持有一次页面生命周期内的请求状态，不缓存指标结果。
/// 项目或期间变化会废弃迟到响应，避免把旧 scope 显示到新项目。
final class PersonalFollowUpConsentRatioPanel extends StatefulWidget {
  const PersonalFollowUpConsentRatioPanel({
    super.key,
    required this.text,
    required this.gateway,
    required this.projectId,
    required this.fromUtc,
    required this.untilUtc,
    required this.refreshRevision,
  });

  final AppStrings text;
  final PersonalFollowUpConsentRatioGateway gateway;
  final String projectId;
  final DateTime fromUtc;
  final DateTime untilUtc;
  final int refreshRevision;

  @override
  State<PersonalFollowUpConsentRatioPanel> createState() =>
      _PersonalFollowUpConsentRatioPanelState();
}

final class _PersonalFollowUpConsentRatioPanelState
    extends State<PersonalFollowUpConsentRatioPanel> {
  PersonalFollowUpConsentRatioResult? _result;
  PersonalFollowUpConsentRatioFailureCode? _failure;
  var _isLoading = true;
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant PersonalFollowUpConsentRatioPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gateway != widget.gateway ||
        oldWidget.projectId != widget.projectId ||
        oldWidget.fromUtc != widget.fromUtc ||
        oldWidget.untilUtc != widget.untilUtc ||
        oldWidget.refreshRevision != widget.refreshRevision) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    if (mounted) {
      setState(() {
        _isLoading = true;
        _result = null;
        _failure = null;
      });
    }
    PersonalFollowUpConsentRatioGatewayResult outcome;
    try {
      outcome = await widget.gateway.load(
        projectId: widget.projectId,
        fromUtc: widget.fromUtc,
        untilUtc: widget.untilUtc,
      );
    } catch (_) {
      outcome = const PersonalFollowUpConsentRatioGatewayRejected(
        PersonalFollowUpConsentRatioFailureCode.serviceUnavailable,
      );
    }
    if (!mounted || generation != _generation) return;
    setState(() {
      _isLoading = false;
      switch (outcome) {
        case PersonalFollowUpConsentRatioGatewaySuccess(:final value):
          _result = value;
        case PersonalFollowUpConsentRatioGatewayRejected(:final code):
          _failure = code;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const ValueKey('personal-follow-up-consent-ratio-panel'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                widget.text.t('personalConsentRatioTitle'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 8),
            Text(widget.text.t('personalConsentRatioHelp')),
            const SizedBox(height: 12),
            Semantics(liveRegion: true, container: true, child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_isLoading) {
      return Semantics(
        label: widget.text.t('personalConsentRatioLoading'),
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    final failure = _failure;
    if (failure != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_failureText(failure)),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonal(
              key: const ValueKey('personal-consent-ratio-retry'),
              onPressed: () => unawaited(_load()),
              child: Text(widget.text.t('personalConsentRatioRetry')),
            ),
          ),
        ],
      );
    }
    return switch (_result) {
      PersonalFollowUpConsentRatioNotEnabled() => Text(
        widget.text.t('personalConsentRatioNotEnabled'),
      ),
      PersonalFollowUpConsentRatioReady(:final metric) =>
        _ReadyPersonalFollowUpConsentRatio(text: widget.text, metric: metric),
      null => Text(widget.text.t('personalConsentRatioServiceUnavailable')),
    };
  }

  String _failureText(PersonalFollowUpConsentRatioFailureCode code) =>
      switch (code) {
        PersonalFollowUpConsentRatioFailureCode.notConfigured => widget.text.t(
          'personalConsentRatioNotConfigured',
        ),
        PersonalFollowUpConsentRatioFailureCode.unauthorized => widget.text.t(
          'personalConsentRatioUnauthorized',
        ),
        PersonalFollowUpConsentRatioFailureCode.invalidRequest => widget.text.t(
          'personalConsentRatioInvalidRequest',
        ),
        PersonalFollowUpConsentRatioFailureCode.forbidden => widget.text.t(
          'personalConsentRatioForbidden',
        ),
        PersonalFollowUpConsentRatioFailureCode.networkUnavailable =>
          widget.text.t('personalConsentRatioNetworkUnavailable'),
        PersonalFollowUpConsentRatioFailureCode.invalidResponse =>
          widget.text.t('personalConsentRatioInvalidResponse'),
        PersonalFollowUpConsentRatioFailureCode.serviceUnavailable ||
        PersonalFollowUpConsentRatioFailureCode.serverRejected => widget.text.t(
          'personalConsentRatioServiceUnavailable',
        ),
      };
}

final class _ReadyPersonalFollowUpConsentRatio extends StatelessWidget {
  const _ReadyPersonalFollowUpConsentRatio({
    required this.text,
    required this.metric,
  });

  final AppStrings text;
  final MetricResult metric;

  @override
  Widget build(BuildContext context) {
    final value = metric.value as RatioMetricValue;
    final yes = value.values.singleWhere((item) => item.label == 'yes');
    final row = text.format('personalConsentRatioRow', {
      'numerator': yes.numerator,
      'denominator': yes.denominator,
      'percentage': _formatPercentage(text, yes.percentageBasisPoints),
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          label: row,
          excludeSemantics: true,
          child: Text(row, style: Theme.of(context).textTheme.titleSmall),
        ),
        const SizedBox(height: 8),
        Text(
          text.format('personalConsentRatioCoverage', {
            'unknown': value.unknownCount,
            'refused': value.refusedCount,
            'notApplicable': value.notApplicableCount,
            'unanswered': value.unansweredCount,
            'excluded': value.excludedCount,
          }),
        ),
      ],
    );
  }
}

String _formatPercentage(AppStrings text, int? basisPoints) {
  if (basisPoints == null) return text.t('interestRatioUnavailable');
  final whole = basisPoints ~/ 100;
  final fraction = (basisPoints % 100).toString().padLeft(2, '0');
  return '$whole.$fraction%';
}
