import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/app/private_session_data_guard.dart';
import 'package:tongxingzhe_app/app_session/app_session.dart';
import 'package:tongxingzhe_app/app_session/session_context_gateway.dart';
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

  test('workspace 或项目切换只清除离开 scope 的离线计划草稿', () async {
    final identity = FakeIdentitySession(initial: _signedIn);
    final contextGateway = FakeSessionContextGateway(
      availableContexts: const [
        syntheticSessionContext,
        syntheticSecondSessionContext,
        _otherWorkspaceSessionContext,
      ],
      selectedContexts: const {
        '55555555-5555-4555-8555-555555555555': syntheticSecondSessionContext,
        '99999999-9999-4999-8999-999999999999': _otherWorkspaceSessionContext,
      },
    );
    final session = AppSession(
      identitySession: identity,
      contextGateway: contextGateway,
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

    await session.selectProject(syntheticSecondSessionContext.project.id);
    await _waitFor(() => cache.clearedOfflineScopes.length == 1);
    await session.selectProject(_otherWorkspaceSessionContext.project.id);
    await _waitFor(() => cache.clearedOfflineScopes.length == 2);

    expect(cache.clearedOfflineScopes, [
      const PersonalPlanningScope(
        appUserId: '11111111-1111-4111-8111-111111111111',
        workspaceId: '22222222-2222-4222-8222-222222222222',
        projectId: '33333333-3333-4333-8333-333333333333',
      ),
      const PersonalPlanningScope(
        appUserId: '11111111-1111-4111-8111-111111111111',
        workspaceId: '22222222-2222-4222-8222-222222222222',
        projectId: '55555555-5555-4555-8555-555555555555',
      ),
    ]);
    expect(cache.clearAllCount, 0);
    expect(scheduler.cancelAllCount, 0);
  });
}

const _signedIn = IdentitySnapshot(
  stage: IdentityStage.signedIn,
  principal: IdentityPrincipal(
    externalSubject: 'external-subject',
    email: 'person@example.test',
  ),
);

const _otherWorkspaceSessionContext = TrustedSessionContext(
  appUserId: '11111111-1111-4111-8111-111111111111',
  workspace: WorkspaceContext(
    id: '88888888-8888-4888-8888-888888888888',
    kind: WorkspaceKind.organization,
    name: '组织空间',
  ),
  project: ProjectContext(
    id: '99999999-9999-4999-8999-999999999999',
    name: '组织项目',
  ),
  questionnaireVersion: QuestionnaireVersionContext(
    id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    versionNumber: 1,
  ),
  capabilities: {'record_contact'},
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
  final clearedOfflineScopes = <PersonalPlanningScope>[];

  @override
  Future<void> clearAll() async => clearAllCount++;

  @override
  Future<void> clearScope(PersonalPlanningScope scope) async {}

  @override
  Future<void> clearOfflinePlanChange(PersonalPlanningScope scope) async {
    clearedOfflineScopes.add(scope);
  }

  @override
  Future<PersonalActionPlanOfflineChange?> readOfflinePlanChange(
    PersonalPlanningScope scope,
  ) async => null;

  @override
  Future<void> writeOfflinePlanChange(
    PersonalPlanningScope scope,
    PersonalActionPlanOfflineChange change,
  ) async {}

  @override
  Future<PersonalActionPlanOfflineChange?> queueOfflinePlanChange(
    PersonalPlanningScope scope,
    PersonalActionPlanOfflineChange change, {
    required bool replaceExisting,
  }) async => change;

  @override
  Future<void> acceptPlan(
    PersonalPlanningScope scope,
    PersonalActionPlanSnapshot plan,
    DateTime cachedAtUtc,
  ) async {}

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
