import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/device/device_time_zone.dart';
import 'package:tongxingzhe_app/features/plans/personal_action_plan_panel.dart';
import 'package:tongxingzhe_app/foundation/runtime_values.dart';
import 'package:tongxingzhe_app/l10n/app_strings.dart';
import 'package:tongxingzhe_app/plans/personal_action_plan.dart';

void main() {
  testWidgets('坦率显示本人计划、已记录场次和差额', (tester) async {
    final gateway = _FakeGateway(plan: _plan);
    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();

    expect(find.text('计划、进度和差距只对你本人可见。'), findsOneWidget);
    expect(find.text('本周计划 3'), findsOneWidget);
    expect(find.text('已记录 1'), findsOneWidget);
    expect(find.text('还差 2'), findsOneWidget);
    expect(find.textContaining('America/Chicago'), findsOneWidget);
    expect(find.textContaining('经理'), findsNothing);
    expect(find.textContaining('排名'), findsNothing);
  });

  testWidgets('首次设置采用设备 IANA 时区并只提交计划字段', (tester) async {
    final gateway = _FakeGateway();
    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('create-personal-plan')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('personal-plan-time-zone')),
          )
          .controller!
          .text,
      'America/Chicago',
    );
    await tester.tap(find.text('启用每周接触场次目标'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('personal-plan-target')),
      '2',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(gateway.savedExpectedRevision, 0);
    expect(gateway.savedTarget, 2);
    expect(gateway.savedTimeZone, 'America/Chicago');
    expect(gateway.savedMutationId, 'mutation-1');
    expect(gateway.savedReplaceOfflineChange, isFalse);
    expect(find.text('本周计划 2'), findsOneWidget);
  });

  testWidgets('已有待生效版本时显示生效边界且不允许叠加修改', (tester) async {
    final gateway = _FakeGateway(plan: _pendingPlan);
    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();

    expect(find.textContaining('2030-03-16T16:00:00.000Z'), findsOneWidget);
    expect(find.text('已有一项待生效修改；生效后才能再次修改。'), findsOneWidget);
    expect(find.byKey(const ValueKey('edit-personal-plan')), findsNothing);
  });

  testWidgets('离线副本显示同步时间并允许保存一项计划修改', (tester) async {
    final gateway = _FakeGateway(plan: _plan, fromOfflineCache: true);
    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();

    expect(find.textContaining('离线副本'), findsOneWidget);
    expect(find.textContaining('2030-03-09T20:00:00.000Z'), findsOneWidget);
    expect(find.byKey(const ValueKey('edit-personal-plan')), findsOneWidget);
  });

  testWidgets('离线副本可保存一项待同步修改且不伪造生效边界', (tester) async {
    final gateway = _FakeGateway(
      plan: _plan,
      fromOfflineCache: true,
      queueOnSave: true,
    );
    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('edit-personal-plan')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('personal-plan-target')),
      '7',
    );
    await tester.enterText(
      find.byKey(const ValueKey('personal-plan-time-zone')),
      'Asia/Shanghai',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('计划修改待同步'), findsOneWidget);
    expect(find.textContaining('每周目标：7'), findsOneWidget);
    expect(find.textContaining('统计时区：Asia/Shanghai'), findsOneWidget);
    expect(find.textContaining('2030-03-09T20:00:00.000Z'), findsWidgets);
    expect(find.textContaining('新设置将在此时间生效'), findsNothing);
    expect(find.byKey(const ValueKey('edit-personal-plan')), findsNothing);
  });

  testWidgets('计划冲突同时显示服务器事实和本机草稿并可保留服务器', (tester) async {
    final gateway = _FakeGateway(
      plan: _plan,
      offlineChange: _offlineChange,
      offlineChangeFailure: PersonalActionPlanFailureCode.conflict,
    );
    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();

    expect(find.text('服务器计划已更新'), findsOneWidget);
    expect(find.text('本周计划 3'), findsOneWidget);
    expect(find.textContaining('每周目标：7'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('discard-offline-plan-change')));
    await tester.pumpAndSettle();

    expect(gateway.discardCalled, isTrue);
    expect(find.text('计划修改待同步'), findsNothing);
    expect(find.byKey(const ValueKey('edit-personal-plan')), findsOneWidget);
  });

  testWidgets('用户明确采用本机草稿时使用服务器最新 revision 和新 mutation', (tester) async {
    final gateway = _FakeGateway(
      plan: _serverPlan,
      offlineChange: _offlineChange,
      offlineChangeFailure: PersonalActionPlanFailureCode.conflict,
    );
    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('resubmit-offline-plan-change')),
    );
    await tester.pumpAndSettle();

    expect(gateway.savedExpectedRevision, 3);
    expect(gateway.savedMutationId, 'mutation-1');
    expect(gateway.savedReplaceOfflineChange, isTrue);
    expect(gateway.savedTarget, 7);
    expect(gateway.savedTimeZone, 'Asia/Shanghai');
    expect(find.text('计划修改待同步'), findsNothing);
  });

  testWidgets('待同步草稿重试时复用原 revision 和 mutation', (tester) async {
    final gateway = _FakeGateway(plan: _plan, offlineChange: _offlineChange);
    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('retry-offline-plan-change')));
    await tester.pumpAndSettle();

    expect(gateway.savedExpectedRevision, 2);
    expect(gateway.savedMutationId, 'offline-mutation-1');
    expect(gateway.savedReplaceOfflineChange, isFalse);
    expect(find.text('计划修改待同步'), findsNothing);
  });

  testWidgets('切换 scope 后忽略旧请求的延迟结果', (tester) async {
    final oldGateway = _DelayedGateway();
    final newGateway = _FakeGateway(plan: _latestServerPlan);
    await tester.pumpWidget(_app(oldGateway, scopeKey: 'old-scope'));
    await tester.pump();

    await tester.pumpWidget(_app(newGateway, scopeKey: 'new-scope'));
    await tester.pumpAndSettle();
    expect(find.text('本周计划 9'), findsOneWidget);

    oldGateway.complete(_plan);
    await tester.pumpAndSettle();

    expect(find.text('本周计划 9'), findsOneWidget);
    expect(find.text('本周计划 3'), findsNothing);
  });

  testWidgets('本机草稿再次冲突后刷新 revision 再提交', (tester) async {
    final gateway = _ConflictRefreshGateway();
    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('resubmit-offline-plan-change')),
    );
    await tester.pumpAndSettle();

    expect(gateway.savedExpectedRevisions, [3]);
    expect(gateway.loadCount, 2);
    expect(find.text('本周计划 9'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('resubmit-offline-plan-change')),
    );
    await tester.pumpAndSettle();

    expect(gateway.savedExpectedRevisions, [3, 4]);
  });
}

Widget _app(
  PersonalActionPlanGateway gateway, {
  String scopeKey = 'user/workspace/project',
}) => MaterialApp(
  home: Scaffold(
    body: PersonalActionPlanPanel(
      text: const AppStrings('zh'),
      scopeKey: scopeKey,
      gateway: gateway,
      timeZoneProvider: const _TimeZoneProvider(),
      idGenerator: _Ids(),
    ),
  ),
);

final class _DelayedGateway implements PersonalActionPlanGateway {
  final _loadResult =
      Completer<PersonalActionPlanResult<PersonalActionPlanSnapshot?>>();

  void complete(PersonalActionPlanSnapshot plan) {
    _loadResult.complete(PersonalActionPlanSuccess(plan));
  }

  @override
  Future<PersonalActionPlanResult<PersonalActionPlanSnapshot?>> load() =>
      _loadResult.future;

  @override
  Future<PersonalActionPlanResult<PersonalActionPlanMutation>> save({
    required int expectedRevision,
    required int? weeklyContactTarget,
    required String statisticsTimeZone,
    required int weekStartIsoDay,
    required String mutationId,
    bool replaceOfflineChange = false,
  }) => throw UnimplementedError();

  @override
  Future<bool> discardOfflineChange() async => true;

  @override
  Future<void> close() async {}
}

final class _ConflictRefreshGateway implements PersonalActionPlanGateway {
  var loadCount = 0;
  final savedExpectedRevisions = <int>[];

  @override
  Future<PersonalActionPlanResult<PersonalActionPlanSnapshot?>> load() async {
    loadCount++;
    return PersonalActionPlanSuccess(
      loadCount == 1 ? _serverPlan : _latestServerPlan,
      offlineChange: _offlineChange,
      offlineChangeFailure: PersonalActionPlanFailureCode.conflict,
    );
  }

  @override
  Future<PersonalActionPlanResult<PersonalActionPlanMutation>> save({
    required int expectedRevision,
    required int? weeklyContactTarget,
    required String statisticsTimeZone,
    required int weekStartIsoDay,
    required String mutationId,
    bool replaceOfflineChange = false,
  }) async {
    savedExpectedRevisions.add(expectedRevision);
    return const PersonalActionPlanRejected(
      PersonalActionPlanFailureCode.conflict,
    );
  }

  @override
  Future<bool> discardOfflineChange() async => true;

  @override
  Future<void> close() async {}
}

final class _FakeGateway implements PersonalActionPlanGateway {
  _FakeGateway({
    this.plan,
    this.fromOfflineCache = false,
    this.queueOnSave = false,
    this.offlineChange,
    this.offlineChangeFailure,
  });

  PersonalActionPlanSnapshot? plan;
  final bool fromOfflineCache;
  final bool queueOnSave;
  PersonalActionPlanOfflineChange? offlineChange;
  final PersonalActionPlanFailureCode? offlineChangeFailure;
  bool discardCalled = false;
  int? savedExpectedRevision;
  int? savedTarget;
  String? savedTimeZone;
  String? savedMutationId;
  bool? savedReplaceOfflineChange;

  @override
  Future<PersonalActionPlanResult<PersonalActionPlanSnapshot?>> load() async =>
      PersonalActionPlanSuccess(
        plan,
        fromOfflineCache: fromOfflineCache,
        cachedAtUtc: fromOfflineCache ? DateTime.utc(2030, 3, 9, 20) : null,
        offlineChange: offlineChange,
        offlineChangeFailure: offlineChangeFailure,
      );

  @override
  Future<PersonalActionPlanResult<PersonalActionPlanMutation>> save({
    required int expectedRevision,
    required int? weeklyContactTarget,
    required String statisticsTimeZone,
    required int weekStartIsoDay,
    required String mutationId,
    bool replaceOfflineChange = false,
  }) async {
    savedExpectedRevision = expectedRevision;
    savedTarget = weeklyContactTarget;
    savedTimeZone = statisticsTimeZone;
    savedMutationId = mutationId;
    savedReplaceOfflineChange = replaceOfflineChange;
    if (queueOnSave) {
      offlineChange = PersonalActionPlanOfflineChange(
        expectedRevision: expectedRevision,
        weeklyContactTarget: weeklyContactTarget,
        statisticsTimeZone: statisticsTimeZone,
        weekStartIsoDay: weekStartIsoDay,
        mutationId: mutationId,
        queuedAtUtc: DateTime.utc(2030, 3, 9, 20),
      );
      return PersonalActionPlanQueued(offlineChange!);
    }
    plan = PersonalActionPlanSnapshot(
      planId: 'plan-1',
      revision: 1,
      current: PersonalActionPlanVersion(
        revision: 1,
        weeklyContactTarget: weeklyContactTarget,
        statisticsTimeZone: statisticsTimeZone,
        weekStartIsoDay: weekStartIsoDay,
        effectiveFromUtc: DateTime.utc(2030, 3, 4, 6),
      ),
      pending: null,
      progress: PersonalActionPlanProgress(
        cycleStartUtc: DateTime.utc(2030, 3, 4, 6),
        cycleUntilUtc: DateTime.utc(2030, 3, 11, 5),
        recordedContactSessions: 0,
        remainingContactSessions: weeklyContactTarget,
        asOfUtc: DateTime.utc(2030, 3, 9, 18),
      ),
    );
    return PersonalActionPlanSuccess(
      PersonalActionPlanMutation(
        plan: plan!,
        duplicate: false,
        acceptedRevision: 1,
      ),
    );
  }

  @override
  Future<bool> discardOfflineChange() async {
    discardCalled = true;
    offlineChange = null;
    return true;
  }

  @override
  Future<void> close() async {}
}

final class _TimeZoneProvider implements DeviceTimeZoneProvider {
  const _TimeZoneProvider();

  @override
  Future<String> currentIanaTimeZone() async => 'America/Chicago';
}

final class _Ids implements IdGenerator {
  @override
  String next() => 'mutation-1';
}

final _plan = PersonalActionPlanSnapshot(
  planId: 'plan-1',
  revision: 1,
  current: PersonalActionPlanVersion(
    revision: 1,
    weeklyContactTarget: 3,
    statisticsTimeZone: 'America/Chicago',
    weekStartIsoDay: DateTime.monday,
    effectiveFromUtc: DateTime.utc(2030, 3, 4, 6),
  ),
  pending: null,
  progress: PersonalActionPlanProgress(
    cycleStartUtc: DateTime.utc(2030, 3, 4, 6),
    cycleUntilUtc: DateTime.utc(2030, 3, 11, 5),
    recordedContactSessions: 1,
    remainingContactSessions: 2,
    asOfUtc: DateTime.utc(2030, 3, 9, 18),
  ),
);

final _pendingPlan = PersonalActionPlanSnapshot(
  planId: 'plan-1',
  revision: 2,
  current: _plan.current,
  pending: PersonalActionPlanVersion(
    revision: 2,
    weeklyContactTarget: 4,
    statisticsTimeZone: 'Asia/Shanghai',
    weekStartIsoDay: DateTime.sunday,
    effectiveFromUtc: DateTime.utc(2030, 3, 16, 16),
  ),
  progress: _plan.progress,
);

final _serverPlan = PersonalActionPlanSnapshot(
  planId: _plan.planId,
  revision: 3,
  current: _plan.current,
  pending: null,
  progress: _plan.progress,
);

final _latestServerPlan = PersonalActionPlanSnapshot(
  planId: _plan.planId,
  revision: 4,
  current: PersonalActionPlanVersion(
    revision: 4,
    weeklyContactTarget: 9,
    statisticsTimeZone: 'America/New_York',
    weekStartIsoDay: DateTime.sunday,
    effectiveFromUtc: DateTime.utc(2030, 3, 4),
  ),
  pending: null,
  progress: _plan.progress,
);

final _offlineChange = PersonalActionPlanOfflineChange(
  expectedRevision: 2,
  weeklyContactTarget: 7,
  statisticsTimeZone: 'Asia/Shanghai',
  weekStartIsoDay: DateTime.sunday,
  mutationId: 'offline-mutation-1',
  queuedAtUtc: DateTime.utc(2030, 3, 9, 20),
);
