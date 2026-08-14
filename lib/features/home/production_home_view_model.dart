import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app_session/app_session.dart';
import '../../app_session/session_context_gateway.dart';
import '../../sync/foreground_sync_coordinator.dart';
import '../../sync/sync_engine_factory.dart';
import '../contact_journal/contact_journal.dart';
import '../contact_journal/contact_models.dart';
import '../contact_metrics/current_relationship_stage.dart';
import '../contact_metrics/metric_contract.dart';
import '../contact_metrics/personal_contact_overview.dart';
import '../contact_metrics/personal_interest_ratio_trend.dart';

/// 首页一次性提示的稳定类别。
enum ProductionHomeNoticeKind {
  contactSubmitted,
  contactAttemptRecorded,
  draftAbandoned,
  draftAbandonFailed,
  draftUndoFailed,
  projectChangeFailed,
}

/// Widget 消费的一次性提示。
final class ProductionHomeNotice {
  const ProductionHomeNotice({
    required this.id,
    required this.kind,
    this.draft,
  });

  final int id;
  final ProductionHomeNoticeKind kind;
  final ContactDraft? draft;
}

/// 首页显示项目所需的最小可信上下文。
final class ProductionHomeProjectOption {
  const ProductionHomeProjectOption({
    required this.id,
    required this.name,
    required this.questionnaireVersionId,
    required this.questionnaireVersionNumber,
    required this.isSelected,
  });

  final String id;
  final String name;
  final String questionnaireVersionId;
  final int questionnaireVersionNumber;
  final bool isSelected;
}

/// 首页可渲染的不可变状态。
final class ProductionHomeViewState {
  ProductionHomeViewState({
    required this.isLoading,
    required this.isSynchronizing,
    required this.loadFailed,
    required this.syncFailed,
    required this.today,
    required this.recentSevenDays,
    required this.contacts,
    required this.interestRatioTrend,
    required this.interestRatioTrendIsLoading,
    required this.interestRatioTrendLoadFailed,
    required this.currentRelationshipStage,
    required this.relationshipStageIsLoading,
    required this.relationshipStageLoadFailed,
    required List<ProductionHomeProjectOption> projectOptions,
    required this.notice,
  }) : projectOptions = List.unmodifiable(projectOptions);

  ProductionHomeViewState.initial({
    required List<ProductionHomeProjectOption> projectOptions,
    required this.relationshipStageIsLoading,
    required this.interestRatioTrendIsLoading,
  }) : isLoading = true,
       isSynchronizing = false,
       loadFailed = false,
       syncFailed = false,
       today = null,
       recentSevenDays = null,
       contacts = null,
       interestRatioTrend = null,
       interestRatioTrendLoadFailed = false,
       currentRelationshipStage = null,
       relationshipStageLoadFailed = false,
       projectOptions = List.unmodifiable(projectOptions),
       notice = null;

  final bool isLoading;
  final bool isSynchronizing;
  final bool loadFailed;
  final bool syncFailed;
  final PersonalSummarySnapshot? today;
  final PersonalSummarySnapshot? recentSevenDays;
  final ContactOverviewSnapshot? contacts;
  final PersonalInterestRatioTrendComparison? interestRatioTrend;
  final bool interestRatioTrendIsLoading;
  final bool interestRatioTrendLoadFailed;
  final CurrentRelationshipStageRepositorySuccess? currentRelationshipStage;
  final bool relationshipStageIsLoading;
  final bool relationshipStageLoadFailed;
  final List<ProductionHomeProjectOption> projectOptions;
  final ProductionHomeNotice? notice;

  ProductionHomeViewState copyWith({
    bool? isLoading,
    bool? isSynchronizing,
    bool? loadFailed,
    bool? syncFailed,
    PersonalSummarySnapshot? today,
    PersonalSummarySnapshot? recentSevenDays,
    ContactOverviewSnapshot? contacts,
    PersonalInterestRatioTrendComparison? interestRatioTrend,
    bool? interestRatioTrendIsLoading,
    bool? interestRatioTrendLoadFailed,
    CurrentRelationshipStageRepositorySuccess? currentRelationshipStage,
    bool? relationshipStageIsLoading,
    bool? relationshipStageLoadFailed,
    ProductionHomeNotice? notice,
    bool clearNotice = false,
    bool clearInterestRatioTrend = false,
    bool clearCurrentRelationshipStage = false,
  }) {
    return ProductionHomeViewState(
      isLoading: isLoading ?? this.isLoading,
      isSynchronizing: isSynchronizing ?? this.isSynchronizing,
      loadFailed: loadFailed ?? this.loadFailed,
      syncFailed: syncFailed ?? this.syncFailed,
      today: today ?? this.today,
      recentSevenDays: recentSevenDays ?? this.recentSevenDays,
      contacts: contacts ?? this.contacts,
      interestRatioTrend: clearInterestRatioTrend
          ? null
          : interestRatioTrend ?? this.interestRatioTrend,
      interestRatioTrendIsLoading:
          interestRatioTrendIsLoading ?? this.interestRatioTrendIsLoading,
      interestRatioTrendLoadFailed:
          interestRatioTrendLoadFailed ?? this.interestRatioTrendLoadFailed,
      currentRelationshipStage: clearCurrentRelationshipStage
          ? null
          : currentRelationshipStage ?? this.currentRelationshipStage,
      relationshipStageIsLoading:
          relationshipStageIsLoading ?? this.relationshipStageIsLoading,
      relationshipStageLoadFailed:
          relationshipStageLoadFailed ?? this.relationshipStageLoadFailed,
      projectOptions: projectOptions,
      notice: clearNotice ? null : notice ?? this.notice,
    );
  }
}

/// 首页切换或创建项目所需的最小会话接口。
abstract interface class ProductionHomeSessionActions {
  Future<bool> selectProject(String projectId);

  Future<bool> createPersonalProject(String displayName);
}

/// 把 [AppSession] 的结果类型收窄为首页需要的成功或失败。
final class AppSessionProductionHomeSessionActions
    implements ProductionHomeSessionActions {
  const AppSessionProductionHomeSessionActions(this._appSession);

  final AppSession _appSession;

  @override
  Future<bool> selectProject(String projectId) async =>
      await _appSession.selectProject(projectId) is SessionContextSuccess;

  @override
  Future<bool> createPersonalProject(String displayName) async =>
      await _appSession.createPersonalProject(displayName)
          is SessionContextSuccess;
}

/// 首页草稿操作需要的最小持久化接口。
abstract interface class ProductionHomeDraftStore {
  Future<void> abandonDraft({
    required String draftId,
    required String appUserId,
    required String deviceId,
  });

  Future<void> undoAbandonDraft({
    required String draftId,
    required String appUserId,
    required String deviceId,
  });
}

/// 把 [ContactJournal] 收窄为首页使用的草稿操作。
final class ContactJournalProductionHomeDraftStore
    implements ProductionHomeDraftStore {
  const ContactJournalProductionHomeDraftStore(this._journal);

  final ContactJournal _journal;

  @override
  Future<void> abandonDraft({
    required String draftId,
    required String appUserId,
    required String deviceId,
  }) => _journal.abandonDraft(
    draftId: draftId,
    appUserId: appUserId,
    deviceId: deviceId,
  );

  @override
  Future<void> undoAbandonDraft({
    required String draftId,
    required String appUserId,
    required String deviceId,
  }) => _journal.undoAbandonDraft(
    draftId: draftId,
    appUserId: appUserId,
    deviceId: deviceId,
  );
}

/// 协调首页同步、草稿操作和可渲染数据。
///
/// Widget 只发送生命周期或用户意图。同步顺序、失败隔离和数据刷新都留在
/// 此模块，因此 Widget 不依赖 [ContactJournal] 或 SyncEngine 的操作细节。
final class ProductionHomeViewModel extends ChangeNotifier {
  factory ProductionHomeViewModel.production({
    required AppSession appSession,
    required TrustedSessionContext context,
    required ContactJournal contactJournal,
    required String deviceId,
    required SyncEngineFactory? syncEngineFactory,
    required CurrentRelationshipStageRepository relationshipStageRepository,
    required DateTime Function() now,
  }) {
    final syncCoordinator = ForegroundSyncCoordinator(
      worker: _syncWorker(syncEngineFactory, context),
    );
    return ProductionHomeViewModel(
      context: context,
      availableContexts: appSession.current.availableContexts,
      deviceId: deviceId,
      sessionActions: AppSessionProductionHomeSessionActions(appSession),
      draftStore: ContactJournalProductionHomeDraftStore(contactJournal),
      overviewRepository: PersonalContactOverviewRepository(
        source: ContactJournalOverviewSource(contactJournal),
        now: now,
        loadSyncHealth: syncCoordinator.health,
      ),
      relationshipStageRepository: relationshipStageRepository,
      syncCoordinator: syncCoordinator,
    );
  }

  factory ProductionHomeViewModel({
    required TrustedSessionContext context,
    required List<TrustedSessionContext> availableContexts,
    required String deviceId,
    required ProductionHomeSessionActions sessionActions,
    required ProductionHomeDraftStore draftStore,
    required PersonalContactOverviewRepository overviewRepository,
    CurrentRelationshipStageRepository? relationshipStageRepository,
    required ForegroundSyncCoordinator syncCoordinator,
  }) => ProductionHomeViewModel._(
    context,
    availableContexts,
    deviceId,
    sessionActions,
    draftStore,
    overviewRepository,
    relationshipStageRepository,
    syncCoordinator,
  );

  ProductionHomeViewModel._(
    this._context,
    List<TrustedSessionContext> availableContexts,
    this._deviceId,
    this._sessionActions,
    this._draftStore,
    this._overviewRepository,
    this._relationshipStageRepository,
    this._syncCoordinator,
  ) : _state = ProductionHomeViewState.initial(
        projectOptions: _projectOptions(availableContexts, _context),
        relationshipStageIsLoading: _relationshipStageRepository != null,
        interestRatioTrendIsLoading:
            _context.workspace.kind == WorkspaceKind.personal,
      );

  final TrustedSessionContext _context;
  final String _deviceId;
  final ProductionHomeSessionActions _sessionActions;
  final ProductionHomeDraftStore _draftStore;
  final PersonalContactOverviewRepository _overviewRepository;
  final CurrentRelationshipStageRepository? _relationshipStageRepository;
  final ForegroundSyncCoordinator _syncCoordinator;

  ProductionHomeViewState _state;
  Future<void>? _activeRefresh;
  var _refreshAgain = false;
  var _nextNoticeId = 0;
  var _disposed = false;

  ProductionHomeViewState get state => _state;

  Future<void> initialize() => _synchronizeAndRefresh();

  Future<void> appResumed() => _synchronizeAndRefresh();

  Future<void> retryInterestRatioTrend() => _synchronizeAndRefresh();

  Future<void> contactPageClosed({required bool submitted}) {
    if (submitted) {
      _publishNotice(ProductionHomeNoticeKind.contactSubmitted);
    }
    return _synchronizeAndRefresh();
  }

  Future<void> contactAttemptRecorded() {
    _publishNotice(ProductionHomeNoticeKind.contactAttemptRecorded);
    return _synchronizeAndRefresh();
  }

  Future<bool> selectProject(String projectId) async {
    if (projectId == _context.project.id) {
      return true;
    }
    return _runProjectChange(() => _sessionActions.selectProject(projectId));
  }

  /// 重新解析当前项目的可信上下文，例如获取刚发布的问卷版本。
  Future<bool> refreshCurrentProject() => _runProjectChange(
    () => _sessionActions.selectProject(_context.project.id),
  );

  Future<bool> createPersonalProject(String displayName) => _runProjectChange(
    () => _sessionActions.createPersonalProject(displayName),
  );

  Future<bool> ensureDraftContext(ContactDraft draft) =>
      selectProject(draft.projectId);

  Future<void> abandonDraft(ContactDraft draft) async {
    try {
      await _draftStore.abandonDraft(
        draftId: draft.draftId,
        appUserId: _context.appUserId,
        deviceId: _deviceId,
      );
      _publishNotice(ProductionHomeNoticeKind.draftAbandoned, draft: draft);
      await _synchronizeAndRefresh();
    } catch (_) {
      _publishNotice(ProductionHomeNoticeKind.draftAbandonFailed);
    }
  }

  Future<void> undoAbandonDraft(ContactDraft draft) async {
    try {
      await _draftStore.undoAbandonDraft(
        draftId: draft.draftId,
        appUserId: _context.appUserId,
        deviceId: _deviceId,
      );
      await _synchronizeAndRefresh();
    } catch (_) {
      _publishNotice(ProductionHomeNoticeKind.draftUndoFailed);
    }
  }

  void clearNotice(int? id) {
    if (id == null || _state.notice?.id != id) {
      return;
    }
    _setState(_state.copyWith(clearNotice: true));
  }

  Future<bool> _runProjectChange(Future<bool> Function() operation) async {
    try {
      final succeeded = await operation();
      if (!succeeded) {
        _publishNotice(ProductionHomeNoticeKind.projectChangeFailed);
      }
      return succeeded;
    } catch (_) {
      _publishNotice(ProductionHomeNoticeKind.projectChangeFailed);
      return false;
    }
  }

  Future<void> _synchronizeAndRefresh() {
    final active = _activeRefresh;
    if (active != null) {
      _refreshAgain = true;
      return active;
    }
    late final Future<void> operation;
    operation = _runUntilSettled().whenComplete(() {
      if (identical(_activeRefresh, operation)) {
        _activeRefresh = null;
      }
    });
    _activeRefresh = operation;
    return operation;
  }

  Future<void> _runUntilSettled() async {
    do {
      _refreshAgain = false;
      await _refreshOnce();
    } while (_refreshAgain && !_disposed);
  }

  Future<void> _refreshOnce() async {
    _setState(
      _state.copyWith(
        isSynchronizing: true,
        loadFailed: false,
        syncFailed: false,
        interestRatioTrendIsLoading:
            _context.workspace.kind == WorkspaceKind.personal,
        interestRatioTrendLoadFailed: false,
        clearInterestRatioTrend: true,
        relationshipStageIsLoading: _relationshipStageRepository != null,
        relationshipStageLoadFailed: false,
      ),
    );

    var syncFailed = false;
    try {
      await _syncCoordinator.synchronize();
    } catch (_) {
      syncFailed = true;
    }

    // Relationship fetch starts after contact sync but does not delay the
    // existing personal summaries. Its panel owns a separate loading state.
    final relationshipStageFuture = _loadRelationshipStage();
    final interestRatioTrendFuture = _loadInterestRatioTrend();

    try {
      final today = await _overviewRepository.loadSummary(
        context: _context,
        period: PersonalSummaryPeriod.today,
      );
      final recentSevenDays = await _overviewRepository.loadSummary(
        context: _context,
        period: PersonalSummaryPeriod.recentSevenDays,
      );
      final contacts = await _overviewRepository.loadContacts(
        context: _context,
      );
      _setState(
        _state.copyWith(
          isLoading: false,
          isSynchronizing: false,
          loadFailed: false,
          syncFailed: syncFailed,
          today: today,
          recentSevenDays: recentSevenDays,
          contacts: contacts,
        ),
      );
    } catch (_) {
      _setState(
        _state.copyWith(
          isLoading: false,
          isSynchronizing: false,
          loadFailed: true,
          syncFailed: syncFailed,
        ),
      );
    }

    final interestRatioTrend = await interestRatioTrendFuture;
    _setState(
      _state.copyWith(
        interestRatioTrendIsLoading: false,
        interestRatioTrendLoadFailed: interestRatioTrend.failed,
        interestRatioTrend: interestRatioTrend.success,
        clearInterestRatioTrend:
            _context.workspace.kind == WorkspaceKind.personal &&
            interestRatioTrend.success == null,
      ),
    );

    final relationshipStage = await relationshipStageFuture;
    _setState(
      _state.copyWith(
        relationshipStageIsLoading: false,
        relationshipStageLoadFailed: relationshipStage.failed,
        currentRelationshipStage: relationshipStage.success,
        clearCurrentRelationshipStage:
            _relationshipStageRepository != null &&
            relationshipStage.success == null,
      ),
    );
  }

  Future<({PersonalInterestRatioTrendComparison? success, bool failed})>
  _loadInterestRatioTrend() async {
    if (_context.workspace.kind != WorkspaceKind.personal) {
      return (success: null, failed: false);
    }
    try {
      final pair = await _overviewRepository.loadAdjacentCompletedSevenDayPair(
        context: _context,
      );
      return (
        success: comparePersonalInterestRatioTrend(
          previous: PersonalInterestRatioTrendObservation(
            scope: pair.scope,
            metric: pair.previous.metric(
              CoreMetricCatalog.interestThreeFourRatio.reference,
            ),
          ),
          current: PersonalInterestRatioTrendObservation(
            scope: pair.scope,
            metric: pair.current.metric(
              CoreMetricCatalog.interestThreeFourRatio.reference,
            ),
          ),
        ),
        failed: false,
      );
    } catch (_) {
      return (success: null, failed: true);
    }
  }

  Future<({CurrentRelationshipStageRepositorySuccess? success, bool failed})>
  _loadRelationshipStage() async {
    final repository = _relationshipStageRepository;
    if (repository == null) return (success: null, failed: false);
    try {
      final result = await repository.load(_context);
      if (result is CurrentRelationshipStageRepositorySuccess) {
        return (success: result, failed: false);
      }
    } catch (_) {
      // The relationship panel reports its own stable failure state.
    }
    return (success: null, failed: true);
  }

  void _publishNotice(ProductionHomeNoticeKind kind, {ContactDraft? draft}) {
    _nextNoticeId++;
    _setState(
      _state.copyWith(
        notice: ProductionHomeNotice(
          id: _nextNoticeId,
          kind: kind,
          draft: draft,
        ),
      ),
    );
  }

  void _setState(ProductionHomeViewState value) {
    if (_disposed) {
      return;
    }
    _state = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _syncCoordinator.dispose();
    super.dispose();
  }

  static ForegroundSyncWorker? _syncWorker(
    SyncEngineFactory? factory,
    TrustedSessionContext context,
  ) {
    final engine = factory?.create(context);
    return engine == null ? null : SyncEngineForegroundWorker(engine);
  }

  static List<ProductionHomeProjectOption> _projectOptions(
    List<TrustedSessionContext> availableContexts,
    TrustedSessionContext selectedContext,
  ) {
    return [
      for (final available in availableContexts)
        ProductionHomeProjectOption(
          id: available.project.id,
          name: available.project.name,
          questionnaireVersionId: available.questionnaireVersion.id,
          questionnaireVersionNumber:
              available.questionnaireVersion.versionNumber,
          isSelected: available.project.id == selectedContext.project.id,
        ),
    ];
  }
}
