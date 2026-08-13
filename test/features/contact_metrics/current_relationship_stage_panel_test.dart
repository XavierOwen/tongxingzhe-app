import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/features/contact_metrics/current_relationship_stage.dart';
import 'package:tongxingzhe_app/features/contact_metrics/current_relationship_stage_panel.dart';
import 'package:tongxingzhe_app/features/contact_metrics/metric_contract.dart';
import 'package:tongxingzhe_app/l10n/app_strings.dart';

void main() {
  testWidgets('320 px 与 200% 字号显示五档且没有溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 900),
          textScaler: TextScaler.linear(2),
        ),
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CurrentRelationshipStagePanel(
                text: const AppStrings('zh'),
                result: CurrentRelationshipStageRepositorySuccess(_snapshot()),
                isLoading: false,
                loadFailed: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('当前关系阶段'), findsOneWidget);
    expect(find.bySemanticsLabel('关系阶段 2：1 个对象项目关系'), findsOneWidget);
    expect(find.bySemanticsLabel('关系阶段 4：1 个对象项目关系'), findsOneWidget);
    expect(find.textContaining('同步覆盖：2/2'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('离线缓存明确标为旧快照', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CurrentRelationshipStagePanel(
            text: const AppStrings('zh'),
            result: CurrentRelationshipStageRepositorySuccess(
              _snapshot(
                freshness: MetricSourceFreshness.stale(
                  sourceDataCutoffUtc: DateTime.utc(2030, 1, 15, 11, 55),
                  authorizedAtUtc: DateTime.utc(2030, 1, 15, 11, 59),
                  lastSuccessfulSyncAtUtc: DateTime.utc(2030, 1, 15, 12, 1),
                ),
              ),
              fromOfflineCache: true,
            ),
            isLoading: false,
            loadFailed: false,
          ),
        ),
      ),
    );

    expect(find.textContaining('离线旧快照'), findsOneWidget);
    expect(find.textContaining('最新取得'), findsNothing);
  });
}

CurrentRelationshipStageSnapshot _snapshot({MetricSourceFreshness? freshness}) {
  final scope = CurrentRelationshipStageScope(
    appUserId: 'app-user-1',
    workspaceId: 'workspace-1',
    projectId: 'project-1',
  );
  return CurrentRelationshipStageSnapshot(
    scope: scope,
    snapshotAsOfUtc: DateTime.utc(2030, 1, 15, 12),
    sourceDataCutoffUtc: DateTime.utc(2030, 1, 15, 11, 55),
    authorizedAtUtc: DateTime.utc(2030, 1, 15, 11, 59),
    lastSuccessfulSyncAtUtc: DateTime.utc(2030, 1, 15, 12, 1),
    coverage: CurrentRelationshipStageCoverage.known(
      totalCount: 2,
      pendingCount: 0,
    ),
    rows: [
      CurrentRelationshipStageRow(
        targetId: 'target-2',
        relationshipProjectId: scope.projectId,
        assignedAppUserId: scope.appUserId,
        stage: 2,
        currentRevision: 1,
        updatedAtUtc: DateTime.utc(2030, 1, 14),
      ),
      CurrentRelationshipStageRow(
        targetId: 'target-4',
        relationshipProjectId: scope.projectId,
        assignedAppUserId: scope.appUserId,
        stage: 4,
        currentRevision: 2,
        updatedAtUtc: DateTime.utc(2030, 1, 15, 10),
      ),
    ],
    freshness:
        freshness ??
        MetricSourceFreshness.fresh(
          sourceDataCutoffUtc: DateTime.utc(2030, 1, 15, 11, 55),
          authorizedAtUtc: DateTime.utc(2030, 1, 15, 11, 59),
          lastSuccessfulSyncAtUtc: DateTime.utc(2030, 1, 15, 12, 1),
        ),
  );
}
