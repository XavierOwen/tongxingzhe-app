/// Flutter 读取管理分析项目、可信快照目录和受保护报告的唯一接口。
///
/// 该接口不暴露 bearer token、授权关系或客户端隐私计算。每次调用都由远端
/// 重新授权；实现也不得把管理报告写入离线缓存。
abstract interface class ManagementReportGateway {
  Future<ManagementReportResult<ManagementAnalysisContextSnapshot>>
  loadContext();

  Future<ManagementReportResult<ManagementAnalysisContextSnapshot>>
  selectContext(String projectId);

  Future<ManagementReportResult<List<ManagementReportSnapshotSummary>>>
  listSnapshots(String projectId);

  Future<ManagementReportResult<ManagementReportSnapshot>> readSnapshot({
    required String projectId,
    required ManagementReportSnapshotSummary summary,
  });

  Future<void> close();
}

enum ManagementReportFailureCode {
  notConfigured,
  unauthorized,
  notFound,
  untrusted,
  networkUnavailable,
  invalidResponse,
  serverRejected,
}

sealed class ManagementReportResult<T> {
  const ManagementReportResult();
}

final class ManagementReportSuccess<T> extends ManagementReportResult<T> {
  const ManagementReportSuccess(this.value);

  final T value;
}

final class ManagementReportRejected<T> extends ManagementReportResult<T> {
  const ManagementReportRejected(this.code);

  final ManagementReportFailureCode code;
}

final class ManagementAnalysisContextSnapshot {
  ManagementAnalysisContextSnapshot({
    required this.current,
    required List<ManagementAnalysisContext> available,
  }) : available = List.unmodifiable(available);

  final ManagementAnalysisContext? current;
  final List<ManagementAnalysisContext> available;
}

final class ManagementAnalysisContext {
  const ManagementAnalysisContext({
    required this.organizationId,
    required this.organizationName,
    required this.projectId,
    required this.projectName,
  });

  final String organizationId;
  final String organizationName;
  final String projectId;
  final String projectName;
}

final class ManagementReportSnapshotSummary {
  const ManagementReportSnapshotSummary({
    required this.snapshotId,
    required this.reportId,
    required this.reportVersion,
    required this.reportingTimeZone,
    required this.dataCutoffUtc,
    required this.releasedAtUtc,
  });

  final String snapshotId;
  final String reportId;
  final int reportVersion;
  final String reportingTimeZone;
  final DateTime dataCutoffUtc;
  final DateTime releasedAtUtc;
}

final class ManagementReportSnapshot {
  const ManagementReportSnapshot({required this.summary, required this.report});

  final ManagementReportSnapshotSummary summary;
  final ProtectedManagementReport report;
}

final class ProtectedManagementReport {
  ProtectedManagementReport({
    required this.reportId,
    required this.reportVersion,
    required this.metricId,
    required this.metricVersion,
    required this.dimension,
    required this.queryFingerprint,
    required this.privacyPolicy,
    required this.sourceScope,
    required this.projectId,
    required this.periodBoundaryId,
    required this.reportingTimeZone,
    required this.dataCutoffUtc,
    required this.previousPeriod,
    required this.currentPeriod,
    required List<ProtectedManagementReportCell> cells,
  }) : cells = List.unmodifiable(cells);

  final String reportId;
  final int reportVersion;
  final String metricId;
  final int metricVersion;
  final String dimension;
  final String queryFingerprint;
  final String privacyPolicy;
  final String sourceScope;
  final String projectId;
  final String periodBoundaryId;
  final String reportingTimeZone;
  final DateTime dataCutoffUtc;
  final ManagementReportPeriod previousPeriod;
  final ManagementReportPeriod currentPeriod;
  final List<ProtectedManagementReportCell> cells;
}

final class ManagementReportPeriod {
  const ManagementReportPeriod({
    required this.startUtc,
    required this.untilUtc,
  });

  final DateTime startUtc;
  final DateTime untilUtc;
}

enum ManagementReportPeriodKey { previous, current }

enum ManagementReportPrivacyStatus { displayed, suppressed }

final class ProtectedManagementReportCell {
  const ProtectedManagementReportCell({
    required this.periodKey,
    required this.categoryKey,
    required this.cellOrder,
    required this.valueCount,
    required this.privacyStatus,
  });

  final ManagementReportPeriodKey periodKey;
  final String categoryKey;
  final int cellOrder;
  final int? valueCount;
  final ManagementReportPrivacyStatus privacyStatus;
}

final class DeferredManagementReportGateway implements ManagementReportGateway {
  const DeferredManagementReportGateway();

  @override
  Future<void> close() async {}

  @override
  Future<ManagementReportResult<ManagementAnalysisContextSnapshot>>
  loadContext() async =>
      const ManagementReportRejected(ManagementReportFailureCode.notConfigured);

  @override
  Future<ManagementReportResult<List<ManagementReportSnapshotSummary>>>
  listSnapshots(String projectId) async =>
      const ManagementReportRejected(ManagementReportFailureCode.notConfigured);

  @override
  Future<ManagementReportResult<ManagementReportSnapshot>> readSnapshot({
    required String projectId,
    required ManagementReportSnapshotSummary summary,
  }) async =>
      const ManagementReportRejected(ManagementReportFailureCode.notConfigured);

  @override
  Future<ManagementReportResult<ManagementAnalysisContextSnapshot>>
  selectContext(String projectId) async =>
      const ManagementReportRejected(ManagementReportFailureCode.notConfigured);
}
