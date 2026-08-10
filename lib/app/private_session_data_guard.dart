import 'dart:async';

import '../app_session/app_session.dart';
import '../app_session/session_context_gateway.dart';
import '../identity/identity_session.dart';
import '../plans/personal_planning_cache.dart';
import '../reminders/personal_action_reminder.dart';

/// 在可信会话失效后撤销本机仍可能显示的私人状态。
///
/// 网络中断不会删除仍在授权期内的只读缓存，也不会取消已有系统提醒。
/// 离开 workspace 或项目时会删除旧 scope 的待同步草稿。登出、账号切换或
/// 明确的授权失败会清除全部计划缓存并取消提醒。
final class PrivateSessionDataGuard {
  PrivateSessionDataGuard._(this._scheduler, this._planningCache);

  final ReminderNotificationScheduler _scheduler;
  final PersonalPlanningCache _planningCache;
  StreamSubscription<AppSessionSnapshot>? _subscription;
  PersonalPlanningScope? _lastReadyScope;

  static Future<PrivateSessionDataGuard> start({
    required AppSession appSession,
    required ReminderNotificationScheduler scheduler,
    required PersonalPlanningCache planningCache,
  }) async {
    final guard = PrivateSessionDataGuard._(scheduler, planningCache);
    guard._subscription = appSession.changes.listen(
      (snapshot) => unawaited(guard._apply(snapshot)),
    );
    await guard._apply(appSession.current);
    return guard;
  }

  Future<void> _apply(AppSessionSnapshot snapshot) async {
    if (snapshot.stage == AppSessionStage.ready) {
      final context = snapshot.context!;
      final scope = PersonalPlanningScope(
        appUserId: context.appUserId,
        workspaceId: context.workspace.id,
        projectId: context.project.id,
      );
      final previousScope = _lastReadyScope;
      _lastReadyScope = scope;
      if (previousScope == null) return;
      if (previousScope.appUserId != scope.appUserId) {
        await _revokeAll();
      } else if (previousScope != scope) {
        await _planningCache.clearOfflinePlanChange(previousScope);
      }
      return;
    }

    if (snapshot.stage == AppSessionStage.signedOut ||
        snapshot.stage == AppSessionStage.unavailable) {
      _lastReadyScope = null;
      await _revokeAll();
      return;
    }

    if (snapshot.stage != AppSessionStage.failed) return;
    if (_isNetworkFailure(snapshot)) return;

    await _scheduler.cancelAll();
    if (_isAuthorizationFailure(snapshot)) {
      _lastReadyScope = null;
      await _planningCache.clearAll();
    }
  }

  bool _isNetworkFailure(AppSessionSnapshot snapshot) =>
      snapshot.identityFailure == IdentityFailureCode.networkUnavailable ||
      snapshot.contextFailure == SessionContextFailureCode.networkUnavailable;

  bool _isAuthorizationFailure(AppSessionSnapshot snapshot) =>
      snapshot.identityFailure == IdentityFailureCode.sessionMissing ||
      snapshot.identityFailure == IdentityFailureCode.invalidCredentials ||
      snapshot.contextFailure == SessionContextFailureCode.unauthorized;

  Future<void> _revokeAll() async {
    await _scheduler.cancelAll();
    await _planningCache.clearAll();
  }

  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
