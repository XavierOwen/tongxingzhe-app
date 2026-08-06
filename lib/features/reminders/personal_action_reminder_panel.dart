import 'dart:async';

import 'package:flutter/material.dart';

import '../../device/device_time_zone.dart';
import '../../foundation/runtime_values.dart';
import '../../l10n/app_strings.dart';
import '../../reminders/personal_action_reminder.dart';

/// “今日”页中的私人提醒卡片。
///
/// 同步提醒时间和逐设备系统通知开关在这里保持分离。只有权限与调度都成功，
/// 本机设置才会写成已启用。
final class PersonalActionReminderPanel extends StatefulWidget {
  const PersonalActionReminderPanel({
    super.key,
    required this.text,
    required this.scope,
    required this.gateway,
    required this.preferenceStore,
    required this.scheduler,
    required this.timeZoneProvider,
    required this.idGenerator,
  });

  final AppStrings text;
  final DeviceReminderScope scope;
  final PersonalActionReminderGateway gateway;
  final DeviceReminderPreferenceStore preferenceStore;
  final ReminderNotificationScheduler scheduler;
  final DeviceTimeZoneProvider timeZoneProvider;
  final IdGenerator idGenerator;

  @override
  State<PersonalActionReminderPanel> createState() =>
      _PersonalActionReminderPanelState();
}

final class _PersonalActionReminderPanelState
    extends State<PersonalActionReminderPanel>
    with WidgetsBindingObserver {
  PersonalActionReminder? _reminder;
  DeviceReminderPreference _preference =
      const DeviceReminderPreference.disabled();
  _ReminderPanelFailure? _failure;
  var _loading = true;
  var _saving = false;

  String get _scheduleKey => [
    widget.scope.deviceId,
    widget.scope.appUserId,
    widget.scope.workspaceId,
    widget.scope.projectId,
  ].join(':');

  ReminderNotificationContent get _genericContent =>
      ReminderNotificationContent(
        title: widget.text.t('appTitle'),
        body: widget.text.t('personalReminderGenericBody'),
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_loading && !_saving) {
      // Another device may have changed or cleared the synced reminder while
      // this app was in the background. Reload before reconciling this device.
      unawaited(_load());
    }
  }

  @override
  void didUpdateWidget(covariant PersonalActionReminderPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameScope(oldWidget.scope, widget.scope) ||
        oldWidget.gateway != widget.gateway ||
        oldWidget.preferenceStore != widget.preferenceStore ||
        oldWidget.scheduler != widget.scheduler) {
      _reminder = null;
      _preference = const DeviceReminderPreference.disabled();
      _failure = null;
      _loading = true;
      unawaited(_load());
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    final localTime = _reminder?.localTime;
    return Card(
      key: const ValueKey('personal-action-reminder-panel'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.notifications_active_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text.t('personalReminderTitle'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (!_loading)
                  TextButton(
                    key: const ValueKey('edit-personal-reminder'),
                    onPressed: _saving ? null : _pickTime,
                    child: Text(
                      text.t(
                        localTime == null
                            ? 'personalReminderSetTime'
                            : 'personalReminderEditTime',
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(text.t('personalReminderPrivateHelp')),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else ...[
              if (localTime == null)
                Text(text.t('personalReminderNotSet'))
              else ...[
                Text(
                  '${text.t('personalReminderAt')} '
                  '${_formatTime(context, localTime)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(text.t('personalReminderLocalTime')),
              ],
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                key: const ValueKey('device-reminder-opt-in'),
                contentPadding: EdgeInsets.zero,
                title: Text(text.t('personalReminderDeviceToggle')),
                subtitle: Text(text.t('personalReminderDeviceOff')),
                value: _preference.systemNotificationsEnabled,
                onChanged: _saving || localTime == null
                    ? null
                    : _setDeviceEnabled,
              ),
              Text(text.t('personalReminderGenericPrivacy')),
              if (localTime != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const ValueKey('clear-personal-reminder'),
                    onPressed: _saving ? null : _clearTime,
                    child: Text(text.t('personalReminderClearTime')),
                  ),
                ),
              if (_failure case final failure?) ...[
                const SizedBox(height: 8),
                Text(
                  text.t(_failureKey(failure)),
                  key: const ValueKey('personal-reminder-failure'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                TextButton(
                  onPressed: _saving ? null : _load,
                  child: Text(text.t('retry')),
                ),
              ],
            ],
            if (_saving) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _failure = null;
      });
    }
    try {
      final preference = await widget.preferenceStore.load(widget.scope);
      final result = await widget.gateway.load();
      if (!mounted) return;
      switch (result) {
        case PersonalActionReminderSuccess<PersonalActionReminder?>(
          :final value,
        ):
          setState(() {
            _reminder = value;
            _preference = preference;
            _loading = false;
          });
          if (preference.systemNotificationsEnabled) {
            if (value?.localTime == null) {
              await _cancelScheduled(showFailure: true);
            } else {
              await _reconcile(showFailure: true);
            }
          }
        case PersonalActionReminderRejected<PersonalActionReminder?>():
          setState(() {
            _preference = preference;
            _loading = false;
            _failure = _ReminderPanelFailure.remoteUnavailable;
          });
          if (preference.systemNotificationsEnabled) {
            await _cancelScheduled(showFailure: false);
          }
      }
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failure = _ReminderPanelFailure.remoteUnavailable;
      });
      await _cancelScheduled(showFailure: false);
    }
  }

  Future<void> _pickTime() async {
    final current = _reminder?.localTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: current?.hour ?? 19,
        minute: current?.minute ?? 0,
      ),
      helpText: widget.text.t('personalReminderSetTime'),
    );
    if (picked == null || !mounted) return;
    await _saveTime(
      LocalReminderTime.fromHourMinute(picked.hour, picked.minute),
    );
  }

  Future<void> _clearTime() => _saveTime(null);

  Future<void> _saveTime(LocalReminderTime? localTime) async {
    setState(() {
      _saving = true;
      _failure = null;
    });
    final result = await widget.gateway.save(
      expectedRevision: _reminder?.revision ?? 0,
      localTime: localTime,
      mutationId: widget.idGenerator.next(),
    );
    if (!mounted) return;
    switch (result) {
      case PersonalActionReminderSuccess<PersonalActionReminderMutation>(
        :final value,
      ):
        setState(() {
          _reminder = value.reminder;
          _saving = false;
        });
        if (_preference.systemNotificationsEnabled) {
          if (localTime == null) {
            final cancelled = await widget.scheduler.cancel(
              scheduleKey: _scheduleKey,
            );
            if (cancelled is ReminderScheduleRejected && mounted) {
              setState(
                () => _failure = _ReminderPanelFailure.scheduleUnavailable,
              );
            }
          } else {
            await _reconcile(showFailure: true);
          }
        }
      case PersonalActionReminderRejected<PersonalActionReminderMutation>(
        :final code,
      ):
        setState(() {
          _saving = false;
          _failure = code == PersonalActionReminderFailureCode.conflict
              ? _ReminderPanelFailure.conflict
              : _ReminderPanelFailure.remoteUnavailable;
        });
    }
  }

  Future<void> _setDeviceEnabled(bool enabled) async {
    final localTime = _reminder?.localTime;
    if (localTime == null) return;
    setState(() {
      _saving = true;
      _failure = null;
    });
    if (!enabled) {
      final result = await widget.scheduler.cancel(scheduleKey: _scheduleKey);
      if (result is ReminderScheduleRejected) {
        if (mounted) {
          setState(() {
            _saving = false;
            _failure = _failureFor(result.failure);
          });
        }
        return;
      }
      try {
        const preference = DeviceReminderPreference.disabled();
        await widget.preferenceStore.save(widget.scope, preference);
        if (mounted) {
          setState(() {
            _preference = preference;
            _saving = false;
          });
        }
      } on Object {
        if (mounted) {
          setState(() {
            _saving = false;
            _failure = _ReminderPanelFailure.scheduleUnavailable;
          });
        }
      }
      return;
    }

    final result = await _schedule(localTime, requestPermission: true);
    if (result is ReminderScheduleRejected) {
      if (mounted) {
        setState(() {
          _saving = false;
          _failure = _failureFor(result.failure);
        });
      }
      return;
    }
    try {
      const preference = DeviceReminderPreference(
        systemNotificationsEnabled: true,
      );
      await widget.preferenceStore.save(widget.scope, preference);
      if (!mounted) return;
      setState(() {
        _preference = preference;
        _saving = false;
      });
    } on Object {
      await widget.scheduler.cancel(scheduleKey: _scheduleKey);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _failure = _ReminderPanelFailure.scheduleUnavailable;
      });
    }
  }

  Future<void> _reconcile({required bool showFailure}) async {
    final localTime = _reminder?.localTime;
    if (localTime == null || !_preference.systemNotificationsEnabled) return;
    final result = await _schedule(localTime, requestPermission: false);
    if (result is ReminderScheduleRejected && mounted && showFailure) {
      setState(() => _failure = _failureFor(result.failure));
    }
  }

  Future<ReminderScheduleResult> _schedule(
    LocalReminderTime localTime, {
    required bool requestPermission,
  }) async {
    try {
      final deviceTimeZone = await widget.timeZoneProvider
          .currentIanaTimeZone();
      if (!requestPermission) {
        final cancelled = await widget.scheduler.cancel(
          scheduleKey: _scheduleKey,
        );
        if (cancelled is ReminderScheduleRejected) return cancelled;
      }
      return requestPermission
          ? widget.scheduler.requestPermissionAndSchedule(
              scheduleKey: _scheduleKey,
              localTime: localTime,
              deviceTimeZone: deviceTimeZone,
              content: _genericContent,
            )
          : widget.scheduler.schedule(
              scheduleKey: _scheduleKey,
              localTime: localTime,
              deviceTimeZone: deviceTimeZone,
              content: _genericContent,
            );
    } on Object {
      return const ReminderScheduleRejected(
        ReminderScheduleFailure.temporarilyUnavailable,
      );
    }
  }

  Future<void> _cancelScheduled({required bool showFailure}) async {
    final result = await widget.scheduler.cancel(scheduleKey: _scheduleKey);
    if (result is ReminderScheduleRejected && mounted && showFailure) {
      setState(() => _failure = _failureFor(result.failure));
    }
  }

  _ReminderPanelFailure _failureFor(ReminderScheduleFailure failure) =>
      switch (failure) {
        ReminderScheduleFailure.unsupported =>
          _ReminderPanelFailure.unsupported,
        ReminderScheduleFailure.permissionDenied =>
          _ReminderPanelFailure.permissionDenied,
        ReminderScheduleFailure.temporarilyUnavailable =>
          _ReminderPanelFailure.scheduleUnavailable,
      };

  String _formatTime(BuildContext context, LocalReminderTime value) =>
      MaterialLocalizations.of(
        context,
      ).formatTimeOfDay(TimeOfDay(hour: value.hour, minute: value.minute));
}

enum _ReminderPanelFailure {
  remoteUnavailable,
  conflict,
  unsupported,
  permissionDenied,
  scheduleUnavailable,
}

String _failureKey(_ReminderPanelFailure failure) => switch (failure) {
  _ReminderPanelFailure.remoteUnavailable => 'personalReminderUnavailable',
  _ReminderPanelFailure.conflict => 'personalReminderConflict',
  _ReminderPanelFailure.unsupported => 'personalReminderUnsupported',
  _ReminderPanelFailure.permissionDenied => 'personalReminderPermissionDenied',
  _ReminderPanelFailure.scheduleUnavailable => 'personalReminderScheduleFailed',
};

bool _sameScope(DeviceReminderScope left, DeviceReminderScope right) =>
    left.appUserId == right.appUserId &&
    left.workspaceId == right.workspaceId &&
    left.projectId == right.projectId &&
    left.deviceId == right.deviceId;
