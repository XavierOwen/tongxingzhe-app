import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:timezone/data/latest_all.dart' as time_zone_data;
import 'package:timezone/timezone.dart' as time_zone;

import '../identity/identity_session.dart';
import 'current_city_report_gateway.dart';

const _backendBaseUrl = String.fromEnvironment('BACKEND_BASE_URL');

/// 从构建配置取得 Backend 地址；未配置时显式降级，不访问网络。
CurrentCityReportGateway productionCurrentCityReportGateway(
  IdentitySession identitySession,
) {
  final configured = _backendBaseUrl.trim();
  if (configured.isEmpty) return const DeferredCurrentCityReportGateway();
  return HttpCurrentCityReportGateway(
    baseUri: Uri.parse(configured),
    identitySession: identitySession,
    client: http.Client(),
  );
}

/// current-city 目录和显式 detail 的独立 HTTP typed gateway。
///
/// 这个 adapter 只发送固定 GET 请求；它不计算报告、不选择“最新”快照，也不
/// 把响应写入任何本地持久化或缓存边界。
final class HttpCurrentCityReportGateway implements CurrentCityReportGateway {
  factory HttpCurrentCityReportGateway({
    required Uri baseUri,
    required IdentitySession identitySession,
    required http.Client client,
    Duration timeout = const Duration(seconds: 15),
  }) => HttpCurrentCityReportGateway._(
    baseUri: _validatedBaseUri(baseUri),
    identitySession: identitySession,
    client: client,
    timeout: timeout,
  );

  const HttpCurrentCityReportGateway._({
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
  Future<CurrentCityReportResult<CurrentCityReportSnapshotDirectory>>
  listSnapshots(String projectId) {
    try {
      _canonicalUuid(projectId);
    } on FormatException {
      return Future.value(
        const CurrentCityReportRejected(
          CurrentCityReportFailureCode.invalidRequest,
        ),
      );
    }
    return _request(
      send: (token) => _client.get(
        _baseUri.resolve(
          '/v1/projects/${Uri.encodeComponent(projectId)}'
          '/management-current-city-report-snapshots',
        ),
        headers: _headers(token),
      ),
      parse: (root) => _parseDirectory(root, projectId),
    );
  }

  @override
  Future<CurrentCityReportResult<CurrentCityReportSnapshot>> readSnapshot({
    required String projectId,
    required CurrentCityReportSnapshotSummary summary,
  }) {
    try {
      _canonicalUuid(projectId);
      _validateSummaryForRequest(summary);
    } on FormatException {
      return Future.value(
        const CurrentCityReportRejected(
          CurrentCityReportFailureCode.invalidRequest,
        ),
      );
    }
    return _request(
      send: (token) => _client.get(
        _baseUri.resolve(
          '/v1/projects/${Uri.encodeComponent(projectId)}'
          '/management-current-city-report-snapshots/'
          '${Uri.encodeComponent(summary.snapshotId)}',
        ),
        headers: _headers(token),
      ),
      parse: (root) => _parseSnapshot(root, projectId, summary),
    );
  }

  Future<CurrentCityReportResult<T>> _request<T>({
    required Future<http.Response> Function(String token) send,
    required T Function(Map<String, Object?> root) parse,
  }) async {
    try {
      var access = await _identitySession.accessToken();
      if (access is! IdentitySuccess<IdentityAccessToken>) {
        return CurrentCityReportRejected(_identityFailure(access));
      }

      var response = await send(access.value.value).timeout(_timeout);
      if (response.statusCode == 401) {
        access = await _identitySession.accessToken(forceRefresh: true);
        if (access is! IdentitySuccess<IdentityAccessToken>) {
          return CurrentCityReportRejected(_identityFailure(access));
        }
        response = await send(access.value.value).timeout(_timeout);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return CurrentCityReportRejected(_httpFailure(response.statusCode));
      }
      _requireJsonNoStore(response);
      return CurrentCityReportSuccess(parse(_jsonObject(response.body)));
    } on TimeoutException {
      return const CurrentCityReportRejected(
        CurrentCityReportFailureCode.networkUnavailable,
      );
    } on http.ClientException {
      return const CurrentCityReportRejected(
        CurrentCityReportFailureCode.networkUnavailable,
      );
    } on FormatException {
      return const CurrentCityReportRejected(
        CurrentCityReportFailureCode.invalidResponse,
      );
    } on StateError {
      return const CurrentCityReportRejected(
        CurrentCityReportFailureCode.invalidResponse,
      );
    } on Object {
      // Adapter 边界不把 provider、HTTP client 或内部异常交给调用方。
      return const CurrentCityReportRejected(
        CurrentCityReportFailureCode.invalidResponse,
      );
    }
  }

  @override
  Future<void> close() async => _client.close();
}

CurrentCityReportSnapshotDirectory _parseDirectory(
  Map<String, Object?> root,
  String requestedProjectId,
) {
  _requireExactKeys(root, const ['access_event_id', 'project_id', 'snapshots']);
  final accessEventId = _canonicalUuid(root['access_event_id']);
  final projectId = _canonicalUuid(root['project_id']);
  if (projectId != requestedProjectId) {
    throw const FormatException('current-city directory project is invalid');
  }

  final values = _list(root['snapshots']);
  if (values.length > 20) {
    throw const FormatException('current-city directory is not bounded');
  }
  final snapshots = values.map(_parseSummary).toList();
  final seen = <String>{};
  for (var index = 0; index < snapshots.length; index++) {
    final snapshot = snapshots[index];
    if (!seen.add(snapshot.snapshotId)) {
      throw const FormatException('current-city directory has duplicates');
    }
    if (index > 0 && _compareSummaries(snapshots[index - 1], snapshot) <= 0) {
      throw const FormatException('current-city directory order is invalid');
    }
  }
  return CurrentCityReportSnapshotDirectory(
    accessEventId: accessEventId,
    projectId: projectId,
    snapshots: snapshots,
  );
}

CurrentCityReportSnapshotSummary _parseSummary(Object? value) {
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
    throw const FormatException('current-city report identity is invalid');
  }
  final reportingTimeZone = _ianaTimeZone(root['reporting_time_zone']);
  final dataCutoffUtc = _canonicalUtcTimestamp(root['data_cutoff_utc']);
  final releasedAtUtc = _canonicalUtcTimestamp(root['released_at_utc']);
  if (releasedAtUtc.isBefore(dataCutoffUtc)) {
    throw const FormatException('current-city release precedes cutoff');
  }
  return CurrentCityReportSnapshotSummary(
    snapshotId: _canonicalUuid(root['snapshot_id']),
    reportId: reportId,
    reportVersion: reportVersion as int,
    reportingTimeZone: reportingTimeZone,
    dataCutoffUtc: dataCutoffUtc,
    releasedAtUtc: releasedAtUtc,
  );
}

int _compareSummaries(
  CurrentCityReportSnapshotSummary left,
  CurrentCityReportSnapshotSummary right,
) {
  final cutoff = left.dataCutoffUtc.compareTo(right.dataCutoffUtc);
  if (cutoff != 0) return cutoff;
  final released = left.releasedAtUtc.compareTo(right.releasedAtUtc);
  if (released != 0) return released;
  return left.snapshotId.compareTo(right.snapshotId);
}

CurrentCityReportSnapshot _parseSnapshot(
  Map<String, Object?> root,
  String requestedProjectId,
  CurrentCityReportSnapshotSummary summary,
) {
  _requireExactKeys(root, const ['access_event_id', 'snapshot_id', 'report']);
  final accessEventId = _canonicalUuid(root['access_event_id']);
  final snapshotId = _canonicalUuid(root['snapshot_id']);
  if (snapshotId != summary.snapshotId) {
    throw const FormatException('current-city snapshot ID is inconsistent');
  }
  return CurrentCityReportSnapshot(
    accessEventId: accessEventId,
    summary: summary,
    report: _parseReport(root['report'], requestedProjectId, summary),
  );
}

CurrentCityReportDocument _parseReport(
  Object? value,
  String requestedProjectId,
  CurrentCityReportSnapshotSummary summary,
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
    'target_context',
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
    throw const FormatException('current-city report metadata is invalid');
  }

  final periods = _parsePeriods(root['periods'], dataCutoffUtc, summary);
  final targetContext = _parseTargetContext(
    root['target_context'],
    dataCutoffUtc,
  );
  final cells = _parseCells(root['cells']);
  return CurrentCityReportDocument(
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
    targetContext: targetContext,
    resultStatus: resultStatus,
    cells: cells,
  );
}

CurrentCityReportPeriods _parsePeriods(
  Object? value,
  DateTime dataCutoffUtc,
  CurrentCityReportSnapshotSummary summary,
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
      periodCutoffUtc != dataCutoffUtc) {
    throw const FormatException('current-city period context is invalid');
  }

  final previous = _parsePeriod(root['previous_period']);
  final current = _parsePeriod(root['current_period']);
  if (previous.untilUtc != current.startUtc ||
      current.untilUtc.isAfter(dataCutoffUtc)) {
    throw const FormatException('current-city periods are not adjacent');
  }
  return CurrentCityReportPeriods(
    periodBoundaryId: periodBoundaryId,
    reportingTimeZone: reportingTimeZone,
    dataCutoffUtc: periodCutoffUtc,
    previousPeriod: previous,
    currentPeriod: current,
  );
}

CurrentCityReportPeriod _parsePeriod(Object? value) {
  final root = _object(value);
  _requireExactKeys(root, const ['start_utc', 'until_utc']);
  final startUtc = _canonicalUtcTimestamp(root['start_utc']);
  final untilUtc = _canonicalUtcTimestamp(root['until_utc']);
  if (!startUtc.isBefore(untilUtc)) {
    throw const FormatException('current-city period is empty');
  }
  return CurrentCityReportPeriod(startUtc: startUtc, untilUtc: untilUtc);
}

CurrentCityReportTargetContext _parseTargetContext(
  Object? value,
  DateTime dataCutoffUtc,
) {
  final root = _object(value);
  _requireExactKeys(root, const [
    'target_context_contract_id',
    'result_status',
    'reason_code',
    'data_cutoff_utc',
    'target_tree_version',
    'target_content_fingerprint',
    'selection_sequence',
    'selection_source',
    'selection_evidence_at_utc',
    'tree_published_at_utc',
  ]);
  final contractId = _nonEmptyString(root['target_context_contract_id']);
  final resultStatus = _nonEmptyString(root['result_status']);
  final reasonCode = _nonEmptyString(root['reason_code']);
  final cutoff = _canonicalUtcTimestamp(root['data_cutoff_utc']);
  final targetTreeVersion = _nonEmptyString(root['target_tree_version']);
  final fingerprint = _nonEmptyString(root['target_content_fingerprint']);
  final selectionSequence = root['selection_sequence'];
  final selectionSource = _nonEmptyString(root['selection_source']);
  final selectionEvidenceAtUtc = _canonicalUtcTimestamp(
    root['selection_evidence_at_utc'],
  );
  final treePublishedAtUtc = _canonicalUtcTimestamp(
    root['tree_published_at_utc'],
  );
  final validEvidence =
      (reasonCode == 'publication_selection' &&
          selectionSource == 'publication') ||
      (reasonCode == 'migration_baseline_observation' &&
          selectionSource == 'migration_baseline');
  if (contractId != _targetContextContractId ||
      resultStatus != 'selected' ||
      !validEvidence ||
      cutoff != dataCutoffUtc ||
      !_nonEmptyWithoutTrimChange(targetTreeVersion) ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(fingerprint) ||
      !_isPositiveSafeInteger(selectionSequence) ||
      selectionEvidenceAtUtc.isAfter(dataCutoffUtc) ||
      treePublishedAtUtc.isAfter(dataCutoffUtc)) {
    throw const FormatException('current-city target context is invalid');
  }
  return CurrentCityReportTargetContext(
    contractId: contractId,
    resultStatus: resultStatus,
    reasonCode: reasonCode,
    dataCutoffUtc: cutoff,
    targetTreeVersion: targetTreeVersion,
    targetContentFingerprint: fingerprint,
    selectionSequence: selectionSequence as int,
    selectionSource: selectionSource,
    selectionEvidenceAtUtc: selectionEvidenceAtUtc,
    treePublishedAtUtc: treePublishedAtUtc,
  );
}

List<CurrentCityReportCell> _parseCells(Object? value) {
  final values = _list(value);
  if (values.length < 2 || values.length > 20000 || values.length.isOdd) {
    throw const FormatException('current-city grid size is invalid');
  }
  final cityCount = values.length ~/ 2;
  if (cityCount < 1 || cityCount > 10000) {
    throw const FormatException('current-city grid city count is invalid');
  }

  final cells = <CurrentCityReportCell>[];
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
      'previous' => CurrentCityReportPeriodKey.previous,
      'current' => CurrentCityReportPeriodKey.current,
      _ => throw const FormatException('current-city period key is invalid'),
    };
    if (root['cell_order'] != index ||
        (index < cityCount &&
            periodKey != CurrentCityReportPeriodKey.previous) ||
        (index >= cityCount &&
            periodKey != CurrentCityReportPeriodKey.current)) {
      throw const FormatException('current-city cell coordinate is invalid');
    }
    final cityId = _nonEmptyWithoutTrimChange(_nonEmptyString(root['city_id']))
        ? root['city_id'] as String
        : (throw const FormatException('current-city city ID is invalid'));
    final privacyStatus = switch (_nonEmptyString(root['privacy_status'])) {
      'displayed' => CurrentCityReportPrivacyStatus.displayed,
      'suppressed' => CurrentCityReportPrivacyStatus.suppressed,
      _ => throw const FormatException(
        'current-city privacy status is invalid',
      ),
    };
    final rawCount = root['value_count'];
    final valueCount = switch (privacyStatus) {
      CurrentCityReportPrivacyStatus.suppressed =>
        rawCount == null
            ? null
            : (throw const FormatException(
                'suppressed current-city cell exposed a value',
              )),
      CurrentCityReportPrivacyStatus.displayed => _displayedCount(rawCount),
    };
    if (index < cityCount) {
      if (previousCities.isNotEmpty &&
          previousCities.last.compareTo(cityId) >= 0) {
        throw const FormatException('current-city grid is not sorted');
      }
      previousCities.add(cityId);
    } else {
      currentCities.add(cityId);
    }
    cells.add(
      CurrentCityReportCell(
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
    throw const FormatException('current-city grid periods do not pair');
  }
  return List.unmodifiable(cells);
}

int _displayedCount(Object? value) {
  if (!_isNonNegativeSafeInteger(value) || (value as int) < 10) {
    throw const FormatException('displayed current-city cell count is invalid');
  }
  return value;
}

void _validateSummaryForRequest(CurrentCityReportSnapshotSummary summary) {
  if (_canonicalUuid(summary.snapshotId) != summary.snapshotId ||
      summary.reportId != _fixedReportId ||
      summary.reportVersion != _fixedReportVersion ||
      _ianaTimeZone(summary.reportingTimeZone) != summary.reportingTimeZone ||
      !_isCanonicalDateTime(summary.dataCutoffUtc) ||
      !_isCanonicalDateTime(summary.releasedAtUtc) ||
      summary.releasedAtUtc.isBefore(summary.dataCutoffUtc)) {
    throw const FormatException('current-city summary is invalid');
  }
}

bool _isCanonicalDateTime(DateTime value) =>
    value.isUtc && _canonicalUtcPattern.hasMatch(value.toIso8601String());

String _requiredHeader(http.Response response, String name) {
  for (final entry in response.headers.entries) {
    if (entry.key.toLowerCase() == name) return entry.value;
  }
  throw const FormatException('current-city response header is missing');
}

void _requireJsonNoStore(http.Response response) {
  final contentType = _requiredHeader(response, 'content-type');
  final mediaType = contentType.split(';').first.trim().toLowerCase();
  final cacheControl = _requiredHeader(response, 'cache-control').trim();
  if (mediaType != 'application/json' || cacheControl != 'no-store') {
    throw const FormatException('current-city response headers are invalid');
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

bool _nonEmptyWithoutTrimChange(String value) =>
    value.isNotEmpty && value.trim() == value;

bool _isNonNegativeSafeInteger(Object? value) =>
    value is int && value >= 0 && value <= _maximumSafeJsonInteger;

bool _isPositiveSafeInteger(Object? value) =>
    _isNonNegativeSafeInteger(value) && (value as int) > 0;

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

CurrentCityReportFailureCode _identityFailure(
  IdentityResult<IdentityAccessToken> result,
) {
  if (result case IdentityRejected<IdentityAccessToken>(:final failure)) {
    return failure.code == IdentityFailureCode.networkUnavailable
        ? CurrentCityReportFailureCode.networkUnavailable
        : CurrentCityReportFailureCode.unauthorized;
  }
  return CurrentCityReportFailureCode.unauthorized;
}

CurrentCityReportFailureCode _httpFailure(int status) => switch (status) {
  400 => CurrentCityReportFailureCode.invalidRequest,
  401 => CurrentCityReportFailureCode.unauthorized,
  403 => CurrentCityReportFailureCode.forbidden,
  404 => CurrentCityReportFailureCode.notFound,
  409 => CurrentCityReportFailureCode.untrusted,
  503 => CurrentCityReportFailureCode.serviceUnavailable,
  _ => CurrentCityReportFailureCode.serverRejected,
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

const _fixedReportId = 'contact_sessions_by_current_city_two_periods';
const _fixedReportVersion = 1;
const _fixedMetricId = 'contact_sessions';
const _fixedMetricVersion = 1;
const _fixedDimension = 'current_city';
const _fixedViewMode = 'current';
const _fixedRegionGranularity = 'city';
const _fixedQueryFingerprint =
    'management-report:contact_sessions_by_current_city_two_periods:v1';
const _fixedPrivacyPolicy =
    'management_current_city_contact_session_privacy_v1';
const _fixedSourceScope = 'backend_accepted_active_contacts_current_revision';
const _fixedPeriodBoundaryId = 'iso_week_monday_v1';
const _fixedResultStatus = 'completed';
const _targetContextContractId = 'management-region-target-context:v1';
const _maximumSafeJsonInteger = 9007199254740991;
