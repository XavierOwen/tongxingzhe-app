import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_strings.dart';
import '../../management_reports/original_region_report_gateway.dart';
import 'original_region_report_panel_view_model.dart';
import 'snapshot_focus_node_cache.dart';

/// 管理项目内 original-region 报告面板。
///
/// [projectId] 必须来自已经重新授权的 `ManagementAnalysisContext`。面板只
/// 读取 gateway 返回的固定报告，不选择 latest、不重新归类城市，也不提供
/// 缓存、离线读取或导出。
final class OriginalRegionReportPanel extends StatefulWidget {
  const OriginalRegionReportPanel({
    super.key,
    required this.text,
    required this.gateway,
    required this.projectId,
  });

  final AppStrings text;
  final OriginalRegionReportGateway gateway;
  final String projectId;

  @override
  State<OriginalRegionReportPanel> createState() =>
      _OriginalRegionReportPanelState();
}

final class _OriginalRegionReportPanelState
    extends State<OriginalRegionReportPanel>
    with AutomaticKeepAliveClientMixin {
  late OriginalRegionReportPanelViewModel _viewModel;
  final _backFocusNode = FocusNode(debugLabel: 'original-region report back');
  final _retryFocusNode = FocusNode(debugLabel: 'original-region report retry');
  final _snapshotFocusNodes = SnapshotFocusNodeCache(
    debugLabelPrefix: 'original-region report',
  );
  OriginalRegionReportPanelStage? _previousStage;
  String? _returnFocusSnapshotId;

  @override
  void initState() {
    super.initState();
    _viewModel = _createViewModel();
    unawaited(_viewModel.initialize());
  }

  @override
  void didUpdateWidget(covariant OriginalRegionReportPanel oldWidget) {
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

  OriginalRegionReportPanelViewModel _createViewModel() {
    final viewModel = OriginalRegionReportPanelViewModel(
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
          key: const ValueKey('original-region-report-panel'),
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  key: const ValueKey('original-region-report-heading'),
                  header: true,
                  child: Text(
                    widget.text.t('originalRegionReportTitle'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                const SizedBox(height: 8),
                Text(widget.text.t('originalRegionReportIntro')),
                const SizedBox(height: 20),
                if (_showsBackAction(state)) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const ValueKey('original-region-report-back'),
                      focusNode: _backFocusNode,
                      onPressed: _showDirectory,
                      icon: const Icon(Icons.arrow_back),
                      label: Text(
                        widget.text.t('originalRegionReportBackToDirectory'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Semantics(
                  key: const ValueKey('original-region-report-live-region'),
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

  Widget _body(OriginalRegionReportPanelState state) {
    switch (state.stage) {
      case OriginalRegionReportPanelStage.inactive:
        return const SizedBox.shrink();
      case OriginalRegionReportPanelStage.loadingDirectory:
        return _Loading(
          text: widget.text.t('originalRegionReportDirectoryLoading'),
        );
      case OriginalRegionReportPanelStage.directory:
        return _Directory(
          text: widget.text,
          snapshots: state.directory?.snapshots ?? const [],
          focusNodeFor: _snapshotFocusNode,
          onOpen: _openSnapshot,
        );
      case OriginalRegionReportPanelStage.loadingSnapshot:
        return _Loading(text: widget.text.t('originalRegionReportLoading'));
      case OriginalRegionReportPanelStage.snapshot:
        final snapshot = state.snapshot;
        if (snapshot == null) {
          return Text(widget.text.t('originalRegionReportFailed'));
        }
        return _SnapshotDetail(text: widget.text, snapshot: snapshot);
      case OriginalRegionReportPanelStage.failure:
        return _Failure(
          text: widget.text,
          code:
              state.failureCode ??
              OriginalRegionReportFailureCode.serviceUnavailable,
          focusNode: _retryFocusNode,
          onRetry: () => unawaited(_retry()),
        );
    }
  }

  bool _showsBackAction(OriginalRegionReportPanelState state) =>
      state.selectedSummary != null &&
      (state.stage == OriginalRegionReportPanelStage.loadingSnapshot ||
          state.stage == OriginalRegionReportPanelStage.snapshot ||
          state.stage == OriginalRegionReportPanelStage.failure);

  FocusNode _snapshotFocusNode(String snapshotId) =>
      _snapshotFocusNodes.nodeFor(snapshotId);

  void _openSnapshot(OriginalRegionReportSnapshotSummary summary) {
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
          _viewModel.state.stage == OriginalRegionReportPanelStage.failure) {
        _retryFocusNode.requestFocus();
      }
    });
  }

  void _stateChanged() {
    if (!mounted) return;
    final state = _viewModel.state;
    final stage = state.stage;
    switch (stage) {
      case OriginalRegionReportPanelStage.inactive:
      case OriginalRegionReportPanelStage.loadingDirectory:
        _snapshotFocusNodes.clear();
      case OriginalRegionReportPanelStage.directory:
        _snapshotFocusNodes.retain(
          state.directory?.snapshots.map((summary) => summary.snapshotId) ??
              const <String>[],
        );
      case OriginalRegionReportPanelStage.loadingSnapshot:
      case OriginalRegionReportPanelStage.snapshot:
      case OriginalRegionReportPanelStage.failure:
        break;
    }
    final shouldFocusBack =
        _previousStage == OriginalRegionReportPanelStage.loadingSnapshot &&
        stage == OriginalRegionReportPanelStage.snapshot;
    final shouldFocusRetry =
        stage == OriginalRegionReportPanelStage.failure &&
        _previousStage != OriginalRegionReportPanelStage.failure;
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
  final List<OriginalRegionReportSnapshotSummary> snapshots;
  final FocusNode Function(String snapshotId) focusNodeFor;
  final ValueChanged<OriginalRegionReportSnapshotSummary> onOpen;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          key: const ValueKey('original-region-report-directory-heading'),
          header: true,
          child: Text(
            text.t('originalRegionReportDirectoryTitle'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 12),
        if (snapshots.isEmpty)
          Text(text.t('originalRegionReportDirectoryEmpty'))
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
  final OriginalRegionReportSnapshotSummary summary;
  final FocusNode focusNode;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final releasedAt = _formatUtc(summary.releasedAtUtc);
    final semantics = text.format('originalRegionReportOpenSemantics', {
      'version': summary.reportVersion,
      'dataCutoff': _formatUtc(summary.dataCutoffUtc),
      'releasedAt': releasedAt,
      'timeZone': summary.reportingTimeZone,
    });
    return Semantics(
      key: ValueKey('original-region-report-${summary.snapshotId}'),
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
            '${text.t('originalRegionReportVersion')} '
            '${summary.reportVersion}',
          ),
          subtitle: Text(
            '${text.t('originalRegionReportDataCutoff')}：'
            '${_formatUtc(summary.dataCutoffUtc)}\n'
            '${text.t('originalRegionReportReleasedAt')}：$releasedAt\n'
            '${text.t('originalRegionReportTimeZone')}：'
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
  final OriginalRegionReportFailureCode code;
  final FocusNode focusNode;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final message = _failureText(text, code);
    return Semantics(
      key: const ValueKey('original-region-report-failure'),
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
              key: const ValueKey('original-region-report-retry'),
              focusNode: focusNode,
              onPressed: onRetry,
              child: Text(text.t('originalRegionReportRetry')),
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
  final OriginalRegionReportSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final report = snapshot.report;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          key: const ValueKey('original-region-report-detail-heading'),
          header: true,
          child: Text(
            '${text.t('originalRegionReportTitle')} · '
            '${text.t('originalRegionReportVersion')} '
            '${report.reportVersion}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 12),
        _MetadataSection(
          title: text.t('originalRegionReportDefinition'),
          rows: [
            _MetadataRow(
              text.t('originalRegionReportDefinition'),
              '${report.reportId}@${report.reportVersion}',
            ),
            _MetadataRow(
              text.t('originalRegionReportMetric'),
              '${report.metricId}@${report.metricVersion}',
            ),
            _MetadataRow(
              text.t('originalRegionReportDimension'),
              report.dimension,
            ),
            _MetadataRow(
              text.t('originalRegionReportViewMode'),
              report.viewMode,
            ),
            _MetadataRow(
              text.t('originalRegionReportRegionGranularity'),
              report.regionGranularity,
            ),
            _MetadataRow(
              text.t('originalRegionReportQueryFingerprint'),
              report.queryFingerprint,
              breakLongValue: true,
            ),
            _MetadataRow(
              text.t('originalRegionReportSourceScope'),
              report.sourceScope,
            ),
            _MetadataRow(
              text.t('originalRegionReportPrivacyRule'),
              report.privacyPolicy,
            ),
            _MetadataRow(
              text.t('originalRegionReportProject'),
              report.projectId,
              breakLongValue: true,
            ),
            _MetadataRow(
              text.t('originalRegionReportTimeZone'),
              report.periods.reportingTimeZone,
            ),
            _MetadataRow(
              text.t('originalRegionReportDataCutoff'),
              _formatUtc(report.dataCutoffUtc),
            ),
            _MetadataRow(
              text.t('originalRegionReportSourceChangeSequence'),
              '${report.sourceChangeSequence}',
            ),
            _MetadataRow(
              text.t('originalRegionReportReleasedAt'),
              _formatUtc(snapshot.summary.releasedAtUtc),
              isLast: true,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _MetadataSection(
          headingKey: const ValueKey('original-region-report-period-heading'),
          title: text.t('originalRegionReportPeriodBoundary'),
          rows: [
            _MetadataRow(
              text.t('originalRegionReportPeriodBoundary'),
              report.periods.periodBoundaryId,
            ),
            _MetadataRow(
              text.t('originalRegionReportPreviousPeriod'),
              _periodText(text, report.periods.previousPeriod, previous: true),
            ),
            _MetadataRow(
              text.t('originalRegionReportCurrentPeriod'),
              _periodText(text, report.periods.currentPeriod, previous: false),
              isLast: true,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SourceTreeSection(text: text, sourceTree: report.sourceTreeContext),
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
  const _MetadataRow(
    this.label,
    this.value, {
    this.breakLongValue = false,
    this.isLast = false,
  });

  final String label;
  final String value;
  final bool breakLongValue;
  final bool isLast;
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
      padding: EdgeInsets.only(bottom: row.isLast ? 0 : 8),
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

final class _SourceTreeSection extends StatelessWidget {
  const _SourceTreeSection({required this.text, required this.sourceTree});

  final AppStrings text;
  final OriginalRegionReportSourceTreeContext sourceTree;

  @override
  Widget build(BuildContext context) => _MetadataSection(
    headingKey: const ValueKey('original-region-report-source-tree-heading'),
    title: text.t('originalRegionReportSourceTreeContext'),
    rows: [
      _MetadataRow(
        text.t('originalRegionReportSourceTreeContract'),
        sourceTree.contractId,
      ),
      _MetadataRow(
        text.t('originalRegionReportSourceTreeResult'),
        sourceTree.resultStatus,
      ),
      _MetadataRow(
        text.t('originalRegionReportSourceTreeReason'),
        sourceTree.reasonCode,
      ),
      _MetadataRow(
        text.t('originalRegionReportSourceTreeVersion'),
        sourceTree.sourceTreeVersion,
      ),
      _MetadataRow(
        text.t('originalRegionReportSourceTreeFingerprint'),
        sourceTree.sourceContentFingerprint,
        breakLongValue: true,
        isLast: true,
      ),
    ],
  );
}

final class _CellsSection extends StatelessWidget {
  const _CellsSection({required this.text, required this.report});

  final AppStrings text;
  final OriginalRegionReportDocument report;

  @override
  Widget build(BuildContext context) {
    final paired = _pairCells(report.cells);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          key: const ValueKey('original-region-report-city-list-heading'),
          header: true,
          child: Text(
            text.t('originalRegionReportCellsTitle'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 560),
          child: Scrollbar(
            child: ListView.builder(
              key: const ValueKey('original-region-report-city-list'),
              primary: false,
              itemCount: paired.length,
              itemBuilder: (context, index) => _CityPairRow(
                key: ValueKey(
                  'original-region-report-city-${paired[index].cityId}',
                ),
                text: text,
                pair: paired[index],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

final class _CityPair {
  const _CityPair({required this.cityId, this.previous, this.current});

  final String cityId;
  final OriginalRegionReportCell? previous;
  final OriginalRegionReportCell? current;
}

List<_CityPair> _pairCells(List<OriginalRegionReportCell> cells) {
  // 这里只按服务端给出的 cityId 配对两期，不重算数量、隐私状态或城市成员。
  final pairs = <String, _MutableCityPair>{};
  final order = <String>[];
  for (final cell in cells) {
    final pair = pairs.putIfAbsent(cell.cityId, () {
      order.add(cell.cityId);
      return _MutableCityPair(cell.cityId);
    });
    if (cell.periodKey == OriginalRegionReportPeriodKey.previous) {
      pair.previous = cell;
    } else {
      pair.current = cell;
    }
  }
  return [
    for (final cityId in order)
      _CityPair(
        cityId: cityId,
        previous: pairs[cityId]!.previous,
        current: pairs[cityId]!.current,
      ),
  ];
}

final class _MutableCityPair {
  _MutableCityPair(this.cityId);

  final String cityId;
  OriginalRegionReportCell? previous;
  OriginalRegionReportCell? current;
}

final class _CityPairRow extends StatelessWidget {
  const _CityPairRow({super.key, required this.text, required this.pair});

  final AppStrings text;
  final _CityPair pair;

  @override
  Widget build(BuildContext context) {
    final previous = _cellText(text, pair.previous, previous: true);
    final current = _cellText(text, pair.current, previous: false);
    final semantics =
        '${text.t('originalRegionReportCityId')}：${pair.cityId}，'
        '$previous，$current';
    return Semantics(
      container: true,
      label: semantics,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${text.t('originalRegionReportCityId')}：${pair.cityId}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(previous),
                Text(current),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _cellText(
  AppStrings text,
  OriginalRegionReportCell? cell, {
  required bool previous,
}) {
  final period = text.t(
    previous
        ? 'originalRegionReportPreviousPeriod'
        : 'originalRegionReportCurrentPeriod',
  );
  final value = switch ((cell?.privacyStatus, cell?.valueCount)) {
    (OriginalRegionReportPrivacyStatus.displayed, final int count) =>
      text.format('originalRegionReportDisplayedValue', {'value': count}),
    _ => text.t('originalRegionReportSuppressed'),
  };
  return text.format('originalRegionReportCellSemantics', {
    'period': period,
    'cityId': cell?.cityId ?? '',
    'value': value,
  });
}

String _periodText(
  AppStrings text,
  OriginalRegionReportPeriod period, {
  required bool previous,
}) => text.format('originalRegionReportPeriodSemantics', {
  'period': text.t(
    previous
        ? 'originalRegionReportPreviousPeriod'
        : 'originalRegionReportCurrentPeriod',
  ),
  'from': _formatUtc(period.startUtc),
  'until': _formatUtc(period.untilUtc),
});

String _failureText(AppStrings text, OriginalRegionReportFailureCode code) =>
    switch (code) {
      OriginalRegionReportFailureCode.notConfigured => text.t(
        'originalRegionReportNotConfigured',
      ),
      OriginalRegionReportFailureCode.invalidRequest => text.t(
        'originalRegionReportInvalidRequest',
      ),
      OriginalRegionReportFailureCode.unauthorized => text.t(
        'originalRegionReportUnauthorized',
      ),
      OriginalRegionReportFailureCode.forbidden => text.t(
        'originalRegionReportForbidden',
      ),
      OriginalRegionReportFailureCode.notFound => text.t(
        'originalRegionReportNotFound',
      ),
      OriginalRegionReportFailureCode.untrusted => text.t(
        'originalRegionReportUntrusted',
      ),
      OriginalRegionReportFailureCode.serviceUnavailable => text.t(
        'originalRegionReportServiceUnavailable',
      ),
      OriginalRegionReportFailureCode.networkUnavailable => text.t(
        'originalRegionReportNetworkUnavailable',
      ),
      OriginalRegionReportFailureCode.invalidResponse => text.t(
        'originalRegionReportInvalidResponse',
      ),
      OriginalRegionReportFailureCode.serverRejected => text.t(
        'originalRegionReportServiceUnavailable',
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
