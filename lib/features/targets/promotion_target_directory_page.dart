import 'dart:async';

import 'package:flutter/material.dart';

import '../../foundation/runtime_values.dart';
import '../../l10n/app_strings.dart';
import '../../targets/promotion_target.dart';
import 'target_institution_relationship_panel.dart';

final class PromotionTargetDirectoryPage extends StatefulWidget {
  const PromotionTargetDirectoryPage({
    super.key,
    required this.text,
    required this.gateway,
    required this.idGenerator,
    required this.clock,
    required this.scopeKey,
    required this.canCreate,
    required this.canConfigureStageAliases,
    required this.canManageRelationship,
    required this.canManageInstitutionRelationships,
  });

  final AppStrings text;
  final PromotionTargetGateway gateway;
  final IdGenerator idGenerator;
  final AppClock clock;
  final String scopeKey;
  final bool canCreate;
  final bool canConfigureStageAliases;
  final bool canManageRelationship;
  final bool canManageInstitutionRelationships;

  @override
  State<PromotionTargetDirectoryPage> createState() =>
      _PromotionTargetDirectoryPageState();
}

final class _PromotionTargetDirectoryPageState
    extends State<PromotionTargetDirectoryPage> {
  List<PromotionTargetProfile>? _targets;
  PromotionTargetFailureCode? _failure;
  DateTime? _offlineAuthorizedAtUtc;
  Timer? _offlineExpiryTimer;
  var _busy = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant PromotionTargetDirectoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scopeKey == widget.scopeKey &&
        identical(oldWidget.gateway, widget.gateway)) {
      return;
    }
    _offlineExpiryTimer?.cancel();
    _offlineExpiryTimer = null;
    _targets = null;
    _offlineAuthorizedAtUtc = null;
    _failure = null;
    _busy = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  @override
  void dispose() {
    _offlineExpiryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                text.t('targetsTitle'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            IconButton(
              key: const ValueKey('refresh-promotion-targets'),
              onPressed: _busy ? null : _load,
              tooltip: text.t('retry'),
              icon: const Icon(Icons.refresh_outlined),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(text.t('targetsPrivacyHelp')),
        if (_offlineAuthorizedAtUtc != null) ...[
          const SizedBox(height: 8),
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: ListTile(
              leading: const Icon(Icons.lock_clock_outlined),
              title: Text(text.t('targetsOfflineSnapshot')),
              subtitle: Text(
                '${text.t('targetsOfflineAuthorizedAt')}: '
                '${_offlineAuthorizedAtUtc!.toIso8601String()}',
              ),
            ),
          ),
        ],
        if (widget.canConfigureStageAliases && _stageAliases != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('configure-target-stage-aliases'),
              onPressed: _busy || _offlineAuthorizedAtUtc != null
                  ? null
                  : _configureStageAliases,
              icon: const Icon(Icons.tune_outlined),
              label: Text(text.t('targetsConfigureStageAliases')),
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (_busy && _targets == null)
          const Center(child: CircularProgressIndicator())
        else if (_targets == null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.cloud_off_outlined),
              title: Text(text.t('targetsOnlineRequired')),
              trailing: IconButton(
                onPressed: _busy ? null : _load,
                icon: const Icon(Icons.refresh_outlined),
              ),
            ),
          )
        else if (_targets!.isEmpty)
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_off_outlined),
              title: Text(text.t('targetsEmpty')),
              subtitle: Text(text.t('targetsAnonymousDefault')),
            ),
          )
        else
          for (final target in _targets!) _targetCard(text, target),
        if (_targets != null && _offlineAuthorizedAtUtc == null)
          TargetInstitutionRelationshipPanel(
            text: text,
            gateway: widget.gateway,
            idGenerator: widget.idGenerator,
            targets: _targets!,
            canManage:
                widget.canManageInstitutionRelationships &&
                _offlineAuthorizedAtUtc == null,
          ),
        if (_failure != null && _targets != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              text.t('targetsOperationFailed'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (widget.canCreate) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('create-promotion-target'),
            onPressed: _busy || _offlineAuthorizedAtUtc != null
                ? null
                : _create,
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: Text(text.t('targetsCreate')),
          ),
        ],
      ],
    );
  }

  Widget _targetCard(AppStrings text, PromotionTargetProfile target) {
    final details = [
      if (target.phone != null) '${text.t('targetsPhone')}: ${target.phone}',
      if (target.email != null) '${text.t('targetsEmail')}: ${target.email}',
    ];
    final relationship = target.projectRelationship;
    return Card(
      key: ValueKey('promotion-target-${target.id}'),
      child: ListTile(
        leading: Icon(
          target.type == PromotionTargetType.person
              ? Icons.person_outline
              : Icons.business_outlined,
        ),
        title: Text(target.displayName),
        subtitle: Text(
          [
            target.type == PromotionTargetType.person
                ? text.t('targetsPerson')
                : text.t('targetsInstitution'),
            ...details,
            if (relationship != null)
              '${text.t('targetsRelationshipStage')}: '
                  '${_stageLabel(text, relationship, relationship.stage)} '
                  '(${relationship.displayStage})',
            if (relationship != null)
              '${text.t('targetsRelationshipLifecycle')}: '
                  '${text.t('targetsLifecycle.${relationship.lifecycleStatus.storageValue}')}',
            if (relationship?.followUpNote != null)
              '${text.t('targetsFollowUpNote')}: '
                  '${relationship!.followUpNote}',
            if (relationship == null) text.t('targetsNoProjectRelationship'),
          ].join('\n'),
        ),
        trailing:
            relationship == null ||
                !widget.canManageRelationship ||
                _offlineAuthorizedAtUtc != null
            ? null
            : const Icon(Icons.chevron_right),
        onTap:
            relationship == null ||
                !widget.canManageRelationship ||
                _offlineAuthorizedAtUtc != null
            ? null
            : () => _editRelationship(target),
      ),
    );
  }

  List<PromotionTargetStageAlias>? get _stageAliases {
    for (final target in _targets ?? const <PromotionTargetProfile>[]) {
      final relationship = target.projectRelationship;
      if (relationship != null) return relationship.stageAliases;
    }
    return null;
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    final result = await widget.gateway.loadAssigned();
    if (!mounted) return;
    switch (result) {
      case PromotionTargetSuccess(
        :final value,
        :final authorizedAtUtc,
        :final expiresAtUtc,
        :final fromOfflineCache,
      ):
        if (fromOfflineCache &&
            (authorizedAtUtc == null ||
                expiresAtUtc == null ||
                !widget.clock.now().toUtc().isBefore(expiresAtUtc))) {
          _clearVisibleTargets(PromotionTargetFailureCode.networkUnavailable);
          return;
        }
        setState(() {
          _targets = value;
          _offlineAuthorizedAtUtc = fromOfflineCache ? authorizedAtUtc : null;
          _busy = false;
        });
        _scheduleOfflineExpiry(fromOfflineCache ? expiresAtUtc : null);
      case PromotionTargetRejected(:final code):
        _clearVisibleTargets(code);
      case PromotionTargetConflict():
        _clearVisibleTargets(PromotionTargetFailureCode.conflict);
    }
  }

  void _scheduleOfflineExpiry(DateTime? expiresAtUtc) {
    _offlineExpiryTimer?.cancel();
    _offlineExpiryTimer = null;
    if (expiresAtUtc == null) return;
    final remaining = expiresAtUtc.difference(widget.clock.now().toUtc());
    if (remaining <= Duration.zero) {
      _clearVisibleTargets(PromotionTargetFailureCode.networkUnavailable);
      return;
    }
    _offlineExpiryTimer = Timer(remaining, () {
      if (!mounted) return;
      _clearVisibleTargets(PromotionTargetFailureCode.networkUnavailable);
    });
  }

  void _clearVisibleTargets(PromotionTargetFailureCode failure) {
    _offlineExpiryTimer?.cancel();
    _offlineExpiryTimer = null;
    setState(() {
      _targets = null;
      _offlineAuthorizedAtUtc = null;
      _failure = failure;
      _busy = false;
    });
  }

  Future<void> _create() async {
    final input = await showDialog<_TargetInput>(
      context: context,
      builder: (context) => _CreateTargetDialog(text: widget.text),
    );
    if (input == null || !mounted) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    final result = await widget.gateway.create(
      type: input.type,
      displayName: input.displayName,
      phone: input.phone,
      email: input.email,
      requestId: widget.idGenerator.next(),
    );
    if (!mounted) return;
    if (result case PromotionTargetRejected(:final code)) {
      setState(() {
        _failure = code;
        _busy = false;
      });
      return;
    }
    if (result case PromotionTargetConflict()) {
      setState(() {
        _failure = PromotionTargetFailureCode.conflict;
        _busy = false;
      });
      return;
    }
    await _load();
  }

  Future<void> _editRelationship(PromotionTargetProfile target) async {
    final current = target.projectRelationship;
    if (current == null) return;
    final input = await showDialog<_RelationshipInput>(
      context: context,
      builder: (context) => _RelationshipDialog(
        text: widget.text,
        targetName: target.displayName,
        relationship: current,
      ),
    );
    if (input == null || !mounted) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    final result = await widget.gateway.updateRelationship(
      targetId: target.id,
      expectedRevision: current.revisionNumber,
      stage: input.stage,
      lifecycleStatus: input.lifecycleStatus,
      followUpNote: input.followUpNote,
      reason: input.reason,
      reasonDetail: input.reasonDetail,
      mutationId: widget.idGenerator.next(),
      resolvedConflictId: null,
    );
    if (!mounted) return;
    switch (result) {
      case PromotionTargetSuccess(:final value):
        _replaceRelationship(target.id, value);
        setState(() => _busy = false);
      case final PromotionTargetConflict<PromotionTargetRelationship> conflict:
        final current = conflict.current;
        _replaceRelationship(target.id, current);
        setState(() => _busy = false);
        await _resolveRelationshipConflict(target, conflict);
      case PromotionTargetRejected(:final code):
        setState(() {
          _busy = false;
          _failure = code;
        });
    }
  }

  Future<void> _resolveRelationshipConflict(
    PromotionTargetProfile target,
    PromotionTargetConflict<PromotionTargetRelationship> conflict,
  ) async {
    final proposal = conflict.proposed;
    final conflictId = conflict.conflictId;
    if (proposal == null || conflictId == null || !mounted) {
      setState(() => _failure = PromotionTargetFailureCode.conflict);
      return;
    }
    final choice = await showDialog<_RelationshipConflictChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.text.t('targetsRelationshipConflictTitle')),
        content: Text(
          '${widget.text.t('targetsRelationshipConflict')}\n\n'
          '${widget.text.t('targetsConflictCurrent')}: '
          '${conflict.current.displayStage} · '
          '${conflict.current.followUpNote ?? widget.text.t('targetsNoNote')}\n'
          '${widget.text.t('targetsConflictProposed')}: '
          '${proposal.displayStage} · '
          '${proposal.followUpNote ?? widget.text.t('targetsNoNote')}',
        ),
        actions: [
          TextButton(
            key: const ValueKey('keep-current-relationship'),
            onPressed: () =>
                Navigator.pop(context, _RelationshipConflictChoice.keepCurrent),
            child: Text(widget.text.t('targetsKeepCurrent')),
          ),
          FilledButton(
            key: const ValueKey('apply-proposed-relationship'),
            onPressed: () => Navigator.pop(
              context,
              _RelationshipConflictChoice.applyProposed,
            ),
            child: Text(widget.text.t('targetsApplyProposed')),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) {
      setState(() => _failure = PromotionTargetFailureCode.conflict);
      return;
    }
    final useProposal = choice == _RelationshipConflictChoice.applyProposed;
    setState(() {
      _busy = true;
      _failure = null;
    });
    final result = await widget.gateway.updateRelationship(
      targetId: target.id,
      expectedRevision: conflict.current.revisionNumber,
      stage: useProposal ? proposal.stage : conflict.current.stage,
      lifecycleStatus: useProposal
          ? proposal.lifecycleStatus
          : conflict.current.lifecycleStatus,
      followUpNote: useProposal
          ? proposal.followUpNote
          : conflict.current.followUpNote,
      reason: PromotionTargetRelationshipReason.correction,
      reasonDetail: null,
      mutationId: widget.idGenerator.next(),
      resolvedConflictId: conflictId,
    );
    if (!mounted) return;
    switch (result) {
      case PromotionTargetSuccess(:final value):
        _replaceRelationship(target.id, value);
        setState(() => _busy = false);
      case PromotionTargetRejected(:final code):
        setState(() {
          _busy = false;
          _failure = code;
        });
      case PromotionTargetConflict(:final current):
        _replaceRelationship(target.id, current);
        setState(() {
          _busy = false;
          _failure = PromotionTargetFailureCode.conflict;
        });
    }
  }

  Future<void> _configureStageAliases() async {
    final current = _stageAliases;
    if (current == null) return;
    final aliases = await showDialog<List<PromotionTargetStageAlias>>(
      context: context,
      builder: (context) =>
          _StageAliasDialog(text: widget.text, aliases: current),
    );
    if (aliases == null || !mounted) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    final result = await widget.gateway.configureStageAliases(aliases: aliases);
    if (!mounted) return;
    switch (result) {
      case PromotionTargetSuccess():
        await _load();
      case PromotionTargetRejected(:final code):
        setState(() {
          _busy = false;
          _failure = code;
        });
      case PromotionTargetConflict():
        setState(() {
          _busy = false;
          _failure = PromotionTargetFailureCode.conflict;
        });
    }
  }

  void _replaceRelationship(
    String targetId,
    PromotionTargetRelationship relationship,
  ) {
    final targets = _targets;
    if (targets == null) return;
    _targets = targets.map((target) {
      if (target.id != targetId) return target;
      return PromotionTargetProfile(
        id: target.id,
        type: target.type,
        displayName: target.displayName,
        phone: target.phone,
        email: target.email,
        createdAtUtc: target.createdAtUtc,
        hasCurrentProjectRelationship: true,
        projectRelationship: relationship,
      );
    }).toList();
  }
}

String _stageLabel(
  AppStrings text,
  PromotionTargetRelationship relationship,
  int stage,
) => relationship.aliasFor(stage).displayName ?? text.t('targetsStage.$stage');

final class _RelationshipDialog extends StatefulWidget {
  const _RelationshipDialog({
    required this.text,
    required this.targetName,
    required this.relationship,
  });

  final AppStrings text;
  final String targetName;
  final PromotionTargetRelationship relationship;

  @override
  State<_RelationshipDialog> createState() => _RelationshipDialogState();
}

final class _RelationshipDialogState extends State<_RelationshipDialog> {
  late int _stage;
  late PromotionTargetRelationshipLifecycle _lifecycleStatus;
  late PromotionTargetRelationshipReason _reason;
  late final TextEditingController _note;
  late final TextEditingController _reasonDetail;

  @override
  void initState() {
    super.initState();
    final relationship = widget.relationship;
    _stage = relationship.stage;
    _lifecycleStatus = relationship.lifecycleStatus;
    _reason = PromotionTargetRelationshipReason.progressUpdate;
    _note = TextEditingController(text: relationship.followUpNote);
    _reasonDetail = TextEditingController();
  }

  @override
  void dispose() {
    _note.dispose();
    _reasonDetail.dispose();
    super.dispose();
  }

  bool get _isDecrease => _stage < widget.relationship.stage;

  List<PromotionTargetRelationshipReason> get _availableReasons =>
      PromotionTargetRelationshipReason.values
          .where(
            (reason) =>
                !_isDecrease ||
                reason != PromotionTargetRelationshipReason.progressUpdate,
          )
          .toList();

  bool get _hasChange =>
      _stage != widget.relationship.stage ||
      _lifecycleStatus != widget.relationship.lifecycleStatus ||
      _nullable(_note.text) != widget.relationship.followUpNote;

  bool get _canSave =>
      _hasChange &&
      (_reason != PromotionTargetRelationshipReason.other ||
          _reasonDetail.text.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      '${widget.text.t('targetsEditRelationship')} · ${widget.targetName}',
    ),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.text.t('targetsRelationshipScaleHelp')),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              key: const ValueKey('target-relationship-stage'),
              initialValue: _stage,
              decoration: InputDecoration(
                labelText: widget.text.t('targetsRelationshipStage'),
              ),
              items: [
                for (var stage = 0; stage <= 4; stage++)
                  DropdownMenuItem(
                    value: stage,
                    child: Text(
                      '${stage * 2} · '
                      '${_stageLabel(widget.text, widget.relationship, stage)}',
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _stage = value;
                  if (!_availableReasons.contains(_reason)) {
                    _reason = PromotionTargetRelationshipReason.contactLost;
                  }
                });
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<PromotionTargetRelationshipLifecycle>(
              key: const ValueKey('target-relationship-lifecycle'),
              initialValue: _lifecycleStatus,
              decoration: InputDecoration(
                labelText: widget.text.t('targetsRelationshipLifecycle'),
              ),
              items: [
                for (final lifecycle
                    in PromotionTargetRelationshipLifecycle.values)
                  DropdownMenuItem(
                    value: lifecycle,
                    child: Text(
                      widget.text.t(
                        'targetsLifecycle.${lifecycle.storageValue}',
                      ),
                    ),
                  ),
              ],
              onChanged: (value) =>
                  setState(() => _lifecycleStatus = value ?? _lifecycleStatus),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('target-follow-up-note'),
              controller: _note,
              maxLength: 4000,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: widget.text.t('targetsFollowUpNote'),
                helperText: widget.text.t('targetsFollowUpNoteHelp'),
              ),
              onChanged: (_) => setState(() {}),
            ),
            DropdownButtonFormField<PromotionTargetRelationshipReason>(
              key: const ValueKey('target-relationship-reason'),
              initialValue: _reason,
              decoration: InputDecoration(
                labelText: widget.text.t('targetsRelationshipReason'),
              ),
              items: [
                for (final reason in _availableReasons)
                  DropdownMenuItem(
                    value: reason,
                    child: Text(
                      widget.text.t('targetsReason.${reason.storageValue}'),
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _reason = value ?? _reason),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('target-relationship-reason-detail'),
              controller: _reasonDetail,
              maxLength: 1000,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: widget.text.t('targetsRelationshipReasonDetail'),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (widget.relationship.history.isNotEmpty) ...[
              const Divider(height: 32),
              Text(
                widget.text.t('targetsRelationshipHistory'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              for (final revision in widget.relationship.history.take(10))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    revision.oldStage == null
                        ? '${revision.newStage * 2} · '
                              '${_stageLabel(widget.text, widget.relationship, revision.newStage)}'
                        : '${revision.oldStage! * 2} → '
                              '${revision.newStage * 2}',
                  ),
                  subtitle: Text(
                    [
                      widget.text.t('targetsReason.${revision.reasonCode}'),
                      if (revision.reasonDetail != null) revision.reasonDetail!,
                      if (revision.followUpNote != null) revision.followUpNote!,
                    ].join(' · '),
                  ),
                  trailing: Text('#${revision.revisionNumber}'),
                ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(widget.text.t('cancel')),
      ),
      FilledButton(
        key: const ValueKey('save-target-relationship'),
        onPressed: _canSave
            ? () => Navigator.pop(
                context,
                _RelationshipInput(
                  stage: _stage,
                  lifecycleStatus: _lifecycleStatus,
                  followUpNote: _nullable(_note.text),
                  reason: _reason,
                  reasonDetail: _nullable(_reasonDetail.text),
                ),
              )
            : null,
        child: Text(widget.text.t('save')),
      ),
    ],
  );
}

final class _RelationshipInput {
  const _RelationshipInput({
    required this.stage,
    required this.lifecycleStatus,
    required this.followUpNote,
    required this.reason,
    required this.reasonDetail,
  });

  final int stage;
  final PromotionTargetRelationshipLifecycle lifecycleStatus;
  final String? followUpNote;
  final PromotionTargetRelationshipReason reason;
  final String? reasonDetail;
}

enum _RelationshipConflictChoice { keepCurrent, applyProposed }

final class _StageAliasDialog extends StatefulWidget {
  const _StageAliasDialog({required this.text, required this.aliases});

  final AppStrings text;
  final List<PromotionTargetStageAlias> aliases;

  @override
  State<_StageAliasDialog> createState() => _StageAliasDialogState();
}

final class _StageAliasDialogState extends State<_StageAliasDialog> {
  late final List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = [
      for (var stage = 0; stage <= 4; stage++)
        TextEditingController(
          text: widget.aliases
              .firstWhere((alias) => alias.stage == stage)
              .displayName,
        ),
    ];
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.text.t('targetsConfigureStageAliases')),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.text.t('targetsStageAliasHelp')),
            const SizedBox(height: 12),
            for (var stage = 0; stage <= 4; stage++) ...[
              TextField(
                key: ValueKey('target-stage-alias-$stage'),
                controller: _controllers[stage],
                maxLength: 80,
                decoration: InputDecoration(
                  labelText:
                      '${stage * 2} · ${widget.text.t('targetsStage.$stage')}',
                  hintText: widget.text.t('targetsStageAliasDefault'),
                ),
              ),
              if (stage < 4) const SizedBox(height: 4),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(widget.text.t('cancel')),
      ),
      FilledButton(
        key: const ValueKey('save-target-stage-aliases'),
        onPressed: () => Navigator.pop(context, [
          for (var stage = 0; stage <= 4; stage++)
            PromotionTargetStageAlias(
              stage: stage,
              displayStage: stage * 2,
              displayName: _nullable(_controllers[stage].text),
            ),
        ]),
        child: Text(widget.text.t('save')),
      ),
    ],
  );
}

final class _CreateTargetDialog extends StatefulWidget {
  const _CreateTargetDialog({required this.text});

  final AppStrings text;

  @override
  State<_CreateTargetDialog> createState() => _CreateTargetDialogState();
}

final class _CreateTargetDialogState extends State<_CreateTargetDialog> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  var _type = PromotionTargetType.person;
  var _confirmed = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.text.t('targetsCreate')),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedButton<PromotionTargetType>(
            segments: [
              ButtonSegment(
                value: PromotionTargetType.person,
                label: Text(widget.text.t('targetsPerson')),
              ),
              ButtonSegment(
                value: PromotionTargetType.institution,
                label: Text(widget.text.t('targetsInstitution')),
              ),
            ],
            selected: {_type},
            onSelectionChanged: (value) => setState(() => _type = value.single),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('promotion-target-name'),
            controller: _name,
            maxLength: 200,
            decoration: InputDecoration(
              labelText: widget.text.t('targetsName'),
            ),
            onChanged: (_) => setState(() {}),
          ),
          TextField(
            key: const ValueKey('promotion-target-phone'),
            controller: _phone,
            maxLength: 80,
            decoration: InputDecoration(
              labelText: widget.text.t('targetsPhone'),
            ),
          ),
          TextField(
            key: const ValueKey('promotion-target-email'),
            controller: _email,
            maxLength: 320,
            decoration: InputDecoration(
              labelText: widget.text.t('targetsEmail'),
            ),
          ),
          CheckboxListTile(
            key: const ValueKey('promotion-target-purpose-confirmed'),
            value: _confirmed,
            onChanged: (value) => setState(() => _confirmed = value ?? false),
            title: Text(widget.text.t('targetsPurposeConfirmation')),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(widget.text.t('cancel')),
      ),
      FilledButton(
        key: const ValueKey('confirm-promotion-target'),
        onPressed: _confirmed && _name.text.trim().isNotEmpty
            ? () => Navigator.pop(
                context,
                _TargetInput(
                  type: _type,
                  displayName: _name.text.trim(),
                  phone: _nullable(_phone.text),
                  email: _nullable(_email.text),
                ),
              )
            : null,
        child: Text(widget.text.t('create')),
      ),
    ],
  );
}

final class _TargetInput {
  const _TargetInput({
    required this.type,
    required this.displayName,
    required this.phone,
    required this.email,
  });

  final PromotionTargetType type;
  final String displayName;
  final String? phone;
  final String? email;
}

String? _nullable(String value) {
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}
