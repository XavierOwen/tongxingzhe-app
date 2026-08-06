import 'package:geolocator/geolocator.dart';

class LocationSnapshot {
  const LocationSnapshot({
    this.latitude,
    this.longitude,
    this.accuracyMeters,
    this.error,
  });

  final double? latitude;
  final double? longitude;
  final double? accuracyMeters;
  final String? error;

  bool get hasPosition => latitude != null && longitude != null;
}

/// 表单依赖的位置端口。测试可提供确定性坐标，不触发系统权限弹窗。
abstract interface class ContactLocationCapture {
  Future<LocationSnapshot> captureCurrentPosition();
}

/// 通过 Geolocator 请求正式设备的当前位置。
final class LocationService implements ContactLocationCapture {
  const LocationService();

  @override
  Future<LocationSnapshot> captureCurrentPosition() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return const LocationSnapshot(error: 'location_service_disabled');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        return const LocationSnapshot(error: 'location_permission_denied');
      }
      if (permission == LocationPermission.deniedForever) {
        return const LocationSnapshot(
          error: 'location_permission_denied_forever',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );

      return LocationSnapshot(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
      );
    } catch (_) {
      return const LocationSnapshot(error: 'location_unavailable');
    }
  }
}
