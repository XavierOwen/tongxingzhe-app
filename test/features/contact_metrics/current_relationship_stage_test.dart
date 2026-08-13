import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/features/contact_metrics/current_relationship_stage.dart';
import 'package:tongxingzhe_app/features/contact_metrics/metric_contract.dart';

void main() {
  final scope = CurrentRelationshipStageScope(
    appUserId: 'user-1',
    workspaceId: 'workspace-1',
    projectId: 'project-1',
  );

  test(
    'current snapshot allows a valid empty known result without a period',
    () {
      final snapshot = CurrentRelationshipStageSnapshot(
        scope: scope,
        snapshotAsOfUtc: DateTime.utc(2030, 1, 15, 12),
        coverage: CurrentRelationshipStageCoverage.known(
          totalCount: 0,
          pendingCount: 0,
        ),
        rows: const [],
      );

      expect(snapshot.stageCounts, [0, 0, 0, 0, 0]);
      final result = snapshot.toMetricResult();
      expect(result.snapshotAsOfUtc, DateTime.utc(2030, 1, 15, 12));
      expect(result.value, isA<MetricDistributionValue>());
      expect(result.syncCoverage!.totalCount, 0);
      expect(result.syncCoverage!.pendingCount, 0);
    },
  );

  test('unknown coverage remains unknown and does not become zero', () {
    final snapshot = CurrentRelationshipStageSnapshot(
      scope: scope,
      snapshotAsOfUtc: DateTime.utc(2030, 1, 15, 12),
      coverage: const CurrentRelationshipStageCoverage.unknown(),
      rows: const [],
    );

    expect(snapshot.coverage.totalCount, isNull);
    expect(snapshot.toMetricResult().syncCoverage!.totalCount, isNull);
    expect(snapshot.toMetricResult().syncCoverage!.pendingCount, isNull);
  });

  test('copyWith preserves snapshot invariants', () {
    final snapshot = CurrentRelationshipStageSnapshot(
      scope: scope,
      snapshotAsOfUtc: DateTime.utc(2030, 1, 15, 12),
      coverage: CurrentRelationshipStageCoverage.known(
        totalCount: 0,
        pendingCount: 0,
      ),
      rows: const [],
    );

    expect(
      () => snapshot.copyWith(
        coverage: CurrentRelationshipStageCoverage.known(
          totalCount: 1,
          pendingCount: 0,
        ),
      ),
      throwsArgumentError,
    );
  });

  test(
    'duplicate target-project rows and rows newer than snapshot fail closed',
    () {
      CurrentRelationshipStageRow row({
        required int stage,
        String target = 't-1',
      }) => CurrentRelationshipStageRow(
        targetId: target,
        relationshipProjectId: scope.projectId,
        assignedAppUserId: scope.appUserId,
        stage: stage,
        currentRevision: 1,
        updatedAtUtc: DateTime.utc(2030, 1, 15, 11),
      );

      expect(
        () => CurrentRelationshipStageSnapshot(
          scope: scope,
          snapshotAsOfUtc: DateTime.utc(2030, 1, 15, 12),
          coverage: CurrentRelationshipStageCoverage.known(
            totalCount: 2,
            pendingCount: 0,
          ),
          rows: [row(stage: 0), row(stage: 4)],
        ),
        throwsArgumentError,
      );
      expect(
        () => CurrentRelationshipStageSnapshot(
          scope: scope,
          snapshotAsOfUtc: DateTime.utc(2030, 1, 15, 12),
          coverage: CurrentRelationshipStageCoverage.known(
            totalCount: 1,
            pendingCount: 0,
          ),
          rows: [
            CurrentRelationshipStageRow(
              targetId: 't-2',
              relationshipProjectId: scope.projectId,
              assignedAppUserId: scope.appUserId,
              stage: 1,
              currentRevision: 2,
              updatedAtUtc: DateTime.utc(2030, 1, 15, 12, 1),
            ),
          ],
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'repository serves stale cache on network failure and clears auth failures',
    () async {
      final snapshot = CurrentRelationshipStageSnapshot(
        scope: scope,
        snapshotAsOfUtc: DateTime.utc(2030, 1, 15, 12),
        coverage: CurrentRelationshipStageCoverage.known(
          totalCount: 0,
          pendingCount: 0,
        ),
        rows: const [],
        freshness: const MetricSourceFreshness.fresh(),
      );
      final store = _FakeStore(snapshot);
      final gateway = _FakeGateway(
        const CurrentRelationshipStageGatewayRejected(
          CurrentRelationshipStageGatewayFailureCode.networkUnavailable,
        ),
      );
      final repository = CurrentRelationshipStageRepository(
        gateway: gateway,
        store: store,
      );

      final cached = await repository.loadForScope(scope);
      expect(cached, isA<CurrentRelationshipStageRepositorySuccess>());
      final cachedSuccess = cached as CurrentRelationshipStageRepositorySuccess;
      expect(cachedSuccess.fromOfflineCache, isTrue);
      expect(
        cachedSuccess.snapshot.freshness.status,
        MetricFreshnessStatus.stale,
      );

      gateway.result = const CurrentRelationshipStageGatewayRejected(
        CurrentRelationshipStageGatewayFailureCode.unauthorized,
      );
      final rejected = await repository.loadForScope(scope);
      expect(rejected, isA<CurrentRelationshipStageRepositoryRejected>());
      expect(store.clearedScopes, [scope]);
    },
  );
}

final class _FakeGateway implements CurrentRelationshipStageGateway {
  _FakeGateway(this.result);

  CurrentRelationshipStageGatewayResult result;

  @override
  Future<void> close() async {}

  @override
  Future<CurrentRelationshipStageGatewayResult> load({
    required CurrentRelationshipStageScope scope,
  }) async => result;
}

final class _FakeStore implements CurrentRelationshipStageSnapshotStore {
  _FakeStore(this.snapshot);

  CurrentRelationshipStageSnapshot? snapshot;
  final List<CurrentRelationshipStageScope> clearedScopes = [];

  @override
  Future<void> clear({required CurrentRelationshipStageScope scope}) async {
    clearedScopes.add(scope);
    snapshot = null;
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
