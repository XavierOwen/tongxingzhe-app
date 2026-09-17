/// Historical receipt; it is not proof of current project access.
final class OrganizationProjectMembershipAssignmentReceipt {
  const OrganizationProjectMembershipAssignmentReceipt({
    required this.projectMembershipAssignmentContractId,
    required this.organizationWorkspaceId,
    required this.projectId,
    required this.organizationMembershipId,
    required this.projectMembershipId,
    required this.activeFromUtc,
    required this.inactiveFromUtc,
  });

  final String projectMembershipAssignmentContractId;
  final String organizationWorkspaceId;
  final String projectId;
  final String organizationMembershipId;
  final String projectMembershipId;
  final DateTime activeFromUtc;
  final DateTime? inactiveFromUtc;
}

enum OrganizationProjectMembershipAssignmentFailureCode {
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

sealed class OrganizationProjectMembershipAssignmentResult {
  const OrganizationProjectMembershipAssignmentResult();
}

final class OrganizationProjectMembershipAssignmentSuccess
    extends OrganizationProjectMembershipAssignmentResult {
  const OrganizationProjectMembershipAssignmentSuccess(this.receipt);

  final OrganizationProjectMembershipAssignmentReceipt receipt;
}

final class OrganizationProjectMembershipAssignmentRejected
    extends OrganizationProjectMembershipAssignmentResult {
  const OrganizationProjectMembershipAssignmentRejected(this.code);

  final OrganizationProjectMembershipAssignmentFailureCode code;
}

abstract interface class OrganizationProjectMembershipAssignmentGateway {
  Future<OrganizationProjectMembershipAssignmentResult> assign({
    required String requestId,
    required String organizationWorkspaceId,
    required String projectId,
    required String targetOrganizationMembershipId,
  });

  Future<void> close();
}

/// Explicit no-network implementation when the Backend is not configured.
final class DeferredOrganizationProjectMembershipAssignmentGateway
    implements OrganizationProjectMembershipAssignmentGateway {
  const DeferredOrganizationProjectMembershipAssignmentGateway();

  @override
  Future<OrganizationProjectMembershipAssignmentResult> assign({
    required String requestId,
    required String organizationWorkspaceId,
    required String projectId,
    required String targetOrganizationMembershipId,
  }) async => const OrganizationProjectMembershipAssignmentRejected(
    OrganizationProjectMembershipAssignmentFailureCode.notConfigured,
  );

  @override
  Future<void> close() async {}
}
