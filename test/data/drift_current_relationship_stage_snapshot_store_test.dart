import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/data/drift_current_relationship_stage_snapshot_store.dart';
import 'package:tongxingzhe_app/data/local_database.dart';
import 'package:tongxingzhe_app/features/contact_metrics/current_relationship_stage.dart';
import 'package:tongxingzhe_app/features/contact_metrics/metric_contract.dart';

void main() {
  late LocalDatabase database;
  late DriftCurrentRelationshipStageSnapshotStore store;

  setUp(() {
    database = LocalDatabase(NativeDatabase.memory());
    store = DriftCurrentRelationshipStageSnapshotStore(database);
  });

  tearDown(() => database.close());

  test('原子保存并读取按稳定对象键排序的完整快照', () async {
    final snapshot = _snapshot(_primaryScope, stages: [4, 0, 2]);

    await store.replace(snapshot);

    final cached = await store.read(scope: _primaryScope);
    expect(cached, isNotNull);
    expect(cached!.rows.map((row) => row.targetId), [
      'target-0',
      'target-2',
      'target-4',
    ]);
    expect(cached.stageCounts, [1, 0, 1, 0, 1]);
    expect(cached.coverage.totalCount, 3);
    expect(cached.coverage.pendingCount, 0);
    expect(cached.freshness.status, MetricFreshnessStatus.fresh);
    expect(cached.sourceDataCutoffUtc, DateTime.utc(2030, 1, 15, 11, 55));
  });

  test('有效空快照删除旧投影但保留快照元数据', () async {
    await store.replace(_snapshot(_primaryScope, stages: [1, 3]));
    final empty = _snapshot(
      _primaryScope,
      stages: const [],
      snapshotAsOfUtc: DateTime.utc(2030, 1, 16, 12),
    );

    await store.replace(empty);

    final cached = await store.read(scope: _primaryScope);
    expect(cached, isNotNull);
    expect(cached!.rows, isEmpty);
    expect(cached.stageCounts, [0, 0, 0, 0, 0]);
    expect(cached.coverage.totalCount, 0);
    expect(cached.snapshotAsOfUtc, DateTime.utc(2030, 1, 16, 12));
  });

  test('范围替换与授权清理不会触碰其他账号项目', () async {
    await store.replace(_snapshot(_primaryScope, stages: [1]));
    await store.replace(_snapshot(_otherScope, stages: [3]));

    await store.clear(scope: _primaryScope);

    expect(await store.read(scope: _primaryScope), isNull);
    final other = await store.read(scope: _otherScope);
    expect(other, isNotNull);
    expect(other!.stageCounts, [0, 0, 0, 1, 0]);
  });

  test('不完整元数据不能覆盖上一份可审计快照', () async {
    await store.replace(_snapshot(_primaryScope, stages: [2]));
    final uncacheable = CurrentRelationshipStageSnapshot(
      scope: _primaryScope,
      snapshotAsOfUtc: DateTime.utc(2030, 1, 16, 12),
      rows: [
        CurrentRelationshipStageRow(
          targetId: 'target-4',
          relationshipProjectId: _primaryScope.projectId,
          assignedAppUserId: _primaryScope.appUserId,
          stage: 4,
          currentRevision: 1,
          updatedAtUtc: DateTime.utc(2030, 1, 16, 11),
        ),
      ],
    );

    await expectLater(
      store.replace(uncacheable),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'current_relationship_stage_snapshot_not_cacheable',
        ),
      ),
    );

    final cached = await store.read(scope: _primaryScope);
    expect(cached!.stageCounts, [0, 0, 1, 0, 0]);
  });
}

final _primaryScope = CurrentRelationshipStageScope(
  appUserId: 'app-user-1',
  workspaceId: 'workspace-1',
  projectId: 'project-1',
);

final _otherScope = CurrentRelationshipStageScope(
  appUserId: 'app-user-2',
  workspaceId: 'workspace-1',
  projectId: 'project-2',
);

CurrentRelationshipStageSnapshot _snapshot(
  CurrentRelationshipStageScope scope, {
  required List<int> stages,
  DateTime? snapshotAsOfUtc,
}) {
  final asOf = snapshotAsOfUtc ?? DateTime.utc(2030, 1, 15, 12);
  final sourceCutoff = asOf.subtract(const Duration(minutes: 5));
  final authorizedAt = asOf.subtract(const Duration(minutes: 1));
  final syncedAt = asOf.add(const Duration(minutes: 1));
  return CurrentRelationshipStageSnapshot(
    scope: scope,
    snapshotAsOfUtc: asOf,
    sourceDataCutoffUtc: sourceCutoff,
    authorizedAtUtc: authorizedAt,
    lastSuccessfulSyncAtUtc: syncedAt,
    coverage: CurrentRelationshipStageCoverage.known(
      totalCount: stages.length,
      pendingCount: 0,
    ),
    rows: [
      for (final stage in stages)
        CurrentRelationshipStageRow(
          targetId: 'target-$stage',
          relationshipProjectId: scope.projectId,
          assignedAppUserId: scope.appUserId,
          stage: stage,
          currentRevision: stage + 1,
          updatedAtUtc: asOf.subtract(Duration(minutes: stage + 1)),
        ),
    ],
    freshness: MetricSourceFreshness.fresh(
      sourceDataCutoffUtc: sourceCutoff,
      authorizedAtUtc: authorizedAt,
      lastSuccessfulSyncAtUtc: syncedAt,
    ),
  );
}
