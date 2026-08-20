import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/data/local_database.dart';
import 'package:tongxingzhe_app/privacy/drift_offline_pii_probe_state_store.dart';
import 'package:tongxingzhe_app/privacy/offline_pii_probe.dart';

void main() {
  test('进程检查点在 store 重建后仍存在且不含 PII', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final first = DriftOfflinePiiProbeStateStore(database);
    await first.write(
      OfflinePiiProbeCheckpoint.crossProcessWrite,
      OfflinePiiProbeCheckpointState(
        processId: 'native-process-123',
        runId: 'probe-run-001',
        commit: 'abcdef1',
        environment: OfflinePiiProbeEnvironment.iosSimulator,
        authorizedAtUtc: DateTime.utc(2026, 8, 20, 12),
      ),
    );

    final restored = await DriftOfflinePiiProbeStateStore(
      database,
    ).read(OfflinePiiProbeCheckpoint.crossProcessWrite);
    final rows = await database.select(database.dbAppSettings).get();
    final stored = rows.map((row) => '${row.key}\n${row.value}').join('\n');

    expect(restored?.processId, 'native-process-123');
    expect(restored?.runId, 'probe-run-001');
    expect(restored?.commit, 'abcdef1');
    expect(restored?.environment, OfflinePiiProbeEnvironment.iosSimulator);
    expect(restored?.authorizedAtUtc, DateTime.utc(2026, 8, 20, 12));
    expect(stored, isNot(contains('external-subject')));
    expect(stored, isNot(contains('display_name')));
    expect(stored, isNot(contains('phone')));
    expect(stored, isNot(contains('email')));

    await first.clear(OfflinePiiProbeCheckpoint.crossProcessWrite);
    expect(
      await first.read(OfflinePiiProbeCheckpoint.crossProcessWrite),
      isNull,
    );
  });
}
