import 'package:flutter/foundation.dart';

enum AppPlatform { android, ios, web, macos, windows, linux, unknown }

/// 当前设备这一次运行所观察到的能力状态，不表示项目已取得该平台的发布证据。
///
/// Adapter 必须通过真实调用或权限探针，才能把 runtimeProbeRequired 升级为
/// available。拒绝和暂时失败分开保存，方便 UI 给出不同的恢复动作。
enum CapabilityAvailability {
  available,
  runtimeProbeRequired,
  denied,
  temporarilyUnavailable,
  unavailable,
}

enum PlatformCapability {
  durableLocalDatabase,
  secureSessionStorage,
  location,
  systemNotifications,
  backgroundSync,
  fileSystem,
}

final class PlatformCapabilities {
  const PlatformCapabilities({required this.platform, required this.values});

  final AppPlatform platform;
  final Map<PlatformCapability, CapabilityAvailability> values;

  CapabilityAvailability availabilityOf(PlatformCapability capability) {
    return values[capability] ?? CapabilityAvailability.unavailable;
  }
}

/// 产品在当前能力下采用的降级规则，而不是在 Widget 内散落平台判断。
final class PlatformPolicy {
  const PlatformPolicy._({
    required this.canPersistAnonymousDrafts,
    required this.canPersistSensitiveTargets,
    required this.syncOnlyWhileForeground,
    required this.canScheduleSystemNotifications,
  });

  factory PlatformPolicy.from(PlatformCapabilities capabilities) {
    final durable = capabilities.availabilityOf(
      PlatformCapability.durableLocalDatabase,
    );
    final secure = capabilities.availabilityOf(
      PlatformCapability.secureSessionStorage,
    );
    final background = capabilities.availabilityOf(
      PlatformCapability.backgroundSync,
    );
    final notifications = capabilities.availabilityOf(
      PlatformCapability.systemNotifications,
    );

    return PlatformPolicy._(
      canPersistAnonymousDrafts: durable == CapabilityAvailability.available,
      canPersistSensitiveTargets:
          durable == CapabilityAvailability.available &&
          secure == CapabilityAvailability.available,
      syncOnlyWhileForeground: background != CapabilityAvailability.available,
      canScheduleSystemNotifications:
          notifications == CapabilityAvailability.available,
    );
  }

  final bool canPersistAnonymousDrafts;
  final bool canPersistSensitiveTargets;
  final bool syncOnlyWhileForeground;
  final bool canScheduleSystemNotifications;
}

abstract interface class PlatformCapabilitiesProvider {
  Future<PlatformCapabilities> load();
}

/// 这是当前 App 已接线能力的保守起点。它不代表某个平台已通过发布验收；
/// runtimeProbeRequired 必须由后续 Adapter 在当前设备实测后才能升级。
final class FlutterPlatformCapabilitiesProvider
    implements PlatformCapabilitiesProvider {
  const FlutterPlatformCapabilitiesProvider();

  @override
  Future<PlatformCapabilities> load() async {
    final platform = _currentPlatform();
    final native =
        platform != AppPlatform.web && platform != AppPlatform.unknown;
    final mobile =
        platform == AppPlatform.android || platform == AppPlatform.ios;
    final locationImplemented =
        platform != AppPlatform.linux && platform != AppPlatform.unknown;

    return PlatformCapabilities(
      platform: platform,
      values: {
        PlatformCapability.durableLocalDatabase: platform == AppPlatform.web
            ? CapabilityAvailability.runtimeProbeRequired
            : native
            ? CapabilityAvailability.available
            : CapabilityAvailability.unavailable,
        PlatformCapability.secureSessionStorage:
            native || platform == AppPlatform.web
            ? CapabilityAvailability.runtimeProbeRequired
            : CapabilityAvailability.unavailable,
        PlatformCapability.location: locationImplemented
            ? CapabilityAvailability.runtimeProbeRequired
            : CapabilityAvailability.unavailable,
        // Slice 0 尚未接通知 Adapter，所以不能把 OS 理论能力写成可用。
        PlatformCapability.systemNotifications:
            CapabilityAvailability.unavailable,
        PlatformCapability.backgroundSync: mobile
            ? CapabilityAvailability.runtimeProbeRequired
            : CapabilityAvailability.unavailable,
        PlatformCapability.fileSystem: native
            ? CapabilityAvailability.available
            : CapabilityAvailability.unavailable,
      },
    );
  }

  AppPlatform _currentPlatform() {
    if (kIsWeb) {
      return AppPlatform.web;
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => AppPlatform.android,
      TargetPlatform.iOS => AppPlatform.ios,
      TargetPlatform.macOS => AppPlatform.macos,
      TargetPlatform.windows => AppPlatform.windows,
      TargetPlatform.linux => AppPlatform.linux,
      TargetPlatform.fuchsia => AppPlatform.unknown,
    };
  }
}
