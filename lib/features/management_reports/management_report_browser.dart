import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../management_reports/current_city_report_gateway.dart';
import '../../management_reports/follow_up_consent_ratio_report_gateway.dart';
import '../../management_reports/interest_report_gateway.dart';
import '../../management_reports/management_report_export_delivery.dart';
import '../../management_reports/management_report_gateway.dart';
import '../../management_reports/original_region_report_gateway.dart';
import '../contact_entry/contact_channel_label.dart';
import '../contact_journal/contact_models.dart';
import 'current_city_report_panel.dart';
import 'follow_up_consent_ratio_report_panel.dart';
import 'interest_report_panel.dart';
import 'management_report_browser_view_model.dart';
import 'original_region_report_panel.dart';

enum _ManagementReportFamily {
  channel,
  currentCity,
  interest,
  originalRegion,
  followUpConsentRatio,
}

final class ManagementReportBrowser extends StatefulWidget {
  const ManagementReportBrowser({
    super.key,
    required this.text,
    required this.gateway,
    required this.currentCityGateway,
    required this.followUpConsentRatioGateway,
    required this.interestGateway,
    required this.originalRegionGateway,
    required this.exportDelivery,
  });

  final AppStrings text;
  final ManagementReportGateway gateway;
  final CurrentCityReportGateway currentCityGateway;
  final FollowUpConsentRatioReportGateway followUpConsentRatioGateway;
  final InterestReportGateway interestGateway;
  final OriginalRegionReportGateway originalRegionGateway;
  final ManagementReportExportDelivery exportDelivery;

  @override
  State<ManagementReportBrowser> createState() =>
      _ManagementReportBrowserState();
}

final class _ManagementReportBrowserState
    extends State<ManagementReportBrowser> {
  final _projectFocusNode = FocusNode(debugLabel: 'management project picker');
  final _backFocusNode = FocusNode(debugLabel: 'management report back');
  final _exportActionFocusNode = FocusNode(
    debugLabel: 'management report export action',
  );
  final _snapshotFocusNodes = <String, FocusNode>{};
  late ManagementReportBrowserViewModel _viewModel;
  ManagementReportBrowserStage? _previousStage;
  ManagementReportExportStage? _previousExportStage;
  String? _returnFocusSnapshotId;
  var _reportFamily = _ManagementReportFamily.channel;

  @override
  void initState() {
    super.initState();
    _viewModel = _createViewModel();
    unawaited(_viewModel.initialize());
  }

  @override
  void didUpdateWidget(covariant ManagementReportBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gateway == widget.gateway &&
        oldWidget.currentCityGateway == widget.currentCityGateway &&
        oldWidget.followUpConsentRatioGateway ==
            widget.followUpConsentRatioGateway &&
        oldWidget.interestGateway == widget.interestGateway &&
        oldWidget.originalRegionGateway == widget.originalRegionGateway &&
        oldWidget.exportDelivery == widget.exportDelivery) {
      return;
    }
    _viewModel
      ..removeListener(_stateChanged)
      ..dispose();
    _clearSnapshotFocusNodes();
    _returnFocusSnapshotId = null;
    _reportFamily = _ManagementReportFamily.channel;
    _viewModel = _createViewModel();
    unawaited(_viewModel.initialize());
  }

  ManagementReportBrowserViewModel _createViewModel() {
    final viewModel = ManagementReportBrowserViewModel(
      widget.gateway,
      widget.exportDelivery,
    );
    _previousStage = viewModel.state.stage;
    _previousExportStage = viewModel.state.exportStage;
    return viewModel..addListener(_stateChanged);
  }

  @override
  void dispose() {
    _viewModel
      ..removeListener(_stateChanged)
      ..dispose();
    _projectFocusNode.dispose();
    _backFocusNode.dispose();
    _exportActionFocusNode.dispose();
    _clearSnapshotFocusNodes();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _viewModel.state;
    final text = widget.text;
    final showCurrentCityPanel =
        _reportFamily == _ManagementReportFamily.currentCity &&
        state.currentContext != null;
    final showInterestPanel =
        _reportFamily == _ManagementReportFamily.interest &&
        state.currentContext != null;
    final showOriginalRegionPanel =
        _reportFamily == _ManagementReportFamily.originalRegion &&
        state.currentContext != null;
    final showFollowUpConsentRatioPanel =
        _reportFamily == _ManagementReportFamily.followUpConsentRatio &&
        state.currentContext != null;
    final showAlternatePanel =
        showCurrentCityPanel ||
        showInterestPanel ||
        showOriginalRegionPanel ||
        showFollowUpConsentRatioPanel;
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
        if (state.currentContext != null) ...[
          _ReportTypePicker(
            text: text,
            family: _reportFamily,
            enabled:
                state.stage != ManagementReportBrowserStage.selectingContext,
            onSelected: _selectReportFamily,
          ),
          const SizedBox(height: 12),
        ],
        if (!showAlternatePanel && _showsBackAction(state)) ...[
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
            state.availableContexts.isNotEmpty &&
            (showAlternatePanel || !_showsBackAction(state)))
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
        if (!showAlternatePanel)
          if (_loadingLabel(state) case final label?) ...[
            const SizedBox(height: 20),
            LinearProgressIndicator(semanticsLabel: label),
            const SizedBox(height: 8),
            Text(label, textAlign: TextAlign.center),
          ],
        if (showCurrentCityPanel)
          CurrentCityReportPanel(
            key: ValueKey(
              'current-city-report/${state.currentContext!.projectId}',
            ),
            text: text,
            gateway: widget.currentCityGateway,
            projectId: state.currentContext!.projectId,
          )
        else if (showInterestPanel)
          InterestReportPanel(
            key: ValueKey('interest-report/${state.currentContext!.projectId}'),
            text: text,
            gateway: widget.interestGateway,
            projectId: state.currentContext!.projectId,
          )
        else if (showOriginalRegionPanel)
          OriginalRegionReportPanel(
            key: ValueKey(
              'original-region-report/${state.currentContext!.projectId}',
            ),
            text: text,
            gateway: widget.originalRegionGateway,
            projectId: state.currentContext!.projectId,
          )
        else if (showFollowUpConsentRatioPanel)
          FollowUpConsentRatioReportPanel(
            key: ValueKey(
              'follow-up-consent-ratio-report/${state.currentContext!.projectId}',
            ),
            text: text,
            gateway: widget.followUpConsentRatioGateway,
            projectId: state.currentContext!.projectId,
          )
        else if (state.stage == ManagementReportBrowserStage.directory)
          _Directory(
            text: text,
            snapshots: state.snapshots,
            focusNodeFor: _snapshotFocusNode,
            onOpen: _openSnapshot,
          ),
        if (!showAlternatePanel &&
            state.stage == ManagementReportBrowserStage.report &&
            state.snapshot != null)
          _ReportDetail(
            text: text,
            snapshot: state.snapshot!,
            exportStage: state.exportStage,
            exportFailureCode: state.exportFailureCode,
            hasExportArtifact: state.exportArtifact != null,
            exportActionFocusNode: _exportActionFocusNode,
            onPrepareExport: () => unawaited(_viewModel.prepareExport()),
            onRequestDownload: () => unawaited(_viewModel.requestDownload()),
          ),
        if (!showAlternatePanel &&
            state.stage == ManagementReportBrowserStage.failure)
          _FailurePanel(
            text: text,
            code: state.failureCode!,
            onRetry: () => unawaited(_viewModel.retry()),
          ),
      ],
    );
  }

  void _selectReportFamily(_ManagementReportFamily family) {
    if (_reportFamily == family) return;
    if (_viewModel.state.currentContext != null) {
      _viewModel.showDirectory();
    }
    _returnFocusSnapshotId = null;
    setState(() => _reportFamily = family);
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
    final exportStage = _viewModel.state.exportStage;
    final shouldFocusExportAction =
        _previousExportStage == ManagementReportExportStage.preparing &&
        exportStage == ManagementReportExportStage.ready;
    _previousStage = stage;
    _previousExportStage = exportStage;
    setState(() {});
    if (shouldFocusBack) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _backFocusNode.requestFocus();
      });
    }
    if (shouldFocusExportAction) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _exportActionFocusNode.requestFocus();
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

final class _ReportTypePicker extends StatelessWidget {
  const _ReportTypePicker({
    required this.text,
    required this.family,
    required this.enabled,
    required this.onSelected,
  });

  final AppStrings text;
  final _ManagementReportFamily family;
  final bool enabled;
  final ValueChanged<_ManagementReportFamily> onSelected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: text.t('managementReportViewLabel'),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ChoiceChip(
            key: const ValueKey('management-channel-report-view'),
            label: Text(text.t('managementReportChannelView')),
            selected: family == _ManagementReportFamily.channel,
            onSelected: enabled
                ? (_) => onSelected(_ManagementReportFamily.channel)
                : null,
          ),
          ChoiceChip(
            key: const ValueKey('management-current-city-report-view'),
            label: Text(text.t('managementReportCurrentCityView')),
            selected: family == _ManagementReportFamily.currentCity,
            onSelected: enabled
                ? (_) => onSelected(_ManagementReportFamily.currentCity)
                : null,
          ),
          ChoiceChip(
            key: const ValueKey('management-interest-report-view'),
            label: Text(text.t('managementReportInterestView')),
            selected: family == _ManagementReportFamily.interest,
            onSelected: enabled
                ? (_) => onSelected(_ManagementReportFamily.interest)
                : null,
          ),
          ChoiceChip(
            key: const ValueKey('management-original-region-report-view'),
            label: Text(text.t('managementReportOriginalRegionView')),
            selected: family == _ManagementReportFamily.originalRegion,
            onSelected: enabled
                ? (_) => onSelected(_ManagementReportFamily.originalRegion)
                : null,
          ),
          ChoiceChip(
            key: const ValueKey(
              'management-follow-up-consent-ratio-report-view',
            ),
            label: Text(
              text.t('managementReportFollowUpConsentRatioView'),
              softWrap: true,
              maxLines: 2,
              overflow: TextOverflow.visible,
              textAlign: TextAlign.center,
            ),
            selected: family == _ManagementReportFamily.followUpConsentRatio,
            onSelected: enabled
                ? (_) =>
                      onSelected(_ManagementReportFamily.followUpConsentRatio)
                : null,
          ),
        ],
      ),
    );
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
  const _ReportDetail({
    required this.text,
    required this.snapshot,
    required this.exportStage,
    required this.exportFailureCode,
    required this.hasExportArtifact,
    required this.exportActionFocusNode,
    required this.onPrepareExport,
    required this.onRequestDownload,
  });

  final AppStrings text;
  final ManagementReportSnapshot snapshot;
  final ManagementReportExportStage exportStage;
  final ManagementReportFailureCode? exportFailureCode;
  final bool hasExportArtifact;
  final FocusNode exportActionFocusNode;
  final VoidCallback onPrepareExport;
  final VoidCallback onRequestDownload;

  @override
  Widget build(BuildContext context) {
    final report = snapshot.report;
    final privacySummary = text.format('managementReportPrivacySummary', {
      'displayed': _cellCount(report, ManagementReportPrivacyStatus.displayed),
      'suppressed': _cellCount(
        report,
        ManagementReportPrivacyStatus.suppressed,
      ),
    });
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
                  label: text.t('managementReportDefinition'),
                  value: '${report.reportId}@${report.reportVersion}',
                ),
                _MetadataLine(
                  label: text.t('managementReportMetric'),
                  value:
                      '${_metricLabel(text, report.metricId)} '
                      '(${report.metricId}@${report.metricVersion})',
                ),
                _MetadataLine(
                  label: text.t('managementReportDataSource'),
                  value:
                      '${_sourceScopeLabel(text, report.sourceScope)} '
                      '(${report.sourceScope})',
                ),
                _MetadataLine(
                  label: text.t('managementReportPrivacyRule'),
                  value:
                      '${_privacyPolicyLabel(text, report.privacyPolicy)} '
                      '(${report.privacyPolicy})',
                ),
                _MetadataLine(
                  label: text.t('managementReportTimeZone'),
                  value: report.reportingTimeZone,
                ),
                _MetadataLine(
                  label: text.t('managementReportDataCutoff'),
                  value: _formatUtc(report.dataCutoffUtc),
                ),
                _MetadataLine(
                  label: text.t('managementReportDisplayedCells'),
                  value:
                      '${_cellCount(report, ManagementReportPrivacyStatus.displayed)}',
                ),
                _MetadataLine(
                  label: text.t('managementReportSuppressedCells'),
                  value:
                      '${_cellCount(report, ManagementReportPrivacyStatus.suppressed)}',
                ),
                _MetadataLine(
                  label: text.t('managementReportReleasedAt'),
                  value: _formatUtc(snapshot.summary.releasedAtUtc),
                  isLast: true,
                ),
                const SizedBox(height: 12),
                Semantics(
                  key: const ValueKey('management-report-privacy-summary'),
                  container: true,
                  excludeSemantics: true,
                  label: privacySummary,
                  child: Text(
                    privacySummary,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        _ExportControls(
          text: text,
          stage: exportStage,
          failureCode: exportFailureCode,
          hasArtifact: hasExportArtifact,
          actionFocusNode: exportActionFocusNode,
          onPrepare: onPrepareExport,
          onRequest: onRequestDownload,
        ),
        const SizedBox(height: 24),
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

final class _ExportControls extends StatelessWidget {
  const _ExportControls({
    required this.text,
    required this.stage,
    required this.failureCode,
    required this.hasArtifact,
    required this.actionFocusNode,
    required this.onPrepare,
    required this.onRequest,
  });

  final AppStrings text;
  final ManagementReportExportStage stage;
  final ManagementReportFailureCode? failureCode;
  final bool hasArtifact;
  final FocusNode actionFocusNode;
  final VoidCallback onPrepare;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final message = _exportStatusMessage(
      text,
      stage,
      failureCode: failureCode,
      hasArtifact: hasArtifact,
    );
    final isFailure = stage == ManagementReportExportStage.failure;
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            text.t('managementReportExportTitle'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 6),
        Text(text.t('managementReportExportIntro')),
        const SizedBox(height: 12),
        Semantics(
          key: const ValueKey('management-report-export-status'),
          container: true,
          liveRegion:
              stage != ManagementReportExportStage.idle &&
              stage != ManagementReportExportStage.unavailable,
          excludeSemantics: true,
          label: message,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isFailure
                  ? colors.errorContainer
                  : colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                message,
                style: TextStyle(
                  color: isFailure
                      ? colors.onErrorContainer
                      : colors.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
        if (_exportAction(text) case final action?) ...[
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: ValueKey(action.key),
                focusNode: actionFocusNode,
                onPressed: action.enabled ? action.onPressed : null,
                icon: action.busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(action.icon),
                label: Text(action.label),
              ),
            ),
          ),
        ],
      ],
    );
  }

  _ExportAction? _exportAction(AppStrings text) => switch (stage) {
    ManagementReportExportStage.unavailable => null,
    ManagementReportExportStage.idle => _ExportAction(
      key: 'management-report-export-prepare',
      label: text.t('managementReportExportPrepare'),
      icon: Icons.inventory_2_outlined,
      onPressed: onPrepare,
    ),
    ManagementReportExportStage.preparing => _ExportAction(
      key: 'management-report-export-prepare',
      label: text.t('managementReportExportPreparing'),
      icon: Icons.inventory_2_outlined,
      onPressed: onPrepare,
      enabled: false,
      busy: true,
    ),
    ManagementReportExportStage.ready => _ExportAction(
      key: 'management-report-export-request',
      label: text.t('managementReportExportRequest'),
      icon: Icons.download_outlined,
      onPressed: onRequest,
    ),
    ManagementReportExportStage.requesting => _ExportAction(
      key: 'management-report-export-request',
      label: text.t('managementReportExportRequesting'),
      icon: Icons.download_outlined,
      onPressed: onRequest,
      enabled: false,
      busy: true,
    ),
    ManagementReportExportStage.requested => _ExportAction(
      key: 'management-report-export-request',
      label: text.t('managementReportExportRequestAgain'),
      icon: Icons.download_outlined,
      onPressed: onRequest,
    ),
    ManagementReportExportStage.failure =>
      hasArtifact
          ? _ExportAction(
              key: 'management-report-export-request',
              label: text.t('managementReportExportRequestAgain'),
              icon: Icons.refresh,
              onPressed: onRequest,
            )
          : _ExportAction(
              key: 'management-report-export-prepare',
              label: text.t('managementReportExportPrepareRetry'),
              icon: Icons.refresh,
              onPressed: onPrepare,
            ),
  };
}

final class _ExportAction {
  const _ExportAction({
    required this.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.enabled = true,
    this.busy = false,
  });

  final String key;
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool enabled;
  final bool busy;
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
        subtitle: Text(value, style: Theme.of(context).textTheme.titleMedium),
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
        for (final categoryKey in managementReportCategoryKeys)
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
    final message = text.t(_failureMessageKey(code));
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

String _exportStatusMessage(
  AppStrings text,
  ManagementReportExportStage stage, {
  required ManagementReportFailureCode? failureCode,
  required bool hasArtifact,
}) => text.t(switch (stage) {
  ManagementReportExportStage.unavailable =>
    'managementReportExportUnavailable',
  ManagementReportExportStage.idle => 'managementReportExportIdle',
  ManagementReportExportStage.preparing => 'managementReportExportPreparing',
  ManagementReportExportStage.ready => 'managementReportExportReady',
  ManagementReportExportStage.requesting => 'managementReportExportRequesting',
  ManagementReportExportStage.requested => 'managementReportExportRequested',
  ManagementReportExportStage.failure when hasArtifact =>
    'managementReportExportDeliveryFailed',
  ManagementReportExportStage.failure when failureCode != null =>
    _exportFailureMessageKey(failureCode),
  ManagementReportExportStage.failure => 'managementReportExportPrepareFailed',
});

String _exportFailureMessageKey(
  ManagementReportFailureCode code,
) => switch (code) {
  ManagementReportFailureCode.unauthorized =>
    'managementReportExportUnauthorized',
  ManagementReportFailureCode.notFound => 'managementReportExportNotFound',
  ManagementReportFailureCode.untrusted => 'managementReportExportUntrusted',
  ManagementReportFailureCode.networkUnavailable =>
    'managementReportNetworkUnavailable',
  ManagementReportFailureCode.invalidResponse =>
    'managementReportExportInvalidResponse',
  ManagementReportFailureCode.notConfigured =>
    'managementReportExportNotConfigured',
  ManagementReportFailureCode.serverRejected => 'managementReportExportFailed',
};

String _failureMessageKey(ManagementReportFailureCode code) => switch (code) {
  ManagementReportFailureCode.unauthorized => 'managementReportUnauthorized',
  ManagementReportFailureCode.notFound => 'managementReportNotFound',
  ManagementReportFailureCode.untrusted => 'managementReportUntrusted',
  ManagementReportFailureCode.networkUnavailable =>
    'managementReportNetworkUnavailable',
  ManagementReportFailureCode.invalidResponse =>
    'managementReportInvalidResponse',
  ManagementReportFailureCode.notConfigured => 'managementReportNotConfigured',
  ManagementReportFailureCode.serverRejected => 'managementReportFailed',
};

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

String _metricLabel(AppStrings text, String metricId) => switch (metricId) {
  'contact_sessions' => text.t('managementReportContactSessions'),
  _ => metricId,
};

String _sourceScopeLabel(AppStrings text, String sourceScope) =>
    switch (sourceScope) {
      'backend_accepted_contacts' => text.t(
        'managementReportSourceBackendAcceptedContacts',
      ),
      _ => sourceScope,
    };

String _privacyPolicyLabel(AppStrings text, String privacyPolicy) =>
    switch (privacyPolicy) {
      'management_contact_session_privacy_v1' => text.t(
        'managementReportPrivacyContactSessionV1',
      ),
      _ => privacyPolicy,
    };

int _cellCount(
  ProtectedManagementReport report,
  ManagementReportPrivacyStatus status,
) => report.cells.where((cell) => cell.privacyStatus == status).length;

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
