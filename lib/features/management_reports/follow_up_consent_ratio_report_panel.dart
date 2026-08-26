import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_strings.dart';
import '../../management_reports/follow_up_consent_ratio_report_gateway.dart';
import 'follow_up_consent_ratio_report_panel_view_model.dart';
import 'snapshot_focus_node_cache.dart';

/// 管理项目内后续联系同意占比报告面板。
///
/// [projectId] 必须由上层已经解析并重新授权的
/// `ManagementAnalysisContext` 提供。面板只保留当前页面的 typed 结果，
/// 不提供缓存、导出或离线读取。
final class FollowUpConsentRatioReportPanel extends StatefulWidget {
  const FollowUpConsentRatioReportPanel({
    super.key,
    required this.text,
    required this.gateway,
    required this.projectId,
  });

  final AppStrings text;
  final FollowUpConsentRatioReportGateway gateway;
  final String? projectId;

  @override
  State<FollowUpConsentRatioReportPanel> createState() =>
      _FollowUpConsentRatioReportPanelState();
}

final class _FollowUpConsentRatioReportPanelState
    extends State<FollowUpConsentRatioReportPanel>
    with AutomaticKeepAliveClientMixin {
  late FollowUpConsentRatioReportPanelViewModel _viewModel;
  final _backFocusNode = FocusNode(
    debugLabel: 'follow-up consent ratio report back',
  );
  final _retryFocusNode = FocusNode(
    debugLabel: 'follow-up consent ratio report retry',
  );
  final _snapshotFocusNodes = SnapshotFocusNodeCache(
    debugLabelPrefix: 'follow-up consent ratio report',
  );
  FollowUpConsentRatioReportPanelStage? _previousStage;
  String? _returnFocusSnapshotId;

  @override
  void initState() {
    super.initState();
    _viewModel = _createViewModel();
    unawaited(_viewModel.initialize());
  }

  @override
  void didUpdateWidget(covariant FollowUpConsentRatioReportPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gateway != widget.gateway) {
      _viewModel
        ..removeListener(_stateChanged)
        ..dispose();
      _snapshotFocusNodes.clear();
      _returnFocusSnapshotId = null;
      _viewModel = _createViewModel();
      unawaited(_viewModel.initialize());
      return;
    }
    if (oldWidget.projectId != widget.projectId) {
      _returnFocusSnapshotId = null;
      unawaited(_viewModel.updateProject(widget.projectId));
    }
  }

  FollowUpConsentRatioReportPanelViewModel _createViewModel() {
    final viewModel = FollowUpConsentRatioReportPanelViewModel(
      gateway: widget.gateway,
      projectId: widget.projectId,
    );
    _previousStage = viewModel.state.stage;
    return viewModel..addListener(_stateChanged);
  }

  @override
  void dispose() {
    _viewModel
      ..removeListener(_stateChanged)
      ..dispose();
    _backFocusNode.dispose();
    _retryFocusNode.dispose();
    _snapshotFocusNodes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = _viewModel.state;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        if (_showsBackAction(state))
          const SingleActivator(LogicalKeyboardKey.escape): _showDirectory,
      },
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Card(
          key: const ValueKey('follow-up-consent-ratio-report-panel'),
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  key: const ValueKey('follow-up-consent-ratio-report-heading'),
                  header: true,
                  child: Text(
                    widget.text.t('followUpConsentRatioReportTitle'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                const SizedBox(height: 8),
                Text(widget.text.t('followUpConsentRatioReportIntro')),
                const SizedBox(height: 20),
                if (_showsBackAction(state)) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const ValueKey(
                        'follow-up-consent-ratio-report-back',
                      ),
                      focusNode: _backFocusNode,
                      onPressed: _showDirectory,
                      icon: const Icon(Icons.arrow_back),
                      label: Text(
                        widget.text.t(
                          'followUpConsentRatioReportBackToDirectory',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Semantics(
                  key: const ValueKey(
                    'follow-up-consent-ratio-report-live-region',
                  ),
                  container: true,
                  liveRegion: true,
                  child: _body(state),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(FollowUpConsentRatioReportPanelState state) {
    switch (state.stage) {
      case FollowUpConsentRatioReportPanelStage.inactive:
        return Semantics(
          key: const ValueKey('follow-up-consent-ratio-report-inactive'),
          container: true,
          child: Text(widget.text.t('followUpConsentRatioReportInactive')),
        );
      case FollowUpConsentRatioReportPanelStage.loadingDirectory:
        return _Loading(
          text: widget.text.t('followUpConsentRatioReportDirectoryLoading'),
        );
      case FollowUpConsentRatioReportPanelStage.directory:
        return _Directory(
          text: widget.text,
          snapshots: state.directory?.snapshots ?? const [],
          focusNodeFor: _snapshotFocusNode,
          onOpen: _openSnapshot,
        );
      case FollowUpConsentRatioReportPanelStage.loadingSnapshot:
        return _Loading(
          text: widget.text.t('followUpConsentRatioReportLoading'),
        );
      case FollowUpConsentRatioReportPanelStage.snapshot:
        final snapshot = state.snapshot;
        if (snapshot == null) {
          return Text(widget.text.t('followUpConsentRatioReportFailed'));
        }
        return _SnapshotDetail(text: widget.text, snapshot: snapshot);
      case FollowUpConsentRatioReportPanelStage.failure:
        return _Failure(
          text: widget.text,
          code:
              state.failureCode ??
              FollowUpConsentRatioReportFailureCode.serviceUnavailable,
          focusNode: _retryFocusNode,
          onRetry: () => unawaited(_retry()),
        );
    }
  }

  bool _showsBackAction(FollowUpConsentRatioReportPanelState state) =>
      state.selectedSummary != null &&
      (state.stage == FollowUpConsentRatioReportPanelStage.loadingSnapshot ||
          state.stage == FollowUpConsentRatioReportPanelStage.snapshot ||
          state.stage == FollowUpConsentRatioReportPanelStage.failure);

  FocusNode _snapshotFocusNode(String snapshotId) =>
      _snapshotFocusNodes.nodeFor(snapshotId);

  void _openSnapshot(FollowUpConsentRatioReportSnapshotSummary summary) {
    _returnFocusSnapshotId = summary.snapshotId;
    unawaited(_viewModel.openSnapshot(summary));
  }

  void _showDirectory() {
    final snapshotId = _returnFocusSnapshotId;
    _viewModel.returnToDirectory();
    if (snapshotId == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _snapshotFocusNodes.contains(snapshotId)) {
        _snapshotFocusNodes.nodeFor(snapshotId).requestFocus();
      }
    });
  }

  Future<void> _retry() async {
    final hadFocus = _retryFocusNode.hasFocus;
    await _viewModel.retry();
    if (!hadFocus || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          _viewModel.state.stage ==
              FollowUpConsentRatioReportPanelStage.failure) {
        _retryFocusNode.requestFocus();
      }
    });
  }

  void _stateChanged() {
    if (!mounted) return;
    final state = _viewModel.state;
    final stage = state.stage;
    switch (stage) {
      case FollowUpConsentRatioReportPanelStage.inactive:
      case FollowUpConsentRatioReportPanelStage.loadingDirectory:
        _snapshotFocusNodes.clear();
      case FollowUpConsentRatioReportPanelStage.directory:
        _snapshotFocusNodes.retain(
          state.directory?.snapshots.map((summary) => summary.snapshotId) ??
              const <String>[],
        );
      case FollowUpConsentRatioReportPanelStage.loadingSnapshot:
      case FollowUpConsentRatioReportPanelStage.snapshot:
      case FollowUpConsentRatioReportPanelStage.failure:
        break;
    }
    final shouldFocusBack =
        _previousStage ==
            FollowUpConsentRatioReportPanelStage.loadingSnapshot &&
        stage == FollowUpConsentRatioReportPanelStage.snapshot;
    final shouldFocusRetry =
        stage == FollowUpConsentRatioReportPanelStage.failure &&
        _previousStage != FollowUpConsentRatioReportPanelStage.failure;
    _previousStage = stage;
    setState(() {});
    if (shouldFocusBack) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _backFocusNode.requestFocus();
      });
    }
    if (shouldFocusRetry) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _retryFocusNode.requestFocus();
      });
    }
  }

  @override
  bool get wantKeepAlive => true;
}

final class _Loading extends StatelessWidget {
  const _Loading({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    label: text,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 8),
        Text(text, textAlign: TextAlign.center),
      ],
    ),
  );
}

final class _Directory extends StatelessWidget {
  const _Directory({
    required this.text,
    required this.snapshots,
    required this.focusNodeFor,
    required this.onOpen,
  });

  final AppStrings text;
  final List<FollowUpConsentRatioReportSnapshotSummary> snapshots;
  final FocusNode Function(String snapshotId) focusNodeFor;
  final ValueChanged<FollowUpConsentRatioReportSnapshotSummary> onOpen;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          key: const ValueKey(
            'follow-up-consent-ratio-report-directory-heading',
          ),
          header: true,
          child: Text(
            text.t('followUpConsentRatioReportDirectoryTitle'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 12),
        if (snapshots.isEmpty)
          Semantics(
            key: const ValueKey('follow-up-consent-ratio-report-empty'),
            child: Text(text.t('followUpConsentRatioReportDirectoryEmpty')),
          )
        else
          for (final summary in snapshots) ...[
            _DirectoryItem(
              text: text,
              summary: summary,
              focusNode: focusNodeFor(summary.snapshotId),
              onOpen: () => onOpen(summary),
            ),
            const SizedBox(height: 8),
          ],
      ],
    ),
  );
}

final class _DirectoryItem extends StatelessWidget {
  const _DirectoryItem({
    required this.text,
    required this.summary,
    required this.focusNode,
    required this.onOpen,
  });

  final AppStrings text;
  final FollowUpConsentRatioReportSnapshotSummary summary;
  final FocusNode focusNode;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final releasedAt = _formatUtc(summary.releasedAtUtc);
    final values = <String, Object>{
      'version': summary.reportVersion,
      'dataCutoff': _formatUtc(summary.dataCutoffUtc),
      'releasedAt': releasedAt,
      'timeZone': summary.reportingTimeZone,
    };
    final semantics = text.format(
      'followUpConsentRatioReportOpenSemantics',
      values,
    );
    final metadata = text.format(
      'followUpConsentRatioReportDirectoryMetadata',
      values,
    );
    return Semantics(
      key: ValueKey('follow-up-consent-ratio-report-${summary.snapshotId}'),
      label: semantics,
      button: true,
      excludeSemantics: true,
      onTap: onOpen,
      child: Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          focusNode: focusNode,
          minVerticalPadding: 12,
          title: Text(
            '${text.t('followUpConsentRatioReportVersion')} '
            '${summary.reportVersion}',
          ),
          subtitle: Text(metadata),
          trailing: const Icon(Icons.chevron_right),
          onTap: onOpen,
        ),
      ),
    );
  }
}

final class _Failure extends StatelessWidget {
  const _Failure({
    required this.text,
    required this.code,
    required this.focusNode,
    required this.onRetry,
  });

  final AppStrings text;
  final FollowUpConsentRatioReportFailureCode code;
  final FocusNode focusNode;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final message = _failureText(text, code);
    return Semantics(
      key: const ValueKey('follow-up-consent-ratio-report-failure'),
      container: true,
      liveRegion: true,
      label: message,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(message),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonal(
              key: const ValueKey('follow-up-consent-ratio-report-retry'),
              focusNode: focusNode,
              onPressed: onRetry,
              child: Text(text.t('followUpConsentRatioReportRetry')),
            ),
          ),
        ],
      ),
    );
  }
}

final class _SnapshotDetail extends StatelessWidget {
  const _SnapshotDetail({required this.text, required this.snapshot});

  final AppStrings text;
  final FollowUpConsentRatioReportSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final report = snapshot.report;
    final periods = report.periods;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          key: const ValueKey('follow-up-consent-ratio-report-detail-heading'),
          header: true,
          child: Text(
            '${text.t('followUpConsentRatioReportTitle')} · '
            '${text.t('followUpConsentRatioReportVersion')} '
            '${report.reportVersion}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 12),
        _MetadataSection(
          text: text,
          title: text.t('followUpConsentRatioReportDefinition'),
          rows: [
            _MetadataRow(
              text.t('followUpConsentRatioReportDefinition'),
              '${report.reportId}@${report.reportVersion}',
            ),
            _MetadataRow(
              text.t('followUpConsentRatioReportMetric'),
              '${report.metricId}@${report.metricVersion}',
            ),
            _MetadataRow(
              text.t('followUpConsentRatioReportStatisticalUnit'),
              report.statisticalUnit,
            ),
            _MetadataRow(
              text.t('followUpConsentRatioReportDimension'),
              report.dimension,
            ),
            _MetadataRow(
              text.t('followUpConsentRatioReportPeriodGrain'),
              report.periodGrain,
            ),
            _MetadataRow(
              text.t('followUpConsentRatioReportComparisonPeriodCount'),
              '${report.comparisonPeriodCount}',
            ),
            _MetadataRow(
              text.t('followUpConsentRatioReportProject'),
              report.projectId,
              breakLongValue: true,
            ),
            _MetadataRow(
              text.t('followUpConsentRatioReportQueryFingerprint'),
              report.queryFingerprint,
              key: const ValueKey(
                'follow-up-consent-ratio-report-query-fingerprint',
              ),
              breakLongValue: true,
            ),
            _MetadataRow(
              text.t('followUpConsentRatioReportSourceScope'),
              report.sourceScope,
              breakLongValue: true,
            ),
            _MetadataRow(
              text.t('followUpConsentRatioReportPrivacyRule'),
              report.privacyPolicy,
              breakLongValue: true,
            ),
            _MetadataRow(
              text.t('followUpConsentRatioReportStatus'),
              report.resultStatus,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _MetadataSection(
          text: text,
          headingKey: const ValueKey(
            'follow-up-consent-ratio-report-period-heading',
          ),
          title: text.t('followUpConsentRatioReportPeriodBoundary'),
          rows: [
            _MetadataRow(
              text.t('followUpConsentRatioReportPeriodBoundary'),
              periods.periodBoundaryId,
            ),
            _MetadataRow(
              text.t('followUpConsentRatioReportTimeZone'),
              periods.reportingTimeZone,
            ),
            _MetadataRow(
              text.t('followUpConsentRatioReportDataCutoff'),
              _formatUtc(periods.dataCutoffUtc),
            ),
            _MetadataRow(
              text.t('followUpConsentRatioReportReleasedAt'),
              _formatUtc(snapshot.summary.releasedAtUtc),
            ),
            _MetadataRow(
              text.t('followUpConsentRatioReportPreviousPeriod'),
              _periodText(text, periods.previousPeriod, previous: true),
            ),
            _MetadataRow(
              text.t('followUpConsentRatioReportCurrentPeriod'),
              _periodText(text, periods.currentPeriod, previous: false),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _PeriodResultsSection(text: text, report: report),
      ],
    );
  }
}

final class _MetadataSection extends StatelessWidget {
  const _MetadataSection({
    required this.text,
    this.headingKey,
    required this.title,
    required this.rows,
  });

  final AppStrings text;
  final Key? headingKey;
  final String title;
  final List<_MetadataRow> rows;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        key: headingKey,
        header: true,
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
      const SizedBox(height: 8),
      for (final row in rows) _MetadataLine(text: text, row: row),
    ],
  );
}

final class _MetadataRow {
  const _MetadataRow(
    this.label,
    this.value, {
    this.key,
    this.breakLongValue = false,
  });

  final String label;
  final String value;
  final Key? key;
  final bool breakLongValue;
}

final class _MetadataLine extends StatelessWidget {
  const _MetadataLine({required this.text, required this.row});

  final AppStrings text;
  final _MetadataRow row;

  @override
  Widget build(BuildContext context) {
    final visibleValue = row.breakLongValue
        ? _insertBreaks(row.value)
        : row.value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        key: row.key,
        container: true,
        label: text.format('followUpConsentRatioReportMetadataSemantics', {
          'label': row.label,
          'value': row.value,
        }),
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(row.label, style: Theme.of(context).textTheme.labelLarge),
            Text(visibleValue),
          ],
        ),
      ),
    );
  }
}

final class _PeriodResultsSection extends StatelessWidget {
  const _PeriodResultsSection({required this.text, required this.report});

  final AppStrings text;
  final FollowUpConsentRatioReportDocument report;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        key: const ValueKey('follow-up-consent-ratio-report-ratio-heading'),
        header: true,
        child: Text(
          text.t('followUpConsentRatioReportRatioTitle'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      const SizedBox(height: 8),
      for (final result in report.periodResults) ...[
        _RatioRow(text: text, result: result),
        const SizedBox(height: 12),
      ],
      Semantics(
        key: const ValueKey('follow-up-consent-ratio-report-coverage-heading'),
        header: true,
        child: Text(
          text.t('followUpConsentRatioReportCoverageTitle'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      const SizedBox(height: 8),
      for (final result in report.periodResults) ...[
        _CoveragePeriod(text: text, result: result),
        const SizedBox(height: 12),
      ],
    ],
  );
}

final class _RatioRow extends StatelessWidget {
  const _RatioRow({required this.text, required this.result});

  final AppStrings text;
  final FollowUpConsentRatioReportPeriodResult result;

  @override
  Widget build(BuildContext context) {
    final period = _periodLabel(text, result.periodKey);
    final ratio = result.ratio;
    final value = switch ((
      ratio.privacyStatus,
      ratio.numerator,
      ratio.denominator,
      ratio.percentageBasisPoints,
      ratio.yesCount,
      ratio.noCount,
    )) {
      (
        FollowUpConsentRatioReportPrivacyStatus.displayed,
        final int numerator,
        final int denominator,
        final int basisPoints,
        final int yesCount,
        final int noCount,
      ) =>
        text.format('followUpConsentRatioReportRatioDisplayed', {
          'yesCount': yesCount,
          'noCount': noCount,
          'numerator': numerator,
          'denominator': denominator,
          'percentage': _formatPercentage(basisPoints),
        }),
      _ => text.t('followUpConsentRatioReportSuppressed'),
    };
    return Semantics(
      key: ValueKey(
        'follow-up-consent-ratio-report-ratio-${result.periodKey.name}',
      ),
      container: true,
      label: text.format('followUpConsentRatioReportRatioSemantics', {
        'period': period,
        'value': value,
      }),
      excludeSemantics: true,
      child: _ReportRow(title: period, value: value, divider: true),
    );
  }
}

final class _CoveragePeriod extends StatelessWidget {
  const _CoveragePeriod({required this.text, required this.result});

  final AppStrings text;
  final FollowUpConsentRatioReportPeriodResult result;

  @override
  Widget build(BuildContext context) {
    final period = _periodLabel(text, result.periodKey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(period, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        for (final cell in result.coverage)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _CoverageRow(
              text: text,
              period: period,
              periodKey: result.periodKey,
              cell: cell,
            ),
          ),
      ],
    );
  }
}

final class _CoverageRow extends StatelessWidget {
  const _CoverageRow({
    required this.text,
    required this.period,
    required this.periodKey,
    required this.cell,
  });

  final AppStrings text;
  final String period;
  final FollowUpConsentRatioReportPeriodKey periodKey;
  final FollowUpConsentRatioReportCoverageCell cell;

  @override
  Widget build(BuildContext context) {
    final state = _coverageLabel(text, cell.consentState);
    final value = switch ((cell.privacyStatus, cell.valueCount)) {
      (FollowUpConsentRatioReportPrivacyStatus.displayed, final int count) =>
        text.format('followUpConsentRatioReportCoverageDisplayed', {
          'value': count,
        }),
      _ => text.t('followUpConsentRatioReportSuppressed'),
    };
    return Semantics(
      key: ValueKey(
        'follow-up-consent-ratio-report-coverage-'
        '${periodKey.name}-'
        '${cell.consentState}',
      ),
      container: true,
      label: text.format('followUpConsentRatioReportCoverageSemantics', {
        'period': period,
        'state': state,
        'value': value,
      }),
      excludeSemantics: true,
      child: _ReportRow(title: state, value: value),
    );
  }
}

final class _ReportRow extends StatelessWidget {
  const _ReportRow({
    required this.title,
    required this.value,
    this.divider = false,
  });

  final String title;
  final String value;
  final bool divider;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: DecoratedBox(
      decoration: divider
          ? BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Theme.of(context).dividerColor),
              ),
            )
          : const BoxDecoration(),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleSmall),
            ),
            const SizedBox(width: 12),
            Flexible(child: Text(value, textAlign: TextAlign.end)),
          ],
        ),
      ),
    ),
  );
}

String _periodLabel(AppStrings text, FollowUpConsentRatioReportPeriodKey key) =>
    text.t(
      key == FollowUpConsentRatioReportPeriodKey.previous
          ? 'followUpConsentRatioReportPreviousPeriod'
          : 'followUpConsentRatioReportCurrentPeriod',
    );

String _coverageLabel(AppStrings text, String state) => switch (state) {
  'unanswered' => text.t('followUpConsentRatioReportUnanswered'),
  'refused' => text.t('followUpConsentRatioReportRefused'),
  'not_applicable' => text.t('followUpConsentRatioReportNotApplicable'),
  _ => state,
};

String _periodText(
  AppStrings text,
  FollowUpConsentRatioReportPeriod period, {
  required bool previous,
}) => text.format('followUpConsentRatioReportPeriodSemantics', {
  'period': text.t(
    previous
        ? 'followUpConsentRatioReportPreviousPeriod'
        : 'followUpConsentRatioReportCurrentPeriod',
  ),
  'from': _formatUtc(period.startUtc),
  'until': _formatUtc(period.untilUtc),
});

String _failureText(
  AppStrings text,
  FollowUpConsentRatioReportFailureCode code,
) => switch (code) {
  FollowUpConsentRatioReportFailureCode.notConfigured => text.t(
    'followUpConsentRatioReportNotConfigured',
  ),
  FollowUpConsentRatioReportFailureCode.invalidRequest => text.t(
    'followUpConsentRatioReportInvalidRequest',
  ),
  FollowUpConsentRatioReportFailureCode.unauthorized => text.t(
    'followUpConsentRatioReportUnauthorized',
  ),
  FollowUpConsentRatioReportFailureCode.forbidden => text.t(
    'followUpConsentRatioReportForbidden',
  ),
  FollowUpConsentRatioReportFailureCode.notFound => text.t(
    'followUpConsentRatioReportNotFound',
  ),
  FollowUpConsentRatioReportFailureCode.untrusted => text.t(
    'followUpConsentRatioReportUntrusted',
  ),
  FollowUpConsentRatioReportFailureCode.serviceUnavailable ||
  FollowUpConsentRatioReportFailureCode.serverRejected => text.t(
    'followUpConsentRatioReportServiceUnavailable',
  ),
  FollowUpConsentRatioReportFailureCode.networkUnavailable => text.t(
    'followUpConsentRatioReportNetworkUnavailable',
  ),
  FollowUpConsentRatioReportFailureCode.invalidResponse => text.t(
    'followUpConsentRatioReportInvalidResponse',
  ),
  FollowUpConsentRatioReportFailureCode.closed => text.t(
    'followUpConsentRatioReportServiceUnavailable',
  ),
};

String _formatPercentage(int basisPoints) {
  final whole = basisPoints ~/ 100;
  final fraction = (basisPoints % 100).toString().padLeft(2, '0');
  return '$whole.$fraction%';
}

String _formatUtc(DateTime value) => value.toUtc().toIso8601String();

String _insertBreaks(String value) {
  if (value.length < 16) return value;
  final chunks = <String>[];
  for (var index = 0; index < value.length; index += 8) {
    final end = (index + 8).clamp(0, value.length).toInt();
    chunks.add(value.substring(index, end));
  }
  return chunks.join('\u200b');
}
