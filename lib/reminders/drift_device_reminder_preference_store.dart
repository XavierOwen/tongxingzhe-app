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
    final notificationQuery = database.select(database.dbAppSettings)
      ..where((row) => row.key.equals(_notificationKey(scope)));
    final row = await notificationQuery.getSingleOrNull();
    if (row == null) return const DeviceReminderPreference.disabled();
    late final bool enabled;
    try {
      final value = jsonDecode(row.value);
      if (value is! Map<String, Object?> ||
          value.length != 1 ||
          value['system_notifications_enabled'] is! bool) {
        return const DeviceReminderPreference.disabled();
      }
      enabled = value['system_notifications_enabled']! as bool;
    } on FormatException {
      return const DeviceReminderPreference.disabled();
    }
    if (!enabled) return const DeviceReminderPreference.disabled();
    try {
      final contentQuery = database.select(database.dbAppSettings)
        ..where((row) => row.key.equals(_contentKey(scope)));
      final contentRow = await contentQuery.getSingleOrNull();
      if (contentRow == null) {
        return const DeviceReminderPreference(systemNotificationsEnabled: true);
      }
      final contentValue = jsonDecode(contentRow.value);
      if (contentValue is! Map<String, Object?> || contentValue.length != 1) {
        return const DeviceReminderPreference(systemNotificationsEnabled: true);
      }
      final contentMode = switch (contentValue['content_mode']) {
        'generic' => ReminderNotificationContentMode.generic,
        'project_and_progress' =>
          ReminderNotificationContentMode.projectAndProgress,
        _ => null,
      };
      if (contentMode == null) {
        return const DeviceReminderPreference(systemNotificationsEnabled: true);
      }
      return DeviceReminderPreference(
        systemNotificationsEnabled: true,
        contentMode: contentMode,
      );
    } on FormatException {
      return const DeviceReminderPreference(systemNotificationsEnabled: true);
    }
  }

  @override
  Future<void> save(
    DeviceReminderScope scope,
    DeviceReminderPreference preference,
  ) async {
    await database.transaction(() async {
      await database
          .into(database.dbAppSettings)
          .insertOnConflictUpdate(
            DbAppSettingsCompanion.insert(
              key: _notificationKey(scope),
              value: jsonEncode({
                'system_notifications_enabled':
                    preference.systemNotificationsEnabled,
              }),
            ),
          );
      await database
          .into(database.dbAppSettings)
          .insertOnConflictUpdate(
            DbAppSettingsCompanion.insert(
              key: _contentKey(scope),
              value: jsonEncode({
                'content_mode': switch (preference.contentMode) {
                  ReminderNotificationContentMode.generic => 'generic',
                  ReminderNotificationContentMode.projectAndProgress =>
                    'project_and_progress',
                },
              }),
            ),
          );
    });
  }

  String _notificationKey(DeviceReminderScope scope) => [
    'personal-reminder-v1',
    scope.deviceId,
    scope.appUserId,
    scope.workspaceId,
    scope.projectId,
  ].join(':');

  String _contentKey(DeviceReminderScope scope) => [
    'personal-reminder-content-v1',
    scope.deviceId,
    scope.appUserId,
    scope.workspaceId,
    scope.projectId,
  ].join(':');
}
