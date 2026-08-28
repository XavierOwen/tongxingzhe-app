import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/platform/platform_capabilities.dart';

void main() {
  test('静态平台识别不会把安全存储直接标为可用', () async {
    const provider = FlutterPlatformCapabilitiesProvider();

    final capabilities = await provider.load();

    expect(
      capabilities.availabilityOf(PlatformCapability.secureSessionStorage),
      isNot(CapabilityAvailability.available),
    );
  });

  test('真实安全存储读写删除探针成功后才标为可用', () async {
    final provider = FlutterPlatformCapabilitiesProvider(
      secureStorageProbe: _SecureProbe(true),
    );

    final capabilities = await provider.load();

    expect(
      capabilities.availabilityOf(PlatformCapability.secureSessionStorage),
      CapabilityAvailability.available,
    );
  });

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

  test('Web 持久化探针未通过时不保存草稿或敏感对象', () {
    const capabilities = PlatformCapabilities(
      platform: AppPlatform.web,
      values: {
        PlatformCapability.durableLocalDatabase:
            CapabilityAvailability.runtimeProbeRequired,
        PlatformCapability.secureSessionStorage:
            CapabilityAvailability.available,
        PlatformCapability.backgroundSync: CapabilityAvailability.unavailable,
        PlatformCapability.systemNotifications:
            CapabilityAvailability.unavailable,
      },
    );

    final policy = PlatformPolicy.from(capabilities);

    expect(policy.canPersistAnonymousDrafts, isFalse);
    expect(policy.canPersistSensitiveTargets, isFalse);
    expect(policy.syncOnlyWhileForeground, isTrue);
    expect(policy.canScheduleSystemNotifications, isFalse);
  });

  test('权限被拒绝时不缓存敏感对象且不安排系统通知', () {
    const capabilities = PlatformCapabilities(
      platform: AppPlatform.ios,
      values: {
        PlatformCapability.durableLocalDatabase:
            CapabilityAvailability.available,
        PlatformCapability.secureSessionStorage: CapabilityAvailability.denied,
        PlatformCapability.backgroundSync: CapabilityAvailability.available,
        PlatformCapability.systemNotifications: CapabilityAvailability.denied,
      },
    );

    final policy = PlatformPolicy.from(capabilities);

    expect(policy.canPersistAnonymousDrafts, isTrue);
    expect(policy.canPersistSensitiveTargets, isFalse);
    expect(policy.syncOnlyWhileForeground, isFalse);
    expect(policy.canScheduleSystemNotifications, isFalse);
  });

  test('安全存储暂时失败时不缓存敏感对象且同步降级到前台', () {
    const capabilities = PlatformCapabilities(
      platform: AppPlatform.windows,
      values: {
        PlatformCapability.durableLocalDatabase:
            CapabilityAvailability.available,
        PlatformCapability.secureSessionStorage:
            CapabilityAvailability.temporarilyUnavailable,
        PlatformCapability.backgroundSync:
            CapabilityAvailability.temporarilyUnavailable,
      },
    );

    final policy = PlatformPolicy.from(capabilities);

    expect(policy.canPersistAnonymousDrafts, isTrue);
    expect(policy.canPersistSensitiveTargets, isFalse);
    expect(policy.syncOnlyWhileForeground, isTrue);
    expect(policy.canScheduleSystemNotifications, isFalse);
  });

  test('当前设备探针全部通过时启用相应策略', () {
    const capabilities = PlatformCapabilities(
      platform: AppPlatform.android,
      values: {
        PlatformCapability.durableLocalDatabase:
            CapabilityAvailability.available,
        PlatformCapability.secureSessionStorage:
            CapabilityAvailability.available,
        PlatformCapability.backgroundSync: CapabilityAvailability.available,
        PlatformCapability.systemNotifications:
            CapabilityAvailability.available,
      },
    );

    final policy = PlatformPolicy.from(capabilities);

    expect(policy.canPersistAnonymousDrafts, isTrue);
    expect(policy.canPersistSensitiveTargets, isTrue);
    expect(policy.syncOnlyWhileForeground, isFalse);
    expect(policy.canScheduleSystemNotifications, isTrue);
  });
}

final class _SecureProbe implements SecureStorageCapabilityProbe {
  const _SecureProbe(this.result);

  final bool result;

  @override
  Future<bool> probe() async => result;
}
