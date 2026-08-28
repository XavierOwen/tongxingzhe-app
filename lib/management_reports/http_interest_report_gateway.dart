import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:timezone/data/latest_all.dart' as time_zone_data;
import 'package:timezone/timezone.dart' as time_zone;

import '../foundation/backend_base_uri.dart';
import '../identity/identity_session.dart';
import 'interest_report_gateway.dart';

const _backendBaseUrl = String.fromEnvironment('BACKEND_BASE_URL');

/// 从构建配置取得 Backend 地址；未配置时显式降级，不访问网络。
InterestReportGateway productionInterestReportGateway(
  IdentitySession identitySession,
) {
  final configured = _backendBaseUrl.trim();
  if (configured.isEmpty) return const DeferredInterestReportGateway();
  return HttpInterestReportGateway(
    baseUri: Uri.parse(configured),
    identitySession: identitySession,
    client: http.Client(),
  );
}

/// interest 目录和显式 detail 的独立 HTTP typed gateway。
///
/// 这个 adapter 只发送固定 GET 请求；它不计算报告、不选择“最新”快照，也不
/// 把响应写入任何本地持久化或缓存边界。
final class HttpInterestReportGateway implements InterestReportGateway {
  factory HttpInterestReportGateway({
    required Uri baseUri,
    required IdentitySession identitySession,
    required http.Client client,
    Duration timeout = const Duration(seconds: 15),
  }) => HttpInterestReportGateway._(
    baseUri: validateManagementReportBaseUri(baseUri),
    identitySession: identitySession,
    client: client,
    timeout: timeout,
  );

  const HttpInterestReportGateway._({
    required this._baseUri,
    required this._identitySession,
    required this._client,
    required this._timeout,
  });

  final Uri _baseUri;
  final IdentitySession _identitySession;
  final http.Client _client;
  final Duration _timeout;

  @override
  Future<InterestReportResult<InterestReportSnapshotDirectory>> listSnapshots(
    String projectId,
  ) {
    try {
      _canonicalUuid(projectId);
    } on FormatException {
      return Future.value(
        const InterestReportRejected(InterestReportFailureCode.invalidRequest),
      );
    }
    return _request(
      send: (token) => _client.get(
        _baseUri.resolve(
          '/v1/projects/${Uri.encodeComponent(projectId)}'
          '/management-interest-report-snapshots',
        ),
        headers: _headers(token),
      ),
      parse: (root) => _parseDirectory(root, projectId),
    );
  }

  @override
  Future<InterestReportResult<InterestReportSnapshot>> readSnapshot({
    required String projectId,
    required InterestReportSnapshotSummary summary,
  }) {
    try {
      _canonicalUuid(projectId);
      _validateSummaryForRequest(summary);
    } on FormatException {
      return Future.value(
        const InterestReportRejected(InterestReportFailureCode.invalidRequest),
      );
    }
    return _request(
      send: (token) => _client.get(
        _baseUri.resolve(
          '/v1/projects/${Uri.encodeComponent(projectId)}'
          '/management-interest-report-snapshots/'
          '${Uri.encodeComponent(summary.snapshotId)}',
        ),
        headers: _headers(token),
      ),
      parse: (root) => _parseSnapshot(root, projectId, summary),
    );
  }

  Future<InterestReportResult<T>> _request<T>({
    required Future<http.Response> Function(String token) send,
    required T Function(Map<String, Object?> root) parse,
  }) async {
    try {
      var access = await _identitySession.accessToken();
      if (access is! IdentitySuccess<IdentityAccessToken>) {
        return InterestReportRejected(_identityFailure(access));
      }

      var response = await send(access.value.value).timeout(_timeout);
      if (response.statusCode == 401) {
        access = await _identitySession.accessToken(forceRefresh: true);
        if (access is! IdentitySuccess<IdentityAccessToken>) {
          return InterestReportRejected(_identityFailure(access));
        }
        response = await send(access.value.value).timeout(_timeout);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return InterestReportRejected(_httpFailure(response.statusCode));
      }
      _requireJsonNoStore(response);
      return InterestReportSuccess(parse(_jsonObject(response.body)));
    } on TimeoutException {
      return const InterestReportRejected(
        InterestReportFailureCode.networkUnavailable,
      );
    } on http.ClientException {
      return const InterestReportRejected(
        InterestReportFailureCode.networkUnavailable,
      );
    } on FormatException {
      return const InterestReportRejected(
        InterestReportFailureCode.invalidResponse,
      );
    } on StateError {
      return const InterestReportRejected(
        InterestReportFailureCode.invalidResponse,
      );
    } on Object {
      // Adapter 边界不把 provider、HTTP client 或内部异常交给调用方。
      return const InterestReportRejected(
        InterestReportFailureCode.invalidResponse,
      );
    }
  }

  @override
  Future<void> close() async => _client.close();
}

InterestReportSnapshotDirectory _parseDirectory(
  Map<String, Object?> root,
  String requestedProjectId,
) {
  _requireExactKeys(root, const ['access_event_id', 'project_id', 'snapshots']);
  final accessEventId = _canonicalUuid(root['access_event_id']);
  final projectId = _canonicalUuid(root['project_id']);
  if (projectId != requestedProjectId) {
    throw const FormatException('interest directory project is invalid');
  }

  final values = _list(root['snapshots']);
  if (values.length > 20) {
    throw const FormatException('interest directory is not bounded');
  }
  final snapshots = values.map(_parseSummary).toList();
  final seen = <String>{};
  for (var index = 0; index < snapshots.length; index++) {
    final snapshot = snapshots[index];
    if (!seen.add(snapshot.snapshotId)) {
      throw const FormatException('interest directory has duplicates');
    }
    if (index > 0 && _compareSummaries(snapshots[index - 1], snapshot) <= 0) {
      throw const FormatException('interest directory order is invalid');
    }
  }
  return InterestReportSnapshotDirectory(
    accessEventId: accessEventId,
    projectId: projectId,
    snapshots: snapshots,
  );
}

InterestReportSnapshotSummary _parseSummary(Object? value) {
  final root = _object(value);
  _requireExactKeys(root, const [
    'snapshot_id',
    'report_id',
    'report_version',
    'reporting_time_zone',
    'data_cutoff_utc',
    'released_at_utc',
  ]);
  final reportId = _nonEmptyString(root['report_id']);
  final reportVersion = root['report_version'];
  if (reportId != _fixedReportId || reportVersion != _fixedReportVersion) {
    throw const FormatException('interest report identity is invalid');
  }
  final reportingTimeZone = _ianaTimeZone(root['reporting_time_zone']);
  final dataCutoffUtc = _canonicalUtcTimestamp(root['data_cutoff_utc']);
  final releasedAtUtc = _canonicalUtcTimestamp(root['released_at_utc']);
  if (releasedAtUtc.isBefore(dataCutoffUtc)) {
    throw const FormatException('interest release precedes cutoff');
  }
  return InterestReportSnapshotSummary(
    snapshotId: _canonicalUuid(root['snapshot_id']),
    reportId: reportId,
    reportVersion: reportVersion as int,
    reportingTimeZone: reportingTimeZone,
    dataCutoffUtc: dataCutoffUtc,
    releasedAtUtc: releasedAtUtc,
  );
}

int _compareSummaries(
  InterestReportSnapshotSummary left,
  InterestReportSnapshotSummary right,
) {
  final cutoff = left.dataCutoffUtc.compareTo(right.dataCutoffUtc);
  if (cutoff != 0) return cutoff;
  final released = left.releasedAtUtc.compareTo(right.releasedAtUtc);
  if (released != 0) return released;
  return left.snapshotId.compareTo(right.snapshotId);
}

InterestReportSnapshot _parseSnapshot(
  Map<String, Object?> root,
  String requestedProjectId,
  InterestReportSnapshotSummary summary,
) {
  _requireExactKeys(root, const ['access_event_id', 'snapshot_id', 'report']);
  final accessEventId = _canonicalUuid(root['access_event_id']);
  final snapshotId = _canonicalUuid(root['snapshot_id']);
  if (snapshotId != summary.snapshotId) {
    throw const FormatException('interest snapshot ID is inconsistent');
  }
  return InterestReportSnapshot(
    accessEventId: accessEventId,
    summary: summary,
    report: _parseReport(root['report'], requestedProjectId, summary),
  );
}

InterestReportDocument _parseReport(
  Object? value,
  String requestedProjectId,
  InterestReportSnapshotSummary summary,
) {
  final root = _object(value);
  _requireExactKeys(root, const [
    'report_id',
    'report_version',
    'metric_id',
    'metric_version',
    'statistical_unit',
    'dimension',
    'query_fingerprint',
    'privacy_policy',
    'source_scope',
    'project_id',
    'periods',
    'cells',
  ]);

  final reportId = _nonEmptyString(root['report_id']);
  final reportVersion = root['report_version'];
  final metricId = _nonEmptyString(root['metric_id']);
  final metricVersion = root['metric_version'];
  final statisticalUnit = _nonEmptyString(root['statistical_unit']);
  final dimension = _nonEmptyString(root['dimension']);
  final queryFingerprint = _nonEmptyString(root['query_fingerprint']);
  final privacyPolicy = _nonEmptyString(root['privacy_policy']);
  final sourceScope = _nonEmptyString(root['source_scope']);
  final projectId = _canonicalUuid(root['project_id']);

  if (reportId != _fixedReportId ||
      reportVersion != _fixedReportVersion ||
      metricId != _fixedMetricId ||
      metricVersion != _fixedMetricVersion ||
      statisticalUnit != _fixedStatisticalUnit ||
      dimension != _fixedDimension ||
      queryFingerprint != _fixedQueryFingerprint ||
      privacyPolicy != _fixedPrivacyPolicy ||
      sourceScope != _fixedSourceScope ||
      projectId != requestedProjectId ||
      reportId != summary.reportId ||
      reportVersion != summary.reportVersion) {
    throw const FormatException('interest report metadata is invalid');
  }

  final periods = _parsePeriods(root['periods'], summary);
  final cells = _parseCells(root['cells']);
  _assertNoSensitiveFacts(root);
  return InterestReportDocument(
    reportId: reportId,
    reportVersion: reportVersion as int,
    metricId: metricId,
    metricVersion: metricVersion as int,
    statisticalUnit: statisticalUnit,
    dimension: dimension,
    queryFingerprint: queryFingerprint,
    privacyPolicy: privacyPolicy,
    sourceScope: sourceScope,
    projectId: projectId,
    periods: periods,
    cells: cells,
  );
}

InterestReportPeriods _parsePeriods(
  Object? value,
  InterestReportSnapshotSummary summary,
) {
  final root = _object(value);
  _requireExactKeys(root, const [
    'period_boundary_id',
    'reporting_time_zone',
    'data_cutoff_utc',
    'previous_period',
    'current_period',
  ]);
  final periodBoundaryId = _nonEmptyString(root['period_boundary_id']);
  final reportingTimeZone = _ianaTimeZone(root['reporting_time_zone']);
  final dataCutoffUtc = _canonicalUtcTimestamp(root['data_cutoff_utc']);
  if (periodBoundaryId != _fixedPeriodBoundaryId ||
      reportingTimeZone != summary.reportingTimeZone ||
      dataCutoffUtc != summary.dataCutoffUtc) {
    throw const FormatException('interest period context is invalid');
  }

  final previous = _parsePeriod(root['previous_period']);
  final current = _parsePeriod(root['current_period']);
  if (previous.untilUtc != current.startUtc ||
      current.untilUtc.isAfter(dataCutoffUtc)) {
    throw const FormatException('interest periods are not adjacent');
  }
  return InterestReportPeriods(
    periodBoundaryId: periodBoundaryId,
    reportingTimeZone: reportingTimeZone,
    dataCutoffUtc: dataCutoffUtc,
    previousPeriod: previous,
    currentPeriod: current,
  );
}

InterestReportPeriod _parsePeriod(Object? value) {
  final root = _object(value);
  _requireExactKeys(root, const ['start_utc', 'until_utc']);
  final startUtc = _canonicalUtcTimestamp(root['start_utc']);
  final untilUtc = _canonicalUtcTimestamp(root['until_utc']);
  if (!startUtc.isBefore(untilUtc)) {
    throw const FormatException('interest period is empty');
  }
  return InterestReportPeriod(startUtc: startUtc, untilUtc: untilUtc);
}

List<InterestReportCell> _parseCells(Object? value) {
  final values = _list(value);
  if (values.length != 10) {
    throw const FormatException('interest grid size is invalid');
  }

  final privacyByPeriod =
      <InterestReportPeriodKey, InterestReportPrivacyStatus>{};
  final cells = <InterestReportCell>[];
  for (var index = 0; index < values.length; index++) {
    final root = _object(values[index]);
    _requireExactKeys(root, const [
      'period_key',
      'interest_level',
      'cell_order',
      'value_count',
      'privacy_status',
    ]);

    final periodKey = switch (_nonEmptyString(root['period_key'])) {
      'previous' => InterestReportPeriodKey.previous,
      'current' => InterestReportPeriodKey.current,
      _ => throw const FormatException('interest period key is invalid'),
    };
    final expectedPeriod = index < 5
        ? InterestReportPeriodKey.previous
        : InterestReportPeriodKey.current;
    final expectedInterestLevel = index % 5;
    final interestLevel = root['interest_level'];
    if (periodKey != expectedPeriod ||
        interestLevel != expectedInterestLevel ||
        root['cell_order'] != index) {
      throw const FormatException('interest cell coordinate is invalid');
    }

    final privacyStatus = switch (_nonEmptyString(root['privacy_status'])) {
      'displayed' => InterestReportPrivacyStatus.displayed,
      'suppressed' => InterestReportPrivacyStatus.suppressed,
      _ => throw const FormatException('interest privacy status is invalid'),
    };
    final rawCount = root['value_count'];
    final valueCount = switch (privacyStatus) {
      InterestReportPrivacyStatus.suppressed =>
        rawCount == null
            ? null
            : (throw const FormatException(
                'suppressed interest cell exposed a value',
              )),
      InterestReportPrivacyStatus.displayed => _displayedCount(rawCount),
    };
    final previousStatus = privacyByPeriod[periodKey];
    if (previousStatus != null && previousStatus != privacyStatus) {
      throw const FormatException('interest period privacy is inconsistent');
    }
    privacyByPeriod[periodKey] = privacyStatus;
    cells.add(
      InterestReportCell(
        periodKey: periodKey,
        interestLevel: interestLevel as int,
        cellOrder: root['cell_order'] as int,
        valueCount: valueCount,
        privacyStatus: privacyStatus,
      ),
    );
  }
  return List.unmodifiable(cells);
}

int _displayedCount(Object? value) {
  if (!_isNonNegativeSafeInteger(value) || (value as int) < 10) {
    throw const FormatException('displayed interest cell count is invalid');
  }
  return value;
}

void _validateSummaryForRequest(InterestReportSnapshotSummary summary) {
  if (_canonicalUuid(summary.snapshotId) != summary.snapshotId ||
      summary.reportId != _fixedReportId ||
      summary.reportVersion != _fixedReportVersion ||
      _ianaTimeZone(summary.reportingTimeZone) != summary.reportingTimeZone ||
      !_isCanonicalDateTime(summary.dataCutoffUtc) ||
      !_isCanonicalDateTime(summary.releasedAtUtc) ||
      summary.releasedAtUtc.isBefore(summary.dataCutoffUtc)) {
    throw const FormatException('interest summary is invalid');
  }
}

bool _isCanonicalDateTime(DateTime value) =>
    value.isUtc && _canonicalUtcPattern.hasMatch(value.toIso8601String());

String _requiredHeader(http.Response response, String name) {
  for (final entry in response.headers.entries) {
    if (entry.key.toLowerCase() == name) return entry.value;
  }
  throw const FormatException('interest response header is missing');
}

void _requireJsonNoStore(http.Response response) {
  final contentType = _requiredHeader(response, 'content-type');
  final mediaType = contentType.split(';').first.trim().toLowerCase();
  final cacheControl = _requiredHeader(response, 'cache-control').trim();
  if (mediaType != 'application/json' || cacheControl != 'no-store') {
    throw const FormatException('interest response headers are invalid');
  }
}

Map<String, Object?> _jsonObject(String body) => _object(jsonDecode(body));

Map<String, Object?> _object(Object? value) {
  if (value is! Map) throw const FormatException('expected JSON object');
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw const FormatException('JSON object key is invalid');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

List<Object?> _list(Object? value) {
  if (value is! List) throw const FormatException('expected JSON list');
  return List<Object?>.of(value);
}

String _nonEmptyString(Object? value) {
  if (value is! String || value.isEmpty || value.trim() != value) {
    throw const FormatException('expected canonical non-empty string');
  }
  return value;
}

bool _isNonNegativeSafeInteger(Object? value) =>
    value is int && value >= 0 && value <= _maximumSafeJsonInteger;

String _canonicalUuid(Object? value) {
  final text = _nonEmptyString(value);
  if (!_uuidPattern.hasMatch(text) || text.toLowerCase() != text) {
    throw const FormatException('expected canonical UUID');
  }
  return text;
}

DateTime _canonicalUtcTimestamp(Object? value) {
  if (value is! String || !_canonicalUtcPattern.hasMatch(value)) {
    throw const FormatException('expected canonical UTC timestamp');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc || parsed.toIso8601String() != value) {
    throw const FormatException('canonical UTC timestamp is invalid');
  }
  return parsed;
}

String _ianaTimeZone(Object? value) {
  final name = _nonEmptyString(value);
  if (!_timeZonePattern.hasMatch(name)) {
    throw const FormatException('IANA time zone is invalid');
  }
  if (!_timeZonesInitialized) {
    time_zone_data.initializeTimeZones();
    _timeZonesInitialized = true;
  }
  try {
    time_zone.getLocation(name);
  } on time_zone.LocationNotFoundException {
    throw const FormatException('IANA time zone is unknown');
  }
  return name;
}

void _assertNoSensitiveFacts(Object? value) {
  if (value is List) {
    for (final item in value) {
      _assertNoSensitiveFacts(item);
    }
    return;
  }
  if (value is! Map) return;
  for (final entry in value.entries) {
    if (entry.key is String && _sensitiveFactKeys.contains(entry.key)) {
      throw const FormatException('interest report contains sensitive facts');
    }
    _assertNoSensitiveFacts(entry.value);
  }
}

void _requireExactKeys(Map<String, Object?> value, List<String> expected) {
  final actual = value.keys.toSet();
  final expectedSet = expected.toSet();
  if (actual.length != expectedSet.length || actual.length != value.length) {
    throw const FormatException('JSON object keys are invalid');
  }
  if (!actual.containsAll(expectedSet)) {
    throw const FormatException('JSON object keys are invalid');
  }
}

Map<String, String> _headers(String token) => {
  'accept': 'application/json',
  'authorization': 'Bearer $token',
};

InterestReportFailureCode _identityFailure(
  IdentityResult<IdentityAccessToken> result,
) {
  if (result case IdentityRejected<IdentityAccessToken>(:final failure)) {
    return failure.code == IdentityFailureCode.networkUnavailable
        ? InterestReportFailureCode.networkUnavailable
        : InterestReportFailureCode.unauthorized;
  }
  return InterestReportFailureCode.unauthorized;
}

InterestReportFailureCode _httpFailure(int status) => switch (status) {
  400 => InterestReportFailureCode.invalidRequest,
  401 => InterestReportFailureCode.unauthorized,
  403 => InterestReportFailureCode.forbidden,
  404 => InterestReportFailureCode.notFound,
  409 => InterestReportFailureCode.untrusted,
  503 => InterestReportFailureCode.serviceUnavailable,
  _ => InterestReportFailureCode.serverRejected,
};

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final _canonicalUtcPattern = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
);
final _timeZonePattern = RegExp(r'^[A-Za-z0-9._+/-]+$');
var _timeZonesInitialized = false;

const _fixedReportId = 'contact_sessions_by_interest_level_two_periods';
const _fixedReportVersion = 1;
const _fixedMetricId = 'interest_distribution';
const _fixedMetricVersion = 1;
const _fixedStatisticalUnit = 'contact_session';
const _fixedDimension = 'interest_level';
const _fixedQueryFingerprint =
    'management-report:contact_sessions_by_interest_level_two_periods:v1';
const _fixedPrivacyPolicy = 'management_interest_distribution_privacy_v1';
const _fixedSourceScope = 'backend_accepted_active_contacts_current_revision';
const _fixedPeriodBoundaryId = 'iso_week_monday_v1';
const _maximumSafeJsonInteger = 9007199254740991;

const _sensitiveFactKeys = <String>{
  'app_user',
  'app_user_id',
  'contact',
  'contact_id',
  'contributor',
  'contributor_id',
  'contributor_key',
  'email',
  'phone',
  'place_name',
  'latitude',
  'longitude',
  'location',
  'source_id',
  'revision_id',
  'organization_membership_id',
  'project_membership_id',
  'capability_grant_id',
};
