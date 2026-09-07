/// The immutable receipt returned by a successful organization membership
/// self-leave operation.
final class OrganizationMembershipSelfLeaveReceipt {
  const OrganizationMembershipSelfLeaveReceipt({
    required this.membershipSelfLeaveContractId,
    required this.organizationWorkspaceId,
    required this.organizationMembershipId,
    required this.effectiveAtUtc,
  });

  final String membershipSelfLeaveContractId;
  final String organizationWorkspaceId;
  final String organizationMembershipId;
  final DateTime effectiveAtUtc;
}

enum OrganizationMembershipSelfLeaveFailureCode {
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

sealed class OrganizationMembershipSelfLeaveResult {
  const OrganizationMembershipSelfLeaveResult();
}

final class OrganizationMembershipSelfLeaveSuccess
    extends OrganizationMembershipSelfLeaveResult {
  const OrganizationMembershipSelfLeaveSuccess(this.receipt);

  final OrganizationMembershipSelfLeaveReceipt receipt;
}

final class OrganizationMembershipSelfLeaveRejected
    extends OrganizationMembershipSelfLeaveResult {
  const OrganizationMembershipSelfLeaveRejected(this.code);

  final OrganizationMembershipSelfLeaveFailureCode code;
}

/// The client seam for the fixed organization membership self-leave operation.
abstract interface class OrganizationMembershipSelfLeaveGateway {
  Future<OrganizationMembershipSelfLeaveResult> leave({
    required String requestId,
    required String organizationWorkspaceId,
  });

  Future<void> close();
}

/// 返回 Backend 未配置状态，不访问网络。
final class DeferredOrganizationMembershipSelfLeaveGateway
    implements OrganizationMembershipSelfLeaveGateway {
  const DeferredOrganizationMembershipSelfLeaveGateway();

  @override
  Future<OrganizationMembershipSelfLeaveResult> leave({
    required String requestId,
    required String organizationWorkspaceId,
  }) async => const OrganizationMembershipSelfLeaveRejected(
    OrganizationMembershipSelfLeaveFailureCode.notConfigured,
  );

  @override
  Future<void> close() async {}
}
