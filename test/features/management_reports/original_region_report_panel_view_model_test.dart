import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/features/management_reports/original_region_report_panel_view_model.dart';
import 'package:tongxingzhe_app/management_reports/original_region_report_gateway.dart';

void main() {
  test(
    'loads the explicit project directory and preserves an empty state',
    () async {
      final gateway = _Gateway(
        directoryResult: OriginalRegionReportSuccess(_emptyDirectory),
      );
      final viewModel = OriginalRegionReportPanelViewModel(
        gateway: gateway,
        projectId: _projectA,
      );
      addTearDown(viewModel.dispose);

      await viewModel.initialize();

      expect(gateway.listedProjectIds, [_projectA]);
      expect(viewModel.state.stage, OriginalRegionReportPanelStage.directory);
      expect(viewModel.state.projectId, _projectA);
      expect(viewModel.state.directory, same(_emptyDirectory));
      expect(viewModel.state.isEmpty, isTrue);
      expect(gateway.readRequests, isEmpty);
    },
  );

  test('does not auto-open the first directory item', () async {
    final gateway = _Gateway(
      directoryResult: OriginalRegionReportSuccess(_directoryWithSummary),
      snapshotResult: OriginalRegionReportSuccess(_snapshot),
    );
    final viewModel = _viewModel(gateway);
    addTearDown(viewModel.dispose);

    await viewModel.initialize();

    expect(viewModel.state.stage, OriginalRegionReportPanelStage.directory);
    expect(viewModel.state.selectedSummary, isNull);
    expect(viewModel.state.snapshot, isNull);
    expect(gateway.readRequests, isEmpty);
  });

  test('opens only an explicitly selected directory summary', () async {
    final gateway = _Gateway(
      directoryResult: OriginalRegionReportSuccess(_directoryWithSummary),
      snapshotResult: OriginalRegionReportSuccess(_snapshot),
    );
    final viewModel = _viewModel(gateway);
    addTearDown(viewModel.dispose);
    await viewModel.initialize();

    await viewModel.openSnapshot(_summary);

    expect(viewModel.state.stage, OriginalRegionReportPanelStage.snapshot);
    expect(viewModel.state.selectedSummary, same(_summary));
    expect(viewModel.state.snapshot, same(_snapshot));
    expect(gateway.readRequests, [(_projectA, _summary)]);
  });

  test('rejects a summary that is not in the current directory', () async {
    final gateway = _Gateway(
      directoryResult: OriginalRegionReportSuccess(_directoryWithSummary),
      snapshotResult: OriginalRegionReportSuccess(_snapshot),
    );
    final viewModel = _viewModel(gateway);
    addTearDown(viewModel.dispose);
    await viewModel.initialize();

    await viewModel.openSnapshot(_otherSummary);

    expect(viewModel.state.stage, OriginalRegionReportPanelStage.directory);
    expect(gateway.readRequests, isEmpty);
  });

  test('returns to directory and ignores a late detail response', () async {
    final detail =
        Completer<OriginalRegionReportResult<OriginalRegionReportSnapshot>>();
    final gateway = _Gateway(
      directoryResult: OriginalRegionReportSuccess(_directoryWithSummary),
      snapshotHandler: (_) => detail.future,
    );
    final viewModel = _viewModel(gateway);
    addTearDown(viewModel.dispose);
    await viewModel.initialize();

    final pending = viewModel.openSnapshot(_summary);
    expect(
      viewModel.state.stage,
      OriginalRegionReportPanelStage.loadingSnapshot,
    );
    viewModel.returnToDirectory();
    detail.complete(OriginalRegionReportSuccess(_snapshot));
    await pending;

    expect(viewModel.state.stage, OriginalRegionReportPanelStage.directory);
    expect(viewModel.state.selectedSummary, isNull);
    expect(viewModel.state.snapshot, isNull);
  });

  test(
    'retries failed directory and detail stages without changing scope',
    () async {
      final gateway = _Gateway(
        directoryResult: const OriginalRegionReportRejected(
          OriginalRegionReportFailureCode.networkUnavailable,
        ),
        snapshotResult: const OriginalRegionReportRejected(
          OriginalRegionReportFailureCode.notFound,
        ),
      );
      final viewModel = _viewModel(gateway);
      addTearDown(viewModel.dispose);

      await viewModel.initialize();
      expect(viewModel.state.stage, OriginalRegionReportPanelStage.failure);

      gateway.directoryResult = OriginalRegionReportSuccess(
        _directoryWithSummary,
      );
      await viewModel.retry();
      expect(viewModel.state.stage, OriginalRegionReportPanelStage.directory);

      await viewModel.openSnapshot(_summary);
      expect(viewModel.state.stage, OriginalRegionReportPanelStage.failure);

      gateway.snapshotResult = OriginalRegionReportSuccess(_snapshot);
      await viewModel.retry();

      expect(viewModel.state.stage, OriginalRegionReportPanelStage.snapshot);
      expect(viewModel.state.snapshot, same(_snapshot));
      expect(gateway.listedProjectIds, [_projectA, _projectA]);
      expect(gateway.readRequests, [
        (_projectA, _summary),
        (_projectA, _summary),
      ]);
    },
  );

  test(
    'project update clears old contents and ignores late old response',
    () async {
      final oldDirectory =
          Completer<
            OriginalRegionReportResult<OriginalRegionReportSnapshotDirectory>
          >();
      final gateway = _Gateway(
        directoryHandler: (projectId) => projectId == _projectA
            ? oldDirectory.future
            : Future.value(OriginalRegionReportSuccess(_directoryB)),
      );
      final viewModel = _viewModel(gateway);
      addTearDown(viewModel.dispose);

      final first = viewModel.initialize();
      await Future<void>.delayed(Duration.zero);
      final second = viewModel.updateProject(_projectB);
      expect(viewModel.state.projectId, _projectB);
      expect(viewModel.state.directory, isNull);
      expect(viewModel.state.snapshot, isNull);
      await second;

      oldDirectory.complete(OriginalRegionReportSuccess(_directoryWithSummary));
      await first;

      expect(viewModel.state.projectId, _projectB);
      expect(viewModel.state.directory, same(_directoryB));
      expect(gateway.listedProjectIds, [_projectA, _projectB]);
    },
  );

  test(
    'null project deactivates and invalidates a pending directory response',
    () async {
      final pendingDirectory =
          Completer<
            OriginalRegionReportResult<OriginalRegionReportSnapshotDirectory>
          >();
      final gateway = _Gateway(
        directoryHandler: (_) => pendingDirectory.future,
      );
      final viewModel = _viewModel(gateway);
      addTearDown(viewModel.dispose);

      final loading = viewModel.initialize();
      await Future<void>.delayed(Duration.zero);
      await viewModel.updateProject(null);
      pendingDirectory.complete(
        OriginalRegionReportSuccess(_directoryWithSummary),
      );
      await loading;

      expect(viewModel.state.stage, OriginalRegionReportPanelStage.inactive);
      expect(viewModel.state.projectId, isNull);
      expect(viewModel.state.directory, isNull);
    },
  );

  test(
    'dispose invalidates a pending response without notifying afterward',
    () async {
      final pendingDirectory =
          Completer<
            OriginalRegionReportResult<OriginalRegionReportSnapshotDirectory>
          >();
      final gateway = _Gateway(
        directoryHandler: (_) => pendingDirectory.future,
      );
      final viewModel = _viewModel(gateway);
      var notifications = 0;
      viewModel.addListener(() => notifications++);

      final loading = viewModel.initialize();
      await Future<void>.delayed(Duration.zero);
      final beforeDispose = notifications;
      viewModel.dispose();
      pendingDirectory.complete(
        OriginalRegionReportSuccess(_directoryWithSummary),
      );
      await loading;

      expect(notifications, beforeDispose);
    },
  );

  test(
    'maps gateway throws to networkUnavailable for directory and detail',
    () async {
      final gateway = _Gateway(
        directoryHandler: (_) => throw StateError('directory transport failed'),
      );
      final viewModel = _viewModel(gateway);
      addTearDown(viewModel.dispose);

      await viewModel.initialize();
      expect(viewModel.state.stage, OriginalRegionReportPanelStage.failure);
      expect(
        viewModel.state.failureCode,
        OriginalRegionReportFailureCode.networkUnavailable,
      );

      gateway.directoryHandler = (_) =>
          Future.value(OriginalRegionReportSuccess(_directoryWithSummary));
      gateway.snapshotHandler = (_) =>
          throw StateError('detail transport failed');
      await viewModel.retry();
      await viewModel.openSnapshot(_summary);

      expect(viewModel.state.stage, OriginalRegionReportPanelStage.failure);
      expect(
        viewModel.state.failureCode,
        OriginalRegionReportFailureCode.networkUnavailable,
      );
    },
  );
}

final class _Gateway implements OriginalRegionReportGateway {
  _Gateway({
    OriginalRegionReportResult<OriginalRegionReportSnapshotDirectory>?
    directoryResult,
    OriginalRegionReportResult<OriginalRegionReportSnapshot>? snapshotResult,
    this.directoryHandler,
    this.snapshotHandler,
  }) : directoryResult =
           directoryResult ?? OriginalRegionReportSuccess(_emptyDirectory),
       snapshotResult =
           snapshotResult ?? OriginalRegionReportSuccess(_snapshot);

  OriginalRegionReportResult<OriginalRegionReportSnapshotDirectory>
  directoryResult;
  OriginalRegionReportResult<OriginalRegionReportSnapshot> snapshotResult;
  Future<OriginalRegionReportResult<OriginalRegionReportSnapshotDirectory>>
  Function(String projectId)?
  directoryHandler;
  Future<OriginalRegionReportResult<OriginalRegionReportSnapshot>> Function(
    OriginalRegionReportSnapshotSummary summary,
  )?
  snapshotHandler;
  final listedProjectIds = <String>[];
  final readRequests = <(String, OriginalRegionReportSnapshotSummary)>[];

  @override
  Future<void> close() async {}

  @override
  Future<OriginalRegionReportResult<OriginalRegionReportSnapshotDirectory>>
  listSnapshots(String projectId) {
    listedProjectIds.add(projectId);
    return directoryHandler?.call(projectId) ?? Future.value(directoryResult);
  }

  @override
  Future<OriginalRegionReportResult<OriginalRegionReportSnapshot>>
  readSnapshot({
    required String projectId,
    required OriginalRegionReportSnapshotSummary summary,
  }) {
    readRequests.add((projectId, summary));
    return snapshotHandler?.call(summary) ?? Future.value(snapshotResult);
  }
}

OriginalRegionReportPanelViewModel _viewModel(_Gateway gateway) =>
    OriginalRegionReportPanelViewModel(gateway: gateway, projectId: _projectA);

const _projectA = 'project-a';
const _projectB = 'project-b';
const _reportId = 'contact_sessions_by_original_region_two_periods';
const _snapshotId = 'snapshot-a';

final _summary = OriginalRegionReportSnapshotSummary(
  snapshotId: _snapshotId,
  reportId: _reportId,
  reportVersion: 1,
  reportingTimeZone: 'Asia/Shanghai',
  dataCutoffUtc: DateTime.utc(2030, 1, 22, 1),
  releasedAtUtc: DateTime.utc(2030, 1, 22, 2),
);

final _otherSummary = OriginalRegionReportSnapshotSummary(
  snapshotId: 'snapshot-other',
  reportId: _reportId,
  reportVersion: 1,
  reportingTimeZone: 'Asia/Shanghai',
  dataCutoffUtc: DateTime.utc(2030, 1, 23, 1),
  releasedAtUtc: DateTime.utc(2030, 1, 23, 2),
);

final _emptyDirectory = OriginalRegionReportSnapshotDirectory(
  accessEventId: 'event-a',
  projectId: _projectA,
  snapshots: const [],
);

final _directoryWithSummary = OriginalRegionReportSnapshotDirectory(
  accessEventId: 'event-a',
  projectId: _projectA,
  snapshots: [_summary],
);

final _directoryB = OriginalRegionReportSnapshotDirectory(
  accessEventId: 'event-b',
  projectId: _projectB,
  snapshots: const [],
);

final _snapshot = OriginalRegionReportSnapshot(
  accessEventId: 'event-a',
  summary: _summary,
  report: OriginalRegionReportDocument(
    reportId: _reportId,
    reportVersion: 1,
    metricId: 'contact_sessions',
    metricVersion: 1,
    dimension: 'original_region',
    viewMode: 'original',
    regionGranularity: 'city',
    queryFingerprint: 'fingerprint',
    privacyPolicy: 'k10',
    sourceScope: 'management',
    projectId: _projectA,
    periods: OriginalRegionReportPeriods(
      periodBoundaryId: 'period-boundary',
      reportingTimeZone: 'Asia/Shanghai',
      dataCutoffUtc: _summary.dataCutoffUtc,
      previousPeriod: OriginalRegionReportPeriod(
        startUtc: DateTime.utc(2029, 12, 30),
        untilUtc: DateTime.utc(2030, 1, 6),
      ),
      currentPeriod: OriginalRegionReportPeriod(
        startUtc: DateTime.utc(2030, 1, 6),
        untilUtc: DateTime.utc(2030, 1, 13),
      ),
    ),
    dataCutoffUtc: _summary.dataCutoffUtc,
    sourceChangeSequence: 1,
    sourceTreeContext: const OriginalRegionReportSourceTreeContext(
      contractId: 'source-tree-contract',
      resultStatus: 'selected',
      reasonCode: 'publication_selection',
      sourceTreeVersion: 'tree-v1',
      sourceContentFingerprint: 'fingerprint',
    ),
    resultStatus: 'completed',
    cells: const [],
  ),
);
