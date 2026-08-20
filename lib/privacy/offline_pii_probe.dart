// Public constructor arguments intentionally differ from private field names.
// ignore_for_file: prefer_initializing_formals

import '../app_session/session_context_gateway.dart';
import '../foundation/runtime_values.dart';
import '../platform/platform_capabilities.dart';
import '../targets/promotion_target.dart';
import 'offline_pii_vault.dart';

enum OfflinePiiProbeEnvironment {
  androidEmulator('android-emulator'),
  iosSimulator('ios-simulator'),
  macosUnsigned('macos-unsigned'),
  nativeHost('native-host'),
  webBrowser('web-browser');

  const OfflinePiiProbeEnvironment(this.storageValue);

  final String storageValue;

  static OfflinePiiProbeEnvironment parse(String value) => values.firstWhere(
    (candidate) => candidate.storageValue == value.trim(),
    orElse: () => throw ArgumentError.value(value, 'environment'),
  );
}

enum OfflinePiiProbeSigning {
  simulator('simulator'),
  unsigned('unsigned'),
  adHoc('ad-hoc'),
  notApplicable('not-applicable');

  const OfflinePiiProbeSigning(this.storageValue);

  final String storageValue;

  static OfflinePiiProbeSigning parse(String value) => values.firstWhere(
    (candidate) => candidate.storageValue == value.trim(),
    orElse: () => throw ArgumentError.value(value, 'signing'),
  );
}

enum OfflinePiiProbeEvidenceClass { simulated, unsupported, blocked }

enum OfflinePiiProbeOutcome { pass, failed, unsupported, blocked }

enum OfflinePiiProbeScenario {
  platformGate,
  writeRead,
  crossProcessRecovery,
  nearExpiry,
  expiry,
  authorizationRevocation,
  revocationDeleteFailure,
  deletionRetry,
  cleanup,
}

enum OfflinePiiProbeReason {
  secureStorageAndDatabaseAvailable,
  sensitiveStorageDisabled,
  initializationFailed,
  savedAndReadable,
  saveOrReadFailed,
  recoveredWithoutRenewal,
  restartRequired,
  recoveryUnavailable,
  readableBeforeExpiry,
  nearExpiryCheckFailed,
  expiredAndLocked,
  expiryCheckFailed,
  authorizationRevokedAndDeleted,
  authorizationRevocationFailed,
  deletionPendingAndLocked,
  deletionFailureCheckFailed,
  deletedAndStillLocked,
  deletionRetryFailed,
  syntheticValuesDeleted,
  cleanupFailed,
  operationFailed,
}

enum OfflinePiiProbeCheckpoint { crossProcessWrite, deletionFailure }

final class OfflinePiiProbeCheckpointState {
  OfflinePiiProbeCheckpointState({
    required String processId,
    required String runId,
    required String commit,
    required this.environment,
    DateTime? authorizedAtUtc,
  }) : processId = _requiredOpaqueId(processId, 'processId'),
       runId = _runId(runId),
       commit = _commit(commit),
       authorizedAtUtc = authorizedAtUtc?.toUtc();

  final String processId;
  final String runId;
  final String commit;
  final OfflinePiiProbeEnvironment environment;
  final DateTime? authorizedAtUtc;

  bool matches(OfflinePiiProbeConfiguration configuration) =>
      runId == configuration.runId &&
      commit == configuration.commit &&
      environment == configuration.environment;
}

/// 保存不含身份信息的进程检查点，用来拒绝跨轮次重放并核对是否续期。
abstract interface class OfflinePiiProbeStateStore {
  Future<OfflinePiiProbeCheckpointState?> read(
    OfflinePiiProbeCheckpoint checkpoint,
  );

  Future<void> write(
    OfflinePiiProbeCheckpoint checkpoint,
    OfflinePiiProbeCheckpointState state,
  );

  Future<void> clear(OfflinePiiProbeCheckpoint checkpoint);
}

final class OfflinePiiProbeConfiguration {
  OfflinePiiProbeConfiguration({
    required String commit,
    required String runId,
    required String flutterVersion,
    required String osVersion,
    required this.environment,
    required this.signing,
  }) : commit = _commit(commit),
       runId = _runId(runId),
       flutterVersion = _version(flutterVersion, 'flutterVersion'),
       osVersion = _version(osVersion, 'osVersion') {
    _validateEnvironmentSigning(environment, signing);
  }

  final String commit;
  final String runId;
  final String flutterVersion;
  final String osVersion;
  final OfflinePiiProbeEnvironment environment;
  final OfflinePiiProbeSigning signing;

  OfflinePiiProbeEvidenceClass get evidenceClass =>
      OfflinePiiProbeEvidenceClass.simulated;

  bool matchesPlatform(AppPlatform platform) => switch (environment) {
    OfflinePiiProbeEnvironment.androidEmulator =>
      platform == AppPlatform.android,
    OfflinePiiProbeEnvironment.iosSimulator => platform == AppPlatform.ios,
    OfflinePiiProbeEnvironment.macosUnsigned => platform == AppPlatform.macos,
    OfflinePiiProbeEnvironment.webBrowser => platform == AppPlatform.web,
    OfflinePiiProbeEnvironment.nativeHost =>
      platform == AppPlatform.macos ||
          platform == AppPlatform.windows ||
          platform == AppPlatform.linux,
  };
}

final class OfflinePiiProbeEvent {
  const OfflinePiiProbeEvent({
    required this.recordedAtUtc,
    required this.scenario,
    required this.outcome,
    required this.evidenceClass,
    required this.reason,
    this.lockReason,
    this.deletionResult,
    this.authorizedAtUtc,
    this.expiresAtUtc,
  });

  final DateTime recordedAtUtc;
  final OfflinePiiProbeScenario scenario;
  final OfflinePiiProbeOutcome outcome;
  final OfflinePiiProbeEvidenceClass evidenceClass;
  final OfflinePiiProbeReason reason;
  final OfflinePiiLockReason? lockReason;
  final OfflinePiiDeletionResult? deletionResult;
  final DateTime? authorizedAtUtc;
  final DateTime? expiresAtUtc;

  Map<String, Object?> toJson() => <String, Object?>{
    'recordedAtUtc': recordedAtUtc.toUtc().toIso8601String(),
    'scenario': scenario.name,
    'outcome': outcome.name,
    'evidenceClass': evidenceClass.name,
    'reason': reason.name,
    if (lockReason case final value?) 'lockReason': value.name,
    if (deletionResult case final value?) 'deletionResult': value.name,
    if (authorizedAtUtc case final value?)
      'authorizedAtUtc': value.toUtc().toIso8601String(),
    if (expiresAtUtc case final value?)
      'expiresAtUtc': value.toUtc().toIso8601String(),
  };
}

/// 只记录 allowlist 元数据和状态码，不接受自由文本或快照内容。
final class OfflinePiiProbeRecorder {
  OfflinePiiProbeRecorder({
    required this.platform,
    required this.configuration,
  });

  static const schemaVersion = 1;

  final AppPlatform platform;
  final OfflinePiiProbeConfiguration configuration;
  final List<OfflinePiiProbeEvent> _events = <OfflinePiiProbeEvent>[];

  List<OfflinePiiProbeEvent> get events => List.unmodifiable(_events);

  OfflinePiiProbeEvidenceClass get evidenceClass {
    for (final event in _events.reversed) {
      if (event.scenario != OfflinePiiProbeScenario.platformGate) continue;
      return switch (event.outcome) {
        OfflinePiiProbeOutcome.unsupported =>
          OfflinePiiProbeEvidenceClass.unsupported,
        OfflinePiiProbeOutcome.blocked => OfflinePiiProbeEvidenceClass.blocked,
        _ => configuration.evidenceClass,
      };
    }
    return configuration.evidenceClass;
  }

  void record(OfflinePiiProbeEvent event) => _events.add(event);

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'platform': platform.name,
    'osVersion': configuration.osVersion,
    'flutterVersion': configuration.flutterVersion,
    'commit': configuration.commit,
    'runId': configuration.runId,
    'environment': configuration.environment.storageValue,
    'signing': configuration.signing.storageValue,
    'evidenceClass': evidenceClass.name,
    'events': _events.map((event) => event.toJson()).toList(growable: false),
  };
}

abstract interface class OfflinePiiProbeActions {
  Future<OfflinePiiProbeEvent> run(OfflinePiiProbeScenario scenario);
}

bool canInitializeOfflinePiiProbe(PlatformCapabilities capabilities) =>
    PlatformPolicy.from(capabilities).canPersistSensitiveTargets;

/// 用 synthetic 快照驱动生产 vault。它不连接 Backend，也不输出快照正文。
final class OfflinePiiProbeRunner implements OfflinePiiProbeActions {
  OfflinePiiProbeRunner({
    required OfflinePiiVault vault,
    required OfflinePiiProbeRecorder recorder,
    required AppClock clock,
    required OfflinePiiProbeStateStore stateStore,
    required String launchId,
    required void Function() armNextDeleteFailure,
  }) : _vault = vault,
       _recorder = recorder,
       _clock = clock,
       _stateStore = stateStore,
       _launchId = _requiredOpaqueId(launchId, 'launchId'),
       _armNextDeleteFailure = armNextDeleteFailure;

  final OfflinePiiVault _vault;
  final OfflinePiiProbeRecorder _recorder;
  final AppClock _clock;
  final OfflinePiiProbeStateStore _stateStore;
  final String _launchId;
  final void Function() _armNextDeleteFailure;

  @override
  Future<OfflinePiiProbeEvent> run(OfflinePiiProbeScenario scenario) async {
    final event = switch (scenario) {
      OfflinePiiProbeScenario.platformGate => throw ArgumentError.value(
        scenario,
        'scenario',
      ),
      OfflinePiiProbeScenario.writeRead => _writeRead(),
      OfflinePiiProbeScenario.crossProcessRecovery => _recover(),
      OfflinePiiProbeScenario.nearExpiry => _nearExpiry(),
      OfflinePiiProbeScenario.expiry => _expiry(),
      OfflinePiiProbeScenario.authorizationRevocation =>
        _authorizationRevocation(),
      OfflinePiiProbeScenario.revocationDeleteFailure =>
        _revocationDeleteFailure(),
      OfflinePiiProbeScenario.deletionRetry => _retryDeletion(),
      OfflinePiiProbeScenario.cleanup => _cleanup(),
    };
    final resolved = await event;
    _recorder.record(resolved);
    return resolved;
  }

  Future<OfflinePiiProbeEvent> _writeRead() async {
    try {
      await _stateStore.clear(OfflinePiiProbeCheckpoint.crossProcessWrite);
      final authorizedAt = _clock.now().toUtc();
      final saved = await _replace(_crossProcessSubject, authorizedAt);
      final read = await _vault.read(_crossProcessSubject);
      final passed =
          saved is OfflinePiiSaved &&
          read is OfflinePiiAvailable &&
          read.snapshot.authorizedAtUtc == authorizedAt &&
          read.snapshot.expiresAtUtc ==
              authorizedAt.add(const Duration(hours: 72));
      if (passed) {
        await _stateStore.write(
          OfflinePiiProbeCheckpoint.crossProcessWrite,
          OfflinePiiProbeCheckpointState(
            processId: _launchId,
            runId: _recorder.configuration.runId,
            commit: _recorder.configuration.commit,
            environment: _recorder.configuration.environment,
            authorizedAtUtc: authorizedAt,
          ),
        );
      }
      return _event(
        OfflinePiiProbeScenario.writeRead,
        passed,
        passed
            ? OfflinePiiProbeReason.savedAndReadable
            : OfflinePiiProbeReason.saveOrReadFailed,
        lockReason: _lockReason(read),
        authorizedAtUtc: read is OfflinePiiAvailable
            ? read.snapshot.authorizedAtUtc
            : null,
        expiresAtUtc: read is OfflinePiiAvailable
            ? read.snapshot.expiresAtUtc
            : null,
      );
    } on Object {
      return _event(
        OfflinePiiProbeScenario.writeRead,
        false,
        OfflinePiiProbeReason.saveOrReadFailed,
      );
    }
  }

  Future<OfflinePiiProbeEvent> _recover() async {
    try {
      final checkpoint = await _stateStore.read(
        OfflinePiiProbeCheckpoint.crossProcessWrite,
      );
      if (checkpoint == null ||
          !checkpoint.matches(_recorder.configuration) ||
          checkpoint.processId == _launchId) {
        return _event(
          OfflinePiiProbeScenario.crossProcessRecovery,
          false,
          OfflinePiiProbeReason.restartRequired,
        );
      }
      final read = await _vault.read(_crossProcessSubject);
      final expectedAuthorizedAt = checkpoint.authorizedAtUtc;
      final passed =
          expectedAuthorizedAt != null &&
          read is OfflinePiiAvailable &&
          read.snapshot.authorizedAtUtc == expectedAuthorizedAt &&
          read.snapshot.expiresAtUtc ==
              expectedAuthorizedAt.add(const Duration(hours: 72));
      return _event(
        OfflinePiiProbeScenario.crossProcessRecovery,
        passed,
        passed
            ? OfflinePiiProbeReason.recoveredWithoutRenewal
            : OfflinePiiProbeReason.recoveryUnavailable,
        lockReason: _lockReason(read),
        authorizedAtUtc: read is OfflinePiiAvailable
            ? read.snapshot.authorizedAtUtc
            : null,
        expiresAtUtc: read is OfflinePiiAvailable
            ? read.snapshot.expiresAtUtc
            : null,
      );
    } on Object {
      return _event(
        OfflinePiiProbeScenario.crossProcessRecovery,
        false,
        OfflinePiiProbeReason.recoveryUnavailable,
      );
    }
  }

  Future<OfflinePiiProbeEvent> _nearExpiry() async {
    try {
      final authorizedAt = _clock.now().toUtc().subtract(
        const Duration(hours: 71, minutes: 59),
      );
      final saved = await _replace(_nearExpirySubject, authorizedAt);
      final read = await _vault.read(_nearExpirySubject);
      final passed =
          saved is OfflinePiiSaved &&
          read is OfflinePiiAvailable &&
          read.snapshot.authorizedAtUtc == authorizedAt &&
          read.snapshot.expiresAtUtc ==
              authorizedAt.add(const Duration(hours: 72));
      return _event(
        OfflinePiiProbeScenario.nearExpiry,
        passed,
        passed
            ? OfflinePiiProbeReason.readableBeforeExpiry
            : OfflinePiiProbeReason.nearExpiryCheckFailed,
        lockReason: _lockReason(read),
        authorizedAtUtc: read is OfflinePiiAvailable
            ? read.snapshot.authorizedAtUtc
            : null,
        expiresAtUtc: read is OfflinePiiAvailable
            ? read.snapshot.expiresAtUtc
            : null,
      );
    } on Object {
      return _event(
        OfflinePiiProbeScenario.nearExpiry,
        false,
        OfflinePiiProbeReason.nearExpiryCheckFailed,
      );
    }
  }

  Future<OfflinePiiProbeEvent> _expiry() async {
    try {
      final authorizedAt = _clock.now().toUtc().subtract(
        const Duration(hours: 72),
      );
      final saved = await _replace(_expirySubject, authorizedAt);
      final read = await _vault.read(_expirySubject);
      final passed =
          saved is OfflinePiiSaved &&
          read is OfflinePiiLocked &&
          read.reason == OfflinePiiLockReason.expired;
      return _event(
        OfflinePiiProbeScenario.expiry,
        passed,
        passed
            ? OfflinePiiProbeReason.expiredAndLocked
            : OfflinePiiProbeReason.expiryCheckFailed,
        lockReason: _lockReason(read),
      );
    } on Object {
      return _event(
        OfflinePiiProbeScenario.expiry,
        false,
        OfflinePiiProbeReason.expiryCheckFailed,
      );
    }
  }

  Future<OfflinePiiProbeEvent> _revocationDeleteFailure() async {
    try {
      await _stateStore.clear(OfflinePiiProbeCheckpoint.deletionFailure);
      final saved = await _replace(
        _deletionFailureSubject,
        _clock.now().toUtc(),
      );
      if (saved is! OfflinePiiSaved) {
        return _event(
          OfflinePiiProbeScenario.revocationDeleteFailure,
          false,
          OfflinePiiProbeReason.deletionFailureCheckFailed,
        );
      }
      _armNextDeleteFailure();
      final deletion = await _vault.revoke(
        _deletionFailureSubject,
        OfflinePiiLockReason.signedOut,
      );
      final read = await _vault.read(_deletionFailureSubject);
      final passed =
          deletion == OfflinePiiDeletionResult.pending &&
          read is OfflinePiiLocked &&
          read.reason == OfflinePiiLockReason.signedOut;
      if (passed) {
        await _stateStore.write(
          OfflinePiiProbeCheckpoint.deletionFailure,
          OfflinePiiProbeCheckpointState(
            processId: _launchId,
            runId: _recorder.configuration.runId,
            commit: _recorder.configuration.commit,
            environment: _recorder.configuration.environment,
          ),
        );
      }
      return _event(
        OfflinePiiProbeScenario.revocationDeleteFailure,
        passed,
        passed
            ? OfflinePiiProbeReason.deletionPendingAndLocked
            : OfflinePiiProbeReason.deletionFailureCheckFailed,
        lockReason: _lockReason(read),
        deletionResult: deletion,
      );
    } on Object {
      return _event(
        OfflinePiiProbeScenario.revocationDeleteFailure,
        false,
        OfflinePiiProbeReason.deletionFailureCheckFailed,
      );
    }
  }

  Future<OfflinePiiProbeEvent> _authorizationRevocation() async {
    try {
      final saved = await _replace(_revocationSubject, _clock.now().toUtc());
      if (saved is! OfflinePiiSaved) {
        return _event(
          OfflinePiiProbeScenario.authorizationRevocation,
          false,
          OfflinePiiProbeReason.authorizationRevocationFailed,
        );
      }
      final deletion = await _vault.revoke(
        _revocationSubject,
        OfflinePiiLockReason.unauthorized,
      );
      final read = await _vault.read(_revocationSubject);
      final passed =
          deletion == OfflinePiiDeletionResult.deleted &&
          read is OfflinePiiLocked &&
          read.reason == OfflinePiiLockReason.unauthorized;
      return _event(
        OfflinePiiProbeScenario.authorizationRevocation,
        passed,
        passed
            ? OfflinePiiProbeReason.authorizationRevokedAndDeleted
            : OfflinePiiProbeReason.authorizationRevocationFailed,
        lockReason: _lockReason(read),
        deletionResult: deletion,
      );
    } on Object {
      return _event(
        OfflinePiiProbeScenario.authorizationRevocation,
        false,
        OfflinePiiProbeReason.authorizationRevocationFailed,
      );
    }
  }

  Future<OfflinePiiProbeEvent> _retryDeletion() async {
    try {
      final checkpoint = await _stateStore.read(
        OfflinePiiProbeCheckpoint.deletionFailure,
      );
      if (checkpoint == null ||
          !checkpoint.matches(_recorder.configuration) ||
          checkpoint.processId == _launchId) {
        return _event(
          OfflinePiiProbeScenario.deletionRetry,
          false,
          OfflinePiiProbeReason.restartRequired,
        );
      }
      final deletion = await _vault.retryLockedDeletion(
        _deletionFailureSubject,
      );
      final read = await _vault.read(_deletionFailureSubject);
      final passed =
          deletion == OfflinePiiDeletionResult.deleted &&
          read is OfflinePiiLocked &&
          read.reason == OfflinePiiLockReason.signedOut;
      return _event(
        OfflinePiiProbeScenario.deletionRetry,
        passed,
        passed
            ? OfflinePiiProbeReason.deletedAndStillLocked
            : OfflinePiiProbeReason.deletionRetryFailed,
        lockReason: _lockReason(read),
        deletionResult: deletion,
      );
    } on Object {
      return _event(
        OfflinePiiProbeScenario.deletionRetry,
        false,
        OfflinePiiProbeReason.deletionRetryFailed,
      );
    }
  }

  Future<OfflinePiiProbeEvent> _cleanup() async {
    try {
      for (final subject in _allSubjects) {
        var deletion = await _vault.revoke(
          subject,
          OfflinePiiLockReason.targetAnonymized,
        );
        if (deletion == OfflinePiiDeletionResult.pending) {
          deletion = await _vault.retryLockedDeletion(subject);
        }
        if (deletion != OfflinePiiDeletionResult.deleted) {
          return _event(
            OfflinePiiProbeScenario.cleanup,
            false,
            OfflinePiiProbeReason.cleanupFailed,
            deletionResult: deletion,
          );
        }
      }
      for (final checkpoint in OfflinePiiProbeCheckpoint.values) {
        await _stateStore.clear(checkpoint);
      }
      return _event(
        OfflinePiiProbeScenario.cleanup,
        true,
        OfflinePiiProbeReason.syntheticValuesDeleted,
      );
    } on Object {
      return _event(
        OfflinePiiProbeScenario.cleanup,
        false,
        OfflinePiiProbeReason.cleanupFailed,
      );
    }
  }

  Future<OfflinePiiSaveResult> _replace(
    String subject,
    DateTime authorizedAtUtc,
  ) => _vault.replace(
    externalSubject: subject,
    context: _syntheticContext,
    assignedTargets: <PromotionTargetProfile>[_syntheticTarget],
    authorizedAtUtc: authorizedAtUtc,
  );

  OfflinePiiProbeEvent _event(
    OfflinePiiProbeScenario scenario,
    bool passed,
    OfflinePiiProbeReason reason, {
    OfflinePiiLockReason? lockReason,
    OfflinePiiDeletionResult? deletionResult,
    DateTime? authorizedAtUtc,
    DateTime? expiresAtUtc,
  }) => OfflinePiiProbeEvent(
    recordedAtUtc: _clock.now().toUtc(),
    scenario: scenario,
    outcome: passed
        ? OfflinePiiProbeOutcome.pass
        : OfflinePiiProbeOutcome.failed,
    evidenceClass: OfflinePiiProbeEvidenceClass.simulated,
    reason: reason,
    lockReason: lockReason,
    deletionResult: deletionResult,
    authorizedAtUtc: authorizedAtUtc,
    expiresAtUtc: expiresAtUtc,
  );
}

OfflinePiiLockReason? _lockReason(OfflinePiiReadResult result) =>
    result is OfflinePiiLocked ? result.reason : null;

String _commit(String value) {
  final normalized = value.trim();
  if (!RegExp(r'^[0-9a-f]{7,40}$').hasMatch(normalized)) {
    throw ArgumentError.value(value, 'commit');
  }
  return normalized;
}

String _runId(String value) {
  final normalized = value.trim();
  if (!RegExp(r'^[0-9A-Za-z][0-9A-Za-z._-]{7,63}$').hasMatch(normalized)) {
    throw ArgumentError.value(value, 'runId');
  }
  return normalized;
}

String _version(String value, String name) {
  final normalized = value.trim();
  if (!RegExp(r'^[0-9A-Za-z][0-9A-Za-z._ +()/-]{0,63}$').hasMatch(normalized)) {
    throw ArgumentError.value(value, name);
  }
  return normalized;
}

String _requiredOpaqueId(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty || normalized.length > 128) {
    throw ArgumentError.value(value, name);
  }
  return normalized;
}

void _validateEnvironmentSigning(
  OfflinePiiProbeEnvironment environment,
  OfflinePiiProbeSigning signing,
) {
  final valid = switch (environment) {
    OfflinePiiProbeEnvironment.androidEmulator ||
    OfflinePiiProbeEnvironment.iosSimulator =>
      signing == OfflinePiiProbeSigning.simulator,
    OfflinePiiProbeEnvironment.macosUnsigned =>
      signing == OfflinePiiProbeSigning.unsigned ||
          signing == OfflinePiiProbeSigning.adHoc,
    OfflinePiiProbeEnvironment.webBrowser =>
      signing == OfflinePiiProbeSigning.notApplicable,
    OfflinePiiProbeEnvironment.nativeHost =>
      signing == OfflinePiiProbeSigning.unsigned ||
          signing == OfflinePiiProbeSigning.adHoc ||
          signing == OfflinePiiProbeSigning.notApplicable,
  };
  if (!valid) {
    throw ArgumentError('environment and signing do not match');
  }
}

const _crossProcessSubject = 'synthetic-offline-pii-probe-recovery-v1';
const _nearExpirySubject = 'synthetic-offline-pii-probe-near-expiry-v1';
const _expirySubject = 'synthetic-offline-pii-probe-expiry-v1';
const _revocationSubject = 'synthetic-offline-pii-probe-revocation-v1';
const _deletionFailureSubject =
    'synthetic-offline-pii-probe-deletion-failure-v1';
const _allSubjects = <String>[
  _crossProcessSubject,
  _nearExpirySubject,
  _expirySubject,
  _revocationSubject,
  _deletionFailureSubject,
];

const _syntheticContext = TrustedSessionContext(
  appUserId: '11111111-1111-4111-8111-111111111111',
  workspace: WorkspaceContext(
    id: '22222222-2222-4222-8222-222222222222',
    kind: WorkspaceKind.personal,
    name: 'SYNTHETIC PROBE WORKSPACE',
  ),
  project: ProjectContext(
    id: '33333333-3333-4333-8333-333333333333',
    name: 'SYNTHETIC PROBE PROJECT',
  ),
  questionnaireVersion: QuestionnaireVersionContext(
    id: '44444444-4444-4444-8444-444444444444',
    versionNumber: 1,
  ),
  capabilities: <String>{'view_assigned_target_pii'},
);

final _syntheticTarget = PromotionTargetProfile(
  id: 'synthetic-target-probe-v1',
  type: PromotionTargetType.person,
  displayName: 'SYNTHETIC PROBE PERSON',
  phone: '+1 555 010 9999',
  email: 'offline-pii-probe@example.invalid',
  createdAtUtc: _syntheticCreatedAtUtc,
);

final _syntheticCreatedAtUtc = DateTime.utc(2026, 1, 1);
