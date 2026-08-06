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
}

Widget _app(_FakeGateway gateway) => MaterialApp(
  home: Scaffold(
    body: PersonalActionPlanPanel(
      text: const AppStrings('zh'),
      scopeKey: 'user/workspace/project',
      gateway: gateway,
      timeZoneProvider: const _TimeZoneProvider(),
      idGenerator: _Ids(),
    ),
  ),
);

final class _FakeGateway implements PersonalActionPlanGateway {
  _FakeGateway({this.plan});

  PersonalActionPlanSnapshot? plan;
  int? savedExpectedRevision;
  int? savedTarget;
  String? savedTimeZone;
  String? savedMutationId;

  @override
  Future<PersonalActionPlanResult<PersonalActionPlanSnapshot?>> load() async =>
      PersonalActionPlanSuccess(plan);

  @override
  Future<PersonalActionPlanResult<PersonalActionPlanMutation>> save({
    required int expectedRevision,
    required int? weeklyContactTarget,
    required String statisticsTimeZone,
    required int weekStartIsoDay,
    required String mutationId,
  }) async {
    savedExpectedRevision = expectedRevision;
    savedTarget = weeklyContactTarget;
    savedTimeZone = statisticsTimeZone;
    savedMutationId = mutationId;
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
