import 'package:drift/drift.dart';

import '../features/contact_metrics/current_relationship_stage.dart';
import '../features/contact_metrics/metric_contract.dart';
import 'local_database.dart';

/// 将完整的个人当前关系快照原子安装到 Drift。
///
/// 存储只接受远端成功读取产生的完整元数据。未知覆盖或缺少来源、授权、同步
/// 时刻的结果不能覆盖上一份可审计快照。
final class DriftCurrentRelationshipStageSnapshotStore
    implements CurrentRelationshipStageSnapshotStore {
  const DriftCurrentRelationshipStageSnapshotStore(this._database);

  final LocalDatabase _database;

  @override
  Future<CurrentRelationshipStageSnapshot?> read({
    required CurrentRelationshipStageScope scope,
  }) async {
    final metadataQuery =
        _database.select(_database.dbCurrentRelationshipStageSnapshots)..where(
          (row) =>
              row.appUserId.equals(scope.appUserId) &
              row.workspaceId.equals(scope.workspaceId) &
              row.projectId.equals(scope.projectId),
        );
    final metadata = await metadataQuery.getSingleOrNull();
    if (metadata == null) return null;

    final projectionQuery =
        _database.select(_database.dbCurrentRelationshipStageProjections)
          ..where(
            (row) =>
                row.appUserId.equals(scope.appUserId) &
                row.workspaceId.equals(scope.workspaceId) &
                row.projectId.equals(scope.projectId),
          )
          ..orderBy([(row) => OrderingTerm.asc(row.targetKey)]);
    final projections = await projectionQuery.get();
    return CurrentRelationshipStageSnapshot(
      scope: scope,
      snapshotAsOfUtc: metadata.snapshotAsOfUtc.toUtc(),
      sourceDataCutoffUtc: metadata.sourceCutoffUtc.toUtc(),
      authorizedAtUtc: metadata.authorizedAtUtc.toUtc(),
      lastSuccessfulSyncAtUtc: metadata.lastSuccessfulSyncAtUtc.toUtc(),
      coverage: CurrentRelationshipStageCoverage.known(
        totalCount: metadata.totalCount,
        pendingCount: metadata.pendingSyncCount,
      ),
      rows: [
        for (final projection in projections)
          CurrentRelationshipStageRow(
            targetId: projection.targetKey,
            relationshipProjectId: projection.projectId,
            assignedAppUserId: projection.appUserId,
            stage: projection.relationshipStage,
            currentRevision: projection.relationshipRevision,
            updatedAtUtc: projection.relationshipUpdatedAtUtc.toUtc(),
          ),
      ],
      freshness: MetricSourceFreshness.fresh(
        sourceDataCutoffUtc: metadata.sourceCutoffUtc.toUtc(),
        authorizedAtUtc: metadata.authorizedAtUtc.toUtc(),
        lastSuccessfulSyncAtUtc: metadata.lastSuccessfulSyncAtUtc.toUtc(),
      ),
    );
  }

  @override
  Future<void> replace(CurrentRelationshipStageSnapshot snapshot) async {
    final sourceCutoffUtc = snapshot.sourceDataCutoffUtc;
    final authorizedAtUtc = snapshot.authorizedAtUtc;
    final lastSuccessfulSyncAtUtc = snapshot.lastSuccessfulSyncAtUtc;
    final totalCount = snapshot.coverage.totalCount;
    final pendingSyncCount = snapshot.coverage.pendingCount;
    if (!snapshot.coverage.isKnown ||
        sourceCutoffUtc == null ||
        authorizedAtUtc == null ||
        lastSuccessfulSyncAtUtc == null ||
        totalCount == null ||
        pendingSyncCount == null) {
      throw StateError('current_relationship_stage_snapshot_not_cacheable');
    }

    final scope = snapshot.scope;
    await _database.transaction(() async {
      await _deleteScopeProjections(scope);
      await (_database.delete(_database.dbCurrentRelationshipStageSnapshots)
            ..where(
              (row) =>
                  row.appUserId.equals(scope.appUserId) &
                  row.workspaceId.equals(scope.workspaceId) &
                  row.projectId.equals(scope.projectId),
            ))
          .go();

      for (final row in snapshot.rows) {
        await _database
            .into(_database.dbCurrentRelationshipStageProjections)
            .insert(
              DbCurrentRelationshipStageProjectionsCompanion.insert(
                appUserId: scope.appUserId,
                workspaceId: scope.workspaceId,
                projectId: scope.projectId,
                targetKey: row.targetId,
                relationshipStage: row.stage,
                relationshipRevision: row.currentRevision,
                relationshipUpdatedAtUtc: row.updatedAtUtc,
              ),
            );
      }
      await _database
          .into(_database.dbCurrentRelationshipStageSnapshots)
          .insert(
            DbCurrentRelationshipStageSnapshotsCompanion.insert(
              appUserId: scope.appUserId,
              workspaceId: scope.workspaceId,
              projectId: scope.projectId,
              snapshotAsOfUtc: snapshot.snapshotAsOfUtc,
              sourceCutoffUtc: sourceCutoffUtc,
              authorizedAtUtc: authorizedAtUtc,
              lastSuccessfulSyncAtUtc: lastSuccessfulSyncAtUtc,
              totalCount: totalCount,
              pendingSyncCount: pendingSyncCount,
            ),
          );
    });
  }

  @override
  Future<void> clear({required CurrentRelationshipStageScope scope}) =>
      _database.transaction(() async {
        await _deleteScopeProjections(scope);
        await (_database.delete(_database.dbCurrentRelationshipStageSnapshots)
              ..where(
                (row) =>
                    row.appUserId.equals(scope.appUserId) &
                    row.workspaceId.equals(scope.workspaceId) &
                    row.projectId.equals(scope.projectId),
              ))
            .go();
      });

  Future<void> _deleteScopeProjections(
    CurrentRelationshipStageScope scope,
  ) async {
    await (_database.delete(_database.dbCurrentRelationshipStageProjections)
          ..where(
            (row) =>
                row.appUserId.equals(scope.appUserId) &
                row.workspaceId.equals(scope.workspaceId) &
                row.projectId.equals(scope.projectId),
          ))
        .go();
  }
}
