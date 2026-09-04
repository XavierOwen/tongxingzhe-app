/// The immutable receipt returned by a successful organization owner transfer.
final class OrganizationOwnerTransferReceipt {
  const OrganizationOwnerTransferReceipt({
    required this.ownerTransferContractId,
    required this.organizationWorkspaceId,
    required this.previousOwnerAssignmentId,
    required this.organizationOwnerAssignmentId,
    required this.effectiveAtUtc,
  });

  final String ownerTransferContractId;
  final String organizationWorkspaceId;
  final String previousOwnerAssignmentId;
  final String organizationOwnerAssignmentId;
  final DateTime effectiveAtUtc;
}

enum OrganizationOwnerTransferFailureCode {
  notConfigured,
  unauthorized,
  invalidJson,
  payloadTooLarge,
  invalidRequest,
  forbidden,
  conflict,
  targetAlreadyOwner,
  serviceUnavailable,
  networkUnavailable,
  invalidResponse,
}

sealed class OrganizationOwnerTransferResult {
  const OrganizationOwnerTransferResult();
}

final class OrganizationOwnerTransferSuccess
    extends OrganizationOwnerTransferResult {
  const OrganizationOwnerTransferSuccess(this.receipt);

  final OrganizationOwnerTransferReceipt receipt;
}

final class OrganizationOwnerTransferRejected
    extends OrganizationOwnerTransferResult {
  const OrganizationOwnerTransferRejected(this.code);

  final OrganizationOwnerTransferFailureCode code;
}

/// The client seam for the fixed organization owner-transfer operation.
abstract interface class OrganizationOwnerTransferGateway {
  Future<OrganizationOwnerTransferResult> transfer({
    required String requestId,
    required String organizationWorkspaceId,
    required String targetOrganizationMembershipId,
  });

  Future<void> close();
}

/// Explicit no-network implementation used when the Backend is not configured.
final class DeferredOrganizationOwnerTransferGateway
    implements OrganizationOwnerTransferGateway {
  const DeferredOrganizationOwnerTransferGateway();

  @override
  Future<OrganizationOwnerTransferResult> transfer({
    required String requestId,
    required String organizationWorkspaceId,
    required String targetOrganizationMembershipId,
  }) async => const OrganizationOwnerTransferRejected(
    OrganizationOwnerTransferFailureCode.notConfigured,
  );

  @override
  Future<void> close() async {}
}
