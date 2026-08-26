import 'dart:collection';

/// 后续联系同意占比管理报告的 Flutter 读取边界。
///
/// 该接口只读取服务端已经授权并严格验证过的目录或显式快照。实现不得在
/// 客户端选择“最新”快照、重新计算比例，或把结果写入 Drift、文件、secure
/// storage、outbox、离线缓存或同步队列。
abstract interface class FollowUpConsentRatioReportGateway {
  /// 读取指定项目的有界快照目录。
  Future<
    FollowUpConsentRatioReportResult<
      FollowUpConsentRatioReportSnapshotDirectory
    >
  >
  listSnapshots(String projectId);

  /// 读取目录中调用方明确选择的单份快照。
  Future<FollowUpConsentRatioReportResult<FollowUpConsentRatioReportSnapshot>>
  readSnapshot({
    required String projectId,
    required FollowUpConsentRatioReportSnapshotSummary summary,
  });

  /// 关闭实现拥有的 HTTP 资源；重复关闭必须安全。
  Future<void> close();
}

/// Flutter 调用方可以处理的稳定失败分类。
enum FollowUpConsentRatioReportFailureCode {
  /// 构建配置没有可用的 Backend。
  notConfigured,

  /// 项目、快照或目录摘要不符合固定请求合同。
  invalidRequest,

  /// 没有有效身份，或身份刷新失败。
  unauthorized,

  /// 身份有效，但没有读取该报告的权限。
  forbidden,

  /// 显式项目或快照不存在。
  notFound,

  /// 服务端报告 provenance 不可信。
  untrusted,

  /// 服务端暂时不可用。
  serviceUnavailable,

  /// 请求超时或无法建立网络连接。
  networkUnavailable,

  /// 响应不是固定的 JSON typed 合同。
  invalidResponse,

  /// 服务端返回了其他未细分的拒绝状态。
  serverRejected,

  /// gateway 已关闭；调用方应丢弃它并重新建立边界。
  closed,
}

/// 成功或稳定失败的 typed gateway 结果。
sealed class FollowUpConsentRatioReportResult<T> {
  const FollowUpConsentRatioReportResult();
}

/// 已严格解析、只存在于当前调用内存中的结果。
final class FollowUpConsentRatioReportSuccess<T>
    extends FollowUpConsentRatioReportResult<T> {
  const FollowUpConsentRatioReportSuccess(this.value);

  final T value;
}

/// 不携带响应正文、数据库消息或其他敏感详情的失败结果。
final class FollowUpConsentRatioReportRejected<T>
    extends FollowUpConsentRatioReportResult<T> {
  const FollowUpConsentRatioReportRejected(this.code);

  final FollowUpConsentRatioReportFailureCode code;
}

/// 服务端返回的三字段后续联系同意占比快照目录。
final class FollowUpConsentRatioReportSnapshotDirectory {
  FollowUpConsentRatioReportSnapshotDirectory({
    required this.accessEventId,
    required this.projectId,
    required List<FollowUpConsentRatioReportSnapshotSummary> snapshots,
  }) : snapshots = UnmodifiableListView(
         List<FollowUpConsentRatioReportSnapshotSummary>.of(snapshots),
       );

  /// 本次读取的 value-free 访问事件 ID。
  final String accessEventId;

  /// 目录所属的显式项目 ID。
  final String projectId;

  /// 服务端排序后的不可修改摘要集合；可为空，最多 20 项。
  final List<FollowUpConsentRatioReportSnapshotSummary> snapshots;
}

/// 目录中的六字段摘要，也是详情请求唯一允许使用的快照坐标。
final class FollowUpConsentRatioReportSnapshotSummary {
  const FollowUpConsentRatioReportSnapshotSummary({
    required this.snapshotId,
    required this.reportId,
    required this.reportVersion,
    required this.reportingTimeZone,
    required this.dataCutoffUtc,
    required this.releasedAtUtc,
  });

  /// 快照 ID。
  final String snapshotId;

  /// 固定的后续联系同意占比报告 ID。
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

/// HTTP 详情返回的快照 envelope 与固定保护报告。
final class FollowUpConsentRatioReportSnapshot {
  const FollowUpConsentRatioReportSnapshot({
    required this.accessEventId,
    required this.summary,
    required this.report,
  });

  /// 本次详情读取的 value-free 访问事件 ID。
  final String accessEventId;

  /// 发起详情请求时明确选择的目录摘要。
  final FollowUpConsentRatioReportSnapshotSummary summary;

  /// 已通过固定 consent-ratio 合同解析的报告。
  final FollowUpConsentRatioReportDocument report;
}

/// 固定的两期后续联系同意占比保护报告。
///
/// 报告中的 ratio 和 coverage 已由服务端执行匿名阈值与贡献者保护；客户端
/// 只保存显示值或 null，不从互补格、总量或其他字段推断被抑制值。
final class FollowUpConsentRatioReportDocument {
  FollowUpConsentRatioReportDocument({
    required this.reportId,
    required this.reportVersion,
    required this.metricId,
    required this.metricVersion,
    required this.statisticalUnit,
    required this.dimension,
    required this.periodGrain,
    required this.comparisonPeriodCount,
    required this.periodBoundaryId,
    required this.privacyPolicy,
    required this.queryFingerprint,
    required this.sourceScope,
    required this.projectId,
    required this.resultStatus,
    required this.periods,
    required List<FollowUpConsentRatioReportPeriodResult> periodResults,
  }) : periodResults = UnmodifiableListView(
         List<FollowUpConsentRatioReportPeriodResult>.of(periodResults),
       );

  /// 固定的报告 ID。
  final String reportId;

  /// 报告版本。
  final int reportVersion;

  /// 固定的指标 ID。
  final String metricId;

  /// 指标版本。
  final int metricVersion;

  /// 统计单位，固定为 contact-target link。
  final String statisticalUnit;

  /// 报告维度，固定为 consent state。
  final String dimension;

  /// 期间粒度，固定为 week。
  final String periodGrain;

  /// 比较期间数量，固定为 2。
  final int comparisonPeriodCount;

  /// 期间边界合同 ID。
  final String periodBoundaryId;

  /// 固定的隐私政策 ID。
  final String privacyPolicy;

  /// 服务端固定的查询指纹。
  final String queryFingerprint;

  /// 报告使用的数据来源范围说明。
  final String sourceScope;

  /// 报告所属的显式项目 ID。
  final String projectId;

  /// 固定的完成状态。
  final String resultStatus;

  /// 两个相邻完整期间及其报告时区。
  final FollowUpConsentRatioReportPeriods periods;

  /// 按服务端顺序保存的两个不可修改期间结果。
  final List<FollowUpConsentRatioReportPeriodResult> periodResults;
}

/// 后续联系同意占比报告的两个相邻完整期间。
final class FollowUpConsentRatioReportPeriods {
  const FollowUpConsentRatioReportPeriods({
    required this.periodBoundaryId,
    required this.reportingTimeZone,
    required this.dataCutoffUtc,
    required this.previousPeriod,
    required this.currentPeriod,
  });

  final String periodBoundaryId;
  final String reportingTimeZone;
  final DateTime dataCutoffUtc;
  final FollowUpConsentRatioReportPeriod previousPeriod;
  final FollowUpConsentRatioReportPeriod currentPeriod;
}

/// 一个完整报告期间的 UTC 半开区间。
final class FollowUpConsentRatioReportPeriod {
  const FollowUpConsentRatioReportPeriod({
    required this.startUtc,
    required this.untilUtc,
  });

  /// 期间开始时间，包含此时刻。
  final DateTime startUtc;

  /// 期间结束时间，不包含此时刻。
  final DateTime untilUtc;
}

/// 报告期间在固定响应中的顺序。
enum FollowUpConsentRatioReportPeriodKey { previous, current }

/// ratio 或 coverage cell 的隐私显示状态。
enum FollowUpConsentRatioReportPrivacyStatus { displayed, suppressed }

/// 一个期间的 ratio 与 coverage 结果。
final class FollowUpConsentRatioReportPeriodResult {
  FollowUpConsentRatioReportPeriodResult({
    required this.periodKey,
    required this.periodOrder,
    required this.ratio,
    required List<FollowUpConsentRatioReportCoverageCell> coverage,
    required this.unknownCount,
    required this.excludedCount,
  }) : coverage = UnmodifiableListView(
         List<FollowUpConsentRatioReportCoverageCell>.of(coverage),
       );

  final FollowUpConsentRatioReportPeriodKey periodKey;
  final int periodOrder;
  final FollowUpConsentRatioReportRatio ratio;
  final List<FollowUpConsentRatioReportCoverageCell> coverage;

  /// 固定为 0；未知回答作为 unanswered coverage，而不是 ratio 分母。
  final int unknownCount;

  /// 固定为 0；该报告不把排除数混入 ratio。
  final int excludedCount;
}

/// 一个期间的 yes／no ratio。抑制时所有数值字段均为 null。
final class FollowUpConsentRatioReportRatio {
  const FollowUpConsentRatioReportRatio({
    required this.privacyStatus,
    required this.yesCount,
    required this.noCount,
    required this.numerator,
    required this.denominator,
    required this.percentageBasisPoints,
  });

  final FollowUpConsentRatioReportPrivacyStatus privacyStatus;
  final int? yesCount;
  final int? noCount;
  final int? numerator;
  final int? denominator;
  final int? percentageBasisPoints;
}

/// 一个期间的未回答／拒绝／不适用 coverage cell。
final class FollowUpConsentRatioReportCoverageCell {
  const FollowUpConsentRatioReportCoverageCell({
    required this.consentState,
    required this.cellOrder,
    required this.valueCount,
    required this.privacyStatus,
  });

  final String consentState;
  final int cellOrder;
  final int? valueCount;
  final FollowUpConsentRatioReportPrivacyStatus privacyStatus;
}

/// 构建配置没有 Backend 时的显式降级结果；不会尝试访问网络。
final class DeferredFollowUpConsentRatioReportGateway
    implements FollowUpConsentRatioReportGateway {
  const DeferredFollowUpConsentRatioReportGateway();

  @override
  Future<void> close() async {}

  @override
  Future<
    FollowUpConsentRatioReportResult<
      FollowUpConsentRatioReportSnapshotDirectory
    >
  >
  listSnapshots(String projectId) async =>
      const FollowUpConsentRatioReportRejected(
        FollowUpConsentRatioReportFailureCode.notConfigured,
      );

  @override
  Future<FollowUpConsentRatioReportResult<FollowUpConsentRatioReportSnapshot>>
  readSnapshot({
    required String projectId,
    required FollowUpConsentRatioReportSnapshotSummary summary,
  }) async => const FollowUpConsentRatioReportRejected(
    FollowUpConsentRatioReportFailureCode.notConfigured,
  );
}
