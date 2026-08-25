import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/management_reports/original_region_report_gateway.dart';
import 'package:tongxingzhe_app/management_reports/http_original_region_report_gateway.dart';

import '../support/fake_identity_session.dart';

void main() {
  test('production factory follows the compile-time Backend configuration', () {
    const configured = String.fromEnvironment('BACKEND_BASE_URL');
    final gateway = productionOriginalRegionReportGateway(_signedInIdentity());
    addTearDown(gateway.close);

    if (configured.isEmpty) {
      expect(gateway, isA<DeferredOriginalRegionReportGateway>());
    } else {
      expect(gateway, isA<HttpOriginalRegionReportGateway>());
    }
  });

  test(
    'directory GET returns a bounded typed original-region directory',
    () async {
      final identity = _signedInIdentity();
      final gateway = HttpOriginalRegionReportGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: identity,
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(
            request.url.path,
            '/v1/projects/$_projectId/management-original-region-report-snapshots',
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
        isA<
          OriginalRegionReportSuccess<OriginalRegionReportSnapshotDirectory>
        >(),
      );
      final directory =
          (result
                  as OriginalRegionReportSuccess<
                    OriginalRegionReportSnapshotDirectory
                  >)
              .value;
      expect(directory.accessEventId, _accessEventId);
      expect(directory.projectId, _projectId);
      expect(directory.snapshots, hasLength(2));
      expect(directory.snapshots.first.snapshotId, _snapshotId);
      expect(directory.snapshots.first.dataCutoffUtc, _cutoff);
      expect(
        () => directory.snapshots.add(directory.snapshots.first),
        throwsUnsupportedError,
      );
      expect(identity.accessTokenForceRefreshValues, [false]);
    },
  );

  test(
    'detail GET uses the explicit directory ID and parses the protected grid',
    () async {
      final summary = _summary();
      final identity = _signedInIdentity();
      final gateway = HttpOriginalRegionReportGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: identity,
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(
            request.url.path,
            '/v1/projects/$_projectId/management-original-region-report-snapshots/$_snapshotId',
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

      expect(
        result,
        isA<OriginalRegionReportSuccess<OriginalRegionReportSnapshot>>(),
      );
      final snapshot =
          (result as OriginalRegionReportSuccess<OriginalRegionReportSnapshot>)
              .value;
      expect(snapshot.accessEventId, _accessEventId);
      expect(snapshot.summary, same(summary));
      expect(snapshot.report.projectId, _projectId);
      expect(snapshot.report.sourceTreeContext.sourceTreeVersion, 'tree-v1');
      expect(
        snapshot.report.sourceTreeContext.sourceContentFingerprint,
        hasLength(64),
      );
      expect(snapshot.report.cells, hasLength(4));
      expect(snapshot.report.cells[0].cityId, 'city-a');
      expect(snapshot.report.cells[0].valueCount, 12);
      expect(snapshot.report.cells[1].valueCount, isNull);
      expect(
        snapshot.report.cells[1].privacyStatus,
        OriginalRegionReportPrivacyStatus.suppressed,
      );
      expect(
        snapshot.report.periods.currentPeriod.startUtc,
        DateTime.utc(2026, 8, 3),
      );
      expect(
        () => snapshot.report.cells.add(snapshot.report.cells.first),
        throwsUnsupportedError,
      );
      expect(identity.accessTokenForceRefreshValues, [false]);
    },
  );

  test(
    'local project and snapshot validation precedes identity and HTTP',
    () async {
      final identity = _signedInIdentity();
      var requestCount = 0;
      final gateway = HttpOriginalRegionReportGateway(
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
        OriginalRegionReportFailureCode.invalidRequest,
      );
      expect(
        _code(
          await gateway.readSnapshot(
            projectId: 'not-a-uuid',
            summary: _summary(),
          ),
        ),
        OriginalRegionReportFailureCode.invalidRequest,
      );
      expect(
        _code(
          await gateway.readSnapshot(
            projectId: _projectId,
            summary: OriginalRegionReportSnapshotSummary(
              snapshotId: 'NOT-A-UUID',
              reportId: _reportId,
              reportVersion: 1,
              reportingTimeZone: 'UTC',
              dataCutoffUtc: _cutoff,
              releasedAtUtc: _released,
            ),
          ),
        ),
        OriginalRegionReportFailureCode.invalidRequest,
      );
      expect(
        _code(
          await gateway.readSnapshot(
            projectId: _projectId,
            summary: OriginalRegionReportSnapshotSummary(
              snapshotId: _snapshotId,
              reportId: 'wrong-report',
              reportVersion: 1,
              reportingTimeZone: 'UTC',
              dataCutoffUtc: _cutoff,
              releasedAtUtc: _released,
            ),
          ),
        ),
        OriginalRegionReportFailureCode.invalidRequest,
      );
      expect(
        _code(
          await gateway.readSnapshot(
            projectId: _projectId,
            summary: OriginalRegionReportSnapshotSummary(
              snapshotId: _snapshotId,
              reportId: _reportId,
              reportVersion: 2,
              reportingTimeZone: 'UTC',
              dataCutoffUtc: _cutoff,
              releasedAtUtc: _released,
            ),
          ),
        ),
        OriginalRegionReportFailureCode.invalidRequest,
      );
      expect(
        _code(
          await gateway.readSnapshot(
            projectId: _projectId,
            summary: OriginalRegionReportSnapshotSummary(
              snapshotId: _snapshotId,
              reportId: _reportId,
              reportVersion: 1,
              reportingTimeZone: 'UTC',
              dataCutoffUtc: _cutoff,
              releasedAtUtc: DateTime.utc(2026, 8, 10, 4, 59),
            ),
          ),
        ),
        OriginalRegionReportFailureCode.invalidRequest,
      );
      expect(identity.accessTokenForceRefreshValues, isEmpty);
      expect(requestCount, 0);
    },
  );

  test(
    'directory accepts empty and exactly twenty server-ordered items',
    () async {
      final emptyGateway = _gatewayForBody({
        ..._directoryBody,
        'snapshots': const <Object?>[],
      });
      final emptyResult = await emptyGateway.listSnapshots(_projectId);
      expect(
        (emptyResult
                as OriginalRegionReportSuccess<
                  OriginalRegionReportSnapshotDirectory
                >)
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
        (twentyResult
                as OriginalRegionReportSuccess<
                  OriginalRegionReportSnapshotDirectory
                >)
            .value
            .snapshots,
        hasLength(20),
      );
      await twentyGateway.close();
    },
  );

  test('401 refreshes once and never loops', () async {
    var requestCount = 0;
    final identity = _signedInIdentity();
    final gateway = HttpOriginalRegionReportGateway(
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

    expect(result, isA<OriginalRegionReportSuccess<Object?>>());
    expect(requestCount, 2);
    expect(identity.accessTokenForceRefreshValues, [false, true]);

    var secondRequestCount = 0;
    final repeatedUnauthorizedIdentity = _signedInIdentity();
    final secondGateway = HttpOriginalRegionReportGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: repeatedUnauthorizedIdentity,
      client: MockClient((request) async {
        secondRequestCount += 1;
        return http.Response('', 401);
      }),
    );
    addTearDown(secondGateway.close);
    expect(
      _code(await secondGateway.listSnapshots(_projectId)),
      OriginalRegionReportFailureCode.unauthorized,
    );
    expect(secondRequestCount, 2);
    expect(repeatedUnauthorizedIdentity.accessTokenForceRefreshValues, [
      false,
      true,
    ]);
  });

  test(
    'maps HTTP, identity, and transport failures without response bodies',
    () async {
      for (final entry in <(int, OriginalRegionReportFailureCode)>[
        (400, OriginalRegionReportFailureCode.invalidRequest),
        (401, OriginalRegionReportFailureCode.unauthorized),
        (403, OriginalRegionReportFailureCode.forbidden),
        (404, OriginalRegionReportFailureCode.notFound),
        (409, OriginalRegionReportFailureCode.untrusted),
        (503, OriginalRegionReportFailureCode.serviceUnavailable),
        (500, OriginalRegionReportFailureCode.serverRejected),
      ]) {
        final gateway = HttpOriginalRegionReportGateway(
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
      final identityGateway = HttpOriginalRegionReportGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: identityFailure,
        client: MockClient((request) async => _jsonResponse(_directoryBody)),
      );
      expect(
        _code(await identityGateway.listSnapshots(_projectId)),
        OriginalRegionReportFailureCode.networkUnavailable,
      );
      await identityGateway.close();

      final unauthenticatedGateway = HttpOriginalRegionReportGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: FakeIdentitySession(),
        client: MockClient((request) async => _jsonResponse(_directoryBody)),
      );
      expect(
        _code(await unauthenticatedGateway.listSnapshots(_projectId)),
        OriginalRegionReportFailureCode.unauthorized,
      );
      await unauthenticatedGateway.close();

      final networkGateway = HttpOriginalRegionReportGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: _signedInIdentity(),
        client: MockClient((request) async {
          throw http.ClientException('offline', request.url);
        }),
      );
      expect(
        _code(await networkGateway.listSnapshots(_projectId)),
        OriginalRegionReportFailureCode.networkUnavailable,
      );
      await networkGateway.close();
    },
  );

  test('HTTP timeout maps to networkUnavailable', () async {
    final pending = Completer<http.Response>();
    final gateway = HttpOriginalRegionReportGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: _signedInIdentity(),
      client: MockClient((request) => pending.future),
      timeout: const Duration(milliseconds: 1),
    );
    expect(
      _code(await gateway.listSnapshots(_projectId)),
      OriginalRegionReportFailureCode.networkUnavailable,
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
      final gateway = HttpOriginalRegionReportGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: _signedInIdentity(),
        client: MockClient(
          (request) async =>
              http.Response(jsonEncode(_directoryBody), 200, headers: headers),
        ),
      );
      expect(
        _code(await gateway.listSnapshots(_projectId)),
        OriginalRegionReportFailureCode.invalidResponse,
      );
      await gateway.close();
    }
  });

  test(
    'strict parsers reject protocol drift and unsafe original-region cells',
    () async {
      final invalidDirectories = <Map<String, Object?>>[
        {..._directoryBody, 'unexpected': true},
        {..._directoryBody, 'access_contract_id': 'db-only'},
        {..._directoryBody, 'email': 'person@example.test'},
        {..._directoryBody, 'project_id': _secondProjectId},
        {
          ..._directoryBody,
          'snapshots': [
            ...(_directoryBody['snapshots']! as List<Object?>),
            ...List<Object?>.generate(19, (index) {
              final day = (19 - index).toString().padLeft(2, '0');
              return {
                'snapshot_id':
                    '${(index + 3).toString().padLeft(8, '0')}'
                    '-0000-4000-8000-000000000000',
                'report_id': _reportId,
                'report_version': 1,
                'reporting_time_zone': 'UTC',
                'data_cutoff_utc': '2026-07-${day}T05:00:00.000Z',
                'released_at_utc': '2026-07-${day}T05:01:00.000Z',
              };
            }),
          ],
        },
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
      ];
      for (final body in invalidDirectories) {
        final gateway = _gatewayForBody(body);
        expect(
          _code(await gateway.listSnapshots(_projectId)),
          OriginalRegionReportFailureCode.invalidResponse,
        );
        await gateway.close();
      }

      final invalidReports = <Map<String, Object?>>[
        {..._snapshotBody, 'extra': true},
        {..._snapshotBody, 'access_contract_id': 'db-only'},
        {..._snapshotBody, 'email': 'person@example.test'},
        {..._snapshotBody, 'snapshot_id': _olderSnapshotId},
        {
          ..._snapshotBody,
          'report': {
            ...(_snapshotBody['report']! as Map<String, Object?>),
            'project_id': _secondProjectId,
          },
        },
        {
          ..._snapshotBody,
          'report': {
            ...(_snapshotBody['report']! as Map<String, Object?>),
            'query_fingerprint': 'management-report:channel:v1',
          },
        },
        {
          ..._snapshotBody,
          'report': {
            ...(_snapshotBody['report']! as Map<String, Object?>),
            'city_name': 'Chicago',
          },
        },
        {
          ..._snapshotBody,
          'report': {
            ...(_snapshotBody['report']! as Map<String, Object?>),
            'dimension': 'channel',
          },
        },
        {
          ..._snapshotBody,
          'report': {
            ...(_snapshotBody['report']! as Map<String, Object?>),
            'periods': {
              ...((_snapshotBody['report']! as Map<String, Object?>)['periods']!
                  as Map<String, Object?>),
              'current_period': {
                'start_utc': '2026-08-04T00:00:00.000Z',
                'until_utc': '2026-08-10T00:00:00.000Z',
              },
            },
          },
        },
        {
          ..._snapshotBody,
          'report': {
            ...(_snapshotBody['report']! as Map<String, Object?>),
            'source_tree_context': {
              ...((_snapshotBody['report']!
                      as Map<String, Object?>)['source_tree_context']!
                  as Map<String, Object?>),
              'source_content_fingerprint': 'not-a-fingerprint',
            },
          },
        },
        {
          ..._snapshotBody,
          'report': {
            ...(_snapshotBody['report']! as Map<String, Object?>),
            'source_tree_context': {
              ...((_snapshotBody['report']!
                      as Map<String, Object?>)['source_tree_context']!
                  as Map<String, Object?>),
              'city_name': 'Chicago',
            },
          },
        },
        {
          ..._snapshotBody,
          'report': {
            ...(_snapshotBody['report']! as Map<String, Object?>),
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
            ...(_snapshotBody['report']! as Map<String, Object?>),
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
            ...(_snapshotBody['report']! as Map<String, Object?>),
            'cells': [
              {
                ...(_cells(_snapshotBody).first as Map<String, Object?>),
                'city_id': 'city-z',
              },
              ..._cells(_snapshotBody).skip(1),
            ],
          },
        },
        {
          ..._snapshotBody,
          'report': {
            ...(_snapshotBody['report']! as Map<String, Object?>),
            'cells': [
              {
                ...(_cells(_snapshotBody).first as Map<String, Object?>),
                'privacy_status': 'suppressed',
                'value_count': 10,
              },
              ..._cells(_snapshotBody).skip(1),
            ],
          },
        },
        {
          ..._snapshotBody,
          'report': {
            ...(_snapshotBody['report']! as Map<String, Object?>),
            'cells': [
              {
                ...(_cells(_snapshotBody).first as Map<String, Object?>),
                'privacy_status': 'displayed',
                'value_count': null,
              },
              ..._cells(_snapshotBody).skip(1),
            ],
          },
        },
        {
          ..._snapshotBody,
          'report': {
            ...(_snapshotBody['report']! as Map<String, Object?>),
            'cells': [
              ..._cells(_snapshotBody),
              {
                'period_key': 'current',
                'city_id': 'city-z',
                'cell_order': 4,
                'privacy_status': 'suppressed',
                'value_count': null,
              },
            ],
          },
        },
        {
          ..._snapshotBody,
          'report': {
            ...(_snapshotBody['report']! as Map<String, Object?>),
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
            ...(_snapshotBody['report']! as Map<String, Object?>),
            'cells': [
              {
                ...(_cells(_snapshotBody)[0] as Map<String, Object?>),
                'value_count': 0,
              },
              ..._cells(_snapshotBody).skip(1),
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
          OriginalRegionReportFailureCode.invalidResponse,
        );
        await gateway.close();
      }
    },
  );

  test('base URL, deferred mode, and client close obey the boundary', () async {
    expect(
      () => HttpOriginalRegionReportGateway(
        baseUri: Uri.parse('http://backend.example.test'),
        identitySession: _signedInIdentity(),
        client: MockClient((request) async => _jsonResponse(_directoryBody)),
      ),
      throwsFormatException,
    );
    expect(
      () => HttpOriginalRegionReportGateway(
        baseUri: Uri.parse('http://localhost:8080'),
        identitySession: _signedInIdentity(),
        client: MockClient((request) async => _jsonResponse(_directoryBody)),
      ),
      returnsNormally,
    );
    expect(
      _code(
        await const DeferredOriginalRegionReportGateway().listSnapshots(
          _projectId,
        ),
      ),
      OriginalRegionReportFailureCode.notConfigured,
    );
    expect(
      _code(
        await const DeferredOriginalRegionReportGateway().readSnapshot(
          projectId: _projectId,
          summary: _summary(),
        ),
      ),
      OriginalRegionReportFailureCode.notConfigured,
    );

    expect(
      () => HttpOriginalRegionReportGateway(
        baseUri: Uri.parse('https://backend.example.test?token=secret'),
        identitySession: _signedInIdentity(),
        client: MockClient((request) async => _jsonResponse(_directoryBody)),
      ),
      throwsFormatException,
    );
    expect(
      () => HttpOriginalRegionReportGateway(
        baseUri: Uri.parse('https://user:password@backend.example.test'),
        identitySession: _signedInIdentity(),
        client: MockClient((request) async => _jsonResponse(_directoryBody)),
      ),
      throwsFormatException,
    );

    final client = _TrackingClient();
    final gateway = HttpOriginalRegionReportGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: _signedInIdentity(),
      client: client,
    );
    await gateway.close();
    expect(client.closed, isTrue);
    expect(
      _code(await gateway.listSnapshots(_projectId)),
      OriginalRegionReportFailureCode.networkUnavailable,
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
const _accessEventId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _snapshotId = '88888888-8888-4888-8888-888888888888';
const _olderSnapshotId = '77777777-7777-4777-8777-777777777777';
const _reportId = 'contact_sessions_by_original_region_two_periods';
final _cutoff = DateTime.utc(2026, 8, 10, 5);

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

http.Response _jsonResponse(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
  },
);

OriginalRegionReportFailureCode _code(
  OriginalRegionReportResult<Object?> result,
) => (result as OriginalRegionReportRejected<Object?>).code;

HttpOriginalRegionReportGateway _gatewayForBody(Map<String, Object?> body) =>
    HttpOriginalRegionReportGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: _signedInIdentity(),
      client: MockClient((request) async => _jsonResponse(body)),
    );

List<Object?> _cells(Map<String, Object?> body) =>
    (body['report']! as Map<String, Object?>)['cells']! as List<Object?>;

OriginalRegionReportSnapshotSummary _summary() =>
    OriginalRegionReportSnapshotSummary(
      snapshotId: _snapshotId,
      reportId: _reportId,
      reportVersion: 1,
      reportingTimeZone: 'UTC',
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

const _snapshotBody = <String, Object?>{
  'access_event_id': _accessEventId,
  'snapshot_id': _snapshotId,
  'report': {
    'report_id': _reportId,
    'report_version': 1,
    'metric_id': 'contact_sessions',
    'metric_version': 1,
    'dimension': 'original_region',
    'view_mode': 'original',
    'region_granularity': 'city',
    'query_fingerprint':
        'management-report:contact_sessions_by_original_region_two_periods:v1',
    'privacy_policy': 'management_original_region_contact_session_privacy_v1',
    'source_scope':
        'backend_accepted_active_contacts_original_current_revision',
    'project_id': _projectId,
    'periods': {
      'period_boundary_id': 'iso_week_monday_v1',
      'reporting_time_zone': 'UTC',
      'data_cutoff_utc': '2026-08-10T05:00:00.000Z',
      'previous_period': {
        'start_utc': '2026-07-27T00:00:00.000Z',
        'until_utc': '2026-08-03T00:00:00.000Z',
      },
      'current_period': {
        'start_utc': '2026-08-03T00:00:00.000Z',
        'until_utc': '2026-08-10T00:00:00.000Z',
      },
    },
    'data_cutoff_utc': '2026-08-10T05:00:00.000Z',
    'source_change_sequence': 7,
    'source_tree_context': {
      'source_tree_context_contract_id':
          'management-original-region-source-tree:v1',
      'result_status': 'selected',
      'reason_code': 'single_original_source_tree',
      'source_tree_version': 'tree-v1',
      'source_content_fingerprint':
          '0000000000000000000000000000000000000000000000000000000000000000',
    },
    'result_status': 'completed',
    'cells': [
      {
        'period_key': 'previous',
        'city_id': 'city-a',
        'cell_order': 0,
        'privacy_status': 'displayed',
        'value_count': 12,
      },
      {
        'period_key': 'previous',
        'city_id': 'city-b',
        'cell_order': 1,
        'privacy_status': 'suppressed',
        'value_count': null,
      },
      {
        'period_key': 'current',
        'city_id': 'city-a',
        'cell_order': 2,
        'privacy_status': 'displayed',
        'value_count': 20,
      },
      {
        'period_key': 'current',
        'city_id': 'city-b',
        'cell_order': 3,
        'privacy_status': 'suppressed',
        'value_count': null,
      },
    ],
  },
};

final _released = DateTime.utc(2026, 8, 10, 5, 1);

const _secondProjectId = '44444444-4444-4444-8444-444444444444';
