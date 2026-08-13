import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app_session/session_context_gateway.dart';
import '../../device/device_time_zone.dart';
import '../../l10n/app_strings.dart';
import '../../regions/contact_region_resolver.dart';
import '../../services/location_service.dart';
import '../../targets/promotion_target.dart';
import '../contact_entry/contact_channel_label.dart';
import '../contact_entry/contact_target_links_editor.dart';
import '../contact_journal/contact_journal.dart';
import '../contact_journal/contact_models.dart';

/// 本人已提交接触的当前投影、追加历史和受控修订入口。
final class ContactRevisionScreen extends StatefulWidget {
  const ContactRevisionScreen({
    super.key,
    required this.controller,
    required this.context,
    required this.contactId,
    required this.contactJournal,
    required this.deviceId,
    required this.locationCapture,
    required this.timeZoneProvider,
    required this.regionResolver,
    this.targetGateway,
  });

  final AppController controller;
  final TrustedSessionContext context;
  final String contactId;
  final ContactJournal contactJournal;
  final String deviceId;
  final ContactLocationCapture locationCapture;
  final DeviceTimeZoneProvider timeZoneProvider;
  final ContactRegionResolver regionResolver;
  final PromotionTargetGateway? targetGateway;

  @override
  State<ContactRevisionScreen> createState() => _ContactRevisionScreenState();
}

final class _ContactRevisionScreenState extends State<ContactRevisionScreen> {
  ContactRecord? _contact;
  List<ContactRevision> _history = const [];
  List<ContactRevisionConflict> _conflicts = const [];
  Object? _loadError;
  var _loading = true;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final contact = await widget.contactJournal.contactByIdForOwner(
        contactId: widget.contactId,
        appUserId: widget.context.appUserId,
      );
      final history = contact == null
          ? const <ContactRevision>[]
          : await widget.contactJournal.listContactRevisions(
              contactId: widget.contactId,
              appUserId: widget.context.appUserId,
            );
      final conflicts = contact == null
          ? const <ContactRevisionConflict>[]
          : await widget.contactJournal.listContactRevisionConflicts(
              contactId: widget.contactId,
              appUserId: widget.context.appUserId,
            );
      if (!mounted) {
        return;
      }
      setState(() {
        _contact = contact;
        _history = history;
        _conflicts = conflicts;
        _loadError = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = AppStrings(widget.controller.localeCode);
    return Scaffold(
      appBar: AppBar(title: Text(text.t('contactDetails'))),
      body: _body(text),
    );
  }

  Widget _body(AppStrings text) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return Center(child: Text(text.t('contactHistoryLoadFailed')));
    }
    final contact = _contact;
    if (contact == null) {
      return Center(child: Text(text.t('contactNotFound')));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final conflict in _conflicts) ...[
          _conflictCard(text, contact, conflict),
          const SizedBox(height: 12),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        text.t('currentContactFacts'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    Chip(
                      label: Text(
                        contact.lifecycleStatus == ContactLifecycleStatus.active
                            ? text.t('contactActive')
                            : text.t('contactVoided'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(_factSummary(text, contact)),
                if (contact.lifecycleStatus == ContactLifecycleStatus.active &&
                    _conflicts.isEmpty) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        key: const ValueKey('correct-contact'),
                        onPressed: _saving ? null : () => _correct(contact),
                        icon: const Icon(Icons.edit_outlined),
                        label: Text(text.t('correctContact')),
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey('void-contact'),
                        onPressed: _saving ? null : () => _void(contact),
                        icon: const Icon(Icons.block_outlined),
                        label: Text(text.t('voidContact')),
                      ),
                    ],
                  ),
                ],
                if (_saving) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          '${text.t('contactHistory')} (${_history.length})',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        for (final revision in _history)
          Card(
            key: ValueKey('contact-revision-${revision.revisionNumber}'),
            child: ListTile(
              leading: CircleAvatar(child: Text('${revision.revisionNumber}')),
              title: Text(_revisionTitle(text, revision)),
              subtitle: Text(
                [
                  revision.revisedAtUtc.toIso8601String(),
                  if (revision.reason != null)
                    '${text.t('revisionReason')}：${revision.reason}',
                  _revisionFactSummary(text, revision),
                ].join('\n'),
              ),
              isThreeLine: true,
            ),
          ),
      ],
    );
  }

  Widget _conflictCard(
    AppStrings text,
    ContactRecord contact,
    ContactRevisionConflict conflict,
  ) {
    return Card(
      key: ValueKey('contact-conflict-${conflict.conflictId}'),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text.t('contactConflictTitle'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              text.t(
                conflict.status == ContactRevisionConflictStatus.pending
                    ? 'contactConflictHelp'
                    : 'contactConflictResolutionPending',
              ),
            ),
            const SizedBox(height: 12),
            for (final field in conflict.conflictingFields) ...[
              Text(
                _conflictDifference(text, conflict, field),
                key: ValueKey('contact-conflict-${conflict.conflictId}-$field'),
              ),
              const SizedBox(height: 8),
            ],
            if (conflict.status == ContactRevisionConflictStatus.pending)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    key: ValueKey('use-current-${conflict.conflictId}'),
                    onPressed: _saving
                        ? null
                        : () => _resolveConflict(
                            conflict,
                            conflict.currentSnapshot,
                            text.t('contactConflictUseCurrentReason'),
                          ),
                    child: Text(text.t('contactConflictUseCurrent')),
                  ),
                  FilledButton(
                    key: ValueKey('use-proposed-${conflict.conflictId}'),
                    onPressed: _saving
                        ? null
                        : () => _resolveConflict(
                            conflict,
                            conflict.proposedSnapshot,
                            text.t('contactConflictUseProposedReason'),
                          ),
                    child: Text(text.t('contactConflictUseProposed')),
                  ),
                  TextButton(
                    key: ValueKey('merge-conflict-${conflict.conflictId}'),
                    onPressed: _saving
                        ? null
                        : () => _mergeConflict(contact, conflict),
                    child: Text(text.t('contactConflictMerge')),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _conflictDifference(
    AppStrings text,
    ContactRevisionConflict conflict,
    String field,
  ) {
    final label = switch (field) {
      'occurredAt' => text.t('occurredAt'),
      'channel' => text.t('contactChannel'),
      'location' => text.t('location'),
      'reachCount' => text.t('reachCount'),
      'interestLevel' => text.t('interestLevel'),
      'answers' => text.t('questionnaireAnswers'),
      'targetLinks' => text.t('contactTargetLinks'),
      _ => field,
    };
    return [
      label,
      '${text.t('contactConflictCurrent')}：${_conflictValue(text, conflict.currentSnapshot, field)}',
      '${text.t('contactConflictProposed')}：${_conflictValue(text, conflict.proposedSnapshot, field)}',
    ].join('\n');
  }

  String _conflictValue(
    AppStrings text,
    ContactConflictSnapshot snapshot,
    String field,
  ) => switch (field) {
    'occurredAt' =>
      '${snapshot.occurredAtUtc.toIso8601String()} (${snapshot.occurredTimeZone})',
    'channel' => contactChannelLabel(text, snapshot.channel),
    'location' => _locationLabel(text, snapshot.location),
    'reachCount' => '${snapshot.reachCount}',
    'interestLevel' => '${snapshot.interestLevel}',
    'answers' => _questionnaireAnswerSummary(text, snapshot.answers),
    'targetLinks' => '${snapshot.targetLinks.length}',
    _ => text.t('unknownValue'),
  };

  Future<void> _resolveConflict(
    ContactRevisionConflict conflict,
    ContactConflictSnapshot snapshot,
    String reason,
  ) async {
    setState(() => _saving = true);
    try {
      await widget.contactJournal.resolveContactRevisionConflict(
        ContactConflictResolutionSubmission(
          conflictId: conflict.conflictId,
          appUserId: widget.context.appUserId,
          workspaceId: widget.context.workspace.id,
          projectId: widget.context.project.id,
          deviceId: widget.deviceId,
          reason: reason,
          snapshot: snapshot,
        ),
      );
      await _load();
      _showMessage('contactConflictResolved');
    } on ContactValidationException catch (error) {
      _showMessage(error.code);
    } catch (_) {
      _showMessage('contactConflictResolutionFailed');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _mergeConflict(
    ContactRecord contact,
    ContactRevisionConflict conflict,
  ) async {
    final values = await showDialog<_CorrectionValues>(
      context: context,
      builder: (dialogContext) => _CorrectionDialog(
        text: AppStrings(widget.controller.localeCode),
        contact: contact,
        locationCapture: widget.locationCapture,
        timeZoneProvider: widget.timeZoneProvider,
        regionResolver: widget.regionResolver,
        titleKey: 'contactConflictMerge',
        proposedAnswers: conflict.conflictingFields.contains('answers')
            ? conflict.proposedSnapshot.answers
            : null,
        proposedTargetLinks: conflict.conflictingFields.contains('targetLinks')
            ? conflict.proposedSnapshot.targetLinks
            : null,
        targetGateway: widget.targetGateway,
      ),
    );
    if (values == null || !mounted) {
      return;
    }
    await _resolveConflict(
      conflict,
      ContactConflictSnapshot(
        occurredAtUtc: values.occurredAtUtc,
        occurredTimeZone: values.occurredTimeZone,
        channel: values.channel,
        channelDetail: values.channelDetail,
        location: values.location,
        reachCount: values.reachCount,
        interestLevel: values.interestLevel,
        answers: values.answers,
        targetLinks: values.targetLinks,
      ),
      values.reason,
    );
  }

  Future<void> _correct(ContactRecord contact) async {
    final values = await showDialog<_CorrectionValues>(
      context: context,
      builder: (dialogContext) => _CorrectionDialog(
        text: AppStrings(widget.controller.localeCode),
        contact: contact,
        locationCapture: widget.locationCapture,
        timeZoneProvider: widget.timeZoneProvider,
        regionResolver: widget.regionResolver,
        targetGateway: widget.targetGateway,
      ),
    );
    if (values == null || !mounted) {
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.contactJournal.correctContact(
        ContactCorrectionSubmission(
          contactId: contact.contactId,
          appUserId: widget.context.appUserId,
          workspaceId: widget.context.workspace.id,
          projectId: widget.context.project.id,
          deviceId: widget.deviceId,
          baseRevision: contact.revisionNumber,
          reason: values.reason,
          occurredAtUtc: values.occurredAtUtc,
          occurredTimeZone: values.occurredTimeZone,
          channel: values.channel,
          channelDetail: values.channelDetail,
          location: values.location,
          reachCount: values.reachCount,
          interestLevel: values.interestLevel,
          answers: values.answers,
          targetLinks: values.targetLinks,
        ),
      );
      await _load();
      _showMessage('contactCorrected');
    } on ContactValidationException catch (error) {
      _showMessage(error.code);
    } catch (_) {
      _showMessage('contactCorrectionFailed');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _void(ContactRecord contact) async {
    final text = AppStrings(widget.controller.localeCode);
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _VoidContactDialog(text: text),
    );
    if (reason == null || !mounted) {
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.contactJournal.voidContact(
        ContactVoidSubmission(
          contactId: contact.contactId,
          appUserId: widget.context.appUserId,
          workspaceId: widget.context.workspace.id,
          projectId: widget.context.project.id,
          deviceId: widget.deviceId,
          baseRevision: contact.revisionNumber,
          reason: reason,
        ),
      );
      await _load();
      _showMessage('contactWasVoided');
    } on ContactValidationException catch (error) {
      _showMessage(error.code);
    } catch (_) {
      _showMessage('contactVoidFailed');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _showMessage(String key) {
    if (!mounted) {
      return;
    }
    final text = AppStrings(widget.controller.localeCode);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(text.t(key))));
  }

  String _factSummary(AppStrings text, ContactRecord contact) => [
    '${text.t('revision')} ${contact.revisionNumber}',
    '${text.t('occurredAt')}：${contact.occurredAtUtc.toIso8601String()}',
    '${text.t('contactChannel')}：${contactChannelLabel(text, contact.channel)}',
    '${text.t('location')}：${_locationLabel(text, contact.location)}',
    '${text.t('reachCount')}：${contact.reachCount}',
    '${text.t('interestLevel')}：${contact.interestLevel}',
    '${text.t('contactTargetLinks')}：${contact.targetLinks.length}',
  ].join('\n');

  String _revisionFactSummary(AppStrings text, ContactRevision revision) => [
    '${text.t('occurredAt')}：${revision.occurredAtUtc.toIso8601String()}',
    '${text.t('contactChannel')}：${contactChannelLabel(text, revision.channel)}',
    '${text.t('reachCount')}：${revision.reachCount}',
    '${text.t('interestLevel')}：${revision.interestLevel}',
    '${text.t('contactTargetLinks')}：${revision.targetLinks.length}',
  ].join('\n');

  String _revisionTitle(AppStrings text, ContactRevision revision) =>
      switch (revision.kind) {
        ContactRevisionKind.submitted => text.t('revisionSubmitted'),
        ContactRevisionKind.corrected => text.t('revisionCorrected'),
        ContactRevisionKind.voided => text.t('revisionVoided'),
      };
}

final class _VoidContactDialog extends StatefulWidget {
  const _VoidContactDialog({required this.text});

  final AppStrings text;

  @override
  State<_VoidContactDialog> createState() => _VoidContactDialogState();
}

final class _VoidContactDialogState extends State<_VoidContactDialog> {
  final TextEditingController _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.text.t('voidContact')),
      content: TextField(
        key: const ValueKey('contact-void-reason'),
        controller: _reasonController,
        autofocus: true,
        decoration: InputDecoration(labelText: widget.text.t('revisionReason')),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.text.t('cancel')),
        ),
        FilledButton(
          key: const ValueKey('confirm-void-contact'),
          onPressed: () {
            final normalized = _reasonController.text.trim();
            if (normalized.isNotEmpty) {
              Navigator.of(context).pop(normalized);
            }
          },
          child: Text(widget.text.t('confirmVoidContact')),
        ),
      ],
    );
  }
}

final class _CorrectionDialog extends StatefulWidget {
  const _CorrectionDialog({
    required this.text,
    required this.contact,
    required this.locationCapture,
    required this.timeZoneProvider,
    required this.regionResolver,
    this.titleKey = 'correctContact',
    this.proposedAnswers,
    this.proposedTargetLinks,
    this.targetGateway,
  });

  final AppStrings text;
  final ContactRecord contact;
  final ContactLocationCapture locationCapture;
  final DeviceTimeZoneProvider timeZoneProvider;
  final ContactRegionResolver regionResolver;
  final String titleKey;
  final List<QuestionnaireAnswer>? proposedAnswers;
  final List<ContactTargetLink>? proposedTargetLinks;
  final PromotionTargetGateway? targetGateway;

  @override
  State<_CorrectionDialog> createState() => _CorrectionDialogState();
}

final class _CorrectionDialogState extends State<_CorrectionDialog> {
  late final TextEditingController _reasonController;
  late final TextEditingController _reachController;
  late final TextEditingController _channelDetailController;
  late DateTime _occurredAtUtc;
  late String _occurredTimeZone;
  late ContactChannel _channel;
  late ContactLocation _location;
  late int _interestLevel;
  late List<ContactTargetLink> _targetLinks;
  List<PromotionTargetProfile> _assignedTargets = const [];
  var _useProposedAnswers = false;
  var _useProposedTargetLinks = false;
  var _targetsLoading = false;
  var _targetsLoaded = false;
  var _targetLoadFailed = false;
  var _capturingLocation = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reasonController = TextEditingController();
    _reachController = TextEditingController(
      text: widget.contact.reachCount.toString(),
    );
    _channelDetailController = TextEditingController(
      text: widget.contact.channelDetail ?? '',
    );
    _occurredAtUtc = widget.contact.occurredAtUtc;
    _occurredTimeZone = widget.contact.occurredTimeZone;
    _channel = widget.contact.channel;
    _location = widget.contact.location;
    _interestLevel = widget.contact.interestLevel;
    _targetLinks = [...widget.contact.targetLinks];
    unawaited(_loadAssignedTargets());
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _reachController.dispose();
    _channelDetailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.text.t(widget.titleKey)),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const ValueKey('contact-correction-reason'),
                controller: _reasonController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: widget.text.t('revisionReason'),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(widget.text.t('occurredAt')),
                subtitle: Text(_occurredAtUtc.toIso8601String()),
                trailing: IconButton(
                  key: const ValueKey('edit-correction-occurred-at'),
                  onPressed: _editOccurredAt,
                  icon: const Icon(Icons.edit_calendar_outlined),
                ),
              ),
              DropdownButtonFormField<ContactChannel>(
                key: const ValueKey('contact-correction-channel'),
                initialValue: _channel,
                decoration: InputDecoration(
                  labelText: widget.text.t('contactChannel'),
                ),
                items: [
                  for (final channel in ContactChannel.values)
                    DropdownMenuItem(
                      value: channel,
                      child: Text(contactChannelLabel(widget.text, channel)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    _setChannel(value);
                  }
                },
              ),
              if (_channel == ContactChannel.otherDirect) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _channelDetailController,
                  decoration: InputDecoration(
                    labelText: widget.text.t('otherChannelDetail'),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                '${widget.text.t('location')}：${_locationLabel(widget.text, _location)}',
              ),
              if (_channel == ContactChannel.faceToFace ||
                  _channel == ContactChannel.mixed)
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    key: const ValueKey('capture-correction-location'),
                    onPressed: _capturingLocation ? null : _captureLocation,
                    icon: _capturingLocation
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location_outlined),
                    label: Text(widget.text.t('captureContactLocation')),
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('contact-correction-reach'),
                controller: _reachController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: widget.text.t('reachCount'),
                ),
              ),
              const SizedBox(height: 12),
              Text(widget.text.t('singleContactInterest')),
              SegmentedButton<int>(
                segments: [
                  for (var level = 0; level <= 4; level++)
                    ButtonSegment(value: level, label: Text('$level')),
                ],
                selected: {_interestLevel},
                onSelectionChanged: (selection) {
                  setState(() => _interestLevel = selection.single);
                },
              ),
              if (widget.proposedTargetLinks != null) ...[
                const SizedBox(height: 12),
                Text(widget.text.t('contactTargetLinks')),
                SegmentedButton<bool>(
                  key: const ValueKey('conflict-target-link-source'),
                  segments: [
                    ButtonSegment(
                      value: false,
                      label: Text(widget.text.t('contactConflictCurrent')),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text(widget.text.t('contactConflictProposed')),
                    ),
                  ],
                  selected: {_useProposedTargetLinks},
                  onSelectionChanged: (selection) {
                    setState(() {
                      _useProposedTargetLinks = selection.single;
                      _targetLinks = [
                        ...(_useProposedTargetLinks
                            ? widget.proposedTargetLinks!
                            : widget.contact.targetLinks),
                      ];
                    });
                  },
                ),
              ],
              const SizedBox(height: 12),
              ContactTargetLinksEditor(
                text: widget.text,
                targetLinks: _targetLinks,
                assignedTargets: _assignedTargets,
                isLoading: _targetsLoading,
                loadFailed: _targetLoadFailed,
                hasLoaded: _targetsLoaded,
                onAdd: _addTarget,
                onRemove: _removeTarget,
                onResponseChanged: _setTargetResponse,
                onConsentChanged: _setTargetConsent,
                onRepresentativeChanged: _setTargetRepresentative,
                onRetry: _loadAssignedTargets,
              ),
              if (widget.proposedAnswers != null) ...[
                const SizedBox(height: 12),
                Text(widget.text.t('questionnaireAnswers')),
                SegmentedButton<bool>(
                  key: const ValueKey('conflict-answer-source'),
                  segments: [
                    ButtonSegment(
                      value: false,
                      label: Text(
                        widget.text.t('contactConflictCurrent'),
                        key: const ValueKey('use-current-answers'),
                      ),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text(
                        widget.text.t('contactConflictProposed'),
                        key: const ValueKey('use-proposed-answers'),
                      ),
                    ),
                  ],
                  selected: {_useProposedAnswers},
                  onSelectionChanged: (selection) {
                    setState(() => _useProposedAnswers = selection.single);
                  },
                ),
                const SizedBox(height: 6),
                Text(
                  _questionnaireAnswerSummary(
                    widget.text,
                    _useProposedAnswers
                        ? widget.proposedAnswers!
                        : widget.contact.answers,
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  widget.text.t(_error!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.text.t('cancel')),
        ),
        FilledButton(
          key: const ValueKey('confirm-contact-correction'),
          onPressed: _submit,
          child: Text(widget.text.t('saveCorrection')),
        ),
      ],
    );
  }

  void _setChannel(ContactChannel channel) {
    setState(() {
      _channel = channel;
      if (channel != ContactChannel.otherDirect) {
        _channelDetailController.clear();
      }
      if (_usesAutomaticNotApplicableLocation(channel)) {
        _location = const NotApplicableContactLocation();
      }
      _error = null;
    });
  }

  Future<void> _editOccurredAt() async {
    final local = _occurredAtUtc.toLocal();
    final date = await showDatePicker(
      context: context,
      initialDate: local,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) {
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(local),
    );
    if (time == null || !mounted) {
      return;
    }
    try {
      final timeZone = await widget.timeZoneProvider.currentIanaTimeZone();
      if (!mounted) {
        return;
      }
      setState(() {
        _occurredAtUtc = DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        ).toUtc();
        _occurredTimeZone = timeZone;
        _error = null;
      });
    } on DeviceTimeZoneException catch (error) {
      setState(() => _error = error.code);
    } catch (_) {
      setState(() => _error = 'device_time_zone_unavailable');
    }
  }

  Future<void> _captureLocation() async {
    setState(() {
      _capturingLocation = true;
      _error = null;
    });
    final snapshot = await widget.locationCapture.captureCurrentPosition();
    if (!mounted) {
      return;
    }
    if (!snapshot.hasPosition) {
      setState(() {
        _capturingLocation = false;
        _error = snapshot.error ?? 'location_unavailable';
      });
      return;
    }
    final pending = PendingContactLocation(
      latitude: snapshot.latitude!,
      longitude: snapshot.longitude!,
      accuracyMeters: snapshot.accuracyMeters,
    );
    ContactLocation location = pending;
    try {
      location = await widget.regionResolver.resolve(pending);
    } catch (_) {
      location = pending;
    }
    if (mounted) {
      setState(() {
        _capturingLocation = false;
        _location = location;
      });
    }
  }

  void _submit() {
    final reason = _reasonController.text.trim();
    final reachCount = int.tryParse(_reachController.text.trim());
    final channelDetail = _channelDetailController.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'contact_reason_required');
      return;
    }
    if (reachCount == null || reachCount < 1) {
      setState(() => _error = 'reach_count_must_be_positive');
      return;
    }
    if (_channel == ContactChannel.otherDirect && channelDetail.isEmpty) {
      setState(() => _error = 'other_channel_detail_required');
      return;
    }
    if (_channel == ContactChannel.faceToFace &&
        _location is NotApplicableContactLocation) {
      setState(() => _error = 'face_to_face_location_required');
      return;
    }
    Navigator.of(context).pop(
      _CorrectionValues(
        reason: reason,
        occurredAtUtc: _occurredAtUtc,
        occurredTimeZone: _occurredTimeZone,
        channel: _channel,
        channelDetail: channelDetail.isEmpty ? null : channelDetail,
        location: _location,
        reachCount: reachCount,
        interestLevel: _interestLevel,
        answers: _useProposedAnswers
            ? widget.proposedAnswers!
            : widget.contact.answers,
        targetLinks: List.unmodifiable(_targetLinks),
      ),
    );
  }

  Future<void> _loadAssignedTargets() async {
    final gateway = widget.targetGateway;
    if (gateway == null || _targetsLoading) return;
    setState(() {
      _targetsLoading = true;
      _targetLoadFailed = false;
    });
    PromotionTargetResult<List<PromotionTargetProfile>> result;
    try {
      result = await gateway.loadAssigned();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _targetsLoading = false;
        _targetLoadFailed = true;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _targetsLoading = false;
      _targetsLoaded = result is PromotionTargetSuccess;
      _targetLoadFailed =
          result is PromotionTargetRejected ||
          result is PromotionTargetConflict;
      _assignedTargets = switch (result) {
        PromotionTargetSuccess<List<PromotionTargetProfile>>(:final value) =>
          List.unmodifiable(value),
        PromotionTargetRejected<List<PromotionTargetProfile>>() => const [],
        PromotionTargetConflict<List<PromotionTargetProfile>>() => const [],
      };
    });
  }

  Future<void> _addTarget(PromotionTargetProfile target) async {
    var confirmed = false;
    if (!target.hasCurrentProjectRelationship) {
      confirmed =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(widget.text.t('confirmTargetProjectEntry')),
              content: Text(widget.text.t('confirmTargetProjectEntryHelp')),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(widget.text.t('cancel')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(widget.text.t('confirm')),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed || !mounted) return;
    }
    if (_targetLinks.any((link) => link.targetId == target.id)) return;
    setState(() {
      _targetLinks.add(
        ContactTargetLink(
          targetId: target.id,
          targetType: target.type,
          confirmStageZero: confirmed,
        ),
      );
    });
  }

  void _removeTarget(String targetId) {
    setState(() {
      _targetLinks.removeWhere((link) => link.targetId == targetId);
    });
  }

  void _setTargetResponse(String targetId, int? responseLevel) {
    _replaceTargetLink(targetId, (link) {
      if (link.targetType == PromotionTargetType.institution &&
          responseLevel != null &&
          !link.institutionRepresentativeConfirmed) {
        return link;
      }
      return ContactTargetLink(
        targetId: link.targetId,
        targetType: link.targetType,
        responseLevel: responseLevel,
        followUpConsent: link.followUpConsent,
        institutionRepresentativeConfirmed:
            link.institutionRepresentativeConfirmed,
        confirmStageZero: link.confirmStageZero,
      );
    });
  }

  void _setTargetConsent(String targetId, ContactFollowUpConsent consent) {
    _replaceTargetLink(
      targetId,
      (link) => ContactTargetLink(
        targetId: link.targetId,
        targetType: link.targetType,
        responseLevel: link.responseLevel,
        followUpConsent: consent,
        institutionRepresentativeConfirmed:
            link.institutionRepresentativeConfirmed,
        confirmStageZero: link.confirmStageZero,
      ),
    );
  }

  void _setTargetRepresentative(String targetId, bool confirmed) {
    _replaceTargetLink(
      targetId,
      (link) => ContactTargetLink(
        targetId: link.targetId,
        targetType: link.targetType,
        responseLevel: confirmed ? link.responseLevel : null,
        followUpConsent: link.followUpConsent,
        institutionRepresentativeConfirmed: confirmed,
        confirmStageZero: link.confirmStageZero,
      ),
    );
  }

  void _replaceTargetLink(
    String targetId,
    ContactTargetLink Function(ContactTargetLink link) replace,
  ) {
    final index = _targetLinks.indexWhere((link) => link.targetId == targetId);
    if (index < 0) return;
    setState(() => _targetLinks[index] = replace(_targetLinks[index]));
  }
}

final class _CorrectionValues {
  const _CorrectionValues({
    required this.reason,
    required this.occurredAtUtc,
    required this.occurredTimeZone,
    required this.channel,
    required this.channelDetail,
    required this.location,
    required this.reachCount,
    required this.interestLevel,
    required this.answers,
    required this.targetLinks,
  });

  final String reason;
  final DateTime occurredAtUtc;
  final String occurredTimeZone;
  final ContactChannel channel;
  final String? channelDetail;
  final ContactLocation location;
  final int reachCount;
  final int interestLevel;
  final List<QuestionnaireAnswer> answers;
  final List<ContactTargetLink> targetLinks;
}

bool _usesAutomaticNotApplicableLocation(ContactChannel channel) =>
    channel == ContactChannel.voiceCall ||
    channel == ContactChannel.videoCall ||
    channel == ContactChannel.instantText ||
    channel == ContactChannel.asynchronousMessage ||
    channel == ContactChannel.otherDirect ||
    channel == ContactChannel.mixed;

String _locationLabel(AppStrings text, ContactLocation location) =>
    switch (location) {
      NotApplicableContactLocation() => text.t('locationNotApplicable'),
      PendingContactLocation() => text.t('locationPendingResolution'),
      final ResolvedContactLocation resolved => resolved.placeName,
    };

String _questionnaireAnswerSummary(
  AppStrings text,
  List<QuestionnaireAnswer> answers,
) {
  if (answers.isEmpty) {
    return text.t('questionnaireAnswersEmpty');
  }
  final sorted = [...answers]
    ..sort((left, right) => left.questionId.compareTo(right.questionId));
  return sorted
      .map((answer) {
        final booleanAnswer = answer as BooleanQuestionnaireAnswer;
        final value = switch (booleanAnswer.state) {
          QuestionnaireAnswerState.answered =>
            booleanAnswer.value!
                ? text.t('questionnaireAnswerYes')
                : text.t('questionnaireAnswerNo'),
          QuestionnaireAnswerState.unknown => text.t(
            'questionnaireAnswerUnknown',
          ),
          QuestionnaireAnswerState.refused => text.t(
            'questionnaireAnswerRefused',
          ),
          QuestionnaireAnswerState.notApplicable => text.t(
            'questionnaireAnswerNotApplicable',
          ),
          QuestionnaireAnswerState.unanswered => text.t(
            'questionnaireAnswerUnanswered',
          ),
        };
        return '${booleanAnswer.questionId}: $value';
      })
      .join('，');
}
