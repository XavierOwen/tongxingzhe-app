import 'dart:convert';

import '../data/local_database.dart';
import 'offline_pii_vault.dart';

/// 普通 Drift 只保存不含 PII 的 fail-closed 锁；密文仍只在平台安全存储中。
final class DriftOfflinePiiLockStore implements OfflinePiiLockStore {
  const DriftOfflinePiiLockStore(this._database);

  static const _prefix = 'modern.offline_pii_lock.v1.';

  final LocalDatabase _database;

  @override
  Future<OfflinePiiLock?> read(String scopeKey) async {
    final query = _database.select(_database.dbAppSettings)
      ..where((row) => row.key.equals(_key(scopeKey)));
    final row = await query.getSingleOrNull();
    if (row == null) return null;
    final value = jsonDecode(row.value);
    if (value is! Map<String, Object?> || value['version'] != 1) {
      throw const FormatException('offline PII lock is invalid');
    }
    final reasonName = value['reason'];
    final lockedAt = value['locked_at_utc'];
    if (reasonName is! String || lockedAt is! String) {
      throw const FormatException('offline PII lock is incomplete');
    }
    return OfflinePiiLock(
      reason: OfflinePiiLockReason.values.firstWhere(
        (candidate) => candidate.name == reasonName,
        orElse: () =>
            throw const FormatException('offline PII lock reason is invalid'),
      ),
      lockedAtUtc: DateTime.parse(lockedAt).toUtc(),
    );
  }

  @override
  Future<void> write(String scopeKey, OfflinePiiLock lock) async {
    await _database
        .into(_database.dbAppSettings)
        .insertOnConflictUpdate(
          DbAppSettingsCompanion.insert(
            key: _key(scopeKey),
            value: jsonEncode({
              'version': 1,
              'reason': lock.reason.name,
              'locked_at_utc': lock.lockedAtUtc.toUtc().toIso8601String(),
            }),
          ),
        );
  }

  @override
  Future<void> clear(String scopeKey) async {
    await (_database.delete(
      _database.dbAppSettings,
    )..where((row) => row.key.equals(_key(scopeKey)))).go();
  }

  String _key(String scopeKey) {
    final normalized = scopeKey.trim();
    if (normalized.isEmpty || normalized.length > 128) {
      throw ArgumentError.value(scopeKey, 'scopeKey');
    }
    return '$_prefix$normalized';
  }
}
