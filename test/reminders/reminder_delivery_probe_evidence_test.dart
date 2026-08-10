import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/reminders/reminder_delivery_probe_evidence.dart';

void main() {
  test('证据明确区分安排、活跃观察和用户交互', () {
    final recorder =
        ReminderDeliveryProbeRecorder(
            platform: 'android',
            osVersion: 'Android 16',
            commit: '214943d',
          )
          ..recordScheduled(
            recordedAtUtc: DateTime.utc(2030, 6, 1, 12),
            deviceTimeZone: 'America/Chicago',
            scheduledForUtc: DateTime.utc(2030, 6, 1, 12, 2),
            scheduledLocalTime: '07:02',
            notificationId: 4817,
          )
          ..recordObservedActive(
            recordedAtUtc: DateTime.utc(2030, 6, 1, 12, 3),
            deviceTimeZone: 'America/New_York',
            notificationId: 4817,
          )
          ..recordInteracted(
            recordedAtUtc: DateTime.utc(2030, 6, 1, 12, 4),
            deviceTimeZone: 'America/New_York',
            notificationId: 4817,
            launchedApp: true,
            responseType: 'selectedNotification',
          );

    final evidence =
        jsonDecode(recorder.toPrettyJson()) as Map<String, Object?>;
    final events = evidence['events']! as List<Object?>;

    expect(
      events.map((event) => (event! as Map<String, Object?>)['kind']),
      <String>['scheduled', 'observed-active', 'interacted'],
    );
    expect(
      (events[1]! as Map<String, Object?>)['deviceTimeZone'],
      'America/New_York',
    );
    expect(recorder.toPrettyJson(), isNot(contains('delivered')));
  });

  test('安排证据保留计划 UTC、当地钟点和安排时区', () {
    final recorder =
        ReminderDeliveryProbeRecorder(
          platform: 'ios',
          osVersion: 'iOS 20',
          commit: '214943d',
        )..recordScheduled(
          recordedAtUtc: DateTime.utc(2030, 12, 2, 1),
          deviceTimeZone: 'Asia/Shanghai',
          scheduledForUtc: DateTime.utc(2030, 12, 2, 1, 5),
          scheduledLocalTime: '09:05',
          notificationId: 4817,
        );

    final evidence = recorder.toJson();
    final event =
        (evidence['events']! as List<Object?>).single as Map<String, Object?>;

    expect(event['recordedAtUtc'], '2030-12-02T01:00:00.000Z');
    expect(event['scheduledForUtc'], '2030-12-02T01:05:00.000Z');
    expect(event['scheduledLocalTime'], '09:05');
    expect(event['deviceTimeZone'], 'Asia/Shanghai');
  });

  test('拒绝没有时区或不是 UTC 的证据', () {
    final recorder = ReminderDeliveryProbeRecorder(
      platform: 'macos',
      osVersion: 'macOS 17',
      commit: '214943d',
    );

    expect(
      () => recorder.recordObservedActive(
        recordedAtUtc: DateTime(2030, 1, 1),
        deviceTimeZone: 'America/Chicago',
        notificationId: 4817,
      ),
      throwsArgumentError,
    );
    expect(
      () => recorder.recordObservedActive(
        recordedAtUtc: DateTime.utc(2030, 1, 1),
        deviceTimeZone: ' ',
        notificationId: 4817,
      ),
      throwsArgumentError,
    );
  });

  test('App 被终止后可从不含个人资料的 payload 恢复安排证据', () {
    final scheduled = ReminderProbeScheduledEvidence(
      recordedAtUtc: DateTime.utc(2030, 8, 9, 20),
      deviceTimeZone: 'America/Chicago',
      scheduledForUtc: DateTime.utc(2030, 8, 9, 20, 3),
      scheduledLocalTime: '15:03',
      notificationId: 4817,
      comparisonTimeZone: 'America/Denver',
      expectedInComparisonZoneUtc: DateTime.utc(2030, 8, 9, 21, 3),
    );
    final restored = ReminderProbeScheduledEvidence.tryParsePayload(
      scheduled.toPayload(),
    );
    final recorder = ReminderDeliveryProbeRecorder(
      platform: 'android',
      osVersion: 'Android 16',
      commit: '214943d',
    );

    expect(restored, isNotNull);
    restored!.recordTo(recorder);

    final event =
        (recorder.toJson()['events']! as List<Object?>).single
            as Map<String, Object?>;
    expect(event['kind'], 'scheduled');
    expect(event['scheduledForUtc'], '2030-08-09T20:03:00.000Z');
    expect(event['comparisonTimeZone'], 'America/Denver');
    expect(event['expectedInComparisonZoneUtc'], '2030-08-09T21:03:00.000Z');
    expect(scheduled.toPayload(), isNot(contains('project')));
    expect(scheduled.toPayload(), isNot(contains('progress')));
  });

  test('损坏或其他类型的 payload 不恢复安排证据', () {
    expect(ReminderProbeScheduledEvidence.tryParsePayload(null), isNull);
    expect(
      ReminderProbeScheduledEvidence.tryParsePayload('{"type":"today"}'),
      isNull,
    );
    expect(ReminderProbeScheduledEvidence.tryParsePayload('{not-json'), isNull);
  });

  test('拒绝不可追溯的 commit 和不完整的目标时区比较', () {
    expect(
      () => ReminderDeliveryProbeRecorder(
        platform: 'android',
        osVersion: 'Android 16',
        commit: 'unknown',
      ),
      throwsArgumentError,
    );
    expect(
      () => ReminderProbeScheduledEvidence(
        recordedAtUtc: DateTime.utc(2030, 8, 9, 20),
        deviceTimeZone: 'America/Chicago',
        scheduledForUtc: DateTime.utc(2030, 8, 9, 20, 3),
        scheduledLocalTime: '15:03',
        notificationId: 4817,
        comparisonTimeZone: 'America/Denver',
      ),
      throwsArgumentError,
    );
  });
}
