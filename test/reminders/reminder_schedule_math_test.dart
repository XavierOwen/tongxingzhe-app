import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as time_zone_data;
import 'package:timezone/timezone.dart' as time_zone;
import 'package:tongxingzhe_app/reminders/flutter_reminder_notification_scheduler.dart';
import 'package:tongxingzhe_app/reminders/personal_action_reminder.dart';
import 'package:tongxingzhe_app/platform/platform_capabilities.dart';

void main() {
  setUpAll(time_zone_data.initializeTimeZones);

  test('旅行后仍按新设备时区的当地 19:00 计算', () {
    final reminder = LocalReminderTime.fromHourMinute(19, 0);
    final chicago = nextReminderOccurrence(
      nowUtc: DateTime.utc(2030, 3, 9, 18),
      localTime: reminder,
      location: time_zone.getLocation('America/Chicago'),
    );
    final shanghai = nextReminderOccurrence(
      nowUtc: DateTime.utc(2030, 3, 9, 18),
      localTime: reminder,
      location: time_zone.getLocation('Asia/Shanghai'),
    );

    expect(chicago.hour, 19);
    expect(chicago.location.name, 'America/Chicago');
    expect(shanghai.location.name, 'Asia/Shanghai');
    expect(shanghai.hour, 19);
    expect(chicago.toUtc(), isNot(shanghai.toUtc()));
  });

  test('当天钟点已过时选择下一当地日而不是固定加 24 小时', () {
    final location = time_zone.getLocation('America/Chicago');
    final result = nextReminderOccurrence(
      nowUtc: DateTime.utc(2030, 3, 10, 1),
      localTime: LocalReminderTime.fromHourMinute(18, 30),
      location: location,
    );

    expect(result.year, 2030);
    expect(result.month, 3);
    expect(result.day, 10);
    expect(result.hour, 18);
    expect(result.minute, 30);
  });

  test('没有可靠后台重复调度的平台明确降级', () {
    for (final platform in [
      AppPlatform.web,
      AppPlatform.windows,
      AppPlatform.linux,
      AppPlatform.unknown,
    ]) {
      expect(
        productionReminderNotificationScheduler(platform),
        isA<UnsupportedReminderNotificationScheduler>(),
      );
    }
    for (final platform in [
      AppPlatform.android,
      AppPlatform.ios,
      AppPlatform.macos,
    ]) {
      expect(
        productionReminderNotificationScheduler(platform),
        isA<FlutterReminderNotificationScheduler>(),
      );
    }
  });

  test('不同项目取得稳定且不同的通知 ID', () {
    expect(
      reminderNotificationId('scope-a'),
      reminderNotificationId('scope-a'),
    );
    expect(
      reminderNotificationId('scope-a'),
      isNot(reminderNotificationId('scope-b')),
    );
  });
}
