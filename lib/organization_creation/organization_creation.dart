/// The immutable receipt returned by a successful organization creation.
final class OrganizationCreationReceipt {
  const OrganizationCreationReceipt({
    required this.creationContractId,
    required this.organizationWorkspaceId,
    required this.organizationMembershipId,
    required this.organizationOwnerAssignmentId,
    required this.createdAtUtc,
  });

  final String creationContractId;
  final String organizationWorkspaceId;
  final String organizationMembershipId;
  final String organizationOwnerAssignmentId;
  final DateTime createdAtUtc;
}

enum OrganizationCreationFailureCode {
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

sealed class OrganizationCreationResult {
  const OrganizationCreationResult();
}

final class OrganizationCreationSuccess extends OrganizationCreationResult {
  const OrganizationCreationSuccess(this.receipt);

  final OrganizationCreationReceipt receipt;
}

final class OrganizationCreationRejected extends OrganizationCreationResult {
  const OrganizationCreationRejected(this.code);

  final OrganizationCreationFailureCode code;
}

/// The client seam for the fixed organization-creation operation.
abstract interface class OrganizationCreationGateway {
  Future<OrganizationCreationResult> create({
    required String requestId,
    required String displayName,
  });

  Future<void> close();
}

/// Explicit no-network implementation used when the Backend is not configured.
final class DeferredOrganizationCreationGateway
    implements OrganizationCreationGateway {
  const DeferredOrganizationCreationGateway();

  @override
  Future<OrganizationCreationResult> create({
    required String requestId,
    required String displayName,
  }) async => const OrganizationCreationRejected(
    OrganizationCreationFailureCode.notConfigured,
  );

  @override
  Future<void> close() async {}
}
