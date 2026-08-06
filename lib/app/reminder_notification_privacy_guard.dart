import 'dart:async';

import '../app_session/app_session.dart';
import '../reminders/personal_action_reminder.dart';

/// 在身份或可信上下文失效后撤销 OS 中仍可能显示私人内容的提醒。
final class ReminderNotificationPrivacyGuard {
  ReminderNotificationPrivacyGuard._(this._scheduler);

  final ReminderNotificationScheduler _scheduler;
  StreamSubscription<AppSessionSnapshot>? _subscription;

  static Future<ReminderNotificationPrivacyGuard> start({
    required AppSession appSession,
    required ReminderNotificationScheduler scheduler,
  }) async {
    final guard = ReminderNotificationPrivacyGuard._(scheduler);
    guard._subscription = appSession.changes.listen(
      (snapshot) => unawaited(guard._apply(snapshot)),
    );
    await guard._apply(appSession.current);
    return guard;
  }

  Future<void> _apply(AppSessionSnapshot snapshot) async {
    if (snapshot.stage == AppSessionStage.signedOut ||
        snapshot.stage == AppSessionStage.unavailable ||
        snapshot.stage == AppSessionStage.failed) {
      await _scheduler.cancelAll();
    }
  }

  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
