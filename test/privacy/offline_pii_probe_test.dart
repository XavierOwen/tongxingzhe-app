import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/platform/platform_capabilities.dart';
import 'package:tongxingzhe_app/privacy/offline_pii_probe.dart';
import 'package:tongxingzhe_app/privacy/offline_pii_vault.dart';

import '../support/fake_runtime_values.dart';

void main() {
  test('配置拒绝运行环境与签名类型不匹配', () {
    expect(
      () => OfflinePiiProbeConfiguration(
        commit: 'abcdef1',
        runId: 'probe-run-001',
        flutterVersion: '3.44.2',
        osVersion: 'iOS 18.4',
        environment: OfflinePiiProbeEnvironment.iosSimulator,
        signing: OfflinePiiProbeSigning.unsigned,
      ),
      throwsArgumentError,
    );

    final configuration = _configuration();
    expect(configuration.matchesPlatform(AppPlatform.ios), isTrue);
    expect(configuration.matchesPlatform(AppPlatform.android), isFalse);
    expect(configuration.evidenceClass, OfflinePiiProbeEvidenceClass.simulated);
  });

  test('Web durable database 未验证时保持失败关闭', () {
    const capabilities = PlatformCapabilities(
      platform: AppPlatform.web,
      values: <PlatformCapability, CapabilityAvailability>{
        PlatformCapability.durableLocalDatabase:
            CapabilityAvailability.runtimeProbeRequired,
        PlatformCapability.secureSessionStorage:
            CapabilityAvailability.available,
      },
    );
    final recorder = OfflinePiiProbeRecorder(
      platform: AppPlatform.web,
      configuration: OfflinePiiProbeConfiguration(
        commit: 'abcdef1',
        runId: 'probe-run-web',
        flutterVersion: '3.44.2',
        osVersion: 'Chrome 140',
        environment: OfflinePiiProbeEnvironment.webBrowser,
        signing: OfflinePiiProbeSigning.notApplicable,
      ),
    );
    recorder.record(
      OfflinePiiProbeEvent(
        recordedAtUtc: DateTime.utc(2026, 8, 20, 12),
        scenario: OfflinePiiProbeScenario.platformGate,
        outcome: OfflinePiiProbeOutcome.unsupported,
        evidenceClass: OfflinePiiProbeEvidenceClass.unsupported,
        reason: OfflinePiiProbeReason.sensitiveStorageDisabled,
      ),
    );

    expect(canInitializeOfflinePiiProbe(capabilities), isFalse);
    expect(recorder.evidenceClass, OfflinePiiProbeEvidenceClass.unsupported);
    expect(recorder.toJson()['evidenceClass'], 'unsupported');
  });

  test('写读、实例重建、近到期和到期阶段都使用生产 vault 合同', () async {
    final secureStore = _MemorySecureValueStore();
    final lockStore = _MemoryOfflinePiiLockStore();
    final stateStore = _MemoryOfflinePiiProbeStateStore();
    final clock = MutableClock(DateTime.utc(2026, 8, 20, 12));
    final first = _runner(
      secureStore: secureStore,
      lockStore: lockStore,
      stateStore: stateStore,
      clock: clock,
      launchId: 'launch-1',
    );

    final writeRead = await first.runner.run(OfflinePiiProbeScenario.writeRead);
    final sameProcessRecovery = await first.runner.run(
      OfflinePiiProbeScenario.crossProcessRecovery,
    );
    clock.value = clock.value.add(const Duration(hours: 1));
    final reconstructed = _runner(
      secureStore: secureStore,
      lockStore: lockStore,
      stateStore: stateStore,
      clock: clock,
      launchId: 'launch-2',
    );
    final recovered = await reconstructed.runner.run(
      OfflinePiiProbeScenario.crossProcessRecovery,
    );
    final nearExpiry = await reconstructed.runner.run(
      OfflinePiiProbeScenario.nearExpiry,
    );
    final expiry = await reconstructed.runner.run(
      OfflinePiiProbeScenario.expiry,
    );

    expect(writeRead.outcome, OfflinePiiProbeOutcome.pass);
    expect(writeRead.authorizedAtUtc, DateTime.utc(2026, 8, 20, 12));
    expect(sameProcessRecovery.reason, OfflinePiiProbeReason.restartRequired);
    expect(recovered.reason, OfflinePiiProbeReason.recoveredWithoutRenewal);
    expect(recovered.authorizedAtUtc, DateTime.utc(2026, 8, 20, 12));
    expect(recovered.expiresAtUtc, DateTime.utc(2026, 8, 23, 12));
    expect(nearExpiry.reason, OfflinePiiProbeReason.readableBeforeExpiry);
    expect(expiry.reason, OfflinePiiProbeReason.expiredAndLocked);
    expect(expiry.lockReason, OfflinePiiLockReason.expired);
  });

  test('删除失败后持久锁阻止读取，下一实例可以重试删除', () async {
    final secureStore = _MemorySecureValueStore();
    final lockStore = _MemoryOfflinePiiLockStore();
    final stateStore = _MemoryOfflinePiiProbeStateStore();
    final clock = MutableClock(DateTime.utc(2026, 8, 20, 12));
    final first = _runner(
      secureStore: secureStore,
      lockStore: lockStore,
      stateStore: stateStore,
      clock: clock,
      launchId: 'launch-1',
    );

    final failedDeletion = await first.runner.run(
      OfflinePiiProbeScenario.revocationDeleteFailure,
    );
    expect(failedDeletion.outcome, OfflinePiiProbeOutcome.pass);
    expect(failedDeletion.deletionResult, OfflinePiiDeletionResult.pending);
    expect(secureStore.values, isNotEmpty);
    final sameProcessRetry = await first.runner.run(
      OfflinePiiProbeScenario.deletionRetry,
    );
    expect(sameProcessRetry.reason, OfflinePiiProbeReason.restartRequired);

    final reconstructed = _runner(
      secureStore: secureStore,
      lockStore: lockStore,
      stateStore: stateStore,
      clock: clock,
      launchId: 'launch-2',
    );
    final retry = await reconstructed.runner.run(
      OfflinePiiProbeScenario.deletionRetry,
    );

    expect(retry.outcome, OfflinePiiProbeOutcome.pass);
    expect(retry.deletionResult, OfflinePiiDeletionResult.deleted);
    expect(retry.lockReason, OfflinePiiLockReason.signedOut);
    expect(secureStore.values, isEmpty);
  });

  test('授权撤销与登出使用不同锁因', () async {
    final session = _runner(
      secureStore: _MemorySecureValueStore(),
      lockStore: _MemoryOfflinePiiLockStore(),
      stateStore: _MemoryOfflinePiiProbeStateStore(),
      clock: MutableClock(DateTime.utc(2026, 8, 20, 12)),
      launchId: 'launch-1',
    );

    final revocation = await session.runner.run(
      OfflinePiiProbeScenario.authorizationRevocation,
    );
    final logoutFailure = await session.runner.run(
      OfflinePiiProbeScenario.revocationDeleteFailure,
    );

    expect(revocation.outcome, OfflinePiiProbeOutcome.pass);
    expect(revocation.lockReason, OfflinePiiLockReason.unauthorized);
    expect(revocation.deletionResult, OfflinePiiDeletionResult.deleted);
    expect(logoutFailure.outcome, OfflinePiiProbeOutcome.pass);
    expect(logoutFailure.lockReason, OfflinePiiLockReason.signedOut);
  });

  test('新一轮写入失败会清除旧 checkpoint，不能沿用旧恢复证据', () async {
    final secureStore = _MemorySecureValueStore();
    final lockStore = _MemoryOfflinePiiLockStore();
    final stateStore = _MemoryOfflinePiiProbeStateStore();
    final clock = MutableClock(DateTime.utc(2026, 8, 20, 12));
    final first = _runner(
      secureStore: secureStore,
      lockStore: lockStore,
      stateStore: stateStore,
      clock: clock,
      launchId: 'launch-1',
    );
    expect(
      (await first.runner.run(OfflinePiiProbeScenario.writeRead)).outcome,
      OfflinePiiProbeOutcome.pass,
    );

    secureStore.failWrite = true;
    final second = _runner(
      secureStore: secureStore,
      lockStore: lockStore,
      stateStore: stateStore,
      clock: clock,
      launchId: 'launch-2',
    );
    expect(
      (await second.runner.run(OfflinePiiProbeScenario.writeRead)).outcome,
      OfflinePiiProbeOutcome.failed,
    );
    secureStore.failWrite = false;
    final third = _runner(
      secureStore: secureStore,
      lockStore: lockStore,
      stateStore: stateStore,
      clock: clock,
      launchId: 'launch-3',
    );

    expect(
      (await third.runner.run(
        OfflinePiiProbeScenario.crossProcessRecovery,
      )).reason,
      OfflinePiiProbeReason.restartRequired,
    );
  });

  test('恢复必须与首次写入的授权时间一致', () async {
    final secureStore = _MemorySecureValueStore();
    final lockStore = _MemoryOfflinePiiLockStore();
    final stateStore = _MemoryOfflinePiiProbeStateStore();
    final clock = MutableClock(DateTime.utc(2026, 8, 20, 12));
    final first = _runner(
      secureStore: secureStore,
      lockStore: lockStore,
      stateStore: stateStore,
      clock: clock,
      launchId: 'launch-1',
    );
    await first.runner.run(OfflinePiiProbeScenario.writeRead);
    stateStore.values[OfflinePiiProbeCheckpoint.crossProcessWrite] =
        OfflinePiiProbeCheckpointState(
          processId: 'launch-1',
          runId: 'probe-run-001',
          commit: 'abcdef1',
          environment: OfflinePiiProbeEnvironment.iosSimulator,
          authorizedAtUtc: DateTime.utc(2026, 8, 20, 12, 1),
        );
    final reconstructed = _runner(
      secureStore: secureStore,
      lockStore: lockStore,
      stateStore: stateStore,
      clock: clock,
      launchId: 'launch-2',
    );

    final recovery = await reconstructed.runner.run(
      OfflinePiiProbeScenario.crossProcessRecovery,
    );

    expect(recovery.outcome, OfflinePiiProbeOutcome.failed);
    expect(recovery.reason, OfflinePiiProbeReason.recoveryUnavailable);
  });

  test('不同 run ID 不能消费上一轮 checkpoint', () async {
    final secureStore = _MemorySecureValueStore();
    final lockStore = _MemoryOfflinePiiLockStore();
    final stateStore = _MemoryOfflinePiiProbeStateStore();
    final clock = MutableClock(DateTime.utc(2026, 8, 20, 12));
    final first = _runner(
      secureStore: secureStore,
      lockStore: lockStore,
      stateStore: stateStore,
      clock: clock,
      launchId: 'launch-1',
      probeRunId: 'probe-run-001',
    );
    await first.runner.run(OfflinePiiProbeScenario.writeRead);

    final nextRun = _runner(
      secureStore: secureStore,
      lockStore: lockStore,
      stateStore: stateStore,
      clock: clock,
      launchId: 'launch-2',
      probeRunId: 'probe-run-002',
    );

    expect(
      (await nextRun.runner.run(
        OfflinePiiProbeScenario.crossProcessRecovery,
      )).reason,
      OfflinePiiProbeReason.restartRequired,
    );
  });

  test('证据 JSON 只含 allowlist 状态，不含 synthetic 快照或异常正文', () async {
    final secureStore = _MemorySecureValueStore();
    final session = _runner(
      secureStore: secureStore,
      lockStore: _MemoryOfflinePiiLockStore(),
      stateStore: _MemoryOfflinePiiProbeStateStore(),
      clock: MutableClock(DateTime.utc(2026, 8, 20, 12)),
      launchId: 'launch-1',
    );
    await session.runner.run(OfflinePiiProbeScenario.writeRead);
    await session.runner.run(OfflinePiiProbeScenario.revocationDeleteFailure);

    final encoded = jsonEncode(session.recorder.toJson());

    expect(encoded, contains('"evidenceClass":"simulated"'));
    expect(encoded, contains('deletionPendingAndLocked'));
    for (final forbidden in <String>[
      'SYNTHETIC PROBE PERSON',
      '+1 555 010 9999',
      'offline-pii-probe@example.invalid',
      'synthetic-offline-pii-probe',
      '11111111-1111-4111-8111-111111111111',
      'assigned_targets',
      'display_name',
      'phone',
      'email',
      'follow_up_note',
      'synthetic secure-storage delete failure',
    ]) {
      expect(encoded, isNot(contains(forbidden)), reason: forbidden);
    }
  });

  test('清理只删除固定探针 scope 的 synthetic 密文', () async {
    final secureStore = _MemorySecureValueStore()
      ..values['unrelated-key'] = 'unrelated-value';
    final session = _runner(
      secureStore: secureStore,
      lockStore: _MemoryOfflinePiiLockStore(),
      stateStore: _MemoryOfflinePiiProbeStateStore(),
      clock: MutableClock(DateTime.utc(2026, 8, 20, 12)),
      launchId: 'launch-1',
    );
    await session.runner.run(OfflinePiiProbeScenario.writeRead);
    await session.runner.run(OfflinePiiProbeScenario.nearExpiry);

    final cleanup = await session.runner.run(OfflinePiiProbeScenario.cleanup);

    expect(cleanup.outcome, OfflinePiiProbeOutcome.pass);
    expect(secureStore.values, {'unrelated-key': 'unrelated-value'});
  });
}

OfflinePiiProbeConfiguration _configuration([String runId = 'probe-run-001']) =>
    OfflinePiiProbeConfiguration(
      commit: 'abcdef1',
      runId: runId,
      flutterVersion: '3.44.2',
      osVersion: 'iOS 18.4',
      environment: OfflinePiiProbeEnvironment.iosSimulator,
      signing: OfflinePiiProbeSigning.simulator,
    );

({OfflinePiiProbeRunner runner, OfflinePiiProbeRecorder recorder}) _runner({
  required _MemorySecureValueStore secureStore,
  required _MemoryOfflinePiiLockStore lockStore,
  required _MemoryOfflinePiiProbeStateStore stateStore,
  required MutableClock clock,
  required String launchId,
  String probeRunId = 'probe-run-001',
}) {
  final recorder = OfflinePiiProbeRecorder(
    platform: AppPlatform.ios,
    configuration: _configuration(probeRunId),
  );
  final vault = OfflinePiiVault(
    secureStore: secureStore,
    lockStore: lockStore,
    clock: clock,
    installationId: 'synthetic-installation-id',
  );
  return (
    runner: OfflinePiiProbeRunner(
      vault: vault,
      recorder: recorder,
      clock: clock,
      stateStore: stateStore,
      launchId: launchId,
      armNextDeleteFailure: secureStore.armNextDeleteFailure,
    ),
    recorder: recorder,
  );
}

final class _MemorySecureValueStore implements SecureValueStore {
  final values = <String, String>{};
  var _failNextDelete = false;
  var failWrite = false;

  void armNextDeleteFailure() => _failNextDelete = true;

  @override
  Future<void> delete(String key) async {
    if (_failNextDelete) {
      _failNextDelete = false;
      throw StateError('synthetic secure-storage delete failure');
    }
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (failWrite) throw StateError('synthetic write failure');
    values[key] = value;
  }
}

final class _MemoryOfflinePiiLockStore implements OfflinePiiLockStore {
  final values = <String, OfflinePiiLock>{};

  @override
  Future<void> clear(String scopeKey) async => values.remove(scopeKey);

  @override
  Future<OfflinePiiLock?> read(String scopeKey) async => values[scopeKey];

  @override
  Future<void> write(String scopeKey, OfflinePiiLock lock) async {
    values[scopeKey] = lock;
  }
}

final class _MemoryOfflinePiiProbeStateStore
    implements OfflinePiiProbeStateStore {
  final values = <OfflinePiiProbeCheckpoint, OfflinePiiProbeCheckpointState>{};

  @override
  Future<void> clear(OfflinePiiProbeCheckpoint checkpoint) async {
    values.remove(checkpoint);
  }

  @override
  Future<OfflinePiiProbeCheckpointState?> read(
    OfflinePiiProbeCheckpoint checkpoint,
  ) async => values[checkpoint];

  @override
  Future<void> write(
    OfflinePiiProbeCheckpoint checkpoint,
    OfflinePiiProbeCheckpointState state,
  ) async {
    values[checkpoint] = state;
  }
}
