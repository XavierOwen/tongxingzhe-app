import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/device/device_time_zone.dart';
import 'package:tongxingzhe_app/features/reminders/personal_action_reminder_panel.dart';
import 'package:tongxingzhe_app/foundation/runtime_values.dart';
import 'package:tongxingzhe_app/l10n/app_strings.dart';
import 'package:tongxingzhe_app/plans/personal_action_plan.dart';
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

  testWidgets('离线副本禁止修改同步时间，但保留本机通知开关', (tester) async {
    final store = _MemoryPreferenceStore();
    final scheduler = _FakeScheduler();
    await tester.pumpWidget(
      _app(
        store: store,
        scheduler: scheduler,
        gateway: _FakeGateway(fromOfflineCache: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('离线副本'), findsOneWidget);
    expect(find.textContaining('2030-03-09T20:00:00.000Z'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('edit-personal-reminder')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('clear-personal-reminder')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('device-reminder-opt-in')),
          )
          .onChanged,
      isNotNull,
    );
  });

  testWidgets('断网且无缓存时保留已安排的本机通知', (tester) async {
    final store = _MemoryPreferenceStore(
      const DeviceReminderPreference(systemNotificationsEnabled: true),
    );
    final scheduler = _FakeScheduler();
    await tester.pumpWidget(
      _app(
        store: store,
        scheduler: scheduler,
        gateway: _FakeGateway(rejectLoad: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('暂时无法载入'), findsOneWidget);
    expect(scheduler.cancelKeys, isEmpty);
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
    expect(scheduler.lastContent?.payload, personalActionReminderPayload);
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

  testWidgets('本人明确选择后才把项目名和个人周进度写入本设备通知', (tester) async {
    final store = _MemoryPreferenceStore(
      const DeviceReminderPreference(systemNotificationsEnabled: true),
    );
    final scheduler = _FakeScheduler();
    await tester.pumpWidget(_app(store: store, scheduler: scheduler));
    await tester.pumpAndSettle();
    scheduler.cancelKeys.clear();

    await tester.tap(find.byKey(const ValueKey('device-reminder-details')));
    await tester.pumpAndSettle();
    expect(find.textContaining('校园推广'), findsOneWidget);
    expect(find.textContaining('3 / 5'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('confirm-device-reminder-details')),
    );
    await tester.pumpAndSettle();

    expect(
      store.value.contentMode,
      ReminderNotificationContentMode.projectAndProgress,
    );
    expect(scheduler.lastContent?.title, contains('校园推广'));
    expect(scheduler.lastContent?.body, contains('3'));
    expect(scheduler.lastContent?.body, contains('5'));
    expect(scheduler.cancelKeys, hasLength(1));
  });

  testWidgets('取消详细通知预览时不改变本机设置或系统调度', (tester) async {
    final store = _MemoryPreferenceStore(
      const DeviceReminderPreference(systemNotificationsEnabled: true),
    );
    final scheduler = _FakeScheduler();
    await tester.pumpWidget(_app(store: store, scheduler: scheduler));
    await tester.pumpAndSettle();
    scheduler.cancelKeys.clear();

    await tester.tap(find.byKey(const ValueKey('device-reminder-details')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('cancel-device-reminder-details')),
    );
    await tester.pumpAndSettle();

    expect(store.value.contentMode, ReminderNotificationContentMode.generic);
    expect(store.saveCount, 0);
    expect(scheduler.cancelKeys, isEmpty);
  });

  testWidgets('没有周目标时详细预览不伪造零目标或差额', (tester) async {
    final store = _MemoryPreferenceStore(
      const DeviceReminderPreference(systemNotificationsEnabled: true),
    );
    final scheduler = _FakeScheduler();
    await tester.pumpWidget(
      _app(
        store: store,
        scheduler: scheduler,
        planGateway: _FakePlanGateway(noPlan: true),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('device-reminder-details')));
    await tester.pumpAndSettle();

    expect(find.textContaining('未设置周目标'), findsOneWidget);
    expect(find.textContaining('0 / 0'), findsNothing);
  });

  testWidgets('个人计划读取失败时保留原通用通知且不写详细 opt-in', (tester) async {
    final store = _MemoryPreferenceStore(
      const DeviceReminderPreference(systemNotificationsEnabled: true),
    );
    final scheduler = _FakeScheduler();
    await tester.pumpWidget(
      _app(
        store: store,
        scheduler: scheduler,
        planGateway: _FakePlanGateway(rejectLoad: true),
      ),
    );
    await tester.pumpAndSettle();
    scheduler.cancelKeys.clear();

    await tester.tap(find.byKey(const ValueKey('device-reminder-details')));
    await tester.pumpAndSettle();

    expect(store.value.contentMode, ReminderNotificationContentMode.generic);
    expect(store.saveCount, 0);
    expect(scheduler.cancelKeys, isEmpty);
    expect(find.textContaining('个人进度暂时无法读取'), findsOneWidget);
  });

  testWidgets('关闭详细显示时先替换为通用通知再保存设置', (tester) async {
    final store = _MemoryPreferenceStore(
      const DeviceReminderPreference(
        systemNotificationsEnabled: true,
        contentMode: ReminderNotificationContentMode.projectAndProgress,
      ),
    );
    final scheduler = _FakeScheduler();
    await tester.pumpWidget(_app(store: store, scheduler: scheduler));
    await tester.pumpAndSettle();
    scheduler.cancelKeys.clear();

    await tester.tap(find.byKey(const ValueKey('device-reminder-details')));
    await tester.pumpAndSettle();

    expect(store.value.contentMode, ReminderNotificationContentMode.generic);
    expect(scheduler.lastContent?.title, '同行者');
    expect(scheduler.lastContent?.body, isNot(contains('校园推广')));
    expect(scheduler.cancelKeys, hasLength(1));
  });

  testWidgets('详细设置落盘失败时取消详细调度并恢复通用通知', (tester) async {
    final store = _MemoryPreferenceStore.withSaveError(
      const DeviceReminderPreference(systemNotificationsEnabled: true),
      StateError('synthetic save failure'),
    );
    final scheduler = _FakeScheduler();
    await tester.pumpWidget(_app(store: store, scheduler: scheduler));
    await tester.pumpAndSettle();
    scheduler.cancelKeys.clear();

    await tester.tap(find.byKey(const ValueKey('device-reminder-details')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('confirm-device-reminder-details')),
    );
    await tester.pumpAndSettle();

    expect(store.value.contentMode, ReminderNotificationContentMode.generic);
    expect(scheduler.lastContent?.title, '同行者');
    expect(scheduler.lastContent?.body, isNot(contains('校园推广')));
    expect(scheduler.cancelKeys, hasLength(2));
  });
}

Widget _app({
  required _MemoryPreferenceStore store,
  required _FakeScheduler scheduler,
  _FakeGateway? gateway,
  _FakePlanGateway? planGateway,
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
      planGateway: planGateway ?? _FakePlanGateway(),
      projectName: '校园推广',
      preferenceStore: store,
      scheduler: scheduler,
      timeZoneProvider: const _TimeZoneProvider(),
      idGenerator: _IdGenerator(),
    ),
  ),
);

final class _FakeGateway implements PersonalActionReminderGateway {
  _FakeGateway({this.fromOfflineCache = false, this.rejectLoad = false});

  final bool fromOfflineCache;
  final bool rejectLoad;
  PersonalActionReminder? reminder = PersonalActionReminder(
    reminderId: 'reminder-1',
    revision: 1,
    localTime: LocalReminderTime.fromHourMinute(19, 0),
    updatedAtUtc: DateTime.utc(2030, 3, 9, 18),
  );
  LocalReminderTime? savedTime;

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

final class _FakePlanGateway implements PersonalActionPlanGateway {
  _FakePlanGateway({this.rejectLoad = false, this.noPlan = false});

  final bool rejectLoad;
  final bool noPlan;

  @override
  Future<PersonalActionPlanResult<PersonalActionPlanSnapshot?>> load() async =>
      rejectLoad
      ? const PersonalActionPlanRejected(
          PersonalActionPlanFailureCode.networkUnavailable,
        )
      : PersonalActionPlanSuccess(noPlan ? null : _plan);

  @override
  Future<PersonalActionPlanResult<PersonalActionPlanMutation>> save({
    required int expectedRevision,
    required int? weeklyContactTarget,
    required String statisticsTimeZone,
    required int weekStartIsoDay,
    required String mutationId,
  }) => throw UnimplementedError();

  @override
  Future<void> close() async {}
}

final _plan = PersonalActionPlanSnapshot(
  planId: 'plan-1',
  revision: 1,
  current: PersonalActionPlanVersion(
    revision: 1,
    weeklyContactTarget: 5,
    statisticsTimeZone: 'America/Chicago',
    weekStartIsoDay: DateTime.monday,
    effectiveFromUtc: DateTime.utc(2030, 3, 4),
  ),
  pending: null,
  progress: PersonalActionPlanProgress(
    cycleStartUtc: DateTime.utc(2030, 3, 4),
    cycleUntilUtc: DateTime.utc(2030, 3, 11),
    recordedContactSessions: 3,
    remainingContactSessions: 2,
    asOfUtc: DateTime.utc(2030, 3, 9),
  ),
);

final class _MemoryPreferenceStore implements DeviceReminderPreferenceStore {
  _MemoryPreferenceStore([
    this.value = const DeviceReminderPreference.disabled(),
  ]) : saveError = null;

  _MemoryPreferenceStore.withSaveError(this.value, this.saveError);

  DeviceReminderPreference value;
  final Object? saveError;
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
    if (saveError case final error?) throw error;
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
  var cancelAllCount = 0;

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
  Future<ReminderScheduleResult> cancelAll() async {
    cancelAllCount++;
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
