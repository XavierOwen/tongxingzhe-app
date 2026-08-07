import 'dart:async';

import 'package:flutter/material.dart';

import '../../device/device_time_zone.dart';
import '../../foundation/runtime_values.dart';
import '../../l10n/app_strings.dart';
import '../../plans/personal_action_plan.dart';
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
    required this.planGateway,
    required this.projectName,
    required this.preferenceStore,
    required this.scheduler,
    required this.timeZoneProvider,
    required this.idGenerator,
  });

  final AppStrings text;
  final DeviceReminderScope scope;
  final PersonalActionReminderGateway gateway;
  final PersonalActionPlanGateway planGateway;
  final String projectName;
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
  final FocusNode _timeActionFocusNode = FocusNode(
    debugLabel: 'personal reminder time action',
  );
  final FocusNode _detailToggleFocusNode = FocusNode(
    debugLabel: 'personal reminder details',
  );
  PersonalActionReminder? _reminder;
  DeviceReminderPreference _preference =
      const DeviceReminderPreference.disabled();
  _ReminderPanelFailure? _failure;
  DateTime? _cachedAtUtc;
  var _fromOfflineCache = false;
  var _loading = true;
  var _saving = false;

  String get _scheduleKey => personalActionReminderScheduleKey(widget.scope);

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
    _timeActionFocusNode.dispose();
    _detailToggleFocusNode.dispose();
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
        oldWidget.planGateway != widget.planGateway ||
        oldWidget.projectName != widget.projectName ||
        oldWidget.preferenceStore != widget.preferenceStore ||
        oldWidget.scheduler != widget.scheduler) {
      _reminder = null;
      _preference = const DeviceReminderPreference.disabled();
      _failure = null;
      _cachedAtUtc = null;
      _fromOfflineCache = false;
      _loading = true;
      unawaited(_load());
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    final localTime = _reminder?.localTime;
    final timeAction = text.t(
      localTime == null
          ? 'personalReminderSetTime'
          : 'personalReminderEditTime',
    );
    final timeActionSemantics = localTime == null
        ? timeAction
        : text
              .t('personalReminderTimeActionSemantics')
              .replaceAll('{action}', timeAction)
              .replaceAll('{time}', _formatTime(context, localTime));
    return Card(
      key: const ValueKey('personal-action-reminder-panel'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ReminderPanelHeader(
              text: text,
              showAction: !_loading,
              actionLabel: timeAction,
              actionSemanticsLabel: timeActionSemantics,
              actionFocusNode: _timeActionFocusNode,
              onEdit: _saving || _fromOfflineCache ? null : _pickTime,
            ),
            const SizedBox(height: 4),
            Text(text.t('personalReminderPrivateHelp')),
            if (_fromOfflineCache) ...[
              const SizedBox(height: 8),
              Semantics(
                container: true,
                label: _offlineCacheText(text, _cachedAtUtc!),
                excludeSemantics: true,
                child: Text(
                  _offlineCacheText(text, _cachedAtUtc!),
                  key: const ValueKey('personal-reminder-offline-cache'),
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (_loading)
              Center(
                child: CircularProgressIndicator(
                  semanticsLabel: text.t('personalReminderLoading'),
                ),
              )
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
              if (_preference.systemNotificationsEnabled)
                SwitchListTile.adaptive(
                  key: const ValueKey('device-reminder-details'),
                  focusNode: _detailToggleFocusNode,
                  contentPadding: EdgeInsets.zero,
                  title: Text(text.t('personalReminderDetailToggle')),
                  subtitle: Text(text.t('personalReminderDetailToggleHelp')),
                  value:
                      _preference.contentMode ==
                      ReminderNotificationContentMode.projectAndProgress,
                  onChanged: _saving || localTime == null
                      ? null
                      : _setDetailedContent,
                ),
              Text(
                text.t(
                  _preference.contentMode ==
                          ReminderNotificationContentMode.projectAndProgress
                      ? 'personalReminderDetailPrivacy'
                      : 'personalReminderGenericPrivacy',
                ),
              ),
              if (localTime != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const ValueKey('clear-personal-reminder'),
                    onPressed: _saving || _fromOfflineCache ? null : _clearTime,
                    child: Text(text.t('personalReminderClearTime')),
                  ),
                ),
              if (_failure case final failure?) ...[
                const SizedBox(height: 8),
                Semantics(
                  container: true,
                  liveRegion: true,
                  child: Text(
                    text.t(_failureKey(failure)),
                    key: const ValueKey('personal-reminder-failure'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _saving ? null : _load,
                  child: Text(text.t('retry')),
                ),
              ],
            ],
            if (_saving) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                semanticsLabel: text.t('personalReminderSaving'),
              ),
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
          :final fromOfflineCache,
          :final cachedAtUtc,
        ):
          setState(() {
            _reminder = value;
            _preference = preference;
            _fromOfflineCache = fromOfflineCache;
            _cachedAtUtc = cachedAtUtc;
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
            _fromOfflineCache = false;
            _cachedAtUtc = null;
            _loading = false;
            _failure = _ReminderPanelFailure.remoteUnavailable;
          });
      }
    } on Object {
      if (!mounted) return;
      setState(() {
        _fromOfflineCache = false;
        _cachedAtUtc = null;
        _loading = false;
        _failure = _ReminderPanelFailure.remoteUnavailable;
      });
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
    if (mounted) {
      _timeActionFocusNode.requestFocus();
    }
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
          _fromOfflineCache = false;
          _cachedAtUtc = null;
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

    final result = await _schedule(
      localTime,
      requestPermission: true,
      content: _genericContent,
    );
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

  Future<void> _setDetailedContent(bool enabled) async {
    final localTime = _reminder?.localTime;
    if (localTime == null || !_preference.systemNotificationsEnabled) return;
    final operationScheduleKey = _scheduleKey;
    final operationProjectName = widget.projectName;
    final previous = _preference;
    final candidate = DeviceReminderPreference(
      systemNotificationsEnabled: true,
      contentMode: enabled
          ? ReminderNotificationContentMode.projectAndProgress
          : ReminderNotificationContentMode.generic,
    );
    setState(() {
      _saving = true;
      _failure = null;
    });

    if (!enabled) {
      final cancelled = await widget.scheduler.cancel(
        scheduleKey: _scheduleKey,
      );
      try {
        await widget.preferenceStore.save(widget.scope, candidate);
      } on Object {
        if (!mounted) return;
        setState(() {
          _saving = false;
          _failure = _ReminderPanelFailure.scheduleUnavailable;
        });
        return;
      }
      if (!mounted) return;
      setState(() => _preference = candidate);
      if (cancelled is ReminderScheduleRejected) {
        setState(() {
          _saving = false;
          _failure = _failureFor(cancelled.failure);
        });
        return;
      }
      final scheduled = await _schedule(
        localTime,
        requestPermission: false,
        content: _genericContent,
        cancelExisting: false,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        if (scheduled is ReminderScheduleRejected) {
          _failure = _failureFor(scheduled.failure);
        }
      });
      return;
    }

    final content = await _contentFor(candidate);
    if (content == null) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _failure = _ReminderPanelFailure.detailUnavailable;
      });
      return;
    }
    if (!mounted ||
        operationScheduleKey != _scheduleKey ||
        operationProjectName != widget.projectName) {
      return;
    }
    setState(() => _saving = false);
    final confirmed = await showDialog<bool>(
      context: context,
      traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
      builder: (context) => FocusTraversalGroup(
        policy: WidgetOrderTraversalPolicy(),
        child: AlertDialog(
          semanticLabel: widget.text.t('personalReminderDetailConfirmTitle'),
          title: Text(widget.text.t('personalReminderDetailConfirmTitle')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.text.t('personalReminderDetailConfirmHelp')),
                const SizedBox(height: 12),
                Text(
                  content.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(content.body),
              ],
            ),
          ),
          actions: [
            TextButton(
              key: const ValueKey('cancel-device-reminder-details'),
              autofocus: true,
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(widget.text.t('cancel')),
            ),
            FilledButton(
              key: const ValueKey('confirm-device-reminder-details'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(widget.text.t('confirm')),
            ),
          ],
        ),
      ),
    );
    if (mounted &&
        operationScheduleKey == _scheduleKey &&
        operationProjectName == widget.projectName) {
      _detailToggleFocusNode.requestFocus();
    }
    if (confirmed != true ||
        !mounted ||
        operationScheduleKey != _scheduleKey ||
        operationProjectName != widget.projectName) {
      return;
    }
    setState(() => _saving = true);
    final scheduled = await _schedule(
      localTime,
      requestPermission: false,
      content: content,
    );
    if (scheduled is ReminderScheduleRejected) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _failure = _failureFor(scheduled.failure);
      });
      return;
    }
    try {
      await widget.preferenceStore.save(widget.scope, candidate);
      if (!mounted) return;
      setState(() {
        _preference = candidate;
        _saving = false;
      });
    } on Object {
      await _schedule(
        localTime,
        requestPermission: false,
        content: _genericContent,
      );
      if (!mounted) return;
      setState(() {
        _preference = previous;
        _saving = false;
        _failure = _ReminderPanelFailure.scheduleUnavailable;
      });
    }
  }

  Future<void> _reconcile({required bool showFailure}) async {
    final localTime = _reminder?.localTime;
    if (localTime == null || !_preference.systemNotificationsEnabled) return;
    final content = await _contentFor(_preference);
    if (content == null) {
      await _cancelScheduled(showFailure: false);
      if (mounted && showFailure) {
        setState(() => _failure = _ReminderPanelFailure.detailUnavailable);
      }
      return;
    }
    final result = await _schedule(
      localTime,
      requestPermission: false,
      content: content,
    );
    if (result is ReminderScheduleRejected && mounted && showFailure) {
      setState(() => _failure = _failureFor(result.failure));
    }
  }

  Future<ReminderScheduleResult> _schedule(
    LocalReminderTime localTime, {
    required bool requestPermission,
    required ReminderNotificationContent content,
    bool cancelExisting = true,
  }) async {
    try {
      final scheduleKey = _scheduleKey;
      final deviceTimeZone = await widget.timeZoneProvider
          .currentIanaTimeZone();
      if (!requestPermission && cancelExisting) {
        final cancelled = await widget.scheduler.cancel(
          scheduleKey: scheduleKey,
        );
        if (cancelled is ReminderScheduleRejected) return cancelled;
      }
      return requestPermission
          ? widget.scheduler.requestPermissionAndSchedule(
              scheduleKey: scheduleKey,
              localTime: localTime,
              deviceTimeZone: deviceTimeZone,
              content: content,
            )
          : widget.scheduler.schedule(
              scheduleKey: scheduleKey,
              localTime: localTime,
              deviceTimeZone: deviceTimeZone,
              content: content,
            );
    } on Object {
      return const ReminderScheduleRejected(
        ReminderScheduleFailure.temporarilyUnavailable,
      );
    }
  }

  Future<ReminderNotificationContent?> _contentFor(
    DeviceReminderPreference preference,
  ) async {
    if (preference.contentMode == ReminderNotificationContentMode.generic) {
      return _genericContent;
    }
    final projectName = widget.projectName.trim();
    if (projectName.isEmpty) return null;
    final result = await widget.planGateway.load();
    return switch (result) {
      PersonalActionPlanRejected<PersonalActionPlanSnapshot?>() => null,
      PersonalActionPlanSuccess<PersonalActionPlanSnapshot?>(
        :final value,
        :final fromOfflineCache,
      ) =>
        fromOfflineCache &&
                value != null &&
                !DateTime.now().toUtc().isBefore(value.progress.cycleUntilUtc)
            ? _genericContent
            : ReminderNotificationContent(
                title: '${widget.text.t('appTitle')} · $projectName',
                body: _detailedBody(value),
              ),
    };
  }

  String _detailedBody(PersonalActionPlanSnapshot? plan) {
    final target = plan?.current.weeklyContactTarget;
    if (plan == null || target == null) {
      return widget.text.t('personalReminderDetailNoTarget');
    }
    return widget.text
        .t('personalReminderDetailProgress')
        .replaceAll('{recorded}', '${plan.progress.recordedContactSessions}')
        .replaceAll('{target}', '$target');
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

final class _ReminderPanelHeader extends StatelessWidget {
  const _ReminderPanelHeader({
    required this.text,
    required this.showAction,
    required this.actionLabel,
    required this.actionSemanticsLabel,
    required this.actionFocusNode,
    required this.onEdit,
  });

  final AppStrings text;
  final bool showAction;
  final String actionLabel;
  final String actionSemanticsLabel;
  final FocusNode actionFocusNode;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final title = Semantics(
      container: true,
      header: true,
      child: Text(
        text.t('personalReminderTitle'),
        style: Theme.of(context).textTheme.titleLarge,
      ),
    );
    final action = showAction
        ? TextButton(
            key: const ValueKey('edit-personal-reminder'),
            focusNode: actionFocusNode,
            onPressed: onEdit,
            child: Semantics(
              label: actionSemanticsLabel,
              excludeSemantics: true,
              child: Text(actionLabel),
            ),
          )
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final largeText = MediaQuery.textScalerOf(context).scale(14) >= 21;
        final compact = constraints.maxWidth < 320 || largeText;
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ExcludeSemantics(
                    child: Icon(Icons.notifications_active_outlined),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: title),
                ],
              ),
              if (action != null)
                Align(alignment: Alignment.centerLeft, child: action),
            ],
          );
        }
        return Row(
          children: [
            const ExcludeSemantics(
              child: Icon(Icons.notifications_active_outlined),
            ),
            const SizedBox(width: 8),
            Expanded(child: title),
            ?action,
          ],
        );
      },
    );
  }
}

enum _ReminderPanelFailure {
  remoteUnavailable,
  conflict,
  unsupported,
  permissionDenied,
  scheduleUnavailable,
  detailUnavailable,
}

String _failureKey(_ReminderPanelFailure failure) => switch (failure) {
  _ReminderPanelFailure.remoteUnavailable => 'personalReminderUnavailable',
  _ReminderPanelFailure.conflict => 'personalReminderConflict',
  _ReminderPanelFailure.unsupported => 'personalReminderUnsupported',
  _ReminderPanelFailure.permissionDenied => 'personalReminderPermissionDenied',
  _ReminderPanelFailure.scheduleUnavailable => 'personalReminderScheduleFailed',
  _ReminderPanelFailure.detailUnavailable =>
    'personalReminderDetailUnavailable',
};

bool _sameScope(DeviceReminderScope left, DeviceReminderScope right) =>
    left.appUserId == right.appUserId &&
    left.workspaceId == right.workspaceId &&
    left.projectId == right.projectId &&
    left.deviceId == right.deviceId;

String _offlineCacheText(AppStrings text, DateTime cachedAtUtc) => text
    .t('personalPlanningOfflineReadOnly')
    .replaceAll('{time}', cachedAtUtc.toUtc().toIso8601String());
