import 'dart:collection';

/// 独立的 current-city 管理报告读取边界。
///
/// 该接口只返回当前调用期间内存中的 typed 结果。它不提供“最新”推断，也不
/// 连接 Drift、文件、secure storage、outbox 或后台同步。
abstract interface class CurrentCityReportGateway {
  /// 读取服务端已经排序且有界的显式快照目录。
  Future<CurrentCityReportResult<CurrentCityReportSnapshotDirectory>>
  listSnapshots(String projectId);

  /// 读取目录返回的显式 [summary] 所指向的单份快照。
  Future<CurrentCityReportResult<CurrentCityReportSnapshot>> readSnapshot({
    required String projectId,
    required CurrentCityReportSnapshotSummary summary,
  });

  Future<void> close();
}

enum CurrentCityReportFailureCode {
  notConfigured,
  invalidRequest,
  unauthorized,
  forbidden,
  notFound,
  untrusted,
  serviceUnavailable,
  networkUnavailable,
  invalidResponse,
  serverRejected,
}

sealed class CurrentCityReportResult<T> {
  const CurrentCityReportResult();
}

final class CurrentCityReportSuccess<T> extends CurrentCityReportResult<T> {
  const CurrentCityReportSuccess(this.value);

  final T value;
}

final class CurrentCityReportRejected<T> extends CurrentCityReportResult<T> {
  const CurrentCityReportRejected(this.code);

  final CurrentCityReportFailureCode code;
}

final class CurrentCityReportSnapshotDirectory {
  CurrentCityReportSnapshotDirectory({
    required this.accessEventId,
    required this.projectId,
    required List<CurrentCityReportSnapshotSummary> snapshots,
  }) : snapshots = UnmodifiableListView(
         List<CurrentCityReportSnapshotSummary>.of(snapshots),
       );

  final String accessEventId;
  final String projectId;
  final List<CurrentCityReportSnapshotSummary> snapshots;
}

/// 目录中的六字段摘要，也是 detail 请求唯一允许使用的快照坐标。
final class CurrentCityReportSnapshotSummary {
  const CurrentCityReportSnapshotSummary({
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

final class CurrentCityReportSnapshot {
  const CurrentCityReportSnapshot({
    required this.accessEventId,
    required this.summary,
    required this.report,
  });

  final String accessEventId;
  final CurrentCityReportSnapshotSummary summary;
  final CurrentCityReportDocument report;
}

final class CurrentCityReportDocument {
  CurrentCityReportDocument({
    required this.reportId,
    required this.reportVersion,
    required this.metricId,
    required this.metricVersion,
    required this.dimension,
    required this.viewMode,
    required this.regionGranularity,
    required this.queryFingerprint,
    required this.privacyPolicy,
    required this.sourceScope,
    required this.projectId,
    required this.periods,
    required this.dataCutoffUtc,
    required this.sourceChangeSequence,
    required this.targetContext,
    required this.resultStatus,
    required List<CurrentCityReportCell> cells,
  }) : cells = UnmodifiableListView(List<CurrentCityReportCell>.of(cells));

  final String reportId;
  final int reportVersion;
  final String metricId;
  final int metricVersion;
  final String dimension;
  final String viewMode;
  final String regionGranularity;
  final String queryFingerprint;
  final String privacyPolicy;
  final String sourceScope;
  final String projectId;
  final CurrentCityReportPeriods periods;
  final DateTime dataCutoffUtc;
  final int sourceChangeSequence;
  final CurrentCityReportTargetContext targetContext;
  final String resultStatus;
  final List<CurrentCityReportCell> cells;
}

final class CurrentCityReportPeriods {
  const CurrentCityReportPeriods({
    required this.periodBoundaryId,
    required this.reportingTimeZone,
    required this.dataCutoffUtc,
    required this.previousPeriod,
    required this.currentPeriod,
  });

  final String periodBoundaryId;
  final String reportingTimeZone;
  final DateTime dataCutoffUtc;
  final CurrentCityReportPeriod previousPeriod;
  final CurrentCityReportPeriod currentPeriod;
}

final class CurrentCityReportPeriod {
  const CurrentCityReportPeriod({
    required this.startUtc,
    required this.untilUtc,
  });

  final DateTime startUtc;
  final DateTime untilUtc;
}

final class CurrentCityReportTargetContext {
  const CurrentCityReportTargetContext({
    required this.contractId,
    required this.resultStatus,
    required this.reasonCode,
    required this.dataCutoffUtc,
    required this.targetTreeVersion,
    required this.targetContentFingerprint,
    required this.selectionSequence,
    required this.selectionSource,
    required this.selectionEvidenceAtUtc,
    required this.treePublishedAtUtc,
  });

  final String contractId;
  final String resultStatus;
  final String reasonCode;
  final DateTime dataCutoffUtc;
  final String targetTreeVersion;
  final String targetContentFingerprint;
  final int selectionSequence;
  final String selectionSource;
  final DateTime selectionEvidenceAtUtc;
  final DateTime treePublishedAtUtc;
}

enum CurrentCityReportPeriodKey { previous, current }

enum CurrentCityReportPrivacyStatus { displayed, suppressed }

final class CurrentCityReportCell {
  const CurrentCityReportCell({
    required this.periodKey,
    required this.cityId,
    required this.cellOrder,
    required this.valueCount,
    required this.privacyStatus,
  });

  final CurrentCityReportPeriodKey periodKey;
  final String cityId;
  final int cellOrder;
  final int? valueCount;
  final CurrentCityReportPrivacyStatus privacyStatus;
}

/// 构建配置没有 Backend 时的显式降级结果；不会尝试访问网络。
final class DeferredCurrentCityReportGateway
    implements CurrentCityReportGateway {
  const DeferredCurrentCityReportGateway();

  @override
  Future<void> close() async {}

  @override
  Future<CurrentCityReportResult<CurrentCityReportSnapshotDirectory>>
  listSnapshots(String projectId) async => const CurrentCityReportRejected(
    CurrentCityReportFailureCode.notConfigured,
  );

  @override
  Future<CurrentCityReportResult<CurrentCityReportSnapshot>> readSnapshot({
    required String projectId,
    required CurrentCityReportSnapshotSummary summary,
  }) async => const CurrentCityReportRejected(
    CurrentCityReportFailureCode.notConfigured,
  );
}
