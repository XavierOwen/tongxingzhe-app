// Public constructor arguments intentionally differ from private field names.
// ignore_for_file: prefer_initializing_formals

import '../foundation/runtime_values.dart';
import '../platform/platform_capabilities.dart';
import 'offline_pii_vault.dart';

/// 只有写入、精确读回和删除都成功，平台安全存储才可承载离线 PII。
final class SecureValueStoreCapabilityProbe
    implements SecureStorageCapabilityProbe {
  const SecureValueStoreCapabilityProbe({
    required SecureValueStore store,
    required IdGenerator idGenerator,
  }) : _store = store,
       _idGenerator = idGenerator;

  final SecureValueStore _store;
  final IdGenerator _idGenerator;

  @override
  Future<bool> probe() async {
    final nonce = _idGenerator.next();
    if (nonce.trim().isEmpty) return false;
    final key = 'tongxingzhe.secure-storage.probe.v1.$nonce';
    var valueRoundTripSucceeded = false;
    try {
      await _store.write(key, nonce);
      valueRoundTripSucceeded = await _store.read(key) == nonce;
    } on Object {
      valueRoundTripSucceeded = false;
    }
    try {
      await _store.delete(key);
    } on Object {
      // 探针残值不含身份或业务资料；删除失败仍使能力保持不可用。
      return false;
    }
    return valueRoundTripSucceeded;
  }
}
