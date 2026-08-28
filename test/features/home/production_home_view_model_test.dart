import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/app_session/session_context_gateway.dart';
import 'package:tongxingzhe_app/features/contact_journal/contact_journal.dart';
import 'package:tongxingzhe_app/features/contact_journal/contact_models.dart';
import 'package:tongxingzhe_app/features/contact_metrics/current_relationship_stage.dart';
import 'package:tongxingzhe_app/features/contact_metrics/personal_contact_overview.dart';
import 'package:tongxingzhe_app/features/home/production_home_view_model.dart';
import 'package:tongxingzhe_app/sync/foreground_sync_coordinator.dart';
import 'package:tongxingzhe_app/sync/sync_models.dart';

void main() {
  test('首页状态只公开项目显示字段并标记当前项目', () {
    final fixture = _Fixture();

    expect(
      fixture.viewModel.state.projectOptions
          .map(
            (option) => (
              option.id,
              option.name,
              option.questionnaireVersionId,
              option.questionnaireVersionNumber,
              option.isSelected,
            ),
          )
          .toList(),
      [
        ('project-1', '项目', 'questionnaire-1', 1, true),
        ('project-2', '第二项目', 'questionnaire-2', 2, false),
      ],
    );
    expect(
      () => fixture.viewModel.state.projectOptions.add(
        const ProductionHomeProjectOption(
          id: 'project-3',
          name: '第三项目',
          questionnaireVersionId: 'questionnaire-3',
          questionnaireVersionNumber: 3,
          isSelected: false,
        ),
      ),
      throwsUnsupportedError,
    );
  });

  test('初始化先同步，再发布同一上下文的首页快照', () async {
    final fixture = _Fixture();

    await fixture.viewModel.initialize();

    expect(fixture.worker.drainCalls, 1);
    expect(fixture.worker.pullCalls, 1);
    expect(fixture.source.summaryCalls, 3);
    expect(fixture.source.summaryPairCalls, 1);
    expect(fixture.viewModel.state.isLoading, isFalse);
    expect(fixture.viewModel.state.isSynchronizing, isFalse);
    expect(fixture.viewModel.state.loadFailed, isFalse);
    expect(fixture.viewModel.state.today?.summary.contactSessionCount, 5);
    expect(fixture.viewModel.state.recentSevenDays?.syncCoverageDenominator, 5);
    expect(fixture.viewModel.state.interestRatioTrend, isNotNull);
    expect(fixture.viewModel.state.interestRatioTrendLoadFailed, isFalse);
    expect(fixture.viewModel.state.contacts?.syncHealth, _health);
  });

  test('当前关系快照与首页接触汇总一起发布', () async {
    final fixture = _Fixture(
      relationshipResult: CurrentRelationshipStageGatewaySuccess(
        _relationshipSnapshot(),
      ),
    );

    await fixture.viewModel.initialize();

    expect(fixture.viewModel.state.loadFailed, isFalse);
    expect(fixture.viewModel.state.relationshipStageLoadFailed, isFalse);
    expect(
      fixture.viewModel.state.currentRelationshipStage?.snapshot.stageCounts,
      [0, 0, 1, 0, 0],
    );
  });

  test('当前关系读取失败不遮蔽既有个人接触汇总', () async {
    final fixture = _Fixture(
      relationshipResult: const CurrentRelationshipStageGatewayRejected(
        CurrentRelationshipStageGatewayFailureCode.networkUnavailable,
      ),
    );

    await fixture.viewModel.initialize();

    expect(fixture.viewModel.state.loadFailed, isFalse);
    expect(fixture.viewModel.state.today, isNotNull);
    expect(fixture.viewModel.state.relationshipStageLoadFailed, isTrue);
    expect(fixture.viewModel.state.currentRelationshipStage, isNull);
  });

  test('兴趣趋势读取失败不遮蔽既有个人接触汇总', () async {
    final fixture = _Fixture()..source.failSummaryPair = true;

    await fixture.viewModel.initialize();

    expect(fixture.viewModel.state.loadFailed, isFalse);
    expect(fixture.viewModel.state.recentSevenDays, isNotNull);
    expect(fixture.viewModel.state.interestRatioTrendLoadFailed, isTrue);
    expect(fixture.viewModel.state.interestRatioTrend, isNull);
  });

  test('兴趣趋势手工重试会重新同步并恢复比较', () async {
    final fixture = _Fixture()..source.failSummaryPair = true;
    await fixture.viewModel.initialize();

    fixture.source.failSummaryPair = false;
    await fixture.viewModel.retryInterestRatioTrend();

    expect(fixture.worker.drainCalls, 2);
    expect(fixture.source.summaryPairCalls, 2);
    expect(fixture.viewModel.state.interestRatioTrendLoadFailed, isFalse);
    expect(fixture.viewModel.state.interestRatioTrend?.deltaBasisPoints, 0);
  });

  test('个人接触汇总失败时仍保留成功的当前关系快照', () async {
    final fixture = _Fixture(
      relationshipResult: CurrentRelationshipStageGatewaySuccess(
        _relationshipSnapshot(),
      ),
    );
    fixture.source.failSummary = true;

    await fixture.viewModel.initialize();

    expect(fixture.viewModel.state.loadFailed, isTrue);
    expect(fixture.viewModel.state.recentSevenDays, isNull);
    expect(fixture.viewModel.state.relationshipStageLoadFailed, isFalse);
    expect(
      fixture.viewModel.state.currentRelationshipStage?.snapshot.stageCounts,
      [0, 0, 1, 0, 0],
    );
  });

  test('提交事件发布提示并在同步后刷新首页快照', () async {
    final fixture = _Fixture();
    await fixture.viewModel.initialize();
    fixture.source.summary = _summary(contactSessionCount: 6);

    await fixture.viewModel.contactPageClosed(submitted: true);

    expect(fixture.worker.drainCalls, 2);
    expect(fixture.viewModel.state.today?.summary.contactSessionCount, 6);
    expect(
      fixture.viewModel.state.notice?.kind,
      ProductionHomeNoticeKind.contactSubmitted,
    );
  });

  test('未提交表单关闭后刷新草稿且不发布提交提示', () async {
    final fixture = _Fixture();
    await fixture.viewModel.initialize();
    fixture.source.summary = _summary(contactSessionCount: 7);

    await fixture.viewModel.contactPageClosed(submitted: false);

    expect(fixture.worker.drainCalls, 2);
    expect(fixture.viewModel.state.today?.summary.contactSessionCount, 7);
    expect(fixture.viewModel.state.notice, isNull);
  });

  test('放弃草稿成功后同步、刷新并提供可撤销提示', () async {
    final fixture = _Fixture();
    await fixture.viewModel.initialize();

    await fixture.viewModel.abandonDraft(_draft);

    expect(fixture.draftStore.abandonedDraftIds, ['draft-1']);
    expect(fixture.worker.drainCalls, 2);
    expect(
      fixture.viewModel.state.notice?.kind,
      ProductionHomeNoticeKind.draftAbandoned,
    );
    expect(fixture.viewModel.state.notice?.draft, _draft);
  });

  test('放弃草稿失败时保留首页数据且不触发同步', () async {
    final fixture = _Fixture()..draftStore.failAbandon = true;
    await fixture.viewModel.initialize();

    await fixture.viewModel.abandonDraft(_draft);

    expect(fixture.worker.drainCalls, 1);
    expect(fixture.viewModel.state.today, isNotNull);
    expect(
      fixture.viewModel.state.notice?.kind,
      ProductionHomeNoticeKind.draftAbandonFailed,
    );
  });

  test('撤销放弃失败时发布稳定提示且不刷新数据', () async {
    final fixture = _Fixture()..draftStore.failUndo = true;
    await fixture.viewModel.initialize();

    await fixture.viewModel.undoAbandonDraft(_draft);

    expect(fixture.worker.drainCalls, 1);
    expect(
      fixture.viewModel.state.notice?.kind,
      ProductionHomeNoticeKind.draftUndoFailed,
    );
  });

  test('同步运行时收到恢复事件会串行补跑一次完整刷新', () async {
    final gate = Completer<void>();
    final fixture = _Fixture(gate: gate);

    final initialization = fixture.viewModel.initialize();
    final resumed = fixture.viewModel.appResumed();
    gate.complete();
    await Future.wait([initialization, resumed]);

    expect(identical(initialization, resumed), isTrue);
    expect(fixture.worker.drainCalls, 2);
    expect(fixture.worker.maximumConcurrentDrains, 1);
    expect(fixture.source.summaryCalls, 6);
    expect(fixture.source.summaryPairCalls, 2);
  });

  test('选择当前项目直接成功且不调用会话接口', () async {
    final fixture = _Fixture();

    final succeeded = await fixture.viewModel.selectProject(
      _context.project.id,
    );

    expect(succeeded, isTrue);
    expect(fixture.sessionActions.selectedProjectIds, isEmpty);
    expect(fixture.viewModel.state.notice, isNull);
  });

  test('发布问卷后刷新当前项目并重新解析可信上下文', () async {
    final fixture = _Fixture();

    final succeeded = await fixture.viewModel.refreshCurrentProject();

    expect(succeeded, isTrue);
    expect(fixture.sessionActions.selectedProjectIds, ['project-1']);
    expect(fixture.viewModel.state.notice, isNull);
  });

  test('选择其他项目成功时只转发用户意图', () async {
    final fixture = _Fixture();

    final succeeded = await fixture.viewModel.selectProject(
      _otherContext.project.id,
    );

    expect(succeeded, isTrue);
    expect(fixture.sessionActions.selectedProjectIds, ['project-2']);
    expect(fixture.viewModel.state.notice, isNull);
  });

  test('项目切换被拒绝时发布稳定失败提示', () async {
    final fixture = _Fixture()..sessionActions.selectResult = false;

    final succeeded = await fixture.viewModel.selectProject('project-2');

    expect(succeeded, isFalse);
    expect(
      fixture.viewModel.state.notice?.kind,
      ProductionHomeNoticeKind.projectChangeFailed,
    );
  });

  test('跨项目草稿先恢复可信上下文，同项目草稿无需切换', () async {
    final fixture = _Fixture();

    final sameProject = await fixture.viewModel.ensureDraftContext(_draft);
    final otherProject = await fixture.viewModel.ensureDraftContext(
      _otherProjectDraft,
    );

    expect(sameProject, isTrue);
    expect(otherProject, isTrue);
    expect(fixture.sessionActions.selectedProjectIds, ['project-2']);
  });

  test('创建项目发生异常时返回失败并发布稳定提示', () async {
    final fixture = _Fixture()
      ..sessionActions.createError = StateError('network_unavailable');

    final succeeded = await fixture.viewModel.createPersonalProject('新项目');

    expect(succeeded, isFalse);
    expect(fixture.sessionActions.createdProjectNames, ['新项目']);
    expect(
      fixture.viewModel.state.notice?.kind,
      ProductionHomeNoticeKind.projectChangeFailed,
    );
  });
}

final class _Fixture {
  _Fixture({
    Completer<void>? gate,
    CurrentRelationshipStageGatewayResult? relationshipResult,
  }) {
    worker = _FakeSyncWorker(gate: gate);
    syncCoordinator = ForegroundSyncCoordinator(worker);
    source = _FakeOverviewSource();
    draftStore = _FakeDraftStore();
    sessionActions = _FakeSessionActions();
    viewModel = ProductionHomeViewModel(
      context: _context,
      availableContexts: const [_context, _otherContext],
      deviceId: 'device-1',
      sessionActions: sessionActions,
      draftStore: draftStore,
      overviewRepository: PersonalContactOverviewRepository(
        source: source,
        now: () => DateTime.utc(2030, 1, 8, 18, 30),
        loadSyncHealth: syncCoordinator.health,
      ),
      relationshipStageRepository: relationshipResult == null
          ? null
          : CurrentRelationshipStageRepository(
              gateway: _FakeRelationshipStageGateway(relationshipResult),
              store: _MemoryRelationshipStageStore(),
            ),
      syncCoordinator: syncCoordinator,
    );
    addTearDown(viewModel.dispose);
  }

  late final _FakeSyncWorker worker;
  late final ForegroundSyncCoordinator syncCoordinator;
  late final _FakeOverviewSource source;
  late final _FakeDraftStore draftStore;
  late final _FakeSessionActions sessionActions;
  late final ProductionHomeViewModel viewModel;
}

final class _FakeRelationshipStageGateway
    implements CurrentRelationshipStageGateway {
  const _FakeRelationshipStageGateway(this.result);

  final CurrentRelationshipStageGatewayResult result;

  @override
  Future<void> close() async {}

  @override
  Future<CurrentRelationshipStageGatewayResult> load({
    required CurrentRelationshipStageScope scope,
  }) async => result;
}

final class _MemoryRelationshipStageStore
    implements CurrentRelationshipStageSnapshotStore {
  CurrentRelationshipStageSnapshot? snapshot;

  @override
  Future<void> clear({required CurrentRelationshipStageScope scope}) async {
    if (snapshot?.scope == scope) snapshot = null;
  }

  @override
  Future<CurrentRelationshipStageSnapshot?> read({
    required CurrentRelationshipStageScope scope,
  }) async => snapshot?.scope == scope ? snapshot : null;

  @override
  Future<void> replace(CurrentRelationshipStageSnapshot snapshot) async {
    this.snapshot = snapshot;
  }
}

final class _FakeSessionActions implements ProductionHomeSessionActions {
  final List<String> selectedProjectIds = [];
  final List<String> createdProjectNames = [];
  bool selectResult = true;
  bool createResult = true;
  Object? selectError;
  Object? createError;

  @override
  Future<bool> selectProject(String projectId) async {
    selectedProjectIds.add(projectId);
    final error = selectError;
    if (error != null) {
      throw error;
    }
    return selectResult;
  }

  @override
  Future<bool> createPersonalProject(String displayName) async {
    createdProjectNames.add(displayName);
    final error = createError;
    if (error != null) {
      throw error;
    }
    return createResult;
  }
}

final class _FakeSyncWorker implements ForegroundSyncWorker {
  _FakeSyncWorker({this.gate});

  final Completer<void>? gate;
  int drainCalls = 0;
  int pullCalls = 0;
  int concurrentDrains = 0;
  int maximumConcurrentDrains = 0;

  @override
  Future<SyncBatchDrainResult> drainBatch() async {
    drainCalls++;
    concurrentDrains++;
    maximumConcurrentDrains = maximumConcurrentDrains < concurrentDrains
        ? concurrentDrains
        : maximumConcurrentDrains;
    try {
      await gate?.future;
      return SyncBatchDrainResult.idle;
    } finally {
      concurrentDrains--;
    }
  }

  @override
  Future<SyncHealth> health() async => _health;

  @override
  Future<SyncPullApplyResult> pullOnce() async {
    pullCalls++;
    return SyncPullApplyResult.idle;
  }
}

final class _FakeOverviewSource implements PersonalContactOverviewSource {
  PersonalContactSummary summary = _summary();
  int summaryCalls = 0;
  int summaryPairCalls = 0;
  bool failSummary = false;
  bool failSummaryPair = false;

  @override
  Future<List<ContactRecord>> listContactRecords({
    required String appUserId,
    required String workspaceId,
    required String projectId,
  }) async => const [];

  @override
  Future<List<ContactDraft>> listDrafts({required String appUserId}) async {
    expect(appUserId, _context.appUserId);
    return [_draft];
  }

  @override
  Future<List<ContactAttempt>> listContactAttempts({
    required String appUserId,
    required String workspaceId,
    required String projectId,
  }) async => const [];

  @override
  Future<PersonalContactSummary> summarizePersonalContacts({
    required String appUserId,
    required String workspaceId,
    required String projectId,
    required DateTime fromUtc,
    required DateTime untilUtc,
  }) async {
    expect(appUserId, _context.appUserId);
    expect(workspaceId, _context.workspace.id);
    expect(projectId, _context.project.id);
    summaryCalls++;
    if (failSummary) throw StateError('synthetic_summary_failure');
    return summary;
  }

  @override
  Future<PersonalContactSummaryPair> summarizePersonalContactsForPeriods({
    required String appUserId,
    required String workspaceId,
    required String projectId,
    required UtcMetricPeriod previousPeriod,
    required UtcMetricPeriod currentPeriod,
  }) async {
    expect(appUserId, _context.appUserId);
    expect(workspaceId, _context.workspace.id);
    expect(projectId, _context.project.id);
    expect(previousPeriod.fromUtc, DateTime.utc(2029, 12, 25));
    expect(previousPeriod.untilUtc, DateTime.utc(2030, 1, 1));
    expect(currentPeriod.fromUtc, DateTime.utc(2030, 1, 1));
    expect(currentPeriod.untilUtc, DateTime.utc(2030, 1, 8));
    summaryPairCalls++;
    if (failSummaryPair) {
      throw StateError('synthetic_summary_pair_failure');
    }
    return PersonalContactSummaryPair(previous: summary, current: summary);
  }
}

final class _FakeDraftStore implements ProductionHomeDraftStore {
  final List<String> abandonedDraftIds = [];
  final List<String> restoredDraftIds = [];
  bool failAbandon = false;
  bool failUndo = false;

  @override
  Future<void> abandonDraft({
    required String draftId,
    required String appUserId,
    required String deviceId,
  }) async {
    if (failAbandon) {
      throw StateError('draft_abandon_failed');
    }
    abandonedDraftIds.add(draftId);
  }

  @override
  Future<void> undoAbandonDraft({
    required String draftId,
    required String appUserId,
    required String deviceId,
  }) async {
    if (failUndo) {
      throw StateError('draft_undo_failed');
    }
    restoredDraftIds.add(draftId);
  }
}

const _context = TrustedSessionContext(
  appUserId: 'user-1',
  workspace: WorkspaceContext(
    id: 'workspace-1',
    kind: WorkspaceKind.personal,
    name: '个人空间',
  ),
  project: ProjectContext(id: 'project-1', name: '项目'),
  questionnaireVersion: QuestionnaireVersionContext(
    id: 'questionnaire-1',
    versionNumber: 1,
  ),
  capabilities: {'record_contact'},
);

const _otherContext = TrustedSessionContext(
  appUserId: 'user-1',
  workspace: WorkspaceContext(
    id: 'workspace-1',
    kind: WorkspaceKind.personal,
    name: '个人空间',
  ),
  project: ProjectContext(id: 'project-2', name: '第二项目'),
  questionnaireVersion: QuestionnaireVersionContext(
    id: 'questionnaire-2',
    versionNumber: 2,
  ),
  capabilities: {'record_contact'},
);

PersonalContactSummary _summary({int contactSessionCount = 5}) {
  return PersonalContactSummary(
    contactSessionCount: contactSessionCount,
    reachCount: 9,
    interestDistribution: [contactSessionCount - 4, 1, 1, 1, 1],
    pendingSyncCount: 2,
    channelDistribution: [contactSessionCount, 0, 0, 0, 0, 0, 0],
  );
}

const _health = SyncHealth(
  onlyOnDeviceCount: 2,
  syncingCount: 0,
  retryingCount: 0,
  needsResolutionCount: 0,
  permanentFailureCount: 0,
  completedCount: 3,
  oldestPendingAge: Duration.zero,
  lastSuccessAtUtc: null,
  lastFailureCode: null,
  serverCursor: null,
);

CurrentRelationshipStageSnapshot _relationshipSnapshot() {
  final scope = CurrentRelationshipStageScope.fromContext(_context);
  return CurrentRelationshipStageSnapshot(
    scope: scope,
    snapshotAsOfUtc: DateTime.utc(2030, 1, 8, 18),
    sourceDataCutoffUtc: DateTime.utc(2030, 1, 8, 17, 55),
    authorizedAtUtc: DateTime.utc(2030, 1, 8, 17, 59),
    lastSuccessfulSyncAtUtc: DateTime.utc(2030, 1, 8, 18, 1),
    coverage: CurrentRelationshipStageCoverage.known(
      totalCount: 1,
      pendingCount: 0,
    ),
    rows: [
      CurrentRelationshipStageRow(
        targetId: 'target-2',
        relationshipProjectId: scope.projectId,
        assignedAppUserId: scope.appUserId,
        stage: 2,
        currentRevision: 1,
        updatedAtUtc: DateTime.utc(2030, 1, 8, 17),
      ),
    ],
  );
}

final _draft = ContactDraft(
  draftId: 'draft-1',
  appUserId: _context.appUserId,
  workspaceId: _context.workspace.id,
  projectId: _context.project.id,
  questionnaireVersionId: _context.questionnaireVersion.id,
  createdAtUtc: DateTime.utc(2030, 1, 8, 18),
  updatedAtUtc: DateTime.utc(2030, 1, 8, 18),
  occurredAtUtc: DateTime.utc(2030, 1, 8, 17),
  occurredTimeZone: 'America/Chicago',
  channel: ContactChannel.videoCall,
  channelDetail: null,
  location: const NotApplicableContactLocation(),
  reachCount: 2,
  interestLevel: 3,
  answers: const [],
  syncMode: ContactDraftSyncMode.accountPrivate,
  localRevision: 1,
  serverRevision: 0,
  conflictOfDraftId: null,
);

final _otherProjectDraft = ContactDraft(
  draftId: 'draft-2',
  appUserId: _context.appUserId,
  workspaceId: _context.workspace.id,
  projectId: _otherContext.project.id,
  questionnaireVersionId: _otherContext.questionnaireVersion.id,
  createdAtUtc: DateTime.utc(2030, 1, 8, 18),
  updatedAtUtc: DateTime.utc(2030, 1, 8, 18),
  occurredAtUtc: DateTime.utc(2030, 1, 8, 17),
  occurredTimeZone: 'America/Chicago',
  channel: ContactChannel.voiceCall,
  channelDetail: null,
  location: const NotApplicableContactLocation(),
  reachCount: 1,
  interestLevel: 2,
  answers: const [],
  syncMode: ContactDraftSyncMode.accountPrivate,
  localRevision: 1,
  serverRevision: 0,
  conflictOfDraftId: null,
);
