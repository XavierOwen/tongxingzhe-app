import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import 'current_relationship_stage.dart';
import 'metric_contract.dart';

/// 个人分析页中的当前关系快照。它不接收或显示对象 PII。
final class CurrentRelationshipStagePanel extends StatelessWidget {
  const CurrentRelationshipStagePanel({
    super.key,
    required this.text,
    required this.result,
    required this.isLoading,
    required this.loadFailed,
  });

  final AppStrings text;
  final CurrentRelationshipStageRepositorySuccess? result;
  final bool isLoading;
  final bool loadFailed;

  @override
  Widget build(BuildContext context) {
    final loaded = result;
    return Card(
      key: const ValueKey('current-relationship-stage-panel'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                text.t('currentRelationshipStageTitle'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 8),
            Text(text.t('currentRelationshipStageHelp')),
            const SizedBox(height: 12),
            if (loaded == null && isLoading)
              Semantics(
                label: text.t('currentRelationshipStageLoading'),
                child: const Center(child: CircularProgressIndicator()),
              )
            else if (loaded == null)
              Text(text.t('currentRelationshipStageUnavailable'))
            else
              _LoadedCurrentRelationshipStage(text: text, result: loaded),
            if (loadFailed && loaded != null) ...[
              const SizedBox(height: 8),
              Text(text.t('currentRelationshipStageUnavailable')),
            ],
          ],
        ),
      ),
    );
  }
}

final class _LoadedCurrentRelationshipStage extends StatelessWidget {
  const _LoadedCurrentRelationshipStage({
    required this.text,
    required this.result,
  });

  final AppStrings text;
  final CurrentRelationshipStageRepositorySuccess result;

  @override
  Widget build(BuildContext context) {
    final snapshot = result.snapshot;
    final coverage = snapshot.coverage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_freshnessText(snapshot)),
        const SizedBox(height: 8),
        Text(
          text.format('currentRelationshipStageSnapshotAt', {
            'time': _utcText(snapshot.snapshotAsOfUtc),
          }),
        ),
        if (snapshot.sourceDataCutoffUtc case final cutoff?)
          Text(
            text.format('currentRelationshipStageSourceCutoff', {
              'time': _utcText(cutoff),
            }),
          ),
        const SizedBox(height: 12),
        for (var stage = 0; stage <= 4; stage++)
          _StageCountRow(
            label: text.format('currentRelationshipStageRow', {
              'stage': stage,
              'count': snapshot.stageCounts[stage],
            }),
            stage: stage,
            count: snapshot.stageCounts[stage],
          ),
        const SizedBox(height: 12),
        Text(
          coverage.isKnown
              ? text.format('currentRelationshipStageCoverage', {
                  'synced': coverage.synchronizedCount!,
                  'total': coverage.totalCount!,
                  'pending': coverage.pendingCount!,
                })
              : text.t('currentRelationshipStageCoverageUnknown'),
        ),
      ],
    );
  }

  String _freshnessText(CurrentRelationshipStageSnapshot snapshot) {
    if (result.fromOfflineCache ||
        snapshot.freshness.status == MetricFreshnessStatus.stale) {
      return text.t('currentRelationshipStageStale');
    }
    return switch (snapshot.freshness.status) {
      MetricFreshnessStatus.fresh => text.t('currentRelationshipStageFresh'),
      MetricFreshnessStatus.stale => text.t('currentRelationshipStageStale'),
      MetricFreshnessStatus.unknown => text.t(
        'currentRelationshipStageFreshnessUnknown',
      ),
    };
  }
}

final class _StageCountRow extends StatelessWidget {
  const _StageCountRow({
    required this.label,
    required this.stage,
    required this.count,
  });

  final String label;
  final int stage;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: label,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text('${stage.toString()} / 4')),
            const SizedBox(width: 12),
            Text(
              count.toString(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}

String _utcText(DateTime value) => value.toUtc().toIso8601String();
