import 'dart:convert';

import '../data/local_database.dart';
import 'offline_pii_probe.dart';

/// 保存探针进程检查点。值只含进程和验证轮次元数据，不含身份或 PII。
final class DriftOfflinePiiProbeStateStore
    implements OfflinePiiProbeStateStore {
  const DriftOfflinePiiProbeStateStore(this._database);

  static const _prefix = 'modern.offline_pii_probe.v1.';

  final LocalDatabase _database;

  @override
  Future<OfflinePiiProbeCheckpointState?> read(
    OfflinePiiProbeCheckpoint checkpoint,
  ) async {
    final query = _database.select(_database.dbAppSettings)
      ..where((row) => row.key.equals(_key(checkpoint)));
    final row = await query.getSingleOrNull();
    if (row == null) return null;
    final decoded = jsonDecode(row.value);
    if (decoded is! Map<String, Object?> ||
        decoded['version'] != 1 ||
        decoded['process_id'] is! String ||
        decoded['run_id'] is! String ||
        decoded['commit'] is! String ||
        decoded['environment'] is! String ||
        (decoded['authorized_at_utc'] != null &&
            decoded['authorized_at_utc'] is! String)) {
      throw const FormatException('offline PII probe checkpoint is invalid');
    }
    return OfflinePiiProbeCheckpointState(
      processId: decoded['process_id']! as String,
      runId: decoded['run_id']! as String,
      commit: decoded['commit']! as String,
      environment: OfflinePiiProbeEnvironment.parse(
        decoded['environment']! as String,
      ),
      authorizedAtUtc: decoded['authorized_at_utc'] == null
          ? null
          : DateTime.parse(decoded['authorized_at_utc']! as String).toUtc(),
    );
  }

  @override
  Future<void> write(
    OfflinePiiProbeCheckpoint checkpoint,
    OfflinePiiProbeCheckpointState state,
  ) async {
    await _database
        .into(_database.dbAppSettings)
        .insertOnConflictUpdate(
          DbAppSettingsCompanion.insert(
            key: _key(checkpoint),
            value: jsonEncode(<String, Object?>{
              'version': 1,
              'process_id': state.processId,
              'run_id': state.runId,
              'commit': state.commit,
              'environment': state.environment.storageValue,
              'authorized_at_utc': state.authorizedAtUtc?.toIso8601String(),
            }),
          ),
        );
  }

  @override
  Future<void> clear(OfflinePiiProbeCheckpoint checkpoint) async {
    await (_database.delete(
      _database.dbAppSettings,
    )..where((row) => row.key.equals(_key(checkpoint)))).go();
  }

  String _key(OfflinePiiProbeCheckpoint checkpoint) =>
      '$_prefix${checkpoint.name}';
}
