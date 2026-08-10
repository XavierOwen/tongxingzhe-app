import 'dart:convert';

const _schedulePayloadType = 'reminder-delivery-probe-scheduled-v1';

/// 可放入本机测试通知 payload 的安排证据。
///
/// App 被系统终止后，用户点击通知仍可恢复原安排时间。字段只包含测试通知
/// 元数据，不包含账号、项目、进度或推广对象资料。
final class ReminderProbeScheduledEvidence {
  ReminderProbeScheduledEvidence({
    required DateTime recordedAtUtc,
    required String deviceTimeZone,
    required DateTime scheduledForUtc,
    required String scheduledLocalTime,
    required int notificationId,
    String? comparisonTimeZone,
    DateTime? expectedInComparisonZoneUtc,
  }) : recordedAtUtc = _utcValue(recordedAtUtc, 'recordedAtUtc'),
       deviceTimeZone = _requiredText(deviceTimeZone, 'deviceTimeZone'),
       scheduledForUtc = _utcValue(scheduledForUtc, 'scheduledForUtc'),
       scheduledLocalTime = _localTime(scheduledLocalTime),
       notificationId = _notificationId(notificationId),
       comparisonTimeZone = _comparisonTimeZone(
         comparisonTimeZone,
         expectedInComparisonZoneUtc,
       ),
       expectedInComparisonZoneUtc = _comparisonExpectedUtc(
         expectedInComparisonZoneUtc,
         comparisonTimeZone,
       );

  final DateTime recordedAtUtc;
  final String deviceTimeZone;
  final DateTime scheduledForUtc;
  final String scheduledLocalTime;
  final int notificationId;
  final String? comparisonTimeZone;
  final DateTime? expectedInComparisonZoneUtc;

  void recordTo(ReminderDeliveryProbeRecorder recorder) {
    recorder.recordScheduled(
      recordedAtUtc: recordedAtUtc,
      deviceTimeZone: deviceTimeZone,
      scheduledForUtc: scheduledForUtc,
      scheduledLocalTime: scheduledLocalTime,
      notificationId: notificationId,
      comparisonTimeZone: comparisonTimeZone,
      expectedInComparisonZoneUtc: expectedInComparisonZoneUtc,
    );
  }

  String toPayload() => jsonEncode(<String, Object?>{
    'type': _schedulePayloadType,
    'recordedAtUtc': recordedAtUtc.toIso8601String(),
    'deviceTimeZone': deviceTimeZone,
    'scheduledForUtc': scheduledForUtc.toIso8601String(),
    'scheduledLocalTime': scheduledLocalTime,
    'notificationId': notificationId,
    'comparisonTimeZone': ?comparisonTimeZone,
    'expectedInComparisonZoneUtc': ?expectedInComparisonZoneUtc
        ?.toIso8601String(),
  });

  static ReminderProbeScheduledEvidence? tryParsePayload(String? payload) {
    if (payload == null || payload.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, Object?> ||
          decoded['type'] != _schedulePayloadType ||
          decoded['recordedAtUtc'] is! String ||
          decoded['deviceTimeZone'] is! String ||
          decoded['scheduledForUtc'] is! String ||
          decoded['scheduledLocalTime'] is! String ||
          decoded['notificationId'] is! int ||
          (decoded['comparisonTimeZone'] != null &&
              decoded['comparisonTimeZone'] is! String) ||
          (decoded['expectedInComparisonZoneUtc'] != null &&
              decoded['expectedInComparisonZoneUtc'] is! String)) {
        return null;
      }
      return ReminderProbeScheduledEvidence(
        recordedAtUtc: DateTime.parse(decoded['recordedAtUtc']! as String),
        deviceTimeZone: decoded['deviceTimeZone']! as String,
        scheduledForUtc: DateTime.parse(decoded['scheduledForUtc']! as String),
        scheduledLocalTime: decoded['scheduledLocalTime']! as String,
        notificationId: decoded['notificationId']! as int,
        comparisonTimeZone: decoded['comparisonTimeZone'] as String?,
        expectedInComparisonZoneUtc:
            decoded['expectedInComparisonZoneUtc'] == null
            ? null
            : DateTime.parse(decoded['expectedInComparisonZoneUtc']! as String),
      );
    } on Object {
      return null;
    }
  }
}

/// 收集真机通知探针可以直接观察到的事实。
///
/// 事件名称刻意不提供“送达”。系统通知仍在通知中心和用户点击都不能证明
/// 操作系统在何时首次呈现了通知。
final class ReminderDeliveryProbeRecorder {
  ReminderDeliveryProbeRecorder({
    required String platform,
    required String osVersion,
    required String commit,
  }) : platform = _requiredText(platform, 'platform'),
       osVersion = _requiredText(osVersion, 'osVersion'),
       commit = _commitSha(commit);

  static const schemaVersion = 1;

  final String platform;
  final String osVersion;
  final String commit;
  final List<Map<String, Object?>> _events = <Map<String, Object?>>[];

  void recordScheduled({
    required DateTime recordedAtUtc,
    required String deviceTimeZone,
    required DateTime scheduledForUtc,
    required String scheduledLocalTime,
    required int notificationId,
    String? comparisonTimeZone,
    DateTime? expectedInComparisonZoneUtc,
  }) {
    final event = <String, Object?>{
      'kind': 'scheduled',
      'recordedAtUtc': _utc(recordedAtUtc, 'recordedAtUtc'),
      'deviceTimeZone': _requiredText(deviceTimeZone, 'deviceTimeZone'),
      'scheduledForUtc': _utc(scheduledForUtc, 'scheduledForUtc'),
      'scheduledLocalTime': _localTime(scheduledLocalTime),
      'notificationId': _notificationId(notificationId),
      if (comparisonTimeZone case final value?)
        'comparisonTimeZone': _requiredText(value, 'comparisonTimeZone'),
      if (expectedInComparisonZoneUtc case final value?)
        'expectedInComparisonZoneUtc': _utc(
          value,
          'expectedInComparisonZoneUtc',
        ),
    };
    if (_events.any(
      (existing) =>
          existing['kind'] == event['kind'] &&
          existing['recordedAtUtc'] == event['recordedAtUtc'] &&
          existing['notificationId'] == event['notificationId'],
    )) {
      return;
    }
    _events.add(event);
  }

  void recordObservedActive({
    required DateTime recordedAtUtc,
    required String deviceTimeZone,
    required int notificationId,
  }) {
    _events.add(<String, Object?>{
      'kind': 'observed-active',
      'recordedAtUtc': _utc(recordedAtUtc, 'recordedAtUtc'),
      'deviceTimeZone': _requiredText(deviceTimeZone, 'deviceTimeZone'),
      'notificationId': _notificationId(notificationId),
    });
  }

  void recordInteracted({
    required DateTime recordedAtUtc,
    required String deviceTimeZone,
    required int notificationId,
    required bool launchedApp,
    required String responseType,
  }) {
    _events.add(<String, Object?>{
      'kind': 'interacted',
      'recordedAtUtc': _utc(recordedAtUtc, 'recordedAtUtc'),
      'deviceTimeZone': _requiredText(deviceTimeZone, 'deviceTimeZone'),
      'notificationId': _notificationId(notificationId),
      'launchedApp': launchedApp,
      'responseType': _requiredText(responseType, 'responseType'),
    });
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'platform': platform,
    'osVersion': osVersion,
    'commit': commit,
    'events': _events
        .map((event) => Map<String, Object?>.unmodifiable(event))
        .toList(growable: false),
  };

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());
}

String _requiredText(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
  return normalized;
}

String _commitSha(String value) {
  final normalized = value.trim();
  if (!RegExp(r'^[0-9a-f]{7,40}$').hasMatch(normalized)) {
    throw ArgumentError.value(value, 'commit', 'must be a Git commit SHA');
  }
  return normalized;
}

String? _comparisonTimeZone(String? value, DateTime? expectedUtc) {
  if ((value == null) != (expectedUtc == null)) {
    throw ArgumentError(
      'comparisonTimeZone and expectedInComparisonZoneUtc must be set together',
    );
  }
  return value == null ? null : _requiredText(value, 'comparisonTimeZone');
}

DateTime? _comparisonExpectedUtc(DateTime? value, String? timeZone) {
  if ((value == null) != (timeZone == null)) {
    throw ArgumentError(
      'comparisonTimeZone and expectedInComparisonZoneUtc must be set together',
    );
  }
  return value == null ? null : _utcValue(value, 'expectedInComparisonZoneUtc');
}

String _utc(DateTime value, String name) {
  return _utcValue(value, name).toIso8601String();
}

DateTime _utcValue(DateTime value, String name) {
  if (!value.isUtc) {
    throw ArgumentError.value(value, name, 'must use UTC');
  }
  return value;
}

String _localTime(String value) {
  final normalized = value.trim();
  final match = RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(normalized);
  if (!match) {
    throw ArgumentError.value(value, 'scheduledLocalTime', 'must use HH:mm');
  }
  return normalized;
}

int _notificationId(int value) {
  if (value <= 0) {
    throw ArgumentError.value(value, 'notificationId', 'must be positive');
  }
  return value;
}
