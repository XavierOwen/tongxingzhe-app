import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import 'metric_contract.dart';
import 'personal_interest_ratio_trend.dart';

/// 个人分析页的两期兴趣比例比较。
///
/// 该组件只显示比较合同已经验证的个人事实，不在 Widget 中重算比例或判断
/// 两期是否可比。
final class PersonalInterestRatioTrendPanel extends StatelessWidget {
  const PersonalInterestRatioTrendPanel({
    super.key,
    required this.text,
    required this.comparison,
    required this.isLoading,
    required this.loadFailed,
    required this.onRetry,
  });

  final AppStrings text;
  final PersonalInterestRatioTrendComparison? comparison;
  final bool isLoading;
  final bool loadFailed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final loaded = comparison;
    return Card(
      key: const ValueKey('personal-interest-ratio-trend-panel'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              key: const ValueKey('personal-interest-ratio-trend-heading'),
              header: true,
              label: text.t('interestTrendTitle'),
              excludeSemantics: true,
              child: Text(
                text.t('interestTrendTitle'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 8),
            Text(text.t('interestTrendHelp')),
            const SizedBox(height: 12),
            if (loaded == null && isLoading)
              Semantics(
                key: const ValueKey('personal-interest-ratio-trend-loading'),
                liveRegion: true,
                label: text.t('interestTrendLoading'),
                excludeSemantics: true,
                child: const Center(child: CircularProgressIndicator()),
              )
            else if (loaded == null)
              _TrendFailure(text: text, onRetry: onRetry)
            else
              _LoadedTrend(text: text, comparison: loaded),
            if (loaded != null && loadFailed) ...[
              const SizedBox(height: 12),
              _TrendFailure(text: text, onRetry: onRetry),
            ],
          ],
        ),
      ),
    );
  }
}

final class _LoadedTrend extends StatelessWidget {
  const _LoadedTrend({required this.text, required this.comparison});

  final AppStrings text;
  final PersonalInterestRatioTrendComparison comparison;

  @override
  Widget build(BuildContext context) {
    final previousRow = _periodRow(
      text.t('interestTrendPrevious'),
      comparison.previous,
      comparison.previousRatio.numerator,
      comparison.previousRatio.denominator,
      comparison.previousRatio.percentageBasisPoints,
    );
    final currentRow = _periodRow(
      text.t('interestTrendCurrent'),
      comparison.current,
      comparison.currentRatio.numerator,
      comparison.currentRatio.denominator,
      comparison.currentRatio.percentageBasisPoints,
    );
    final delta = comparison.deltaBasisPoints;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SemanticText(
          previousRow,
          key: const ValueKey('personal-interest-ratio-trend-previous'),
        ),
        const SizedBox(height: 8),
        _SemanticText(
          currentRow,
          key: const ValueKey('personal-interest-ratio-trend-current'),
        ),
        const SizedBox(height: 12),
        if (delta == null)
          Text(text.t('interestTrendDeltaUnavailable'))
        else
          _SemanticText(
            text.format('interestTrendDelta', {
              'delta': text.format('interestTrendDeltaValue', {
                'value': _formatSignedBasisPoints(delta),
              }),
            }),
            key: const ValueKey('personal-interest-ratio-trend-delta'),
          ),
        const SizedBox(height: 8),
        Text(text.t('interestTrendObservationNotice')),
        const SizedBox(height: 8),
        Text(
          text.format('interestTrendDataCutoff', {
            'time': comparison.current.dataCutoffUtc!.toIso8601String(),
          }),
        ),
      ],
    );
  }

  String _periodRow(
    String label,
    MetricResult metric,
    int numerator,
    int denominator,
    int? basisPoints,
  ) {
    return text.format('interestTrendPeriodRow', {
      'label': label,
      'from': metric.period.fromUtc.toIso8601String(),
      'until': metric.period.untilUtc.toIso8601String(),
      'numerator': numerator,
      'denominator': denominator,
      'percentage': _formatPercentage(text, basisPoints),
      'pending': metric.syncCoverage!.pendingCount!,
    });
  }
}

final class _TrendFailure extends StatelessWidget {
  const _TrendFailure({required this.text, required this.onRetry});

  final AppStrings text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(text.t('interestTrendUnavailable')),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonal(
            key: const ValueKey('personal-interest-ratio-trend-retry'),
            onPressed: onRetry,
            child: Text(text.t('interestTrendRetry')),
          ),
        ),
      ],
    );
  }
}

final class _SemanticText extends StatelessWidget {
  const _SemanticText(this.value, {super.key});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: value,
      excludeSemantics: true,
      child: Text(value),
    );
  }
}

String _formatPercentage(AppStrings text, int? basisPoints) {
  if (basisPoints == null) return text.t('interestRatioUnavailable');
  final whole = basisPoints ~/ 100;
  final fraction = (basisPoints % 100).toString().padLeft(2, '0');
  return '$whole.$fraction%';
}

String _formatSignedBasisPoints(int basisPoints) {
  final sign = basisPoints > 0
      ? '+'
      : basisPoints < 0
      ? '−'
      : '';
  final magnitude = basisPoints.abs();
  final whole = magnitude ~/ 100;
  final fraction = (magnitude % 100).toString().padLeft(2, '0');
  return '$sign$whole.$fraction';
}
