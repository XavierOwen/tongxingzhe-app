import 'package:tongxingzhe_app/platform/platform_capabilities.dart';

final class FakePlatformCapabilitiesProvider
    implements PlatformCapabilitiesProvider {
  const FakePlatformCapabilitiesProvider({this.failure});

  final Object? failure;

  @override
  Future<PlatformCapabilities> load() async {
    final error = failure;
    if (error != null) {
      throw error;
    }
    return fullyAvailableTestCapabilities;
  }
}

const fullyAvailableTestCapabilities = PlatformCapabilities(
  platform: AppPlatform.unknown,
  values: {
    PlatformCapability.durableLocalDatabase: CapabilityAvailability.available,
    PlatformCapability.secureSessionStorage: CapabilityAvailability.available,
    PlatformCapability.location: CapabilityAvailability.available,
    PlatformCapability.systemNotifications: CapabilityAvailability.available,
    PlatformCapability.backgroundSync: CapabilityAvailability.available,
    PlatformCapability.fileSystem: CapabilityAvailability.available,
  },
);
