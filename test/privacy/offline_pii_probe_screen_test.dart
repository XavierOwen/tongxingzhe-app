import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/platform/platform_capabilities.dart';
import 'package:tongxingzhe_app/privacy/offline_pii_probe.dart';

import '../../tool/offline_pii_runtime_probe.dart';

void main() {
  testWidgets('支持的平台可以运行阶段并复制脱敏证据', (tester) async {
    final recorder = _recorder();
    recorder.record(_gateEvent(OfflinePiiProbeOutcome.pass));
    final actions = _FakeActions(recorder);

    await tester.pumpWidget(
      MaterialApp(
        home: OfflinePiiProbeScreen(
          configuration: _configuration,
          initialize: (_) async => OfflinePiiProbeSession(
            recorder: recorder,
            actions: actions,
            close: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('探针已就绪'), findsOneWidget);
    await tester.tap(find.text('1. 写入并读回 synthetic 快照'));
    await tester.pumpAndSettle();

    expect(actions.scenarios, [OfflinePiiProbeScenario.writeRead]);
    expect(find.textContaining('writeRead 通过'), findsOneWidget);
    expect(recorder.events.last.reason, OfflinePiiProbeReason.savedAndReadable);
  });

  testWidgets('不支持的平台保持失败关闭且禁用所有写入阶段', (tester) async {
    final recorder = _recorder();
    recorder.record(
      OfflinePiiProbeEvent(
        recordedAtUtc: DateTime.utc(2026, 8, 20, 12),
        scenario: OfflinePiiProbeScenario.platformGate,
        outcome: OfflinePiiProbeOutcome.unsupported,
        evidenceClass: OfflinePiiProbeEvidenceClass.unsupported,
        reason: OfflinePiiProbeReason.sensitiveStorageDisabled,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: OfflinePiiProbeScreen(
          configuration: _configuration,
          initialize: (_) async => OfflinePiiProbeSession(
            recorder: recorder,
            actions: null,
            close: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('当前平台保持失败关闭'), findsOneWidget);
    final writeButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '1. 写入并读回 synthetic 快照'),
    );
    expect(writeButton.onPressed, isNull);
    expect(
      recorder.events.single.reason,
      OfflinePiiProbeReason.sensitiveStorageDisabled,
    );
  });

  testWidgets('意外异常只记录固定失败码并恢复按钮', (tester) async {
    final recorder = _recorder();
    recorder.record(_gateEvent(OfflinePiiProbeOutcome.pass));

    await tester.pumpWidget(
      MaterialApp(
        home: OfflinePiiProbeScreen(
          configuration: _configuration,
          initialize: (_) async => OfflinePiiProbeSession(
            recorder: recorder,
            actions: const _ThrowingActions(),
            close: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('1. 写入并读回 synthetic 快照'));
    await tester.pumpAndSettle();

    expect(find.textContaining('writeRead 未通过'), findsOneWidget);
    final writeButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '1. 写入并读回 synthetic 快照'),
    );
    expect(writeButton.onPressed, isNotNull);
    expect(recorder.events.last.reason, OfflinePiiProbeReason.operationFailed);
  });
}

final _configuration = OfflinePiiProbeConfiguration(
  commit: 'abcdef1',
  runId: 'probe-run-001',
  flutterVersion: '3.44.2',
  osVersion: 'iOS 18.4',
  environment: OfflinePiiProbeEnvironment.iosSimulator,
  signing: OfflinePiiProbeSigning.simulator,
);

OfflinePiiProbeRecorder _recorder() => OfflinePiiProbeRecorder(
  platform: AppPlatform.ios,
  configuration: _configuration,
);

OfflinePiiProbeEvent _gateEvent(OfflinePiiProbeOutcome outcome) =>
    OfflinePiiProbeEvent(
      recordedAtUtc: DateTime.utc(2026, 8, 20, 12),
      scenario: OfflinePiiProbeScenario.platformGate,
      outcome: outcome,
      evidenceClass: OfflinePiiProbeEvidenceClass.simulated,
      reason: OfflinePiiProbeReason.secureStorageAndDatabaseAvailable,
    );

final class _FakeActions implements OfflinePiiProbeActions {
  _FakeActions(this.recorder);

  final OfflinePiiProbeRecorder recorder;
  final scenarios = <OfflinePiiProbeScenario>[];

  @override
  Future<OfflinePiiProbeEvent> run(OfflinePiiProbeScenario scenario) async {
    scenarios.add(scenario);
    final event = OfflinePiiProbeEvent(
      recordedAtUtc: DateTime.utc(2026, 8, 20, 12, 1),
      scenario: scenario,
      outcome: OfflinePiiProbeOutcome.pass,
      evidenceClass: OfflinePiiProbeEvidenceClass.simulated,
      reason: OfflinePiiProbeReason.savedAndReadable,
    );
    recorder.record(event);
    return event;
  }
}

final class _ThrowingActions implements OfflinePiiProbeActions {
  const _ThrowingActions();

  @override
  Future<OfflinePiiProbeEvent> run(OfflinePiiProbeScenario scenario) =>
      throw StateError('secret value that must not enter evidence');
}
