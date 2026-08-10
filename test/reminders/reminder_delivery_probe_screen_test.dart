import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/reminder_delivery_probe.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const notificationChannel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  const timeZoneChannel = MethodChannel('flutter_timezone');

  setUp(() {
    MacOSFlutterLocalNotificationsPlugin.registerWith();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationChannel, (call) async {
          return switch (call.method) {
            'initialize' => false,
            'getNotificationAppLaunchDetails' => <String, Object?>{
              'notificationLaunchedApp': false,
            },
            _ => throw PlatformException(
              code: 'unexpected_notification_call',
              message: call.method,
            ),
          };
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(timeZoneChannel, (call) async {
          if (call.method == 'getLocalTimezone') {
            return 'America/Chicago';
          }
          throw PlatformException(
            code: 'unexpected_time_zone_call',
            message: call.method,
          );
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(timeZoneChannel, null);
  });

  testWidgets('Apple 初始化延后权限请求时探针仍进入就绪状态', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await tester.pumpWidget(
        const MaterialApp(home: ReminderDeliveryProbeScreen(commit: 'eb8a09f')),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('探针已就绪'), findsOneWidget);
      final scheduleButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '安排约 3 分钟后的每日测试提醒'),
      );
      expect(scheduleButton.onPressed, isNotNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
