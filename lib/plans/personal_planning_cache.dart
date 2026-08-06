import 'dart:convert';

import 'package:drift/drift.dart';

import '../data/local_database.dart';
import '../foundation/runtime_values.dart';
import '../reminders/personal_action_reminder.dart';
import 'personal_action_plan.dart';

final class PersonalPlanningScope {
  const PersonalPlanningScope({
    required this.appUserId,
    required this.workspaceId,
    required this.projectId,
  });

  final String appUserId;
  final String workspaceId;
  final String projectId;

  PersonalPlanningScope copyWith({
    String? appUserId,
    String? workspaceId,
    String? projectId,
  }) => PersonalPlanningScope(
    appUserId: appUserId ?? this.appUserId,
    workspaceId: workspaceId ?? this.workspaceId,
    projectId: projectId ?? this.projectId,
  );

  @override
  bool operator ==(Object other) =>
      other is PersonalPlanningScope &&
      other.appUserId == appUserId &&
      other.workspaceId == workspaceId &&
      other.projectId == projectId;

  @override
  int get hashCode => Object.hash(appUserId, workspaceId, projectId);
}

final class CachedPersonalPlanningValue<T> {
  const CachedPersonalPlanningValue({
    required this.value,
    required this.cachedAtUtc,
  });

  final T value;
  final DateTime cachedAtUtc;
}

abstract interface class PersonalPlanningCache {
  Future<CachedPersonalPlanningValue<PersonalActionPlanSnapshot?>?> readPlan(
    PersonalPlanningScope scope,
  );

  Future<void> writePlan(
    PersonalPlanningScope scope,
    PersonalActionPlanSnapshot? plan,
    DateTime cachedAtUtc,
  );

  Future<CachedPersonalPlanningValue<PersonalActionReminder?>?> readReminder(
    PersonalPlanningScope scope,
  );

  Future<void> writeReminder(
    PersonalPlanningScope scope,
    PersonalActionReminder? reminder,
    DateTime cachedAtUtc,
  );

  Future<void> clearScope(PersonalPlanningScope scope);

  Future<void> clearAll();
}

typedef PersonalPlanningAuthorizationRevoked =
    Future<void> Function(PersonalPlanningScope scope);

final class DriftPersonalPlanningCache implements PersonalPlanningCache {
  const DriftPersonalPlanningCache(this.database);

  final LocalDatabase database;

  @override
  Future<CachedPersonalPlanningValue<PersonalActionPlanSnapshot?>?> readPlan(
    PersonalPlanningScope scope,
  ) => _read(
    _planKey(scope),
    valueKey: 'plan',
    parse: (value) => value == null ? null : _parsePlan(value),
  );

  @override
  Future<void> writePlan(
    PersonalPlanningScope scope,
    PersonalActionPlanSnapshot? plan,
    DateTime cachedAtUtc,
  ) => _write(
    _planKey(scope),
    valueKey: 'plan',
    value: plan == null ? null : _planJson(plan),
    cachedAtUtc: cachedAtUtc,
  );

  @override
  Future<CachedPersonalPlanningValue<PersonalActionReminder?>?> readReminder(
    PersonalPlanningScope scope,
  ) => _read(
    _reminderKey(scope),
    valueKey: 'reminder',
    parse: (value) => value == null ? null : _parseReminder(value),
  );

  @override
  Future<void> writeReminder(
    PersonalPlanningScope scope,
    PersonalActionReminder? reminder,
    DateTime cachedAtUtc,
  ) => _write(
    _reminderKey(scope),
    valueKey: 'reminder',
    value: reminder == null ? null : _reminderJson(reminder),
    cachedAtUtc: cachedAtUtc,
  );

  @override
  Future<void> clearScope(PersonalPlanningScope scope) =>
      database.transaction(() async {
        await _delete(_planKey(scope));
        await _delete(_reminderKey(scope));
      });

  @override
  Future<void> clearAll() async {
    await (database.delete(database.dbAppSettings)..where(
          (row) =>
              row.key.like('personal-plan-cache-v1:%') |
              row.key.like('personal-reminder-cache-v1:%'),
        ))
        .go();
  }

  Future<CachedPersonalPlanningValue<T>?> _read<T>(
    String key, {
    required String valueKey,
    required T Function(Object? value) parse,
  }) async {
    final query = database.select(database.dbAppSettings)
      ..where((row) => row.key.equals(key));
    final row = await query.getSingleOrNull();
    if (row == null) return null;
    try {
      final root = _object(jsonDecode(row.value));
      if (!_hasOnlyKeys(root, ['schema_version', 'cached_at_utc', valueKey]) ||
          root['schema_version'] != 1) {
        throw const FormatException('invalid personal planning cache root');
      }
      return CachedPersonalPlanningValue(
        value: parse(root[valueKey]),
        cachedAtUtc: _timestamp(root['cached_at_utc']),
      );
    } on FormatException {
      await _delete(key);
      return null;
    }
  }

  Future<void> _write(
    String key, {
    required String valueKey,
    required Object? value,
    required DateTime cachedAtUtc,
  }) async {
    await database
        .into(database.dbAppSettings)
        .insertOnConflictUpdate(
          DbAppSettingsCompanion.insert(
            key: key,
            value: jsonEncode({
              'schema_version': 1,
              'cached_at_utc': cachedAtUtc.toUtc().toIso8601String(),
              valueKey: value,
            }),
          ),
        );
  }

  Future<void> _delete(String key) async {
    await (database.delete(
      database.dbAppSettings,
    )..where((row) => row.key.equals(key))).go();
  }

  String _planKey(PersonalPlanningScope scope) => [
    'personal-plan-cache-v1',
    scope.appUserId,
    scope.workspaceId,
    scope.projectId,
  ].join(':');

  String _reminderKey(PersonalPlanningScope scope) => [
    'personal-reminder-cache-v1',
    scope.appUserId,
    scope.workspaceId,
    scope.projectId,
  ].join(':');
}

final class CachedPersonalActionPlanGateway
    implements PersonalActionPlanGateway {
  const CachedPersonalActionPlanGateway({
    required this.remote,
    required this.cache,
    required this.scopeProvider,
    required this.clock,
    this.onAuthorizationRevoked,
  });

  final PersonalActionPlanGateway remote;
  final PersonalPlanningCache cache;
  final PersonalPlanningScope? Function() scopeProvider;
  final AppClock clock;
  final PersonalPlanningAuthorizationRevoked? onAuthorizationRevoked;

  @override
  Future<PersonalActionPlanResult<PersonalActionPlanSnapshot?>> load() async {
    final scope = scopeProvider();
    final result = await remote.load();
    if (scope == null || scopeProvider() != scope) return result;
    switch (result) {
      case PersonalActionPlanSuccess<PersonalActionPlanSnapshot?>(:final value):
        await _ignoreCacheFailure(
          () => cache.writePlan(scope, value, clock.now().toUtc()),
        );
        return result;
      case PersonalActionPlanRejected<PersonalActionPlanSnapshot?>(:final code):
        if (code == PersonalActionPlanFailureCode.unauthorized) {
          await _revokeScopeAccess(cache, scope, onAuthorizationRevoked);
          return result;
        }
        if (code != PersonalActionPlanFailureCode.networkUnavailable) {
          return result;
        }
        try {
          final cached = await cache.readPlan(scope);
          if (cached != null) {
            return PersonalActionPlanSuccess(
              cached.value,
              fromOfflineCache: true,
              cachedAtUtc: cached.cachedAtUtc,
            );
          }
        } on Object {
          return result;
        }
    }
    return result;
  }

  @override
  Future<PersonalActionPlanResult<PersonalActionPlanMutation>> save({
    required int expectedRevision,
    required int? weeklyContactTarget,
    required String statisticsTimeZone,
    required int weekStartIsoDay,
    required String mutationId,
  }) async {
    final scope = scopeProvider();
    final result = await remote.save(
      expectedRevision: expectedRevision,
      weeklyContactTarget: weeklyContactTarget,
      statisticsTimeZone: statisticsTimeZone,
      weekStartIsoDay: weekStartIsoDay,
      mutationId: mutationId,
    );
    if (scope == null || scopeProvider() != scope) return result;
    switch (result) {
      case PersonalActionPlanSuccess<PersonalActionPlanMutation>(:final value):
        await _ignoreCacheFailure(
          () => cache.writePlan(scope, value.plan, clock.now().toUtc()),
        );
        return result;
      case PersonalActionPlanRejected<PersonalActionPlanMutation>(:final code):
        if (code == PersonalActionPlanFailureCode.unauthorized) {
          await _revokeScopeAccess(cache, scope, onAuthorizationRevoked);
        }
    }
    return result;
  }

  @override
  Future<void> close() => remote.close();
}

final class CachedPersonalActionReminderGateway
    implements PersonalActionReminderGateway {
  const CachedPersonalActionReminderGateway({
    required this.remote,
    required this.cache,
    required this.scopeProvider,
    required this.clock,
    this.onAuthorizationRevoked,
  });

  final PersonalActionReminderGateway remote;
  final PersonalPlanningCache cache;
  final PersonalPlanningScope? Function() scopeProvider;
  final AppClock clock;
  final PersonalPlanningAuthorizationRevoked? onAuthorizationRevoked;

  @override
  Future<PersonalActionReminderResult<PersonalActionReminder?>> load() async {
    final scope = scopeProvider();
    final result = await remote.load();
    if (scope == null || scopeProvider() != scope) return result;
    switch (result) {
      case PersonalActionReminderSuccess<PersonalActionReminder?>(:final value):
        await _ignoreCacheFailure(
          () => cache.writeReminder(scope, value, clock.now().toUtc()),
        );
        return result;
      case PersonalActionReminderRejected<PersonalActionReminder?>(:final code):
        if (code == PersonalActionReminderFailureCode.unauthorized) {
          await _revokeScopeAccess(cache, scope, onAuthorizationRevoked);
          return result;
        }
        if (code != PersonalActionReminderFailureCode.networkUnavailable) {
          return result;
        }
        try {
          final cached = await cache.readReminder(scope);
          if (cached != null) {
            return PersonalActionReminderSuccess(
              cached.value,
              fromOfflineCache: true,
              cachedAtUtc: cached.cachedAtUtc,
            );
          }
        } on Object {
          return result;
        }
    }
    return result;
  }

  @override
  Future<PersonalActionReminderResult<PersonalActionReminderMutation>> save({
    required int expectedRevision,
    required LocalReminderTime? localTime,
    required String mutationId,
  }) async {
    final scope = scopeProvider();
    final result = await remote.save(
      expectedRevision: expectedRevision,
      localTime: localTime,
      mutationId: mutationId,
    );
    if (scope == null || scopeProvider() != scope) return result;
    switch (result) {
      case PersonalActionReminderSuccess<PersonalActionReminderMutation>(
        :final value,
      ):
        await _ignoreCacheFailure(
          () => cache.writeReminder(scope, value.reminder, clock.now().toUtc()),
        );
        return result;
      case PersonalActionReminderRejected<PersonalActionReminderMutation>(
        :final code,
      ):
        if (code == PersonalActionReminderFailureCode.unauthorized) {
          await _revokeScopeAccess(cache, scope, onAuthorizationRevoked);
        }
    }
    return result;
  }

  @override
  Future<void> close() => remote.close();
}

Future<void> _ignoreCacheFailure(Future<void> Function() operation) async {
  try {
    await operation();
  } on Object {
    // The online result remains authoritative when local cache I/O fails.
  }
}

Future<void> _revokeScopeAccess(
  PersonalPlanningCache cache,
  PersonalPlanningScope scope,
  PersonalPlanningAuthorizationRevoked? onAuthorizationRevoked,
) async {
  await _ignoreCacheFailure(() => cache.clearScope(scope));
  if (onAuthorizationRevoked == null) return;
  try {
    await onAuthorizationRevoked(scope);
  } on Object {
    // The authorization rejection remains authoritative if OS cleanup fails.
  }
}

Map<String, Object?> _planJson(PersonalActionPlanSnapshot plan) => {
  'plan_id': plan.planId,
  'revision': plan.revision,
  'current': _versionJson(plan.current),
  'pending': plan.pending == null ? null : _versionJson(plan.pending!),
  'progress': _progressJson(plan.progress),
};

Map<String, Object?> _versionJson(PersonalActionPlanVersion version) => {
  'revision': version.revision,
  'weekly_contact_target': version.weeklyContactTarget,
  'statistics_time_zone': version.statisticsTimeZone,
  'week_start_iso_day': version.weekStartIsoDay,
  'effective_from_utc': version.effectiveFromUtc.toUtc().toIso8601String(),
};

Map<String, Object?> _progressJson(PersonalActionPlanProgress progress) => {
  'cycle_start_utc': progress.cycleStartUtc.toUtc().toIso8601String(),
  'cycle_until_utc': progress.cycleUntilUtc.toUtc().toIso8601String(),
  'recorded_contact_sessions': progress.recordedContactSessions,
  'remaining_contact_sessions': progress.remainingContactSessions,
  'as_of_utc': progress.asOfUtc.toUtc().toIso8601String(),
};

PersonalActionPlanSnapshot _parsePlan(Object? value) {
  final root = _object(value);
  _requireKeys(root, ['plan_id', 'revision', 'current', 'pending', 'progress']);
  final pending = root['pending'];
  return PersonalActionPlanSnapshot(
    planId: _string(root['plan_id']),
    revision: _integer(root['revision'], 1, 0x7fffffff),
    current: _parseVersion(root['current']),
    pending: pending == null ? null : _parseVersion(pending),
    progress: _parseProgress(root['progress']),
  );
}

PersonalActionPlanVersion _parseVersion(Object? value) {
  final root = _object(value);
  _requireKeys(root, [
    'revision',
    'weekly_contact_target',
    'statistics_time_zone',
    'week_start_iso_day',
    'effective_from_utc',
  ]);
  final target = root['weekly_contact_target'];
  return PersonalActionPlanVersion(
    revision: _integer(root['revision'], 1, 0x7fffffff),
    weeklyContactTarget: target == null ? null : _integer(target, 1, 999),
    statisticsTimeZone: _string(root['statistics_time_zone']),
    weekStartIsoDay: _integer(root['week_start_iso_day'], 1, 7),
    effectiveFromUtc: _timestamp(root['effective_from_utc']),
  );
}

PersonalActionPlanProgress _parseProgress(Object? value) {
  final root = _object(value);
  _requireKeys(root, [
    'cycle_start_utc',
    'cycle_until_utc',
    'recorded_contact_sessions',
    'remaining_contact_sessions',
    'as_of_utc',
  ]);
  final remaining = root['remaining_contact_sessions'];
  return PersonalActionPlanProgress(
    cycleStartUtc: _timestamp(root['cycle_start_utc']),
    cycleUntilUtc: _timestamp(root['cycle_until_utc']),
    recordedContactSessions: _integer(
      root['recorded_contact_sessions'],
      0,
      0x7fffffff,
    ),
    remainingContactSessions: remaining == null
        ? null
        : _integer(remaining, 0, 0x7fffffff),
    asOfUtc: _timestamp(root['as_of_utc']),
  );
}

Map<String, Object?> _reminderJson(PersonalActionReminder reminder) => {
  'reminder_id': reminder.reminderId,
  'revision': reminder.revision,
  'local_minute_of_day': reminder.localTime?.minuteOfDay,
  'updated_at_utc': reminder.updatedAtUtc.toUtc().toIso8601String(),
};

PersonalActionReminder _parseReminder(Object? value) {
  final root = _object(value);
  _requireKeys(root, [
    'reminder_id',
    'revision',
    'local_minute_of_day',
    'updated_at_utc',
  ]);
  final minute = root['local_minute_of_day'];
  return PersonalActionReminder(
    reminderId: _string(root['reminder_id']),
    revision: _integer(root['revision'], 1, 0x7fffffff),
    localTime: minute == null
        ? null
        : LocalReminderTime.fromMinuteOfDay(_integer(minute, 0, 1439)),
    updatedAtUtc: _timestamp(root['updated_at_utc']),
  );
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('invalid personal planning cache object');
  }
  return value;
}

void _requireKeys(Map<String, Object?> value, List<String> keys) {
  if (!_hasOnlyKeys(value, keys)) {
    throw const FormatException('invalid personal planning cache fields');
  }
}

bool _hasOnlyKeys(Map<String, Object?> value, List<String> keys) =>
    value.length == keys.length && value.keys.every(keys.contains);

String _string(Object? value) {
  if (value is! String || value.isEmpty) {
    throw const FormatException('invalid personal planning cache string');
  }
  return value;
}

int _integer(Object? value, int minimum, int maximum) {
  if (value is! int || value < minimum || value > maximum) {
    throw const FormatException('invalid personal planning cache integer');
  }
  return value;
}

DateTime _timestamp(Object? value) {
  if (value is! String || !value.endsWith('Z')) {
    throw const FormatException('invalid personal planning cache timestamp');
  }
  final result = DateTime.tryParse(value);
  if (result == null || !result.isUtc) {
    throw const FormatException('personal planning cache timestamp is not UTC');
  }
  return result;
}
