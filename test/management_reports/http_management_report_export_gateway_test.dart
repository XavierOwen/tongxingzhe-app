import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/management_reports/http_management_report_gateway.dart';
import 'package:tongxingzhe_app/management_reports/management_report_gateway.dart';

import '../support/fake_identity_session.dart';

void main() {
  test(
    '6AI GET export sends only project/snapshot path, accept, and bearer',
    () async {
      final identity = _signedInIdentity();
      final rawBytes = _canonicalExportBytes();
      final gateway = HttpManagementReportGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: identity,
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(
            request.url.path,
            '/v1/projects/$_projectId/'
            'management-report-snapshots/$_snapshotId/export',
          );
          expect(request.url.query, isEmpty);
          expect(request.body, isEmpty);
          expect(request.headers['accept'], 'application/json');
          expect(
            request.headers['authorization'],
            'Bearer test-only-access-token',
          );
          expect(request.headers.containsKey('content-type'), isFalse);
          return _exportResponse(bytes: rawBytes);
        }),
      );
      addTearDown(gateway.close);

      final result = await gateway.exportSnapshot(
        projectId: _projectId,
        summary: _summary(),
      );

      final artifact = _successValue(result);
      expect(artifact.bytes, orderedEquals(rawBytes));
      expect(artifact.fileName, 'management-report-snapshot-v1.json');
      expect(artifact.contentType, 'application/json; charset=utf-8');
      expect(artifact.exportEventId, _exportEventId);
      expect(artifact.bytes, isNot(same(rawBytes)));
      expect(() => artifact.bytes.add(0), throwsUnsupportedError);
      expect(identity.accessTokenForceRefreshValues, [false]);
    },
  );

  test(
    '6AI artifact preserves canonical bytes and full snapshot identity',
    () async {
      final rawBytes = _canonicalExportBytes();
      final responses = <int>[];
      final gateway = HttpManagementReportGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: _signedInIdentity(),
        client: MockClient((request) async {
          responses.add(1);
          return _exportResponse(bytes: rawBytes);
        }),
      );
      addTearDown(gateway.close);

      final first = _successValue(
        await gateway.exportSnapshot(
          projectId: _projectId,
          summary: _summary(),
        ),
      );
      final second = _successValue(
        await gateway.exportSnapshot(
          projectId: _projectId,
          summary: _summary(),
        ),
      );

      expect(responses, hasLength(2));
      expect(first.bytes, orderedEquals(rawBytes));
      expect(second.bytes, orderedEquals(rawBytes));
      expect(second.bytes, orderedEquals(first.bytes));

      final snapshot = first.snapshot;
      expect(snapshot.summary.snapshotId, _snapshotId);
      expect(snapshot.summary.reportId, _reportId);
      expect(snapshot.summary.reportVersion, 1);
      expect(snapshot.summary.reportingTimeZone, 'America/Chicago');
      expect(snapshot.summary.dataCutoffUtc, DateTime.utc(2030, 3, 11, 5));
      expect(snapshot.summary.releasedAtUtc, DateTime.utc(2030, 3, 11, 5, 1));

      final report = snapshot.report;
      expect(report.projectId, _projectId);
      expect(report.reportId, _reportId);
      expect(report.reportVersion, 1);
      expect(report.metricId, 'contact_sessions');
      expect(report.metricVersion, 1);
      expect(report.dimension, 'channel');
      expect(
        report.queryFingerprint,
        'management-report:contact_sessions_by_channel_two_periods:v1',
      );
      expect(report.privacyPolicy, 'management_contact_session_privacy_v1');
      expect(report.sourceScope, 'backend_accepted_contacts');
      expect(report.periodBoundaryId, 'iso_week_monday_v1');
      expect(report.reportingTimeZone, 'America/Chicago');
      expect(report.dataCutoffUtc, DateTime.utc(2030, 3, 11, 5));
      expect(report.previousPeriod.startUtc, DateTime.utc(2030, 2, 25, 6));
      expect(report.previousPeriod.untilUtc, DateTime.utc(2030, 3, 4, 6));
      expect(report.currentPeriod.startUtc, DateTime.utc(2030, 3, 4, 6));
      expect(report.currentPeriod.untilUtc, DateTime.utc(2030, 3, 11, 5));

      expect(report.cells, hasLength(16));
      expect(report.cells[0].periodKey, ManagementReportPeriodKey.previous);
      expect(report.cells[0].categoryKey, 'all');
      expect(report.cells[0].cellOrder, 0);
      expect(report.cells[0].valueCount, 10);
      expect(
        report.cells[0].privacyStatus,
        ManagementReportPrivacyStatus.displayed,
      );
      expect(report.cells[1].valueCount, isNull);
      expect(
        report.cells[1].privacyStatus,
        ManagementReportPrivacyStatus.suppressed,
      );
      expect(report.cells[2].categoryKey, 'voice_call');
      expect(report.cells[2].valueCount, 12);
      expect(report.cells[2].cellOrder, 2);
      expect(report.cells[8].periodKey, ManagementReportPeriodKey.current);
      expect(report.cells[8].categoryKey, 'all');
      expect(report.cells[8].valueCount, 10);
      expect(report.cells[10].categoryKey, 'voice_call');
      expect(report.cells[10].valueCount, 12);
    },
  );

  test(
    '6AI refreshes a 401 once and retries the same export request',
    () async {
      var requestCount = 0;
      final identity = _signedInIdentity();
      final gateway = HttpManagementReportGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: identity,
        client: MockClient((request) async {
          requestCount += 1;
          expect(request.method, 'GET');
          expect(request.url.query, isEmpty);
          return requestCount == 1 ? http.Response('', 401) : _exportResponse();
        }),
      );
      addTearDown(gateway.close);

      final result = await gateway.exportSnapshot(
        projectId: _projectId,
        summary: _summary(),
      );

      expect(
        result,
        isA<ManagementReportSuccess<ManagementReportExportArtifact>>(),
      );
      expect(requestCount, 2);
      expect(identity.accessTokenForceRefreshValues, [false, true]);
    },
  );

  test('6AI stops after the second 401 without a third request', () async {
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

    final result = await gateway.exportSnapshot(
      projectId: _projectId,
      summary: _summary(),
    );

    expect(_rejectedCode(result), ManagementReportFailureCode.unauthorized);
    expect(requestCount, 2);
    expect(identity.accessTokenForceRefreshValues, [false, true]);
  });

  test(
    '6AI maps authorization, provenance, server, and network failures',
    () async {
      for (final entry in <(int, ManagementReportFailureCode)>[
        (403, ManagementReportFailureCode.unauthorized),
        (404, ManagementReportFailureCode.notFound),
        (409, ManagementReportFailureCode.untrusted),
        (500, ManagementReportFailureCode.serverRejected),
        (503, ManagementReportFailureCode.serverRejected),
      ]) {
        final gateway = HttpManagementReportGateway(
          baseUri: Uri.parse('https://backend.example.test'),
          identitySession: _signedInIdentity(),
          client: MockClient((request) async => http.Response('', entry.$1)),
        );

        final result = await gateway.exportSnapshot(
          projectId: _projectId,
          summary: _summary(),
        );

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
      final networkResult = await networkGateway.exportSnapshot(
        projectId: _projectId,
        summary: _summary(),
      );
      expect(
        _rejectedCode(networkResult),
        ManagementReportFailureCode.networkUnavailable,
      );
      await networkGateway.close();

      final timeoutGateway = HttpManagementReportGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: _signedInIdentity(),
        timeout: const Duration(milliseconds: 1),
        client: MockClient(
          (request) => Future<http.Response>.delayed(
            const Duration(milliseconds: 20),
            _exportResponse,
          ),
        ),
      );
      final timeoutResult = await timeoutGateway.exportSnapshot(
        projectId: _projectId,
        summary: _summary(),
      );
      expect(
        _rejectedCode(timeoutResult),
        ManagementReportFailureCode.networkUnavailable,
      );
      await timeoutGateway.close();
    },
  );

  test('6AI rejects every fixed response header drift', () async {
    final variants = <(String, String?)>[
      ('content-type', null),
      ('content-type', 'application/json'),
      ('content-disposition', null),
      ('content-disposition', 'attachment; filename="other.json"'),
      ('cache-control', null),
      ('cache-control', 'public, max-age=3600'),
      ('x-content-type-options', null),
      ('x-content-type-options', 'sniff'),
      ('x-management-report-export-event-id', null),
      ('x-management-report-export-event-id', 'not-an-event-id'),
      ('content-length', null),
      ('content-length', '0'),
    ];

    for (final (name, value) in variants) {
      final headers = _exportHeaders(_canonicalExportBytes());
      if (value == null) {
        headers.remove(name);
      } else {
        headers[name] = value;
      }
      final result = await _exportWithResponse(
        _exportResponse(headers: headers),
      );
      expect(
        _rejectedCode(result),
        ManagementReportFailureCode.invalidResponse,
        reason: '$name=$value',
      );
    }
  });

  test(
    '6AI rejects a non-UTF8 body, malformed JSON, and non-canonical whitespace',
    () async {
      final canonical = _canonicalExportBytes();
      final invalidUtf8 = <int>[0x7b, 0xc3, 0x28, 0x7d];
      final whitespace = <int>[...utf8.encode(' '), ...canonical];
      final trailingWhitespace = <int>[...canonical, 0x0a];

      for (final bytes in [invalidUtf8, whitespace, trailingWhitespace]) {
        final result = await _exportWithResponse(_exportResponse(bytes: bytes));
        expect(
          _rejectedCode(result),
          ManagementReportFailureCode.invalidResponse,
        );
      }

      final malformed = await _exportWithResponse(
        _exportResponse(bytes: utf8.encode('{')),
      );
      expect(
        _rejectedCode(malformed),
        ManagementReportFailureCode.invalidResponse,
      );
    },
  );

  test('6AI rejects root and nested canonical key-order drift', () async {
    final document = _exportDocument();
    final rootReordered = <String, Object?>{
      'snapshot_id': document['snapshot_id'],
      'export_contract_id': document['export_contract_id'],
      'released_at_utc': document['released_at_utc'],
      'report': document['report'],
    };
    final report = _report(document);
    final reorderedReport = <String, Object?>{
      'report_id': report['report_id'],
      'report_version': report['report_version'],
      'metric_id': report['metric_id'],
      'metric_version': report['metric_version'],
      'dimension': report['dimension'],
      'query_fingerprint': report['query_fingerprint'],
      'privacy_policy': report['privacy_policy'],
      'source_scope': report['source_scope'],
      'project_id': report['project_id'],
      'cells': report['cells'],
      'periods': report['periods'],
    };
    final nestedReordered = <String, Object?>{
      ...document,
      'report': reorderedReport,
    };
    final periodsReordered = _exportDocument();
    final periods = _periods(periodsReordered);
    _report(periodsReordered)['periods'] = <String, Object?>{
      'reporting_time_zone': periods['reporting_time_zone'],
      'period_boundary_id': periods['period_boundary_id'],
      'data_cutoff_utc': periods['data_cutoff_utc'],
      'previous_period': periods['previous_period'],
      'current_period': periods['current_period'],
    };
    final cellReordered = _exportDocument();
    final cell = _cells(cellReordered).first as Map<String, Object?>;
    _cells(cellReordered).first = <String, Object?>{
      'category_key': cell['category_key'],
      'period_key': cell['period_key'],
      'cell_order': cell['cell_order'],
      'privacy_status': cell['privacy_status'],
      'value_count': cell['value_count'],
    };

    for (final value in [
      rootReordered,
      nestedReordered,
      periodsReordered,
      cellReordered,
    ]) {
      final result = await _exportWithResponse(
        _exportResponse(bytes: utf8.encode(jsonEncode(value))),
      );
      expect(
        _rejectedCode(result),
        ManagementReportFailureCode.invalidResponse,
      );
    }
  });

  test(
    '6AI rejects snapshot, release, report, period, and cell identity drift',
    () async {
      final wrongSnapshot = _exportDocument()
        ..['snapshot_id'] = _olderSnapshotId;
      final uppercaseSnapshot = _exportDocument()
        ..['snapshot_id'] = _snapshotId.toUpperCase();
      final wrongRelease = _exportDocument()
        ..['released_at_utc'] = '2030-03-11T05:02:00.000Z';
      final nonCanonicalRelease = _exportDocument()
        ..['released_at_utc'] = '2030-03-11T05:01:00Z';
      final wrongReportId = _exportDocument();
      _report(wrongReportId)['report_id'] = 'other_report';
      final wrongReportVersion = _exportDocument();
      _report(wrongReportVersion)['report_version'] = 2;
      final wrongProject = _exportDocument();
      _report(wrongProject)['project_id'] = _secondProjectId;
      final uppercaseProject = _exportDocument();
      _report(uppercaseProject)['project_id'] = _projectId.toUpperCase();
      final wrongTimeZone = _exportDocument();
      _periods(wrongTimeZone)['reporting_time_zone'] = 'UTC';
      final wrongCutoff = _exportDocument();
      _periods(wrongCutoff)['data_cutoff_utc'] = '2030-03-11T05:01:00.000Z';
      final wrongBoundary = _exportDocument();
      _periods(wrongBoundary)['period_boundary_id'] = 'iso_week_sunday_v1';
      final nonAdjacent = _exportDocument();
      (_periods(nonAdjacent)['current_period']!
              as Map<String, Object?>)['start_utc'] =
          '2030-03-05T06:00:00.000Z';
      final wrongCellCoordinate = _exportDocument();
      (_cells(wrongCellCoordinate)[2] as Map<String, Object?>)['category_key'] =
          'video_call';
      final wrongCellOrder = _exportDocument();
      (_cells(wrongCellOrder)[2] as Map<String, Object?>)['cell_order'] = 3;

      for (final (name, value) in <(String, Map<String, Object?>)>[
        ('wrong snapshot', wrongSnapshot),
        ('uppercase snapshot', uppercaseSnapshot),
        ('wrong release', wrongRelease),
        ('non-canonical release', nonCanonicalRelease),
        ('wrong report ID', wrongReportId),
        ('wrong report version', wrongReportVersion),
        ('wrong project', wrongProject),
        ('uppercase project', uppercaseProject),
        ('wrong time zone', wrongTimeZone),
        ('wrong cutoff', wrongCutoff),
        ('wrong period boundary', wrongBoundary),
        ('non-adjacent period', nonAdjacent),
        ('wrong cell coordinate', wrongCellCoordinate),
        ('wrong cell order', wrongCellOrder),
      ]) {
        final result = await _exportWithResponse(
          _exportResponse(document: value),
        );
        expect(
          result,
          isA<ManagementReportRejected<ManagementReportExportArtifact>>(),
          reason: name,
        );
        expect(
          _rejectedCode(result),
          ManagementReportFailureCode.invalidResponse,
          reason: name,
        );
      }
    },
  );

  test(
    '6AI enforces displayed >= 10, suppressed null, and exactly 16 cells',
    () async {
      final displayedBelowMinimum = _exportDocument();
      (_cells(displayedBelowMinimum)[0]
              as Map<String, Object?>)['value_count'] =
          9;
      final displayedNull = _exportDocument();
      (_cells(displayedNull)[0] as Map<String, Object?>)['value_count'] = null;
      final displayedUnsafe = _exportDocument();
      (_cells(displayedUnsafe)[0] as Map<String, Object?>)['value_count'] =
          9007199254740992;
      final suppressedValue = _exportDocument();
      (_cells(suppressedValue)[1] as Map<String, Object?>)['value_count'] = 0;
      final missingCell = _exportDocument();
      _cells(missingCell).removeLast();
      final extraCell = _exportDocument();
      _cells(extraCell).add(_cells(extraCell).last);

      for (final value in [
        displayedBelowMinimum,
        displayedNull,
        displayedUnsafe,
        suppressedValue,
        missingCell,
        extraCell,
      ]) {
        final result = await _exportWithResponse(
          _exportResponse(document: value),
        );
        expect(
          _rejectedCode(result),
          ManagementReportFailureCode.invalidResponse,
        );
      }
    },
  );

  test('6AI rejects extra location, PII, and export-event fields', () async {
    final extraRoot = _exportDocument()..['export_event_id'] = _exportEventId;
    final extraReport = _exportDocument();
    _report(extraReport)['organization_name'] = 'Private organization';
    final extraCell = _exportDocument();
    (_cells(extraCell).first as Map<String, Object?>)['location_name'] =
        'private place';
    final extraPii = _exportDocument();
    (_cells(extraPii).first as Map<String, Object?>)['email'] =
        'person@example.test';

    for (final value in [extraRoot, extraReport, extraCell, extraPii]) {
      final result = await _exportWithResponse(
        _exportResponse(document: value),
      );
      expect(
        _rejectedCode(result),
        ManagementReportFailureCode.invalidResponse,
      );
    }
  });

  test('deferred gateway reports export as not configured', () async {
    const gateway = DeferredManagementReportGateway();

    final result = await gateway.exportSnapshot(
      projectId: _projectId,
      summary: _summary(),
    );

    expect(_rejectedCode(result), ManagementReportFailureCode.notConfigured);
  });
}

Future<ManagementReportResult<ManagementReportExportArtifact>>
_exportWithResponse(http.Response response) async {
  final gateway = HttpManagementReportGateway(
    baseUri: Uri.parse('https://backend.example.test'),
    identitySession: _signedInIdentity(),
    client: MockClient((request) async => response),
  );
  final result = await gateway.exportSnapshot(
    projectId: _projectId,
    summary: _summary(),
  );
  await gateway.close();
  return result;
}

ManagementReportExportArtifact _successValue(
  ManagementReportResult<ManagementReportExportArtifact> result,
) => (result as ManagementReportSuccess<ManagementReportExportArtifact>).value;

ManagementReportFailureCode _rejectedCode(
  ManagementReportResult<Object?> result,
) => (result as ManagementReportRejected<Object?>).code;

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

http.Response _exportResponse({
  Map<String, Object?>? document,
  List<int>? bytes,
  int status = 200,
  Map<String, String>? headers,
}) {
  final bodyBytes =
      bytes ?? utf8.encode(jsonEncode(document ?? _exportDocument()));
  final responseHeaders = _exportHeaders(bodyBytes);
  if (headers != null) {
    responseHeaders
      ..clear()
      ..addAll(headers);
  }
  return http.Response.bytes(bodyBytes, status, headers: responseHeaders);
}

Map<String, String> _exportHeaders(List<int> bytes) => {
  'content-type': 'application/json; charset=utf-8',
  'content-disposition':
      'attachment; filename="management-report-snapshot-v1.json"',
  'cache-control': 'no-store',
  'x-content-type-options': 'nosniff',
  'x-management-report-export-event-id': _exportEventId,
  'content-length': '${bytes.length}',
};

List<int> _canonicalExportBytes() => utf8.encode(jsonEncode(_exportDocument()));

Map<String, Object?> _exportDocument() => {
  'export_contract_id': 'management_report_snapshot_export_v1',
  'snapshot_id': _snapshotId,
  'released_at_utc': '2030-03-11T05:01:00.000Z',
  'report': {
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
    'cells': _exportCells(),
  },
};

List<Object?> _exportCells() {
  const categories = [
    'all',
    'face_to_face',
    'voice_call',
    'video_call',
    'instant_text',
    'asynchronous_message',
    'mixed',
    'other_direct',
  ];
  return ['previous', 'current'].expand((periodKey) sync* {
    final periodIndex = periodKey == 'previous' ? 0 : 1;
    for (
      var categoryIndex = 0;
      categoryIndex < categories.length;
      categoryIndex++
    ) {
      final categoryKey = categories[categoryIndex];
      final displayed = categoryKey == 'all' || categoryKey == 'voice_call';
      yield <String, Object?>{
        'period_key': periodKey,
        'category_key': categoryKey,
        'cell_order': periodIndex * categories.length + categoryIndex,
        'privacy_status': displayed ? 'displayed' : 'suppressed',
        'value_count': displayed ? (categoryKey == 'all' ? 10 : 12) : null,
      };
    }
  }).toList();
}

Map<String, Object?> _report(Map<String, Object?> document) =>
    document['report']! as Map<String, Object?>;

Map<String, Object?> _periods(Map<String, Object?> document) =>
    _report(document)['periods']! as Map<String, Object?>;

List<Object?> _cells(Map<String, Object?> document) =>
    _report(document)['cells']! as List<Object?>;

ManagementReportSnapshotSummary _summary() => ManagementReportSnapshotSummary(
  snapshotId: _snapshotId,
  reportId: _reportId,
  reportVersion: 1,
  reportingTimeZone: 'America/Chicago',
  dataCutoffUtc: DateTime.utc(2030, 3, 11, 5),
  releasedAtUtc: DateTime.utc(2030, 3, 11, 5, 1),
);

const _projectId = '33333333-3333-4333-8333-3333333333ab';
const _secondProjectId = '55555555-5555-4555-8555-5555555555ab';
const _snapshotId = '88888888-8888-4888-8888-8888888888ab';
const _olderSnapshotId = '77777777-7777-4777-8777-7777777777ab';
const _reportId = 'contact_sessions_by_channel_two_periods';
const _exportEventId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
