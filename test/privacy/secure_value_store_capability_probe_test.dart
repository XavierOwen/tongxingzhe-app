import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/foundation/runtime_values.dart';
import 'package:tongxingzhe_app/privacy/offline_pii_vault.dart';
import 'package:tongxingzhe_app/privacy/secure_value_store_capability_probe.dart';

void main() {
  test('安全存储必须完成写入、读回和删除才可启用 PII 缓存', () async {
    final store = _MemorySecureValueStore()..failDelete = true;
    final probe = SecureValueStoreCapabilityProbe(
      store: store,
      idGenerator: _FixedIdGenerator(),
    );

    expect(await probe.probe(), isFalse);

    store.failDelete = false;
    store.values.clear();
    expect(await probe.probe(), isTrue);

    store.returnWrongValue = true;
    expect(await probe.probe(), isFalse);
    expect(store.values, isEmpty);

    store.returnWrongValue = false;
    store.failWrite = true;
    expect(await probe.probe(), isFalse);
  });
}

final class _FixedIdGenerator implements IdGenerator {
  var nextValue = 0;

  @override
  String next() => 'probe-${nextValue++}';
}

final class _MemorySecureValueStore implements SecureValueStore {
  final values = <String, String>{};
  var failDelete = false;
  var failWrite = false;
  var returnWrongValue = false;

  @override
  Future<void> delete(String key) async {
    if (failDelete) throw StateError('synthetic delete failure');
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async =>
      returnWrongValue ? 'synthetic-wrong-value' : values[key];

  @override
  Future<void> write(String key, String value) async {
    if (failWrite) throw StateError('synthetic write failure');
    values[key] = value;
  }
}
