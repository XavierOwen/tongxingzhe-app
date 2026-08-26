import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/management_reports/follow_up_consent_ratio_report_gateway.dart';
import 'package:tongxingzhe_app/management_reports/http_follow_up_consent_ratio_report_gateway.dart';

import '../support/fake_identity_session.dart';

void main() {
  test('production factory follows the compile-time Backend configuration', () {
    const configured = String.fromEnvironment('BACKEND_BASE_URL');
    final gateway = productionFollowUpConsentRatioReportGateway(
      _signedInIdentity(),
    );
    addTearDown(gateway.close);

    if (configured.isEmpty) {
      expect(gateway, isA<DeferredFollowUpConsentRatioReportGateway>());
    } else {
      expect(gateway, isA<HttpFollowUpConsentRatioReportGateway>());
    }
  });

  test('directory GET returns ordered immutable metadata', () async {
    final identity = _signedInIdentity();
    final gateway = HttpFollowUpConsentRatioReportGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: identity,
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(
          request.url.path,
          '/v1/projects/$_projectId'
          '/management-follow-up-consent-ratio-report-snapshots',
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
        FollowUpConsentRatioReportSuccess<
          FollowUpConsentRatioReportSnapshotDirectory
        >
      >(),
    );
    final directory =
        (result
                as FollowUpConsentRatioReportSuccess<
                  FollowUpConsentRatioReportSnapshotDirectory
                >)
            .value;
    expect(directory.accessEventId, _accessEventId);
    expect(directory.projectId, _projectId);
    expect(directory.snapshots, hasLength(2));
    expect(directory.snapshots.first.snapshotId, _snapshotId);
    expect(directory.snapshots.first.dataCutoffUtc, _cutoff);
    expect(
      directory.snapshots.first.releasedAtUtc,
      DateTime.utc(2026, 8, 10, 0, 1),
    );
    expect(
      () => directory.snapshots.add(directory.snapshots.first),
      throwsUnsupportedError,
    );
    expect(identity.accessTokenForceRefreshValues, [false]);
  });

  test('directory accepts an empty list and exactly twenty items', () async {
    final emptyGateway = _gatewayForBody({
      ..._directoryBody,
      'snapshots': const <Object?>[],
    });
    final emptyResult = await emptyGateway.listSnapshots(_projectId);
    expect(
      (emptyResult
              as FollowUpConsentRatioReportSuccess<
                FollowUpConsentRatioReportSnapshotDirectory
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
          'data_cutoff_utc': '2026-08-${day}T00:00:00.000Z',
          'released_at_utc': '2026-08-${day}T00:01:00.000Z',
        };
      }),
    });
    final twentyResult = await twentyGateway.listSnapshots(_projectId);
    expect(
      (twentyResult
              as FollowUpConsentRatioReportSuccess<
                FollowUpConsentRatioReportSnapshotDirectory
              >)
          .value
          .snapshots,
      hasLength(20),
    );
    await twentyGateway.close();
  });

  test(
    'detail GET uses the explicit directory ID and parses two periods',
    () async {
      final summary = _summary();
      final identity = _signedInIdentity();
      final gateway = HttpFollowUpConsentRatioReportGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: identity,
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(
            request.url.path,
            '/v1/projects/$_projectId'
            '/management-follow-up-consent-ratio-report-snapshots/$_snapshotId',
          );
          expect(request.url.query, isEmpty);
          expect(request.body, isEmpty);
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
        isA<
          FollowUpConsentRatioReportSuccess<FollowUpConsentRatioReportSnapshot>
        >(),
      );
      final snapshot =
          (result
                  as FollowUpConsentRatioReportSuccess<
                    FollowUpConsentRatioReportSnapshot
                  >)
              .value;
      expect(snapshot.accessEventId, _accessEventId);
      expect(snapshot.summary, same(summary));
      expect(snapshot.report.projectId, _projectId);
      expect(snapshot.report.periods.reportingTimeZone, 'UTC');
      expect(snapshot.report.periods.previousPeriod.startUtc, _previousStart);
      expect(snapshot.report.periods.currentPeriod.untilUtc, _currentUntil);
      expect(snapshot.report.periodResults, hasLength(2));

      final previous = snapshot.report.periodResults.first;
      expect(previous.periodKey, FollowUpConsentRatioReportPeriodKey.previous);
      expect(previous.periodOrder, 0);
      expect(
        previous.ratio.privacyStatus,
        FollowUpConsentRatioReportPrivacyStatus.displayed,
      );
      expect(previous.ratio.yesCount, 12);
      expect(previous.ratio.noCount, 18);
      expect(previous.ratio.numerator, 12);
      expect(previous.ratio.denominator, 30);
      expect(previous.ratio.percentageBasisPoints, 4000);
      expect(previous.coverage, hasLength(3));
      expect(previous.coverage[0].consentState, 'unanswered');
      expect(previous.coverage[0].valueCount, 10);
      expect(
        previous.coverage[1].privacyStatus,
        FollowUpConsentRatioReportPrivacyStatus.suppressed,
      );
      expect(previous.coverage[1].valueCount, isNull);

      final current = snapshot.report.periodResults[1];
      expect(
        current.ratio.privacyStatus,
        FollowUpConsentRatioReportPrivacyStatus.suppressed,
      );
      expect(current.ratio.yesCount, isNull);
      expect(current.ratio.noCount, isNull);
      expect(current.ratio.numerator, isNull);
      expect(current.ratio.denominator, isNull);
      expect(current.ratio.percentageBasisPoints, isNull);
      expect(current.coverage.every((cell) => cell.valueCount == null), isTrue);
      expect(
        () => snapshot.report.periodResults.add(previous),
        throwsUnsupportedError,
      );
      expect(
        () => previous.coverage.add(previous.coverage.first),
        throwsUnsupportedError,
      );
    },
  );

  test('detail accepts complete local weeks across a DST transition', () async {
    final report = _snapshotBody['report']! as Map<String, Object?>;
    final cutoff = DateTime.utc(2026, 3, 10, 12);
    final summary = FollowUpConsentRatioReportSnapshotSummary(
      snapshotId: _snapshotId,
      reportId: _reportId,
      reportVersion: 1,
      reportingTimeZone: 'America/Chicago',
      dataCutoffUtc: cutoff,
      releasedAtUtc: DateTime.utc(2026, 3, 10, 12, 1),
    );
    final gateway = _gatewayForBody({
      ..._snapshotBody,
      'report': {
        ...report,
        'periods': {
          'period_boundary_id': 'iso_week_monday_v1',
          'reporting_time_zone': 'America/Chicago',
          'data_cutoff_utc': '2026-03-10T12:00:00.000Z',
          'previous_period': {
            'start_utc': '2026-02-23T06:00:00.000Z',
            'until_utc': '2026-03-02T06:00:00.000Z',
          },
          'current_period': {
            'start_utc': '2026-03-02T06:00:00.000Z',
            'until_utc': '2026-03-09T05:00:00.000Z',
          },
        },
      },
    });

    final result = await gateway.readSnapshot(
      projectId: _projectId,
      summary: summary,
    );

    expect(
      result,
      isA<
        FollowUpConsentRatioReportSuccess<FollowUpConsentRatioReportSnapshot>
      >(),
    );
    final snapshot =
        (result
                as FollowUpConsentRatioReportSuccess<
                  FollowUpConsentRatioReportSnapshot
                >)
            .value;
    expect(snapshot.report.periods.reportingTimeZone, 'America/Chicago');
    expect(
      snapshot.report.periods.currentPeriod.untilUtc,
      DateTime.utc(2026, 3, 9, 5),
    );
    await gateway.close();
  });

  test('local request validation precedes identity and HTTP', () async {
    final identity = _signedInIdentity();
    var requestCount = 0;
    final gateway = HttpFollowUpConsentRatioReportGateway(
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
      FollowUpConsentRatioReportFailureCode.invalidRequest,
    );
    expect(
      _code(
        await gateway.readSnapshot(
          projectId: 'not-a-uuid',
          summary: _summary(),
        ),
      ),
      FollowUpConsentRatioReportFailureCode.invalidRequest,
    );
    expect(
      _code(
        await gateway.readSnapshot(
          projectId: _projectId,
          summary: FollowUpConsentRatioReportSnapshotSummary(
            snapshotId: 'NOT-A-UUID',
            reportId: _reportId,
            reportVersion: 1,
            reportingTimeZone: 'UTC',
            dataCutoffUtc: _cutoff,
            releasedAtUtc: _released,
          ),
        ),
      ),
      FollowUpConsentRatioReportFailureCode.invalidRequest,
    );
    expect(
      _code(
        await gateway.readSnapshot(
          projectId: _projectId,
          summary: FollowUpConsentRatioReportSnapshotSummary(
            snapshotId: _snapshotId,
            reportId: 'wrong-report',
            reportVersion: 1,
            reportingTimeZone: 'UTC',
            dataCutoffUtc: _cutoff,
            releasedAtUtc: _released,
          ),
        ),
      ),
      FollowUpConsentRatioReportFailureCode.invalidRequest,
    );
    expect(identity.accessTokenForceRefreshValues, isEmpty);
    expect(requestCount, 0);
  });

  test('401 refreshes once and never loops', () async {
    var requestCount = 0;
    final identity = _signedInIdentity();
    final gateway = HttpFollowUpConsentRatioReportGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: identity,
      client: MockClient((request) async {
        requestCount += 1;
        expect(request.headers['authorization'], contains('Bearer '));
        return requestCount == 1
            ? http.Response('', 401)
            : _jsonResponse(_directoryBody);
      }),
    );
    addTearDown(gateway.close);

    final result = await gateway.listSnapshots(_projectId);

    expect(result, isA<FollowUpConsentRatioReportSuccess<Object?>>());
    expect(requestCount, 2);
    expect(identity.accessTokenForceRefreshValues, [false, true]);

    var repeatedRequestCount = 0;
    final repeatedIdentity = _signedInIdentity();
    final repeatedGateway = HttpFollowUpConsentRatioReportGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: repeatedIdentity,
      client: MockClient((request) async {
        repeatedRequestCount += 1;
        return http.Response('', 401);
      }),
    );
    addTearDown(repeatedGateway.close);
    expect(
      _code(await repeatedGateway.listSnapshots(_projectId)),
      FollowUpConsentRatioReportFailureCode.unauthorized,
    );
    expect(repeatedRequestCount, 2);
    expect(repeatedIdentity.accessTokenForceRefreshValues, [false, true]);
  });

  test(
    'maps HTTP, identity, and network failures without response details',
    () async {
      for (final entry in <(int, FollowUpConsentRatioReportFailureCode)>[
        (400, FollowUpConsentRatioReportFailureCode.invalidRequest),
        (401, FollowUpConsentRatioReportFailureCode.unauthorized),
        (403, FollowUpConsentRatioReportFailureCode.forbidden),
        (404, FollowUpConsentRatioReportFailureCode.notFound),
        (409, FollowUpConsentRatioReportFailureCode.untrusted),
        (503, FollowUpConsentRatioReportFailureCode.serviceUnavailable),
        (500, FollowUpConsentRatioReportFailureCode.serverRejected),
      ]) {
        final gateway = HttpFollowUpConsentRatioReportGateway(
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
      final identityGateway = HttpFollowUpConsentRatioReportGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: identityFailure,
        client: MockClient((request) async => _jsonResponse(_directoryBody)),
      );
      expect(
        _code(await identityGateway.listSnapshots(_projectId)),
        FollowUpConsentRatioReportFailureCode.networkUnavailable,
      );
      await identityGateway.close();

      final notConfiguredIdentity = _signedInIdentity()
        ..rejectNextAccessTokenWith = const IdentityFailure(
          code: IdentityFailureCode.notConfigured,
        );
      final notConfiguredGateway = HttpFollowUpConsentRatioReportGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: notConfiguredIdentity,
        client: MockClient((request) async => _jsonResponse(_directoryBody)),
      );
      expect(
        _code(await notConfiguredGateway.listSnapshots(_projectId)),
        FollowUpConsentRatioReportFailureCode.notConfigured,
      );
      await notConfiguredGateway.close();

      final networkGateway = HttpFollowUpConsentRatioReportGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: _signedInIdentity(),
        client: MockClient((request) async {
          throw http.ClientException('offline', request.url);
        }),
      );
      expect(
        _code(await networkGateway.listSnapshots(_projectId)),
        FollowUpConsentRatioReportFailureCode.networkUnavailable,
      );
      await networkGateway.close();
    },
  );

  test('HTTP timeout maps to networkUnavailable', () async {
    final pending = Completer<http.Response>();
    final gateway = HttpFollowUpConsentRatioReportGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: _signedInIdentity(),
      client: MockClient((request) => pending.future),
      timeout: const Duration(milliseconds: 1),
    );
    expect(
      _code(await gateway.listSnapshots(_projectId)),
      FollowUpConsentRatioReportFailureCode.networkUnavailable,
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
      final gateway = HttpFollowUpConsentRatioReportGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: _signedInIdentity(),
        client: MockClient(
          (request) async =>
              http.Response(jsonEncode(_directoryBody), 200, headers: headers),
        ),
      );
      expect(
        _code(await gateway.listSnapshots(_projectId)),
        FollowUpConsentRatioReportFailureCode.invalidResponse,
      );
      await gateway.close();
    }
  });

  test('close is idempotent and blocks later requests', () async {
    final identity = _signedInIdentity();
    var requestCount = 0;
    final gateway = HttpFollowUpConsentRatioReportGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: identity,
      client: MockClient((request) async {
        requestCount += 1;
        return _jsonResponse(_directoryBody);
      }),
    );

    await gateway.close();
    await gateway.close();
    expect(
      _code(await gateway.listSnapshots(_projectId)),
      FollowUpConsentRatioReportFailureCode.closed,
    );
    expect(identity.accessTokenForceRefreshValues, isEmpty);
    expect(requestCount, 0);
  });

  test('close rejects an in-flight request without refreshing a 401', () async {
    final identity = _signedInIdentity();
    final requestStarted = Completer<void>();
    final pendingResponse = Completer<http.Response>();
    final gateway = HttpFollowUpConsentRatioReportGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: identity,
      client: MockClient((request) {
        requestStarted.complete();
        return pendingResponse.future;
      }),
    );

    final resultFuture = gateway.listSnapshots(_projectId);
    await requestStarted.future;
    await gateway.close();
    pendingResponse.complete(http.Response('', 401));

    expect(
      _code(await resultFuture),
      FollowUpConsentRatioReportFailureCode.closed,
    );
    expect(identity.accessTokenForceRefreshValues, [false]);
  });

  test(
    'strict directory parser rejects bindings, ordering, and unsafe shape',
    () async {
      final invalidDirectories = <Map<String, Object?>>[
        {..._directoryBody, 'unexpected': true},
        {..._directoryBody, 'access_event_id': 'not-a-uuid'},
        {..._directoryBody, 'project_id': _secondProjectId},
        {..._directoryBody, 'snapshots': 'not-a-list'},
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
            ...(_directoryBody['snapshots']! as List<Object?>),
            ...List<Object?>.generate(19, (index) {
              final day = (20 - index).toString().padLeft(2, '0');
              return {
                'snapshot_id':
                    'aaaaaaaa-${(index + 1).toString().padLeft(4, '0')}'
                    '-4000-8000-000000000000',
                'report_id': _reportId,
                'report_version': 1,
                'reporting_time_zone': 'UTC',
                'data_cutoff_utc': '2026-07-${day}T00:00:00.000Z',
                'released_at_utc': '2026-07-${day}T00:01:00.000Z',
              };
            }),
          ],
        },
        {
          ..._directoryBody,
          'snapshots': [
            {
              ...((_directoryBody['snapshots']! as List<Object?>).first
                  as Map<String, Object?>),
              'snapshot_id': 'NOT-A-UUID',
            },
          ],
        },
        {
          ..._directoryBody,
          'snapshots': [
            {
              ...((_directoryBody['snapshots']! as List<Object?>).first
                  as Map<String, Object?>),
              'report_id': 'other-report',
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
              'reporting_time_zone': 'Not/AZone',
            },
          ],
        },
        {
          ..._directoryBody,
          'snapshots': [
            {
              ...((_directoryBody['snapshots']! as List<Object?>).first
                  as Map<String, Object?>),
              'data_cutoff_utc': '2026-08-10T00:00:00Z',
            },
          ],
        },
        {
          ..._directoryBody,
          'snapshots': [
            {
              ...((_directoryBody['snapshots']! as List<Object?>).first
                  as Map<String, Object?>),
              'released_at_utc': '2026-08-09T23:59:59.000Z',
            },
          ],
        },
      ];
      for (final body in invalidDirectories) {
        final gateway = _gatewayForBody(body);
        expect(
          _code(await gateway.listSnapshots(_projectId)),
          FollowUpConsentRatioReportFailureCode.invalidResponse,
        );
        await gateway.close();
      }
    },
  );

  test(
    'strict report parser rejects protocol, period, arithmetic, and privacy drift',
    () async {
      final invalidReports = <Map<String, Object?>>[
        {..._snapshotBody, 'unexpected': true},
        {..._snapshotBody, 'access_event_id': 'not-a-uuid'},
        {..._snapshotBody, 'snapshot_id': _olderSnapshotId},
        {
          ..._snapshotBody,
          'report': {
            ...(_snapshotBody['report']! as Map<String, Object?>),
            'extra': true,
          },
        },
        {
          ..._snapshotBody,
          'report': {
            ...(_snapshotBody['report']! as Map<String, Object?>),
            'contract_id': 'wrong-contract',
          },
        },
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
            'metric_id': 'other-metric',
          },
        },
        {
          ..._snapshotBody,
          'report': {
            ...(_snapshotBody['report']! as Map<String, Object?>),
            'status': 'pending',
          },
        },
        {
          ..._snapshotBody,
          'report': {
            ...(_snapshotBody['report']! as Map<String, Object?>),
            'periods': {
              ...((_snapshotBody['report']! as Map<String, Object?>)['periods']!
                  as Map<String, Object?>),
              'data_cutoff_utc': '2026-08-09T00:00:00.000Z',
            },
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
                'until_utc': '2026-08-11T00:00:00.000Z',
              },
            },
          },
        },
        {
          ..._snapshotBody,
          'report': {
            ...(_snapshotBody['report']! as Map<String, Object?>),
            'periods': {
              ...((_snapshotBody['report']! as Map<String, Object?>)['periods']!
                  as Map<String, Object?>),
              'previous_period': {
                'start_utc': '2026-07-28T00:00:00.000Z',
                'until_utc': '2026-08-04T00:00:00.000Z',
              },
            },
          },
        },
        {
          ..._snapshotBody,
          'report': {
            ...(_snapshotBody['report']! as Map<String, Object?>),
            'periods': {
              ...((_snapshotBody['report']! as Map<String, Object?>)['periods']!
                  as Map<String, Object?>),
              'period_boundary_id': 'other-boundary',
            },
          },
        },
        {
          ..._snapshotBody,
          'report': {
            ...(_snapshotBody['report']! as Map<String, Object?>),
            'period_results': const <Object?>[],
          },
        },
        _withPeriodResult((period) => {...period, 'period_order': 1}),
        _withPeriodResult((period) => {...period, 'period_key': 'current'}),
        _withPeriodResult((period) => {...period, 'unknown_count': 1}),
        _withPeriodResult((period) => {...period, 'excluded_count': 1}),
        _withPeriodResult(
          (period) => {
            ...period,
            'ratio': {
              ...(period['ratio']! as Map<String, Object?>),
              'privacy_status': 'unknown',
            },
          },
        ),
        _withPeriodResult(
          (period) => {
            ...period,
            'ratio': {
              ...(period['ratio']! as Map<String, Object?>),
              'yes_count': null,
            },
          },
        ),
        _withPeriodResult(
          (period) => {
            ...period,
            'ratio': {
              ...(period['ratio']! as Map<String, Object?>),
              'no_count': 9,
            },
          },
        ),
        _withPeriodResult(
          (period) => {
            ...period,
            'ratio': {
              ...(period['ratio']! as Map<String, Object?>),
              'numerator': 13,
            },
          },
        ),
        _withPeriodResult(
          (period) => {
            ...period,
            'ratio': {
              ...(period['ratio']! as Map<String, Object?>),
              'denominator': 31,
            },
          },
        ),
        _withPeriodResult(
          (period) => {
            ...period,
            'ratio': {
              ...(period['ratio']! as Map<String, Object?>),
              'percentage_basis_points': 4001,
            },
          },
        ),
        _withPeriodResult(
          (period) => {
            ...period,
            'ratio': {
              ...(period['ratio']! as Map<String, Object?>),
              'yes_count': _maximumSafeInteger + 1,
            },
          },
        ),
        _withPeriodResult(
          (period) => {...period, 'coverage': const <Object?>[]},
        ),
        _withPeriodResult((period) {
          final coverage = (period['coverage']! as List<Object?>).toList(
            growable: true,
          );
          coverage[0] = {
            ...(coverage[0]! as Map<String, Object?>),
            'cell_order': 2,
          };
          return {...period, 'coverage': coverage};
        }),
        _withPeriodResult((period) {
          final coverage = (period['coverage']! as List<Object?>).toList(
            growable: true,
          );
          coverage[0] = {
            ...(coverage[0]! as Map<String, Object?>),
            'consent_state': 'refused',
          };
          return {...period, 'coverage': coverage};
        }),
        _withPeriodResult((period) {
          final coverage = (period['coverage']! as List<Object?>).toList(
            growable: true,
          );
          coverage[1] = {
            ...(coverage[1]! as Map<String, Object?>),
            'value_count': 10,
          };
          return {...period, 'coverage': coverage};
        }),
        _withPeriodResult((period) {
          final coverage = (period['coverage']! as List<Object?>).toList(
            growable: true,
          );
          coverage[0] = {
            ...(coverage[0]! as Map<String, Object?>),
            'value_count': 9,
            'privacy_status': 'displayed',
          };
          return {...period, 'coverage': coverage};
        }),
        _withPeriodResult((period) {
          final coverage = (period['coverage']! as List<Object?>).toList(
            growable: true,
          );
          coverage[0] = {
            ...(coverage[0]! as Map<String, Object?>),
            'email': 'person@example.test',
          };
          return {...period, 'coverage': coverage};
        }),
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
          FollowUpConsentRatioReportFailureCode.invalidResponse,
        );
        await gateway.close();
      }
    },
  );

  test('base URI validation rejects insecure or ambiguous endpoints', () {
    for (final uri in <Uri>[
      Uri.parse('http://backend.example.test'),
      Uri.parse('https://backend.example.test/path?query=value'),
      Uri.parse('https://user:password@backend.example.test'),
      Uri.parse('https://backend.example.test/#fragment'),
    ]) {
      expect(
        () => HttpFollowUpConsentRatioReportGateway(
          baseUri: uri,
          identitySession: _signedInIdentity(),
          client: MockClient((request) async => _jsonResponse(_directoryBody)),
        ),
        throwsFormatException,
      );
    }
    expect(
      HttpFollowUpConsentRatioReportGateway(
        baseUri: Uri.parse('http://127.0.0.1:54321'),
        identitySession: _signedInIdentity(),
        client: MockClient((request) async => _jsonResponse(_directoryBody)),
      ),
      isA<HttpFollowUpConsentRatioReportGateway>(),
    );
  });
}

const _projectId = '88888888-8888-4888-8888-888888888888';
const _secondProjectId = '99999999-9999-4999-8999-999999999999';
const _snapshotId = '77777777-7777-4777-8777-777777777777';
const _olderSnapshotId = '66666666-6666-4666-8666-666666666666';
const _accessEventId = '55555555-5555-4555-8555-555555555555';
const _reportId = 'contact_target_follow_up_consent_ratio_two_periods';
final _cutoff = DateTime.utc(2026, 8, 10);
final _released = DateTime.utc(2026, 8, 10, 0, 1);
final _previousStart = DateTime.utc(2026, 7, 27);
final _currentUntil = DateTime.utc(2026, 8, 10);
const _maximumSafeInteger = 9007199254740991;

final _directoryBody = <String, Object?>{
  'access_event_id': _accessEventId,
  'project_id': _projectId,
  'snapshots': [
    {
      'snapshot_id': _snapshotId,
      'report_id': _reportId,
      'report_version': 1,
      'reporting_time_zone': 'UTC',
      'data_cutoff_utc': '2026-08-10T00:00:00.000Z',
      'released_at_utc': '2026-08-10T00:01:00.000Z',
    },
    {
      'snapshot_id': _olderSnapshotId,
      'report_id': _reportId,
      'report_version': 1,
      'reporting_time_zone': 'UTC',
      'data_cutoff_utc': '2026-08-03T00:00:00.000Z',
      'released_at_utc': '2026-08-03T00:01:00.000Z',
    },
  ],
};

final _snapshotBody = <String, Object?>{
  'access_event_id': _accessEventId,
  'snapshot_id': _snapshotId,
  'report': {
    'contract_id': 'management_follow_up_consent_ratio_candidate_v1',
    'report_id': _reportId,
    'report_version': 1,
    'metric_id': 'follow_up_consent_ratio',
    'metric_version': 1,
    'statistical_unit': 'contact_target_link',
    'dimension': 'consent_state',
    'period_grain': 'week',
    'comparison_period_count': 2,
    'period_boundary_id': 'iso_week_monday_v1',
    'privacy_policy': 'management_follow_up_consent_ratio_privacy_v1',
    'query_fingerprint':
        'management-report:contact_target_follow_up_consent_ratio_two_periods:v1',
    'source_scope':
        'backend_accepted_active_contact_target_links_current_revision',
    'project_id': _projectId,
    'status': 'completed',
    'periods': {
      'period_boundary_id': 'iso_week_monday_v1',
      'reporting_time_zone': 'UTC',
      'data_cutoff_utc': '2026-08-10T00:00:00.000Z',
      'previous_period': {
        'start_utc': '2026-07-27T00:00:00.000Z',
        'until_utc': '2026-08-03T00:00:00.000Z',
      },
      'current_period': {
        'start_utc': '2026-08-03T00:00:00.000Z',
        'until_utc': '2026-08-10T00:00:00.000Z',
      },
    },
    'period_results': [
      {
        'period_key': 'previous',
        'period_order': 0,
        'ratio': {
          'privacy_status': 'displayed',
          'yes_count': 12,
          'no_count': 18,
          'numerator': 12,
          'denominator': 30,
          'percentage_basis_points': 4000,
        },
        'coverage': [
          {
            'consent_state': 'unanswered',
            'cell_order': 0,
            'value_count': 10,
            'privacy_status': 'displayed',
          },
          {
            'consent_state': 'refused',
            'cell_order': 1,
            'value_count': null,
            'privacy_status': 'suppressed',
          },
          {
            'consent_state': 'not_applicable',
            'cell_order': 2,
            'value_count': 11,
            'privacy_status': 'displayed',
          },
        ],
        'unknown_count': 0,
        'excluded_count': 0,
      },
      {
        'period_key': 'current',
        'period_order': 1,
        'ratio': {
          'privacy_status': 'suppressed',
          'yes_count': null,
          'no_count': null,
          'numerator': null,
          'denominator': null,
          'percentage_basis_points': null,
        },
        'coverage': [
          {
            'consent_state': 'unanswered',
            'cell_order': 3,
            'value_count': null,
            'privacy_status': 'suppressed',
          },
          {
            'consent_state': 'refused',
            'cell_order': 4,
            'value_count': null,
            'privacy_status': 'suppressed',
          },
          {
            'consent_state': 'not_applicable',
            'cell_order': 5,
            'value_count': null,
            'privacy_status': 'suppressed',
          },
        ],
        'unknown_count': 0,
        'excluded_count': 0,
      },
    ],
  },
};

FakeIdentitySession _signedInIdentity() => FakeIdentitySession(
  initial: IdentitySnapshot(
    stage: IdentityStage.signedIn,
    principal: const IdentityPrincipal(
      externalSubject: 'test-subject',
      email: 'test@example.test',
    ),
  ),
);

FollowUpConsentRatioReportSnapshotSummary _summary() =>
    FollowUpConsentRatioReportSnapshotSummary(
      snapshotId: _snapshotId,
      reportId: _reportId,
      reportVersion: 1,
      reportingTimeZone: 'UTC',
      dataCutoffUtc: _cutoff,
      releasedAtUtc: _released,
    );

http.Response _jsonResponse(Object body, {Map<String, String>? headers}) =>
    http.Response(
      jsonEncode(body),
      200,
      headers:
          headers ??
          const {
            'content-type': 'application/json; charset=utf-8',
            'cache-control': 'no-store',
          },
    );

HttpFollowUpConsentRatioReportGateway _gatewayForBody(
  Map<String, Object?> body,
) => HttpFollowUpConsentRatioReportGateway(
  baseUri: Uri.parse('https://backend.example.test'),
  identitySession: _signedInIdentity(),
  client: MockClient((request) async => _jsonResponse(body)),
);

Map<String, Object?> _withPeriodResult(
  Map<String, Object?> Function(Map<String, Object?> period) transform,
) {
  final report = _snapshotBody['report']! as Map<String, Object?>;
  final periodResults = List<Object?>.from(
    report['period_results']! as List<Object?>,
  );
  periodResults[0] = transform((periodResults[0]! as Map<String, Object?>));
  return {
    ..._snapshotBody,
    'report': {...report, 'period_results': periodResults},
  };
}

FollowUpConsentRatioReportFailureCode _code(
  FollowUpConsentRatioReportResult<Object?> result,
) => (result as FollowUpConsentRatioReportRejected<Object?>).code;
