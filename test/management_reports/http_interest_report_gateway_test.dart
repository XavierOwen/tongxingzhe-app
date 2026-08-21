import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/management_reports/http_interest_report_gateway.dart';
import 'package:tongxingzhe_app/management_reports/interest_report_gateway.dart';

import '../support/fake_identity_session.dart';

void main() {
  test('production factory follows the compile-time Backend configuration', () {
    const configured = String.fromEnvironment('BACKEND_BASE_URL');
    final gateway = productionInterestReportGateway(_signedInIdentity());
    addTearDown(gateway.close);

    if (configured.isEmpty) {
      expect(gateway, isA<DeferredInterestReportGateway>());
    } else {
      expect(gateway, isA<HttpInterestReportGateway>());
    }
  });

  test('directory GET returns the bounded typed interest directory', () async {
    final identity = _signedInIdentity();
    final gateway = HttpInterestReportGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: identity,
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(
          request.url.path,
          '/v1/projects/$_projectId/management-interest-report-snapshots',
        );
        expect(request.url.query, isEmpty);
        expect(request.body, isEmpty);
        expect(request.headers['accept'], 'application/json');
        expect(
          request.headers['authorization'],
          'Bearer test-only-access-token',
        );
        return _jsonResponse(_directoryBody);
      }),
    );
    addTearDown(gateway.close);

    final result = await gateway.listSnapshots(_projectId);

    expect(
      result,
      isA<InterestReportSuccess<InterestReportSnapshotDirectory>>(),
    );
    final directory =
        (result as InterestReportSuccess<InterestReportSnapshotDirectory>)
            .value;
    expect(directory.accessEventId, _accessEventId);
    expect(directory.projectId, _projectId);
    expect(directory.snapshots, hasLength(2));
    expect(directory.snapshots.first.snapshotId, _snapshotId);
    expect(directory.snapshots.first.reportingTimeZone, 'America/Chicago');
    expect(directory.snapshots.first.dataCutoffUtc, _cutoff);
    expect(
      () => directory.snapshots.add(directory.snapshots.first),
      throwsUnsupportedError,
    );
    expect(identity.accessTokenForceRefreshValues, [false]);
  });

  test(
    'detail GET uses the explicit directory ID and parses the ten cells',
    () async {
      final summary = _summary();
      final gateway = HttpInterestReportGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: _signedInIdentity(),
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(
            request.url.path,
            '/v1/projects/$_projectId/management-interest-report-snapshots/$_snapshotId',
          );
          expect(request.url.query, isEmpty);
          expect(request.body, isEmpty);
          expect(request.headers['accept'], 'application/json');
          expect(
            request.headers['authorization'],
            'Bearer test-only-access-token',
          );
          return _jsonResponse(_snapshotBody);
        }),
      );
      addTearDown(gateway.close);

      final result = await gateway.readSnapshot(
        projectId: _projectId,
        summary: summary,
      );

      expect(result, isA<InterestReportSuccess<InterestReportSnapshot>>());
      final snapshot =
          (result as InterestReportSuccess<InterestReportSnapshot>).value;
      expect(snapshot.accessEventId, _accessEventId);
      expect(snapshot.summary, same(summary));
      expect(snapshot.report.projectId, _projectId);
      expect(snapshot.report.cells, hasLength(10));
      expect(snapshot.report.cells.first.valueCount, 10);
      expect(
        snapshot.report.cells[0].privacyStatus,
        InterestReportPrivacyStatus.displayed,
      );
      expect(snapshot.report.cells[5].valueCount, isNull);
      expect(
        snapshot.report.cells[5].privacyStatus,
        InterestReportPrivacyStatus.suppressed,
      );
      expect(
        snapshot.report.periods.previousPeriod.untilUtc,
        snapshot.report.periods.currentPeriod.startUtc,
      );
      expect(snapshot.report.periods.dataCutoffUtc, _cutoff);
      expect(
        () => snapshot.report.cells.add(snapshot.report.cells.first),
        throwsUnsupportedError,
      );
    },
  );

  test('directory accepts empty and exactly twenty ordered items', () async {
    final emptyGateway = _gatewayForBody({
      ..._directoryBody,
      'snapshots': const <Object?>[],
    });
    final emptyResult = await emptyGateway.listSnapshots(_projectId);
    expect(
      (emptyResult as InterestReportSuccess<InterestReportSnapshotDirectory>)
          .value
          .snapshots,
      isEmpty,
    );
    await emptyGateway.close();

    final twentyGateway = _gatewayForBody({
      ..._directoryBody,
      'snapshots': List<Object?>.generate(20, (index) {
        final day = (30 - index).toString().padLeft(2, '0');
        final id =
            '${(index + 1).toString().padLeft(8, '0')}'
            '-0000-4000-8000-000000000000';
        return {
          'snapshot_id': id,
          'report_id': _reportId,
          'report_version': 1,
          'reporting_time_zone': 'UTC',
          'data_cutoff_utc': '2026-08-${day}T05:00:00.000Z',
          'released_at_utc': '2026-08-${day}T05:01:00.000Z',
        };
      }),
    });
    final twentyResult = await twentyGateway.listSnapshots(_projectId);
    expect(
      (twentyResult as InterestReportSuccess<InterestReportSnapshotDirectory>)
          .value
          .snapshots,
      hasLength(20),
    );
    await twentyGateway.close();

    final overBoundGateway = _gatewayForBody({
      ..._directoryBody,
      'snapshots': [
        ...(_directoryBody['snapshots']! as List<Object?>),
        ...List<Object?>.generate(
          19,
          (index) => {
            'snapshot_id':
                '${(index + 3).toString().padLeft(8, '0')}'
                '-0000-4000-8000-000000000000',
            'report_id': _reportId,
            'report_version': 1,
            'reporting_time_zone': 'UTC',
            'data_cutoff_utc':
                '2026-07-${(30 - index).toString().padLeft(2, '0')}T05:00:00.000Z',
            'released_at_utc':
                '2026-07-${(30 - index).toString().padLeft(2, '0')}T05:01:00.000Z',
          },
        ),
      ],
    });
    expect(
      _code(await overBoundGateway.listSnapshots(_projectId)),
      InterestReportFailureCode.invalidResponse,
    );
    await overBoundGateway.close();
  });

  test('401 refreshes once and does not loop', () async {
    var requestCount = 0;
    final identity = _signedInIdentity();
    final gateway = HttpInterestReportGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: identity,
      client: MockClient((request) async {
        requestCount += 1;
        return requestCount == 1
            ? http.Response('', 401)
            : _jsonResponse(_directoryBody);
      }),
    );
    addTearDown(gateway.close);

    final result = await gateway.listSnapshots(_projectId);

    expect(result, isA<InterestReportSuccess<Object?>>());
    expect(requestCount, 2);
    expect(identity.accessTokenForceRefreshValues, [false, true]);

    var repeatedUnauthorizedCount = 0;
    final repeatedUnauthorizedIdentity = _signedInIdentity();
    final repeatedUnauthorizedGateway = HttpInterestReportGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: repeatedUnauthorizedIdentity,
      client: MockClient((request) async {
        repeatedUnauthorizedCount += 1;
        return http.Response('', 401);
      }),
    );
    addTearDown(repeatedUnauthorizedGateway.close);

    expect(
      _code(await repeatedUnauthorizedGateway.listSnapshots(_projectId)),
      InterestReportFailureCode.unauthorized,
    );
    expect(repeatedUnauthorizedCount, 2);
    expect(repeatedUnauthorizedIdentity.accessTokenForceRefreshValues, [
      false,
      true,
    ]);
  });

  test(
    'maps HTTP, identity, and network failures without leaking bodies',
    () async {
      for (final entry in <(int, InterestReportFailureCode)>[
        (400, InterestReportFailureCode.invalidRequest),
        (401, InterestReportFailureCode.unauthorized),
        (403, InterestReportFailureCode.forbidden),
        (404, InterestReportFailureCode.notFound),
        (409, InterestReportFailureCode.untrusted),
        (503, InterestReportFailureCode.serviceUnavailable),
        (500, InterestReportFailureCode.serverRejected),
      ]) {
        final gateway = HttpInterestReportGateway(
          baseUri: Uri.parse('https://backend.example.test'),
          identitySession: _signedInIdentity(),
          client: MockClient(
            (request) async => http.Response('secret internal body', entry.$1),
          ),
        );
        final result = await gateway.listSnapshots(_projectId);
        expect(_code(result), entry.$2);
        expect(result.toString(), isNot(contains('secret')));
        await gateway.close();
      }

      final identityFailure = _signedInIdentity()
        ..rejectNextAccessTokenWith = const IdentityFailure(
          code: IdentityFailureCode.networkUnavailable,
        );
      final identityGateway = HttpInterestReportGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: identityFailure,
        client: MockClient((request) async => _jsonResponse(_directoryBody)),
      );
      expect(
        _code(await identityGateway.listSnapshots(_projectId)),
        InterestReportFailureCode.networkUnavailable,
      );
      await identityGateway.close();

      final networkGateway = HttpInterestReportGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: _signedInIdentity(),
        client: MockClient((request) async {
          throw http.ClientException('offline', request.url);
        }),
      );
      expect(
        _code(await networkGateway.listSnapshots(_projectId)),
        InterestReportFailureCode.networkUnavailable,
      );
      await networkGateway.close();
    },
  );

  test('HTTP timeout maps to networkUnavailable', () async {
    final pending = Completer<http.Response>();
    final gateway = HttpInterestReportGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: _signedInIdentity(),
      client: MockClient((request) => pending.future),
      timeout: const Duration(milliseconds: 1),
    );
    expect(
      _code(await gateway.listSnapshots(_projectId)),
      InterestReportFailureCode.networkUnavailable,
    );
    await gateway.close();
  });

  test('successful responses require JSON and no-store', () async {
    for (final headers in const <Map<String, String>>[
      {'cache-control': 'no-store'},
      {'content-type': 'application/json; charset=utf-8'},
      {'content-type': 'text/plain', 'cache-control': 'no-store'},
      {
        'content-type': 'application/json; charset=utf-8',
        'cache-control': 'private',
      },
    ]) {
      final gateway = HttpInterestReportGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: _signedInIdentity(),
        client: MockClient(
          (request) async =>
              http.Response(jsonEncode(_directoryBody), 200, headers: headers),
        ),
      );
      expect(
        _code(await gateway.listSnapshots(_projectId)),
        InterestReportFailureCode.invalidResponse,
      );
      await gateway.close();
    }

    final invalidJsonGateway = HttpInterestReportGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: _signedInIdentity(),
      client: MockClient(
        (request) async => http.Response(
          '{not-json',
          200,
          headers: const {
            'content-type': 'application/json',
            'cache-control': 'no-store',
          },
        ),
      ),
    );
    expect(
      _code(await invalidJsonGateway.listSnapshots(_projectId)),
      InterestReportFailureCode.invalidResponse,
    );
    await invalidJsonGateway.close();
  });

  test(
    'strict parsers reject directory drift and duplicate metadata',
    () async {
      final missingProject = Map<String, Object?>.of(_directoryBody)
        ..remove('project_id');
      final invalidDirectories = <Map<String, Object?>>[
        missingProject,
        {..._directoryBody, 'snapshots': 'not-a-list'},
        {..._directoryBody, 'unexpected': true},
        {..._directoryBody, 'access_contract_id': 'db-only'},
        {..._directoryBody, 'access_event_id': 'not-a-uuid'},
        {..._directoryBody, 'project_id': _secondProjectId},
        {
          ..._directoryBody,
          'snapshots': [
            ...(_directoryBody['snapshots']! as List<Object?>),
            ...(_directoryBody['snapshots']! as List<Object?>),
          ],
        },
        {
          ..._directoryBody,
          'snapshots': (_directoryBody['snapshots']! as List<Object?>).reversed
              .toList(),
        },
        {
          ..._directoryBody,
          'snapshots': [
            {
              ...((_directoryBody['snapshots']! as List<Object?>).first
                  as Map<String, Object?>),
              'released_at_utc': '2026-08-09T05:00:01.000Z',
            },
          ],
        },
        {
          ..._directoryBody,
          'snapshots': [
            {
              ...((_directoryBody['snapshots']! as List<Object?>).first
                  as Map<String, Object?>),
              'report_id': 'contact_sessions_by_channel_two_periods',
            },
          ],
        },
        {
          ..._directoryBody,
          'snapshots': [
            {
              ...((_directoryBody['snapshots']! as List<Object?>).first
                  as Map<String, Object?>),
              'report_version': 2,
            },
          ],
        },
        {
          ..._directoryBody,
          'snapshots': [
            {
              ...((_directoryBody['snapshots']! as List<Object?>).first
                  as Map<String, Object?>),
              'snapshot_id': _uppercaseSnapshotId,
            },
          ],
        },
        {
          ..._directoryBody,
          'snapshots': [
            {
              ...((_directoryBody['snapshots']! as List<Object?>).first
                  as Map<String, Object?>),
              'reporting_time_zone': 'Mars/Olympus_Mons',
            },
          ],
        },
        {
          ..._directoryBody,
          'snapshots': [
            {
              ...((_directoryBody['snapshots']! as List<Object?>).first
                  as Map<String, Object?>),
              'data_cutoff_utc': '2026-08-10T05:00:00Z',
            },
          ],
        },
      ];
      for (final body in invalidDirectories) {
        final gateway = _gatewayForBody(body);
        expect(
          _code(await gateway.listSnapshots(_projectId)),
          InterestReportFailureCode.invalidResponse,
        );
        await gateway.close();
      }

      final duplicateBody = {
        ..._directoryBody,
        'snapshots': [
          (_directoryBody['snapshots']! as List<Object?>).first,
          (_directoryBody['snapshots']! as List<Object?>).first,
        ],
      };
      final duplicateGateway = _gatewayForBody(duplicateBody);
      expect(
        _code(await duplicateGateway.listSnapshots(_projectId)),
        InterestReportFailureCode.invalidResponse,
      );
      await duplicateGateway.close();
    },
  );

  test(
    'strict detail parser enforces metadata, periods, cells, and PII',
    () async {
      final report = _report(_snapshotBody);
      final invalidReports = <Map<String, Object?>>[
        {..._snapshotBody, 'extra': true},
        {..._snapshotBody, 'access_contract_id': 'db-only'},
        {..._snapshotBody, 'access_event_id': 'not-a-uuid'},
        {..._snapshotBody, 'snapshot_id': _olderSnapshotId},
        {
          ..._snapshotBody,
          'report': {...report, 'project_id': _secondProjectId},
        },
        {
          ..._snapshotBody,
          'report': {...report, 'dimension': 'channel'},
        },
        {
          ..._snapshotBody,
          'report': {...report, 'metric_id': 'contacts'},
        },
        {
          ..._snapshotBody,
          'report': {...report, 'metric_version': 2},
        },
        {
          ..._snapshotBody,
          'report': {...report, 'statistical_unit': 'person'},
        },
        {
          ..._snapshotBody,
          'report': {...report, 'query_fingerprint': 'wrong'},
        },
        {
          ..._snapshotBody,
          'report': {...report, 'privacy_policy': 'wrong'},
        },
        {
          ..._snapshotBody,
          'report': {...report, 'source_scope': 'wrong'},
        },
        {
          ..._snapshotBody,
          'report': {...report, 'contact_id': 'pii'},
        },
        {
          ..._snapshotBody,
          'report': {
            ...report,
            'periods': {...(_periods(report)), 'reporting_time_zone': 'UTC'},
          },
        },
        {
          ..._snapshotBody,
          'report': {
            ...report,
            'periods': {
              ...(_periods(report)),
              'period_boundary_id': 'rolling_window_v1',
            },
          },
        },
        {
          ..._snapshotBody,
          'report': {
            ...report,
            'periods': {
              ...(_periods(report)),
              'current_period': {
                'start_utc': '2026-08-04T05:00:00.000Z',
                'until_utc': '2026-08-10T05:00:00.000Z',
              },
            },
          },
        },
        {
          ..._snapshotBody,
          'report': {...report, 'cells': _cells(_snapshotBody).sublist(0, 9)},
        },
        {
          ..._snapshotBody,
          'report': {
            ...report,
            'cells': [
              {
                ...(_cells(_snapshotBody).first as Map<String, Object?>),
                'cell_order': 1,
              },
              ..._cells(_snapshotBody).skip(1),
            ],
          },
        },
        {
          ..._snapshotBody,
          'report': {
            ...report,
            'cells': [
              {
                ...(_cells(_snapshotBody).first as Map<String, Object?>),
                'value_count': 9007199254740992,
              },
              ..._cells(_snapshotBody).skip(1),
            ],
          },
        },
        {
          ..._snapshotBody,
          'report': {
            ...report,
            'cells': [
              ..._cells(_snapshotBody).take(5),
              {
                ...(_cells(_snapshotBody)[5] as Map<String, Object?>),
                'value_count': 12,
              },
              ..._cells(_snapshotBody).skip(6),
            ],
          },
        },
        {
          ..._snapshotBody,
          'report': {
            ...report,
            'cells': [
              {
                ...(_cells(_snapshotBody).first as Map<String, Object?>),
                'value_count': 9,
              },
              ..._cells(_snapshotBody).skip(1),
            ],
          },
        },
        {
          ..._snapshotBody,
          'report': {
            ...report,
            'cells': [
              ..._cells(_snapshotBody).take(5),
              {
                ...(_cells(_snapshotBody)[5] as Map<String, Object?>),
                'privacy_status': 'displayed',
                'value_count': 10,
              },
              ..._cells(_snapshotBody).skip(6),
            ],
          },
        },
      ];
      for (final body in invalidReports) {
        final gateway = _gatewayForBody(body);
        expect(
          _code(
            await gateway.readSnapshot(
              projectId: _projectId,
              summary: _summary(),
            ),
          ),
          InterestReportFailureCode.invalidResponse,
        );
        await gateway.close();
      }
    },
  );

  test('local UUID and summary validation precede identity and HTTP', () async {
    final identity = _signedInIdentity();
    var requestCount = 0;
    final gateway = HttpInterestReportGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: identity,
      client: MockClient((request) async {
        requestCount += 1;
        return _jsonResponse(_directoryBody);
      }),
    );
    addTearDown(gateway.close);

    expect(
      _code(await gateway.listSnapshots('not-a-uuid')),
      InterestReportFailureCode.invalidRequest,
    );
    expect(
      _code(
        await gateway.readSnapshot(
          projectId: 'not-a-uuid',
          summary: _summary(),
        ),
      ),
      InterestReportFailureCode.invalidRequest,
    );
    expect(
      _code(
        await gateway.readSnapshot(
          projectId: _projectId,
          summary: InterestReportSnapshotSummary(
            snapshotId: _uppercaseSnapshotId,
            reportId: _reportId,
            reportVersion: 1,
            reportingTimeZone: 'UTC',
            dataCutoffUtc: _cutoff,
            releasedAtUtc: _released,
          ),
        ),
      ),
      InterestReportFailureCode.invalidRequest,
    );
    expect(
      _code(
        await gateway.readSnapshot(
          projectId: _projectId,
          summary: InterestReportSnapshotSummary(
            snapshotId: _snapshotId,
            reportId: 'wrong-report',
            reportVersion: 1,
            reportingTimeZone: 'UTC',
            dataCutoffUtc: _cutoff,
            releasedAtUtc: _released,
          ),
        ),
      ),
      InterestReportFailureCode.invalidRequest,
    );
    expect(
      _code(
        await gateway.readSnapshot(
          projectId: _projectId,
          summary: InterestReportSnapshotSummary(
            snapshotId: _snapshotId,
            reportId: _reportId,
            reportVersion: 1,
            reportingTimeZone: 'UTC',
            dataCutoffUtc: DateTime(2026, 8, 10, 5),
            releasedAtUtc: _released,
          ),
        ),
      ),
      InterestReportFailureCode.invalidRequest,
    );
    expect(identity.accessTokenForceRefreshValues, isEmpty);
    expect(requestCount, 0);
  });

  test('base URL, deferred mode, and client close obey the boundary', () async {
    expect(
      () => HttpInterestReportGateway(
        baseUri: Uri.parse('http://backend.example.test'),
        identitySession: _signedInIdentity(),
        client: MockClient((request) async => _jsonResponse(_directoryBody)),
      ),
      throwsFormatException,
    );
    expect(
      () => HttpInterestReportGateway(
        baseUri: Uri.parse('http://localhost:8080'),
        identitySession: _signedInIdentity(),
        client: MockClient((request) async => _jsonResponse(_directoryBody)),
      ),
      returnsNormally,
    );
    expect(
      _code(
        await const DeferredInterestReportGateway().listSnapshots(_projectId),
      ),
      InterestReportFailureCode.notConfigured,
    );
    expect(
      _code(
        await const DeferredInterestReportGateway().readSnapshot(
          projectId: _projectId,
          summary: _summary(),
        ),
      ),
      InterestReportFailureCode.notConfigured,
    );

    final client = _TrackingClient();
    final gateway = HttpInterestReportGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: _signedInIdentity(),
      client: client,
    );
    await gateway.close();
    expect(client.closed, isTrue);
    expect(
      _code(await gateway.listSnapshots(_projectId)),
      InterestReportFailureCode.networkUnavailable,
    );
    expect(client.sendCount, 1);
  });
}

FakeIdentitySession _signedInIdentity() => FakeIdentitySession(
  initial: const IdentitySnapshot(
    stage: IdentityStage.signedIn,
    principal: IdentityPrincipal(
      externalSubject: 'subject',
      email: 'person@example.test',
    ),
  ),
);

const _projectId = '33333333-3333-4333-8333-333333333333';
const _secondProjectId = '44444444-4444-4444-8444-444444444444';
const _accessEventId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _snapshotId = '88888888-8888-4888-8888-888888888888';
const _olderSnapshotId = '77777777-7777-4777-8777-777777777777';
const _uppercaseSnapshotId = 'A8888888-8888-4888-8888-888888888888';
const _reportId = 'contact_sessions_by_interest_level_two_periods';
final _cutoff = DateTime.utc(2026, 8, 10, 5);
final _released = DateTime.utc(2026, 8, 10, 5, 1);

const _directoryBody = <String, Object?>{
  'access_event_id': _accessEventId,
  'project_id': _projectId,
  'snapshots': [
    {
      'snapshot_id': _snapshotId,
      'report_id': _reportId,
      'report_version': 1,
      'reporting_time_zone': 'America/Chicago',
      'data_cutoff_utc': '2026-08-10T05:00:00.000Z',
      'released_at_utc': '2026-08-10T05:00:01.000Z',
    },
    {
      'snapshot_id': _olderSnapshotId,
      'report_id': _reportId,
      'report_version': 1,
      'reporting_time_zone': 'UTC',
      'data_cutoff_utc': '2026-08-03T00:00:00.000Z',
      'released_at_utc': '2026-08-03T00:00:01.000Z',
    },
  ],
};

const _snapshotBody = <String, Object?>{
  'access_event_id': _accessEventId,
  'snapshot_id': _snapshotId,
  'report': {
    'report_id': _reportId,
    'report_version': 1,
    'metric_id': 'interest_distribution',
    'metric_version': 1,
    'statistical_unit': 'contact_session',
    'dimension': 'interest_level',
    'query_fingerprint':
        'management-report:contact_sessions_by_interest_level_two_periods:v1',
    'privacy_policy': 'management_interest_distribution_privacy_v1',
    'source_scope': 'backend_accepted_active_contacts_current_revision',
    'project_id': _projectId,
    'periods': {
      'period_boundary_id': 'iso_week_monday_v1',
      'reporting_time_zone': 'America/Chicago',
      'data_cutoff_utc': '2026-08-10T05:00:00.000Z',
      'previous_period': {
        'start_utc': '2026-07-27T05:00:00.000Z',
        'until_utc': '2026-08-03T05:00:00.000Z',
      },
      'current_period': {
        'start_utc': '2026-08-03T05:00:00.000Z',
        'until_utc': '2026-08-10T05:00:00.000Z',
      },
    },
    'cells': [
      {
        'period_key': 'previous',
        'interest_level': 0,
        'cell_order': 0,
        'privacy_status': 'displayed',
        'value_count': 10,
      },
      {
        'period_key': 'previous',
        'interest_level': 1,
        'cell_order': 1,
        'privacy_status': 'displayed',
        'value_count': 11,
      },
      {
        'period_key': 'previous',
        'interest_level': 2,
        'cell_order': 2,
        'privacy_status': 'displayed',
        'value_count': 12,
      },
      {
        'period_key': 'previous',
        'interest_level': 3,
        'cell_order': 3,
        'privacy_status': 'displayed',
        'value_count': 13,
      },
      {
        'period_key': 'previous',
        'interest_level': 4,
        'cell_order': 4,
        'privacy_status': 'displayed',
        'value_count': 14,
      },
      {
        'period_key': 'current',
        'interest_level': 0,
        'cell_order': 5,
        'privacy_status': 'suppressed',
        'value_count': null,
      },
      {
        'period_key': 'current',
        'interest_level': 1,
        'cell_order': 6,
        'privacy_status': 'suppressed',
        'value_count': null,
      },
      {
        'period_key': 'current',
        'interest_level': 2,
        'cell_order': 7,
        'privacy_status': 'suppressed',
        'value_count': null,
      },
      {
        'period_key': 'current',
        'interest_level': 3,
        'cell_order': 8,
        'privacy_status': 'suppressed',
        'value_count': null,
      },
      {
        'period_key': 'current',
        'interest_level': 4,
        'cell_order': 9,
        'privacy_status': 'suppressed',
        'value_count': null,
      },
    ],
  },
};

http.Response _jsonResponse(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
  },
);

InterestReportFailureCode _code(InterestReportResult<Object?> result) =>
    (result as InterestReportRejected<Object?>).code;

HttpInterestReportGateway _gatewayForBody(Map<String, Object?> body) =>
    HttpInterestReportGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: _signedInIdentity(),
      client: MockClient((request) async => _jsonResponse(body)),
    );

List<Object?> _cells(Map<String, Object?> body) =>
    (_report(body)['cells']! as List<Object?>);

Map<String, Object?> _report(Map<String, Object?> body) =>
    body['report']! as Map<String, Object?>;

Map<String, Object?> _periods(Map<String, Object?> report) =>
    report['periods']! as Map<String, Object?>;

InterestReportSnapshotSummary _summary() => InterestReportSnapshotSummary(
  snapshotId: _snapshotId,
  reportId: _reportId,
  reportVersion: 1,
  reportingTimeZone: 'America/Chicago',
  dataCutoffUtc: _cutoff,
  releasedAtUtc: _released,
);

final class _TrackingClient extends http.BaseClient {
  bool closed = false;
  int sendCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    sendCount += 1;
    if (closed) {
      throw http.ClientException('client is closed', request.url);
    }
    throw StateError('tracking client should not send before close');
  }

  @override
  void close() {
    closed = true;
  }
}
