import 'dart:async';
import 'dart:convert';

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

  test('断网保存一项计划修改并在重启后恢复同一 mutation', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final cache = DriftPersonalPlanningCache(database);
    final remote = _PlanGateway(PersonalActionPlanSuccess(_plan))
      ..saveResult = const PersonalActionPlanRejected(
        PersonalActionPlanFailureCode.networkUnavailable,
      );
    final gateway = CachedPersonalActionPlanGateway(
      remote: remote,
      cache: cache,
      scopeProvider: () => _scope,
      clock: const _Clock(),
    );
    await gateway.load();

    final queued = await gateway.save(
      expectedRevision: 2,
      weeklyContactTarget: 7,
      statisticsTimeZone: 'Asia/Shanghai',
      weekStartIsoDay: DateTime.sunday,
      mutationId: 'offline-mutation-1',
    );

    expect(queued, isA<PersonalActionPlanQueued>());
    final restarted = CachedPersonalActionPlanGateway(
      remote: _PlanGateway(
        const PersonalActionPlanRejected(
          PersonalActionPlanFailureCode.networkUnavailable,
        ),
      ),
      cache: cache,
      scopeProvider: () => _scope,
      clock: const _Clock(),
    );
    final offline =
        await restarted.load()
            as PersonalActionPlanSuccess<PersonalActionPlanSnapshot?>;

    expect(offline.fromOfflineCache, isTrue);
    expect(offline.offlineChange?.expectedRevision, 2);
    expect(offline.offlineChange?.weeklyContactTarget, 7);
    expect(offline.offlineChange?.statisticsTimeZone, 'Asia/Shanghai');
    expect(offline.offlineChange?.weekStartIsoDay, DateTime.sunday);
    expect(offline.offlineChange?.mutationId, 'offline-mutation-1');
    expect(offline.offlineChange?.queuedAtUtc, DateTime.utc(2030, 3, 9, 20));
  });

  test('从未取得可信计划快照时断网保存失败关闭', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final cache = DriftPersonalPlanningCache(database);
    final remote =
        _PlanGateway(
            const PersonalActionPlanRejected(
              PersonalActionPlanFailureCode.networkUnavailable,
            ),
          )
          ..saveResult = const PersonalActionPlanRejected(
            PersonalActionPlanFailureCode.networkUnavailable,
          );
    final gateway = CachedPersonalActionPlanGateway(
      remote: remote,
      cache: cache,
      scopeProvider: () => _scope,
      clock: const _Clock(),
    );

    final result = await gateway.save(
      expectedRevision: 0,
      weeklyContactTarget: 2,
      statisticsTimeZone: 'America/Chicago',
      weekStartIsoDay: DateTime.monday,
      mutationId: 'offline-mutation-1',
    );

    expect(
      result,
      isA<PersonalActionPlanRejected<PersonalActionPlanMutation>>(),
    );
    expect(await cache.readOfflinePlanChange(_scope), isNull);
  });

  test('重试同一离线 mutation 时保留最初排队时间', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final cache = DriftPersonalPlanningCache(database);
    await cache.writePlan(_scope, _plan, DateTime.utc(2030, 3, 9, 18));
    await cache.writeOfflinePlanChange(
      _scope,
      PersonalActionPlanOfflineChange(
        expectedRevision: 2,
        weeklyContactTarget: 7,
        statisticsTimeZone: 'Asia/Shanghai',
        weekStartIsoDay: DateTime.sunday,
        mutationId: 'offline-mutation-1',
        queuedAtUtc: DateTime.utc(2030, 3, 9, 19),
      ),
    );
    final remote = _PlanGateway(PersonalActionPlanSuccess(_plan))
      ..saveResult = const PersonalActionPlanRejected(
        PersonalActionPlanFailureCode.networkUnavailable,
      );
    final gateway = CachedPersonalActionPlanGateway(
      remote: remote,
      cache: cache,
      scopeProvider: () => _scope,
      clock: const _Clock(),
    );

    final result = await gateway.save(
      expectedRevision: 2,
      weeklyContactTarget: 7,
      statisticsTimeZone: 'Asia/Shanghai',
      weekStartIsoDay: DateTime.sunday,
      mutationId: 'offline-mutation-1',
    );

    final queued =
        result as PersonalActionPlanQueued<PersonalActionPlanMutation>;
    expect(queued.offlineChange.queuedAtUtc, DateTime.utc(2030, 3, 9, 19));
  });

  test('并发离线保存不覆盖同 scope 的第一项草稿', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final cache = DriftPersonalPlanningCache(database);
    await cache.writePlan(_scope, _plan, DateTime.utc(2030, 3, 9, 18));
    final remote = _PlanGateway(PersonalActionPlanSuccess(_plan))
      ..saveResult = const PersonalActionPlanRejected(
        PersonalActionPlanFailureCode.networkUnavailable,
      );
    final gateway = CachedPersonalActionPlanGateway(
      remote: remote,
      cache: cache,
      scopeProvider: () => _scope,
      clock: const _Clock(),
    );

    final results = await Future.wait([
      gateway.save(
        expectedRevision: 2,
        weeklyContactTarget: 6,
        statisticsTimeZone: 'America/Chicago',
        weekStartIsoDay: DateTime.monday,
        mutationId: 'offline-mutation-1',
      ),
      gateway.save(
        expectedRevision: 2,
        weeklyContactTarget: 7,
        statisticsTimeZone: 'Asia/Shanghai',
        weekStartIsoDay: DateTime.sunday,
        mutationId: 'offline-mutation-2',
      ),
    ]);

    expect(results.whereType<PersonalActionPlanQueued>(), hasLength(1));
    expect(
      results.whereType<PersonalActionPlanRejected>().single.code,
      PersonalActionPlanFailureCode.pendingChange,
    );
    expect(
      (await cache.readOfflinePlanChange(_scope))?.mutationId,
      anyOf('offline-mutation-1', 'offline-mutation-2'),
    );
  });

  test('用户明确采用本机草稿时可原子替换旧排队修改', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final cache = DriftPersonalPlanningCache(database);
    await cache.writePlan(_scope, _plan, DateTime.utc(2030, 3, 9, 18));
    await cache.writeOfflinePlanChange(
      _scope,
      PersonalActionPlanOfflineChange(
        expectedRevision: 2,
        weeklyContactTarget: 7,
        statisticsTimeZone: 'Asia/Shanghai',
        weekStartIsoDay: DateTime.sunday,
        mutationId: 'offline-mutation-1',
        queuedAtUtc: DateTime.utc(2030, 3, 9, 19),
      ),
    );
    final remote = _PlanGateway(PersonalActionPlanSuccess(_plan))
      ..saveResult = const PersonalActionPlanRejected(
        PersonalActionPlanFailureCode.networkUnavailable,
      );
    final gateway = CachedPersonalActionPlanGateway(
      remote: remote,
      cache: cache,
      scopeProvider: () => _scope,
      clock: const _Clock(),
    );

    final result = await gateway.save(
      expectedRevision: 2,
      weeklyContactTarget: 8,
      statisticsTimeZone: 'Europe/London',
      weekStartIsoDay: DateTime.monday,
      mutationId: 'replacement-mutation',
      replaceOfflineChange: true,
    );

    expect(result, isA<PersonalActionPlanQueued>());
    final stored = await cache.readOfflinePlanChange(_scope);
    expect(stored?.mutationId, 'replacement-mutation');
    expect(stored?.weeklyContactTarget, 8);
  });

  test('scope 在草稿写入期间改变时不会复活旧 scope 草稿', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final driftCache = DriftPersonalPlanningCache(database);
    await driftCache.writePlan(_scope, _plan, DateTime.utc(2030, 3, 9, 18));
    final cache = _BlockingQueueCache(driftCache);
    var scope = _scope;
    final remote = _PlanGateway(PersonalActionPlanSuccess(_plan))
      ..saveResult = const PersonalActionPlanRejected(
        PersonalActionPlanFailureCode.networkUnavailable,
      );
    final gateway = CachedPersonalActionPlanGateway(
      remote: remote,
      cache: cache,
      scopeProvider: () => scope,
      clock: const _Clock(),
    );

    final save = gateway.save(
      expectedRevision: 2,
      weeklyContactTarget: 7,
      statisticsTimeZone: 'Asia/Shanghai',
      weekStartIsoDay: DateTime.sunday,
      mutationId: 'offline-mutation-1',
    );
    await cache.queueStarted.future;
    scope = _scope.copyWith(projectId: 'project-2');
    cache.releaseQueue.complete();

    final result = await save;

    expect(result, isA<PersonalActionPlanRejected>());
    expect(await driftCache.readOfflinePlanChange(_scope), isNull);
  });

  test('联网读取后用原 mutation 重放并原子接受服务端快照', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final cache = DriftPersonalPlanningCache(database);
    await cache.writePlan(_scope, _plan, DateTime.utc(2030, 3, 9, 19));
    await cache.writeOfflinePlanChange(
      _scope,
      PersonalActionPlanOfflineChange(
        expectedRevision: 2,
        weeklyContactTarget: 7,
        statisticsTimeZone: 'Asia/Shanghai',
        weekStartIsoDay: DateTime.sunday,
        mutationId: 'offline-mutation-1',
        queuedAtUtc: DateTime.utc(2030, 3, 9, 20),
      ),
    );
    final acceptedPlan = _copyPlan(
      revision: 3,
      pending: PersonalActionPlanVersion(
        revision: 3,
        weeklyContactTarget: 7,
        statisticsTimeZone: 'Asia/Shanghai',
        weekStartIsoDay: DateTime.sunday,
        effectiveFromUtc: DateTime.utc(2030, 3, 17, 16),
      ),
    );
    final remote = _PlanGateway(PersonalActionPlanSuccess(_plan))
      ..saveResult = PersonalActionPlanSuccess(
        PersonalActionPlanMutation(
          plan: acceptedPlan,
          duplicate: false,
          acceptedRevision: 3,
        ),
      );
    final gateway = CachedPersonalActionPlanGateway(
      remote: remote,
      cache: cache,
      scopeProvider: () => _scope,
      clock: const _Clock(),
    );

    final loaded =
        await gateway.load()
            as PersonalActionPlanSuccess<PersonalActionPlanSnapshot?>;

    expect(loaded.value?.revision, 3);
    expect(loaded.offlineChange, isNull);
    expect(remote.savedExpectedRevision, 2);
    expect(remote.savedMutationId, 'offline-mutation-1');
    expect(await cache.readOfflinePlanChange(_scope), isNull);
    expect((await cache.readPlan(_scope))?.value?.revision, 3);
  });

  test('revision 冲突同时保留服务器快照和离线草稿并可放弃草稿', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final cache = DriftPersonalPlanningCache(database);
    final offlineChange = PersonalActionPlanOfflineChange(
      expectedRevision: 2,
      weeklyContactTarget: 7,
      statisticsTimeZone: 'Asia/Shanghai',
      weekStartIsoDay: DateTime.sunday,
      mutationId: 'offline-mutation-1',
      queuedAtUtc: DateTime.utc(2030, 3, 9, 20),
    );
    await cache.writeOfflinePlanChange(_scope, offlineChange);
    final serverPlan = _copyPlan(revision: 3, pending: null);
    final remote = _PlanGateway(PersonalActionPlanSuccess(serverPlan))
      ..saveResult = const PersonalActionPlanRejected(
        PersonalActionPlanFailureCode.conflict,
      );
    final gateway = CachedPersonalActionPlanGateway(
      remote: remote,
      cache: cache,
      scopeProvider: () => _scope,
      clock: const _Clock(),
    );

    final conflicted =
        await gateway.load()
            as PersonalActionPlanSuccess<PersonalActionPlanSnapshot?>;

    expect(conflicted.value?.revision, 3);
    expect(conflicted.offlineChange?.mutationId, 'offline-mutation-1');
    expect(
      conflicted.offlineChangeFailure,
      PersonalActionPlanFailureCode.conflict,
    );
    expect(await gateway.discardOfflineChange(), isTrue);
    expect(await cache.readOfflinePlanChange(_scope), isNull);
    expect((await cache.readPlan(_scope))?.value?.revision, 3);
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

  test('损坏离线计划草稿被删除且不进入同步状态', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final cache = DriftPersonalPlanningCache(database);
    await cache.writePlan(_scope, _plan, DateTime.utc(2030, 3, 9, 20));
    await database
        .into(database.dbAppSettings)
        .insert(
          DbAppSettingsCompanion.insert(
            key:
                'personal-plan-offline-change-v1:'
                'user-1:workspace-1:project-1',
            value: '{broken',
          ),
        );
    final gateway = CachedPersonalActionPlanGateway(
      remote: _PlanGateway(
        const PersonalActionPlanRejected(
          PersonalActionPlanFailureCode.networkUnavailable,
        ),
      ),
      cache: cache,
      scopeProvider: () => _scope,
      clock: const _Clock(),
    );

    final result =
        await gateway.load()
            as PersonalActionPlanSuccess<PersonalActionPlanSnapshot?>;

    expect(result.offlineChange, isNull);
    expect(await cache.readOfflinePlanChange(_scope), isNull);
  });

  test('超出 HTTP 字段合同的离线草稿失败关闭并删除', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final cache = DriftPersonalPlanningCache(database);
    for (final invalid in [
      {'statistics_time_zone': '   ', 'mutation_id': 'mutation-1'},
      {'statistics_time_zone': 'America/Chicago', 'mutation_id': 'x' * 121},
    ]) {
      await database
          .into(database.dbAppSettings)
          .insertOnConflictUpdate(
            DbAppSettingsCompanion.insert(
              key:
                  'personal-plan-offline-change-v1:'
                  'user-1:workspace-1:project-1',
              value: jsonEncode({
                'schema_version': 1,
                'expected_revision': 2,
                'weekly_contact_target': 7,
                'statistics_time_zone': invalid['statistics_time_zone'],
                'week_start_iso_day': DateTime.monday,
                'mutation_id': invalid['mutation_id'],
                'queued_at_utc': '2030-03-09T20:00:00.000Z',
              }),
            ),
          );

      expect(await cache.readOfflinePlanChange(_scope), isNull);
    }
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
    await cache.writeOfflinePlanChange(
      _scope,
      PersonalActionPlanOfflineChange(
        expectedRevision: 2,
        weeklyContactTarget: 7,
        statisticsTimeZone: 'Asia/Shanghai',
        weekStartIsoDay: DateTime.sunday,
        mutationId: 'offline-mutation-1',
        queuedAtUtc: DateTime.utc(2030, 3, 9, 20),
      ),
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
    expect(await cache.readOfflinePlanChange(_scope), isNull);
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

final class _BlockingQueueCache implements PersonalPlanningCache {
  _BlockingQueueCache(this.delegate);

  final PersonalPlanningCache delegate;
  final queueStarted = Completer<void>();
  final releaseQueue = Completer<void>();

  @override
  Future<PersonalActionPlanOfflineChange?> queueOfflinePlanChange(
    PersonalPlanningScope scope,
    PersonalActionPlanOfflineChange change, {
    required bool replaceExisting,
  }) async {
    queueStarted.complete();
    await releaseQueue.future;
    return delegate.queueOfflinePlanChange(
      scope,
      change,
      replaceExisting: replaceExisting,
    );
  }

  @override
  Future<void> acceptPlan(
    PersonalPlanningScope scope,
    PersonalActionPlanSnapshot plan,
    DateTime cachedAtUtc,
  ) => delegate.acceptPlan(scope, plan, cachedAtUtc);

  @override
  Future<void> clearAll() => delegate.clearAll();

  @override
  Future<void> clearOfflinePlanChange(PersonalPlanningScope scope) =>
      delegate.clearOfflinePlanChange(scope);

  @override
  Future<void> clearScope(PersonalPlanningScope scope) =>
      delegate.clearScope(scope);

  @override
  Future<PersonalActionPlanOfflineChange?> readOfflinePlanChange(
    PersonalPlanningScope scope,
  ) => delegate.readOfflinePlanChange(scope);

  @override
  Future<CachedPersonalPlanningValue<PersonalActionPlanSnapshot?>?> readPlan(
    PersonalPlanningScope scope,
  ) => delegate.readPlan(scope);

  @override
  Future<CachedPersonalPlanningValue<PersonalActionReminder?>?> readReminder(
    PersonalPlanningScope scope,
  ) => delegate.readReminder(scope);

  @override
  Future<void> writeOfflinePlanChange(
    PersonalPlanningScope scope,
    PersonalActionPlanOfflineChange change,
  ) => delegate.writeOfflinePlanChange(scope, change);

  @override
  Future<void> writePlan(
    PersonalPlanningScope scope,
    PersonalActionPlanSnapshot? plan,
    DateTime cachedAtUtc,
  ) => delegate.writePlan(scope, plan, cachedAtUtc);

  @override
  Future<void> writeReminder(
    PersonalPlanningScope scope,
    PersonalActionReminder? reminder,
    DateTime cachedAtUtc,
  ) => delegate.writeReminder(scope, reminder, cachedAtUtc);
}

final class _PlanGateway implements PersonalActionPlanGateway {
  _PlanGateway(this.loadResult);

  PersonalActionPlanResult<PersonalActionPlanSnapshot?> loadResult;
  PersonalActionPlanResult<PersonalActionPlanMutation> saveResult =
      const PersonalActionPlanRejected(
        PersonalActionPlanFailureCode.serverRejected,
      );
  int? savedExpectedRevision;
  String? savedMutationId;

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
    bool replaceOfflineChange = false,
  }) async {
    savedExpectedRevision = expectedRevision;
    savedMutationId = mutationId;
    return saveResult;
  }

  @override
  Future<bool> discardOfflineChange() async => true;

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

PersonalActionPlanSnapshot _copyPlan({
  required int revision,
  required PersonalActionPlanVersion? pending,
}) => PersonalActionPlanSnapshot(
  planId: _plan.planId,
  revision: revision,
  current: _plan.current,
  pending: pending,
  progress: _plan.progress,
);
