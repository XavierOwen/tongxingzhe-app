import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/plans/http_personal_action_plan_gateway.dart';
import 'package:tongxingzhe_app/plans/personal_action_plan.dart';

import '../support/fake_identity_session.dart';

void main() {
  test('读取私人计划不发送用户、空间或项目 ID', () async {
    late http.Request request;
    final gateway = HttpPersonalActionPlanGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: _identity(),
      client: MockClient((value) async {
        request = value;
        return http.Response(jsonEncode({'plan': _plan}), 200);
      }),
    );
    addTearDown(gateway.close);

    final result = await gateway.load();

    expect(request.method, 'GET');
    expect(request.url.path, '/v1/personal-action-plan');
    expect(request.url.query, isEmpty);
    expect(result, isA<PersonalActionPlanSuccess>());
    final plan =
        (result as PersonalActionPlanSuccess).value
            as PersonalActionPlanSnapshot;
    expect(plan.current.weeklyContactTarget, 3);
    expect(plan.progress.recordedContactSessions, 1);
    expect(plan.progress.remainingContactSessions, 2);
  });

  test('保存只发送计划字段并保留 nullable 周目标', () async {
    late Map<String, Object?> body;
    final gateway = HttpPersonalActionPlanGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: _identity(),
      client: MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, Object?>;
        return http.Response(
          jsonEncode({
            'plan': _plan,
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
      weeklyContactTarget: null,
      statisticsTimeZone: 'Asia/Shanghai',
      weekStartIsoDay: 7,
      mutationId: 'mutation-2',
    );

    expect(body, {
      'expected_revision': 1,
      'weekly_contact_target': null,
      'statistics_time_zone': 'Asia/Shanghai',
      'week_start_iso_day': 7,
      'mutation_id': 'mutation-2',
    });
    expect(result, isA<PersonalActionPlanSuccess>());
  });

  test('冲突与已有待生效修改保持不同失败类别', () async {
    Future<PersonalActionPlanFailureCode> saveWith(String code) async {
      final gateway = HttpPersonalActionPlanGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: _identity(),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {'code': code},
            }),
            409,
          ),
        ),
      );
      addTearDown(gateway.close);
      final result = await gateway.save(
        expectedRevision: 1,
        weeklyContactTarget: 4,
        statisticsTimeZone: 'UTC',
        weekStartIsoDay: 1,
        mutationId: 'mutation',
      );
      return (result as PersonalActionPlanRejected).code;
    }

    expect(
      await saveWith('personal_action_plan_conflict'),
      PersonalActionPlanFailureCode.conflict,
    );
    expect(
      await saveWith('personal_action_plan_pending_change'),
      PersonalActionPlanFailureCode.pendingChange,
    );
  });

  test('非 UTC 或结构不完整的计划响应失败关闭', () async {
    final invalid = Map<String, Object?>.from(_plan)
      ..['progress'] = {
        ...(_plan['progress']! as Map<String, Object?>),
        'as_of_utc': '2030-03-09T12:00:00-06:00',
      };
    final gateway = HttpPersonalActionPlanGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: _identity(),
      client: MockClient(
        (_) async => http.Response(jsonEncode({'plan': invalid}), 200),
      ),
    );
    addTearDown(gateway.close);

    final result = await gateway.load();

    expect(
      (result as PersonalActionPlanRejected).code,
      PersonalActionPlanFailureCode.invalidResponse,
    );
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

final Map<String, Object?> _plan = {
  'plan_id': '55555555-5555-4555-8555-555555555555',
  'revision': 2,
  'current': {
    'revision': 1,
    'weekly_contact_target': 3,
    'statistics_time_zone': 'America/Chicago',
    'week_start_iso_day': 1,
    'effective_from_utc': '2030-03-04T06:00:00.000Z',
  },
  'pending': {
    'revision': 2,
    'weekly_contact_target': 4,
    'statistics_time_zone': 'Asia/Shanghai',
    'week_start_iso_day': 7,
    'effective_from_utc': '2030-03-16T16:00:00.000Z',
  },
  'progress': {
    'cycle_start_utc': '2030-03-04T06:00:00.000Z',
    'cycle_until_utc': '2030-03-11T05:00:00.000Z',
    'recorded_contact_sessions': 1,
    'remaining_contact_sessions': 2,
    'as_of_utc': '2030-03-09T18:00:00.000Z',
  },
};
