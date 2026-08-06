import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/app/reminder_notification_privacy_guard.dart';
import 'package:tongxingzhe_app/app_session/app_session.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/reminders/personal_action_reminder.dart';

import '../support/fake_identity_session.dart';
import '../support/fake_session_context_gateway.dart';

void main() {
  test('登出后中央生命周期取消全部私人提醒', () async {
    final identity = FakeIdentitySession(initial: _signedIn);
    final session = AppSession(
      identitySession: identity,
      contextGateway: FakeSessionContextGateway(),
    );
    await session.start();
    addTearDown(session.close);
    addTearDown(identity.close);
    final scheduler = _FakeScheduler();
    final guard = await ReminderNotificationPrivacyGuard.start(
      appSession: session,
      scheduler: scheduler,
    );
    addTearDown(guard.close);

    expect(scheduler.cancelAllCount, 0);

    await identity.signOut();
    await _waitFor(() => scheduler.cancelAllCount == 1);

    expect(session.current.stage, AppSessionStage.signedOut);
  });

  test('以未登录状态启动时清理上次进程遗留的私人提醒', () async {
    final identity = FakeIdentitySession();
    final session = AppSession(
      identitySession: identity,
      contextGateway: FakeSessionContextGateway(),
    );
    await session.start();
    addTearDown(session.close);
    addTearDown(identity.close);
    final scheduler = _FakeScheduler();
    final guard = await ReminderNotificationPrivacyGuard.start(
      appSession: session,
      scheduler: scheduler,
    );
    addTearDown(guard.close);

    expect(scheduler.cancelAllCount, 1);
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
