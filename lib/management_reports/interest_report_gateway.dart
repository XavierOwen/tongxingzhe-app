import 'dart:collection';

/// 独立的 interest 管理报告读取边界。
///
/// 该接口只返回当前调用期间内存中的 typed 结果。它不提供“最新”推断，也不
/// 连接 Drift、文件、secure storage、outbox 或后台同步。
abstract interface class InterestReportGateway {
  /// 读取服务端已经排序且有界的显式快照目录。
  Future<InterestReportResult<InterestReportSnapshotDirectory>> listSnapshots(
    String projectId,
  );

  /// 读取目录返回的显式 [summary] 所指向的单份快照。
  Future<InterestReportResult<InterestReportSnapshot>> readSnapshot({
    required String projectId,
    required InterestReportSnapshotSummary summary,
  });

  Future<void> close();
}

enum InterestReportFailureCode {
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

sealed class InterestReportResult<T> {
  const InterestReportResult();
}

final class InterestReportSuccess<T> extends InterestReportResult<T> {
  const InterestReportSuccess(this.value);

  final T value;
}

final class InterestReportRejected<T> extends InterestReportResult<T> {
  const InterestReportRejected(this.code);

  final InterestReportFailureCode code;
}

final class InterestReportSnapshotDirectory {
  InterestReportSnapshotDirectory({
    required this.accessEventId,
    required this.projectId,
    required List<InterestReportSnapshotSummary> snapshots,
  }) : snapshots = UnmodifiableListView(
         List<InterestReportSnapshotSummary>.of(snapshots),
       );

  final String accessEventId;
  final String projectId;
  final List<InterestReportSnapshotSummary> snapshots;
}

/// 目录中的六字段摘要，也是 detail 请求唯一允许使用的快照坐标。
final class InterestReportSnapshotSummary {
  const InterestReportSnapshotSummary({
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

final class InterestReportSnapshot {
  const InterestReportSnapshot({
    required this.accessEventId,
    required this.summary,
    required this.report,
  });

  final String accessEventId;
  final InterestReportSnapshotSummary summary;
  final InterestReportDocument report;
}

final class InterestReportDocument {
  InterestReportDocument({
    required this.reportId,
    required this.reportVersion,
    required this.metricId,
    required this.metricVersion,
    required this.statisticalUnit,
    required this.dimension,
    required this.queryFingerprint,
    required this.privacyPolicy,
    required this.sourceScope,
    required this.projectId,
    required this.periods,
    required List<InterestReportCell> cells,
  }) : cells = UnmodifiableListView(List<InterestReportCell>.of(cells));

  final String reportId;
  final int reportVersion;
  final String metricId;
  final int metricVersion;
  final String statisticalUnit;
  final String dimension;
  final String queryFingerprint;
  final String privacyPolicy;
  final String sourceScope;
  final String projectId;
  final InterestReportPeriods periods;
  final List<InterestReportCell> cells;
}

final class InterestReportPeriods {
  const InterestReportPeriods({
    required this.periodBoundaryId,
    required this.reportingTimeZone,
    required this.dataCutoffUtc,
    required this.previousPeriod,
    required this.currentPeriod,
  });

  final String periodBoundaryId;
  final String reportingTimeZone;
  final DateTime dataCutoffUtc;
  final InterestReportPeriod previousPeriod;
  final InterestReportPeriod currentPeriod;
}

final class InterestReportPeriod {
  const InterestReportPeriod({required this.startUtc, required this.untilUtc});

  final DateTime startUtc;
  final DateTime untilUtc;
}

enum InterestReportPeriodKey { previous, current }

enum InterestReportPrivacyStatus { displayed, suppressed }

final class InterestReportCell {
  const InterestReportCell({
    required this.periodKey,
    required this.interestLevel,
    required this.cellOrder,
    required this.valueCount,
    required this.privacyStatus,
  });

  final InterestReportPeriodKey periodKey;
  final int interestLevel;
  final int cellOrder;
  final int? valueCount;
  final InterestReportPrivacyStatus privacyStatus;
}

/// 构建配置没有 Backend 时的显式降级结果；不会尝试访问网络。
final class DeferredInterestReportGateway implements InterestReportGateway {
  const DeferredInterestReportGateway();

  @override
  Future<void> close() async {}

  @override
  Future<InterestReportResult<InterestReportSnapshotDirectory>> listSnapshots(
    String projectId,
  ) async =>
      const InterestReportRejected(InterestReportFailureCode.notConfigured);

  @override
  Future<InterestReportResult<InterestReportSnapshot>> readSnapshot({
    required String projectId,
    required InterestReportSnapshotSummary summary,
  }) async =>
      const InterestReportRejected(InterestReportFailureCode.notConfigured);
}
