import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/features/targets/promotion_target_directory_page.dart';
import 'package:tongxingzhe_app/foundation/runtime_values.dart';
import 'package:tongxingzhe_app/l10n/app_strings.dart';
import 'package:tongxingzhe_app/targets/promotion_target.dart';

void main() {
  testWidgets(
    'anonymous contact remains available when the directory is empty',
    (tester) async {
      await tester.pumpWidget(_app(_MemoryGateway()));
      await tester.pumpAndSettle();

      expect(find.text('尚未建立推广对象'), findsOneWidget);
      expect(find.text('不建立对象不会影响记录接触。'), findsOneWidget);
    },
  );

  testWidgets('creation requires an explicit purpose confirmation', (
    tester,
  ) async {
    final gateway = _MemoryGateway();
    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('create-promotion-target')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('promotion-target-name')),
      '王小明',
    );

    var confirm = tester.widget<FilledButton>(
      find.byKey(const ValueKey('confirm-promotion-target')),
    );
    expect(confirm.onPressed, isNull);

    await tester.tap(
      find.byKey(const ValueKey('promotion-target-purpose-confirmed')),
    );
    await tester.pump();
    confirm = tester.widget<FilledButton>(
      find.byKey(const ValueKey('confirm-promotion-target')),
    );
    expect(confirm.onPressed, isNotNull);

    await tester.tap(find.byKey(const ValueKey('confirm-promotion-target')));
    await tester.pumpAndSettle();

    expect(gateway.createdName, '王小明');
    expect(gateway.requestId, 'request-1');
    expect(find.text('王小明'), findsOneWidget);
  });

  testWidgets(
    'current assignee can revise relationship stage and shared note',
    (tester) async {
      final gateway = _MemoryGateway()..targets.add(_targetWithRelationship());
      await tester.pumpWidget(_app(gateway));
      await tester.pumpAndSettle();

      expect(find.textContaining('关系阶段: 明确推进 (6)'), findsOneWidget);
      expect(find.textContaining('共享跟进备注: 下周联系'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('promotion-target-target-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('target-relationship-stage')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('8 · 达成项目目标关系').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('target-follow-up-note')),
        '已约定下次会面',
      );
      await tester.tap(find.byKey(const ValueKey('save-target-relationship')));
      await tester.pumpAndSettle();

      expect(gateway.updatedStage, 4);
      expect(gateway.updatedNote, '已约定下次会面');
      expect(gateway.expectedRevision, 2);
      expect(find.textContaining('关系阶段: 达成项目目标关系 (8)'), findsOneWidget);
    },
  );

  testWidgets('same-field conflict keeps proposal until assignee resolves it', (
    tester,
  ) async {
    final gateway = _MemoryGateway()..targets.add(_targetWithRelationship());
    gateway.conflictOnce = PromotionTargetConflict(
      current: _relationship(stage: 2, revision: 3, note: '服务器备注'),
      conflictId: 'conflict-1',
      conflictingFields: const ['stage', 'follow_up_note'],
      proposed: const PromotionTargetRelationshipProposal(
        expectedRevision: 2,
        stage: 4,
        displayStage: 8,
        lifecycleStatus: PromotionTargetRelationshipLifecycle.active,
        followUpNote: '我的备注',
        reason: PromotionTargetRelationshipReason.progressUpdate,
        reasonDetail: null,
      ),
    );
    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('promotion-target-target-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('target-relationship-stage')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('8 · 达成项目目标关系').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('target-follow-up-note')),
      '我的备注',
    );
    await tester.tap(find.byKey(const ValueKey('save-target-relationship')));
    await tester.pumpAndSettle();

    expect(find.text('需要选择关系版本'), findsOneWidget);
    expect(find.textContaining('服务器备注'), findsWidgets);
    expect(find.textContaining('我的备注'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('apply-proposed-relationship')));
    await tester.pumpAndSettle();

    expect(gateway.resolvedConflictId, 'conflict-1');
    expect(gateway.updatedStage, 4);
    expect(find.textContaining('共享跟进备注: 我的备注'), findsOneWidget);
  });

  testWidgets(
    'assigned user creates and ends an explicit institution relation',
    (tester) async {
      final gateway = _MemoryGateway()
        ..targets.addAll([
          _plainTarget(
            id: 'person-1',
            type: PromotionTargetType.person,
            name: '王小明',
          ),
          _plainTarget(
            id: 'institution-1',
            type: PromotionTargetType.institution,
            name: '社区中心',
          ),
        ]);
      await tester.pumpWidget(_app(gateway));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('create-target-institution-relationship')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('institution-relationship-role')),
        '项目协调员',
      );
      await tester.tap(
        find.byKey(const ValueKey('save-target-institution-relationship')),
      );
      await tester.pumpAndSettle();

      expect(
        gateway.createdInstitutionKind,
        TargetInstitutionRelationshipKind.employmentRepresentative,
      );
      expect(find.text('王小明 ↔ 社区中心'), findsOneWidget);

      await tester.tap(
        find.byKey(
          const ValueKey('end-target-institution-institution-relation-1'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey('confirm-end-target-institution-relationship'),
        ),
      );
      await tester.pumpAndSettle();

      expect(gateway.endedInstitutionRelationshipId, 'institution-relation-1');
      expect(find.textContaining('结束: 2026-08-07'), findsOneWidget);
    },
  );
}

Widget _app(PromotionTargetGateway gateway) => MaterialApp(
  home: Scaffold(
    body: PromotionTargetDirectoryPage(
      text: const AppStrings('zh'),
      gateway: gateway,
      idGenerator: _FixedIds(),
      canCreate: true,
      canConfigureStageAliases: true,
      canManageRelationship: true,
      canManageInstitutionRelationships: true,
    ),
  ),
);

final class _FixedIds implements IdGenerator {
  var _next = 0;

  @override
  String next() => 'request-${++_next}';
}

final class _MemoryGateway implements PromotionTargetGateway {
  final targets = <PromotionTargetProfile>[];
  String? createdName;
  String? requestId;
  int? updatedStage;
  int? expectedRevision;
  String? updatedNote;
  String? resolvedConflictId;
  PromotionTargetConflict<PromotionTargetRelationship>? conflictOnce;
  final institutionRelationships = <TargetInstitutionRelationship>[];
  TargetInstitutionRelationshipKind? createdInstitutionKind;
  String? endedInstitutionRelationshipId;

  @override
  Future<PromotionTargetResult<List<PromotionTargetProfile>>>
  loadAssigned() async => PromotionTargetSuccess(List.of(targets));

  @override
  Future<PromotionTargetResult<PromotionTargetProfile>> create({
    required PromotionTargetType type,
    required String displayName,
    required String? phone,
    required String? email,
    required String requestId,
  }) async {
    createdName = displayName;
    this.requestId = requestId;
    final target = PromotionTargetProfile(
      id: 'target-1',
      type: type,
      displayName: displayName,
      phone: phone,
      email: email,
      createdAtUtc: DateTime.utc(2026, 8, 6),
    );
    targets.add(target);
    return PromotionTargetSuccess(target);
  }

  @override
  Future<PromotionTargetResult<PromotionTargetRelationship>>
  updateRelationship({
    required String targetId,
    required int expectedRevision,
    required int stage,
    required PromotionTargetRelationshipLifecycle lifecycleStatus,
    required String? followUpNote,
    required PromotionTargetRelationshipReason reason,
    required String? reasonDetail,
    required String mutationId,
    required String? resolvedConflictId,
  }) async {
    final pendingConflict = conflictOnce;
    if (pendingConflict != null && resolvedConflictId == null) {
      conflictOnce = null;
      return pendingConflict;
    }
    updatedStage = stage;
    this.expectedRevision = expectedRevision;
    updatedNote = followUpNote;
    this.resolvedConflictId = resolvedConflictId;
    final old = targets.single.projectRelationship!;
    final updated = PromotionTargetRelationship(
      targetId: targetId,
      projectId: old.projectId,
      stage: stage,
      displayStage: stage * 2,
      lifecycleStatus: lifecycleStatus,
      followUpNote: followUpNote,
      revisionNumber: expectedRevision + 1,
      updatedAtUtc: DateTime.utc(2026, 8, 6, 13),
      stageAliases: old.stageAliases,
      history: old.history,
    );
    targets[0] = PromotionTargetProfile(
      id: targets.single.id,
      type: targets.single.type,
      displayName: targets.single.displayName,
      phone: targets.single.phone,
      email: targets.single.email,
      createdAtUtc: targets.single.createdAtUtc,
      hasCurrentProjectRelationship: true,
      projectRelationship: updated,
    );
    return PromotionTargetSuccess(updated);
  }

  @override
  Future<PromotionTargetResult<List<PromotionTargetStageAlias>>>
  configureStageAliases({
    required List<PromotionTargetStageAlias> aliases,
  }) async => PromotionTargetSuccess(aliases);

  @override
  Future<PromotionTargetResult<List<TargetInstitutionRelationship>>>
  loadInstitutionRelationships() async =>
      PromotionTargetSuccess(List.of(institutionRelationships));

  @override
  Future<PromotionTargetResult<TargetInstitutionRelationship>>
  createInstitutionRelationship({
    required String personTargetId,
    required String institutionTargetId,
    required TargetInstitutionRelationshipKind kind,
    required String? roleDescription,
    required String mutationId,
  }) async {
    createdInstitutionKind = kind;
    final relationship = TargetInstitutionRelationship(
      id: 'institution-relation-1',
      personTargetId: personTargetId,
      institutionTargetId: institutionTargetId,
      kind: kind,
      roleDescription: roleDescription,
      startedAtUtc: DateTime.utc(2026, 8, 6),
      endedAtUtc: null,
      status: TargetInstitutionRelationshipStatus.active,
      revisionNumber: 1,
      history: [
        TargetInstitutionRelationshipRevision(
          revisionNumber: 1,
          event: TargetInstitutionRelationshipEvent.created,
          oldStatus: null,
          newStatus: TargetInstitutionRelationshipStatus.active,
          endedAtUtc: null,
          changedByAppUserId: 'user-1',
          changedAtUtc: DateTime.utc(2026, 8, 6),
        ),
      ],
    );
    institutionRelationships.insert(0, relationship);
    return PromotionTargetSuccess(relationship);
  }

  @override
  Future<PromotionTargetResult<TargetInstitutionRelationship>>
  endInstitutionRelationship({
    required String relationshipId,
    required int expectedRevision,
    required String mutationId,
  }) async {
    endedInstitutionRelationshipId = relationshipId;
    final current = institutionRelationships.single;
    final ended = TargetInstitutionRelationship(
      id: current.id,
      personTargetId: current.personTargetId,
      institutionTargetId: current.institutionTargetId,
      kind: current.kind,
      roleDescription: current.roleDescription,
      startedAtUtc: current.startedAtUtc,
      endedAtUtc: DateTime.utc(2026, 8, 7),
      status: TargetInstitutionRelationshipStatus.ended,
      revisionNumber: expectedRevision + 1,
      history: current.history,
    );
    institutionRelationships[0] = ended;
    return PromotionTargetSuccess(ended);
  }

  @override
  Future<void> close() async {}
}

PromotionTargetProfile _plainTarget({
  required String id,
  required PromotionTargetType type,
  required String name,
}) => PromotionTargetProfile(
  id: id,
  type: type,
  displayName: name,
  phone: null,
  email: null,
  createdAtUtc: DateTime.utc(2026, 8, 6),
);

PromotionTargetProfile _targetWithRelationship() => PromotionTargetProfile(
  id: 'target-1',
  type: PromotionTargetType.person,
  displayName: '王小明',
  phone: null,
  email: null,
  createdAtUtc: DateTime.utc(2026, 8, 6),
  hasCurrentProjectRelationship: true,
  projectRelationship: _relationship(stage: 3, revision: 2, note: '下周联系'),
);

PromotionTargetRelationship _relationship({
  required int stage,
  required int revision,
  required String? note,
}) => PromotionTargetRelationship(
  targetId: 'target-1',
  projectId: 'project-1',
  stage: stage,
  displayStage: stage * 2,
  lifecycleStatus: PromotionTargetRelationshipLifecycle.active,
  followUpNote: note,
  revisionNumber: revision,
  updatedAtUtc: DateTime.utc(2026, 8, 6, 12),
  stageAliases: [
    for (var value = 0; value <= 4; value++)
      PromotionTargetStageAlias(
        stage: value,
        displayStage: value * 2,
        displayName: null,
      ),
  ],
  history: [
    PromotionTargetRelationshipRevision(
      revisionNumber: revision,
      oldStage: stage == 0 ? null : stage - 1,
      newStage: stage,
      oldLifecycleStatus: stage == 0
          ? null
          : PromotionTargetRelationshipLifecycle.active,
      newLifecycleStatus: PromotionTargetRelationshipLifecycle.active,
      followUpNote: note,
      changedFields: const ['stage', 'follow_up_note'],
      reasonCode: 'progress_update',
      reasonDetail: null,
      changedByAppUserId: 'user-1',
      changedAtUtc: DateTime.utc(2026, 8, 6, 12),
    ),
  ],
);
