import 'dart:convert';
import 'dart:math';

/// 提供业务代码可观察的当前时间。
///
/// 正式环境使用 [SystemClock]；测试实现可以固定在时区或周期边界，避免
/// `DateTime.now()` 让同一个用例在不同时间得到不同结果。
abstract interface class AppClock {
  DateTime now();
}

final class SystemClock implements AppClock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}

String secureUuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((value) => value.toRadixString(16).padLeft(2, '0'));
  final text = hex.join();
  return '${text.substring(0, 8)}-${text.substring(8, 12)}-'
      '${text.substring(12, 16)}-${text.substring(16, 20)}-'
      '${text.substring(20)}';
}

/// 生成不携带业务含义的稳定标识。
///
/// 调用者只依赖“每次调用得到新的不透明字符串”，不依赖时间戳格式。
abstract interface class IdGenerator {
  String next();
}

final class SecureIdGenerator implements IdGenerator {
  SecureIdGenerator() : _random = Random.secure();

  final Random _random;

  @override
  String next() {
    final bytes = List<int>.generate(18, (_) => _random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
