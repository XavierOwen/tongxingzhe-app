import 'promotion_target.dart';

const personalTargetMergeDirectoryPageSize = 20;

abstract interface class PersonalTargetMergeDirectoryGateway {
  Future<PersonalTargetMergeDirectoryResult> read({
    required String expectedSubject,
    required String workspaceId,
    required String projectId,
    String? afterGenerationId,
    required bool Function() requestIsCurrent,
  });

  Future<void> close();
}

sealed class PersonalTargetMergeDirectoryResult {
  const PersonalTargetMergeDirectoryResult();
}

final class PersonalTargetMergeDirectoryReady
    extends PersonalTargetMergeDirectoryResult {
  const PersonalTargetMergeDirectoryReady(this.directory);
  final PersonalTargetMergeDirectory directory;
}

final class PersonalTargetMergeDirectoryRejected
    extends PersonalTargetMergeDirectoryResult {
  const PersonalTargetMergeDirectoryRejected(this.failure);
  final PersonalTargetMergeDirectoryFailure failure;
}

enum PersonalTargetMergeDirectoryFailure {
  unauthenticated,
  forbidden,
  invalidRequest,
  serviceUnavailable,
  networkUnavailable,
  invalidResponse,
  requestInvalidated,
}

final class PersonalTargetMergeDirectory {
  PersonalTargetMergeDirectory({
    required this.workspaceId,
    required this.projectId,
    required List<PersonalTargetMergeDirectoryItem> items,
    required this.nextCursor,
  }) : items = List.unmodifiable(items);

  final String workspaceId;
  final String projectId;
  final List<PersonalTargetMergeDirectoryItem> items;
  final String? nextCursor;
}

final class PersonalTargetMergeDirectoryItem {
  PersonalTargetMergeDirectoryItem({
    required this.generationId,
    required this.targetType,
    required this.retainedTargetId,
    required List<String> memberTargetIds,
    required this.reviewDueAtUtc,
  }) : memberTargetIds = List.unmodifiable(memberTargetIds);

  final String generationId;
  final PromotionTargetType targetType;
  final String retainedTargetId;
  final List<String> memberTargetIds;
  final DateTime reviewDueAtUtc;
}
