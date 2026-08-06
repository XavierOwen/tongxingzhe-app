import 'dart:convert';

import '../data/local_database.dart';
import 'personal_action_reminder.dart';

/// 逐设备 opt-in 使用现有非敏感设置表，不进入同步 Outbox。
final class DriftDeviceReminderPreferenceStore
    implements DeviceReminderPreferenceStore {
  const DriftDeviceReminderPreferenceStore(this.database);

  final LocalDatabase database;

  @override
  Future<DeviceReminderPreference> load(DeviceReminderScope scope) async {
    final query = database.select(database.dbAppSettings)
      ..where((row) => row.key.equals(_key(scope)));
    final row = await query.getSingleOrNull();
    if (row == null) return const DeviceReminderPreference.disabled();
    try {
      final value = jsonDecode(row.value);
      if (value is! Map<String, Object?> ||
          value.length != 1 ||
          value['system_notifications_enabled'] is! bool) {
        return const DeviceReminderPreference.disabled();
      }
      return DeviceReminderPreference(
        systemNotificationsEnabled:
            value['system_notifications_enabled']! as bool,
      );
    } on FormatException {
      return const DeviceReminderPreference.disabled();
    }
  }

  @override
  Future<void> save(
    DeviceReminderScope scope,
    DeviceReminderPreference preference,
  ) async {
    await database
        .into(database.dbAppSettings)
        .insertOnConflictUpdate(
          DbAppSettingsCompanion.insert(
            key: _key(scope),
            value: jsonEncode({
              'system_notifications_enabled':
                  preference.systemNotificationsEnabled,
            }),
          ),
        );
  }

  String _key(DeviceReminderScope scope) => [
    'personal-reminder-v1',
    scope.deviceId,
    scope.appUserId,
    scope.workspaceId,
    scope.projectId,
  ].join(':');
}
