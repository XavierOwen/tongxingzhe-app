/// 每日提醒采用设备当地钟点，不保存 UTC 时刻或计划统计时区。
final class LocalReminderTime {
  const LocalReminderTime._(this.minuteOfDay);

  factory LocalReminderTime.fromMinuteOfDay(int value) {
    if (value < 0 || value > 1439) {
      throw ArgumentError.value(value, 'value', 'must be from 0 to 1439');
    }
    return LocalReminderTime._(value);
  }

  factory LocalReminderTime.fromHourMinute(int hour, int minute) {
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      throw ArgumentError('invalid local reminder time');
    }
    return LocalReminderTime._(hour * 60 + minute);
  }

  final int minuteOfDay;

  int get hour => minuteOfDay ~/ 60;
  int get minute => minuteOfDay % 60;

  @override
  bool operator ==(Object other) =>
      other is LocalReminderTime && other.minuteOfDay == minuteOfDay;

  @override
  int get hashCode => minuteOfDay.hashCode;
}

/// 在所有设备间同步的私人提醒计划。
final class PersonalActionReminder {
  const PersonalActionReminder({
    required this.reminderId,
    required this.revision,
    required this.localTime,
    required this.updatedAtUtc,
  });

  final String reminderId;
  final int revision;
  final LocalReminderTime? localTime;
  final DateTime updatedAtUtc;
}

final class PersonalActionReminderMutation {
  const PersonalActionReminderMutation({
    required this.reminder,
    required this.duplicate,
    required this.acceptedRevision,
  });

  final PersonalActionReminder reminder;
  final bool duplicate;
  final int acceptedRevision;
}

enum PersonalActionReminderFailureCode {
  unauthorized,
  notConfigured,
  networkUnavailable,
  invalidResponse,
  invalidRequest,
  conflict,
  serverRejected,
}

sealed class PersonalActionReminderResult<T> {
  const PersonalActionReminderResult();
}

final class PersonalActionReminderSuccess<T>
    extends PersonalActionReminderResult<T> {
  const PersonalActionReminderSuccess(
    this.value, {
    this.fromOfflineCache = false,
    this.cachedAtUtc,
  }) : assert(fromOfflineCache == (cachedAtUtc != null));

  final T value;
  final bool fromOfflineCache;
  final DateTime? cachedAtUtc;
}

final class PersonalActionReminderRejected<T>
    extends PersonalActionReminderResult<T> {
  const PersonalActionReminderRejected(this.code);

  final PersonalActionReminderFailureCode code;
}

abstract interface class PersonalActionReminderGateway {
  Future<PersonalActionReminderResult<PersonalActionReminder?>> load();

  Future<PersonalActionReminderResult<PersonalActionReminderMutation>> save({
    required int expectedRevision,
    required LocalReminderTime? localTime,
    required String mutationId,
  });

  Future<void> close();
}

/// 本机数据库中的 scope。设备 ID 使“新设备默认关闭”成为显式合同。
final class DeviceReminderScope {
  const DeviceReminderScope({
    required this.appUserId,
    required this.workspaceId,
    required this.projectId,
    required this.deviceId,
  });

  final String appUserId;
  final String workspaceId;
  final String projectId;
  final String deviceId;
}

String personalActionReminderScheduleKey(DeviceReminderScope scope) => [
  scope.deviceId,
  scope.appUserId,
  scope.workspaceId,
  scope.projectId,
].join(':');

enum ReminderNotificationContentMode { generic, projectAndProgress }

final class DeviceReminderPreference {
  const DeviceReminderPreference({
    required this.systemNotificationsEnabled,
    this.contentMode = ReminderNotificationContentMode.generic,
  }) : assert(
         systemNotificationsEnabled ||
             contentMode == ReminderNotificationContentMode.generic,
       );

  const DeviceReminderPreference.disabled()
    : systemNotificationsEnabled = false,
      contentMode = ReminderNotificationContentMode.generic;

  final bool systemNotificationsEnabled;
  final ReminderNotificationContentMode contentMode;
}

abstract interface class DeviceReminderPreferenceStore {
  Future<DeviceReminderPreference> load(DeviceReminderScope scope);

  Future<void> save(
    DeviceReminderScope scope,
    DeviceReminderPreference preference,
  );
}

/// 系统通知只接收已经过隐私收缩的文本和预留的 Today payload。
const personalActionReminderPayload = 'today:personal-action-reminder:v1';

final class ReminderNotificationContent {
  const ReminderNotificationContent({
    required this.title,
    required this.body,
    this.payload = personalActionReminderPayload,
  });

  final String title;
  final String body;
  final String payload;
}

enum ReminderScheduleFailure {
  unsupported,
  permissionDenied,
  temporarilyUnavailable,
}

sealed class ReminderScheduleResult {
  const ReminderScheduleResult();
}

final class ReminderScheduleSucceeded extends ReminderScheduleResult {
  const ReminderScheduleSucceeded();
}

final class ReminderScheduleRejected extends ReminderScheduleResult {
  const ReminderScheduleRejected(this.failure);

  final ReminderScheduleFailure failure;
}

abstract interface class ReminderNotificationScheduler {
  Future<ReminderScheduleResult> requestPermissionAndSchedule({
    required String scheduleKey,
    required LocalReminderTime localTime,
    required String deviceTimeZone,
    required ReminderNotificationContent content,
  });

  Future<ReminderScheduleResult> schedule({
    required String scheduleKey,
    required LocalReminderTime localTime,
    required String deviceTimeZone,
    required ReminderNotificationContent content,
  });

  Future<ReminderScheduleResult> cancel({required String scheduleKey});

  /// 登出或可信上下文失效时取消本功能排入系统的全部通知。
  Future<ReminderScheduleResult> cancelAll();

  Future<void> close();
}

final class UnsupportedReminderNotificationScheduler
    implements ReminderNotificationScheduler {
  const UnsupportedReminderNotificationScheduler();

  @override
  Future<ReminderScheduleResult> requestPermissionAndSchedule({
    required String scheduleKey,
    required LocalReminderTime localTime,
    required String deviceTimeZone,
    required ReminderNotificationContent content,
  }) async =>
      const ReminderScheduleRejected(ReminderScheduleFailure.unsupported);

  @override
  Future<ReminderScheduleResult> schedule({
    required String scheduleKey,
    required LocalReminderTime localTime,
    required String deviceTimeZone,
    required ReminderNotificationContent content,
  }) async =>
      const ReminderScheduleRejected(ReminderScheduleFailure.unsupported);

  @override
  Future<ReminderScheduleResult> cancel({required String scheduleKey}) async =>
      const ReminderScheduleSucceeded();

  @override
  Future<ReminderScheduleResult> cancelAll() async =>
      const ReminderScheduleSucceeded();

  @override
  Future<void> close() async {}
}
