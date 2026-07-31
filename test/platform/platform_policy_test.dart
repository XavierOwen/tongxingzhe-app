import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/platform/platform_capabilities.dart';

void main() {
  test('未通过 runtime probe 时不缓存敏感对象且只前台同步', () {
    const capabilities = PlatformCapabilities(
      platform: AppPlatform.linux,
      values: {
        PlatformCapability.durableLocalDatabase:
            CapabilityAvailability.available,
        PlatformCapability.secureSessionStorage:
            CapabilityAvailability.runtimeProbeRequired,
        PlatformCapability.backgroundSync: CapabilityAvailability.unavailable,
      },
    );

    final policy = PlatformPolicy.from(capabilities);

    expect(policy.canPersistAnonymousDrafts, isTrue);
    expect(policy.canPersistSensitiveTargets, isFalse);
    expect(policy.syncOnlyWhileForeground, isTrue);
    expect(policy.canScheduleSystemNotifications, isFalse);
  });
}
