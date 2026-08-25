import 'dart:collection';

/// 独立的 original-region 管理报告读取边界。
///
/// 该接口只返回当前调用期间内存中的 typed 结果。它不推断 current、latest
/// 或未被取代，也不连接 Drift、文件、secure storage、outbox 或后台同步。
abstract interface class OriginalRegionReportGateway {
  /// 读取服务端已经排序且有界的显式快照目录。
  Future<OriginalRegionReportResult<OriginalRegionReportSnapshotDirectory>>
  listSnapshots(String projectId);

  /// 读取目录返回的显式 [summary] 所指向的单份快照。
  Future<OriginalRegionReportResult<OriginalRegionReportSnapshot>>
  readSnapshot({
    required String projectId,
    required OriginalRegionReportSnapshotSummary summary,
  });

  /// 关闭此读取边界拥有的网络资源。
  Future<void> close();
}

/// Original-region gateway 对调用方公开的稳定失败分类。
enum OriginalRegionReportFailureCode {
  /// 构建配置没有可用的 Backend。
  notConfigured,

  /// 调用方提供的项目、快照或摘要不符合请求合同。
  invalidRequest,

  /// 身份不存在、失效或刷新失败。
  unauthorized,

  /// 身份存在，但没有报告读取权限。
  forbidden,

  /// 指定的项目或快照不存在。
  notFound,

  /// 服务端返回的快照 provenance 不可信。
  untrusted,

  /// 服务端返回稳定的不可用状态。
  serviceUnavailable,

  /// 网络请求超时或无法建立连接。
  networkUnavailable,

  /// 响应不是固定的 typed 合同。
  invalidResponse,

  /// 服务端以其他非成功状态拒绝请求。
  serverRejected,
}

/// Original-region gateway 的成功或失败结果。
sealed class OriginalRegionReportResult<T> {
  const OriginalRegionReportResult();
}

/// 包含已严格解析、只保存在内存中的 original-region 结果。
final class OriginalRegionReportSuccess<T>
    extends OriginalRegionReportResult<T> {
  const OriginalRegionReportSuccess(this.value);

  /// 已验证的 typed 值。
  final T value;
}

/// 不携带部分响应或服务端详情的稳定失败结果。
final class OriginalRegionReportRejected<T>
    extends OriginalRegionReportResult<T> {
  const OriginalRegionReportRejected(this.code);

  /// 调用方可以处理的失败分类。
  final OriginalRegionReportFailureCode code;
}

/// 服务端返回的有界 original-region 快照目录。
final class OriginalRegionReportSnapshotDirectory {
  OriginalRegionReportSnapshotDirectory({
    required this.accessEventId,
    required this.projectId,
    required List<OriginalRegionReportSnapshotSummary> snapshots,
  }) : snapshots = UnmodifiableListView(
         List<OriginalRegionReportSnapshotSummary>.of(snapshots),
       );

  /// 本次目录读取的 value-free 访问事件 ID。
  final String accessEventId;

  /// 目录所属的显式项目 ID。
  final String projectId;

  /// 服务端排序后的不可修改摘要集合。
  final List<OriginalRegionReportSnapshotSummary> snapshots;
}

/// 目录中的六字段摘要，也是详情请求唯一允许使用的快照坐标。
final class OriginalRegionReportSnapshotSummary {
  const OriginalRegionReportSnapshotSummary({
    required this.snapshotId,
    required this.reportId,
    required this.reportVersion,
    required this.reportingTimeZone,
    required this.dataCutoffUtc,
    required this.releasedAtUtc,
  });

  /// 快照 ID。
  final String snapshotId;

  /// 固定的 original-region 报告 ID。
  final String reportId;

  /// 固定的报告版本。
  final int reportVersion;

  /// 报告使用的 IANA 时区名称。
  final String reportingTimeZone;

  /// 报告数据截止时间，已规范化为 UTC。
  final DateTime dataCutoffUtc;

  /// 快照发布时间，已规范化为 UTC。
  final DateTime releasedAtUtc;
}

/// 一次详情读取返回的快照和完整 original-region 保护报告。
final class OriginalRegionReportSnapshot {
  const OriginalRegionReportSnapshot({
    required this.accessEventId,
    required this.summary,
    required this.report,
  });

  /// 本次详情读取的 value-free 访问事件 ID。
  final String accessEventId;

  /// 发起详情请求时明确选择的目录摘要。
  final OriginalRegionReportSnapshotSummary summary;

  /// 已通过固定 6BJ 合同解析的报告。
  final OriginalRegionReportDocument report;
}

/// 6BJ 返回的 17-key original-region 报告。
///
/// 该类型保留服务端已保护的城市格和最小 provenance 元数据；它不计算、
/// 聚合或补全任何报告值。
final class OriginalRegionReportDocument {
  OriginalRegionReportDocument({
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
    required this.sourceTreeContext,
    required this.resultStatus,
    required List<OriginalRegionReportCell> cells,
  }) : cells = UnmodifiableListView(List<OriginalRegionReportCell>.of(cells));

  /// 固定的 original-region 报告 ID。
  final String reportId;

  /// 固定的报告版本。
  final int reportVersion;

  /// 指标 ID。
  final String metricId;

  /// 指标版本。
  final int metricVersion;

  /// 报告维度。
  final String dimension;

  /// 报告视图模式，固定为 original。
  final String viewMode;

  /// 区域粒度，固定为 city。
  final String regionGranularity;

  /// 服务端固定的查询指纹。
  final String queryFingerprint;

  /// 服务端固定的隐私政策 ID。
  final String privacyPolicy;

  /// 报告使用的数据来源范围说明。
  final String sourceScope;

  /// 报告所属的显式项目 ID。
  final String projectId;

  /// 两个相邻完整期间及其报告时区。
  final OriginalRegionReportPeriods periods;

  /// 报告数据截止时间，已规范化为 UTC。
  final DateTime dataCutoffUtc;

  /// 报告使用的来源变化序号。
  final int sourceChangeSequence;

  /// 报告唯一来源树的最小上下文。
  final OriginalRegionReportSourceTreeContext sourceTreeContext;

  /// 服务端报告状态。
  final String resultStatus;

  /// 按服务端顺序保存的不可修改城市格集合。
  final List<OriginalRegionReportCell> cells;
}

/// original-region 报告的两个相邻完整期间。
final class OriginalRegionReportPeriods {
  const OriginalRegionReportPeriods({
    required this.periodBoundaryId,
    required this.reportingTimeZone,
    required this.dataCutoffUtc,
    required this.previousPeriod,
    required this.currentPeriod,
  });

  /// 期间边界合同 ID。
  final String periodBoundaryId;

  /// 两个期间使用的 IANA 时区名称。
  final String reportingTimeZone;

  /// 期间解析使用的数据截止时间，已规范化为 UTC。
  final DateTime dataCutoffUtc;

  /// 较早的完整期间。
  final OriginalRegionReportPeriod previousPeriod;

  /// 较晚的完整期间。
  final OriginalRegionReportPeriod currentPeriod;
}

/// 一个完整报告期间的 UTC 半开区间。
final class OriginalRegionReportPeriod {
  const OriginalRegionReportPeriod({
    required this.startUtc,
    required this.untilUtc,
  });

  /// 期间开始时间，包含此时刻。
  final DateTime startUtc;

  /// 期间结束时间，不包含此时刻。
  final DateTime untilUtc;
}

/// original-region 报告的唯一来源树上下文。
final class OriginalRegionReportSourceTreeContext {
  const OriginalRegionReportSourceTreeContext({
    required this.contractId,
    required this.resultStatus,
    required this.reasonCode,
    required this.sourceTreeVersion,
    required this.sourceContentFingerprint,
  });

  /// 来源树上下文合同 ID。
  final String contractId;

  /// 来源树选择状态。
  final String resultStatus;

  /// 来源树选择原因代码。
  final String reasonCode;

  /// 已发布的来源树版本。
  final String sourceTreeVersion;

  /// 来源树内容指纹。
  final String sourceContentFingerprint;
}

/// original-region 城市格所属的两个报告期间。
enum OriginalRegionReportPeriodKey { previous, current }

/// 城市格的隐私显示状态。
enum OriginalRegionReportPrivacyStatus { displayed, suppressed }

/// 一个 original-region 城市格。
final class OriginalRegionReportCell {
  const OriginalRegionReportCell({
    required this.periodKey,
    required this.cityId,
    required this.cellOrder,
    required this.valueCount,
    required this.privacyStatus,
  });

  /// 城市格所属的较早或较晚期间。
  final OriginalRegionReportPeriodKey periodKey;

  /// 服务端稳定的城市 ID；不代表可显示的城市名称。
  final String cityId;

  /// 完整城市格在报告中的连续顺序。
  final int cellOrder;

  /// 已显示的安全整数；隐藏格必须为 null。
  final int? valueCount;

  /// 该格是已显示还是已抑制。
  final OriginalRegionReportPrivacyStatus privacyStatus;
}

/// 构建配置没有 Backend 时的显式降级结果；不会尝试访问网络。
final class DeferredOriginalRegionReportGateway
    implements OriginalRegionReportGateway {
  const DeferredOriginalRegionReportGateway();

  @override
  Future<void> close() async {}

  @override
  Future<OriginalRegionReportResult<OriginalRegionReportSnapshotDirectory>>
  listSnapshots(String projectId) async => const OriginalRegionReportRejected(
    OriginalRegionReportFailureCode.notConfigured,
  );

  @override
  Future<OriginalRegionReportResult<OriginalRegionReportSnapshot>>
  readSnapshot({
    required String projectId,
    required OriginalRegionReportSnapshotSummary summary,
  }) async => const OriginalRegionReportRejected(
    OriginalRegionReportFailureCode.notConfigured,
  );
}
