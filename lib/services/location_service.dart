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

class LocationService {
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
