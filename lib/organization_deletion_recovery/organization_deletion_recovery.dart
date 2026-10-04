/// The fixed, owner-only organization deletion recovery transport contract.
final class OrganizationDeletionRecoveryItem {
  const OrganizationDeletionRecoveryItem({
    required this.organizationWorkspaceId,
    required this.deletionRequestId,
    required this.displayName,
    required this.observedAtUtc,
    required this.effectiveAtUtc,
    required this.purgeAfterUtc,
  });

  final String organizationWorkspaceId;
  final String deletionRequestId;
  final String displayName;

  /// Canonical UTC timestamp with six fractional digits, preserving wire precision.
  final String observedAtUtc;
  final String effectiveAtUtc;
  final String purgeAfterUtc;
  OrganizationDeletionRecoveryStatus get status =>
      OrganizationDeletionRecoveryStatus.deletionPending;
}

enum OrganizationDeletionRecoveryStatus { deletionPending }

final class OrganizationDeletionRecoveryDirectory {
  const OrganizationDeletionRecoveryDirectory({required this.items});

  final List<OrganizationDeletionRecoveryItem> items;
}

final class OrganizationDeletionRequestReceipt {
  const OrganizationDeletionRequestReceipt({
    required this.organizationWorkspaceId,
    required this.deletionRequestId,
    required this.effectiveAtUtc,
    required this.purgeAfterUtc,
  });

  final String organizationWorkspaceId;
  final String deletionRequestId;
  final String effectiveAtUtc;
  final String purgeAfterUtc;
}

final class OrganizationRestorationReceipt {
  const OrganizationRestorationReceipt({
    required this.organizationWorkspaceId,
    required this.deletionRequestId,
    required this.restoredAtUtc,
  });

  final String organizationWorkspaceId;
  final String deletionRequestId;
  final String restoredAtUtc;
}

enum OrganizationDeletionRecoveryFailureCode {
  notConfigured,
  unauthorized,
  invalidRequest,
  forbidden,
  conflict,
  serviceUnavailable,
  networkUnavailable,
  invalidResponse,
}

sealed class OrganizationDeletionRecoveryResult<T> {
  const OrganizationDeletionRecoveryResult();
}

final class OrganizationDeletionRecoverySuccess<T>
    extends OrganizationDeletionRecoveryResult<T> {
  const OrganizationDeletionRecoverySuccess(this.value);

  final T value;
}

final class OrganizationDeletionRecoveryRejected<T>
    extends OrganizationDeletionRecoveryResult<T> {
  const OrganizationDeletionRecoveryRejected(this.code);

  final OrganizationDeletionRecoveryFailureCode code;
}

abstract interface class OrganizationDeletionRecoveryGateway {
  Future<
    OrganizationDeletionRecoveryResult<OrganizationDeletionRecoveryDirectory>
  >
  listRecoverableOrganizations();

  Future<OrganizationDeletionRecoveryResult<OrganizationDeletionRequestReceipt>>
  requestDeletion({
    required String requestId,
    required String organizationWorkspaceId,
  });

  Future<OrganizationDeletionRecoveryResult<OrganizationRestorationReceipt>>
  restore({
    required String requestId,
    required String organizationWorkspaceId,
    required String deletionRequestId,
  });

  Future<void> close();
}

final class DeferredOrganizationDeletionRecoveryGateway
    implements OrganizationDeletionRecoveryGateway {
  const DeferredOrganizationDeletionRecoveryGateway();

  @override
  Future<
    OrganizationDeletionRecoveryResult<OrganizationDeletionRecoveryDirectory>
  >
  listRecoverableOrganizations() async =>
      const OrganizationDeletionRecoveryRejected(
        OrganizationDeletionRecoveryFailureCode.notConfigured,
      );

  @override
  Future<OrganizationDeletionRecoveryResult<OrganizationDeletionRequestReceipt>>
  requestDeletion({
    required String requestId,
    required String organizationWorkspaceId,
  }) async => const OrganizationDeletionRecoveryRejected(
    OrganizationDeletionRecoveryFailureCode.notConfigured,
  );

  @override
  Future<OrganizationDeletionRecoveryResult<OrganizationRestorationReceipt>>
  restore({
    required String requestId,
    required String organizationWorkspaceId,
    required String deletionRequestId,
  }) async => const OrganizationDeletionRecoveryRejected(
    OrganizationDeletionRecoveryFailureCode.notConfigured,
  );

  @override
  Future<void> close() async {}
}
