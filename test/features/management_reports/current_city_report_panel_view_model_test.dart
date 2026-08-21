import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/features/management_reports/current_city_report_panel_view_model.dart';
import 'package:tongxingzhe_app/management_reports/current_city_report_gateway.dart';

void main() {
  test(
    'loads the explicit project directory and preserves a successful empty state',
    () async {
      final gateway = _Gateway(
        directoryResult: CurrentCityReportSuccess(_directory),
      );
      final viewModel = _viewModel(gateway);
      addTearDown(viewModel.dispose);

      await viewModel.initialize();

      expect(gateway.listedProjectIds, [_projectA]);
      expect(viewModel.state.stage, CurrentCityReportPanelStage.directory);
      expect(viewModel.state.projectId, _projectA);
      expect(viewModel.state.directory, same(_directory));
      expect(viewModel.state.isEmpty, isTrue);
    },
  );

  test('does not auto-open the first directory item', () async {
    final gateway = _Gateway(
      directoryResult: CurrentCityReportSuccess(_directoryWithSummary),
      snapshotResult: CurrentCityReportSuccess(_snapshot),
    );
    final viewModel = _viewModel(gateway);
    addTearDown(viewModel.dispose);

    await viewModel.initialize();

    expect(viewModel.state.stage, CurrentCityReportPanelStage.directory);
    expect(viewModel.state.selectedSummary, isNull);
    expect(viewModel.state.snapshot, isNull);
    expect(gateway.readRequests, isEmpty);
  });

  test(
    'opens only the explicitly selected directory summary and shows its detail',
    () async {
      final gateway = _Gateway(
        directoryResult: CurrentCityReportSuccess(_directoryWithSummary),
        snapshotResult: CurrentCityReportSuccess(_snapshot),
      );
      final viewModel = _viewModel(gateway);
      addTearDown(viewModel.dispose);
      await viewModel.initialize();

      await viewModel.openSnapshot(_summary);

      expect(viewModel.state.stage, CurrentCityReportPanelStage.snapshot);
      expect(viewModel.state.selectedSummary, same(_summary));
      expect(viewModel.state.snapshot, same(_snapshot));
      expect(gateway.readRequests, [(_projectA, _summary)]);
    },
  );

  test(
    'rejects a summary that is not the current directory selection',
    () async {
      final gateway = _Gateway(
        directoryResult: CurrentCityReportSuccess(_directoryWithSummary),
        snapshotResult: CurrentCityReportSuccess(_snapshot),
      );
      final viewModel = _viewModel(gateway);
      addTearDown(viewModel.dispose);
      await viewModel.initialize();

      await viewModel.openSnapshot(_otherSummary);

      expect(viewModel.state.stage, CurrentCityReportPanelStage.directory);
      expect(gateway.readRequests, isEmpty);
    },
  );

  test('returns to directory and ignores a late detail response', () async {
    final detail =
        Completer<CurrentCityReportResult<CurrentCityReportSnapshot>>();
    final gateway = _Gateway(
      directoryResult: CurrentCityReportSuccess(_directoryWithSummary),
      snapshotHandler: (_) => detail.future,
    );
    final viewModel = _viewModel(gateway);
    addTearDown(viewModel.dispose);
    await viewModel.initialize();

    final pending = viewModel.openSnapshot(_summary);
    expect(viewModel.state.stage, CurrentCityReportPanelStage.loadingSnapshot);
    viewModel.returnToDirectory();
    detail.complete(CurrentCityReportSuccess(_snapshot));
    await pending;

    expect(viewModel.state.stage, CurrentCityReportPanelStage.directory);
    expect(viewModel.state.selectedSummary, isNull);
    expect(viewModel.state.snapshot, isNull);
  });

  test('retries a failed directory load at the directory stage', () async {
    final gateway = _Gateway(
      directoryResult: const CurrentCityReportRejected(
        CurrentCityReportFailureCode.networkUnavailable,
      ),
    );
    final viewModel = _viewModel(gateway);
    addTearDown(viewModel.dispose);
    await viewModel.initialize();
    expect(viewModel.state.stage, CurrentCityReportPanelStage.failure);

    gateway.directoryResult = CurrentCityReportSuccess(_directory);
    await viewModel.retry();

    expect(gateway.listedProjectIds, [_projectA, _projectA]);
    expect(viewModel.state.stage, CurrentCityReportPanelStage.directory);
  });

  test(
    'retries a failed detail load without rereading the directory',
    () async {
      final gateway = _Gateway(
        directoryResult: CurrentCityReportSuccess(_directoryWithSummary),
        snapshotResult: const CurrentCityReportRejected(
          CurrentCityReportFailureCode.notFound,
        ),
      );
      final viewModel = _viewModel(gateway);
      addTearDown(viewModel.dispose);
      await viewModel.initialize();
      await viewModel.openSnapshot(_summary);
      expect(viewModel.state.stage, CurrentCityReportPanelStage.failure);

      gateway.snapshotResult = CurrentCityReportSuccess(_snapshot);
      await viewModel.retry();

      expect(viewModel.state.stage, CurrentCityReportPanelStage.snapshot);
      expect(viewModel.state.snapshot, same(_snapshot));
      expect(gateway.listedProjectIds, [_projectA]);
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
            CurrentCityReportResult<CurrentCityReportSnapshotDirectory>
          >();
      final gateway = _Gateway(
        directoryHandler: (projectId) => projectId == _projectA
            ? oldDirectory.future
            : Future.value(CurrentCityReportSuccess(_directoryB)),
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
      oldDirectory.complete(CurrentCityReportSuccess(_directoryWithSummary));
      await first;

      expect(viewModel.state.projectId, _projectB);
      expect(viewModel.state.directory, same(_directoryB));
    },
  );

  test(
    'null project deactivates and invalidates a pending directory response',
    () async {
      final pending =
          Completer<
            CurrentCityReportResult<CurrentCityReportSnapshotDirectory>
          >();
      final gateway = _Gateway(directoryHandler: (_) => pending.future);
      final viewModel = _viewModel(gateway);
      addTearDown(viewModel.dispose);

      final loading = viewModel.initialize();
      await Future<void>.delayed(Duration.zero);
      await viewModel.updateProject(null);
      pending.complete(CurrentCityReportSuccess(_directoryWithSummary));
      await loading;

      expect(viewModel.state.stage, CurrentCityReportPanelStage.inactive);
      expect(viewModel.state.projectId, isNull);
      expect(viewModel.state.directory, isNull);
    },
  );

  test(
    'dispose invalidates a pending response without notifying afterward',
    () async {
      final pending =
          Completer<
            CurrentCityReportResult<CurrentCityReportSnapshotDirectory>
          >();
      final gateway = _Gateway(directoryHandler: (_) => pending.future);
      final viewModel = _viewModel(gateway);
      var notifications = 0;
      viewModel.addListener(() => notifications++);

      final loading = viewModel.initialize();
      await Future<void>.delayed(Duration.zero);
      final beforeDispose = notifications;
      viewModel.dispose();
      pending.complete(CurrentCityReportSuccess(_directoryWithSummary));
      await loading;

      expect(notifications, beforeDispose);
    },
  );
}

final class _Gateway implements CurrentCityReportGateway {
  _Gateway({
    CurrentCityReportResult<CurrentCityReportSnapshotDirectory>?
    directoryResult,
    CurrentCityReportResult<CurrentCityReportSnapshot>? snapshotResult,
    this.directoryHandler,
    this.snapshotHandler,
  }) : directoryResult =
           directoryResult ?? CurrentCityReportSuccess(_directory),
       snapshotResult = snapshotResult ?? CurrentCityReportSuccess(_snapshot);

  CurrentCityReportResult<CurrentCityReportSnapshotDirectory> directoryResult;
  CurrentCityReportResult<CurrentCityReportSnapshot> snapshotResult;
  final Future<CurrentCityReportResult<CurrentCityReportSnapshotDirectory>>
  Function(String projectId)?
  directoryHandler;
  final Future<CurrentCityReportResult<CurrentCityReportSnapshot>> Function(
    CurrentCityReportSnapshotSummary summary,
  )?
  snapshotHandler;
  final listedProjectIds = <String>[];
  final readRequests = <(String, CurrentCityReportSnapshotSummary)>[];

  @override
  Future<void> close() async {}

  @override
  Future<CurrentCityReportResult<CurrentCityReportSnapshotDirectory>>
  listSnapshots(String projectId) {
    listedProjectIds.add(projectId);
    return directoryHandler?.call(projectId) ?? Future.value(directoryResult);
  }

  @override
  Future<CurrentCityReportResult<CurrentCityReportSnapshot>> readSnapshot({
    required String projectId,
    required CurrentCityReportSnapshotSummary summary,
  }) {
    readRequests.add((projectId, summary));
    return snapshotHandler?.call(summary) ?? Future.value(snapshotResult);
  }
}

CurrentCityReportPanelViewModel _viewModel(_Gateway gateway) =>
    CurrentCityReportPanelViewModel(gateway: gateway, projectId: _projectA);

const _projectA = 'project-a';
const _projectB = 'project-b';
const _reportId = 'report-current-city';
const _snapshotId = 'snapshot-a';

final _summary = CurrentCityReportSnapshotSummary(
  snapshotId: _snapshotId,
  reportId: _reportId,
  reportVersion: 1,
  reportingTimeZone: 'Asia/Shanghai',
  dataCutoffUtc: DateTime.utc(2026, 8, 1),
  releasedAtUtc: DateTime.utc(2026, 8, 1, 1),
);

final _otherSummary = CurrentCityReportSnapshotSummary(
  snapshotId: 'snapshot-other',
  reportId: _reportId,
  reportVersion: 1,
  reportingTimeZone: 'Asia/Shanghai',
  dataCutoffUtc: DateTime.utc(2026, 8, 2),
  releasedAtUtc: DateTime.utc(2026, 8, 2, 1),
);

final _directory = CurrentCityReportSnapshotDirectory(
  accessEventId: 'event-a',
  projectId: _projectA,
  snapshots: const [],
);

final _directoryWithSummary = CurrentCityReportSnapshotDirectory(
  accessEventId: 'event-a',
  projectId: _projectA,
  snapshots: [_summary],
);

final _directoryB = CurrentCityReportSnapshotDirectory(
  accessEventId: 'event-b',
  projectId: _projectB,
  snapshots: const [],
);

final _snapshot = CurrentCityReportSnapshot(
  accessEventId: 'event-a',
  summary: _summary,
  report: _report,
);

final _report = CurrentCityReportDocument(
  reportId: _reportId,
  reportVersion: 1,
  metricId: 'contact_sessions',
  metricVersion: 1,
  dimension: 'current_city',
  viewMode: 'current',
  regionGranularity: 'city',
  queryFingerprint: 'fingerprint',
  privacyPolicy: 'k10',
  sourceScope: 'management',
  projectId: _projectA,
  periods: _periods,
  dataCutoffUtc: _cutoff,
  sourceChangeSequence: 1,
  targetContext: _targetContext,
  resultStatus: 'completed',
  cells: const [],
);

final _periods = CurrentCityReportPeriods(
  periodBoundaryId: 'period-boundary',
  reportingTimeZone: 'Asia/Shanghai',
  dataCutoffUtc: _cutoff,
  previousPeriod: CurrentCityReportPeriod(
    startUtc: DateTime.utc(2026, 7, 1),
    untilUtc: DateTime.utc(2026, 7, 2),
  ),
  currentPeriod: CurrentCityReportPeriod(
    startUtc: DateTime.utc(2026, 7, 2),
    untilUtc: DateTime.utc(2026, 7, 3),
  ),
);

final _targetContext = CurrentCityReportTargetContext(
  contractId: 'contract',
  resultStatus: 'selected',
  reasonCode: 'selected',
  dataCutoffUtc: _cutoff,
  targetTreeVersion: 'tree-v1',
  targetContentFingerprint: 'fingerprint',
  selectionSequence: 1,
  selectionSource: 'test',
  selectionEvidenceAtUtc: DateTime.utc(2026, 7, 1),
  treePublishedAtUtc: DateTime.utc(2026, 7, 1),
);

final _cutoff = DateTime.utc(2026, 8, 1);
