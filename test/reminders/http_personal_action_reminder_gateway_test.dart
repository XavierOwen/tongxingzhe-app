import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/reminders/http_personal_action_reminder_gateway.dart';
import 'package:tongxingzhe_app/reminders/personal_action_reminder.dart';

import '../support/fake_identity_session.dart';

void main() {
  test('读取同步提醒不发送用户、空间、项目或设备 ID', () async {
    late http.Request request;
    final gateway = HttpPersonalActionReminderGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: _identity(),
      client: MockClient((value) async {
        request = value;
        return http.Response(jsonEncode({'reminder': _reminder}), 200);
      }),
    );
    addTearDown(gateway.close);

    final result = await gateway.load();

    expect(request.method, 'GET');
    expect(request.url.path, '/v1/personal-action-reminder');
    expect(request.url.query, isEmpty);
    final reminder =
        (result as PersonalActionReminderSuccess).value
            as PersonalActionReminder;
    expect(reminder.localTime, LocalReminderTime.fromHourMinute(19, 0));
  });

  test('保存只发送 revision、当地分钟和 mutation', () async {
    late Map<String, Object?> body;
    final gateway = HttpPersonalActionReminderGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: _identity(),
      client: MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, Object?>;
        return http.Response(
          jsonEncode({
            'reminder': _reminder,
            'duplicate': false,
            'accepted_revision': 2,
          }),
          200,
        );
      }),
    );
    addTearDown(gateway.close);

    final result = await gateway.save(
      expectedRevision: 1,
      localTime: LocalReminderTime.fromHourMinute(19, 0),
      mutationId: 'reminder-update',
    );

    expect(body, {
      'expected_revision': 1,
      'local_minute_of_day': 1140,
      'mutation_id': 'reminder-update',
    });
    expect(result, isA<PersonalActionReminderSuccess>());
  });

  test('403 明确归为授权失效，供上层清除离线缓存', () async {
    final gateway = HttpPersonalActionReminderGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: _identity(),
      client: MockClient((_) async => http.Response('', 403)),
    );
    addTearDown(gateway.close);

    final result = await gateway.load();

    expect(
      (result as PersonalActionReminderRejected).code,
      PersonalActionReminderFailureCode.unauthorized,
    );
  });

  test('非 UTC 更新时间和越界当地分钟失败关闭', () async {
    for (final invalid in [
      {..._reminder, 'local_minute_of_day': 1440},
      {..._reminder, 'updated_at_utc': '2030-03-09T12:00:00-06:00'},
    ]) {
      final gateway = HttpPersonalActionReminderGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: _identity(),
        client: MockClient(
          (_) async => http.Response(jsonEncode({'reminder': invalid}), 200),
        ),
      );
      addTearDown(gateway.close);

      final result = await gateway.load();
      expect(
        (result as PersonalActionReminderRejected).code,
        PersonalActionReminderFailureCode.invalidResponse,
      );
    }
  });
}

FakeIdentitySession _identity() => FakeIdentitySession(
  initial: IdentitySnapshot(
    stage: IdentityStage.signedIn,
    principal: const IdentityPrincipal(
      externalSubject: 'external-subject',
      email: 'person@example.test',
    ),
    expiresAt: DateTime.utc(2030, 3, 10),
  ),
);

const Map<String, Object?> _reminder = {
  'reminder_id': '55555555-5555-4555-8555-555555555555',
  'revision': 2,
  'local_minute_of_day': 1140,
  'updated_at_utc': '2030-03-09T18:00:00.000Z',
};
