import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as time_zone_data;
import 'package:timezone/timezone.dart' as time_zone;
import 'package:tongxingzhe_app/device/device_time_zone.dart';
import 'package:tongxingzhe_app/reminders/flutter_reminder_notification_scheduler.dart';
import 'package:tongxingzhe_app/reminders/reminder_delivery_probe_evidence.dart';
import 'package:tongxingzhe_app/reminders/personal_action_reminder.dart';

const _notificationId = 4817001;
const _commit = String.fromEnvironment(
  'REMINDER_PROBE_COMMIT',
  defaultValue: '',
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!RegExp(r'^[0-9a-f]{7,40}$').hasMatch(_commit)) {
    runApp(const _ProbeConfigurationErrorApp());
    return;
  }
  time_zone_data.initializeTimeZones();
  runApp(const ReminderDeliveryProbeApp());
}

final class _ProbeConfigurationErrorApp extends StatelessWidget {
  const _ProbeConfigurationErrorApp();

  @override
  Widget build(BuildContext context) => const MaterialApp(
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('缺少有效 commit。请确认工作树干净，再按文档传入 REMINDER_PROBE_COMMIT。'),
        ),
      ),
    ),
  );
}

final class ReminderDeliveryProbeApp extends StatelessWidget {
  const ReminderDeliveryProbeApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: ReminderDeliveryProbeScreen(),
  );
}

final class ReminderDeliveryProbeScreen extends StatefulWidget {
  const ReminderDeliveryProbeScreen({super.key, this.commit = _commit});

  final String commit;

  @override
  State<ReminderDeliveryProbeScreen> createState() =>
      _ReminderDeliveryProbeScreenState();
}

final class _ReminderDeliveryProbeScreenState
    extends State<ReminderDeliveryProbeScreen> {
  final _plugin = FlutterLocalNotificationsPlugin();
  final _timeZoneProvider = const FlutterDeviceTimeZoneProvider();
  final _comparisonTimeZoneController = TextEditingController();
  late final ReminderDeliveryProbeRecorder _recorder;
  var _ready = false;
  var _busy = false;
  var _status = '正在初始化通知插件。';

  @override
  void initState() {
    super.initState();
    _recorder = ReminderDeliveryProbeRecorder(
      platform: Platform.operatingSystem,
      osVersion: Platform.operatingSystemVersion,
      commit: widget.commit,
    );
    unawaited(_initialize());
  }

  @override
  void dispose() {
    _comparisonTimeZoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('提醒交付真机探针')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Text('此工具只安排通用测试通知。它不连接 Backend，也不读取项目、进度或对象资料。'),
          const SizedBox(height: 12),
          Text(_status, key: const ValueKey('probe-status')),
          const SizedBox(height: 16),
          TextField(
            controller: _comparisonTimeZoneController,
            enabled: _ready && !_busy,
            decoration: const InputDecoration(
              labelText: '旅行目标 IANA 时区',
              helperText: '选当前时区以西约一小时的地区，可缩短正确行为的等待时间。',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _ready && !_busy ? _schedule : null,
            child: const Text('安排约 3 分钟后的每日测试提醒'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _ready && !_busy ? _observeActive : null,
            child: const Text('检查通知中心中的活跃通知'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _ready && !_busy ? _cancel : null,
            child: const Text('取消测试提醒'),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: _copyEvidence, child: const Text('复制证据 JSON')),
          const Divider(height: 32),
          const Text('当前证据', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SelectableText(
            _recorder.toPrettyJson(),
            key: const ValueKey('probe-evidence'),
          ),
        ],
      ),
    ),
  );

  Future<void> _initialize() async {
    try {
      final initialized = await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_notification'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
          macOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: _recordInteraction,
      );
      // Darwin returns the permission result from initialize. This probe
      // deliberately defers that request until the user schedules a reminder.
      final deferredApplePermission = switch (defaultTargetPlatform) {
        TargetPlatform.iOS || TargetPlatform.macOS => initialized == false,
        _ => false,
      };
      if (initialized != true && !deferredApplePermission) {
        _setStatus('通知插件初始化失败。', ready: false);
        return;
      }
      final currentTimeZone = await _timeZoneProvider.currentIanaTimeZone();
      final recommendedTimeZone = _recommendedComparisonTimeZone(
        currentTimeZone,
      );
      _comparisonTimeZoneController.text = recommendedTimeZone;
      final launchDetails = await _plugin.getNotificationAppLaunchDetails();
      final response = launchDetails?.notificationResponse;
      if (launchDetails?.didNotificationLaunchApp == true &&
          response != null &&
          _isProbeResponse(response)) {
        await _recordInteraction(response, launchedApp: true);
      }
      _setStatus(
        recommendedTimeZone == currentTimeZone
            ? '探针已就绪。请先填写一个向西至少一小时的旅行目标时区。'
            : '探针已就绪。请确认旅行目标时区，再安排提醒。',
        ready: true,
      );
    } on Object catch (error) {
      _setStatus('初始化失败：$error', ready: false);
    }
  }

  Future<void> _schedule() async {
    _setBusy(true, '正在请求系统权限。');
    try {
      final granted = await _requestPermission();
      if (!granted) {
        _setStatus('系统没有授予通知权限。', ready: true);
        return;
      }
      final zoneName = await _timeZoneProvider.currentIanaTimeZone();
      final location = time_zone.getLocation(zoneName);
      final comparisonZoneName = _comparisonTimeZoneController.text.trim();
      if (comparisonZoneName == zoneName) {
        throw ArgumentError('旅行目标时区必须与当前时区不同');
      }
      final comparisonLocation = time_zone.getLocation(comparisonZoneName);
      final now = time_zone.TZDateTime.now(location);
      final seed = now.add(const Duration(minutes: 3));
      final scheduledDate = time_zone.TZDateTime(
        location,
        seed.year,
        seed.month,
        seed.day,
        seed.hour,
        seed.minute,
      );
      final expectedInComparisonZone = nextReminderOccurrence(
        nowUtc: now.toUtc(),
        localTime: LocalReminderTime.fromHourMinute(
          scheduledDate.hour,
          scheduledDate.minute,
        ),
        location: comparisonLocation,
      );
      final scheduledEvidence = ReminderProbeScheduledEvidence(
        recordedAtUtc: DateTime.now().toUtc(),
        deviceTimeZone: zoneName,
        scheduledForUtc: scheduledDate.toUtc(),
        scheduledLocalTime: _formatLocalTime(scheduledDate),
        notificationId: _notificationId,
        comparisonTimeZone: comparisonZoneName,
        expectedInComparisonZoneUtc: expectedInComparisonZone.toUtc(),
      );
      await _plugin.zonedSchedule(
        id: _notificationId,
        title: '同行者',
        body: '今天可以采取一个行动。',
        scheduledDate: scheduledDate,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'personal_action_reminders',
            '私人行动提醒',
            channelDescription: '只由本设备明确启用的私人行动提醒',
          ),
          iOS: DarwinNotificationDetails(),
          macOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: scheduledEvidence.toPayload(),
      );
      scheduledEvidence.recordTo(_recorder);
      _setStatus(
        '已安排 ${_formatLocalTime(scheduledDate)}。旧时区预定 UTC 为 ${scheduledDate.toUtc().toIso8601String()}；切换到 $comparisonZoneName 后，合同预期 UTC 为 ${expectedInComparisonZone.toUtc().toIso8601String()}。',
        ready: true,
      );
    } on Object catch (error) {
      _setStatus('安排失败：$error', ready: true);
    } finally {
      _setBusy(false);
    }
  }

  Future<bool> _requestPermission() async => switch (defaultTargetPlatform) {
    TargetPlatform.android =>
      await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          false,
    TargetPlatform.iOS =>
      await _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: false, sound: true) ??
          false,
    TargetPlatform.macOS =>
      await _plugin
              .resolvePlatformSpecificImplementation<
                MacOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: false, sound: true) ??
          false,
    _ => false,
  };

  Future<void> _observeActive() async {
    _setBusy(true, '正在查询通知中心。');
    try {
      final notifications = await _plugin.getActiveNotifications();
      if (!notifications.any((item) => item.id == _notificationId)) {
        _setStatus('没有找到探针通知。此结果不能单独证明通知从未呈现。', ready: true);
        return;
      }
      final zoneName = await _timeZoneProvider.currentIanaTimeZone();
      _recorder.recordObservedActive(
        recordedAtUtc: DateTime.now().toUtc(),
        deviceTimeZone: zoneName,
        notificationId: _notificationId,
      );
      _setStatus('已记录通知仍在通知中心，观察时区为 $zoneName。', ready: true);
    } on Object catch (error) {
      _setStatus('查询失败：$error', ready: true);
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _recordInteraction(
    NotificationResponse response, {
    bool launchedApp = false,
  }) async {
    if (!_isProbeResponse(response)) return;
    try {
      ReminderProbeScheduledEvidence.tryParsePayload(
        response.payload,
      )?.recordTo(_recorder);
      final zoneName = await _timeZoneProvider.currentIanaTimeZone();
      _recorder.recordInteracted(
        recordedAtUtc: DateTime.now().toUtc(),
        deviceTimeZone: zoneName,
        notificationId: response.id ?? _notificationId,
        launchedApp: launchedApp,
        responseType: response.notificationResponseType.name,
      );
      _setStatus('已记录用户交互。它不是系统首次呈现时间。', ready: true);
    } on Object catch (error) {
      _setStatus('记录交互失败：$error', ready: true);
    }
  }

  bool _isProbeResponse(NotificationResponse response) =>
      response.id == _notificationId ||
      ReminderProbeScheduledEvidence.tryParsePayload(
            response.payload,
          )?.notificationId ==
          _notificationId;

  Future<void> _cancel() async {
    _setBusy(true, '正在取消测试提醒。');
    try {
      await _plugin.cancel(id: _notificationId);
      _setStatus('测试提醒已取消。', ready: true);
    } on Object catch (error) {
      _setStatus('取消失败：$error', ready: true);
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _copyEvidence() async {
    await Clipboard.setData(ClipboardData(text: _recorder.toPrettyJson()));
    _setStatus('证据 JSON 已复制。', ready: _ready);
  }

  void _setBusy(bool value, [String? status]) {
    if (!mounted) return;
    setState(() {
      _busy = value;
      if (status != null) _status = status;
    });
  }

  void _setStatus(String status, {required bool ready}) {
    if (!mounted) return;
    setState(() {
      _ready = ready;
      _busy = false;
      _status = status;
    });
  }
}

String _formatLocalTime(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';

String _recommendedComparisonTimeZone(String current) => switch (current) {
  'America/New_York' => 'America/Chicago',
  'America/Chicago' => 'America/Denver',
  'America/Denver' => 'America/Los_Angeles',
  'America/Los_Angeles' => 'America/Anchorage',
  'Asia/Tokyo' => 'Asia/Shanghai',
  'Asia/Shanghai' => 'Asia/Bangkok',
  'Asia/Bangkok' => 'Asia/Karachi',
  'Australia/Sydney' => 'Australia/Perth',
  'Europe/London' => 'Atlantic/Azores',
  'Europe/Paris' || 'Europe/Berlin' => 'Europe/London',
  _ => current,
};
