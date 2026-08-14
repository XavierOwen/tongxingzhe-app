import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import 'relationship_stage_change_summary.dart';

/// 个人分析页中的远端阶段变更历史汇总。
///
/// 结果只保留在当前页面生命周期。项目、期间或刷新 revision 变化时，
/// generation guard 会丢弃旧 scope 的迟到响应。
final class RelationshipStageChangeSummaryPanel extends StatefulWidget {
  const RelationshipStageChangeSummaryPanel({
    super.key,
    required this.text,
    required this.gateway,
    required this.projectId,
    required this.fromUtc,
    required this.untilUtc,
    required this.refreshRevision,
  });

  final AppStrings text;
  final PersonalRelationshipStageChangeSummaryGateway gateway;
  final String projectId;
  final DateTime fromUtc;
  final DateTime untilUtc;
  final int refreshRevision;

  @override
  State<RelationshipStageChangeSummaryPanel> createState() =>
      _RelationshipStageChangeSummaryPanelState();
}

final class _RelationshipStageChangeSummaryPanelState
    extends State<RelationshipStageChangeSummaryPanel>
    with AutomaticKeepAliveClientMixin {
  PersonalRelationshipStageChangeSummary? _summary;
  PersonalRelationshipStageChangeSummaryFailureCode? _failure;
  final _retryFocusNode = FocusNode();
  var _isLoading = true;
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(
    covariant RelationshipStageChangeSummaryPanel oldWidget,
  ) {
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
    _retryFocusNode.dispose();
    super.dispose();
  }

  Future<void> _load({bool restoreRetryFocus = false}) async {
    final shouldRestoreRetryFocus =
        restoreRetryFocus || _retryFocusNode.hasFocus;
    final generation = ++_generation;
    if (mounted) {
      setState(() {
        _isLoading = true;
        _summary = null;
        _failure = null;
      });
    }
    PersonalRelationshipStageChangeSummaryGatewayResult outcome;
    try {
      outcome = await widget.gateway.load(
        projectId: widget.projectId,
        fromUtc: widget.fromUtc,
        untilUtc: widget.untilUtc,
      );
    } catch (_) {
      outcome = const PersonalRelationshipStageChangeSummaryGatewayRejected(
        PersonalRelationshipStageChangeSummaryFailureCode.serviceUnavailable,
      );
    }
    if (!mounted || generation != _generation) return;
    setState(() {
      _isLoading = false;
      switch (outcome) {
        case PersonalRelationshipStageChangeSummaryGatewaySuccess(:final value):
          _summary = value;
        case PersonalRelationshipStageChangeSummaryGatewayRejected(:final code):
          _failure = code;
      }
    });
    if (shouldRestoreRetryFocus && _failure != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _retryFocusNode.requestFocus();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Card(
      key: const ValueKey('relationship-stage-change-summary-panel'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                widget.text.t('relationshipStageChangeTitle'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 8),
            Text(widget.text.t('relationshipStageChangeHelp')),
            const SizedBox(height: 12),
            Semantics(liveRegion: true, container: true, child: _body()),
          ],
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;

  Widget _body() {
    if (_isLoading) {
      return Semantics(
        label: widget.text.t('relationshipStageChangeLoading'),
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
              key: const ValueKey('relationship-stage-change-retry'),
              focusNode: _retryFocusNode,
              onPressed: () => unawaited(_load(restoreRetryFocus: true)),
              child: Text(widget.text.t('relationshipStageChangeRetry')),
            ),
          ),
        ],
      );
    }
    final summary = _summary;
    if (summary == null) {
      return Text(widget.text.t('relationshipStageChangeServiceUnavailable'));
    }
    return _ReadyRelationshipStageChangeSummary(
      text: widget.text,
      summary: summary,
    );
  }

  String _failureText(PersonalRelationshipStageChangeSummaryFailureCode code) =>
      switch (code) {
        PersonalRelationshipStageChangeSummaryFailureCode.notConfigured =>
          widget.text.t('relationshipStageChangeNotConfigured'),
        PersonalRelationshipStageChangeSummaryFailureCode.unauthorized =>
          widget.text.t('relationshipStageChangeUnauthorized'),
        PersonalRelationshipStageChangeSummaryFailureCode.invalidRequest =>
          widget.text.t('relationshipStageChangeInvalidRequest'),
        PersonalRelationshipStageChangeSummaryFailureCode.forbidden =>
          widget.text.t('relationshipStageChangeForbidden'),
        PersonalRelationshipStageChangeSummaryFailureCode.networkUnavailable =>
          widget.text.t('relationshipStageChangeNetworkUnavailable'),
        PersonalRelationshipStageChangeSummaryFailureCode.invalidResponse =>
          widget.text.t('relationshipStageChangeInvalidResponse'),
        PersonalRelationshipStageChangeSummaryFailureCode.serviceUnavailable ||
        PersonalRelationshipStageChangeSummaryFailureCode.serverRejected =>
          widget.text.t('relationshipStageChangeServiceUnavailable'),
      };
}

final class _ReadyRelationshipStageChangeSummary extends StatelessWidget {
  const _ReadyRelationshipStageChangeSummary({
    required this.text,
    required this.summary,
  });

  final AppStrings text;
  final PersonalRelationshipStageChangeSummary summary;

  @override
  Widget build(BuildContext context) {
    final rows = [
      text.format('relationshipStageChangeEventCount', {
        'count': summary.eventCount,
      }),
      text.format('relationshipStageChangeUpwardCount', {
        'count': summary.upwardCount,
      }),
      text.format('relationshipStageChangeDownwardCount', {
        'count': summary.downwardCount,
      }),
      text.format('relationshipStageChangeRelationshipCount', {
        'count': summary.distinctRelationshipCount,
      }),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in rows) ...[
          Semantics(
            container: true,
            label: row,
            excludeSemantics: true,
            child: Text(row, style: Theme.of(context).textTheme.titleSmall),
          ),
          const SizedBox(height: 6),
        ],
        const SizedBox(height: 2),
        Text(
          text.format('relationshipStageChangePeriod', {
            'from': summary.period.fromUtc.toIso8601String(),
            'until': summary.period.untilUtc.toIso8601String(),
          }),
        ),
        const SizedBox(height: 4),
        Text(
          text.format('relationshipStageChangeDataCutoff', {
            'time': summary.dataCutoffUtc.toIso8601String(),
          }),
        ),
      ],
    );
  }
}
