import '../../app_session/session_context_gateway.dart';
import 'metric_contract.dart';

/// 当前关系快照使用的生命周期状态。只有 [active] 关系进入五档分布。
enum CurrentRelationshipLifecycleStatus { active, paused, ended }

/// 当前关系投影中对象的隐私状态。
enum CurrentRelationshipTargetStatus { active, anonymized }

/// 查看者对当前关系的分配状态。
enum CurrentRelationshipAssignmentStatus { active, ended }

// 这些别名让领域代码可以使用更短的名称，同时不把它们误用成推广对象资料。
typedef RelationshipLifecycleStatus = CurrentRelationshipLifecycleStatus;
typedef RelationshipTargetStatus = CurrentRelationshipTargetStatus;
typedef RelationshipAssignmentStatus = CurrentRelationshipAssignmentStatus;

/// 6AC 的显式查询边界。
final class CurrentRelationshipStageScope {
  factory CurrentRelationshipStageScope({
    required String appUserId,
    required String workspaceId,
    required String projectId,
  }) {
    final user = _scopeId(appUserId, 'app_user_id');
    final workspace = _scopeId(workspaceId, 'workspace_id');
    final project = _scopeId(projectId, 'project_id');
    return CurrentRelationshipStageScope._(user, workspace, project);
  }

  factory CurrentRelationshipStageScope.fromContext(
    TrustedSessionContext context,
  ) => CurrentRelationshipStageScope(
    appUserId: context.appUserId,
    workspaceId: context.workspace.id,
    projectId: context.project.id,
  );

  const CurrentRelationshipStageScope._(
    this.appUserId,
    this.workspaceId,
    this.projectId,
  );

  final String appUserId;
  final String workspaceId;
  final String projectId;

  @override
  bool operator ==(Object other) =>
      other is CurrentRelationshipStageScope &&
      other.appUserId == appUserId &&
      other.workspaceId == workspaceId &&
      other.projectId == projectId;

  @override
  int get hashCode => Object.hash(appUserId, workspaceId, projectId);
}

/// 不含姓名、联系方式、备注或历史的最小关系投影行。
final class CurrentRelationshipStageRow {
  factory CurrentRelationshipStageRow({
    required String targetId,
    String? relationshipProjectId,
    String? projectId,
    required String assignedAppUserId,
    required int stage,
    CurrentRelationshipLifecycleStatus lifecycleStatus =
        CurrentRelationshipLifecycleStatus.active,
    CurrentRelationshipTargetStatus targetStatus =
        CurrentRelationshipTargetStatus.active,
    CurrentRelationshipAssignmentStatus assignmentStatus =
        CurrentRelationshipAssignmentStatus.active,
    required int currentRevision,
    required DateTime updatedAtUtc,
  }) {
    final relationshipProject = _scopeId(
      relationshipProjectId ?? projectId,
      'relationship_project_id',
    );
    if (targetId.trim().isEmpty ||
        assignedAppUserId.trim().isEmpty ||
        stage < 0 ||
        stage > 4 ||
        currentRevision < 1 ||
        !updatedAtUtc.isUtc) {
      throw ArgumentError('invalid_current_relationship_stage_row');
    }
    if (relationshipProjectId != null &&
        projectId != null &&
        relationshipProjectId != projectId) {
      throw ArgumentError('relationship_project_id_mismatch');
    }
    return CurrentRelationshipStageRow._(
      targetId: targetId.trim(),
      relationshipProjectId: relationshipProject,
      assignedAppUserId: assignedAppUserId.trim(),
      stage: stage,
      lifecycleStatus: lifecycleStatus,
      targetStatus: targetStatus,
      assignmentStatus: assignmentStatus,
      currentRevision: currentRevision,
      updatedAtUtc: updatedAtUtc,
    );
  }

  const CurrentRelationshipStageRow._({
    required this.targetId,
    required this.relationshipProjectId,
    required this.assignedAppUserId,
    required this.stage,
    required this.lifecycleStatus,
    required this.targetStatus,
    required this.assignmentStatus,
    required this.currentRevision,
    required this.updatedAtUtc,
  });

  final String targetId;
  final String relationshipProjectId;
  final String assignedAppUserId;
  final int stage;
  final CurrentRelationshipLifecycleStatus lifecycleStatus;
  final CurrentRelationshipTargetStatus targetStatus;
  final CurrentRelationshipAssignmentStatus assignmentStatus;
  final int currentRevision;
  final DateTime updatedAtUtc;

  /// 兼容读取代码中更短的项目字段名；它仍然表示关系所属项目。
  String get projectId => relationshipProjectId;

  bool isEligibleFor(CurrentRelationshipStageScope scope) =>
      relationshipProjectId == scope.projectId &&
      assignedAppUserId == scope.appUserId &&
      lifecycleStatus == CurrentRelationshipLifecycleStatus.active &&
      targetStatus == CurrentRelationshipTargetStatus.active &&
      assignmentStatus == CurrentRelationshipAssignmentStatus.active;
}

enum CurrentRelationshipStageCoverageStatus { known, unknown }

/// 当前投影的同步覆盖；未知时不允许以 0 代替未知数量。
final class CurrentRelationshipStageCoverage {
  factory CurrentRelationshipStageCoverage({
    required CurrentRelationshipStageCoverageStatus status,
    int? totalCount,
    int? pendingCount,
  }) {
    if (status == CurrentRelationshipStageCoverageStatus.known) {
      if (totalCount == null ||
          pendingCount == null ||
          totalCount < 0 ||
          pendingCount < 0 ||
          pendingCount > totalCount) {
        throw ArgumentError('invalid_known_relationship_stage_coverage');
      }
    } else if (totalCount != null || pendingCount != null) {
      throw ArgumentError('unknown_relationship_stage_coverage_must_be_null');
    }
    return CurrentRelationshipStageCoverage._(
      status: status,
      totalCount: totalCount,
      pendingCount: pendingCount,
    );
  }

  factory CurrentRelationshipStageCoverage.known({
    required int totalCount,
    required int pendingCount,
  }) => CurrentRelationshipStageCoverage(
    status: CurrentRelationshipStageCoverageStatus.known,
    totalCount: totalCount,
    pendingCount: pendingCount,
  );

  const CurrentRelationshipStageCoverage.unknown()
    : this._(
        status: CurrentRelationshipStageCoverageStatus.unknown,
        totalCount: null,
        pendingCount: null,
      );

  const CurrentRelationshipStageCoverage._({
    required this.status,
    required this.totalCount,
    required this.pendingCount,
  });

  final CurrentRelationshipStageCoverageStatus status;
  final int? totalCount;
  final int? pendingCount;

  bool get isKnown => status == CurrentRelationshipStageCoverageStatus.known;

  int? get synchronizedCount => isKnown ? totalCount! - pendingCount! : null;

  MetricSyncCoverage toMetricCoverage() => isKnown
      ? MetricSyncCoverage(
          statisticalUnit: MetricStatisticalUnit.targetProjectRelationship,
          totalCount: totalCount!,
          pendingCount: pendingCount!,
        )
      : MetricSyncCoverage.unknown(
          statisticalUnit: MetricStatisticalUnit.targetProjectRelationship,
        );
}

/// 一次一致性读取返回的当前关系投影。
final class CurrentRelationshipStageSnapshot {
  factory CurrentRelationshipStageSnapshot({
    String? appUserId,
    String? workspaceId,
    String? projectId,
    CurrentRelationshipStageScope? scope,
    required DateTime snapshotAsOfUtc,
    DateTime? sourceDataCutoffUtc,
    DateTime? authorizedAtUtc,
    DateTime? lastSuccessfulSyncAtUtc,
    CurrentRelationshipStageCoverage coverage =
        const CurrentRelationshipStageCoverage.unknown(),
    required List<CurrentRelationshipStageRow> rows,
    MetricSourceFreshness freshness = const MetricSourceFreshness.unknown(),
  }) {
    final resolvedScope =
        scope ??
        CurrentRelationshipStageScope(
          appUserId: appUserId ?? '',
          workspaceId: workspaceId ?? '',
          projectId: projectId ?? '',
        );
    if (appUserId != null && appUserId != resolvedScope.appUserId ||
        workspaceId != null && workspaceId != resolvedScope.workspaceId ||
        projectId != null && projectId != resolvedScope.projectId ||
        !snapshotAsOfUtc.isUtc ||
        sourceDataCutoffUtc != null && !sourceDataCutoffUtc.isUtc ||
        authorizedAtUtc != null && !authorizedAtUtc.isUtc ||
        lastSuccessfulSyncAtUtc != null && !lastSuccessfulSyncAtUtc.isUtc ||
        sourceDataCutoffUtc != null &&
            sourceDataCutoffUtc.isAfter(snapshotAsOfUtc)) {
      throw ArgumentError('invalid_current_relationship_stage_snapshot');
    }

    final immutableRows = List<CurrentRelationshipStageRow>.unmodifiable(rows);
    final keys = <String>{};
    for (final row in immutableRows) {
      if (!row.isEligibleFor(resolvedScope) ||
          row.updatedAtUtc.isAfter(snapshotAsOfUtc) ||
          !keys.add('${row.targetId}\u0000${row.relationshipProjectId}')) {
        throw ArgumentError('invalid_current_relationship_stage_projection');
      }
    }
    if (coverage.isKnown && coverage.totalCount != immutableRows.length) {
      throw ArgumentError('relationship_stage_coverage_total_mismatch');
    }
    if (freshness.sourceDataCutoffUtc != null &&
        sourceDataCutoffUtc != null &&
        freshness.sourceDataCutoffUtc != sourceDataCutoffUtc) {
      throw ArgumentError('relationship_stage_freshness_cutoff_mismatch');
    }
    return CurrentRelationshipStageSnapshot._(
      scope: resolvedScope,
      snapshotAsOfUtc: snapshotAsOfUtc,
      sourceDataCutoffUtc: sourceDataCutoffUtc,
      authorizedAtUtc: authorizedAtUtc,
      lastSuccessfulSyncAtUtc: lastSuccessfulSyncAtUtc,
      coverage: coverage,
      rows: immutableRows,
      freshness: freshness,
    );
  }

  const CurrentRelationshipStageSnapshot._({
    required this.scope,
    required this.snapshotAsOfUtc,
    required this.sourceDataCutoffUtc,
    required this.authorizedAtUtc,
    required this.lastSuccessfulSyncAtUtc,
    required this.coverage,
    required this.rows,
    required this.freshness,
  });

  final CurrentRelationshipStageScope scope;
  final DateTime snapshotAsOfUtc;
  final DateTime? sourceDataCutoffUtc;
  final DateTime? authorizedAtUtc;
  final DateTime? lastSuccessfulSyncAtUtc;
  final CurrentRelationshipStageCoverage coverage;
  final List<CurrentRelationshipStageRow> rows;
  final MetricSourceFreshness freshness;

  String get appUserId => scope.appUserId;
  String get workspaceId => scope.workspaceId;
  String get projectId => scope.projectId;

  List<int> get stageCounts {
    final counts = List<int>.filled(5, 0);
    for (final row in rows) {
      counts[row.stage] += 1;
    }
    return List.unmodifiable(counts);
  }

  CurrentRelationshipStageSnapshot copyWith({
    MetricSourceFreshness? freshness,
    CurrentRelationshipStageCoverage? coverage,
  }) => CurrentRelationshipStageSnapshot(
    scope: scope,
    snapshotAsOfUtc: snapshotAsOfUtc,
    sourceDataCutoffUtc: sourceDataCutoffUtc,
    authorizedAtUtc: authorizedAtUtc,
    lastSuccessfulSyncAtUtc: lastSuccessfulSyncAtUtc,
    coverage: coverage ?? this.coverage,
    rows: rows,
    freshness: freshness ?? this.freshness,
  );

  CurrentSnapshotMetricResult toMetricResult() => MetricResult.currentSnapshot(
    definition: CoreMetricCatalog.currentRelationshipStageDistribution,
    value: MetricDistributionValue(
      labels:
          CoreMetricCatalog.currentRelationshipStageDistribution.bucketLabels,
      counts: stageCounts,
    ),
    snapshotAsOfUtc: snapshotAsOfUtc,
    timeZone: 'UTC',
    sourceDataCutoffUtc: sourceDataCutoffUtc,
    freshness: freshness,
    sourceTier: MetricSourceTier.localOperational,
    syncCoverage: coverage.toMetricCoverage(),
    privacyStatus: MetricPrivacyStatus.personalFact,
  );
}

/// 可替换的离线快照存储边界；实现不得读取或解密 PII vault。
abstract interface class CurrentRelationshipStageSnapshotStore {
  Future<CurrentRelationshipStageSnapshot?> read({
    required CurrentRelationshipStageScope scope,
  });

  Future<void> replace(CurrentRelationshipStageSnapshot snapshot);

  Future<void> clear({required CurrentRelationshipStageScope scope});
}

enum CurrentRelationshipStageGatewayFailureCode {
  notConfigured,
  unauthorized,
  forbidden,
  networkUnavailable,
  invalidResponse,
  serverRejected,
}

sealed class CurrentRelationshipStageGatewayResult {
  const CurrentRelationshipStageGatewayResult();
}

final class CurrentRelationshipStageGatewaySuccess
    extends CurrentRelationshipStageGatewayResult {
  const CurrentRelationshipStageGatewaySuccess(this.snapshot);

  final CurrentRelationshipStageSnapshot snapshot;
}

final class CurrentRelationshipStageGatewayRejected
    extends CurrentRelationshipStageGatewayResult {
  const CurrentRelationshipStageGatewayRejected(this.code);

  final CurrentRelationshipStageGatewayFailureCode code;
}

/// 个人当前关系快照的远端读取边界。
abstract interface class CurrentRelationshipStageGateway {
  Future<CurrentRelationshipStageGatewayResult> load({
    required CurrentRelationshipStageScope scope,
  });

  Future<void> close();
}

sealed class CurrentRelationshipStageRepositoryResult {
  const CurrentRelationshipStageRepositoryResult();
}

final class CurrentRelationshipStageRepositorySuccess
    extends CurrentRelationshipStageRepositoryResult {
  const CurrentRelationshipStageRepositorySuccess(
    this.snapshot, {
    this.fromOfflineCache = false,
  });

  final CurrentRelationshipStageSnapshot snapshot;
  final bool fromOfflineCache;

  CurrentSnapshotMetricResult get metric => snapshot.toMetricResult();
}

final class CurrentRelationshipStageRepositoryRejected
    extends CurrentRelationshipStageRepositoryResult {
  const CurrentRelationshipStageRepositoryRejected(this.code);

  final CurrentRelationshipStageGatewayFailureCode code;
}

/// 在线优先、网络失败回退本地快照的窄仓储。
final class CurrentRelationshipStageRepository {
  const CurrentRelationshipStageRepository({
    required CurrentRelationshipStageGateway gateway,
    required CurrentRelationshipStageSnapshotStore store,
  }) : this._(gateway, store);

  const CurrentRelationshipStageRepository._(this._gateway, this._store);

  final CurrentRelationshipStageGateway _gateway;
  final CurrentRelationshipStageSnapshotStore _store;

  Future<CurrentRelationshipStageRepositoryResult> load(
    TrustedSessionContext context,
  ) => loadForScope(CurrentRelationshipStageScope.fromContext(context));

  Future<CurrentRelationshipStageRepositoryResult> loadForScope(
    CurrentRelationshipStageScope scope,
  ) async {
    final result = await _gateway.load(scope: scope);
    switch (result) {
      case CurrentRelationshipStageGatewaySuccess(:final snapshot):
        if (snapshot.scope != scope) {
          return const CurrentRelationshipStageRepositoryRejected(
            CurrentRelationshipStageGatewayFailureCode.invalidResponse,
          );
        }
        await _store.replace(snapshot);
        return CurrentRelationshipStageRepositorySuccess(snapshot);
      case CurrentRelationshipStageGatewayRejected(:final code):
        if (code ==
            CurrentRelationshipStageGatewayFailureCode.networkUnavailable) {
          final cached = await _store.read(scope: scope);
          if (cached == null) {
            return CurrentRelationshipStageRepositoryRejected(code);
          }
          return CurrentRelationshipStageRepositorySuccess(
            cached.copyWith(
              freshness: MetricSourceFreshness.stale(
                sourceDataCutoffUtc: cached.sourceDataCutoffUtc,
                authorizedAtUtc: cached.authorizedAtUtc,
                lastSuccessfulSyncAtUtc: cached.lastSuccessfulSyncAtUtc,
              ),
            ),
            fromOfflineCache: true,
          );
        }
        if (code == CurrentRelationshipStageGatewayFailureCode.unauthorized ||
            code == CurrentRelationshipStageGatewayFailureCode.forbidden) {
          await _store.clear(scope: scope);
        }
        return CurrentRelationshipStageRepositoryRejected(code);
    }
  }
}

String _scopeId(String? value, String name) {
  final normalized = value?.trim() ?? '';
  if (normalized.isEmpty) throw ArgumentError('invalid_$name');
  return normalized;
}
