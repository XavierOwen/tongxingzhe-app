import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as time_zone_data;
import 'package:timezone/timezone.dart' as time_zone;

import '../platform/platform_capabilities.dart';
import 'personal_action_reminder.dart';

var _timeZonesInitialized = false;

ReminderNotificationScheduler productionReminderNotificationScheduler(
  AppPlatform platform,
) {
  return switch (platform) {
    AppPlatform.android ||
    AppPlatform.ios ||
    AppPlatform.macos => FlutterReminderNotificationScheduler(
      FlutterLocalNotificationsPlugin(),
      platform: platform,
    ),
    _ => const UnsupportedReminderNotificationScheduler(),
  };
}

/// Android、iOS 和 macOS 的每日当地钟点 Adapter。
///
/// Web 与 Linux 没有后台 scheduler，Windows 没有重复通知；这些平台由
/// production factory 返回明确的 unsupported 降级，不会假装已安排提醒。
final class FlutterReminderNotificationScheduler
    implements ReminderNotificationScheduler {
  FlutterReminderNotificationScheduler(this._plugin, {required this.platform});

  final AppPlatform platform;
  final FlutterLocalNotificationsPlugin _plugin;
  Future<bool>? _initialization;

  @override
  Future<ReminderScheduleResult> requestPermissionAndSchedule({
    required String scheduleKey,
    required LocalReminderTime localTime,
    required String deviceTimeZone,
    required ReminderNotificationContent content,
  }) async {
    if (!await _initialize()) {
      return const ReminderScheduleRejected(
        ReminderScheduleFailure.temporarilyUnavailable,
      );
    }
    try {
      final granted = switch (platform) {
        AppPlatform.android =>
          await _plugin
                  .resolvePlatformSpecificImplementation<
                    AndroidFlutterLocalNotificationsPlugin
                  >()
                  ?.requestNotificationsPermission() ??
              false,
        AppPlatform.ios =>
          await _plugin
                  .resolvePlatformSpecificImplementation<
                    IOSFlutterLocalNotificationsPlugin
                  >()
                  ?.requestPermissions(
                    alert: true,
                    badge: false,
                    sound: true,
                  ) ??
              false,
        AppPlatform.macos =>
          await _plugin
                  .resolvePlatformSpecificImplementation<
                    MacOSFlutterLocalNotificationsPlugin
                  >()
                  ?.requestPermissions(
                    alert: true,
                    badge: false,
                    sound: true,
                  ) ??
              false,
        _ => false,
      };
      if (!granted) {
        return const ReminderScheduleRejected(
          ReminderScheduleFailure.permissionDenied,
        );
      }
      return schedule(
        scheduleKey: scheduleKey,
        localTime: localTime,
        deviceTimeZone: deviceTimeZone,
        content: content,
      );
    } on Object {
      return const ReminderScheduleRejected(
        ReminderScheduleFailure.temporarilyUnavailable,
      );
    }
  }

  @override
  Future<ReminderScheduleResult> schedule({
    required String scheduleKey,
    required LocalReminderTime localTime,
    required String deviceTimeZone,
    required ReminderNotificationContent content,
  }) async {
    if (!await _initialize()) {
      return const ReminderScheduleRejected(
        ReminderScheduleFailure.temporarilyUnavailable,
      );
    }
    try {
      final location = time_zone.getLocation(deviceTimeZone);
      final scheduledDate = nextReminderOccurrence(
        nowUtc: DateTime.now().toUtc(),
        localTime: localTime,
        location: location,
      );
      await _plugin.zonedSchedule(
        id: reminderNotificationId(scheduleKey),
        title: content.title,
        body: content.body,
        scheduledDate: scheduledDate,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'personal_action_reminders',
            '私人行动提醒',
            channelDescription: '只由本设备明确启用的私人行动提醒',
          ),
          iOS: DarwinNotificationDetails(),
          macOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: content.payload,
      );
      return const ReminderScheduleSucceeded();
    } on Object {
      return const ReminderScheduleRejected(
        ReminderScheduleFailure.temporarilyUnavailable,
      );
    }
  }

  @override
  Future<ReminderScheduleResult> cancel({required String scheduleKey}) async {
    if (!await _initialize()) {
      return const ReminderScheduleRejected(
        ReminderScheduleFailure.temporarilyUnavailable,
      );
    }
    try {
      await _plugin.cancel(id: reminderNotificationId(scheduleKey));
      return const ReminderScheduleSucceeded();
    } on Object {
      return const ReminderScheduleRejected(
        ReminderScheduleFailure.temporarilyUnavailable,
      );
    }
  }

  @override
  Future<ReminderScheduleResult> cancelAll() async {
    if (!await _initialize()) {
      return const ReminderScheduleRejected(
        ReminderScheduleFailure.temporarilyUnavailable,
      );
    }
    try {
      final pending = await _plugin.pendingNotificationRequests();
      for (final request in pending) {
        if (request.payload == personalActionReminderPayload ||
            request.payload == 'today') {
          await _plugin.cancel(id: request.id);
        }
      }
      return const ReminderScheduleSucceeded();
    } on Object {
      return const ReminderScheduleRejected(
        ReminderScheduleFailure.temporarilyUnavailable,
      );
    }
  }

  Future<bool> _initialize() => _initialization ??= _initializeOnce();

  Future<bool> _initializeOnce() async {
    try {
      _ensureTimeZones();
      return await _plugin.initialize(
            settings: const InitializationSettings(
              android: AndroidInitializationSettings('ic_notification'),
              iOS: DarwinInitializationSettings(
                requestAlertPermission: false,
                requestBadgePermission: false,
                requestSoundPermission: false,
              ),
              macOS: DarwinInitializationSettings(
                requestAlertPermission: false,
                requestBadgePermission: false,
                requestSoundPermission: false,
              ),
            ),
          ) ??
          false;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> close() async {}
}

/// 先在指定 IANA 地区建立当地日历时间，再转为下一次出现。
/// 这避免把“每天 19:00”错误地换算成固定 24 小时 UTC 间隔。
time_zone.TZDateTime nextReminderOccurrence({
  required DateTime nowUtc,
  required LocalReminderTime localTime,
  required time_zone.Location location,
}) {
  final now = time_zone.TZDateTime.from(nowUtc, location);
  var candidate = time_zone.TZDateTime(
    location,
    now.year,
    now.month,
    now.day,
    localTime.hour,
    localTime.minute,
  );
  if (!candidate.isAfter(now)) {
    candidate = time_zone.TZDateTime(
      location,
      now.year,
      now.month,
      now.day + 1,
      localTime.hour,
      localTime.minute,
    );
  }
  return candidate;
}

void _ensureTimeZones() {
  if (_timeZonesInitialized) return;
  time_zone_data.initializeTimeZones();
  _timeZonesInitialized = true;
}

/// 生成稳定的正整数通知 ID，使不同项目的提醒不会互相覆盖。
int reminderNotificationId(String scheduleKey) {
  if (scheduleKey.isEmpty) {
    throw ArgumentError.value(scheduleKey, 'scheduleKey', 'must not be empty');
  }
  var hash = 0x811c9dc5;
  for (final codeUnit in scheduleKey.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash == 0 ? 1 : hash;
}
