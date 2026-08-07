import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/device/device_time_zone.dart';
import 'package:tongxingzhe_app/features/plans/personal_action_plan_panel.dart';
import 'package:tongxingzhe_app/foundation/runtime_values.dart';
import 'package:tongxingzhe_app/l10n/app_strings.dart';
import 'package:tongxingzhe_app/plans/personal_action_plan.dart';

void main() {
  for (final size in [const Size(320, 568), const Size(360, 640)]) {
    testWidgets('${size.width.toInt()} 宽标准文字不产生计划布局异常', (tester) async {
      await _setCompactView(tester, size: size);
      await tester.pumpWidget(
        _app(
          gateway: _PlanGateway(plan: _plan),
          textScaler: TextScaler.noScaling,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('320 宽和 200% 文字下计划标题动作纵排且 fact 只播报一次', (tester) async {
    final semantics = tester.ensureSemantics();
    await _setCompactView(tester);
    await tester.pumpWidget(
      _app(
        gateway: _PlanGateway(plan: _plan),
        textScaler: TextScaler.linear(2),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      tester.getTopLeft(find.text('编辑')).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(find.text('私人周计划')).dy),
    );
    expect(
      tester
          .getSemantics(find.text('私人周计划'))
          .getSemanticsData()
          .flagsCollection
          .isHeader,
      isTrue,
    );
    expect(tester.getSemantics(find.byType(Chip).at(0)).label, '本周计划 3');
    expect(tester.getSemantics(find.byType(Chip).at(1)).label, '已记录 1');
    expect(tester.getSemantics(find.byType(Chip).at(2)).label, '还差 2');
    semantics.dispose();
  });

  testWidgets('计划对话框按视觉顺序闭环遍历，Escape 取消并恢复焦点', (tester) async {
    await _setCompactView(tester);
    final gateway = _PlanGateway(plan: _plan);
    await tester.pumpWidget(
      _app(gateway: gateway, textScaler: TextScaler.linear(2)),
    );
    await tester.pumpAndSettle();

    final trigger = find.byKey(const ValueKey('edit-personal-plan'));
    await tester.tap(trigger);
    await tester.pumpAndSettle();

    final targetToggle = find.byKey(
      const ValueKey('personal-plan-target-enabled'),
    );
    final target = find.byKey(const ValueKey('personal-plan-target'));
    final timeZone = find.byKey(const ValueKey('personal-plan-time-zone'));
    final weekStart = find.byKey(const ValueKey('personal-plan-week-start'));
    final cancel = find.byKey(const ValueKey('cancel-personal-plan'));
    final save = find.byKey(const ValueKey('save-personal-plan'));

    expect(tester.takeException(), isNull);
    expect(_containsPrimaryFocus(tester, targetToggle), isTrue);
    await _tabTo(tester, target);
    await _tabTo(tester, timeZone);
    await _tabTo(tester, weekStart);
    await _tabTo(tester, cancel);
    await _tabTo(tester, save);
    await _tabTo(tester, targetToggle);
    await _shiftTabTo(tester, save);
    await _tabTo(tester, targetToggle);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(target, findsNothing);
    await _tabTo(tester, timeZone);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('编辑私人周计划'), findsNothing);
    expect(_containsPrimaryFocus(tester, trigger), isTrue);
    expect(gateway.saveCount, 0);
  });

  testWidgets('离线只读状态是单一节点，载入错误通过 live region 播报', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        gateway: _PlanGateway(plan: _plan, fromOfflineCache: true),
        textScaler: TextScaler.noScaling,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('personal-plan-offline-cache')),
          )
          .label,
      '离线副本 · 上次同步 2030-03-09T20:00:00.000Z。'
      '计划与提醒时间只读；联网后再修改。',
    );

    await tester.pumpWidget(
      _app(
        gateway: _PlanGateway(rejectLoad: true),
        textScaler: TextScaler.noScaling,
      ),
    );
    await tester.pumpAndSettle();

    final loadErrorNode = tester.getSemantics(find.text('私人计划暂时无法载入。'));
    expect(loadErrorNode.label, '私人计划暂时无法载入。');
    expect(
      loadErrorNode.getSemanticsData().flagsCollection.isLiveRegion,
      isTrue,
    );
    semantics.dispose();
  });

  testWidgets('计划校验错误留在对话框并作为 live region 播报', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        gateway: _PlanGateway(plan: _plan),
        textScaler: TextScaler.noScaling,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('edit-personal-plan')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('personal-plan-target')),
      '0',
    );
    await tester.tap(find.byKey(const ValueKey('save-personal-plan')));
    await tester.pump();

    expect(find.text('编辑私人周计划'), findsOneWidget);
    final validationErrorNode = tester.getSemantics(
      find.byKey(const ValueKey('personal-plan-validation-error')),
    );
    expect(validationErrorNode.label, '请检查目标数、IANA 时区和周期起始日。');
    expect(
      validationErrorNode.getSemanticsData().flagsCollection.isLiveRegion,
      isTrue,
    );
    semantics.dispose();
  });
}

Future<void> _tabTo(WidgetTester tester, Finder target) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.pump();
  expect(_containsPrimaryFocus(tester, target), isTrue);
}

Future<void> _shiftTabTo(WidgetTester tester, Finder target) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump();
  expect(_containsPrimaryFocus(tester, target), isTrue);
}

bool _containsPrimaryFocus(WidgetTester tester, Finder finder) {
  final target = tester.element(finder);
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused is! Element) return false;
  if (identical(focused, target)) return true;
  var contains = false;
  focused.visitAncestorElements((ancestor) {
    if (identical(ancestor, target)) {
      contains = true;
      return false;
    }
    return true;
  });
  return contains;
}

Future<void> _setCompactView(
  WidgetTester tester, {
  Size size = const Size(320, 568),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Widget _app({required _PlanGateway gateway, required TextScaler textScaler}) =>
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: PersonalActionPlanPanel(
            text: const AppStrings('zh'),
            scopeKey: 'user/workspace/project',
            gateway: gateway,
            timeZoneProvider: const _TimeZoneProvider(),
            idGenerator: _Ids(),
          ),
        ),
      ),
    );

final class _PlanGateway implements PersonalActionPlanGateway {
  _PlanGateway({
    this.plan,
    this.fromOfflineCache = false,
    this.rejectLoad = false,
  });

  PersonalActionPlanSnapshot? plan;
  final bool fromOfflineCache;
  final bool rejectLoad;
  var saveCount = 0;

  @override
  Future<PersonalActionPlanResult<PersonalActionPlanSnapshot?>> load() async =>
      rejectLoad
      ? const PersonalActionPlanRejected(
          PersonalActionPlanFailureCode.networkUnavailable,
        )
      : PersonalActionPlanSuccess(
          plan,
          fromOfflineCache: fromOfflineCache,
          cachedAtUtc: fromOfflineCache ? DateTime.utc(2030, 3, 9, 20) : null,
        );

  @override
  Future<PersonalActionPlanResult<PersonalActionPlanMutation>> save({
    required int expectedRevision,
    required int? weeklyContactTarget,
    required String statisticsTimeZone,
    required int weekStartIsoDay,
    required String mutationId,
  }) async {
    saveCount += 1;
    throw UnimplementedError();
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
