/// 当前账号具有有效成员关系的一个组织。
final class OrganizationDirectoryEntry {
  const OrganizationDirectoryEntry({
    required this.organizationWorkspaceId,
    required this.organizationName,
  });

  final String organizationWorkspaceId;
  final String organizationName;
}

/// 组织目录读取的稳定失败分类。
enum OrganizationDirectoryFailureCode {
  notConfigured,
  unauthorized,
  invalidRequest,
  forbidden,
  serviceUnavailable,
  networkUnavailable,
  invalidResponse,
}

/// 组织目录的类型化读取结果。
sealed class OrganizationDirectoryResult {
  const OrganizationDirectoryResult();
}

/// 目录读取成功。列表保留 Backend 顺序与同名项，且不可修改。
final class OrganizationDirectorySuccess extends OrganizationDirectoryResult {
  OrganizationDirectorySuccess(List<OrganizationDirectoryEntry> organizations)
    : organizations = List.unmodifiable(organizations);

  final List<OrganizationDirectoryEntry> organizations;
}

/// 目录读取失败，[code] 不包含 provider、HTTP 或数据库原文。
final class OrganizationDirectoryRejected extends OrganizationDirectoryResult {
  const OrganizationDirectoryRejected(this.code);

  final OrganizationDirectoryFailureCode code;
}

/// 使用当前 [IdentitySession] 授权的组织目录客户端边界。
///
/// [list] 无输入，返回读取时快照。它不创建、选择或修改工作空间。
/// [close] 只释放网关自有资源，不关闭 identity session。
abstract interface class OrganizationDirectoryGateway {
  Future<OrganizationDirectoryResult> list();

  Future<void> close();
}

/// Backend 未配置时使用的延迟网关；不发起网络请求。
final class DeferredOrganizationDirectoryGateway
    implements OrganizationDirectoryGateway {
  const DeferredOrganizationDirectoryGateway();

  @override
  Future<OrganizationDirectoryResult> list() async =>
      const OrganizationDirectoryRejected(
        OrganizationDirectoryFailureCode.notConfigured,
      );

  @override
  Future<void> close() async {}
}
