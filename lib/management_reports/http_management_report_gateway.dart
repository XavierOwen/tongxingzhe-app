import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../features/contact_journal/contact_models.dart';
import '../identity/identity_session.dart';
import 'management_report_gateway.dart';

const _backendBaseUrl = String.fromEnvironment('BACKEND_BASE_URL');

ManagementReportGateway productionManagementReportGateway(
  IdentitySession identitySession,
) {
  if (_backendBaseUrl.trim().isEmpty) {
    return const DeferredManagementReportGateway();
  }
  return HttpManagementReportGateway(
    baseUri: Uri.parse(_backendBaseUrl),
    identitySession: identitySession,
    client: http.Client(),
  );
}

final class HttpManagementReportGateway implements ManagementReportGateway {
  factory HttpManagementReportGateway({
    required Uri baseUri,
    required IdentitySession identitySession,
    required http.Client client,
    Duration timeout = const Duration(seconds: 15),
  }) => HttpManagementReportGateway._(
    baseUri: _validatedBaseUri(baseUri),
    identitySession: identitySession,
    client: client,
    timeout: timeout,
  );

  const HttpManagementReportGateway._({
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
  Future<ManagementReportResult<ManagementAnalysisContextSnapshot>>
  loadContext() => _request(
    send: (token) => _client.get(
      _baseUri.resolve('/v1/management-analysis/context'),
      headers: _headers(token),
    ),
    parse: _parseContextSnapshot,
  );

  @override
  Future<ManagementReportResult<ManagementAnalysisContextSnapshot>>
  selectContext(String projectId) => _request(
    send: (token) => _client.put(
      _baseUri.resolve('/v1/management-analysis/context'),
      headers: _headers(token, hasBody: true),
      body: jsonEncode({'project_id': projectId}),
    ),
    parse: _parseContextSnapshot,
  );

  @override
  Future<ManagementReportResult<List<ManagementReportSnapshotSummary>>>
  listSnapshots(String projectId) => _request(
    send: (token) => _client.get(
      _baseUri.resolve(
        '/v1/projects/${Uri.encodeComponent(projectId)}/'
        'management-report-snapshots',
      ),
      headers: _headers(token),
    ),
    parse: (root) => _parseSnapshotDirectory(root, projectId),
  );

  @override
  Future<ManagementReportResult<ManagementReportSnapshot>> readSnapshot({
    required String projectId,
    required ManagementReportSnapshotSummary summary,
  }) => _request(
    send: (token) => _client.get(
      _baseUri.resolve(
        '/v1/projects/${Uri.encodeComponent(projectId)}/'
        'management-report-snapshots/'
        '${Uri.encodeComponent(summary.snapshotId)}',
      ),
      headers: _headers(token),
    ),
    parse: (root) => _parseSnapshot(root, projectId, summary),
  );

  Future<ManagementReportResult<T>> _request<T>({
    required Future<http.Response> Function(IdentityAccessToken token) send,
    required T Function(Map<String, Object?> root) parse,
  }) async {
    try {
      var access = await _identitySession.accessToken();
      if (access is! IdentitySuccess<IdentityAccessToken>) {
        return ManagementReportRejected(_identityFailure(access));
      }
      var response = await send(access.value).timeout(_timeout);
      if (response.statusCode == 401) {
        access = await _identitySession.accessToken(forceRefresh: true);
        if (access is! IdentitySuccess<IdentityAccessToken>) {
          return const ManagementReportRejected(
            ManagementReportFailureCode.unauthorized,
          );
        }
        response = await send(access.value).timeout(_timeout);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return ManagementReportRejected(_httpFailure(response.statusCode));
      }
      return ManagementReportSuccess(parse(_jsonObject(response.body)));
    } on TimeoutException {
      return const ManagementReportRejected(
        ManagementReportFailureCode.networkUnavailable,
      );
    } on http.ClientException {
      return const ManagementReportRejected(
        ManagementReportFailureCode.networkUnavailable,
      );
    } on FormatException {
      return const ManagementReportRejected(
        ManagementReportFailureCode.invalidResponse,
      );
    } on StateError {
      return const ManagementReportRejected(
        ManagementReportFailureCode.invalidResponse,
      );
    }
  }

  @override
  Future<void> close() async => _client.close();
}

ManagementAnalysisContextSnapshot _parseContextSnapshot(
  Map<String, Object?> root,
) {
  _requireExactKeys(root, const [
    'authorization',
    'available_contexts',
    'current_context',
  ]);
  if (root['authorization'] != 'must_reauthorize') {
    throw const FormatException('management authorization marker is invalid');
  }
  final availableValues = _list(root['available_contexts']);
  final available = availableValues.map(_parseContext).toList();
  if (available.map((context) => context.projectId).toSet().length !=
      available.length) {
    throw const FormatException('management projects must be unique');
  }
  final current = root['current_context'] == null
      ? null
      : _parseContext(root['current_context']);
  if (current != null &&
      !available.any(
        (item) =>
            item.organizationId == current.organizationId &&
            item.organizationName == current.organizationName &&
            item.projectId == current.projectId &&
            item.projectName == current.projectName,
      )) {
    throw const FormatException('current management context is unavailable');
  }
  return ManagementAnalysisContextSnapshot(
    current: current,
    available: available,
  );
}

ManagementAnalysisContext _parseContext(Object? value) {
  final root = _object(value);
  _requireExactKeys(root, const ['organization', 'project']);
  final organization = _object(root['organization']);
  final project = _object(root['project']);
  _requireExactKeys(organization, const ['name', 'workspace_id']);
  _requireExactKeys(project, const ['name', 'project_id']);
  return ManagementAnalysisContext(
    organizationId: _uuid(organization['workspace_id']),
    organizationName: _nonEmptyString(organization['name']),
    projectId: _uuid(project['project_id']),
    projectName: _nonEmptyString(project['name']),
  );
}

List<ManagementReportSnapshotSummary> _parseSnapshotDirectory(
  Map<String, Object?> root,
  String requestedProjectId,
) {
  _requireExactKeys(root, const ['access_event_id', 'project_id', 'snapshots']);
  _uuid(root['access_event_id']);
  if (_uuid(root['project_id']) != _uuid(requestedProjectId)) {
    throw const FormatException('snapshot directory project is inconsistent');
  }
  final values = _list(root['snapshots']);
  if (values.length > 20) {
    throw const FormatException('snapshot directory is not bounded');
  }
  final snapshots = values.map(_parseSnapshotSummary).toList();
  if (snapshots.map((item) => item.snapshotId).toSet().length !=
      snapshots.length) {
    throw const FormatException('snapshot directory contains duplicates');
  }
  for (var index = 1; index < snapshots.length; index++) {
    if (_compareSummaries(snapshots[index - 1], snapshots[index]) <= 0) {
      throw const FormatException('snapshot directory order is invalid');
    }
  }
  return List.unmodifiable(snapshots);
}

ManagementReportSnapshotSummary _parseSnapshotSummary(Object? value) {
  final root = _object(value);
  _requireExactKeys(root, const [
    'data_cutoff_utc',
    'released_at_utc',
    'report_id',
    'report_version',
    'reporting_time_zone',
    'snapshot_id',
  ]);
  final reportId = _nonEmptyString(root['report_id']);
  final reportVersion = _positiveInt(root['report_version']);
  if (reportId != _fixedReportId || reportVersion != _fixedReportVersion) {
    throw const FormatException('snapshot report is unsupported');
  }
  final timeZone = _nonEmptyString(root['reporting_time_zone']);
  if (!_timeZonePattern.hasMatch(timeZone)) {
    throw const FormatException('snapshot time zone is invalid');
  }
  final dataCutoffUtc = _utcTimestamp(root['data_cutoff_utc']);
  final releasedAtUtc = _utcTimestamp(root['released_at_utc']);
  if (releasedAtUtc.isBefore(dataCutoffUtc)) {
    throw const FormatException('snapshot release precedes its cutoff');
  }
  return ManagementReportSnapshotSummary(
    snapshotId: _uuid(root['snapshot_id']),
    reportId: reportId,
    reportVersion: reportVersion,
    reportingTimeZone: timeZone,
    dataCutoffUtc: dataCutoffUtc,
    releasedAtUtc: releasedAtUtc,
  );
}

int _compareSummaries(
  ManagementReportSnapshotSummary left,
  ManagementReportSnapshotSummary right,
) {
  final cutoff = left.dataCutoffUtc.compareTo(right.dataCutoffUtc);
  if (cutoff != 0) return cutoff;
  final released = left.releasedAtUtc.compareTo(right.releasedAtUtc);
  if (released != 0) return released;
  return left.snapshotId.compareTo(right.snapshotId);
}

ManagementReportSnapshot _parseSnapshot(
  Map<String, Object?> root,
  String requestedProjectId,
  ManagementReportSnapshotSummary summary,
) {
  _requireExactKeys(root, const ['access_event_id', 'report', 'snapshot_id']);
  _uuid(root['access_event_id']);
  if (_uuid(root['snapshot_id']) != summary.snapshotId.toLowerCase()) {
    throw const FormatException('snapshot response ID is inconsistent');
  }
  final report = _parseProtectedReport(
    root['report'],
    requestedProjectId,
    summary,
  );
  return ManagementReportSnapshot(summary: summary, report: report);
}

ProtectedManagementReport _parseProtectedReport(
  Object? value,
  String requestedProjectId,
  ManagementReportSnapshotSummary summary,
) {
  final root = _object(value);
  _requireExactKeys(root, const [
    'cells',
    'dimension',
    'metric_id',
    'metric_version',
    'periods',
    'privacy_policy',
    'project_id',
    'query_fingerprint',
    'report_id',
    'report_version',
    'source_scope',
  ]);
  final reportId = _nonEmptyString(root['report_id']);
  final reportVersion = _positiveInt(root['report_version']);
  final metricId = _nonEmptyString(root['metric_id']);
  final metricVersion = _positiveInt(root['metric_version']);
  final dimension = _nonEmptyString(root['dimension']);
  final queryFingerprint = _nonEmptyString(root['query_fingerprint']);
  final privacyPolicy = _nonEmptyString(root['privacy_policy']);
  final sourceScope = _nonEmptyString(root['source_scope']);
  final projectId = _uuid(root['project_id']);
  if (reportId != _fixedReportId ||
      reportVersion != _fixedReportVersion ||
      metricId != _fixedMetricId ||
      metricVersion != _fixedMetricVersion ||
      dimension != _fixedDimension ||
      queryFingerprint != _fixedQueryFingerprint ||
      privacyPolicy != _fixedPrivacyPolicy ||
      sourceScope != _fixedSourceScope ||
      projectId != _uuid(requestedProjectId) ||
      reportId != summary.reportId ||
      reportVersion != summary.reportVersion) {
    throw const FormatException('protected report metadata is inconsistent');
  }

  final periods = _parsePeriods(root['periods']);
  if (periods.reportingTimeZone != summary.reportingTimeZone ||
      periods.dataCutoffUtc != summary.dataCutoffUtc) {
    throw const FormatException(
      'protected report period context is inconsistent',
    );
  }

  final cellValues = _list(root['cells']);
  if (cellValues.length != 16) {
    throw const FormatException('protected report must contain 16 cells');
  }
  final cells = <ProtectedManagementReportCell>[];
  for (var index = 0; index < cellValues.length; index++) {
    cells.add(_parseCell(cellValues[index], index));
  }

  return ProtectedManagementReport(
    reportId: reportId,
    reportVersion: reportVersion,
    metricId: metricId,
    metricVersion: metricVersion,
    dimension: dimension,
    queryFingerprint: queryFingerprint,
    privacyPolicy: privacyPolicy,
    sourceScope: sourceScope,
    projectId: projectId,
    periodBoundaryId: periods.periodBoundaryId,
    reportingTimeZone: periods.reportingTimeZone,
    dataCutoffUtc: periods.dataCutoffUtc,
    previousPeriod: periods.previous,
    currentPeriod: periods.current,
    cells: cells,
  );
}

({
  String periodBoundaryId,
  String reportingTimeZone,
  DateTime dataCutoffUtc,
  ManagementReportPeriod previous,
  ManagementReportPeriod current,
})
_parsePeriods(Object? value) {
  final root = _object(value);
  _requireExactKeys(root, const [
    'current_period',
    'data_cutoff_utc',
    'period_boundary_id',
    'previous_period',
    'reporting_time_zone',
  ]);
  final periodBoundaryId = _nonEmptyString(root['period_boundary_id']);
  final reportingTimeZone = _nonEmptyString(root['reporting_time_zone']);
  if (periodBoundaryId != _fixedPeriodBoundaryId ||
      !_timeZonePattern.hasMatch(reportingTimeZone)) {
    throw const FormatException('protected report period metadata is invalid');
  }
  final dataCutoffUtc = _utcTimestamp(root['data_cutoff_utc']);
  final previous = _parsePeriod(root['previous_period']);
  final current = _parsePeriod(root['current_period']);
  if (previous.untilUtc != current.startUtc ||
      current.untilUtc.isAfter(dataCutoffUtc)) {
    throw const FormatException('protected report periods are not adjacent');
  }
  return (
    periodBoundaryId: periodBoundaryId,
    reportingTimeZone: reportingTimeZone,
    dataCutoffUtc: dataCutoffUtc,
    previous: previous,
    current: current,
  );
}

ManagementReportPeriod _parsePeriod(Object? value) {
  final root = _object(value);
  _requireExactKeys(root, const ['start_utc', 'until_utc']);
  final start = _utcTimestamp(root['start_utc']);
  final until = _utcTimestamp(root['until_utc']);
  if (!start.isBefore(until)) {
    throw const FormatException('protected report period is empty');
  }
  return ManagementReportPeriod(startUtc: start, untilUtc: until);
}

ProtectedManagementReportCell _parseCell(Object? value, int expectedOrder) {
  final root = _object(value);
  _requireExactKeys(root, const [
    'category_key',
    'cell_order',
    'period_key',
    'privacy_status',
    'value_count',
  ]);
  if (root['cell_order'] != expectedOrder) {
    throw const FormatException('protected report cell order is invalid');
  }
  final expectedPeriod = expectedOrder < 8
      ? ManagementReportPeriodKey.previous
      : ManagementReportPeriodKey.current;
  final periodKey = switch (_nonEmptyString(root['period_key'])) {
    'previous' => ManagementReportPeriodKey.previous,
    'current' => ManagementReportPeriodKey.current,
    _ => throw const FormatException('protected report period key is invalid'),
  };
  final expectedCategory = _orderedCategoryKeys[expectedOrder % 8];
  final categoryKey = _nonEmptyString(root['category_key']);
  if (periodKey != expectedPeriod ||
      categoryKey != expectedCategory ||
      !_supportedCategoryKeys.contains(categoryKey)) {
    throw const FormatException(
      'protected report cell coordinates are invalid',
    );
  }
  final privacyStatus = switch (_nonEmptyString(root['privacy_status'])) {
    'displayed' => ManagementReportPrivacyStatus.displayed,
    'suppressed' => ManagementReportPrivacyStatus.suppressed,
    _ => throw const FormatException(
      'protected report privacy status is invalid',
    ),
  };
  final valueCount = root['value_count'];
  if (privacyStatus == ManagementReportPrivacyStatus.displayed) {
    if (valueCount is! int || valueCount < 0) {
      throw const FormatException('displayed report cell needs a count');
    }
  } else if (valueCount != null) {
    throw const FormatException('suppressed report cell exposed a value');
  }
  return ProtectedManagementReportCell(
    periodKey: periodKey,
    categoryKey: categoryKey,
    cellOrder: expectedOrder,
    valueCount: valueCount as int?,
    privacyStatus: privacyStatus,
  );
}

Map<String, String> _headers(
  IdentityAccessToken token, {
  bool hasBody = false,
}) => {
  'accept': 'application/json',
  'authorization': 'Bearer ${token.value}',
  if (hasBody) 'content-type': 'application/json; charset=utf-8',
};

ManagementReportFailureCode _identityFailure(
  IdentityResult<IdentityAccessToken> result,
) {
  if (result case IdentityRejected<IdentityAccessToken>(:final failure)) {
    return failure.code == IdentityFailureCode.networkUnavailable
        ? ManagementReportFailureCode.networkUnavailable
        : ManagementReportFailureCode.unauthorized;
  }
  return ManagementReportFailureCode.unauthorized;
}

ManagementReportFailureCode _httpFailure(int status) => switch (status) {
  401 || 403 => ManagementReportFailureCode.unauthorized,
  404 => ManagementReportFailureCode.notFound,
  409 => ManagementReportFailureCode.untrusted,
  _ => ManagementReportFailureCode.serverRejected,
};

Map<String, Object?> _jsonObject(String value) => _object(jsonDecode(value));

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('expected object');
  }
  return value;
}

List<Object?> _list(Object? value) {
  if (value is! List<Object?>) {
    throw const FormatException('expected list');
  }
  return value;
}

String _nonEmptyString(Object? value) {
  if (value is! String || value.trim().isEmpty || value != value.trim()) {
    throw const FormatException('expected non-empty string');
  }
  return value;
}

int _positiveInt(Object? value) {
  if (value is! int || value < 1) {
    throw const FormatException('expected positive integer');
  }
  return value;
}

DateTime _utcTimestamp(Object? value) {
  if (value is! String || !_rfc3339Pattern.hasMatch(value)) {
    throw const FormatException('expected RFC3339 timestamp');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw const FormatException('timestamp is invalid');
  }
  return parsed.toUtc();
}

String _uuid(Object? value) {
  final text = _nonEmptyString(value);
  if (!_uuidPattern.hasMatch(text)) {
    throw const FormatException('expected UUID');
  }
  return text.toLowerCase();
}

void _requireExactKeys(Map<String, Object?> value, List<String> expected) {
  final actual = value.keys.toList()..sort();
  final sortedExpected = [...expected]..sort();
  if (actual.length != sortedExpected.length) {
    throw const FormatException('object keys are invalid');
  }
  for (var index = 0; index < actual.length; index++) {
    if (actual[index] != sortedExpected[index]) {
      throw const FormatException('object keys are invalid');
    }
  }
}

Uri _validatedBaseUri(Uri value) {
  if (!value.hasScheme || value.host.isEmpty) {
    throw const FormatException('BACKEND_BASE_URL must be an absolute URL');
  }
  final localHttp =
      value.scheme == 'http' &&
      const {'localhost', '127.0.0.1', '::1'}.contains(value.host);
  if (value.scheme != 'https' && !localHttp) {
    throw const FormatException(
      'BACKEND_BASE_URL must use HTTPS except on localhost',
    );
  }
  return value;
}

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);
final _rfc3339Pattern = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$',
);
final _timeZonePattern = RegExp(r'^[A-Za-z0-9._+/-]+$');
const _fixedReportId = 'contact_sessions_by_channel_two_periods';
const _fixedReportVersion = 1;
const _fixedMetricId = 'contact_sessions';
const _fixedMetricVersion = 1;
const _fixedDimension = 'channel';
const _fixedQueryFingerprint =
    'management-report:contact_sessions_by_channel_two_periods:v1';
const _fixedPrivacyPolicy = 'management_contact_session_privacy_v1';
const _fixedSourceScope = 'backend_accepted_contacts';
const _fixedPeriodBoundaryId = 'iso_week_monday_v1';
final _supportedCategoryKeys = {
  'all',
  ...ContactChannel.values.map((channel) => channel.storageValue),
};
final _orderedCategoryKeys = [
  'all',
  ...ContactChannel.values.map((channel) => channel.storageValue),
];
