import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_strings.dart';
import '../../management_reports/interest_report_gateway.dart';
import 'interest_report_panel_view_model.dart';
import 'snapshot_focus_node_cache.dart';

/// 管理项目内 interest 五档分布报告面板。
///
/// [projectId] 必须来自已经重新授权的 ManagementAnalysisContext。面板只
/// 读取 gateway 返回的固定十格结果，不缓存、不导出、不重算，也不从个人
/// 项目或目录正文推导管理范围。
final class InterestReportPanel extends StatefulWidget {
  const InterestReportPanel({
    super.key,
    required this.text,
    required this.gateway,
    required this.projectId,
  });

  final AppStrings text;
  final InterestReportGateway gateway;
  final String projectId;

  @override
  State<InterestReportPanel> createState() => _InterestReportPanelState();
}

final class _InterestReportPanelState extends State<InterestReportPanel>
    with AutomaticKeepAliveClientMixin {
  late InterestReportPanelViewModel _viewModel;
  final _backFocusNode = FocusNode(debugLabel: 'interest report back');
  final _retryFocusNode = FocusNode(debugLabel: 'interest report retry');
  final _snapshotFocusNodes = SnapshotFocusNodeCache(
    debugLabelPrefix: 'interest report',
  );
  InterestReportPanelStage? _previousStage;
  String? _returnFocusSnapshotId;

  @override
  void initState() {
    super.initState();
    _viewModel = _createViewModel();
    unawaited(_viewModel.initialize());
  }

  @override
  void didUpdateWidget(covariant InterestReportPanel oldWidget) {
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

  InterestReportPanelViewModel _createViewModel() {
    final viewModel = InterestReportPanelViewModel(
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
          key: const ValueKey('interest-report-panel'),
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  key: const ValueKey('interest-report-heading'),
                  header: true,
                  child: Text(
                    widget.text.t('interestReportTitle'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                const SizedBox(height: 8),
                Text(widget.text.t('interestReportIntro')),
                const SizedBox(height: 20),
                if (_showsBackAction(state)) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const ValueKey('interest-report-back'),
                      focusNode: _backFocusNode,
                      onPressed: _showDirectory,
                      icon: const Icon(Icons.arrow_back),
                      label: Text(
                        widget.text.t('interestReportBackToDirectory'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Semantics(
                  key: const ValueKey('interest-report-live-region'),
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

  Widget _body(InterestReportPanelState state) {
    switch (state.stage) {
      case InterestReportPanelStage.inactive:
        return const SizedBox.shrink();
      case InterestReportPanelStage.loadingDirectory:
        return _Loading(text: widget.text.t('interestReportDirectoryLoading'));
      case InterestReportPanelStage.directory:
        return _Directory(
          text: widget.text,
          snapshots: state.directory?.snapshots ?? const [],
          focusNodeFor: _snapshotFocusNode,
          onOpen: _openSnapshot,
        );
      case InterestReportPanelStage.loadingSnapshot:
        return _Loading(text: widget.text.t('interestReportLoading'));
      case InterestReportPanelStage.snapshot:
        final snapshot = state.snapshot;
        if (snapshot == null) {
          return Text(widget.text.t('interestReportFailed'));
        }
        return _SnapshotDetail(text: widget.text, snapshot: snapshot);
      case InterestReportPanelStage.failure:
        return _Failure(
          text: widget.text,
          code:
              state.failureCode ?? InterestReportFailureCode.serviceUnavailable,
          focusNode: _retryFocusNode,
          onRetry: () => unawaited(_retry()),
        );
    }
  }

  bool _showsBackAction(InterestReportPanelState state) =>
      state.selectedSummary != null &&
      (state.stage == InterestReportPanelStage.loadingSnapshot ||
          state.stage == InterestReportPanelStage.snapshot ||
          state.stage == InterestReportPanelStage.failure);

  FocusNode _snapshotFocusNode(String snapshotId) =>
      _snapshotFocusNodes.nodeFor(snapshotId);

  void _openSnapshot(InterestReportSnapshotSummary summary) {
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
          _viewModel.state.stage == InterestReportPanelStage.failure) {
        _retryFocusNode.requestFocus();
      }
    });
  }

  void _stateChanged() {
    if (!mounted) return;
    final state = _viewModel.state;
    final stage = state.stage;
    switch (stage) {
      case InterestReportPanelStage.inactive:
      case InterestReportPanelStage.loadingDirectory:
        _snapshotFocusNodes.clear();
      case InterestReportPanelStage.directory:
        _snapshotFocusNodes.retain(
          state.directory?.snapshots.map((summary) => summary.snapshotId) ??
              const <String>[],
        );
      case InterestReportPanelStage.loadingSnapshot:
      case InterestReportPanelStage.snapshot:
      case InterestReportPanelStage.failure:
        break;
    }
    final shouldFocusBack =
        _previousStage == InterestReportPanelStage.loadingSnapshot &&
        stage == InterestReportPanelStage.snapshot;
    final shouldFocusRetry =
        stage == InterestReportPanelStage.failure &&
        _previousStage != InterestReportPanelStage.failure;
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
  final List<InterestReportSnapshotSummary> snapshots;
  final FocusNode Function(String snapshotId) focusNodeFor;
  final ValueChanged<InterestReportSnapshotSummary> onOpen;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          key: const ValueKey('interest-report-directory-heading'),
          header: true,
          child: Text(
            text.t('interestReportDirectoryTitle'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 12),
        if (snapshots.isEmpty)
          Text(text.t('interestReportDirectoryEmpty'))
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
  final InterestReportSnapshotSummary summary;
  final FocusNode focusNode;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final releasedAt = _formatUtc(summary.releasedAtUtc);
    final semantics = text.format('interestReportOpenSemantics', {
      'version': summary.reportVersion,
      'dataCutoff': _formatUtc(summary.dataCutoffUtc),
      'releasedAt': releasedAt,
      'timeZone': summary.reportingTimeZone,
    });
    return Semantics(
      key: ValueKey('interest-report-${summary.snapshotId}'),
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
            '${text.t('interestReportVersion')} ${summary.reportVersion}',
          ),
          subtitle: Text(
            '${text.t('interestReportDataCutoff')}：'
            '${_formatUtc(summary.dataCutoffUtc)}\n'
            '${text.t('interestReportReleasedAt')}：$releasedAt\n'
            '${text.t('interestReportTimeZone')}：'
            '${summary.reportingTimeZone}',
          ),
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
  final InterestReportFailureCode code;
  final FocusNode focusNode;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final message = _failureText(text, code);
    return Semantics(
      key: const ValueKey('interest-report-failure'),
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
              key: const ValueKey('interest-report-retry'),
              focusNode: focusNode,
              onPressed: onRetry,
              child: Text(text.t('interestReportRetry')),
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
  final InterestReportSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final report = snapshot.report;
    final periods = report.periods;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          key: const ValueKey('interest-report-detail-heading'),
          header: true,
          child: Text(
            '${text.t('interestReportTitle')} · '
            '${text.t('interestReportVersion')} ${report.reportVersion}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 12),
        _MetadataSection(
          title: text.t('interestReportDefinition'),
          rows: [
            _MetadataRow(
              text.t('interestReportDefinition'),
              '${report.reportId}@${report.reportVersion}',
            ),
            _MetadataRow(
              text.t('interestReportMetric'),
              '${report.metricId}@${report.metricVersion}',
            ),
            _MetadataRow(
              text.t('interestReportStatisticalUnit'),
              report.statisticalUnit,
            ),
            _MetadataRow(text.t('interestReportDimension'), report.dimension),
            _MetadataRow(
              text.t('interestReportQueryFingerprint'),
              report.queryFingerprint,
              breakLongValue: true,
            ),
            _MetadataRow(
              text.t('interestReportSourceScope'),
              report.sourceScope,
            ),
            _MetadataRow(
              text.t('interestReportPrivacyRule'),
              report.privacyPolicy,
            ),
            _MetadataRow(text.t('interestReportProject'), report.projectId),
            _MetadataRow(
              text.t('interestReportTimeZone'),
              periods.reportingTimeZone,
            ),
            _MetadataRow(
              text.t('interestReportDataCutoff'),
              _formatUtc(periods.dataCutoffUtc),
            ),
            _MetadataRow(
              text.t('interestReportReleasedAt'),
              _formatUtc(snapshot.summary.releasedAtUtc),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _MetadataSection(
          headingKey: const ValueKey('interest-report-period-heading'),
          title: text.t('interestReportPeriodBoundary'),
          rows: [
            _MetadataRow(
              text.t('interestReportPeriodBoundary'),
              periods.periodBoundaryId,
            ),
            _MetadataRow(
              text.t('interestReportPreviousPeriod'),
              _periodText(text, periods.previousPeriod, previous: true),
            ),
            _MetadataRow(
              text.t('interestReportCurrentPeriod'),
              _periodText(text, periods.currentPeriod, previous: false),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _CellsSection(text: text, report: report),
      ],
    );
  }
}

final class _MetadataSection extends StatelessWidget {
  const _MetadataSection({
    this.headingKey,
    required this.title,
    required this.rows,
  });

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
      for (final row in rows) _MetadataLine(row: row),
    ],
  );
}

final class _MetadataRow {
  const _MetadataRow(this.label, this.value, {this.breakLongValue = false});

  final String label;
  final String value;
  final bool breakLongValue;
}

final class _MetadataLine extends StatelessWidget {
  const _MetadataLine({required this.row});

  final _MetadataRow row;

  @override
  Widget build(BuildContext context) {
    final visibleValue = row.breakLongValue
        ? _insertBreaks(row.value)
        : row.value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        container: true,
        label: '${row.label}：${row.value}',
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

final class _CellsSection extends StatelessWidget {
  const _CellsSection({required this.text, required this.report});

  final AppStrings text;
  final InterestReportDocument report;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        key: const ValueKey('interest-report-cell-list-heading'),
        header: true,
        child: Text(
          text.t('interestReportCellsTitle'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      const SizedBox(height: 8),
      ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 560),
        child: Scrollbar(
          child: ListView.builder(
            key: const ValueKey('interest-report-cell-list'),
            primary: false,
            itemCount: report.cells.length,
            itemBuilder: (context, index) => _InterestCellRow(
              key: ValueKey(
                'interest-report-cell-${report.cells[index].periodKey.name}'
                '-${report.cells[index].interestLevel}',
              ),
              text: text,
              cell: report.cells[index],
            ),
          ),
        ),
      ),
    ],
  );
}

final class _InterestCellRow extends StatelessWidget {
  const _InterestCellRow({super.key, required this.text, required this.cell});

  final AppStrings text;
  final InterestReportCell cell;

  @override
  Widget build(BuildContext context) {
    final value = switch ((cell.privacyStatus, cell.valueCount)) {
      (InterestReportPrivacyStatus.displayed, final int count) => text.format(
        'interestReportDisplayedValue',
        {'value': count},
      ),
      _ => text.t('interestReportSuppressed'),
    };
    final period = text.t(
      cell.periodKey == InterestReportPeriodKey.previous
          ? 'interestReportPreviousPeriod'
          : 'interestReportCurrentPeriod',
    );
    final level = text.format('interestReportLevel', {
      'level': cell.interestLevel,
    });
    return Semantics(
      container: true,
      label: text.format('interestReportCellSemantics', {
        'period': period,
        'level': level,
        'value': value,
      }),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    text.format('interestReportCellTitle', {
                      'period': period,
                      'level': level,
                    }),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(child: Text(value, textAlign: TextAlign.end)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _periodText(
  AppStrings text,
  InterestReportPeriod period, {
  required bool previous,
}) => text.format('interestReportPeriodSemantics', {
  'period': text.t(
    previous ? 'interestReportPreviousPeriod' : 'interestReportCurrentPeriod',
  ),
  'from': _formatUtc(period.startUtc),
  'until': _formatUtc(period.untilUtc),
});

String _failureText(AppStrings text, InterestReportFailureCode code) =>
    switch (code) {
      InterestReportFailureCode.notConfigured => text.t(
        'interestReportNotConfigured',
      ),
      InterestReportFailureCode.invalidRequest => text.t(
        'interestReportInvalidRequest',
      ),
      InterestReportFailureCode.unauthorized => text.t(
        'interestReportUnauthorized',
      ),
      InterestReportFailureCode.forbidden => text.t('interestReportForbidden'),
      InterestReportFailureCode.notFound => text.t('interestReportNotFound'),
      InterestReportFailureCode.untrusted => text.t('interestReportUntrusted'),
      InterestReportFailureCode.serviceUnavailable ||
      InterestReportFailureCode.serverRejected => text.t(
        'interestReportServiceUnavailable',
      ),
      InterestReportFailureCode.networkUnavailable => text.t(
        'interestReportNetworkUnavailable',
      ),
      InterestReportFailureCode.invalidResponse => text.t(
        'interestReportInvalidResponse',
      ),
    };

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
