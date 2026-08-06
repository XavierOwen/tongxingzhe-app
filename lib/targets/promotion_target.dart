enum PromotionTargetType {
  person('person'),
  institution('institution');

  const PromotionTargetType(this.storageValue);

  final String storageValue;
}

final class PromotionTargetProfile {
  const PromotionTargetProfile({
    required this.id,
    required this.type,
    required this.displayName,
    required this.phone,
    required this.email,
    required this.createdAtUtc,
  });

  final String id;
  final PromotionTargetType type;
  final String displayName;
  final String? phone;
  final String? email;
  final DateTime createdAtUtc;
}

enum PromotionTargetFailureCode {
  unauthorized,
  forbidden,
  conflict,
  invalidInput,
  networkUnavailable,
  serverRejected,
}

sealed class PromotionTargetResult<T> {
  const PromotionTargetResult();
}

final class PromotionTargetSuccess<T> extends PromotionTargetResult<T> {
  const PromotionTargetSuccess(this.value);

  final T value;
}

final class PromotionTargetRejected<T> extends PromotionTargetResult<T> {
  const PromotionTargetRejected(this.code);

  final PromotionTargetFailureCode code;
}

abstract interface class PromotionTargetGateway {
  Future<PromotionTargetResult<List<PromotionTargetProfile>>> loadAssigned();

  Future<PromotionTargetResult<PromotionTargetProfile>> create({
    required PromotionTargetType type,
    required String displayName,
    required String? phone,
    required String? email,
    required String requestId,
  });

  Future<void> close();
}
