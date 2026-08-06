import '../data/local_database.dart';
import '../foundation/runtime_values.dart';

/// 为当前 App 安装提供可跨重启复用的不透明设备 ID。
///
/// ID 不是认证凭据。Outbox 用它区分命令来源和租约执行者，因此同一次安装
/// 不能在每次启动时换一个新值。
final class DeviceIdentityStore {
  const DeviceIdentityStore(this._database, this._idGenerator);

  static const _settingKey = 'modern.device_id.v1';

  final LocalDatabase _database;
  final IdGenerator _idGenerator;

  Future<String> loadOrCreate() {
    return _database.transaction(() async {
      final query = _database.select(_database.dbAppSettings)
        ..where((row) => row.key.equals(_settingKey));
      final existing = await query.getSingleOrNull();
      if (existing != null && existing.value.trim().isNotEmpty) {
        return existing.value;
      }

      final created = _idGenerator.next();
      if (created.trim().isEmpty) {
        throw StateError('device_identity_generator_returned_empty_id');
      }
      await _database
          .into(_database.dbAppSettings)
          .insertOnConflictUpdate(
            DbAppSettingsCompanion.insert(key: _settingKey, value: created),
          );
      return created;
    });
  }
}
