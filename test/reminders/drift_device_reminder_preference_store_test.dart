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
