import 'dart:math';

/// Backend contract for the optional personal follow-up consent ratio.
const personalFollowUpConsentOptInMetric = 'follow_up_consent_ratio@1';
const personalFollowUpConsentOptInStateContract =
    'project_follow_up_consent_opt_in_state_v1';
const personalFollowUpConsentOptInConfigurationContract =
    'project_follow_up_consent_opt_in_configuration_v1';

/// PostgreSQL `integer` is the version's wire type, not an unbounded Dart int.
const personalFollowUpConsentOptInMaxVersion = 2147483647;

enum PersonalFollowUpConsentOptInStatus { enabled, notEnabled }

final class PersonalFollowUpConsentOptInConfiguration {
  const PersonalFollowUpConsentOptInConfiguration({
    required this.configurationContractId,
    required this.metricId,
    required this.projectId,
    required this.versionNumber,
    required this.expectedVersion,
    required this.enabled,
    required this.requestId,
    required this.recordedAtUtc,
  });

  final String configurationContractId;
  final String metricId;
  final String projectId;
  final int versionNumber;
  final int expectedVersion;
  final bool enabled;
  final String requestId;
  final DateTime recordedAtUtc;

  String get contractId => configurationContractId;
  int get version => versionNumber;
}

final class PersonalFollowUpConsentOptInState {
  const PersonalFollowUpConsentOptInState({
    required this.stateContractId,
    required this.metricId,
    required this.projectId,
    required this.status,
    required this.configuration,
  });

  final String stateContractId;
  final String metricId;
  final String projectId;
  final PersonalFollowUpConsentOptInStatus status;
  final PersonalFollowUpConsentOptInConfiguration? configuration;

  String get contractId => stateContractId;
}

enum PersonalFollowUpConsentOptInFailureCode {
  notConfigured,
  unauthorized,
  invalidRequest,
  forbidden,
  conflict,
  networkUnavailable,
  serviceUnavailable,
  serverRejected,
  invalidResponse,
}

sealed class PersonalFollowUpConsentOptInResult<T> {
  const PersonalFollowUpConsentOptInResult();
}

final class PersonalFollowUpConsentOptInSuccess<T>
    extends PersonalFollowUpConsentOptInResult<T> {
  const PersonalFollowUpConsentOptInSuccess(this.value);

  final T value;
}

final class PersonalFollowUpConsentOptInRejected<T>
    extends PersonalFollowUpConsentOptInResult<T> {
  const PersonalFollowUpConsentOptInRejected(this.code);

  final PersonalFollowUpConsentOptInFailureCode code;
}

/// The settings controller owns request-ID reuse across one uncertain save.
abstract interface class ConsentOptInRequestIdGenerator {
  String next();
}

/// Cryptographically random UUID v4 generator for opt-in mutations.
final class SecureConsentOptInRequestIdGenerator
    implements ConsentOptInRequestIdGenerator {
  SecureConsentOptInRequestIdGenerator() : _random = Random.secure();

  final Random _random;

  @override
  String next() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((value) => value.toRadixString(16).padLeft(2, '0'));
    final text = hex.join();
    return '${text.substring(0, 8)}-${text.substring(8, 12)}-'
        '${text.substring(12, 16)}-${text.substring(16, 20)}-'
        '${text.substring(20)}';
  }
}

abstract interface class PersonalFollowUpConsentOptInGateway {
  Future<PersonalFollowUpConsentOptInResult<PersonalFollowUpConsentOptInState>>
  load();

  Future<
    PersonalFollowUpConsentOptInResult<
      PersonalFollowUpConsentOptInConfiguration
    >
  >
  configure({
    required int expectedVersion,
    required bool enabled,
    required String requestId,
  });

  Future<void> close();
}
