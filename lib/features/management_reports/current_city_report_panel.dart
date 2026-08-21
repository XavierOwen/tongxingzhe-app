import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_strings.dart';
import '../../management_reports/current_city_report_gateway.dart';
import 'current_city_report_panel_view_model.dart';

/// 管理项目内 current-city 报告面板。
///
/// [projectId] 必须由上层已经解析并重新授权的
/// `ManagementAnalysisContext` 提供，不由面板从个人上下文或目录正文推导。
/// 面板只在当前页面内存中保留 gateway 结果，不提供缓存、导出或离线读取。
final class CurrentCityReportPanel extends StatefulWidget {
  const CurrentCityReportPanel({
    super.key,
    required this.text,
    required this.gateway,
    required this.projectId,
  });

  final AppStrings text;
  final CurrentCityReportGateway gateway;
  final String projectId;

  @override
  State<CurrentCityReportPanel> createState() => _CurrentCityReportPanelState();
}

final class _CurrentCityReportPanelState extends State<CurrentCityReportPanel>
    with AutomaticKeepAliveClientMixin {
  late CurrentCityReportPanelViewModel _viewModel;
  final _backFocusNode = FocusNode(debugLabel: 'current-city report back');
  final _retryFocusNode = FocusNode(debugLabel: 'current-city report retry');
  final _snapshotFocusNodes = <String, FocusNode>{};
  CurrentCityReportPanelStage? _previousStage;
  String? _returnFocusSnapshotId;

  @override
  void initState() {
    super.initState();
    _viewModel = _createViewModel();
    unawaited(_viewModel.initialize());
  }

  @override
  void didUpdateWidget(covariant CurrentCityReportPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gateway != widget.gateway) {
      _viewModel
        ..removeListener(_stateChanged)
        ..dispose();
      _clearSnapshotFocusNodes();
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

  CurrentCityReportPanelViewModel _createViewModel() {
    final viewModel = CurrentCityReportPanelViewModel(
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
    _clearSnapshotFocusNodes();
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
          key: const ValueKey('current-city-report-panel'),
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  key: const ValueKey('current-city-report-heading'),
                  header: true,
                  child: Text(
                    widget.text.t('currentCityReportTitle'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                const SizedBox(height: 8),
                Text(widget.text.t('currentCityReportIntro')),
                const SizedBox(height: 20),
                if (_showsBackAction(state)) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const ValueKey('current-city-report-back'),
                      focusNode: _backFocusNode,
                      onPressed: _showDirectory,
                      icon: const Icon(Icons.arrow_back),
                      label: Text(
                        widget.text.t('currentCityReportBackToDirectory'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Semantics(
                  key: const ValueKey('current-city-report-live-region'),
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

  Widget _body(CurrentCityReportPanelState state) {
    switch (state.stage) {
      case CurrentCityReportPanelStage.inactive:
        return const SizedBox.shrink();
      case CurrentCityReportPanelStage.loadingDirectory:
        return _Loading(
          text: widget.text.t('currentCityReportDirectoryLoading'),
        );
      case CurrentCityReportPanelStage.directory:
        return _Directory(
          text: widget.text,
          snapshots: state.directory?.snapshots ?? const [],
          focusNodeFor: _snapshotFocusNode,
          onOpen: _openSnapshot,
        );
      case CurrentCityReportPanelStage.loadingSnapshot:
        return _Loading(text: widget.text.t('currentCityReportLoading'));
      case CurrentCityReportPanelStage.snapshot:
        final snapshot = state.snapshot;
        if (snapshot == null) {
          return Text(widget.text.t('currentCityReportFailed'));
        }
        return _SnapshotDetail(text: widget.text, snapshot: snapshot);
      case CurrentCityReportPanelStage.failure:
        return _Failure(
          text: widget.text,
          code:
              state.failureCode ??
              CurrentCityReportFailureCode.serviceUnavailable,
          focusNode: _retryFocusNode,
          onRetry: () => unawaited(_retry()),
        );
    }
  }

  bool _showsBackAction(CurrentCityReportPanelState state) =>
      state.selectedSummary != null &&
      (state.stage == CurrentCityReportPanelStage.loadingSnapshot ||
          state.stage == CurrentCityReportPanelStage.snapshot ||
          state.stage == CurrentCityReportPanelStage.failure);

  FocusNode _snapshotFocusNode(String snapshotId) =>
      _snapshotFocusNodes.putIfAbsent(
        snapshotId,
        () => FocusNode(debugLabel: 'current-city report $snapshotId'),
      );

  void _openSnapshot(CurrentCityReportSnapshotSummary summary) {
    _returnFocusSnapshotId = summary.snapshotId;
    unawaited(_viewModel.openSnapshot(summary));
  }

  void _showDirectory() {
    final snapshotId = _returnFocusSnapshotId;
    _viewModel.returnToDirectory();
    if (snapshotId == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _snapshotFocusNodes[snapshotId]?.requestFocus();
    });
  }

  Future<void> _retry() async {
    final hadFocus = _retryFocusNode.hasFocus;
    await _viewModel.retry();
    if (!hadFocus || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          _viewModel.state.stage == CurrentCityReportPanelStage.failure) {
        _retryFocusNode.requestFocus();
      }
    });
  }

  void _stateChanged() {
    if (!mounted) return;
    final stage = _viewModel.state.stage;
    final shouldFocusBack =
        _previousStage == CurrentCityReportPanelStage.loadingSnapshot &&
        stage == CurrentCityReportPanelStage.snapshot;
    final shouldFocusRetry =
        stage == CurrentCityReportPanelStage.failure &&
        _previousStage != CurrentCityReportPanelStage.failure;
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

  void _clearSnapshotFocusNodes() {
    for (final node in _snapshotFocusNodes.values) {
      node.dispose();
    }
    _snapshotFocusNodes.clear();
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
  final List<CurrentCityReportSnapshotSummary> snapshots;
  final FocusNode Function(String snapshotId) focusNodeFor;
  final ValueChanged<CurrentCityReportSnapshotSummary> onOpen;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          key: const ValueKey('current-city-report-directory-heading'),
          header: true,
          child: Text(
            text.t('currentCityReportDirectoryTitle'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 12),
        if (snapshots.isEmpty)
          Text(text.t('currentCityReportDirectoryEmpty'))
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
  final CurrentCityReportSnapshotSummary summary;
  final FocusNode focusNode;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final releasedAt = _formatUtc(summary.releasedAtUtc);
    final semantics =
        '${text.t('currentCityReportVersion')} '
        '${summary.reportVersion}，${text.t('currentCityReportDataCutoff')}：'
        '${_formatUtc(summary.dataCutoffUtc)}，'
        '${text.t('currentCityReportReleasedAt')}：$releasedAt，'
        '${text.t('currentCityReportTimeZone')}：'
        '${summary.reportingTimeZone}';
    return Semantics(
      key: ValueKey('current-city-report-${summary.snapshotId}'),
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
            '${text.t('currentCityReportVersion')} ${summary.reportVersion}',
          ),
          subtitle: Text(
            '${text.t('currentCityReportDataCutoff')}：'
            '${_formatUtc(summary.dataCutoffUtc)}\n'
            '${text.t('currentCityReportReleasedAt')}：$releasedAt\n'
            '${text.t('currentCityReportTimeZone')}：'
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
  final CurrentCityReportFailureCode code;
  final FocusNode focusNode;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final message = _failureText(text, code);
    return Semantics(
      key: const ValueKey('current-city-report-failure'),
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
              key: const ValueKey('current-city-report-retry'),
              focusNode: focusNode,
              onPressed: onRetry,
              child: Text(text.t('currentCityReportRetry')),
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
  final CurrentCityReportSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final report = snapshot.report;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          key: const ValueKey('current-city-report-detail-heading'),
          header: true,
          child: Text(
            '${text.t('currentCityReportTitle')} · '
            '${text.t('currentCityReportVersion')} ${report.reportVersion}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 12),
        _MetadataSection(
          title: text.t('currentCityReportDefinition'),
          rows: [
            _MetadataRow(
              text.t('currentCityReportDefinition'),
              '${report.reportId}@${report.reportVersion}',
            ),
            _MetadataRow(
              text.t('currentCityReportVersion'),
              '${report.reportVersion}',
            ),
            _MetadataRow(
              text.t('currentCityReportMetric'),
              '${report.metricId}@${report.metricVersion}',
            ),
            _MetadataRow(
              text.t('currentCityReportDimension'),
              report.dimension,
            ),
            _MetadataRow(text.t('currentCityReportViewMode'), report.viewMode),
            _MetadataRow(
              text.t('currentCityReportRegionGranularity'),
              report.regionGranularity,
            ),
            _MetadataRow(
              text.t('currentCityReportQueryFingerprint'),
              report.queryFingerprint,
              breakLongValue: true,
            ),
            _MetadataRow(
              text.t('currentCityReportSourceScope'),
              report.sourceScope,
            ),
            _MetadataRow(
              text.t('currentCityReportPrivacyRule'),
              report.privacyPolicy,
            ),
            _MetadataRow(
              text.t('currentCityReportProject'),
              report.projectId,
              breakLongValue: true,
            ),
            _MetadataRow(
              text.t('currentCityReportTimeZone'),
              report.periods.reportingTimeZone,
            ),
            _MetadataRow(
              text.t('currentCityReportDataCutoff'),
              _formatUtc(report.dataCutoffUtc),
            ),
            _MetadataRow(
              text.t('currentCityReportReleasedAt'),
              _formatUtc(snapshot.summary.releasedAtUtc),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _MetadataSection(
          headingKey: const ValueKey('current-city-report-period-heading'),
          title: text.t('currentCityReportPeriodBoundary'),
          rows: [
            _MetadataRow(
              text.t('currentCityReportPeriodBoundary'),
              report.periods.periodBoundaryId,
            ),
            _MetadataRow(
              text.t('currentCityReportPreviousPeriod'),
              _periodText(text, report.periods.previousPeriod, previous: true),
            ),
            _MetadataRow(
              text.t('currentCityReportCurrentPeriod'),
              _periodText(text, report.periods.currentPeriod, previous: false),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _TargetContextSection(text: text, target: report.targetContext),
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

final class _TargetContextSection extends StatelessWidget {
  const _TargetContextSection({required this.text, required this.target});

  final AppStrings text;
  final CurrentCityReportTargetContext target;

  @override
  Widget build(BuildContext context) => _MetadataSection(
    title: text.t('currentCityReportTargetContext'),
    rows: [
      _MetadataRow(
        text.t('currentCityReportTargetContract'),
        target.contractId,
      ),
      _MetadataRow(
        text.t('currentCityReportTargetResult'),
        target.resultStatus,
      ),
      _MetadataRow(text.t('currentCityReportTargetReason'), target.reasonCode),
      _MetadataRow(
        text.t('currentCityReportTargetDataCutoff'),
        _formatUtc(target.dataCutoffUtc),
      ),
      _MetadataRow(
        text.t('currentCityReportTargetTreeVersion'),
        target.targetTreeVersion,
      ),
      _MetadataRow(
        text.t('currentCityReportTargetFingerprint'),
        target.targetContentFingerprint,
        breakLongValue: true,
      ),
      _MetadataRow(
        text.t('currentCityReportTargetSelectionSequence'),
        '${target.selectionSequence}',
      ),
      _MetadataRow(
        text.t('currentCityReportTargetSelectionSource'),
        target.selectionSource,
      ),
      _MetadataRow(
        text.t('currentCityReportTargetEvidenceAt'),
        _formatUtc(target.selectionEvidenceAtUtc),
      ),
      _MetadataRow(
        text.t('currentCityReportTargetPublishedAt'),
        _formatUtc(target.treePublishedAtUtc),
      ),
    ],
  );
}

final class _CellsSection extends StatelessWidget {
  const _CellsSection({required this.text, required this.report});

  final AppStrings text;
  final CurrentCityReportDocument report;

  @override
  Widget build(BuildContext context) {
    final paired = _pairCells(report.cells);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          key: const ValueKey('current-city-report-city-list-heading'),
          header: true,
          child: Text(
            text.t('currentCityReportDisplayedCount'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${text.t('currentCityReportDisplayedCount')}：'
          '${report.cells.where((cell) => cell.privacyStatus == CurrentCityReportPrivacyStatus.displayed).length}',
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 560),
          child: Scrollbar(
            child: ListView.builder(
              key: const ValueKey('current-city-report-city-list'),
              primary: false,
              itemCount: paired.length,
              itemBuilder: (context, index) => _CityPairRow(
                key: ValueKey(
                  'current-city-report-city-${paired[index].cityId}',
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
  final CurrentCityReportCell? previous;
  final CurrentCityReportCell? current;
}

List<_CityPair> _pairCells(List<CurrentCityReportCell> cells) {
  // 这里只把服务端给出的两期按 cityId 配对呈现，不重算数量、隐私状态或城市成员。
  final pairs = <String, _MutableCityPair>{};
  final order = <String>[];
  for (final cell in cells) {
    final pair = pairs.putIfAbsent(cell.cityId, () {
      order.add(cell.cityId);
      return _MutableCityPair(cell.cityId);
    });
    if (cell.periodKey == CurrentCityReportPeriodKey.previous) {
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
  CurrentCityReportCell? previous;
  CurrentCityReportCell? current;
}

final class _CityPairRow extends StatelessWidget {
  const _CityPairRow({super.key, required this.text, required this.pair});

  final AppStrings text;
  final _CityPair pair;

  @override
  Widget build(BuildContext context) {
    final previous = _cellText(text, pair.previous, previous: true);
    final current = _cellText(text, pair.current, previous: false);
    final semantics = '${text.t('city')}：${pair.cityId}，$previous，$current';
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
                  '${text.t('city')}：${pair.cityId}',
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
  CurrentCityReportCell? cell, {
  required bool previous,
}) {
  final period = text.t(
    previous
        ? 'currentCityReportPreviousPeriod'
        : 'currentCityReportCurrentPeriod',
  );
  final value = switch ((cell?.privacyStatus, cell?.valueCount)) {
    (CurrentCityReportPrivacyStatus.displayed, final int count) => text.format(
      'currentCityReportDisplayedValue',
      {'value': count},
    ),
    _ => text.t('currentCityReportSuppressed'),
  };
  return text.format('currentCityReportCellSemantics', {
    'period': period,
    'cityId': cell?.cityId ?? '',
    'value': value,
  });
}

String _periodText(
  AppStrings text,
  CurrentCityReportPeriod period, {
  required bool previous,
}) => text.format('currentCityReportPeriodSemantics', {
  'period': text.t(
    previous
        ? 'currentCityReportPreviousPeriod'
        : 'currentCityReportCurrentPeriod',
  ),
  'from': _formatUtc(period.startUtc),
  'until': _formatUtc(period.untilUtc),
});

String _failureText(AppStrings text, CurrentCityReportFailureCode code) =>
    switch (code) {
      CurrentCityReportFailureCode.notConfigured => text.t(
        'currentCityReportNotConfigured',
      ),
      CurrentCityReportFailureCode.invalidRequest => text.t(
        'currentCityReportInvalidRequest',
      ),
      CurrentCityReportFailureCode.unauthorized => text.t(
        'currentCityReportUnauthorized',
      ),
      CurrentCityReportFailureCode.forbidden => text.t(
        'currentCityReportForbidden',
      ),
      CurrentCityReportFailureCode.notFound => text.t(
        'currentCityReportNotFound',
      ),
      CurrentCityReportFailureCode.untrusted => text.t(
        'currentCityReportUntrusted',
      ),
      CurrentCityReportFailureCode.serviceUnavailable ||
      CurrentCityReportFailureCode.serverRejected => text.t(
        'currentCityReportServiceUnavailable',
      ),
      CurrentCityReportFailureCode.networkUnavailable => text.t(
        'currentCityReportNetworkUnavailable',
      ),
      CurrentCityReportFailureCode.invalidResponse => text.t(
        'currentCityReportInvalidResponse',
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
