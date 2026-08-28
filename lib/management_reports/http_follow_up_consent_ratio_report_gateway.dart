import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:timezone/data/latest_all.dart' as time_zone_data;
import 'package:timezone/timezone.dart' as time_zone;

import '../foundation/backend_base_uri.dart';
import '../identity/identity_session.dart';
import 'follow_up_consent_ratio_report_gateway.dart';

const _backendBaseUrl = String.fromEnvironment('BACKEND_BASE_URL');

/// 从构建配置取得 Backend 地址；未配置时显式降级，不访问网络。
FollowUpConsentRatioReportGateway productionFollowUpConsentRatioReportGateway(
  IdentitySession identitySession,
) {
  final configured = _backendBaseUrl.trim();
  if (configured.isEmpty) {
    return const DeferredFollowUpConsentRatioReportGateway();
  }
  return HttpFollowUpConsentRatioReportGateway(
    baseUri: Uri.parse(configured),
    identitySession: identitySession,
    client: http.Client(),
  );
}

/// 后续联系同意占比目录和显式 detail 的独立 HTTP typed gateway。
///
/// 这个 adapter 只发送固定 GET 请求；它不计算报告、不选择“最新”快照，也不
/// 把响应写入任何本地持久化或缓存边界。
final class HttpFollowUpConsentRatioReportGateway
    implements FollowUpConsentRatioReportGateway {
  factory HttpFollowUpConsentRatioReportGateway({
    required Uri baseUri,
    required IdentitySession identitySession,
    required http.Client client,
    Duration timeout = const Duration(seconds: 15),
  }) => HttpFollowUpConsentRatioReportGateway._(
    baseUri: validateManagementReportBaseUri(baseUri),
    identitySession: identitySession,
    client: client,
    timeout: timeout,
  );

  HttpFollowUpConsentRatioReportGateway._({
    required this._baseUri,
    required this._identitySession,
    required this._client,
    required this._timeout,
  });

  final Uri _baseUri;
  final IdentitySession _identitySession;
  final http.Client _client;
  final Duration _timeout;
  bool _closed = false;

  @override
  Future<
    FollowUpConsentRatioReportResult<
      FollowUpConsentRatioReportSnapshotDirectory
    >
  >
  listSnapshots(String projectId) {
    try {
      _canonicalUuid(projectId);
    } on FormatException {
      return Future.value(
        const FollowUpConsentRatioReportRejected(
          FollowUpConsentRatioReportFailureCode.invalidRequest,
        ),
      );
    }
    return _request(
      send: (token) => _client.get(
        _baseUri.resolve(
          '/v1/projects/${Uri.encodeComponent(projectId)}'
          '/management-follow-up-consent-ratio-report-snapshots',
        ),
        headers: _headers(token),
      ),
      parse: (root) => _parseDirectory(root, projectId),
    );
  }

  @override
  Future<FollowUpConsentRatioReportResult<FollowUpConsentRatioReportSnapshot>>
  readSnapshot({
    required String projectId,
    required FollowUpConsentRatioReportSnapshotSummary summary,
  }) {
    try {
      _canonicalUuid(projectId);
      _validateSummaryForRequest(summary);
    } on FormatException {
      return Future.value(
        const FollowUpConsentRatioReportRejected(
          FollowUpConsentRatioReportFailureCode.invalidRequest,
        ),
      );
    }
    return _request(
      send: (token) => _client.get(
        _baseUri.resolve(
          '/v1/projects/${Uri.encodeComponent(projectId)}'
          '/management-follow-up-consent-ratio-report-snapshots/'
          '${Uri.encodeComponent(summary.snapshotId)}',
        ),
        headers: _headers(token),
      ),
      parse: (root) => _parseSnapshot(root, projectId, summary),
    );
  }

  Future<FollowUpConsentRatioReportResult<T>> _request<T>({
    required Future<http.Response> Function(String token) send,
    required T Function(Map<String, Object?> root) parse,
  }) {
    if (_closed) {
      return Future.value(
        const FollowUpConsentRatioReportRejected(
          FollowUpConsentRatioReportFailureCode.closed,
        ),
      );
    }
    return _requestOpen(send: send, parse: parse);
  }

  Future<FollowUpConsentRatioReportResult<T>> _requestOpen<T>({
    required Future<http.Response> Function(String token) send,
    required T Function(Map<String, Object?> root) parse,
  }) async {
    try {
      if (_closed) {
        return const FollowUpConsentRatioReportRejected(
          FollowUpConsentRatioReportFailureCode.closed,
        );
      }
      var access = await _identitySession.accessToken();
      if (_closed) {
        return const FollowUpConsentRatioReportRejected(
          FollowUpConsentRatioReportFailureCode.closed,
        );
      }
      if (access is! IdentitySuccess<IdentityAccessToken>) {
        return FollowUpConsentRatioReportRejected(_identityFailure(access));
      }

      var response = await send(access.value.value).timeout(_timeout);
      if (_closed) {
        return const FollowUpConsentRatioReportRejected(
          FollowUpConsentRatioReportFailureCode.closed,
        );
      }
      if (response.statusCode == 401) {
        access = await _identitySession.accessToken(forceRefresh: true);
        if (_closed) {
          return const FollowUpConsentRatioReportRejected(
            FollowUpConsentRatioReportFailureCode.closed,
          );
        }
        if (access is! IdentitySuccess<IdentityAccessToken>) {
          return FollowUpConsentRatioReportRejected(_identityFailure(access));
        }
        response = await send(access.value.value).timeout(_timeout);
        if (_closed) {
          return const FollowUpConsentRatioReportRejected(
            FollowUpConsentRatioReportFailureCode.closed,
          );
        }
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return FollowUpConsentRatioReportRejected(
          _httpFailure(response.statusCode),
        );
      }
      _requireJsonNoStore(response);
      return FollowUpConsentRatioReportSuccess(
        parse(_jsonObject(response.body)),
      );
    } on TimeoutException {
      return const FollowUpConsentRatioReportRejected(
        FollowUpConsentRatioReportFailureCode.networkUnavailable,
      );
    } on http.ClientException {
      return const FollowUpConsentRatioReportRejected(
        FollowUpConsentRatioReportFailureCode.networkUnavailable,
      );
    } on FormatException {
      return const FollowUpConsentRatioReportRejected(
        FollowUpConsentRatioReportFailureCode.invalidResponse,
      );
    } on ArgumentError {
      return const FollowUpConsentRatioReportRejected(
        FollowUpConsentRatioReportFailureCode.invalidResponse,
      );
    } on StateError {
      return _closed
          ? const FollowUpConsentRatioReportRejected(
              FollowUpConsentRatioReportFailureCode.closed,
            )
          : const FollowUpConsentRatioReportRejected(
              FollowUpConsentRatioReportFailureCode.invalidResponse,
            );
    } on Object {
      // Adapter 边界不把 provider、HTTP client 或内部异常交给调用方。
      return const FollowUpConsentRatioReportRejected(
        FollowUpConsentRatioReportFailureCode.invalidResponse,
      );
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _client.close();
  }
}

FollowUpConsentRatioReportSnapshotDirectory _parseDirectory(
  Map<String, Object?> root,
  String requestedProjectId,
) {
  _requireExactKeys(root, const ['access_event_id', 'project_id', 'snapshots']);
  final accessEventId = _canonicalUuid(root['access_event_id']);
  final projectId = _canonicalUuid(root['project_id']);
  if (projectId != requestedProjectId) {
    throw const FormatException('follow-up directory project is invalid');
  }

  final values = _list(root['snapshots']);
  if (values.length > 20) {
    throw const FormatException('follow-up directory is not bounded');
  }
  final snapshots = values.map(_parseSummary).toList();
  final seen = <String>{};
  for (var index = 0; index < snapshots.length; index++) {
    final snapshot = snapshots[index];
    if (!seen.add(snapshot.snapshotId)) {
      throw const FormatException('follow-up directory has duplicates');
    }
    if (index > 0 && _compareSummaries(snapshots[index - 1], snapshot) <= 0) {
      throw const FormatException('follow-up directory order is invalid');
    }
  }
  return FollowUpConsentRatioReportSnapshotDirectory(
    accessEventId: accessEventId,
    projectId: projectId,
    snapshots: snapshots,
  );
}

FollowUpConsentRatioReportSnapshotSummary _parseSummary(Object? value) {
  final root = _object(value);
  _requireExactKeys(root, const [
    'snapshot_id',
    'report_id',
    'report_version',
    'reporting_time_zone',
    'data_cutoff_utc',
    'released_at_utc',
  ]);
  final snapshotId = _canonicalUuid(root['snapshot_id']);
  final reportId = _nonEmptyString(root['report_id']);
  final reportVersion = root['report_version'];
  if (reportId != _fixedReportId ||
      reportVersion is! int ||
      reportVersion != _fixedReportVersion) {
    throw const FormatException('follow-up report identity is invalid');
  }
  final reportingTimeZone = _ianaTimeZone(root['reporting_time_zone']);
  final dataCutoffUtc = _canonicalUtcTimestamp(root['data_cutoff_utc']);
  final releasedAtUtc = _canonicalUtcTimestamp(root['released_at_utc']);
  if (releasedAtUtc.isBefore(dataCutoffUtc)) {
    throw const FormatException('follow-up release precedes cutoff');
  }
  return FollowUpConsentRatioReportSnapshotSummary(
    snapshotId: snapshotId,
    reportId: reportId,
    reportVersion: reportVersion,
    reportingTimeZone: reportingTimeZone,
    dataCutoffUtc: dataCutoffUtc,
    releasedAtUtc: releasedAtUtc,
  );
}

int _compareSummaries(
  FollowUpConsentRatioReportSnapshotSummary left,
  FollowUpConsentRatioReportSnapshotSummary right,
) {
  final cutoff = left.dataCutoffUtc.compareTo(right.dataCutoffUtc);
  if (cutoff != 0) return cutoff;
  final released = left.releasedAtUtc.compareTo(right.releasedAtUtc);
  if (released != 0) return released;
  return left.snapshotId.compareTo(right.snapshotId);
}

FollowUpConsentRatioReportSnapshot _parseSnapshot(
  Map<String, Object?> root,
  String requestedProjectId,
  FollowUpConsentRatioReportSnapshotSummary summary,
) {
  _requireExactKeys(root, const ['access_event_id', 'snapshot_id', 'report']);
  final accessEventId = _canonicalUuid(root['access_event_id']);
  final snapshotId = _canonicalUuid(root['snapshot_id']);
  if (snapshotId != summary.snapshotId) {
    throw const FormatException('follow-up snapshot ID is inconsistent');
  }
  return FollowUpConsentRatioReportSnapshot(
    accessEventId: accessEventId,
    summary: summary,
    report: _parseReport(root['report'], requestedProjectId, summary),
  );
}

FollowUpConsentRatioReportDocument _parseReport(
  Object? value,
  String requestedProjectId,
  FollowUpConsentRatioReportSnapshotSummary summary,
) {
  final root = _object(value);
  _requireExactKeys(root, const [
    'contract_id',
    'report_id',
    'report_version',
    'metric_id',
    'metric_version',
    'statistical_unit',
    'dimension',
    'period_grain',
    'comparison_period_count',
    'period_boundary_id',
    'privacy_policy',
    'query_fingerprint',
    'source_scope',
    'project_id',
    'status',
    'periods',
    'period_results',
  ]);

  final contractId = _nonEmptyString(root['contract_id']);
  final reportId = _nonEmptyString(root['report_id']);
  final reportVersion = root['report_version'];
  final metricId = _nonEmptyString(root['metric_id']);
  final metricVersion = root['metric_version'];
  final statisticalUnit = _nonEmptyString(root['statistical_unit']);
  final dimension = _nonEmptyString(root['dimension']);
  final periodGrain = _nonEmptyString(root['period_grain']);
  final comparisonPeriodCount = root['comparison_period_count'];
  final periodBoundaryId = _nonEmptyString(root['period_boundary_id']);
  final privacyPolicy = _nonEmptyString(root['privacy_policy']);
  final queryFingerprint = _nonEmptyString(root['query_fingerprint']);
  final sourceScope = _nonEmptyString(root['source_scope']);
  final projectId = _canonicalUuid(root['project_id']);
  final resultStatus = _nonEmptyString(root['status']);

  if (contractId != _fixedContractId ||
      reportId != _fixedReportId ||
      reportVersion is! int ||
      reportVersion != _fixedReportVersion ||
      metricId != _fixedMetricId ||
      metricVersion is! int ||
      metricVersion != _fixedMetricVersion ||
      statisticalUnit != _fixedStatisticalUnit ||
      dimension != _fixedDimension ||
      periodGrain != _fixedPeriodGrain ||
      comparisonPeriodCount is! int ||
      comparisonPeriodCount != _fixedComparisonPeriodCount ||
      periodBoundaryId != _fixedPeriodBoundaryId ||
      privacyPolicy != _fixedPrivacyPolicy ||
      queryFingerprint != _fixedQueryFingerprint ||
      sourceScope != _fixedSourceScope ||
      projectId != requestedProjectId ||
      resultStatus != _fixedResultStatus ||
      reportId != summary.reportId ||
      reportVersion != summary.reportVersion) {
    throw const FormatException('follow-up report metadata is invalid');
  }

  final periods = _parsePeriods(root['periods'], summary);
  final periodResults = _parsePeriodResults(root['period_results']);
  _assertNoSensitiveFacts(root);
  return FollowUpConsentRatioReportDocument(
    reportId: reportId,
    reportVersion: reportVersion,
    metricId: metricId,
    metricVersion: metricVersion,
    statisticalUnit: statisticalUnit,
    dimension: dimension,
    periodGrain: periodGrain,
    comparisonPeriodCount: comparisonPeriodCount,
    periodBoundaryId: periodBoundaryId,
    privacyPolicy: privacyPolicy,
    queryFingerprint: queryFingerprint,
    sourceScope: sourceScope,
    projectId: projectId,
    resultStatus: resultStatus,
    periods: periods,
    periodResults: periodResults,
  );
}

FollowUpConsentRatioReportPeriods _parsePeriods(
  Object? value,
  FollowUpConsentRatioReportSnapshotSummary summary,
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
    throw const FormatException('follow-up period context is invalid');
  }

  final previous = _parsePeriod(root['previous_period']);
  final current = _parsePeriod(root['current_period']);
  if (previous.untilUtc != current.startUtc ||
      current.untilUtc.isAfter(dataCutoffUtc) ||
      _isoWeekBoundaryLocalDay(previous.startUtc, reportingTimeZone) == null ||
      _isoWeekBoundaryLocalDay(previous.untilUtc, reportingTimeZone) == null ||
      _isoWeekBoundaryLocalDay(current.startUtc, reportingTimeZone) == null ||
      _isoWeekBoundaryLocalDay(current.untilUtc, reportingTimeZone) == null ||
      _isoWeekBoundaryLocalDay(previous.untilUtc, reportingTimeZone)! -
              _isoWeekBoundaryLocalDay(previous.startUtc, reportingTimeZone)! !=
          _sevenDays ||
      _isoWeekBoundaryLocalDay(current.untilUtc, reportingTimeZone)! -
              _isoWeekBoundaryLocalDay(current.startUtc, reportingTimeZone)! !=
          _sevenDays) {
    throw const FormatException('follow-up periods are not complete');
  }
  return FollowUpConsentRatioReportPeriods(
    periodBoundaryId: periodBoundaryId,
    reportingTimeZone: reportingTimeZone,
    dataCutoffUtc: dataCutoffUtc,
    previousPeriod: previous,
    currentPeriod: current,
  );
}

FollowUpConsentRatioReportPeriod _parsePeriod(Object? value) {
  final root = _object(value);
  _requireExactKeys(root, const ['start_utc', 'until_utc']);
  final startUtc = _canonicalUtcTimestamp(root['start_utc']);
  final untilUtc = _canonicalUtcTimestamp(root['until_utc']);
  if (!startUtc.isBefore(untilUtc)) {
    throw const FormatException('follow-up period is empty');
  }
  return FollowUpConsentRatioReportPeriod(
    startUtc: startUtc,
    untilUtc: untilUtc,
  );
}

List<FollowUpConsentRatioReportPeriodResult> _parsePeriodResults(
  Object? value,
) {
  final values = _list(value);
  if (values.length != 2) {
    throw const FormatException('follow-up period result count is invalid');
  }
  final results = <FollowUpConsentRatioReportPeriodResult>[];
  for (var index = 0; index < values.length; index++) {
    final root = _object(values[index]);
    _requireExactKeys(root, const [
      'period_key',
      'period_order',
      'ratio',
      'coverage',
      'unknown_count',
      'excluded_count',
    ]);
    final periodKey = switch (_nonEmptyString(root['period_key'])) {
      'previous' => FollowUpConsentRatioReportPeriodKey.previous,
      'current' => FollowUpConsentRatioReportPeriodKey.current,
      _ => throw const FormatException('follow-up period key is invalid'),
    };
    final periodOrderValue = root['period_order'];
    final unknownCountValue = root['unknown_count'];
    final excludedCountValue = root['excluded_count'];
    if (periodKey !=
            (index == 0
                ? FollowUpConsentRatioReportPeriodKey.previous
                : FollowUpConsentRatioReportPeriodKey.current) ||
        periodOrderValue is! int ||
        periodOrderValue != index ||
        unknownCountValue is! int ||
        !_isNonNegativeSafeInteger(unknownCountValue) ||
        unknownCountValue != 0 ||
        excludedCountValue is! int ||
        !_isNonNegativeSafeInteger(excludedCountValue) ||
        excludedCountValue != 0) {
      throw const FormatException(
        'follow-up period result coordinate is invalid',
      );
    }
    final periodOrder = periodOrderValue;
    final unknownCount = unknownCountValue;
    final excludedCount = excludedCountValue;
    results.add(
      FollowUpConsentRatioReportPeriodResult(
        periodKey: periodKey,
        periodOrder: periodOrder,
        ratio: _parseRatio(root['ratio']),
        coverage: _parseCoverage(root['coverage'], periodOrder),
        unknownCount: unknownCount,
        excludedCount: excludedCount,
      ),
    );
  }
  return List.unmodifiable(results);
}

FollowUpConsentRatioReportRatio _parseRatio(Object? value) {
  final root = _object(value);
  _requireExactKeys(root, const [
    'privacy_status',
    'yes_count',
    'no_count',
    'numerator',
    'denominator',
    'percentage_basis_points',
  ]);
  final privacyStatus = switch (_nonEmptyString(root['privacy_status'])) {
    'displayed' => FollowUpConsentRatioReportPrivacyStatus.displayed,
    'suppressed' => FollowUpConsentRatioReportPrivacyStatus.suppressed,
    _ => throw const FormatException(
      'follow-up ratio privacy status is invalid',
    ),
  };
  final yesCountValue = root['yes_count'];
  final noCountValue = root['no_count'];
  final numeratorValue = root['numerator'];
  final denominatorValue = root['denominator'];
  final percentageBasisPointsValue = root['percentage_basis_points'];
  if (privacyStatus == FollowUpConsentRatioReportPrivacyStatus.suppressed) {
    if (yesCountValue != null ||
        noCountValue != null ||
        numeratorValue != null ||
        denominatorValue != null ||
        percentageBasisPointsValue != null) {
      throw const FormatException('suppressed follow-up ratio exposed a value');
    }
    return const FollowUpConsentRatioReportRatio(
      privacyStatus: FollowUpConsentRatioReportPrivacyStatus.suppressed,
      yesCount: null,
      noCount: null,
      numerator: null,
      denominator: null,
      percentageBasisPoints: null,
    );
  }

  final yesCount = _requiredPositiveSafeInteger(yesCountValue);
  final noCount = _requiredPositiveSafeInteger(noCountValue);
  final numerator = _requiredPositiveSafeInteger(numeratorValue);
  final denominator = _requiredPositiveSafeInteger(denominatorValue);
  final percentageBasisPoints = _requiredNonnegativeSafeInteger(
    percentageBasisPointsValue,
  );
  if (yesCount < _minimumDisplayedCount ||
      noCount < _minimumDisplayedCount ||
      percentageBasisPoints > 10000) {
    throw const FormatException('displayed follow-up ratio is invalid');
  }
  final expectedBasisPoints = _ratioBasisPoints(yesCount, denominator);
  if (numerator != yesCount ||
      denominator != yesCount + noCount ||
      denominator > _maximumSafeJsonInteger ||
      percentageBasisPoints != expectedBasisPoints) {
    throw const FormatException('follow-up ratio arithmetic is invalid');
  }
  return FollowUpConsentRatioReportRatio(
    privacyStatus: FollowUpConsentRatioReportPrivacyStatus.displayed,
    yesCount: yesCount,
    noCount: noCount,
    numerator: numerator,
    denominator: denominator,
    percentageBasisPoints: percentageBasisPoints,
  );
}

int _ratioBasisPoints(int yesCount, int denominator) {
  final scaled = BigInt.from(yesCount) * BigInt.from(10000);
  return ((scaled + BigInt.from(denominator) ~/ BigInt.from(2)) ~/
          BigInt.from(denominator))
      .toInt();
}

List<FollowUpConsentRatioReportCoverageCell> _parseCoverage(
  Object? value,
  int periodOrder,
) {
  final values = _list(value);
  if (values.length != 3) {
    throw const FormatException('follow-up coverage size is invalid');
  }
  const expectedStates = ['unanswered', 'refused', 'not_applicable'];
  final cells = <FollowUpConsentRatioReportCoverageCell>[];
  for (var index = 0; index < values.length; index++) {
    final root = _object(values[index]);
    _requireExactKeys(root, const [
      'consent_state',
      'cell_order',
      'value_count',
      'privacy_status',
    ]);
    final consentState = _nonEmptyString(root['consent_state']);
    final cellOrderValue = root['cell_order'];
    final privacyStatus = switch (_nonEmptyString(root['privacy_status'])) {
      'displayed' => FollowUpConsentRatioReportPrivacyStatus.displayed,
      'suppressed' => FollowUpConsentRatioReportPrivacyStatus.suppressed,
      _ => throw const FormatException(
        'follow-up coverage privacy status is invalid',
      ),
    };
    final valueCountValue = root['value_count'];
    int? valueCount;
    if (consentState != expectedStates[index] ||
        cellOrderValue is! int ||
        cellOrderValue != periodOrder * 3 + index) {
      throw const FormatException('follow-up coverage coordinate is invalid');
    }
    if (privacyStatus == FollowUpConsentRatioReportPrivacyStatus.suppressed) {
      if (valueCountValue != null) {
        throw const FormatException(
          'suppressed follow-up coverage exposed a value',
        );
      }
    } else {
      valueCount = _requiredPositiveSafeInteger(valueCountValue);
      if (valueCount < _minimumDisplayedCount) {
        throw const FormatException('displayed follow-up coverage is invalid');
      }
    }
    final cellOrder = cellOrderValue;
    cells.add(
      FollowUpConsentRatioReportCoverageCell(
        consentState: consentState,
        cellOrder: cellOrder,
        valueCount: valueCount,
        privacyStatus: privacyStatus,
      ),
    );
  }
  return List.unmodifiable(cells);
}

int? _isoWeekBoundaryLocalDay(DateTime value, String reportingTimeZone) {
  final location = time_zone.getLocation(reportingTimeZone);
  final local = time_zone.TZDateTime.from(value, location);
  if (local.weekday != DateTime.monday ||
      local.hour != 0 ||
      local.minute != 0 ||
      local.second != 0 ||
      local.millisecond != 0 ||
      local.microsecond != 0) {
    return null;
  }
  return DateTime.utc(
    local.year,
    local.month,
    local.day,
  ).millisecondsSinceEpoch;
}

void _validateSummaryForRequest(
  FollowUpConsentRatioReportSnapshotSummary summary,
) {
  if (_canonicalUuid(summary.snapshotId) != summary.snapshotId ||
      summary.reportId != _fixedReportId ||
      summary.reportVersion != _fixedReportVersion ||
      _ianaTimeZone(summary.reportingTimeZone) != summary.reportingTimeZone ||
      !_isCanonicalDateTime(summary.dataCutoffUtc) ||
      !_isCanonicalDateTime(summary.releasedAtUtc) ||
      summary.releasedAtUtc.isBefore(summary.dataCutoffUtc)) {
    throw const FormatException('follow-up summary is invalid');
  }
}

bool _isCanonicalDateTime(DateTime value) =>
    value.isUtc && _canonicalUtcPattern.hasMatch(value.toIso8601String());

String _requiredHeader(http.Response response, String name) {
  for (final entry in response.headers.entries) {
    if (entry.key.toLowerCase() == name) return entry.value;
  }
  throw const FormatException('follow-up response header is missing');
}

void _requireJsonNoStore(http.Response response) {
  final contentType = _requiredHeader(response, 'content-type');
  final mediaType = contentType.split(';').first.trim().toLowerCase();
  final cacheControl = _requiredHeader(response, 'cache-control').trim();
  if (mediaType != 'application/json' || cacheControl != 'no-store') {
    throw const FormatException('follow-up response headers are invalid');
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

bool _isPositiveSafeInteger(Object? value) =>
    value is int && value > 0 && value <= _maximumSafeJsonInteger;

int _requiredNonnegativeSafeInteger(Object? value) {
  if (!_isNonNegativeSafeInteger(value)) {
    throw const FormatException('expected safe non-negative integer');
  }
  return value as int;
}

int _requiredPositiveSafeInteger(Object? value) {
  if (!_isPositiveSafeInteger(value)) {
    throw const FormatException('expected safe positive integer');
  }
  return value as int;
}

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
      throw const FormatException('follow-up report contains sensitive facts');
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

FollowUpConsentRatioReportFailureCode _identityFailure(
  IdentityResult<IdentityAccessToken> result,
) {
  if (result case IdentityRejected<IdentityAccessToken>(:final failure)) {
    return switch (failure.code) {
      IdentityFailureCode.notConfigured =>
        FollowUpConsentRatioReportFailureCode.notConfigured,
      IdentityFailureCode.networkUnavailable =>
        FollowUpConsentRatioReportFailureCode.networkUnavailable,
      _ => FollowUpConsentRatioReportFailureCode.unauthorized,
    };
  }
  return FollowUpConsentRatioReportFailureCode.unauthorized;
}

FollowUpConsentRatioReportFailureCode _httpFailure(int status) =>
    switch (status) {
      400 => FollowUpConsentRatioReportFailureCode.invalidRequest,
      401 => FollowUpConsentRatioReportFailureCode.unauthorized,
      403 => FollowUpConsentRatioReportFailureCode.forbidden,
      404 => FollowUpConsentRatioReportFailureCode.notFound,
      409 => FollowUpConsentRatioReportFailureCode.untrusted,
      503 => FollowUpConsentRatioReportFailureCode.serviceUnavailable,
      _ => FollowUpConsentRatioReportFailureCode.serverRejected,
    };

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final _canonicalUtcPattern = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
);
final _timeZonePattern = RegExp(r'^[A-Za-z0-9._+/-]+$');
var _timeZonesInitialized = false;

const _fixedContractId = 'management_follow_up_consent_ratio_candidate_v1';
const _fixedReportId = 'contact_target_follow_up_consent_ratio_two_periods';
const _fixedReportVersion = 1;
const _fixedMetricId = 'follow_up_consent_ratio';
const _fixedMetricVersion = 1;
const _fixedStatisticalUnit = 'contact_target_link';
const _fixedDimension = 'consent_state';
const _fixedPeriodGrain = 'week';
const _fixedComparisonPeriodCount = 2;
const _fixedPeriodBoundaryId = 'iso_week_monday_v1';
const _fixedPrivacyPolicy = 'management_follow_up_consent_ratio_privacy_v1';
const _fixedQueryFingerprint =
    'management-report:contact_target_follow_up_consent_ratio_two_periods:v1';
const _fixedSourceScope =
    'backend_accepted_active_contact_target_links_current_revision';
const _fixedResultStatus = 'completed';
const _maximumSafeJsonInteger = 9007199254740991;
const _minimumDisplayedCount = 10;
const _sevenDays = 7 * 24 * 60 * 60 * 1000;

const _sensitiveFactKeys = <String>{
  'app_user',
  'app_user_id',
  'contact',
  'contact_id',
  'contact_key',
  'target',
  'target_id',
  'promotion_target',
  'promotion_target_id',
  'contributor',
  'contributor_id',
  'contributor_key',
  'email',
  'phone',
  'raw_answer',
  'raw_value',
  'answer',
  'place_name',
  'placeName',
  'latitude',
  'longitude',
  'location',
  'location_source',
  'locationSource',
  'source',
  'source_id',
  'source_key',
  'revision',
  'revision_id',
  'canonical_name',
  'city_name',
  'cityName',
  'region_name',
  'regionName',
  'boundary',
  'geometry',
  'coordinates',
  'organization_membership_id',
  'project_membership_id',
  'capability_grant_id',
};
