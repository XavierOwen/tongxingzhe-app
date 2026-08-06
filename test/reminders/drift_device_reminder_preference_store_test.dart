import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/data/local_database.dart';
import 'package:tongxingzhe_app/reminders/drift_device_reminder_preference_store.dart';
import 'package:tongxingzhe_app/reminders/personal_action_reminder.dart';

void main() {
  test('新设备和新项目默认关闭系统通知', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final store = DriftDeviceReminderPreferenceStore(database);

    expect((await store.load(_scope())).systemNotificationsEnabled, isFalse);
    expect(
      (await store.load(
        _scope(deviceId: 'device-2'),
      )).systemNotificationsEnabled,
      isFalse,
    );
    expect(
      (await store.load(
        _scope(projectId: 'project-2'),
      )).systemNotificationsEnabled,
      isFalse,
    );
  });

  test('明确启用只影响本用户、本项目和本设备', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final first = DriftDeviceReminderPreferenceStore(database);

    await first.save(
      _scope(),
      const DeviceReminderPreference(systemNotificationsEnabled: true),
    );
    final restored = DriftDeviceReminderPreferenceStore(database);

    expect((await restored.load(_scope())).systemNotificationsEnabled, isTrue);
    expect(
      (await restored.load(_scope())).contentMode,
      ReminderNotificationContentMode.generic,
    );
    expect(
      (await restored.load(
        _scope(deviceId: 'device-2'),
      )).systemNotificationsEnabled,
      isFalse,
    );
    expect(
      (await restored.load(
        _scope(appUserId: 'user-2'),
      )).systemNotificationsEnabled,
      isFalse,
    );
  });

  test('详细通知必须逐设备明确保存，旧格式仍按通用通知读取', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final store = DriftDeviceReminderPreferenceStore(database);
    await database
        .into(database.dbAppSettings)
        .insert(
          DbAppSettingsCompanion.insert(
            key: 'personal-reminder-v1:device-1:user-1:workspace-1:project-1',
            value: '{"system_notifications_enabled":true}',
          ),
        );

    expect(
      (await store.load(_scope())).contentMode,
      ReminderNotificationContentMode.generic,
    );

    await store.save(
      _scope(),
      const DeviceReminderPreference(
        systemNotificationsEnabled: true,
        contentMode: ReminderNotificationContentMode.projectAndProgress,
      ),
    );

    expect(
      (await store.load(_scope())).contentMode,
      ReminderNotificationContentMode.projectAndProgress,
    );
    expect(
      (await store.load(_scope(deviceId: 'device-2'))).contentMode,
      ReminderNotificationContentMode.generic,
    );
    final legacyRow =
        await (database.select(database.dbAppSettings)..where(
              (row) => row.key.equals(
                'personal-reminder-v1:device-1:user-1:workspace-1:project-1',
              ),
            ))
            .getSingle();
    expect(legacyRow.value, '{"system_notifications_enabled":true}');
  });

  test('损坏设置失败关闭，不能意外启用通知', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final store = DriftDeviceReminderPreferenceStore(database);
    await database
        .into(database.dbAppSettings)
        .insert(
          DbAppSettingsCompanion.insert(
            key: 'personal-reminder-v1:device-1:user-1:workspace-1:project-1',
            value: '{broken',
          ),
        );

    expect((await store.load(_scope())).systemNotificationsEnabled, isFalse);
  });

  test('损坏的详细披露设置降级为通用通知但保留原通知开关', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final store = DriftDeviceReminderPreferenceStore(database);
    await database.batch((batch) {
      batch.insert(
        database.dbAppSettings,
        DbAppSettingsCompanion.insert(
          key: 'personal-reminder-v1:device-1:user-1:workspace-1:project-1',
          value: '{"system_notifications_enabled":true}',
        ),
      );
      batch.insert(
        database.dbAppSettings,
        DbAppSettingsCompanion.insert(
          key:
              'personal-reminder-content-v1:device-1:user-1:workspace-1:project-1',
          value: '{broken',
        ),
      );
    });

    final preference = await store.load(_scope());

    expect(preference.systemNotificationsEnabled, isTrue);
    expect(preference.contentMode, ReminderNotificationContentMode.generic);
  });
}

DeviceReminderScope _scope({
  String appUserId = 'user-1',
  String workspaceId = 'workspace-1',
  String projectId = 'project-1',
  String deviceId = 'device-1',
}) => DeviceReminderScope(
  appUserId: appUserId,
  workspaceId: workspaceId,
  projectId: projectId,
  deviceId: deviceId,
);
