import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/data/local_database.dart';
import 'package:tongxingzhe_app/foundation/runtime_values.dart';
import 'package:tongxingzhe_app/plans/personal_action_plan.dart';
import 'package:tongxingzhe_app/plans/personal_planning_cache.dart';
import 'package:tongxingzhe_app/reminders/personal_action_reminder.dart';

void main() {
  test('联网读取后按可信 scope 缓存计划，断网只读恢复并带新鲜度', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final cache = DriftPersonalPlanningCache(database);
    final remote = _PlanGateway(PersonalActionPlanSuccess(_plan));
    final gateway = CachedPersonalActionPlanGateway(
      remote: remote,
      cache: cache,
      scopeProvider: () => _scope,
      clock: const _Clock(),
    );

    final online = await gateway.load();
    expect((online as PersonalActionPlanSuccess).fromOfflineCache, isFalse);

    remote.loadResult = const PersonalActionPlanRejected(
      PersonalActionPlanFailureCode.networkUnavailable,
    );
    final offline =
        await gateway.load()
            as PersonalActionPlanSuccess<PersonalActionPlanSnapshot?>;

    expect(offline.fromOfflineCache, isTrue);
    expect(offline.cachedAtUtc, DateTime.utc(2030, 3, 9, 20));
    expect(offline.value?.revision, 2);
    expect(offline.value?.progress.recordedContactSessions, 3);
  });

  test('计划缓存不跨用户、workspace 或项目回退', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final cache = DriftPersonalPlanningCache(database);
    var scope = _scope;
    final remote = _PlanGateway(PersonalActionPlanSuccess(_plan));
    final gateway = CachedPersonalActionPlanGateway(
      remote: remote,
      cache: cache,
      scopeProvider: () => scope,
      clock: const _Clock(),
    );
    await gateway.load();
    remote.loadResult = const PersonalActionPlanRejected(
      PersonalActionPlanFailureCode.networkUnavailable,
    );

    for (final other in [
      _scope.copyWith(appUserId: 'user-2'),
      _scope.copyWith(workspaceId: 'workspace-2'),
      _scope.copyWith(projectId: 'project-2'),
    ]) {
      scope = other;
      final result = await gateway.load();
      expect(result, isA<PersonalActionPlanRejected>());
    }
  });

  test('提醒的空值也可离线恢复，未授权响应清除当前缓存', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final cache = DriftPersonalPlanningCache(database);
    final remote = _ReminderGateway(const PersonalActionReminderSuccess(null));
    var revokedScopes = <PersonalPlanningScope>[];
    final gateway = CachedPersonalActionReminderGateway(
      remote: remote,
      cache: cache,
      scopeProvider: () => _scope,
      clock: const _Clock(),
      onAuthorizationRevoked: (scope) async => revokedScopes.add(scope),
    );
    await gateway.load();
    remote.loadResult = const PersonalActionReminderRejected(
      PersonalActionReminderFailureCode.networkUnavailable,
    );

    final offline =
        await gateway.load()
            as PersonalActionReminderSuccess<PersonalActionReminder?>;
    expect(offline.fromOfflineCache, isTrue);
    expect(offline.value, isNull);

    remote.loadResult = const PersonalActionReminderRejected(
      PersonalActionReminderFailureCode.unauthorized,
    );
    expect(await gateway.load(), isA<PersonalActionReminderRejected>());
    expect(revokedScopes, [_scope]);
    remote.loadResult = const PersonalActionReminderRejected(
      PersonalActionReminderFailureCode.networkUnavailable,
    );
    expect(await gateway.load(), isA<PersonalActionReminderRejected>());
  });

  test('损坏缓存失败关闭，不能伪造成可读计划', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database
        .into(database.dbAppSettings)
        .insert(
          DbAppSettingsCompanion.insert(
            key: 'personal-plan-cache-v1:user-1:workspace-1:project-1',
            value: '{broken',
          ),
        );
    final gateway = CachedPersonalActionPlanGateway(
      remote: _PlanGateway(
        const PersonalActionPlanRejected(
          PersonalActionPlanFailureCode.networkUnavailable,
        ),
      ),
      cache: DriftPersonalPlanningCache(database),
      scopeProvider: () => _scope,
      clock: const _Clock(),
    );

    expect(await gateway.load(), isA<PersonalActionPlanRejected>());
  });

  test('普通服务器拒绝不回退，计划授权失效同时清除同 scope 提醒', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final cache = DriftPersonalPlanningCache(database);
    await cache.writePlan(_scope, _plan, DateTime.utc(2030, 3, 9, 20));
    await cache.writeReminder(
      _scope,
      PersonalActionReminder(
        reminderId: 'reminder-1',
        revision: 1,
        localTime: LocalReminderTime.fromHourMinute(19, 0),
        updatedAtUtc: DateTime.utc(2030, 3, 9, 19),
      ),
      DateTime.utc(2030, 3, 9, 20),
    );
    final planRemote = _PlanGateway(
      const PersonalActionPlanRejected(
        PersonalActionPlanFailureCode.serverRejected,
      ),
    );
    var revokedScopes = <PersonalPlanningScope>[];
    final planGateway = CachedPersonalActionPlanGateway(
      remote: planRemote,
      cache: cache,
      scopeProvider: () => _scope,
      clock: const _Clock(),
      onAuthorizationRevoked: (scope) async => revokedScopes.add(scope),
    );

    expect(await planGateway.load(), isA<PersonalActionPlanRejected>());

    planRemote.loadResult = const PersonalActionPlanRejected(
      PersonalActionPlanFailureCode.unauthorized,
    );
    await planGateway.load();
    expect(revokedScopes, [_scope]);
    final reminderGateway = CachedPersonalActionReminderGateway(
      remote: _ReminderGateway(
        const PersonalActionReminderRejected(
          PersonalActionReminderFailureCode.networkUnavailable,
        ),
      ),
      cache: cache,
      scopeProvider: () => _scope,
      clock: const _Clock(),
    );
    expect(await reminderGateway.load(), isA<PersonalActionReminderRejected>());
  });
}

const _scope = PersonalPlanningScope(
  appUserId: 'user-1',
  workspaceId: 'workspace-1',
  projectId: 'project-1',
);

final _plan = PersonalActionPlanSnapshot(
  planId: 'plan-1',
  revision: 2,
  current: PersonalActionPlanVersion(
    revision: 2,
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
    asOfUtc: DateTime.utc(2030, 3, 9, 19),
  ),
);

final class _PlanGateway implements PersonalActionPlanGateway {
  _PlanGateway(this.loadResult);

  PersonalActionPlanResult<PersonalActionPlanSnapshot?> loadResult;

  @override
  Future<PersonalActionPlanResult<PersonalActionPlanSnapshot?>> load() async =>
      loadResult;

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

final class _ReminderGateway implements PersonalActionReminderGateway {
  _ReminderGateway(this.loadResult);

  PersonalActionReminderResult<PersonalActionReminder?> loadResult;

  @override
  Future<PersonalActionReminderResult<PersonalActionReminder?>> load() async =>
      loadResult;

  @override
  Future<PersonalActionReminderResult<PersonalActionReminderMutation>> save({
    required int expectedRevision,
    required LocalReminderTime? localTime,
    required String mutationId,
  }) => throw UnimplementedError();

  @override
  Future<void> close() async {}
}

final class _Clock implements AppClock {
  const _Clock();

  @override
  DateTime now() => DateTime.utc(2030, 3, 9, 20);
}
