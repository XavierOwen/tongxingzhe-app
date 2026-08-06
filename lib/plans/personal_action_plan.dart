/// 私人周计划的一个不可变版本。
final class PersonalActionPlanVersion {
  const PersonalActionPlanVersion({
    required this.revision,
    required this.weeklyContactTarget,
    required this.statisticsTimeZone,
    required this.weekStartIsoDay,
    required this.effectiveFromUtc,
  });

  final int revision;
  final int? weeklyContactTarget;
  final String statisticsTimeZone;
  final int weekStartIsoDay;
  final DateTime effectiveFromUtc;
}

/// 当前自然周的私人事实，不包含触达人数、兴趣或结果。
final class PersonalActionPlanProgress {
  const PersonalActionPlanProgress({
    required this.cycleStartUtc,
    required this.cycleUntilUtc,
    required this.recordedContactSessions,
    required this.remainingContactSessions,
    required this.asOfUtc,
  });

  final DateTime cycleStartUtc;
  final DateTime cycleUntilUtc;
  final int recordedContactSessions;
  final int? remainingContactSessions;
  final DateTime asOfUtc;

  bool get hasWeeklyTarget => remainingContactSessions != null;
  bool get hasReachedTarget => hasWeeklyTarget && remainingContactSessions == 0;
}

/// 一个项目中只属于当前用户的计划与进度。
final class PersonalActionPlanSnapshot {
  const PersonalActionPlanSnapshot({
    required this.planId,
    required this.revision,
    required this.current,
    required this.pending,
    required this.progress,
  });

  final String planId;
  final int revision;
  final PersonalActionPlanVersion current;
  final PersonalActionPlanVersion? pending;
  final PersonalActionPlanProgress progress;
}

final class PersonalActionPlanMutation {
  const PersonalActionPlanMutation({
    required this.plan,
    required this.duplicate,
    required this.acceptedRevision,
  });

  final PersonalActionPlanSnapshot plan;
  final bool duplicate;
  final int acceptedRevision;
}

enum PersonalActionPlanFailureCode {
  unauthorized,
  notConfigured,
  networkUnavailable,
  invalidResponse,
  invalidRequest,
  conflict,
  pendingChange,
  serverRejected,
}

sealed class PersonalActionPlanResult<T> {
  const PersonalActionPlanResult();
}

final class PersonalActionPlanSuccess<T> extends PersonalActionPlanResult<T> {
  const PersonalActionPlanSuccess(this.value);

  final T value;
}

final class PersonalActionPlanRejected<T> extends PersonalActionPlanResult<T> {
  const PersonalActionPlanRejected(this.code);

  final PersonalActionPlanFailureCode code;
}

abstract interface class PersonalActionPlanGateway {
  Future<PersonalActionPlanResult<PersonalActionPlanSnapshot?>> load();

  Future<PersonalActionPlanResult<PersonalActionPlanMutation>> save({
    required int expectedRevision,
    required int? weeklyContactTarget,
    required String statisticsTimeZone,
    required int weekStartIsoDay,
    required String mutationId,
  });

  Future<void> close();
}
