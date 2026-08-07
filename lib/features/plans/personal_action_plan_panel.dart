import 'dart:async';

import 'package:flutter/material.dart';

import '../../device/device_time_zone.dart';
import '../../foundation/runtime_values.dart';
import '../../l10n/app_strings.dart';
import '../../plans/personal_action_plan.dart';

/// “今日”页中的私人周计划卡片。
///
/// 该组件只依赖本人计划 gateway。它没有管理者列表、排名或差距上报入口。
final class PersonalActionPlanPanel extends StatefulWidget {
  const PersonalActionPlanPanel({
    super.key,
    required this.text,
    required this.scopeKey,
    required this.gateway,
    required this.timeZoneProvider,
    required this.idGenerator,
  });

  final AppStrings text;
  final String scopeKey;
  final PersonalActionPlanGateway gateway;
  final DeviceTimeZoneProvider timeZoneProvider;
  final IdGenerator idGenerator;

  @override
  State<PersonalActionPlanPanel> createState() =>
      _PersonalActionPlanPanelState();
}

final class _PersonalActionPlanPanelState
    extends State<PersonalActionPlanPanel> {
  final FocusNode _editActionFocusNode = FocusNode(
    debugLabel: 'personal plan edit action',
  );
  PersonalActionPlanSnapshot? _plan;
  PersonalActionPlanFailureCode? _failure;
  DateTime? _cachedAtUtc;
  var _fromOfflineCache = false;
  var _loading = true;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant PersonalActionPlanPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scopeKey != widget.scopeKey ||
        oldWidget.gateway != widget.gateway) {
      _plan = null;
      _failure = null;
      _cachedAtUtc = null;
      _fromOfflineCache = false;
      _loading = true;
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _editActionFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    return Card(
      key: const ValueKey('personal-action-plan-panel'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PlanPanelHeader(
              text: text,
              showAction:
                  _plan != null && _plan!.pending == null && !_fromOfflineCache,
              actionFocusNode: _editActionFocusNode,
              onEdit: _saving ? null : _edit,
            ),
            const SizedBox(height: 4),
            Text(text.t('personalPlanPrivateHelp')),
            if (_fromOfflineCache) ...[
              const SizedBox(height: 8),
              Semantics(
                container: true,
                label: _offlineCacheText(text, _cachedAtUtc!),
                excludeSemantics: true,
                child: Text(
                  _offlineCacheText(text, _cachedAtUtc!),
                  key: const ValueKey('personal-plan-offline-cache'),
                ),
              ),
              if (_plan != null &&
                  !DateTime.now().toUtc().isBefore(
                    _plan!.progress.cycleUntilUtc,
                  ))
                Text(text.t('personalPlanOfflinePreviousCycle')),
            ],
            const SizedBox(height: 12),
            if (_loading)
              Center(
                child: CircularProgressIndicator(
                  semanticsLabel: text.t('personalPlanLoading'),
                ),
              )
            else if (_failure != null)
              _PlanFailure(text: text, failure: _failure!, onRetry: _load)
            else if (_plan == null)
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  key: const ValueKey('create-personal-plan'),
                  focusNode: _editActionFocusNode,
                  onPressed: _saving || _fromOfflineCache ? null : _edit,
                  icon: const Icon(Icons.add_outlined),
                  label: Text(text.t('personalPlanCreate')),
                ),
              )
            else
              _PlanFacts(
                text: text,
                plan: _plan!,
                fromOfflineCache: _fromOfflineCache,
              ),
            if (_saving) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                semanticsLabel: text.t('personalPlanSaving'),
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
    final result = await widget.gateway.load();
    if (!mounted) return;
    setState(() {
      _loading = false;
      switch (result) {
        case PersonalActionPlanSuccess<PersonalActionPlanSnapshot?>(
          :final value,
          :final fromOfflineCache,
          :final cachedAtUtc,
        ):
          _plan = value;
          _failure = null;
          _fromOfflineCache = fromOfflineCache;
          _cachedAtUtc = cachedAtUtc;
        case PersonalActionPlanRejected<PersonalActionPlanSnapshot?>(
          :final code,
        ):
          _failure = code;
          _fromOfflineCache = false;
          _cachedAtUtc = null;
      }
    });
  }

  Future<void> _edit() async {
    if (_fromOfflineCache) return;
    final current = _plan?.current;
    late final String timeZone;
    try {
      timeZone =
          current?.statisticsTimeZone ??
          await widget.timeZoneProvider.currentIanaTimeZone();
    } catch (_) {
      if (mounted) {
        setState(() => _failure = PersonalActionPlanFailureCode.invalidRequest);
      }
      return;
    }
    if (!mounted) return;
    final localeFirstDay = MaterialLocalizations.of(
      context,
    ).firstDayOfWeekIndex;
    final initialWeekStart =
        current?.weekStartIsoDay ??
        (localeFirstDay == 0 ? DateTime.sunday : localeFirstDay);
    final draft = await showDialog<_PlanDraft>(
      context: context,
      traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
      builder: (context) => FocusTraversalGroup(
        policy: WidgetOrderTraversalPolicy(),
        child: _PlanDialog(
          text: widget.text,
          initialTarget: current?.weeklyContactTarget,
          initialTimeZone: timeZone,
          initialWeekStartIsoDay: initialWeekStart,
        ),
      ),
    );
    if (mounted) {
      _editActionFocusNode.requestFocus();
    }
    if (draft == null || !mounted) return;
    setState(() {
      _saving = true;
      _failure = null;
    });
    final result = await widget.gateway.save(
      expectedRevision: _plan?.revision ?? 0,
      weeklyContactTarget: draft.weeklyContactTarget,
      statisticsTimeZone: draft.statisticsTimeZone,
      weekStartIsoDay: draft.weekStartIsoDay,
      mutationId: widget.idGenerator.next(),
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      switch (result) {
        case PersonalActionPlanSuccess<PersonalActionPlanMutation>(
          :final value,
        ):
          _plan = value.plan;
          _failure = null;
          _fromOfflineCache = false;
          _cachedAtUtc = null;
        case PersonalActionPlanRejected<PersonalActionPlanMutation>(
          :final code,
        ):
          _failure = code;
      }
    });
  }
}

final class _PlanPanelHeader extends StatelessWidget {
  const _PlanPanelHeader({
    required this.text,
    required this.showAction,
    required this.actionFocusNode,
    required this.onEdit,
  });

  final AppStrings text;
  final bool showAction;
  final FocusNode actionFocusNode;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final title = Semantics(
      container: true,
      header: true,
      child: Text(
        text.t('personalPlanTitle'),
        style: Theme.of(context).textTheme.titleLarge,
      ),
    );
    final action = showAction
        ? TextButton(
            key: const ValueKey('edit-personal-plan'),
            focusNode: actionFocusNode,
            onPressed: onEdit,
            child: Text(text.t('edit')),
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
                    child: Icon(Icons.event_available_outlined),
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
            const ExcludeSemantics(child: Icon(Icons.event_available_outlined)),
            const SizedBox(width: 8),
            Expanded(child: title),
            ?action,
          ],
        );
      },
    );
  }
}

final class _PlanFacts extends StatelessWidget {
  const _PlanFacts({
    required this.text,
    required this.plan,
    required this.fromOfflineCache,
  });

  final AppStrings text;
  final PersonalActionPlanSnapshot plan;
  final bool fromOfflineCache;

  @override
  Widget build(BuildContext context) {
    final target = plan.current.weeklyContactTarget;
    final progress = plan.progress;
    final previousCycle =
        fromOfflineCache &&
        !DateTime.now().toUtc().isBefore(progress.cycleUntilUtc);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (target == null)
          Text(text.t('personalPlanTargetOff'))
        else ...[
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _PlanFact(
                label: text.t(
                  previousCycle
                      ? 'personalPlanPreviousTarget'
                      : 'personalPlanTarget',
                ),
                value: target,
              ),
              _PlanFact(
                label: text.t('personalPlanRecorded'),
                value: progress.recordedContactSessions,
              ),
              if (progress.hasReachedTarget)
                Chip(label: Text(text.t('personalPlanReached')))
              else
                _PlanFact(
                  label: text.t('personalPlanRemaining'),
                  value: progress.remainingContactSessions ?? 0,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(text.t('personalPlanCountHelp')),
        ],
        const SizedBox(height: 8),
        Text(
          '${text.t('personalPlanTimeZone')} '
          '${plan.current.statisticsTimeZone} · '
          '${text.t('personalPlanWeekStart')} '
          '${_weekDay(text, plan.current.weekStartIsoDay)}',
        ),
        if (plan.pending case final pending?) ...[
          const SizedBox(height: 8),
          Text(
            '${text.t('personalPlanPending')} '
            '${pending.effectiveFromUtc.toIso8601String()}',
          ),
          Text(text.t('personalPlanPendingLocked')),
        ],
      ],
    );
  }
}

final class _PlanFact extends StatelessWidget {
  const _PlanFact({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$label $value',
      excludeSemantics: true,
      child: Chip(label: Text('$label $value')),
    );
  }
}

final class _PlanFailure extends StatelessWidget {
  const _PlanFailure({
    required this.text,
    required this.failure,
    required this.onRetry,
  });

  final AppStrings text;
  final PersonalActionPlanFailureCode failure;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final message = switch (failure) {
      PersonalActionPlanFailureCode.conflict => text.t('personalPlanConflict'),
      PersonalActionPlanFailureCode.pendingChange => text.t(
        'personalPlanPendingLocked',
      ),
      PersonalActionPlanFailureCode.invalidRequest => text.t(
        'personalPlanInvalid',
      ),
      _ => text.t('personalPlanUnavailable'),
    };
    return Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Semantics(container: true, liveRegion: true, child: Text(message)),
        TextButton(onPressed: onRetry, child: Text(text.t('retry'))),
      ],
    );
  }
}

final class _PlanDraft {
  const _PlanDraft({
    required this.weeklyContactTarget,
    required this.statisticsTimeZone,
    required this.weekStartIsoDay,
  });

  final int? weeklyContactTarget;
  final String statisticsTimeZone;
  final int weekStartIsoDay;
}

final class _PlanDialog extends StatefulWidget {
  const _PlanDialog({
    required this.text,
    required this.initialTarget,
    required this.initialTimeZone,
    required this.initialWeekStartIsoDay,
  });

  final AppStrings text;
  final int? initialTarget;
  final String initialTimeZone;
  final int initialWeekStartIsoDay;

  @override
  State<_PlanDialog> createState() => _PlanDialogState();
}

final class _PlanDialogState extends State<_PlanDialog> {
  late final TextEditingController _targetController;
  late final TextEditingController _timeZoneController;
  late bool _targetEnabled;
  late int _weekStart;
  String? _error;

  @override
  void initState() {
    super.initState();
    _targetEnabled = widget.initialTarget != null;
    _targetController = TextEditingController(
      text: widget.initialTarget?.toString() ?? '1',
    );
    _timeZoneController = TextEditingController(text: widget.initialTimeZone);
    _weekStart = widget.initialWeekStartIsoDay;
  }

  @override
  void dispose() {
    _targetController.dispose();
    _timeZoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    return AlertDialog(
      semanticLabel: text.t('personalPlanEdit'),
      title: Text(text.t('personalPlanEdit')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              key: const ValueKey('personal-plan-target-enabled'),
              autofocus: true,
              contentPadding: EdgeInsets.zero,
              value: _targetEnabled,
              onChanged: (value) => setState(() => _targetEnabled = value),
              title: Text(text.t('personalPlanEnableTarget')),
            ),
            if (_targetEnabled)
              TextField(
                key: const ValueKey('personal-plan-target'),
                controller: _targetController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: text.t('personalPlanTarget'),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('personal-plan-time-zone'),
              controller: _timeZoneController,
              decoration: InputDecoration(
                labelText: text.t('personalPlanTimeZone'),
                helperText: text.t('personalPlanTimeZoneHelp'),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              key: const ValueKey('personal-plan-week-start'),
              initialValue: _weekStart,
              decoration: InputDecoration(
                labelText: text.t('personalPlanWeekStart'),
              ),
              items: [
                for (var day = 1; day <= 7; day++)
                  DropdownMenuItem(
                    value: day,
                    child: Text(_weekDay(text, day)),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _weekStart = value);
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Semantics(
                container: true,
                liveRegion: true,
                child: Text(
                  _error!,
                  key: const ValueKey('personal-plan-validation-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('cancel-personal-plan'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(text.t('cancel')),
        ),
        FilledButton(
          key: const ValueKey('save-personal-plan'),
          onPressed: _submit,
          child: Text(text.t('save')),
        ),
      ],
    );
  }

  void _submit() {
    final target = _targetEnabled ? int.tryParse(_targetController.text) : null;
    final timeZone = _timeZoneController.text.trim();
    if ((_targetEnabled && (target == null || target < 1 || target > 999)) ||
        timeZone.isEmpty ||
        timeZone.length > 100) {
      setState(() => _error = widget.text.t('personalPlanInvalid'));
      return;
    }
    Navigator.of(context).pop(
      _PlanDraft(
        weeklyContactTarget: target,
        statisticsTimeZone: timeZone,
        weekStartIsoDay: _weekStart,
      ),
    );
  }
}

String _weekDay(AppStrings text, int isoDay) => text.t('weekDay.$isoDay');

String _offlineCacheText(AppStrings text, DateTime cachedAtUtc) => text
    .t('personalPlanningOfflineReadOnly')
    .replaceAll('{time}', cachedAtUtc.toUtc().toIso8601String());
