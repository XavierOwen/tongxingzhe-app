import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'offline_pii_vault.dart';

/// 平台安全存储的窄 Adapter。业务层看不到 plugin 类型或平台分支。
final class FlutterSecureValueStore implements SecureValueStore {
  FlutterSecureValueStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
