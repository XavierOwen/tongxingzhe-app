import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/app/private_session_data_guard.dart';
import 'package:tongxingzhe_app/app_session/app_session.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/plans/personal_action_plan.dart';
import 'package:tongxingzhe_app/plans/personal_planning_cache.dart';
import 'package:tongxingzhe_app/reminders/personal_action_reminder.dart';

import '../support/fake_identity_session.dart';
import '../support/fake_session_context_gateway.dart';

void main() {
  test('登出后取消私人提醒并清除计划缓存', () async {
    final identity = FakeIdentitySession(initial: _signedIn);
    final session = AppSession(
      identitySession: identity,
      contextGateway: FakeSessionContextGateway(),
    );
    await session.start();
    addTearDown(session.close);
    addTearDown(identity.close);
    final scheduler = _FakeScheduler();
    final cache = _FakePlanningCache();
    final guard = await PrivateSessionDataGuard.start(
      appSession: session,
      scheduler: scheduler,
      planningCache: cache,
    );
    addTearDown(guard.close);

    expect(scheduler.cancelAllCount, 0);
    expect(cache.clearAllCount, 0);

    await identity.signOut();
    await _waitFor(() => cache.clearAllCount == 1);

    expect(session.current.stage, AppSessionStage.signedOut);
    expect(scheduler.cancelAllCount, 1);
  });

  test('以未登录状态启动时清理上次进程遗留的私人状态', () async {
    final identity = FakeIdentitySession();
    final session = AppSession(
      identitySession: identity,
      contextGateway: FakeSessionContextGateway(),
    );
    await session.start();
    addTearDown(session.close);
    addTearDown(identity.close);
    final scheduler = _FakeScheduler();
    final cache = _FakePlanningCache();
    final guard = await PrivateSessionDataGuard.start(
      appSession: session,
      scheduler: scheduler,
      planningCache: cache,
    );
    addTearDown(guard.close);

    expect(scheduler.cancelAllCount, 1);
    expect(cache.clearAllCount, 1);
  });

  test('网络中断不取消仍有效的通知或删除只读缓存', () async {
    final identity = FakeIdentitySession(initial: _signedIn)
      ..rejectNextWith = const IdentityFailure(
        code: IdentityFailureCode.networkUnavailable,
      );
    final session = AppSession(
      identitySession: identity,
      contextGateway: FakeSessionContextGateway(),
    );
    await session.start();
    addTearDown(session.close);
    addTearDown(identity.close);
    final scheduler = _FakeScheduler();
    final cache = _FakePlanningCache();
    final guard = await PrivateSessionDataGuard.start(
      appSession: session,
      scheduler: scheduler,
      planningCache: cache,
    );
    addTearDown(guard.close);

    expect(
      session.current.identityFailure,
      IdentityFailureCode.networkUnavailable,
    );
    expect(scheduler.cancelAllCount, 0);
    expect(cache.clearAllCount, 0);
  });

  test('凭据失效会取消通知并清除全部计划缓存', () async {
    final identity = FakeIdentitySession(initial: _signedIn)
      ..rejectNextWith = const IdentityFailure(
        code: IdentityFailureCode.invalidCredentials,
      );
    final session = AppSession(
      identitySession: identity,
      contextGateway: FakeSessionContextGateway(),
    );
    await session.start();
    addTearDown(session.close);
    addTearDown(identity.close);
    final scheduler = _FakeScheduler();
    final cache = _FakePlanningCache();
    final guard = await PrivateSessionDataGuard.start(
      appSession: session,
      scheduler: scheduler,
      planningCache: cache,
    );
    addTearDown(guard.close);

    expect(scheduler.cancelAllCount, 1);
    expect(cache.clearAllCount, 1);
  });
}

const _signedIn = IdentitySnapshot(
  stage: IdentityStage.signedIn,
  principal: IdentityPrincipal(
    externalSubject: 'external-subject',
    email: 'person@example.test',
  ),
);

Future<void> _waitFor(bool Function() predicate) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    if (predicate()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('condition did not become true');
}

final class _FakePlanningCache implements PersonalPlanningCache {
  var clearAllCount = 0;

  @override
  Future<void> clearAll() async => clearAllCount++;

  @override
  Future<void> clearScope(PersonalPlanningScope scope) async {}

  @override
  Future<CachedPersonalPlanningValue<PersonalActionPlanSnapshot?>?> readPlan(
    PersonalPlanningScope scope,
  ) async => null;

  @override
  Future<CachedPersonalPlanningValue<PersonalActionReminder?>?> readReminder(
    PersonalPlanningScope scope,
  ) async => null;

  @override
  Future<void> writePlan(
    PersonalPlanningScope scope,
    PersonalActionPlanSnapshot? plan,
    DateTime cachedAtUtc,
  ) async {}

  @override
  Future<void> writeReminder(
    PersonalPlanningScope scope,
    PersonalActionReminder? reminder,
    DateTime cachedAtUtc,
  ) async {}
}

final class _FakeScheduler implements ReminderNotificationScheduler {
  var cancelAllCount = 0;

  @override
  Future<ReminderScheduleResult> cancel({required String scheduleKey}) async =>
      const ReminderScheduleSucceeded();

  @override
  Future<ReminderScheduleResult> cancelAll() async {
    cancelAllCount++;
    return const ReminderScheduleSucceeded();
  }

  @override
  Future<void> close() async {}

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
}
