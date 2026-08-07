import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/device/device_time_zone.dart';
import 'package:tongxingzhe_app/features/reminders/personal_action_reminder_panel.dart';
import 'package:tongxingzhe_app/foundation/runtime_values.dart';
import 'package:tongxingzhe_app/l10n/app_strings.dart';
import 'package:tongxingzhe_app/plans/personal_action_plan.dart';
import 'package:tongxingzhe_app/reminders/personal_action_reminder.dart';

void main() {
  for (final size in [const Size(320, 568), const Size(360, 640)]) {
    testWidgets('${size.width.toInt()} 宽标准文字不产生布局异常', (tester) async {
      await _setCompactView(tester, size: size);
      await tester.pumpWidget(_app(textScaler: TextScaler.noScaling));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('320 宽和 200% 文字下完整显示，并把卡片标题标成 heading', (tester) async {
    final semantics = tester.ensureSemantics();
    await _setCompactView(tester);

    await tester.pumpWidget(_app(textScaler: TextScaler.linear(2)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('修改提醒时间'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('修改提醒时间')).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(find.text('每日行动提醒')).dy),
    );
    expect(
      tester
          .getSemantics(find.text('每日行动提醒'))
          .getSemanticsData()
          .flagsCollection
          .isHeader,
      isTrue,
    );
    semantics.dispose();
  });

  testWidgets('详细预览限制键盘焦点，Escape 取消后返回触发开关', (tester) async {
    await _setCompactView(tester);
    final store = _PreferenceStore(
      const DeviceReminderPreference(systemNotificationsEnabled: true),
    );
    final scheduler = _Scheduler();
    await tester.pumpWidget(
      _app(
        textScaler: TextScaler.linear(2),
        preferenceStore: store,
        scheduler: scheduler,
      ),
    );
    await tester.pumpAndSettle();

    final trigger = find.byKey(const ValueKey('device-reminder-details'));
    await tester.scrollUntilVisible(trigger, 120);
    await tester.tap(trigger);
    await tester.pumpAndSettle();

    final cancel = find.byKey(const ValueKey('cancel-device-reminder-details'));
    final confirm = find.byKey(
      const ValueKey('confirm-device-reminder-details'),
    );
    expect(_containsPrimaryFocus(tester, cancel), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(_containsPrimaryFocus(tester, confirm), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(_containsPrimaryFocus(tester, cancel), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(cancel, findsNothing);
    expect(_containsPrimaryFocus(tester, trigger), isTrue);
    expect(store.saveCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('提醒时间动作包含当前钟点，异步错误作为 live region 播报', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app(textScaler: TextScaler.noScaling));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel(RegExp(r'修改提醒时间.*7:00')), findsOneWidget);

    await tester.pumpWidget(
      _app(
        textScaler: TextScaler.noScaling,
        gateway: _ReminderGateway(rejectLoad: true),
      ),
    );
    await tester.pumpAndSettle();

    final errorNode = tester.getSemantics(find.text('私人提醒暂时无法载入或保存。'));
    expect(errorNode.label, '私人提醒暂时无法载入或保存。');
    expect(errorNode.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
    semantics.dispose();
  });

  testWidgets('提醒离线副本用单一语义节点表达时间和只读状态', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        textScaler: TextScaler.noScaling,
        gateway: _ReminderGateway(fromOfflineCache: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('personal-reminder-offline-cache')),
          )
          .label,
      '离线副本 · 上次同步 2030-03-09T20:00:00.000Z。'
      '计划与提醒时间只读；联网后再修改。',
    );
    semantics.dispose();
  });

  testWidgets('关闭 Material 时间选择器后焦点返回提醒时间动作', (tester) async {
    await tester.pumpWidget(_app(textScaler: TextScaler.noScaling));
    await tester.pumpAndSettle();

    final trigger = find.byKey(const ValueKey('edit-personal-reminder'));
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(TimePickerDialog), findsNothing);
    expect(_containsPrimaryFocus(tester, trigger), isTrue);
  });
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

Widget _app({
  required TextScaler textScaler,
  _PreferenceStore? preferenceStore,
  _Scheduler? scheduler,
  _ReminderGateway? gateway,
}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: textScaler),
    child: child!,
  ),
  home: Scaffold(
    body: SingleChildScrollView(
      child: PersonalActionReminderPanel(
        text: const AppStrings('zh'),
        scope: const DeviceReminderScope(
          appUserId: 'user-1',
          workspaceId: 'workspace-1',
          projectId: 'project-1',
          deviceId: 'device-1',
        ),
        gateway: gateway ?? _ReminderGateway(),
        planGateway: const _PlanGateway(),
        projectName: '校园推广',
        preferenceStore: preferenceStore ?? _PreferenceStore(),
        scheduler: scheduler ?? _Scheduler(),
        timeZoneProvider: const _TimeZoneProvider(),
        idGenerator: _Ids(),
      ),
    ),
  ),
);

final class _ReminderGateway implements PersonalActionReminderGateway {
  _ReminderGateway({this.rejectLoad = false, this.fromOfflineCache = false});

  final bool rejectLoad;
  final bool fromOfflineCache;
  PersonalActionReminder reminder = PersonalActionReminder(
    reminderId: 'reminder-1',
    revision: 1,
    localTime: LocalReminderTime.fromHourMinute(19, 0),
    updatedAtUtc: DateTime.utc(2030, 3, 9, 18),
  );

  @override
  Future<PersonalActionReminderResult<PersonalActionReminder?>> load() async =>
      rejectLoad
      ? const PersonalActionReminderRejected(
          PersonalActionReminderFailureCode.networkUnavailable,
        )
      : PersonalActionReminderSuccess(
          reminder,
          fromOfflineCache: fromOfflineCache,
          cachedAtUtc: fromOfflineCache ? DateTime.utc(2030, 3, 9, 20) : null,
        );

  @override
  Future<PersonalActionReminderResult<PersonalActionReminderMutation>> save({
    required int expectedRevision,
    required LocalReminderTime? localTime,
    required String mutationId,
  }) async => throw UnimplementedError();

  @override
  Future<void> close() async {}
}

final class _PreferenceStore implements DeviceReminderPreferenceStore {
  _PreferenceStore([this.value = const DeviceReminderPreference.disabled()]);

  DeviceReminderPreference value;
  var saveCount = 0;

  @override
  Future<DeviceReminderPreference> load(DeviceReminderScope scope) async =>
      value;

  @override
  Future<void> save(
    DeviceReminderScope scope,
    DeviceReminderPreference preference,
  ) async {
    value = preference;
    saveCount += 1;
  }
}

final class _Scheduler implements ReminderNotificationScheduler {
  @override
  Future<ReminderScheduleResult> requestPermissionAndSchedule({
    required String scheduleKey,
    required LocalReminderTime localTime,
    required String deviceTimeZone,
    required ReminderNotificationContent content,
  }) async => const ReminderScheduleSucceeded();

  @override
  Future<ReminderScheduleResult> schedule({
    required String scheduleKey,
    required LocalReminderTime localTime,
    required String deviceTimeZone,
    required ReminderNotificationContent content,
  }) async => const ReminderScheduleSucceeded();

  @override
  Future<ReminderScheduleResult> cancel({required String scheduleKey}) async =>
      const ReminderScheduleSucceeded();

  @override
  Future<ReminderScheduleResult> cancelAll() async =>
      const ReminderScheduleSucceeded();

  @override
  Future<void> close() async {}
}

final class _PlanGateway implements PersonalActionPlanGateway {
  const _PlanGateway();

  @override
  Future<PersonalActionPlanResult<PersonalActionPlanSnapshot?>> load() async =>
      const PersonalActionPlanSuccess(null);

  @override
  Future<PersonalActionPlanResult<PersonalActionPlanMutation>> save({
    required int expectedRevision,
    required int? weeklyContactTarget,
    required String statisticsTimeZone,
    required int weekStartIsoDay,
    required String mutationId,
  }) async => throw UnimplementedError();

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
