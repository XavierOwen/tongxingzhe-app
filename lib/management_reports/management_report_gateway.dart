import 'dart:collection';

/// Flutter 读取管理分析项目、可信快照目录和受保护报告的唯一接口。
///
/// 该接口不暴露 bearer token、授权关系或客户端隐私计算。每次调用都由远端
/// 重新授权；实现也不得把管理报告写入离线缓存。
abstract interface class ManagementReportGateway {
  /// 重新授权并读取可用项目和已保存的管理导航选择。
  Future<ManagementReportResult<ManagementAnalysisContextSnapshot>>
  loadContext();

  /// 把来自 [loadContext] 的项目 ID 保存为导航选择；选择本身不授予报告权限。
  Future<ManagementReportResult<ManagementAnalysisContextSnapshot>>
  selectContext(String projectId);

  /// 重新授权并读取显式 [projectId] 的有界目录；返回顺序不代表“当前有效”。
  Future<ManagementReportResult<List<ManagementReportSnapshotSummary>>>
  listSnapshots(String projectId);

  /// 重新授权并读取 [summary] 指定的报告。
  ///
  /// 6L 单份响应没有发布时间，因此实现必须把目录摘要与报告逐项对照，不能自行
  /// 补造该时间。成功结果只存在于调用方内存，不得写入离线缓存。
  Future<ManagementReportResult<ManagementReportSnapshot>> readSnapshot({
    required String projectId,
    required ManagementReportSnapshotSummary summary,
  });

  /// 重新授权并取得 [summary] 指定快照的固定 canonical JSON v1 字节。
  ///
  /// 成功结果只表示客户端已验证服务端准备交付的内存 artifact。它不表示文件已经
  /// 下载、落盘、打开或分享，也不得由 gateway 写入离线缓存。
  Future<ManagementReportResult<ManagementReportExportArtifact>>
  exportSnapshot({
    required String projectId,
    required ManagementReportSnapshotSummary summary,
  });

  Future<void> close();
}

/// 固定报告的协议坐标顺序。HTTP 解码和宽屏表格共同使用这一份定义，避免两边漂移。
const managementReportCategoryKeys = <String>[
  'all',
  'face_to_face',
  'voice_call',
  'video_call',
  'instant_text',
  'asynchronous_message',
  'mixed',
  'other_direct',
];

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

/// 服务端生成并由 Flutter 严格验证的固定管理报告导出 artifact。
///
/// [bytes] 保留服务端 canonical JSON v1 原始字节，不由客户端重新序列化。
/// 该对象只存在于内存；后续平台交付必须通过独立 capability adapter。
final class ManagementReportExportArtifact {
  ManagementReportExportArtifact({
    required List<int> bytes,
    required this.fileName,
    required this.contentType,
    required this.exportEventId,
    required this.snapshot,
  }) : bytes = UnmodifiableListView(List<int>.of(bytes));

  final List<int> bytes;
  final String fileName;
  final String contentType;
  final String exportEventId;
  final ManagementReportSnapshot snapshot;
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
  Future<ManagementReportResult<ManagementReportExportArtifact>>
  exportSnapshot({
    required String projectId,
    required ManagementReportSnapshotSummary summary,
  }) async =>
      const ManagementReportRejected(ManagementReportFailureCode.notConfigured);

  @override
  Future<ManagementReportResult<ManagementAnalysisContextSnapshot>>
  selectContext(String projectId) async =>
      const ManagementReportRejected(ManagementReportFailureCode.notConfigured);
}
