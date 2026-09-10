/// 成功创建可分享加入链接后返回的不可变内存回执。
final class OrganizationShareableJoinLinkCreateReceipt {
  const OrganizationShareableJoinLinkCreateReceipt({
    required this.organizationShareableJoinLinkContractId,
    required this.linkId,
    required this.organizationWorkspaceId,
    required this.issuedAtUtc,
    required this.expiresAtUtc,
  });

  final String organizationShareableJoinLinkContractId;
  final String linkId;
  final String organizationWorkspaceId;
  final DateTime issuedAtUtc;
  final DateTime expiresAtUtc;
}

/// 入组申请前可见的可分享加入链接回执。
final class OrganizationShareableJoinLinkPreviewReceipt {
  const OrganizationShareableJoinLinkPreviewReceipt({
    required this.organizationShareableJoinLinkPreviewContractId,
    required this.linkId,
    required this.organizationName,
    required this.expiresAtUtc,
  });

  final String organizationShareableJoinLinkPreviewContractId;
  final String linkId;
  final String organizationName;
  final DateTime expiresAtUtc;
}

/// 成功提交可分享加入申请后返回的不可变内存回执。
final class OrganizationShareableJoinApplicationSubmitReceipt {
  const OrganizationShareableJoinApplicationSubmitReceipt({
    required this.organizationShareableJoinApplicationContractId,
    required this.applicationId,
    required this.linkId,
    required this.organizationWorkspaceId,
    required this.submittedAtUtc,
    required this.expiresAtUtc,
  });

  final String organizationShareableJoinApplicationContractId;
  final String applicationId;
  final String linkId;
  final String organizationWorkspaceId;
  final DateTime submittedAtUtc;
  final DateTime expiresAtUtc;
}

/// 成功批准可分享加入申请后返回的不可变内存回执。
final class OrganizationShareableJoinApplicationApproveReceipt {
  const OrganizationShareableJoinApplicationApproveReceipt({
    required this.organizationShareableJoinApplicationContractId,
    required this.applicationId,
    required this.organizationWorkspaceId,
    required this.organizationMembershipId,
    required this.approvedAtUtc,
  });

  final String organizationShareableJoinApplicationContractId;
  final String applicationId;
  final String organizationWorkspaceId;
  final String organizationMembershipId;
  final DateTime approvedAtUtc;
}

/// 可分享加入操作失败时使用的稳定分类。
enum OrganizationShareableJoinFailureCode {
  notConfigured,
  unauthorized,
  invalidJson,
  payloadTooLarge,
  invalidRequest,
  forbidden,
  conflict,
  serviceUnavailable,
  networkUnavailable,
  invalidResponse,
}

sealed class OrganizationShareableJoinLinkCreateResult {
  const OrganizationShareableJoinLinkCreateResult();
}

final class OrganizationShareableJoinLinkCreateSuccess
    extends OrganizationShareableJoinLinkCreateResult {
  const OrganizationShareableJoinLinkCreateSuccess(this.receipt);

  final OrganizationShareableJoinLinkCreateReceipt receipt;
}

final class OrganizationShareableJoinLinkCreateRejected
    extends OrganizationShareableJoinLinkCreateResult {
  const OrganizationShareableJoinLinkCreateRejected(this.code);

  final OrganizationShareableJoinFailureCode code;
}

sealed class OrganizationShareableJoinLinkPreviewResult {
  const OrganizationShareableJoinLinkPreviewResult();
}

final class OrganizationShareableJoinLinkPreviewSuccess
    extends OrganizationShareableJoinLinkPreviewResult {
  const OrganizationShareableJoinLinkPreviewSuccess(this.receipt);

  final OrganizationShareableJoinLinkPreviewReceipt receipt;
}

final class OrganizationShareableJoinLinkPreviewRejected
    extends OrganizationShareableJoinLinkPreviewResult {
  const OrganizationShareableJoinLinkPreviewRejected(this.code);

  final OrganizationShareableJoinFailureCode code;
}

sealed class OrganizationShareableJoinApplicationSubmitResult {
  const OrganizationShareableJoinApplicationSubmitResult();
}

final class OrganizationShareableJoinApplicationSubmitSuccess
    extends OrganizationShareableJoinApplicationSubmitResult {
  const OrganizationShareableJoinApplicationSubmitSuccess(this.receipt);

  final OrganizationShareableJoinApplicationSubmitReceipt receipt;
}

final class OrganizationShareableJoinApplicationSubmitRejected
    extends OrganizationShareableJoinApplicationSubmitResult {
  const OrganizationShareableJoinApplicationSubmitRejected(this.code);

  final OrganizationShareableJoinFailureCode code;
}

sealed class OrganizationShareableJoinApplicationApproveResult {
  const OrganizationShareableJoinApplicationApproveResult();
}

final class OrganizationShareableJoinApplicationApproveSuccess
    extends OrganizationShareableJoinApplicationApproveResult {
  const OrganizationShareableJoinApplicationApproveSuccess(this.receipt);

  final OrganizationShareableJoinApplicationApproveReceipt receipt;
}

final class OrganizationShareableJoinApplicationApproveRejected
    extends OrganizationShareableJoinApplicationApproveResult {
  const OrganizationShareableJoinApplicationApproveRejected(this.code);

  final OrganizationShareableJoinFailureCode code;
}

/// 可分享加入链接和申请的单一客户端网关。
abstract interface class OrganizationShareableJoinGateway {
  Future<OrganizationShareableJoinLinkCreateResult> createLink({
    required String linkId,
    required String organizationWorkspaceId,
  });

  Future<OrganizationShareableJoinLinkPreviewResult> previewLink({
    required String linkId,
  });

  Future<OrganizationShareableJoinApplicationSubmitResult> submitApplication({
    required String applicationId,
    required String linkId,
  });

  Future<OrganizationShareableJoinApplicationApproveResult> approveApplication({
    required String organizationWorkspaceId,
    required String applicationId,
  });

  /// 释放网关自有资源，不关闭 identity。
  Future<void> close();
}

/// Backend 未配置时使用的延迟网关；不发起网络请求。
final class DeferredOrganizationShareableJoinGateway
    implements OrganizationShareableJoinGateway {
  const DeferredOrganizationShareableJoinGateway();

  @override
  Future<OrganizationShareableJoinLinkCreateResult> createLink({
    required String linkId,
    required String organizationWorkspaceId,
  }) async => const OrganizationShareableJoinLinkCreateRejected(
    OrganizationShareableJoinFailureCode.notConfigured,
  );

  @override
  Future<OrganizationShareableJoinLinkPreviewResult> previewLink({
    required String linkId,
  }) async => const OrganizationShareableJoinLinkPreviewRejected(
    OrganizationShareableJoinFailureCode.notConfigured,
  );

  @override
  Future<OrganizationShareableJoinApplicationSubmitResult> submitApplication({
    required String applicationId,
    required String linkId,
  }) async => const OrganizationShareableJoinApplicationSubmitRejected(
    OrganizationShareableJoinFailureCode.notConfigured,
  );

  @override
  Future<OrganizationShareableJoinApplicationApproveResult> approveApplication({
    required String organizationWorkspaceId,
    required String applicationId,
  }) async => const OrganizationShareableJoinApplicationApproveRejected(
    OrganizationShareableJoinFailureCode.notConfigured,
  );

  @override
  Future<void> close() async {}
}
