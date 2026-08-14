import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/management_reports/http_management_report_gateway.dart';
import 'package:tongxingzhe_app/management_reports/management_report_gateway.dart';

import '../support/fake_identity_session.dart';

void main() {
  test('GET management context sends bearer and strictly parses 6M', () async {
    final identity = _signedInIdentity();
    final gateway = HttpManagementReportGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: identity,
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/v1/management-analysis/context');
        expect(
          request.headers['authorization'],
          'Bearer test-only-access-token',
        );
        return http.Response(
          jsonEncode(_contextBody),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    addTearDown(gateway.close);

    final result = await gateway.loadContext();

    expect(
      result,
      isA<ManagementReportSuccess<ManagementAnalysisContextSnapshot>>(),
    );
    final value =
        (result as ManagementReportSuccess<ManagementAnalysisContextSnapshot>)
            .value;
    expect(value.current?.projectId, _projectId);
    expect(value.current?.organizationName, '同行组织');
    expect(value.available, hasLength(2));
    expect(value.available.last.projectName, '社区推广');
    expect(identity.accessTokenForceRefreshValues, [false]);
  });

  test('GET snapshot directory strictly parses bounded 6N summaries', () async {
    final identity = _signedInIdentity();
    final gateway = HttpManagementReportGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: identity,
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(
          request.url.path,
          '/v1/projects/$_projectId/management-report-snapshots',
        );
        expect(request.url.query, isEmpty);
        return _jsonResponse(_directoryBody);
      }),
    );
    addTearDown(gateway.close);

    final result = await gateway.listSnapshots(_projectId);

    expect(
      result,
      isA<ManagementReportSuccess<List<ManagementReportSnapshotSummary>>>(),
    );
    final values =
        (result
                as ManagementReportSuccess<
                  List<ManagementReportSnapshotSummary>
                >)
            .value;
    expect(values, hasLength(2));
    expect(values.first.snapshotId, _snapshotId);
    expect(values.first.reportId, _reportId);
    expect(values.first.reportVersion, 1);
    expect(values.first.reportingTimeZone, 'America/Chicago');
    expect(values.first.dataCutoffUtc, DateTime.utc(2030, 3, 11, 5));
    expect(values.first.releasedAtUtc, DateTime.utc(2030, 3, 11, 5, 1));
  });

  test(
    'GET one snapshot validates 6L metadata and protected 16-cell report',
    () async {
      final summary = _summary();
      final gateway = HttpManagementReportGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: _signedInIdentity(),
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(
            request.url.path,
            '/v1/projects/$_projectId/management-report-snapshots/$_snapshotId',
          );
          return _jsonResponse({
            'access_event_id': _accessEventId,
            'snapshot_id': _snapshotId,
            'report': _protectedReportBody,
          });
        }),
      );
      addTearDown(gateway.close);

      final result = await gateway.readSnapshot(
        projectId: _projectId,
        summary: summary,
      );

      expect(result, isA<ManagementReportSuccess<ManagementReportSnapshot>>());
      final snapshot =
          (result as ManagementReportSuccess<ManagementReportSnapshot>).value;
      expect(snapshot.summary, same(summary));
      expect(snapshot.report.reportId, _reportId);
      expect(snapshot.report.metricId, 'contact_sessions');
      expect(snapshot.report.dimension, 'channel');
      expect(
        snapshot.report.previousPeriod.untilUtc,
        DateTime.utc(2030, 3, 4, 6),
      );
      expect(
        snapshot.report.currentPeriod.startUtc,
        DateTime.utc(2030, 3, 4, 6),
      );
      expect(snapshot.report.cells, hasLength(16));
      expect(snapshot.report.cells[2].categoryKey, 'voice_call');
      expect(snapshot.report.cells[2].valueCount, 10);
      expect(
        snapshot.report.cells[2].privacyStatus,
        ManagementReportPrivacyStatus.displayed,
      );
      expect(snapshot.report.cells[0].valueCount, isNull);
      expect(
        snapshot.report.cells[0].privacyStatus,
        ManagementReportPrivacyStatus.suppressed,
      );
    },
  );

  test('PUT management context sends only the selected project ID', () async {
    final gateway = HttpManagementReportGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: _signedInIdentity(),
      client: MockClient((request) async {
        expect(request.method, 'PUT');
        expect(request.url.path, '/v1/management-analysis/context');
        expect(request.url.query, isEmpty);
        expect(request.headers['content-type'], contains('application/json'));
        expect(jsonDecode(request.body), {'project_id': _projectId});
        return _jsonResponse(_contextBody);
      }),
    );
    addTearDown(gateway.close);

    final result = await gateway.selectContext(_projectId);

    expect(
      result,
      isA<ManagementReportSuccess<ManagementAnalysisContextSnapshot>>(),
    );
  });

  test('a 401 refreshes the bearer and retries exactly once', () async {
    var requestCount = 0;
    final identity = _signedInIdentity();
    final gateway = HttpManagementReportGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: identity,
      client: MockClient((request) async {
        requestCount += 1;
        return requestCount == 1
            ? http.Response('', 401)
            : _jsonResponse(_contextBody);
      }),
    );
    addTearDown(gateway.close);

    final result = await gateway.loadContext();

    expect(result, isA<ManagementReportSuccess<Object?>>());
    expect(requestCount, 2);
    expect(identity.accessTokenForceRefreshValues, [false, true]);
  });

  test('a second 401 is rejected without a third request', () async {
    var requestCount = 0;
    final identity = _signedInIdentity();
    final gateway = HttpManagementReportGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: identity,
      client: MockClient((request) async {
        requestCount += 1;
        return http.Response('', 401);
      }),
    );
    addTearDown(gateway.close);

    final result = await gateway.loadContext();

    expect(_rejectedCode(result), ManagementReportFailureCode.unauthorized);
    expect(requestCount, 2);
    expect(identity.accessTokenForceRefreshValues, [false, true]);
  });

  test(
    'a network failure while refreshing a 401 stays a network failure',
    () async {
      var requestCount = 0;
      final identity = _signedInIdentity();
      final gateway = HttpManagementReportGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: identity,
        client: MockClient((request) async {
          requestCount += 1;
          identity.rejectNextAccessTokenWith = const IdentityFailure(
            code: IdentityFailureCode.networkUnavailable,
          );
          return http.Response('', 401);
        }),
      );
      addTearDown(gateway.close);

      final result = await gateway.loadContext();

      expect(
        _rejectedCode(result),
        ManagementReportFailureCode.networkUnavailable,
      );
      expect(requestCount, 1);
      expect(identity.accessTokenForceRefreshValues, [false, true]);
    },
  );

  test(
    'identity failures stay outside HTTP and retain stable categories',
    () async {
      for (final entry in <(IdentityFailureCode, ManagementReportFailureCode)>[
        (
          IdentityFailureCode.networkUnavailable,
          ManagementReportFailureCode.networkUnavailable,
        ),
        (
          IdentityFailureCode.sessionMissing,
          ManagementReportFailureCode.unauthorized,
        ),
      ]) {
        var requestCount = 0;
        final identity = _signedInIdentity()
          ..rejectNextAccessTokenWith = IdentityFailure(code: entry.$1);
        final gateway = HttpManagementReportGateway(
          baseUri: Uri.parse('https://backend.example.test'),
          identitySession: identity,
          client: MockClient((request) async {
            requestCount += 1;
            return _jsonResponse(_contextBody);
          }),
        );

        final result = await gateway.loadContext();

        expect(_rejectedCode(result), entry.$2);
        expect(requestCount, 0);
        await gateway.close();
      }
    },
  );

  test('HTTP and transport failures map to stable categories', () async {
    for (final entry in <(int, ManagementReportFailureCode)>[
      (403, ManagementReportFailureCode.unauthorized),
      (404, ManagementReportFailureCode.notFound),
      (409, ManagementReportFailureCode.untrusted),
      (400, ManagementReportFailureCode.serverRejected),
      (503, ManagementReportFailureCode.serverRejected),
    ]) {
      final gateway = HttpManagementReportGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: _signedInIdentity(),
        client: MockClient((request) async => http.Response('', entry.$1)),
      );

      final result = await gateway.loadContext();

      expect(_rejectedCode(result), entry.$2);
      await gateway.close();
    }

    final networkGateway = HttpManagementReportGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: _signedInIdentity(),
      client: MockClient((request) async {
        throw http.ClientException('offline', request.url);
      }),
    );
    final networkResult = await networkGateway.loadContext();
    expect(
      _rejectedCode(networkResult),
      ManagementReportFailureCode.networkUnavailable,
    );
    await networkGateway.close();
  });

  test(
    '6M rejects extra keys, duplicate projects, and stale current choice',
    () async {
      final invalidBodies = <Map<String, Object?>>[
        {..._contextBody, 'unexpected': true},
        {
          ..._contextBody,
          'available_contexts': [
            (_contextBody['available_contexts']! as List<Object?>).first,
            (_contextBody['available_contexts']! as List<Object?>).first,
          ],
        },
        {..._contextBody, 'available_contexts': const <Object?>[]},
      ];

      for (final body in invalidBodies) {
        final result = await _loadContextBody(body);
        expect(
          _rejectedCode(result),
          ManagementReportFailureCode.invalidResponse,
        );
      }
    },
  );

  test(
    '6N rejects unbounded, duplicate, unordered, and foreign directories',
    () async {
      final unbounded = _mutableJson(_directoryBody);
      unbounded['snapshots'] = List<Object?>.generate(
        21,
        (index) => {
          ...(_directorySnapshots(unbounded).first as Map<String, Object?>),
          'snapshot_id':
              '00000000-0000-4000-8000-${index.toString().padLeft(12, '0')}',
        },
      );
      final duplicate = _mutableJson(_directoryBody);
      _directorySnapshots(duplicate)[1] = _directorySnapshots(duplicate).first;
      final unordered = _mutableJson(_directoryBody);
      _directorySnapshots(
        unordered,
      ).setAll(0, _directorySnapshots(unordered).reversed);
      final foreign = _mutableJson(_directoryBody)
        ..['project_id'] = _secondProjectId;
      final offsetTimestamp = _mutableJson(_directoryBody);
      (_directorySnapshots(offsetTimestamp).first
              as Map<String, Object?>)['data_cutoff_utc'] =
          '2030-03-10T23:00:00.000-06:00';
      final unknownTimeZone = _mutableJson(_directoryBody);
      (_directorySnapshots(unknownTimeZone).first
              as Map<String, Object?>)['reporting_time_zone'] =
          'Mars/Olympus_Mons';

      for (final body in [
        unbounded,
        duplicate,
        unordered,
        foreign,
        offsetTimestamp,
        unknownTimeZone,
      ]) {
        final result = await _listDirectoryBody(body);
        expect(
          _rejectedCode(result),
          ManagementReportFailureCode.invalidResponse,
        );
      }
    },
  );

  test('6L rejects changed report metadata and summary context', () async {
    final wrongMetric = _snapshotBody();
    _report(wrongMetric)['metric_id'] = 'people';
    final wrongSnapshot = _snapshotBody()..['snapshot_id'] = _olderSnapshotId;
    final wrongTimeZone = _snapshotBody();
    _periods(wrongTimeZone)['reporting_time_zone'] = 'UTC';
    final wrongCutoff = _snapshotBody();
    _periods(wrongCutoff)['data_cutoff_utc'] = '2030-03-12T05:00:00.000Z';

    for (final body in [
      wrongMetric,
      wrongSnapshot,
      wrongTimeZone,
      wrongCutoff,
    ]) {
      final result = await _readSnapshotBody(body);
      expect(
        _rejectedCode(result),
        ManagementReportFailureCode.invalidResponse,
      );
    }
  });

  test(
    '6L rejects non-adjacent periods and any unstable cell coordinate',
    () async {
      final nonAdjacent = _snapshotBody();
      (_periods(nonAdjacent)['current_period']!
              as Map<String, Object?>)['start_utc'] =
          '2030-03-05T06:00:00.000Z';
      final missingCell = _snapshotBody();
      _cells(missingCell).removeLast();
      final wrongOrder = _snapshotBody();
      (_cells(wrongOrder)[2] as Map<String, Object?>)['cell_order'] = 3;
      final wrongCategory = _snapshotBody();
      (_cells(wrongCategory)[2] as Map<String, Object?>)['category_key'] =
          'instant_text';

      for (final body in [
        nonAdjacent,
        missingCell,
        wrongOrder,
        wrongCategory,
      ]) {
        final result = await _readSnapshotBody(body);
        expect(
          _rejectedCode(result),
          ManagementReportFailureCode.invalidResponse,
        );
      }
    },
  );

  test(
    '6L never derives or exposes a value against the privacy marker',
    () async {
      final displayedWithoutValue = _snapshotBody();
      (_cells(displayedWithoutValue)[2]
              as Map<String, Object?>)['value_count'] =
          null;
      final suppressedWithValue = _snapshotBody();
      final suppressed =
          _cells(suppressedWithValue).first as Map<String, Object?>;
      suppressed['value_count'] = 0;
      final negativeValue = _snapshotBody();
      (_cells(negativeValue)[2] as Map<String, Object?>)['value_count'] = -1;

      for (final body in [
        displayedWithoutValue,
        suppressedWithValue,
        negativeValue,
      ]) {
        final result = await _readSnapshotBody(body);
        expect(
          _rejectedCode(result),
          ManagementReportFailureCode.invalidResponse,
        );
      }
    },
  );

  test(
    'malformed JSON is an invalid response and base URL is constrained',
    () async {
      final gateway = HttpManagementReportGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: _signedInIdentity(),
        client: MockClient((request) async => http.Response('{', 200)),
      );
      final result = await gateway.loadContext();
      expect(
        _rejectedCode(result),
        ManagementReportFailureCode.invalidResponse,
      );
      await gateway.close();

      expect(
        () => HttpManagementReportGateway(
          baseUri: Uri.parse('http://backend.example.test'),
          identitySession: _signedInIdentity(),
          client: MockClient((request) async => _jsonResponse(_contextBody)),
        ),
        throwsFormatException,
      );
      expect(
        () => HttpManagementReportGateway(
          baseUri: Uri.parse('http://127.0.0.1:8080'),
          identitySession: _signedInIdentity(),
          client: MockClient((request) async => _jsonResponse(_contextBody)),
        ),
        returnsNormally,
      );
    },
  );

  test('deferred gateway reports an explicit not-configured result', () async {
    const gateway = DeferredManagementReportGateway();

    expect(
      _rejectedCode(await gateway.loadContext()),
      ManagementReportFailureCode.notConfigured,
    );
    expect(
      _rejectedCode(await gateway.selectContext(_projectId)),
      ManagementReportFailureCode.notConfigured,
    );
    expect(
      _rejectedCode(await gateway.listSnapshots(_projectId)),
      ManagementReportFailureCode.notConfigured,
    );
    expect(
      _rejectedCode(
        await gateway.readSnapshot(projectId: _projectId, summary: _summary()),
      ),
      ManagementReportFailureCode.notConfigured,
    );
    expect(
      _rejectedCode(
        await gateway.exportSnapshot(
          projectId: _projectId,
          summary: _summary(),
        ),
      ),
      ManagementReportFailureCode.notConfigured,
    );
  });
}

ManagementReportFailureCode _rejectedCode(
  ManagementReportResult<Object?> result,
) => (result as ManagementReportRejected<Object?>).code;

Future<ManagementReportResult<ManagementAnalysisContextSnapshot>>
_loadContextBody(Object? body) async {
  final gateway = HttpManagementReportGateway(
    baseUri: Uri.parse('https://backend.example.test'),
    identitySession: _signedInIdentity(),
    client: MockClient((request) async => _jsonResponse(body)),
  );
  final result = await gateway.loadContext();
  await gateway.close();
  return result;
}

Future<ManagementReportResult<List<ManagementReportSnapshotSummary>>>
_listDirectoryBody(Object? body) async {
  final gateway = HttpManagementReportGateway(
    baseUri: Uri.parse('https://backend.example.test'),
    identitySession: _signedInIdentity(),
    client: MockClient((request) async => _jsonResponse(body)),
  );
  final result = await gateway.listSnapshots(_projectId);
  await gateway.close();
  return result;
}

Future<ManagementReportResult<ManagementReportSnapshot>> _readSnapshotBody(
  Object? body,
) async {
  final gateway = HttpManagementReportGateway(
    baseUri: Uri.parse('https://backend.example.test'),
    identitySession: _signedInIdentity(),
    client: MockClient((request) async => _jsonResponse(body)),
  );
  final result = await gateway.readSnapshot(
    projectId: _projectId,
    summary: _summary(),
  );
  await gateway.close();
  return result;
}

Map<String, Object?> _mutableJson(Object? value) =>
    jsonDecode(jsonEncode(value)) as Map<String, Object?>;

List<Object?> _directorySnapshots(Map<String, Object?> body) =>
    body['snapshots']! as List<Object?>;

Map<String, Object?> _snapshotBody() => _mutableJson({
  'access_event_id': _accessEventId,
  'snapshot_id': _snapshotId,
  'report': _protectedReportBody,
});

Map<String, Object?> _report(Map<String, Object?> body) =>
    body['report']! as Map<String, Object?>;

Map<String, Object?> _periods(Map<String, Object?> body) =>
    _report(body)['periods']! as Map<String, Object?>;

List<Object?> _cells(Map<String, Object?> body) =>
    _report(body)['cells']! as List<Object?>;

FakeIdentitySession _signedInIdentity() => FakeIdentitySession(
  initial: IdentitySnapshot(
    stage: IdentityStage.signedIn,
    principal: const IdentityPrincipal(
      externalSubject: 'subject',
      email: 'person@example.test',
    ),
    expiresAt: DateTime.utc(2030, 1, 2, 4),
  ),
);

const _organizationId = '22222222-2222-4222-8222-222222222222';
const _projectId = '33333333-3333-4333-8333-333333333333';
const _secondProjectId = '55555555-5555-4555-8555-555555555555';
const _accessEventId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _snapshotId = '88888888-8888-4888-8888-888888888888';
const _olderSnapshotId = '77777777-7777-4777-8777-777777777777';
const _reportId = 'contact_sessions_by_channel_two_periods';

const _contextBody = <String, Object?>{
  'current_context': {
    'organization': {'workspace_id': _organizationId, 'name': '同行组织'},
    'project': {'project_id': _projectId, 'name': '校园推广'},
  },
  'available_contexts': [
    {
      'organization': {'workspace_id': _organizationId, 'name': '同行组织'},
      'project': {'project_id': _projectId, 'name': '校园推广'},
    },
    {
      'organization': {'workspace_id': _organizationId, 'name': '同行组织'},
      'project': {'project_id': _secondProjectId, 'name': '社区推广'},
    },
  ],
  'authorization': 'must_reauthorize',
};

const _directoryBody = <String, Object?>{
  'access_event_id': _accessEventId,
  'project_id': _projectId,
  'snapshots': [
    {
      'snapshot_id': _snapshotId,
      'report_id': _reportId,
      'report_version': 1,
      'reporting_time_zone': 'America/Chicago',
      'data_cutoff_utc': '2030-03-11T05:00:00.000Z',
      'released_at_utc': '2030-03-11T05:01:00.000Z',
    },
    {
      'snapshot_id': _olderSnapshotId,
      'report_id': _reportId,
      'report_version': 1,
      'reporting_time_zone': 'America/Chicago',
      'data_cutoff_utc': '2030-03-04T06:00:00.000Z',
      'released_at_utc': '2030-03-04T06:01:00.000Z',
    },
  ],
};

http.Response _jsonResponse(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

ManagementReportSnapshotSummary _summary() => ManagementReportSnapshotSummary(
  snapshotId: _snapshotId,
  reportId: _reportId,
  reportVersion: 1,
  reportingTimeZone: 'America/Chicago',
  dataCutoffUtc: DateTime.utc(2030, 3, 11, 5),
  releasedAtUtc: DateTime.utc(2030, 3, 11, 5, 1),
);

const _protectedReportBody = <String, Object?>{
  'report_id': _reportId,
  'report_version': 1,
  'metric_id': 'contact_sessions',
  'metric_version': 1,
  'dimension': 'channel',
  'query_fingerprint':
      'management-report:contact_sessions_by_channel_two_periods:v1',
  'privacy_policy': 'management_contact_session_privacy_v1',
  'source_scope': 'backend_accepted_contacts',
  'project_id': _projectId,
  'periods': {
    'period_boundary_id': 'iso_week_monday_v1',
    'reporting_time_zone': 'America/Chicago',
    'data_cutoff_utc': '2030-03-11T05:00:00.000Z',
    'previous_period': {
      'start_utc': '2030-02-25T06:00:00.000Z',
      'until_utc': '2030-03-04T06:00:00.000Z',
    },
    'current_period': {
      'start_utc': '2030-03-04T06:00:00.000Z',
      'until_utc': '2030-03-11T05:00:00.000Z',
    },
  },
  'cells': [
    {
      'period_key': 'previous',
      'category_key': 'all',
      'cell_order': 0,
      'value_count': null,
      'privacy_status': 'suppressed',
    },
    {
      'period_key': 'previous',
      'category_key': 'face_to_face',
      'cell_order': 1,
      'value_count': null,
      'privacy_status': 'suppressed',
    },
    {
      'period_key': 'previous',
      'category_key': 'voice_call',
      'cell_order': 2,
      'value_count': 10,
      'privacy_status': 'displayed',
    },
    {
      'period_key': 'previous',
      'category_key': 'video_call',
      'cell_order': 3,
      'value_count': null,
      'privacy_status': 'suppressed',
    },
    {
      'period_key': 'previous',
      'category_key': 'instant_text',
      'cell_order': 4,
      'value_count': null,
      'privacy_status': 'suppressed',
    },
    {
      'period_key': 'previous',
      'category_key': 'asynchronous_message',
      'cell_order': 5,
      'value_count': null,
      'privacy_status': 'suppressed',
    },
    {
      'period_key': 'previous',
      'category_key': 'mixed',
      'cell_order': 6,
      'value_count': null,
      'privacy_status': 'suppressed',
    },
    {
      'period_key': 'previous',
      'category_key': 'other_direct',
      'cell_order': 7,
      'value_count': null,
      'privacy_status': 'suppressed',
    },
    {
      'period_key': 'current',
      'category_key': 'all',
      'cell_order': 8,
      'value_count': null,
      'privacy_status': 'suppressed',
    },
    {
      'period_key': 'current',
      'category_key': 'face_to_face',
      'cell_order': 9,
      'value_count': null,
      'privacy_status': 'suppressed',
    },
    {
      'period_key': 'current',
      'category_key': 'voice_call',
      'cell_order': 10,
      'value_count': 12,
      'privacy_status': 'displayed',
    },
    {
      'period_key': 'current',
      'category_key': 'video_call',
      'cell_order': 11,
      'value_count': null,
      'privacy_status': 'suppressed',
    },
    {
      'period_key': 'current',
      'category_key': 'instant_text',
      'cell_order': 12,
      'value_count': null,
      'privacy_status': 'suppressed',
    },
    {
      'period_key': 'current',
      'category_key': 'asynchronous_message',
      'cell_order': 13,
      'value_count': null,
      'privacy_status': 'suppressed',
    },
    {
      'period_key': 'current',
      'category_key': 'mixed',
      'cell_order': 14,
      'value_count': null,
      'privacy_status': 'suppressed',
    },
    {
      'period_key': 'current',
      'category_key': 'other_direct',
      'cell_order': 15,
      'value_count': null,
      'privacy_status': 'suppressed',
    },
  ],
};
