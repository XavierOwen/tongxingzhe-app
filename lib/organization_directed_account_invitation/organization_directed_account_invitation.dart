/// 成功创建组织定向账号邀请后返回的不可变内存回执。
final class OrganizationDirectedAccountInvitationCreateReceipt {
  const OrganizationDirectedAccountInvitationCreateReceipt({
    required this.organizationInvitationContractId,
    required this.invitationId,
    required this.organizationWorkspaceId,
    required this.issuedAtUtc,
    required this.expiresAtUtc,
  });

  final String organizationInvitationContractId;
  final String invitationId;
  final String organizationWorkspaceId;
  final DateTime issuedAtUtc;
  final DateTime expiresAtUtc;
}

/// 成功接受组织定向账号邀请后返回的不可变内存回执。
final class OrganizationDirectedAccountInvitationAcceptReceipt {
  const OrganizationDirectedAccountInvitationAcceptReceipt({
    required this.organizationInvitationContractId,
    required this.invitationId,
    required this.organizationWorkspaceId,
    required this.organizationMembershipId,
    required this.acceptedAtUtc,
  });

  final String organizationInvitationContractId;
  final String invitationId;
  final String organizationWorkspaceId;
  final String organizationMembershipId;
  final DateTime acceptedAtUtc;
}

/// 入组前可见的组织定向账号邀请快照。
final class OrganizationDirectedAccountInvitationPreview {
  const OrganizationDirectedAccountInvitationPreview({
    required this.organizationInvitationPreviewContractId,
    required this.invitationId,
    required this.organizationName,
    required this.expiresAtUtc,
  });

  final String organizationInvitationPreviewContractId;
  final String invitationId;
  final String organizationName;
  final DateTime expiresAtUtc;
}

/// 创建、预览或接受邀请失败时使用的稳定失败分类。
enum OrganizationDirectedAccountInvitationFailureCode {
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

/// 创建组织定向账号邀请的结果。
sealed class OrganizationDirectedAccountInvitationCreateResult {
  const OrganizationDirectedAccountInvitationCreateResult();
}

/// 创建邀请成功，并携带仅存在于内存中的回执。
final class OrganizationDirectedAccountInvitationCreateSuccess
    extends OrganizationDirectedAccountInvitationCreateResult {
  const OrganizationDirectedAccountInvitationCreateSuccess(this.receipt);

  final OrganizationDirectedAccountInvitationCreateReceipt receipt;
}

/// 创建邀请被拒绝，并携带失败分类。
final class OrganizationDirectedAccountInvitationCreateRejected
    extends OrganizationDirectedAccountInvitationCreateResult {
  const OrganizationDirectedAccountInvitationCreateRejected(this.code);

  final OrganizationDirectedAccountInvitationFailureCode code;
}

/// 预览组织定向账号邀请的结果。
sealed class OrganizationDirectedAccountInvitationPreviewResult {
  const OrganizationDirectedAccountInvitationPreviewResult();
}

/// 预览成功，并携带仅存在于内存中的快照。
final class OrganizationDirectedAccountInvitationPreviewSuccess
    extends OrganizationDirectedAccountInvitationPreviewResult {
  const OrganizationDirectedAccountInvitationPreviewSuccess(this.preview);

  final OrganizationDirectedAccountInvitationPreview preview;
}

/// 预览被拒绝，并携带失败分类。
final class OrganizationDirectedAccountInvitationPreviewRejected
    extends OrganizationDirectedAccountInvitationPreviewResult {
  const OrganizationDirectedAccountInvitationPreviewRejected(this.code);

  final OrganizationDirectedAccountInvitationFailureCode code;
}

/// 接受组织定向账号邀请的结果。
sealed class OrganizationDirectedAccountInvitationAcceptResult {
  const OrganizationDirectedAccountInvitationAcceptResult();
}

/// 接受邀请成功，并携带仅存在于内存中的回执。
final class OrganizationDirectedAccountInvitationAcceptSuccess
    extends OrganizationDirectedAccountInvitationAcceptResult {
  const OrganizationDirectedAccountInvitationAcceptSuccess(this.receipt);

  final OrganizationDirectedAccountInvitationAcceptReceipt receipt;
}

/// 接受邀请被拒绝，并携带失败分类。
final class OrganizationDirectedAccountInvitationAcceptRejected
    extends OrganizationDirectedAccountInvitationAcceptResult {
  const OrganizationDirectedAccountInvitationAcceptRejected(this.code);

  final OrganizationDirectedAccountInvitationFailureCode code;
}

/// 组织定向账号邀请的客户端网关接口。
///
/// 参数来自调用方；identity 与授权由实现通过 IdentitySession/Backend
/// 处理。结果只保存在内存中；close 只释放网关自有资源，不关闭 identity。
abstract interface class OrganizationDirectedAccountInvitationGateway {
  /// 创建邀请。
  Future<OrganizationDirectedAccountInvitationCreateResult> create({
    required String invitationId,
    required String organizationWorkspaceId,
    required String targetAppUserId,
  });

  /// 在接受前预览邀请所属组织与过期时间。
  Future<OrganizationDirectedAccountInvitationPreviewResult> preview({
    required String invitationId,
  });

  /// 接受邀请。
  Future<OrganizationDirectedAccountInvitationAcceptResult> accept({
    required String invitationId,
  });

  /// 释放网关自有资源，不关闭 identity。
  Future<void> close();
}

/// Backend 未配置时使用的延迟网关；不发起网络请求。
final class DeferredOrganizationDirectedAccountInvitationGateway
    implements OrganizationDirectedAccountInvitationGateway {
  const DeferredOrganizationDirectedAccountInvitationGateway();

  @override
  Future<OrganizationDirectedAccountInvitationCreateResult> create({
    required String invitationId,
    required String organizationWorkspaceId,
    required String targetAppUserId,
  }) async => const OrganizationDirectedAccountInvitationCreateRejected(
    OrganizationDirectedAccountInvitationFailureCode.notConfigured,
  );

  @override
  Future<OrganizationDirectedAccountInvitationPreviewResult> preview({
    required String invitationId,
  }) async => const OrganizationDirectedAccountInvitationPreviewRejected(
    OrganizationDirectedAccountInvitationFailureCode.notConfigured,
  );

  @override
  Future<OrganizationDirectedAccountInvitationAcceptResult> accept({
    required String invitationId,
  }) async => const OrganizationDirectedAccountInvitationAcceptRejected(
    OrganizationDirectedAccountInvitationFailureCode.notConfigured,
  );

  @override
  Future<void> close() async {}
}
