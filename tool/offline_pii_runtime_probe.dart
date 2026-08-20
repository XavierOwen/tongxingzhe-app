// Public constructor arguments intentionally differ from private field names.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tongxingzhe_app/data/local_database.dart';
import 'package:tongxingzhe_app/data/local_database_factory.dart';
import 'package:tongxingzhe_app/device/device_identity_store.dart';
import 'package:tongxingzhe_app/foundation/runtime_values.dart';
import 'package:tongxingzhe_app/platform/platform_capabilities.dart';
import 'package:tongxingzhe_app/privacy/drift_offline_pii_probe_state_store.dart';
import 'package:tongxingzhe_app/privacy/drift_offline_pii_lock_store.dart';
import 'package:tongxingzhe_app/privacy/flutter_secure_value_store.dart';
import 'package:tongxingzhe_app/privacy/offline_pii_probe.dart';
import 'package:tongxingzhe_app/privacy/offline_pii_probe_process.dart';
import 'package:tongxingzhe_app/privacy/offline_pii_vault.dart';
import 'package:tongxingzhe_app/privacy/secure_value_store_capability_probe.dart';

const _commit = String.fromEnvironment('OFFLINE_PII_PROBE_COMMIT');
const _runId = String.fromEnvironment('OFFLINE_PII_PROBE_RUN_ID');
const _flutterVersion = String.fromEnvironment(
  'OFFLINE_PII_PROBE_FLUTTER_VERSION',
);
const _osVersion = String.fromEnvironment('OFFLINE_PII_PROBE_OS_VERSION');
const _environment = String.fromEnvironment('OFFLINE_PII_PROBE_ENVIRONMENT');
const _signing = String.fromEnvironment('OFFLINE_PII_PROBE_SIGNING');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    runApp(OfflinePiiProbeApp(configuration: _configurationFromEnvironment()));
  } on Object {
    runApp(const _ProbeConfigurationErrorApp());
  }
}

OfflinePiiProbeConfiguration _configurationFromEnvironment() =>
    OfflinePiiProbeConfiguration(
      commit: _commit,
      runId: _runId,
      flutterVersion: _flutterVersion,
      osVersion: _osVersion,
      environment: OfflinePiiProbeEnvironment.parse(_environment),
      signing: OfflinePiiProbeSigning.parse(_signing),
    );

final class _ProbeConfigurationErrorApp extends StatelessWidget {
  const _ProbeConfigurationErrorApp();

  @override
  Widget build(BuildContext context) => const MaterialApp(
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('探针配置无效。请按学习文档传入 commit、run ID、版本、运行环境和签名类型。'),
        ),
      ),
    ),
  );
}

final class OfflinePiiProbeApp extends StatelessWidget {
  const OfflinePiiProbeApp({super.key, required this.configuration});

  final OfflinePiiProbeConfiguration configuration;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: OfflinePiiProbeScreen(configuration: configuration),
  );
}

typedef OfflinePiiProbeInitializer =
    Future<OfflinePiiProbeSession> Function(
      OfflinePiiProbeConfiguration configuration,
    );

final class OfflinePiiProbeSession {
  const OfflinePiiProbeSession({
    required this.recorder,
    required this.actions,
    required Future<void> Function() close,
  }) : _close = close;

  final OfflinePiiProbeRecorder recorder;
  final OfflinePiiProbeActions? actions;
  final Future<void> Function() _close;

  bool get supported => actions != null;

  Future<void> close() => _close();
}

Future<OfflinePiiProbeSession> initializeOfflinePiiProbe(
  OfflinePiiProbeConfiguration configuration,
) async {
  final platform = _currentPlatform();
  final recorder = OfflinePiiProbeRecorder(
    platform: platform,
    configuration: configuration,
  );
  if (!configuration.matchesPlatform(platform)) {
    recorder.record(
      _gateEvent(
        OfflinePiiProbeOutcome.blocked,
        OfflinePiiProbeEvidenceClass.blocked,
        OfflinePiiProbeReason.initializationFailed,
      ),
    );
    return OfflinePiiProbeSession(
      recorder: recorder,
      actions: null,
      close: _noOpClose,
    );
  }

  final rawSecureStore = FlutterSecureValueStore();
  final capabilitiesProvider = kIsWeb
      ? const FlutterPlatformCapabilitiesProvider()
      : FlutterPlatformCapabilitiesProvider(
          secureStorageProbe: SecureValueStoreCapabilityProbe(
            store: rawSecureStore,
            idGenerator: SecureIdGenerator(),
          ),
        );

  LocalDatabase? database;
  try {
    final capabilities = await capabilitiesProvider.load();
    if (!canInitializeOfflinePiiProbe(capabilities)) {
      recorder.record(
        _gateEvent(
          OfflinePiiProbeOutcome.unsupported,
          OfflinePiiProbeEvidenceClass.unsupported,
          OfflinePiiProbeReason.sensitiveStorageDisabled,
        ),
      );
      return OfflinePiiProbeSession(
        recorder: recorder,
        actions: null,
        close: _noOpClose,
      );
    }

    database = const DriftLocalDatabaseFactory().open();
    final idGenerator = SecureIdGenerator();
    final installationId = await DeviceIdentityStore(
      database,
      idGenerator,
    ).loadOrCreate();
    final faultInjectingStore = _FaultInjectingSecureValueStore(rawSecureStore);
    final runner = OfflinePiiProbeRunner(
      vault: OfflinePiiVault(
        secureStore: faultInjectingStore,
        lockStore: DriftOfflinePiiLockStore(database),
        clock: const SystemClock(),
        installationId: installationId,
      ),
      recorder: recorder,
      clock: const SystemClock(),
      stateStore: DriftOfflinePiiProbeStateStore(database),
      launchId: currentOfflinePiiProbeProcessId(),
      armNextDeleteFailure: faultInjectingStore.armNextDeleteFailure,
    );
    recorder.record(
      _gateEvent(
        OfflinePiiProbeOutcome.pass,
        OfflinePiiProbeEvidenceClass.simulated,
        OfflinePiiProbeReason.secureStorageAndDatabaseAvailable,
      ),
    );
    return OfflinePiiProbeSession(
      recorder: recorder,
      actions: runner,
      close: database.close,
    );
  } on Object {
    if (database != null) await database.close();
    recorder.record(
      _gateEvent(
        OfflinePiiProbeOutcome.blocked,
        OfflinePiiProbeEvidenceClass.blocked,
        OfflinePiiProbeReason.initializationFailed,
      ),
    );
    return OfflinePiiProbeSession(
      recorder: recorder,
      actions: null,
      close: _noOpClose,
    );
  }
}

final class OfflinePiiProbeScreen extends StatefulWidget {
  const OfflinePiiProbeScreen({
    super.key,
    required this.configuration,
    this.initialize = initializeOfflinePiiProbe,
  });

  final OfflinePiiProbeConfiguration configuration;
  final OfflinePiiProbeInitializer initialize;

  @override
  State<OfflinePiiProbeScreen> createState() => _OfflinePiiProbeScreenState();
}

final class _OfflinePiiProbeScreenState extends State<OfflinePiiProbeScreen> {
  OfflinePiiProbeSession? _session;
  var _busy = false;
  var _status = '正在检查本机数据库和平台安全存储。';

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  @override
  void dispose() {
    final session = _session;
    if (session != null) unawaited(session.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final ready = session?.supported == true && !_busy;
    return Scaffold(
      appBar: AppBar(title: const Text('离线 PII 模拟验证探针')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            const Text(
              '本工具只写入固定 synthetic 资料，不连接 Backend。模拟器和 unsigned 构建结果不能替代真机或正式签名验收。',
            ),
            const SizedBox(height: 12),
            Text(_status, key: const ValueKey('probe-status')),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: ready
                  ? () => _run(OfflinePiiProbeScenario.writeRead)
                  : null,
              child: const Text('1. 写入并读回 synthetic 快照'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: ready
                  ? () => _run(OfflinePiiProbeScenario.crossProcessRecovery)
                  : null,
              child: const Text('2. 完全结束 App 后重新启动，再检查恢复'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: ready
                  ? () => _run(OfflinePiiProbeScenario.nearExpiry)
                  : null,
              child: const Text('3. 检查 72h 前一分钟仍可读'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: ready
                  ? () => _run(OfflinePiiProbeScenario.expiry)
                  : null,
              child: const Text('4. 检查 72h 整立即锁定'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: ready
                  ? () => _run(OfflinePiiProbeScenario.authorizationRevocation)
                  : null,
              child: const Text('5. 模拟授权撤销并立即删除'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: ready
                  ? () => _run(OfflinePiiProbeScenario.revocationDeleteFailure)
                  : null,
              child: const Text('6. 模拟登出并让下一次删除失败'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: ready
                  ? () => _run(OfflinePiiProbeScenario.deletionRetry)
                  : null,
              child: const Text('7. 重新启动后重试删除'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: ready
                  ? () => _run(OfflinePiiProbeScenario.cleanup)
                  : null,
              child: const Text('清除全部 synthetic 密文'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: session == null ? null : _copyEvidence,
              child: const Text('复制脱敏证据 JSON'),
            ),
            const Divider(height: 32),
            const Text('当前证据', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SelectableText(
              _evidenceJson(),
              key: const ValueKey('probe-evidence'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _initialize() async {
    final session = await widget.initialize(widget.configuration);
    if (!mounted) {
      await session.close();
      return;
    }
    setState(() {
      _session = session;
      _status = session.supported
          ? '探针已就绪。第 2 步和第 7 步必须在完全结束 App 后执行。'
          : '当前平台保持失败关闭。请查看证据中的 platformGate 状态。';
    });
  }

  Future<void> _run(OfflinePiiProbeScenario scenario) async {
    final actions = _session?.actions;
    if (actions == null) return;
    setState(() {
      _busy = true;
      _status = '正在执行 ${scenario.name}。';
    });
    late final OfflinePiiProbeEvent event;
    try {
      event = await actions.run(scenario);
    } on Object {
      event = OfflinePiiProbeEvent(
        recordedAtUtc: DateTime.now().toUtc(),
        scenario: scenario,
        outcome: OfflinePiiProbeOutcome.failed,
        evidenceClass: OfflinePiiProbeEvidenceClass.simulated,
        reason: OfflinePiiProbeReason.operationFailed,
      );
      _session?.recorder.record(event);
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = _statusFor(event);
    });
  }

  Future<void> _copyEvidence() async {
    await Clipboard.setData(ClipboardData(text: _evidenceJson()));
    if (!mounted) return;
    setState(() => _status = '已复制脱敏证据 JSON。');
  }

  String _evidenceJson() {
    final session = _session;
    if (session == null) return '{}';
    return const JsonEncoder.withIndent(
      '  ',
    ).convert(session.recorder.toJson());
  }
}

String _statusFor(OfflinePiiProbeEvent event) => switch (event.outcome) {
  OfflinePiiProbeOutcome.pass => '${event.scenario.name} 通过（仅为模拟证据）。',
  OfflinePiiProbeOutcome.failed => '${event.scenario.name} 未通过。请先清理，再重试。',
  OfflinePiiProbeOutcome.unsupported => '当前平台不装配离线 PII。',
  OfflinePiiProbeOutcome.blocked => '当前环境无法初始化探针。',
};

OfflinePiiProbeEvent _gateEvent(
  OfflinePiiProbeOutcome outcome,
  OfflinePiiProbeEvidenceClass evidenceClass,
  OfflinePiiProbeReason reason,
) => OfflinePiiProbeEvent(
  recordedAtUtc: DateTime.now().toUtc(),
  scenario: OfflinePiiProbeScenario.platformGate,
  outcome: outcome,
  evidenceClass: evidenceClass,
  reason: reason,
);

AppPlatform _currentPlatform() {
  if (kIsWeb) return AppPlatform.web;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => AppPlatform.android,
    TargetPlatform.iOS => AppPlatform.ios,
    TargetPlatform.macOS => AppPlatform.macos,
    TargetPlatform.windows => AppPlatform.windows,
    TargetPlatform.linux => AppPlatform.linux,
    TargetPlatform.fuchsia => AppPlatform.unknown,
  };
}

Future<void> _noOpClose() async {}

final class _FaultInjectingSecureValueStore implements SecureValueStore {
  _FaultInjectingSecureValueStore(this._inner);

  final SecureValueStore _inner;
  var _failNextDelete = false;

  void armNextDeleteFailure() => _failNextDelete = true;

  @override
  Future<void> delete(String key) {
    if (_failNextDelete) {
      _failNextDelete = false;
      throw StateError('synthetic secure-storage delete failure');
    }
    return _inner.delete(key);
  }

  @override
  Future<String?> read(String key) => _inner.read(key);

  @override
  Future<void> write(String key, String value) => _inner.write(key, value);
}
