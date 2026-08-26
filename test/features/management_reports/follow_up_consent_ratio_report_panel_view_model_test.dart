import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/features/management_reports/follow_up_consent_ratio_report_panel_view_model.dart';
import 'package:tongxingzhe_app/management_reports/follow_up_consent_ratio_report_gateway.dart';

void main() {
  test(
    'keeps a nullable project inactive without querying the gateway',
    () async {
      final gateway = _Gateway();
      final viewModel = _viewModel(gateway, projectId: null);
      addTearDown(viewModel.dispose);

      await viewModel.initialize();

      expect(
        viewModel.state.stage,
        FollowUpConsentRatioReportPanelStage.inactive,
      );
      expect(viewModel.state.projectId, isNull);
      expect(viewModel.state.directory, isNull);
      expect(gateway.listedProjectIds, isEmpty);
      expect(gateway.readRequests, isEmpty);
    },
  );

  test(
    'loads the explicit project directory and preserves an empty result',
    () async {
      final gateway = _Gateway(
        directoryResult: FollowUpConsentRatioReportSuccess(_emptyDirectory),
      );
      final viewModel = _viewModel(gateway);
      addTearDown(viewModel.dispose);

      await viewModel.initialize();

      expect(gateway.listedProjectIds, [_projectA]);
      expect(
        viewModel.state.stage,
        FollowUpConsentRatioReportPanelStage.directory,
      );
      expect(viewModel.state.projectId, _projectA);
      expect(viewModel.state.directory, same(_emptyDirectory));
      expect(viewModel.state.isEmpty, isTrue);
      expect(gateway.readRequests, isEmpty);
    },
  );

  test(
    'exposes a project-bound loading directory state until the read completes',
    () async {
      final pendingDirectory =
          Completer<
            FollowUpConsentRatioReportResult<
              FollowUpConsentRatioReportSnapshotDirectory
            >
          >();
      final gateway = _Gateway(
        directoryHandler: (_) => pendingDirectory.future,
      );
      final viewModel = _viewModel(gateway);
      addTearDown(viewModel.dispose);

      final loading = viewModel.initialize();
      await Future<void>.delayed(Duration.zero);

      expect(
        viewModel.state.stage,
        FollowUpConsentRatioReportPanelStage.loadingDirectory,
      );
      expect(viewModel.state.isLoading, isTrue);
      expect(viewModel.state.projectId, _projectA);
      expect(viewModel.state.directory, isNull);
      expect(viewModel.state.selectedSummary, isNull);
      expect(viewModel.state.snapshot, isNull);
      expect(gateway.listedProjectIds, [_projectA]);

      pendingDirectory.complete(
        FollowUpConsentRatioReportSuccess(_emptyDirectory),
      );
      await loading;

      expect(
        viewModel.state.stage,
        FollowUpConsentRatioReportPanelStage.directory,
      );
      expect(viewModel.state.directory, same(_emptyDirectory));
      expect(gateway.listedProjectIds, [_projectA]);
    },
  );

  test('does not auto-open the first directory item', () async {
    final gateway = _Gateway(
      directoryResult: FollowUpConsentRatioReportSuccess(_directoryWithSummary),
      snapshotResult: FollowUpConsentRatioReportSuccess(_snapshot),
    );
    final viewModel = _viewModel(gateway);
    addTearDown(viewModel.dispose);

    await viewModel.initialize();

    expect(
      viewModel.state.stage,
      FollowUpConsentRatioReportPanelStage.directory,
    );
    expect(viewModel.state.selectedSummary, isNull);
    expect(viewModel.state.snapshot, isNull);
    expect(gateway.readRequests, isEmpty);
  });

  test('opens only a directory summary with an exact summary match', () async {
    final gateway = _Gateway(
      directoryResult: FollowUpConsentRatioReportSuccess(_directoryWithSummary),
      snapshotResult: FollowUpConsentRatioReportSuccess(_snapshot),
    );
    final viewModel = _viewModel(gateway);
    addTearDown(viewModel.dispose);
    await viewModel.initialize();

    await viewModel.openSnapshot(_sameIdDifferentSummary);

    expect(
      viewModel.state.stage,
      FollowUpConsentRatioReportPanelStage.directory,
    );
    expect(gateway.readRequests, isEmpty);

    await viewModel.openSnapshot(_summary);

    expect(
      viewModel.state.stage,
      FollowUpConsentRatioReportPanelStage.snapshot,
    );
    expect(viewModel.state.selectedSummary, same(_summary));
    expect(viewModel.state.snapshot, same(_snapshot));
    expect(gateway.readRequests, [(_projectA, _summary)]);
  });

  test(
    'preserves both typed periods and suppressed values from detail',
    () async {
      final gateway = _Gateway(
        directoryResult: FollowUpConsentRatioReportSuccess(
          _directoryWithSummary,
        ),
        snapshotResult: FollowUpConsentRatioReportSuccess(_snapshot),
      );
      final viewModel = _viewModel(gateway);
      addTearDown(viewModel.dispose);
      await viewModel.initialize();

      await viewModel.openSnapshot(_summary);

      final report = viewModel.state.snapshot!.report;
      expect(report.periods.previousPeriod.startUtc, DateTime.utc(2030, 1, 1));
      expect(report.periods.currentPeriod.untilUtc, DateTime.utc(2030, 1, 15));
      expect(report.periodResults, hasLength(2));
      expect(
        report.periodResults[0].periodKey,
        FollowUpConsentRatioReportPeriodKey.previous,
      );
      expect(report.periodResults[0].ratio.yesCount, 8);
      expect(report.periodResults[0].coverage[0].valueCount, 1);
      expect(
        report.periodResults[1].periodKey,
        FollowUpConsentRatioReportPeriodKey.current,
      );
      expect(
        report.periodResults[1].ratio.privacyStatus,
        FollowUpConsentRatioReportPrivacyStatus.suppressed,
      );
      expect(report.periodResults[1].ratio.yesCount, isNull);
      expect(report.periodResults[1].ratio.noCount, isNull);
      expect(report.periodResults[1].ratio.numerator, isNull);
      expect(report.periodResults[1].ratio.denominator, isNull);
      expect(report.periodResults[1].ratio.percentageBasisPoints, isNull);
      expect(report.periodResults[1].coverage[0].valueCount, isNull);
    },
  );

  test(
    'keeps stable failure codes without exposing gateway exceptions',
    () async {
      final gateway = _Gateway(
        directoryResult: const FollowUpConsentRatioReportRejected(
          FollowUpConsentRatioReportFailureCode.forbidden,
        ),
      );
      final viewModel = _viewModel(gateway);
      addTearDown(viewModel.dispose);

      await viewModel.initialize();

      expect(
        viewModel.state.stage,
        FollowUpConsentRatioReportPanelStage.failure,
      );
      expect(
        viewModel.state.failureCode,
        FollowUpConsentRatioReportFailureCode.forbidden,
      );
      expect(viewModel.state.directory, isNull);
      expect(viewModel.state.selectedSummary, isNull);
      expect(viewModel.state.snapshot, isNull);

      gateway.directoryResult = FollowUpConsentRatioReportSuccess(
        _directoryWithSummary,
      );
      gateway.snapshotResult = const FollowUpConsentRatioReportRejected(
        FollowUpConsentRatioReportFailureCode.untrusted,
      );
      await viewModel.retry();
      await viewModel.openSnapshot(_summary);

      expect(
        viewModel.state.stage,
        FollowUpConsentRatioReportPanelStage.failure,
      );
      expect(
        viewModel.state.failureCode,
        FollowUpConsentRatioReportFailureCode.untrusted,
      );
      expect(viewModel.state.directory, same(_directoryWithSummary));
      expect(viewModel.state.selectedSummary, same(_summary));
      expect(viewModel.state.snapshot, isNull);
    },
  );

  test(
    'retries directory and detail failures without changing project scope',
    () async {
      final gateway = _Gateway(
        directoryResult: const FollowUpConsentRatioReportRejected(
          FollowUpConsentRatioReportFailureCode.networkUnavailable,
        ),
        snapshotResult: const FollowUpConsentRatioReportRejected(
          FollowUpConsentRatioReportFailureCode.notFound,
        ),
      );
      final viewModel = _viewModel(gateway);
      addTearDown(viewModel.dispose);

      await viewModel.initialize();
      expect(
        viewModel.state.stage,
        FollowUpConsentRatioReportPanelStage.failure,
      );

      gateway.directoryResult = FollowUpConsentRatioReportSuccess(
        _directoryWithSummary,
      );
      await viewModel.retry();
      expect(
        viewModel.state.stage,
        FollowUpConsentRatioReportPanelStage.directory,
      );

      await viewModel.openSnapshot(_summary);
      expect(
        viewModel.state.stage,
        FollowUpConsentRatioReportPanelStage.failure,
      );

      gateway.snapshotResult = FollowUpConsentRatioReportSuccess(_snapshot);
      await viewModel.retry();

      expect(
        viewModel.state.stage,
        FollowUpConsentRatioReportPanelStage.snapshot,
      );
      expect(viewModel.state.snapshot, same(_snapshot));
      expect(gateway.listedProjectIds, [_projectA, _projectA]);
      expect(gateway.readRequests, [
        (_projectA, _summary),
        (_projectA, _summary),
      ]);
    },
  );

  test('maps directory and detail throws to networkUnavailable', () async {
    final gateway = _Gateway(
      directoryHandler: (_) => throw StateError('directory transport failed'),
    );
    final viewModel = _viewModel(gateway);
    addTearDown(viewModel.dispose);

    await viewModel.initialize();
    expect(viewModel.state.stage, FollowUpConsentRatioReportPanelStage.failure);
    expect(
      viewModel.state.failureCode,
      FollowUpConsentRatioReportFailureCode.networkUnavailable,
    );

    gateway.directoryHandler = (_) =>
        Future.value(FollowUpConsentRatioReportSuccess(_directoryWithSummary));
    gateway.snapshotHandler = (_) =>
        throw StateError('detail transport failed');
    await viewModel.retry();
    await viewModel.openSnapshot(_summary);

    expect(viewModel.state.stage, FollowUpConsentRatioReportPanelStage.failure);
    expect(
      viewModel.state.failureCode,
      FollowUpConsentRatioReportFailureCode.networkUnavailable,
    );
  });

  test('returns to directory and invalidates a late detail response', () async {
    final detail =
        Completer<
          FollowUpConsentRatioReportResult<FollowUpConsentRatioReportSnapshot>
        >();
    final gateway = _Gateway(
      directoryResult: FollowUpConsentRatioReportSuccess(_directoryWithSummary),
      snapshotHandler: (_) => detail.future,
    );
    final viewModel = _viewModel(gateway);
    addTearDown(viewModel.dispose);
    await viewModel.initialize();

    final pending = viewModel.openSnapshot(_summary);
    expect(
      viewModel.state.stage,
      FollowUpConsentRatioReportPanelStage.loadingSnapshot,
    );
    viewModel.returnToDirectory();
    detail.complete(FollowUpConsentRatioReportSuccess(_snapshot));
    await pending;

    expect(
      viewModel.state.stage,
      FollowUpConsentRatioReportPanelStage.directory,
    );
    expect(viewModel.state.selectedSummary, isNull);
    expect(viewModel.state.snapshot, isNull);
  });

  test(
    'project change clears old state and ignores its late response',
    () async {
      final oldDirectory =
          Completer<
            FollowUpConsentRatioReportResult<
              FollowUpConsentRatioReportSnapshotDirectory
            >
          >();
      final gateway = _Gateway(
        directoryHandler: (projectId) => projectId == _projectA
            ? oldDirectory.future
            : Future.value(FollowUpConsentRatioReportSuccess(_directoryB)),
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

      oldDirectory.complete(
        FollowUpConsentRatioReportSuccess(_directoryWithSummary),
      );
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
            FollowUpConsentRatioReportResult<
              FollowUpConsentRatioReportSnapshotDirectory
            >
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
        FollowUpConsentRatioReportSuccess(_directoryWithSummary),
      );
      await loading;

      expect(
        viewModel.state.stage,
        FollowUpConsentRatioReportPanelStage.inactive,
      );
      expect(viewModel.state.projectId, isNull);
      expect(viewModel.state.directory, isNull);
    },
  );

  test(
    'dispose invalidates a pending response without notifying afterward',
    () async {
      final pendingDirectory =
          Completer<
            FollowUpConsentRatioReportResult<
              FollowUpConsentRatioReportSnapshotDirectory
            >
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
        FollowUpConsentRatioReportSuccess(_directoryWithSummary),
      );
      await loading;

      expect(notifications, beforeDispose);
    },
  );
}

final class _Gateway implements FollowUpConsentRatioReportGateway {
  _Gateway({
    FollowUpConsentRatioReportResult<
      FollowUpConsentRatioReportSnapshotDirectory
    >?
    directoryResult,
    FollowUpConsentRatioReportResult<FollowUpConsentRatioReportSnapshot>?
    snapshotResult,
    this.directoryHandler,
    this.snapshotHandler,
  }) : directoryResult =
           directoryResult ??
           FollowUpConsentRatioReportSuccess(_emptyDirectory),
       snapshotResult =
           snapshotResult ?? FollowUpConsentRatioReportSuccess(_snapshot);

  FollowUpConsentRatioReportResult<FollowUpConsentRatioReportSnapshotDirectory>
  directoryResult;
  FollowUpConsentRatioReportResult<FollowUpConsentRatioReportSnapshot>
  snapshotResult;
  Future<
    FollowUpConsentRatioReportResult<
      FollowUpConsentRatioReportSnapshotDirectory
    >
  >
  Function(String projectId)?
  directoryHandler;
  Future<FollowUpConsentRatioReportResult<FollowUpConsentRatioReportSnapshot>>
  Function(FollowUpConsentRatioReportSnapshotSummary summary)?
  snapshotHandler;
  final listedProjectIds = <String>[];
  final readRequests = <(String, FollowUpConsentRatioReportSnapshotSummary)>[];

  @override
  Future<void> close() async {}

  @override
  Future<
    FollowUpConsentRatioReportResult<
      FollowUpConsentRatioReportSnapshotDirectory
    >
  >
  listSnapshots(String projectId) {
    listedProjectIds.add(projectId);
    return directoryHandler?.call(projectId) ?? Future.value(directoryResult);
  }

  @override
  Future<FollowUpConsentRatioReportResult<FollowUpConsentRatioReportSnapshot>>
  readSnapshot({
    required String projectId,
    required FollowUpConsentRatioReportSnapshotSummary summary,
  }) {
    readRequests.add((projectId, summary));
    return snapshotHandler?.call(summary) ?? Future.value(snapshotResult);
  }
}

FollowUpConsentRatioReportPanelViewModel _viewModel(
  _Gateway gateway, {
  String? projectId = _projectA,
}) => FollowUpConsentRatioReportPanelViewModel(
  gateway: gateway,
  projectId: projectId,
);

const _projectA = 'project-a';
const _projectB = 'project-b';
const _reportId = 'follow_up_consent_ratio_two_periods';
const _snapshotId = 'snapshot-a';

final _summary = FollowUpConsentRatioReportSnapshotSummary(
  snapshotId: _snapshotId,
  reportId: _reportId,
  reportVersion: 1,
  reportingTimeZone: 'Asia/Shanghai',
  dataCutoffUtc: DateTime.utc(2030, 1, 15),
  releasedAtUtc: DateTime.utc(2030, 1, 16),
);

final _sameIdDifferentSummary = FollowUpConsentRatioReportSnapshotSummary(
  snapshotId: _snapshotId,
  reportId: _reportId,
  reportVersion: 1,
  reportingTimeZone: 'Asia/Shanghai',
  dataCutoffUtc: DateTime.utc(2030, 1, 14),
  releasedAtUtc: DateTime.utc(2030, 1, 16),
);

final _emptyDirectory = FollowUpConsentRatioReportSnapshotDirectory(
  accessEventId: 'event-a',
  projectId: _projectA,
  snapshots: const [],
);

final _directoryWithSummary = FollowUpConsentRatioReportSnapshotDirectory(
  accessEventId: 'event-a',
  projectId: _projectA,
  snapshots: [_summary],
);

final _directoryB = FollowUpConsentRatioReportSnapshotDirectory(
  accessEventId: 'event-b',
  projectId: _projectB,
  snapshots: const [],
);

final _snapshot = FollowUpConsentRatioReportSnapshot(
  accessEventId: 'event-a',
  summary: _summary,
  report: FollowUpConsentRatioReportDocument(
    reportId: _reportId,
    reportVersion: 1,
    metricId: 'follow_up_consent_ratio',
    metricVersion: 1,
    statisticalUnit: 'contact-target link',
    dimension: 'consent state',
    periodGrain: 'week',
    comparisonPeriodCount: 2,
    periodBoundaryId: 'iso_week_monday_v1',
    privacyPolicy: 'follow_up_consent_ratio_privacy_v1',
    queryFingerprint: 'fingerprint',
    sourceScope: 'backend_accepted_active_contacts',
    projectId: _projectA,
    resultStatus: 'completed',
    periods: FollowUpConsentRatioReportPeriods(
      periodBoundaryId: 'iso_week_monday_v1',
      reportingTimeZone: 'Asia/Shanghai',
      dataCutoffUtc: DateTime.utc(2030, 1, 15),
      previousPeriod: FollowUpConsentRatioReportPeriod(
        startUtc: DateTime.utc(2030, 1, 1),
        untilUtc: DateTime.utc(2030, 1, 8),
      ),
      currentPeriod: FollowUpConsentRatioReportPeriod(
        startUtc: DateTime.utc(2030, 1, 8),
        untilUtc: DateTime.utc(2030, 1, 15),
      ),
    ),
    periodResults: [
      FollowUpConsentRatioReportPeriodResult(
        periodKey: FollowUpConsentRatioReportPeriodKey.previous,
        periodOrder: 0,
        ratio: const FollowUpConsentRatioReportRatio(
          privacyStatus: FollowUpConsentRatioReportPrivacyStatus.displayed,
          yesCount: 8,
          noCount: 2,
          numerator: 8,
          denominator: 10,
          percentageBasisPoints: 8000,
        ),
        coverage: const [
          FollowUpConsentRatioReportCoverageCell(
            consentState: 'unknown',
            cellOrder: 0,
            valueCount: 1,
            privacyStatus: FollowUpConsentRatioReportPrivacyStatus.displayed,
          ),
          FollowUpConsentRatioReportCoverageCell(
            consentState: 'refused',
            cellOrder: 1,
            valueCount: 2,
            privacyStatus: FollowUpConsentRatioReportPrivacyStatus.displayed,
          ),
          FollowUpConsentRatioReportCoverageCell(
            consentState: 'not_applicable',
            cellOrder: 2,
            valueCount: 0,
            privacyStatus: FollowUpConsentRatioReportPrivacyStatus.displayed,
          ),
        ],
        unknownCount: 0,
        excludedCount: 0,
      ),
      FollowUpConsentRatioReportPeriodResult(
        periodKey: FollowUpConsentRatioReportPeriodKey.current,
        periodOrder: 1,
        ratio: const FollowUpConsentRatioReportRatio(
          privacyStatus: FollowUpConsentRatioReportPrivacyStatus.suppressed,
          yesCount: null,
          noCount: null,
          numerator: null,
          denominator: null,
          percentageBasisPoints: null,
        ),
        coverage: const [
          FollowUpConsentRatioReportCoverageCell(
            consentState: 'unknown',
            cellOrder: 0,
            valueCount: null,
            privacyStatus: FollowUpConsentRatioReportPrivacyStatus.suppressed,
          ),
          FollowUpConsentRatioReportCoverageCell(
            consentState: 'refused',
            cellOrder: 1,
            valueCount: null,
            privacyStatus: FollowUpConsentRatioReportPrivacyStatus.suppressed,
          ),
          FollowUpConsentRatioReportCoverageCell(
            consentState: 'not_applicable',
            cellOrder: 2,
            valueCount: null,
            privacyStatus: FollowUpConsentRatioReportPrivacyStatus.suppressed,
          ),
        ],
        unknownCount: 0,
        excludedCount: 0,
      ),
    ],
  ),
);
