import 'package:flutter_timezone/flutter_timezone.dart';

/// 读取设备当前使用的 IANA 时区标识。
///
/// 接触保存 UTC 时刻和此标识。统计层可以据此解释实际发生日期，不能用会随
/// 语言变化的缩写代替，例如 `CST`。
abstract interface class DeviceTimeZoneProvider {
  Future<String> currentIanaTimeZone();
}

final class FlutterDeviceTimeZoneProvider implements DeviceTimeZoneProvider {
  const FlutterDeviceTimeZoneProvider();

  @override
  Future<String> currentIanaTimeZone() async {
    final timeZone = await FlutterTimezone.getLocalTimezone();
    final identifier = timeZone.identifier.trim();
    if (identifier.isEmpty) {
      throw const DeviceTimeZoneException('device_time_zone_empty');
    }
    return identifier;
  }
}

final class DeviceTimeZoneException implements Exception {
  const DeviceTimeZoneException(this.code);

  final String code;

  @override
  String toString() => 'DeviceTimeZoneException($code)';
}
