import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../management_reports/management_report_gateway.dart';
import '../contact_entry/contact_channel_label.dart';
import '../contact_journal/contact_models.dart';
import 'management_report_browser_view_model.dart';

final class ManagementReportBrowser extends StatefulWidget {
  const ManagementReportBrowser({
    super.key,
    required this.text,
    required this.gateway,
  });

  final AppStrings text;
  final ManagementReportGateway gateway;

  @override
  State<ManagementReportBrowser> createState() =>
      _ManagementReportBrowserState();
}

final class _ManagementReportBrowserState
    extends State<ManagementReportBrowser> {
  final _projectFocusNode = FocusNode(debugLabel: 'management project picker');
  final _backFocusNode = FocusNode(debugLabel: 'management report back');
  final _snapshotFocusNodes = <String, FocusNode>{};
  late ManagementReportBrowserViewModel _viewModel;
  ManagementReportBrowserStage? _previousStage;
  String? _returnFocusSnapshotId;

  @override
  void initState() {
    super.initState();
    _viewModel = _createViewModel();
    unawaited(_viewModel.initialize());
  }

  @override
  void didUpdateWidget(covariant ManagementReportBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gateway == widget.gateway) return;
    _viewModel
      ..removeListener(_stateChanged)
      ..dispose();
    _clearSnapshotFocusNodes();
    _returnFocusSnapshotId = null;
    _viewModel = _createViewModel();
    unawaited(_viewModel.initialize());
  }

  ManagementReportBrowserViewModel _createViewModel() {
    final viewModel = ManagementReportBrowserViewModel(widget.gateway);
    _previousStage = viewModel.state.stage;
    return viewModel..addListener(_stateChanged);
  }

  @override
  void dispose() {
    _viewModel
      ..removeListener(_stateChanged)
      ..dispose();
    _projectFocusNode.dispose();
    _backFocusNode.dispose();
    _clearSnapshotFocusNodes();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _viewModel.state;
    final text = widget.text;
    return ListView(
      key: const ValueKey('management-report-browser'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Semantics(
          header: true,
          child: Text(
            text.t('managementReportTitle'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        const SizedBox(height: 8),
        Text(text.t('managementReportIntro')),
        const SizedBox(height: 20),
        if (_showsBackAction(state)) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('management-report-back'),
              focusNode: _backFocusNode,
              onPressed: _showDirectory,
              icon: const Icon(Icons.arrow_back),
              label: Text(text.t('managementReportBackToDirectory')),
            ),
          ),
          const SizedBox(height: 8),
        ] else if (state.stage != ManagementReportBrowserStage.loadingContext &&
            state.availableContexts.isNotEmpty)
          _ProjectPicker(
            text: text,
            focusNode: _projectFocusNode,
            current: state.currentContext,
            available: state.availableContexts,
            enabled:
                state.stage != ManagementReportBrowserStage.selectingContext &&
                state.availableContexts.isNotEmpty,
            onSelected: (projectId) =>
                unawaited(_viewModel.selectContext(projectId)),
          ),
        if (state.stage == ManagementReportBrowserStage.contextSelection) ...[
          const SizedBox(height: 16),
          Text(text.t('managementReportProjectPrompt')),
          if (state.availableContexts.isEmpty) ...[
            const SizedBox(height: 8),
            Text(text.t('managementReportNoProjects')),
          ],
        ],
        if (_loadingLabel(state) case final label?) ...[
          const SizedBox(height: 20),
          LinearProgressIndicator(semanticsLabel: label),
          const SizedBox(height: 8),
          Text(label, textAlign: TextAlign.center),
        ],
        if (state.stage == ManagementReportBrowserStage.directory)
          _Directory(
            text: text,
            snapshots: state.snapshots,
            focusNodeFor: _snapshotFocusNode,
            onOpen: _openSnapshot,
          ),
        if (state.stage == ManagementReportBrowserStage.report &&
            state.snapshot != null)
          _ReportDetail(text: text, snapshot: state.snapshot!),
        if (state.stage == ManagementReportBrowserStage.failure)
          _FailurePanel(
            text: text,
            code: state.failureCode!,
            onRetry: () => unawaited(_viewModel.retry()),
          ),
      ],
    );
  }

  bool _showsBackAction(ManagementReportBrowserState state) =>
      state.selectedSummary != null &&
      (state.stage == ManagementReportBrowserStage.loadingReport ||
          state.stage == ManagementReportBrowserStage.report ||
          state.stage == ManagementReportBrowserStage.failure);

  String? _loadingLabel(ManagementReportBrowserState state) =>
      switch (state.stage) {
        ManagementReportBrowserStage.loadingContext => widget.text.t(
          'managementReportLoading',
        ),
        ManagementReportBrowserStage.selectingContext => widget.text.t(
          'managementReportProjectSwitching',
        ),
        ManagementReportBrowserStage.loadingDirectory => widget.text.t(
          'managementReportDirectoryLoading',
        ),
        ManagementReportBrowserStage.loadingReport => widget.text.t(
          'managementReportLoading',
        ),
        _ => null,
      };

  FocusNode _snapshotFocusNode(String snapshotId) =>
      _snapshotFocusNodes.putIfAbsent(
        snapshotId,
        () => FocusNode(debugLabel: 'management report $snapshotId'),
      );

  void _openSnapshot(ManagementReportSnapshotSummary summary) {
    _returnFocusSnapshotId = summary.snapshotId;
    unawaited(_viewModel.openSnapshot(summary));
  }

  void _showDirectory() {
    final snapshotId = _returnFocusSnapshotId;
    _viewModel.showDirectory();
    if (snapshotId == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _snapshotFocusNodes[snapshotId]?.requestFocus();
    });
  }

  void _stateChanged() {
    if (!mounted) return;
    final stage = _viewModel.state.stage;
    final shouldFocusBack =
        _previousStage == ManagementReportBrowserStage.loadingReport &&
        stage == ManagementReportBrowserStage.report;
    _previousStage = stage;
    setState(() {});
    if (shouldFocusBack) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _backFocusNode.requestFocus();
      });
    }
  }

  void _clearSnapshotFocusNodes() {
    for (final node in _snapshotFocusNodes.values) {
      node.dispose();
    }
    _snapshotFocusNodes.clear();
  }
}

final class _ProjectPicker extends StatelessWidget {
  const _ProjectPicker({
    required this.text,
    required this.focusNode,
    required this.current,
    required this.available,
    required this.enabled,
    required this.onSelected,
  });

  final AppStrings text;
  final FocusNode focusNode;
  final ManagementAnalysisContext? current;
  final List<ManagementAnalysisContext> available;
  final bool enabled;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final selected =
        current != null &&
            available.any((item) => item.projectId == current!.projectId)
        ? current!.projectId
        : null;
    return DropdownButtonFormField<String>(
      key: const ValueKey('management-project-picker'),
      focusNode: focusNode,
      initialValue: selected,
      isExpanded: true,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: text.t('managementReportProjectLabel'),
      ),
      items: [
        for (final item in available)
          DropdownMenuItem(
            value: item.projectId,
            child: Text(
              '${item.organizationName} · ${item.projectName}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: enabled
          ? (value) {
              if (value != null && value != selected) onSelected(value);
            }
          : null,
    );
  }
}

final class _Directory extends StatelessWidget {
  const _Directory({
    required this.text,
    required this.snapshots,
    required this.focusNodeFor,
    required this.onOpen,
  });

  final AppStrings text;
  final List<ManagementReportSnapshotSummary> snapshots;
  final FocusNode Function(String snapshotId) focusNodeFor;
  final ValueChanged<ManagementReportSnapshotSummary> onOpen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              text.t('managementReportDirectoryTitle'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 12),
          if (snapshots.isEmpty)
            Text(text.t('managementReportDirectoryEmpty'))
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
}

final class _DirectoryItem extends StatelessWidget {
  const _DirectoryItem({
    required this.text,
    required this.summary,
    required this.focusNode,
    required this.onOpen,
  });

  final AppStrings text;
  final ManagementReportSnapshotSummary summary;
  final FocusNode focusNode;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final releasedAt = _formatUtc(summary.releasedAtUtc);
    final semantics = text
        .t('managementReportOpenSemantics')
        .replaceAll('{version}', summary.reportVersion.toString())
        .replaceAll('{releasedAt}', releasedAt);
    return Semantics(
      key: ValueKey('management-report-${summary.snapshotId}'),
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
            '${text.t('managementReportVersion')} ${summary.reportVersion}',
          ),
          subtitle: Text(
            '${text.t('managementReportDataCutoff')}：'
            '${_formatUtc(summary.dataCutoffUtc)}\n'
            '${text.t('managementReportReleasedAt')}：$releasedAt\n'
            '${text.t('managementReportTimeZone')}：'
            '${summary.reportingTimeZone}',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: onOpen,
        ),
      ),
    );
  }
}

final class _ReportDetail extends StatelessWidget {
  const _ReportDetail({required this.text, required this.snapshot});

  final AppStrings text;
  final ManagementReportSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final report = snapshot.report;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            '${text.t('managementReportTitle')} · '
            '${text.t('managementReportVersion')} ${report.reportVersion}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MetadataLine(
                  label: text.t('managementReportTimeZone'),
                  value: report.reportingTimeZone,
                ),
                _MetadataLine(
                  label: text.t('managementReportDataCutoff'),
                  value: _formatUtc(report.dataCutoffUtc),
                ),
                _MetadataLine(
                  label: text.t('managementReportReleasedAt'),
                  value: _formatUtc(snapshot.summary.releasedAtUtc),
                  isLast: true,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(
              context,
            ).scale(1).clamp(1, 3);
            if (constraints.maxWidth < 640 || textScale > 1.3) {
              return _CompactReportGrid(text: text, report: report);
            }
            return _WideReportGrid(text: text, report: report);
          },
        ),
      ],
    );
  }
}

final class _MetadataLine extends StatelessWidget {
  const _MetadataLine({
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
    child: Text('$label：$value'),
  );
}

final class _CompactReportGrid extends StatelessWidget {
  const _CompactReportGrid({required this.text, required this.report});

  final AppStrings text;
  final ProtectedManagementReport report;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final periodKey in ManagementReportPeriodKey.values) ...[
        _PeriodHeading(text: text, report: report, periodKey: periodKey),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              for (final cell in report.cells.where(
                (cell) => cell.periodKey == periodKey,
              ))
                _CompactCell(text: text, cell: cell),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    ],
  );
}

final class _PeriodHeading extends StatelessWidget {
  const _PeriodHeading({
    required this.text,
    required this.report,
    required this.periodKey,
  });

  final AppStrings text;
  final ProtectedManagementReport report;
  final ManagementReportPeriodKey periodKey;

  @override
  Widget build(BuildContext context) {
    final label = _periodLabel(text, periodKey);
    final period = switch (periodKey) {
      ManagementReportPeriodKey.previous => report.previousPeriod,
      ManagementReportPeriodKey.current => report.currentPeriod,
    };
    return Semantics(
      header: true,
      child: Text(
        '$label\n${_formatUtc(period.startUtc)} – '
        '${_formatUtc(period.untilUtc)}',
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}

final class _CompactCell extends StatelessWidget {
  const _CompactCell({required this.text, required this.cell});

  final AppStrings text;
  final ProtectedManagementReportCell cell;

  @override
  Widget build(BuildContext context) {
    final category = _categoryLabel(text, cell.categoryKey);
    final value = _cellValue(text, cell);
    return Semantics(
      key: ValueKey(
        'management-report-cell-${cell.periodKey.name}-${cell.categoryKey}',
      ),
      container: true,
      label: _cellSemantics(text, cell, category, value),
      excludeSemantics: true,
      child: ListTile(
        minVerticalPadding: 12,
        title: Text(category),
        trailing: Text(value, style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }
}

final class _WideReportGrid extends StatelessWidget {
  const _WideReportGrid({required this.text, required this.report});

  final AppStrings text;
  final ProtectedManagementReport report;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: DataTable(
      columns: [
        DataColumn(label: Text(text.t('contactChannel'))),
        DataColumn(label: Text(text.t('managementReportEarlierCompleteWeek'))),
        DataColumn(label: Text(text.t('managementReportLaterCompleteWeek'))),
      ],
      rows: [
        for (final categoryKey in _managementReportCategories)
          DataRow(
            cells: [
              DataCell(Text(_categoryLabel(text, categoryKey))),
              _dataCell(
                text,
                report.cells.singleWhere(
                  (cell) =>
                      cell.periodKey == ManagementReportPeriodKey.previous &&
                      cell.categoryKey == categoryKey,
                ),
              ),
              _dataCell(
                text,
                report.cells.singleWhere(
                  (cell) =>
                      cell.periodKey == ManagementReportPeriodKey.current &&
                      cell.categoryKey == categoryKey,
                ),
              ),
            ],
          ),
      ],
    ),
  );

  DataCell _dataCell(AppStrings text, ProtectedManagementReportCell cell) {
    final category = _categoryLabel(text, cell.categoryKey);
    final value = _cellValue(text, cell);
    return DataCell(
      Semantics(
        container: true,
        label: _cellSemantics(text, cell, category, value),
        excludeSemantics: true,
        child: Text(value),
      ),
    );
  }
}

final class _FailurePanel extends StatelessWidget {
  const _FailurePanel({
    required this.text,
    required this.code,
    required this.onRetry,
  });

  final AppStrings text;
  final ManagementReportFailureCode code;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final message = text.t(switch (code) {
      ManagementReportFailureCode.unauthorized =>
        'managementReportUnauthorized',
      ManagementReportFailureCode.notFound => 'managementReportNotFound',
      ManagementReportFailureCode.untrusted => 'managementReportUntrusted',
      ManagementReportFailureCode.networkUnavailable =>
        'managementReportNetworkUnavailable',
      ManagementReportFailureCode.invalidResponse =>
        'managementReportInvalidResponse',
      ManagementReportFailureCode.notConfigured ||
      ManagementReportFailureCode.serverRejected => 'managementReportFailed',
    });
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            container: true,
            liveRegion: true,
            child: Text(
              message,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            key: const ValueKey('management-report-retry'),
            onPressed: onRetry,
            child: Text(text.t('managementReportRetry')),
          ),
        ],
      ),
    );
  }
}

String _cellSemantics(
  AppStrings text,
  ProtectedManagementReportCell cell,
  String category,
  String value,
) => text
    .t('managementReportCellSemantics')
    .replaceAll('{period}', _periodLabel(text, cell.periodKey))
    .replaceAll('{category}', category)
    .replaceAll('{value}', value);

String _cellValue(AppStrings text, ProtectedManagementReportCell cell) =>
    switch (cell.privacyStatus) {
      ManagementReportPrivacyStatus.displayed =>
        '${cell.valueCount} ${text.t('managementReportContactSessions')}',
      ManagementReportPrivacyStatus.suppressed => text.t(
        'managementReportSuppressed',
      ),
    };

String _periodLabel(AppStrings text, ManagementReportPeriodKey periodKey) =>
    text.t(switch (periodKey) {
      ManagementReportPeriodKey.previous =>
        'managementReportEarlierCompleteWeek',
      ManagementReportPeriodKey.current => 'managementReportLaterCompleteWeek',
    });

String _categoryLabel(AppStrings text, String categoryKey) {
  if (categoryKey == 'all') return text.t('managementReportTotal');
  return contactChannelLabel(text, ContactChannel.fromStorage(categoryKey));
}

String _formatUtc(DateTime value) => value.toUtc().toIso8601String();

const _managementReportCategories = [
  'all',
  'face_to_face',
  'voice_call',
  'video_call',
  'instant_text',
  'asynchronous_message',
  'mixed',
  'other_direct',
];
