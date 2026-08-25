import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:timezone/data/latest_all.dart' as time_zone_data;
import 'package:timezone/timezone.dart' as time_zone;

import '../identity/identity_session.dart';
import 'original_region_report_gateway.dart';

const _backendBaseUrl = String.fromEnvironment('BACKEND_BASE_URL');

/// 从构建配置取得 Backend 地址；未配置时显式降级，不访问网络。
OriginalRegionReportGateway productionOriginalRegionReportGateway(
  IdentitySession identitySession,
) {
  final configured = _backendBaseUrl.trim();
  if (configured.isEmpty) return const DeferredOriginalRegionReportGateway();
  return HttpOriginalRegionReportGateway(
    baseUri: Uri.parse(configured),
    identitySession: identitySession,
    client: http.Client(),
  );
}

/// original-region 目录和显式 detail 的独立 HTTP typed gateway。
///
/// 这个 adapter 只发送固定 GET 请求；它不计算报告、不选择“最新”快照，也不
/// 把响应写入任何本地持久化或缓存边界。
final class HttpOriginalRegionReportGateway
    implements OriginalRegionReportGateway {
  factory HttpOriginalRegionReportGateway({
    required Uri baseUri,
    required IdentitySession identitySession,
    required http.Client client,
    Duration timeout = const Duration(seconds: 15),
  }) => HttpOriginalRegionReportGateway._(
    baseUri: _validatedBaseUri(baseUri),
    identitySession: identitySession,
    client: client,
    timeout: timeout,
  );

  const HttpOriginalRegionReportGateway._({
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
  Future<OriginalRegionReportResult<OriginalRegionReportSnapshotDirectory>>
  listSnapshots(String projectId) {
    try {
      _canonicalUuid(projectId);
    } on FormatException {
      return Future.value(
        const OriginalRegionReportRejected(
          OriginalRegionReportFailureCode.invalidRequest,
        ),
      );
    }
    return _request(
      send: (token) => _client.get(
        _baseUri.resolve(
          '/v1/projects/${Uri.encodeComponent(projectId)}'
          '/management-original-region-report-snapshots',
        ),
        headers: _headers(token),
      ),
      parse: (root) => _parseDirectory(root, projectId),
    );
  }

  @override
  Future<OriginalRegionReportResult<OriginalRegionReportSnapshot>>
  readSnapshot({
    required String projectId,
    required OriginalRegionReportSnapshotSummary summary,
  }) {
    try {
      _canonicalUuid(projectId);
      _validateSummaryForRequest(summary);
    } on FormatException {
      return Future.value(
        const OriginalRegionReportRejected(
          OriginalRegionReportFailureCode.invalidRequest,
        ),
      );
    }
    return _request(
      send: (token) => _client.get(
        _baseUri.resolve(
          '/v1/projects/${Uri.encodeComponent(projectId)}'
          '/management-original-region-report-snapshots/'
          '${Uri.encodeComponent(summary.snapshotId)}',
        ),
        headers: _headers(token),
      ),
      parse: (root) => _parseSnapshot(root, projectId, summary),
    );
  }

  Future<OriginalRegionReportResult<T>> _request<T>({
    required Future<http.Response> Function(String token) send,
    required T Function(Map<String, Object?> root) parse,
  }) async {
    try {
      var access = await _identitySession.accessToken();
      if (access is! IdentitySuccess<IdentityAccessToken>) {
        return OriginalRegionReportRejected(_identityFailure(access));
      }

      var response = await send(access.value.value).timeout(_timeout);
      if (response.statusCode == 401) {
        access = await _identitySession.accessToken(forceRefresh: true);
        if (access is! IdentitySuccess<IdentityAccessToken>) {
          return OriginalRegionReportRejected(_identityFailure(access));
        }
        response = await send(access.value.value).timeout(_timeout);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return OriginalRegionReportRejected(_httpFailure(response.statusCode));
      }
      _requireJsonNoStore(response);
      return OriginalRegionReportSuccess(parse(_jsonObject(response.body)));
    } on TimeoutException {
      return const OriginalRegionReportRejected(
        OriginalRegionReportFailureCode.networkUnavailable,
      );
    } on http.ClientException {
      return const OriginalRegionReportRejected(
        OriginalRegionReportFailureCode.networkUnavailable,
      );
    } on FormatException {
      return const OriginalRegionReportRejected(
        OriginalRegionReportFailureCode.invalidResponse,
      );
    } on StateError {
      return const OriginalRegionReportRejected(
        OriginalRegionReportFailureCode.invalidResponse,
      );
    } on Object {
      // Adapter 边界不把 provider、HTTP client 或内部异常交给调用方。
      return const OriginalRegionReportRejected(
        OriginalRegionReportFailureCode.invalidResponse,
      );
    }
  }

  @override
  Future<void> close() async => _client.close();
}

OriginalRegionReportSnapshotDirectory _parseDirectory(
  Map<String, Object?> root,
  String requestedProjectId,
) {
  _requireExactKeys(root, const ['access_event_id', 'project_id', 'snapshots']);
  final accessEventId = _canonicalUuid(root['access_event_id']);
  final projectId = _canonicalUuid(root['project_id']);
  if (projectId != requestedProjectId) {
    throw const FormatException('original-region directory project is invalid');
  }

  final values = _list(root['snapshots']);
  if (values.length > 20) {
    throw const FormatException('original-region directory is not bounded');
  }
  final snapshots = values.map(_parseSummary).toList();
  final seen = <String>{};
  for (var index = 0; index < snapshots.length; index++) {
    final snapshot = snapshots[index];
    if (!seen.add(snapshot.snapshotId)) {
      throw const FormatException('original-region directory has duplicates');
    }
    if (index > 0 && _compareSummaries(snapshots[index - 1], snapshot) <= 0) {
      throw const FormatException('original-region directory order is invalid');
    }
  }
  return OriginalRegionReportSnapshotDirectory(
    accessEventId: accessEventId,
    projectId: projectId,
    snapshots: snapshots,
  );
}

OriginalRegionReportSnapshotSummary _parseSummary(Object? value) {
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
    throw const FormatException('original-region report identity is invalid');
  }
  final reportingTimeZone = _ianaTimeZone(root['reporting_time_zone']);
  final dataCutoffUtc = _canonicalUtcTimestamp(root['data_cutoff_utc']);
  final releasedAtUtc = _canonicalUtcTimestamp(root['released_at_utc']);
  if (releasedAtUtc.isBefore(dataCutoffUtc)) {
    throw const FormatException('original-region release precedes cutoff');
  }
  return OriginalRegionReportSnapshotSummary(
    snapshotId: _canonicalUuid(root['snapshot_id']),
    reportId: reportId,
    reportVersion: reportVersion as int,
    reportingTimeZone: reportingTimeZone,
    dataCutoffUtc: dataCutoffUtc,
    releasedAtUtc: releasedAtUtc,
  );
}

int _compareSummaries(
  OriginalRegionReportSnapshotSummary left,
  OriginalRegionReportSnapshotSummary right,
) {
  final cutoff = left.dataCutoffUtc.compareTo(right.dataCutoffUtc);
  if (cutoff != 0) return cutoff;
  final released = left.releasedAtUtc.compareTo(right.releasedAtUtc);
  if (released != 0) return released;
  return left.snapshotId.compareTo(right.snapshotId);
}

OriginalRegionReportSnapshot _parseSnapshot(
  Map<String, Object?> root,
  String requestedProjectId,
  OriginalRegionReportSnapshotSummary summary,
) {
  _requireExactKeys(root, const ['access_event_id', 'snapshot_id', 'report']);
  final accessEventId = _canonicalUuid(root['access_event_id']);
  final snapshotId = _canonicalUuid(root['snapshot_id']);
  if (snapshotId != summary.snapshotId) {
    throw const FormatException('original-region snapshot ID is inconsistent');
  }
  return OriginalRegionReportSnapshot(
    accessEventId: accessEventId,
    summary: summary,
    report: _parseReport(root['report'], requestedProjectId, summary),
  );
}

OriginalRegionReportDocument _parseReport(
  Object? value,
  String requestedProjectId,
  OriginalRegionReportSnapshotSummary summary,
) {
  final root = _object(value);
  _requireExactKeys(root, const [
    'report_id',
    'report_version',
    'metric_id',
    'metric_version',
    'dimension',
    'view_mode',
    'region_granularity',
    'query_fingerprint',
    'privacy_policy',
    'source_scope',
    'project_id',
    'periods',
    'data_cutoff_utc',
    'source_change_sequence',
    'source_tree_context',
    'result_status',
    'cells',
  ]);

  final reportId = _nonEmptyString(root['report_id']);
  final reportVersion = root['report_version'];
  final metricId = _nonEmptyString(root['metric_id']);
  final metricVersion = root['metric_version'];
  final dimension = _nonEmptyString(root['dimension']);
  final viewMode = _nonEmptyString(root['view_mode']);
  final regionGranularity = _nonEmptyString(root['region_granularity']);
  final queryFingerprint = _nonEmptyString(root['query_fingerprint']);
  final privacyPolicy = _nonEmptyString(root['privacy_policy']);
  final sourceScope = _nonEmptyString(root['source_scope']);
  final projectId = _canonicalUuid(root['project_id']);
  final dataCutoffUtc = _canonicalUtcTimestamp(root['data_cutoff_utc']);
  final sourceChangeSequence = root['source_change_sequence'];
  final sourceTreeContext = _parseSourceTreeContext(
    root['source_tree_context'],
  );
  final resultStatus = _nonEmptyString(root['result_status']);

  if (reportId != _fixedReportId ||
      reportVersion != _fixedReportVersion ||
      metricId != _fixedMetricId ||
      metricVersion != _fixedMetricVersion ||
      dimension != _fixedDimension ||
      viewMode != _fixedViewMode ||
      regionGranularity != _fixedRegionGranularity ||
      queryFingerprint != _fixedQueryFingerprint ||
      privacyPolicy != _fixedPrivacyPolicy ||
      sourceScope != _fixedSourceScope ||
      projectId != requestedProjectId ||
      dataCutoffUtc != summary.dataCutoffUtc ||
      reportId != summary.reportId ||
      reportVersion != summary.reportVersion ||
      resultStatus != _fixedResultStatus ||
      !_isNonNegativeSafeInteger(sourceChangeSequence)) {
    throw const FormatException('original-region report metadata is invalid');
  }

  final periods = _parsePeriods(root['periods'], dataCutoffUtc, summary);
  final cells = _parseCells(root['cells']);
  _assertNoSensitiveFacts(root);
  return OriginalRegionReportDocument(
    reportId: reportId,
    reportVersion: reportVersion as int,
    metricId: metricId,
    metricVersion: metricVersion as int,
    dimension: dimension,
    viewMode: viewMode,
    regionGranularity: regionGranularity,
    queryFingerprint: queryFingerprint,
    privacyPolicy: privacyPolicy,
    sourceScope: sourceScope,
    projectId: projectId,
    periods: periods,
    dataCutoffUtc: dataCutoffUtc,
    sourceChangeSequence: sourceChangeSequence as int,
    sourceTreeContext: sourceTreeContext,
    resultStatus: resultStatus,
    cells: cells,
  );
}

OriginalRegionReportPeriods _parsePeriods(
  Object? value,
  DateTime dataCutoffUtc,
  OriginalRegionReportSnapshotSummary summary,
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
  final periodCutoffUtc = _canonicalUtcTimestamp(root['data_cutoff_utc']);
  if (periodBoundaryId != _fixedPeriodBoundaryId ||
      reportingTimeZone != summary.reportingTimeZone ||
      periodCutoffUtc != dataCutoffUtc ||
      periodCutoffUtc != summary.dataCutoffUtc) {
    throw const FormatException('original-region period context is invalid');
  }

  final previous = _parsePeriod(root['previous_period']);
  final current = _parsePeriod(root['current_period']);
  if (previous.untilUtc != current.startUtc ||
      current.untilUtc.isAfter(dataCutoffUtc)) {
    throw const FormatException('original-region periods are not adjacent');
  }
  return OriginalRegionReportPeriods(
    periodBoundaryId: periodBoundaryId,
    reportingTimeZone: reportingTimeZone,
    dataCutoffUtc: periodCutoffUtc,
    previousPeriod: previous,
    currentPeriod: current,
  );
}

OriginalRegionReportPeriod _parsePeriod(Object? value) {
  final root = _object(value);
  _requireExactKeys(root, const ['start_utc', 'until_utc']);
  final startUtc = _canonicalUtcTimestamp(root['start_utc']);
  final untilUtc = _canonicalUtcTimestamp(root['until_utc']);
  if (!startUtc.isBefore(untilUtc)) {
    throw const FormatException('original-region period is empty');
  }
  return OriginalRegionReportPeriod(startUtc: startUtc, untilUtc: untilUtc);
}

OriginalRegionReportSourceTreeContext _parseSourceTreeContext(Object? value) {
  final root = _object(value);
  _requireExactKeys(root, const [
    'source_tree_context_contract_id',
    'result_status',
    'reason_code',
    'source_tree_version',
    'source_content_fingerprint',
  ]);
  final contractId = _nonEmptyString(root['source_tree_context_contract_id']);
  final resultStatus = _nonEmptyString(root['result_status']);
  final reasonCode = _nonEmptyString(root['reason_code']);
  final sourceTreeVersion = _nonEmptyString(root['source_tree_version']);
  final sourceContentFingerprint = _nonEmptyString(
    root['source_content_fingerprint'],
  );
  if (contractId != _sourceTreeContextContractId ||
      resultStatus != _sourceTreeResultStatus ||
      reasonCode != _sourceTreeReasonCode ||
      sourceTreeVersion.length > 200 ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(sourceContentFingerprint)) {
    throw const FormatException(
      'original-region source tree context is invalid',
    );
  }
  return OriginalRegionReportSourceTreeContext(
    contractId: contractId,
    resultStatus: resultStatus,
    reasonCode: reasonCode,
    sourceTreeVersion: sourceTreeVersion,
    sourceContentFingerprint: sourceContentFingerprint,
  );
}

List<OriginalRegionReportCell> _parseCells(Object? value) {
  final values = _list(value);
  if (values.isEmpty || values.length.isOdd) {
    throw const FormatException('original-region grid size is invalid');
  }
  final cityCount = values.length ~/ 2;

  final cells = <OriginalRegionReportCell>[];
  final previousCities = <String>[];
  final currentCities = <String>[];
  for (var index = 0; index < values.length; index++) {
    final root = _object(values[index]);
    _requireExactKeys(root, const [
      'period_key',
      'city_id',
      'cell_order',
      'value_count',
      'privacy_status',
    ]);
    final periodKey = switch (_nonEmptyString(root['period_key'])) {
      'previous' => OriginalRegionReportPeriodKey.previous,
      'current' => OriginalRegionReportPeriodKey.current,
      _ => throw const FormatException('original-region period key is invalid'),
    };
    final expectedPeriod = index < cityCount
        ? OriginalRegionReportPeriodKey.previous
        : OriginalRegionReportPeriodKey.current;
    if (root['cell_order'] != index || periodKey != expectedPeriod) {
      throw const FormatException('original-region cell coordinate is invalid');
    }
    final cityId = _nonEmptyString(root['city_id']);
    if (cityId.length > 120) {
      throw const FormatException('original-region city ID is invalid');
    }
    final privacyStatus = switch (_nonEmptyString(root['privacy_status'])) {
      'displayed' => OriginalRegionReportPrivacyStatus.displayed,
      'suppressed' => OriginalRegionReportPrivacyStatus.suppressed,
      _ => throw const FormatException(
        'original-region privacy status is invalid',
      ),
    };
    final rawCount = root['value_count'];
    final valueCount = switch (privacyStatus) {
      OriginalRegionReportPrivacyStatus.suppressed =>
        rawCount == null
            ? null
            : (throw const FormatException(
                'suppressed original-region cell exposed a value',
              )),
      OriginalRegionReportPrivacyStatus.displayed => _displayedCount(rawCount),
    };
    if (index < cityCount) {
      if (previousCities.isNotEmpty &&
          previousCities.last.compareTo(cityId) >= 0) {
        throw const FormatException('original-region grid is not sorted');
      }
      previousCities.add(cityId);
    } else {
      if (currentCities.isNotEmpty &&
          currentCities.last.compareTo(cityId) >= 0) {
        throw const FormatException('original-region grid is not sorted');
      }
      currentCities.add(cityId);
    }
    cells.add(
      OriginalRegionReportCell(
        periodKey: periodKey,
        cityId: cityId,
        cellOrder: index,
        valueCount: valueCount,
        privacyStatus: privacyStatus,
      ),
    );
  }
  if (previousCities.length != currentCities.length ||
      previousCities.asMap().entries.any(
        (entry) => entry.value != currentCities[entry.key],
      )) {
    throw const FormatException('original-region grid periods do not pair');
  }
  return List.unmodifiable(cells);
}

int _displayedCount(Object? value) {
  if (!_isNonNegativeSafeInteger(value) || (value as int) < 10) {
    throw const FormatException(
      'displayed original-region cell count is invalid',
    );
  }
  return value;
}

void _validateSummaryForRequest(OriginalRegionReportSnapshotSummary summary) {
  if (_canonicalUuid(summary.snapshotId) != summary.snapshotId ||
      summary.reportId != _fixedReportId ||
      summary.reportVersion != _fixedReportVersion ||
      _ianaTimeZone(summary.reportingTimeZone) != summary.reportingTimeZone ||
      !_isCanonicalDateTime(summary.dataCutoffUtc) ||
      !_isCanonicalDateTime(summary.releasedAtUtc) ||
      summary.releasedAtUtc.isBefore(summary.dataCutoffUtc)) {
    throw const FormatException('original-region summary is invalid');
  }
}

bool _isCanonicalDateTime(DateTime value) =>
    value.isUtc && _canonicalUtcPattern.hasMatch(value.toIso8601String());

String _requiredHeader(http.Response response, String name) {
  for (final entry in response.headers.entries) {
    if (entry.key.toLowerCase() == name) return entry.value;
  }
  throw const FormatException('original-region response header is missing');
}

void _requireJsonNoStore(http.Response response) {
  final contentType = _requiredHeader(response, 'content-type');
  final mediaType = contentType.split(';').first.trim().toLowerCase();
  final cacheControl = _requiredHeader(response, 'cache-control').trim();
  if (mediaType != 'application/json' || cacheControl != 'no-store') {
    throw const FormatException('original-region response headers are invalid');
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
      throw const FormatException(
        'original-region report contains sensitive facts',
      );
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

OriginalRegionReportFailureCode _identityFailure(
  IdentityResult<IdentityAccessToken> result,
) {
  if (result case IdentityRejected<IdentityAccessToken>(:final failure)) {
    return failure.code == IdentityFailureCode.networkUnavailable
        ? OriginalRegionReportFailureCode.networkUnavailable
        : OriginalRegionReportFailureCode.unauthorized;
  }
  return OriginalRegionReportFailureCode.unauthorized;
}

OriginalRegionReportFailureCode _httpFailure(int status) => switch (status) {
  400 => OriginalRegionReportFailureCode.invalidRequest,
  401 => OriginalRegionReportFailureCode.unauthorized,
  403 => OriginalRegionReportFailureCode.forbidden,
  404 => OriginalRegionReportFailureCode.notFound,
  409 => OriginalRegionReportFailureCode.untrusted,
  503 => OriginalRegionReportFailureCode.serviceUnavailable,
  _ => OriginalRegionReportFailureCode.serverRejected,
};

Uri _validatedBaseUri(Uri value) {
  if (!value.hasScheme || value.host.isEmpty) {
    throw const FormatException('Backend URL must be absolute');
  }
  final localHttp =
      value.scheme == 'http' &&
      const {'localhost', '127.0.0.1', '::1'}.contains(value.host);
  if (value.scheme != 'https' && !localHttp) {
    throw const FormatException(
      'Backend URL must use HTTPS except on localhost',
    );
  }
  if (value.userInfo.isNotEmpty || value.hasQuery || value.hasFragment) {
    throw const FormatException('Backend URL contains unsupported components');
  }
  return value;
}

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final _canonicalUtcPattern = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
);
final _timeZonePattern = RegExp(r'^[A-Za-z0-9._+/-]+$');
var _timeZonesInitialized = false;

const _fixedReportId = 'contact_sessions_by_original_region_two_periods';
const _fixedReportVersion = 1;
const _fixedMetricId = 'contact_sessions';
const _fixedMetricVersion = 1;
const _fixedDimension = 'original_region';
const _fixedViewMode = 'original';
const _fixedRegionGranularity = 'city';
const _fixedQueryFingerprint =
    'management-report:contact_sessions_by_original_region_two_periods:v1';
const _fixedPrivacyPolicy =
    'management_original_region_contact_session_privacy_v1';
const _fixedSourceScope =
    'backend_accepted_active_contacts_original_current_revision';
const _fixedPeriodBoundaryId = 'iso_week_monday_v1';
const _fixedResultStatus = 'completed';
const _sourceTreeContextContractId =
    'management-original-region-source-tree:v1';
const _sourceTreeResultStatus = 'selected';
const _sourceTreeReasonCode = 'single_original_source_tree';
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
  'location_source',
  'location_kind',
  'source',
  'source_id',
  'revision',
  'revision_id',
  'canonical_name',
  'city_name',
  'region_name',
  'boundary',
  'geometry',
  'coordinates',
  'smallest_region_id',
  'region_tree_version',
  'region_tree_content_fingerprint',
  'accuracy_meters',
  'resolver_contract_version',
  'organization_membership_id',
  'project_membership_id',
  'capability_grant_id',
};
