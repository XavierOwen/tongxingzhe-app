import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/device/device_time_zone.dart';
import 'package:tongxingzhe_app/features/reminders/personal_action_reminder_panel.dart';
import 'package:tongxingzhe_app/foundation/runtime_values.dart';
import 'package:tongxingzhe_app/l10n/app_strings.dart';
import 'package:tongxingzhe_app/reminders/personal_action_reminder.dart';

void main() {
  testWidgets('新设备默认关闭，卡片仍显示同步的当地提醒时间', (tester) async {
    final store = _MemoryPreferenceStore();
    final scheduler = _FakeScheduler();
    await tester.pumpWidget(_app(store: store, scheduler: scheduler));
    await tester.pumpAndSettle();

    expect(find.textContaining('每天提醒'), findsOneWidget);
    expect(find.textContaining('7:00'), findsOneWidget);
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('device-reminder-opt-in')),
          )
          .value,
      isFalse,
    );
    expect(scheduler.scheduleCount, 0);
  });

  testWidgets('明确启用后才请求权限、安排通用通知并保存本机 opt-in', (tester) async {
    final store = _MemoryPreferenceStore();
    final scheduler = _FakeScheduler();
    await tester.pumpWidget(_app(store: store, scheduler: scheduler));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('device-reminder-opt-in')));
    await tester.pumpAndSettle();

    expect(scheduler.permissionRequestCount, 1);
    expect(scheduler.lastTimeZone, 'America/Chicago');
    expect(scheduler.lastContent?.payload, 'today');
    expect(scheduler.lastContent?.title, '同行者');
    expect(scheduler.lastContent?.body, isNot(contains('校园推广')));
    expect(scheduler.lastContent?.body, isNot(contains('王小明')));
    expect(store.value.systemNotificationsEnabled, isTrue);
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('device-reminder-opt-in')),
          )
          .value,
      isTrue,
    );
  });

  testWidgets('权限被拒绝时本机保持关闭且不写假成功', (tester) async {
    final store = _MemoryPreferenceStore();
    final scheduler = _FakeScheduler(
      requestResult: const ReminderScheduleRejected(
        ReminderScheduleFailure.permissionDenied,
      ),
    );
    await tester.pumpWidget(_app(store: store, scheduler: scheduler));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('device-reminder-opt-in')));
    await tester.pumpAndSettle();

    expect(store.saveCount, 0);
    expect(store.value.systemNotificationsEnabled, isFalse);
    expect(find.textContaining('本设备仍保持关闭'), findsOneWidget);
  });

  testWidgets('清除同步提醒会取消本项目通知但不触碰其他项目', (tester) async {
    final store = _MemoryPreferenceStore(
      const DeviceReminderPreference(systemNotificationsEnabled: true),
    );
    final scheduler = _FakeScheduler();
    final gateway = _FakeGateway();
    await tester.pumpWidget(
      _app(store: store, scheduler: scheduler, gateway: gateway),
    );
    await tester.pumpAndSettle();
    scheduler.cancelKeys.clear();

    await tester.tap(find.byKey(const ValueKey('clear-personal-reminder')));
    await tester.pumpAndSettle();

    expect(gateway.savedTime, isNull);
    expect(scheduler.cancelKeys, hasLength(1));
    expect(scheduler.cancelKeys.single, contains('project-1'));
    expect(find.textContaining('尚未设置'), findsOneWidget);
  });

  testWidgets('从后台恢复时重新读取跨设备变更并取消已清除的本机通知', (tester) async {
    final store = _MemoryPreferenceStore(
      const DeviceReminderPreference(systemNotificationsEnabled: true),
    );
    final scheduler = _FakeScheduler();
    final gateway = _FakeGateway();
    await tester.pumpWidget(
      _app(store: store, scheduler: scheduler, gateway: gateway),
    );
    await tester.pumpAndSettle();
    scheduler.cancelKeys.clear();

    gateway.reminder = null;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(scheduler.cancelKeys, hasLength(1));
    expect(scheduler.cancelKeys.single, contains('project-1'));
    expect(find.textContaining('尚未设置'), findsOneWidget);
  });
}

Widget _app({
  required _MemoryPreferenceStore store,
  required _FakeScheduler scheduler,
  _FakeGateway? gateway,
}) => MaterialApp(
  home: Scaffold(
    body: PersonalActionReminderPanel(
      text: const AppStrings('zh'),
      scope: const DeviceReminderScope(
        appUserId: 'user-1',
        workspaceId: 'workspace-1',
        projectId: 'project-1',
        deviceId: 'device-1',
      ),
      gateway: gateway ?? _FakeGateway(),
      preferenceStore: store,
      scheduler: scheduler,
      timeZoneProvider: const _TimeZoneProvider(),
      idGenerator: _IdGenerator(),
    ),
  ),
);

final class _FakeGateway implements PersonalActionReminderGateway {
  PersonalActionReminder? reminder = PersonalActionReminder(
    reminderId: 'reminder-1',
    revision: 1,
    localTime: LocalReminderTime.fromHourMinute(19, 0),
    updatedAtUtc: DateTime.utc(2030, 3, 9, 18),
  );
  LocalReminderTime? savedTime;

  @override
  Future<PersonalActionReminderResult<PersonalActionReminder?>> load() async =>
      PersonalActionReminderSuccess(reminder);

  @override
  Future<PersonalActionReminderResult<PersonalActionReminderMutation>> save({
    required int expectedRevision,
    required LocalReminderTime? localTime,
    required String mutationId,
  }) async {
    savedTime = localTime;
    reminder = PersonalActionReminder(
      reminderId: 'reminder-1',
      revision: expectedRevision + 1,
      localTime: localTime,
      updatedAtUtc: DateTime.utc(2030, 3, 9, 19),
    );
    return PersonalActionReminderSuccess(
      PersonalActionReminderMutation(
        reminder: reminder!,
        duplicate: false,
        acceptedRevision: reminder!.revision,
      ),
    );
  }

  @override
  Future<void> close() async {}
}

final class _MemoryPreferenceStore implements DeviceReminderPreferenceStore {
  _MemoryPreferenceStore([
    this.value = const DeviceReminderPreference.disabled(),
  ]);

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
    saveCount++;
    value = preference;
  }
}

final class _FakeScheduler implements ReminderNotificationScheduler {
  _FakeScheduler({this.requestResult = const ReminderScheduleSucceeded()});

  final ReminderScheduleResult requestResult;
  var permissionRequestCount = 0;
  var scheduleCount = 0;
  String? lastTimeZone;
  ReminderNotificationContent? lastContent;
  final cancelKeys = <String>[];

  @override
  Future<ReminderScheduleResult> requestPermissionAndSchedule({
    required String scheduleKey,
    required LocalReminderTime localTime,
    required String deviceTimeZone,
    required ReminderNotificationContent content,
  }) async {
    permissionRequestCount++;
    lastTimeZone = deviceTimeZone;
    lastContent = content;
    return requestResult;
  }

  @override
  Future<ReminderScheduleResult> schedule({
    required String scheduleKey,
    required LocalReminderTime localTime,
    required String deviceTimeZone,
    required ReminderNotificationContent content,
  }) async {
    scheduleCount++;
    lastTimeZone = deviceTimeZone;
    lastContent = content;
    return const ReminderScheduleSucceeded();
  }

  @override
  Future<ReminderScheduleResult> cancel({required String scheduleKey}) async {
    cancelKeys.add(scheduleKey);
    return const ReminderScheduleSucceeded();
  }

  @override
  Future<void> close() async {}
}

final class _TimeZoneProvider implements DeviceTimeZoneProvider {
  const _TimeZoneProvider();

  @override
  Future<String> currentIanaTimeZone() async => 'America/Chicago';
}

final class _IdGenerator implements IdGenerator {
  var value = 0;

  @override
  String next() => 'mutation-${++value}';
}
