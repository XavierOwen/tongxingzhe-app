import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app_session/session_context_gateway.dart';
import '../../l10n/app_strings.dart';
import '../../services/location_service.dart';
import '../contact_journal/contact_journal.dart';
import '../contact_journal/contact_models.dart';

/// 正式接触表单的首个渐进式切片。
///
/// Widget 只提交当前表单快照。草稿 ID、transaction 和创建时固定的归属由
/// [ContactJournal] 处理。
final class ContactEntryScreen extends StatefulWidget {
  const ContactEntryScreen({
    super.key,
    required this.controller,
    required this.context,
    required this.contactJournal,
    required this.deviceId,
    required this.locationCapture,
    this.initialDraft,
  });

  final AppController controller;
  final TrustedSessionContext context;
  final ContactJournal contactJournal;
  final String deviceId;
  final ContactLocationCapture locationCapture;
  final ContactDraft? initialDraft;

  @override
  State<ContactEntryScreen> createState() => _ContactEntryScreenState();
}

enum _DraftSaveState { untouched, waiting, saving, saved, failed }

final class _ContactEntryScreenState extends State<ContactEntryScreen>
    with WidgetsBindingObserver {
  static const _saveDelay = Duration(milliseconds: 350);

  Timer? _saveTimer;
  late final TextEditingController _reachController;
  late final TextEditingController _channelDetailController;
  ContactDraft? _draft;
  late DateTime _occurredAtUtc;
  late String _occurredTimeZone;
  ContactChannel? _channel;
  ContactLocation? _location;
  int? _reachCount;
  int? _interestLevel;
  Future<void>? _activeSave;
  var _editRevision = 0;
  var _savedRevision = 0;
  var _saveState = _DraftSaveState.untouched;
  var _submitting = false;
  var _capturingLocation = false;
  var _allowPop = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _draft = widget.initialDraft;
    _occurredAtUtc = _draft?.occurredAtUtc ?? widget.controller.now().toUtc();
    _occurredTimeZone = _draft?.occurredTimeZone ?? 'UTC';
    _channel = _draft?.channel;
    _location = _draft?.location;
    _reachCount = _draft?.reachCount;
    _interestLevel = _draft?.interestLevel;
    _reachController = TextEditingController(
      text: _reachCount?.toString() ?? '',
    );
    _channelDetailController = TextEditingController(
      text: _draft?.channelDetail ?? '',
    );
    if (_draft != null) {
      _saveState = _DraftSaveState.saved;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _reachController.dispose();
    _channelDetailController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_saveDraft());
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = AppStrings(widget.controller.localeCode);
    return PopScope<bool>(
      canPop: _allowPop || !_hasUnsavedChanges,
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
        appBar: AppBar(title: Text(text.t('recordContact'))),
        body: ListView(
          // 固定提交栏会覆盖 Scaffold 底部区域；额外留白让最后一个输入控件
          // 可以完整滚到提交栏上方，在小屏幕和键盘弹出时仍可操作。
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          children: [
            _ContextCard(context: widget.context, text: text),
            const SizedBox(height: 16),
            Text(
              text.t('coreContactFacts'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(text.t('chooseContactChannel')),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final channel in ContactChannel.values)
                  ChoiceChip(
                    label: Text(contactChannelLabel(text, channel)),
                    selected: _channel == channel,
                    onSelected: (_) => _setChannel(channel),
                  ),
              ],
            ),
            if (_channel == ContactChannel.otherDirect) ...[
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('contact-channel-detail'),
                controller: _channelDetailController,
                decoration: InputDecoration(
                  labelText: text.t('otherChannelDetail'),
                  helperText: text.t('otherChannelDetailHelp'),
                  prefixIcon: const Icon(Icons.edit_outlined),
                ),
                onChanged: (_) => _markEdited(),
              ),
            ],
            const SizedBox(height: 16),
            _FactRow(
              icon: Icons.schedule_outlined,
              label: text.t('occurredAt'),
              value: _occurredAtUtc.toIso8601String(),
            ),
            const SizedBox(height: 8),
            _FactRow(
              icon: Icons.public_outlined,
              label: text.t('occurredTimeZone'),
              value: _occurredTimeZone,
            ),
            const SizedBox(height: 8),
            _FactRow(
              icon: Icons.place_outlined,
              label: text.t('location'),
              value: _locationLabel(text),
            ),
            if (_channel == ContactChannel.faceToFace ||
                _channel == ContactChannel.mixed) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _capturingLocation ? null : _captureLocation,
                  icon: _capturingLocation
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location_outlined),
                  label: Text(
                    _capturingLocation
                        ? text.t('gettingLocation')
                        : text.t('captureContactLocation'),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('contact-reach-count'),
              controller: _reachController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: text.t('reachCount'),
                helperText: text.t('reachCountHelp'),
                prefixIcon: const Icon(Icons.groups_outlined),
              ),
              onChanged: _setReachCount,
            ),
            const SizedBox(height: 16),
            Text(text.t('singleContactInterest')),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: [
                for (var level = 0; level <= 4; level++)
                  ButtonSegment(value: level, label: Text('$level')),
              ],
              selected: _interestLevel == null
                  ? const <int>{}
                  : {_interestLevel!},
              emptySelectionAllowed: true,
              onSelectionChanged: (selection) {
                if (selection.isNotEmpty) {
                  _setInterestLevel(selection.single);
                }
              },
            ),
            const SizedBox(height: 12),
            Text(
              '${_draft?.completedCoreFactCount ?? 0} / '
              '${_draft?.requiredCoreFactCount ?? 5}',
              textAlign: TextAlign.end,
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Icon(_saveIcon, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(_saveLabel(text))),
                FilledButton(
                  onPressed: _canSubmit ? _submit : null,
                  child: _submitting
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(text.t('submitContact')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData get _saveIcon => switch (_saveState) {
    _DraftSaveState.untouched => Icons.edit_outlined,
    _DraftSaveState.waiting || _DraftSaveState.saving => Icons.sync_outlined,
    _DraftSaveState.saved => Icons.cloud_done_outlined,
    _DraftSaveState.failed => Icons.error_outline,
  };

  String _saveLabel(AppStrings text) {
    return switch (_saveState) {
      _DraftSaveState.untouched => text.t('draftStartsAfterInput'),
      _DraftSaveState.waiting || _DraftSaveState.saving => text.t('saving'),
      _DraftSaveState.saved => text.t('saved'),
      _DraftSaveState.failed => text.t('draftSaveFailed'),
    };
  }

  bool get _canSubmit =>
      !_submitting &&
      _saveState == _DraftSaveState.saved &&
      (_draft?.hasCompleteCoreFacts ?? false);

  bool get _hasUnsavedChanges => _editRevision > _savedRevision;

  void _setChannel(ContactChannel channel) {
    setState(() {
      _channel = channel;
      if (channel != ContactChannel.otherDirect) {
        _channelDetailController.clear();
      }
      if (_usesAutomaticNotApplicableLocation(channel)) {
        _location = const NotApplicableContactLocation();
      } else if (channel == ContactChannel.faceToFace &&
          _location is NotApplicableContactLocation) {
        _location = null;
      }
      _editRevision++;
      _saveState = _DraftSaveState.waiting;
    });
    _scheduleSave();
  }

  void _markEdited() {
    setState(() {
      _editRevision++;
      _saveState = _DraftSaveState.waiting;
    });
    _scheduleSave();
  }

  Future<void> _captureLocation() async {
    if (_capturingLocation) {
      return;
    }
    setState(() => _capturingLocation = true);
    final snapshot = await widget.locationCapture.captureCurrentPosition();
    if (!mounted) {
      return;
    }
    if (!snapshot.hasPosition) {
      setState(() => _capturingLocation = false);
      final code = snapshot.error ?? 'location_unavailable';
      final text = AppStrings(widget.controller.localeCode);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(text.t(code))));
      return;
    }
    setState(() {
      _location = PendingContactLocation(
        latitude: snapshot.latitude!,
        longitude: snapshot.longitude!,
        accuracyMeters: snapshot.accuracyMeters,
      );
      _capturingLocation = false;
      _editRevision++;
      _saveState = _DraftSaveState.waiting;
    });
    _scheduleSave();
  }

  String _locationLabel(AppStrings text) {
    return switch (_location) {
      NotApplicableContactLocation() => text.t('locationNotApplicable'),
      final PendingContactLocation pending =>
        '${pending.latitude.toStringAsFixed(6)}, '
            '${pending.longitude.toStringAsFixed(6)}'
            '${pending.accuracyMeters == null ? '' : '\n${text.t('locationAccuracy')} ${pending.accuracyMeters!.toStringAsFixed(1)} m'}',
      final ResolvedContactLocation resolved => resolved.placeName,
      null => text.t('locationRequired'),
    };
  }

  void _setReachCount(String value) {
    final parsed = int.tryParse(value.trim());
    setState(() {
      _reachCount = parsed != null && parsed > 0 ? parsed : null;
      _editRevision++;
      _saveState = _DraftSaveState.waiting;
    });
    _scheduleSave();
  }

  void _setInterestLevel(int value) {
    setState(() {
      _interestLevel = value;
      _editRevision++;
      _saveState = _DraftSaveState.waiting;
    });
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, () => unawaited(_saveDraft()));
  }

  Future<void> _saveDraft() {
    _saveTimer?.cancel();
    final active = _activeSave;
    if (active != null) {
      return active;
    }
    if (!_hasUnsavedChanges || !mounted) {
      return Future.value();
    }

    late final Future<void> operation;
    operation = _drainPendingSaves().whenComplete(() {
      if (identical(_activeSave, operation)) {
        _activeSave = null;
      }
    });
    _activeSave = operation;
    return operation;
  }

  Future<void> _drainPendingSaves() async {
    while (mounted && _hasUnsavedChanges) {
      final savingRevision = _editRevision;
      setState(() => _saveState = _DraftSaveState.saving);
      try {
        final saved = await widget.contactJournal.saveDraft(
          ContactDraftInput(
            draftId: _draft?.draftId,
            appUserId: widget.context.appUserId,
            workspaceId: widget.context.workspace.id,
            projectId: widget.context.project.id,
            questionnaireVersionId: widget.context.questionnaireVersion.id,
            occurredAtUtc: _occurredAtUtc,
            occurredTimeZone: _occurredTimeZone,
            channel: _channel,
            channelDetail: _channel == ContactChannel.otherDirect
                ? _channelDetailController.text.trim()
                : null,
            location: _location,
            reachCount: _reachCount,
            interestLevel: _interestLevel,
          ),
        );
        if (!mounted) {
          return;
        }
        setState(() {
          _draft = saved;
          _savedRevision = savingRevision;
          _saveState = _hasUnsavedChanges
              ? _DraftSaveState.waiting
              : _DraftSaveState.saved;
        });
      } catch (_) {
        if (mounted) {
          setState(() => _saveState = _DraftSaveState.failed);
        }
        return;
      }
    }
  }

  Future<void> _onPopInvoked(bool didPop, bool? result) async {
    if (didPop || _allowPop) {
      return;
    }
    await _saveDraft();
    if (!mounted || _hasUnsavedChanges) {
      return;
    }
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).pop(result);
      }
    });
  }

  Future<void> _submit() async {
    if (!_canSubmit) {
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.contactJournal.submitDraft(
        draftId: _draft!.draftId,
        appUserId: widget.context.appUserId,
        deviceId: widget.deviceId,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _submitting = false;
        _saveState = _DraftSaveState.failed;
      });
    }
  }

  bool _usesAutomaticNotApplicableLocation(ContactChannel channel) {
    return channel == ContactChannel.voiceCall ||
        channel == ContactChannel.videoCall ||
        channel == ContactChannel.instantText ||
        channel == ContactChannel.asynchronousMessage ||
        channel == ContactChannel.otherDirect ||
        channel == ContactChannel.mixed;
  }
}

final class _ContextCard extends StatelessWidget {
  const _ContextCard({required this.context, required this.text});

  final TrustedSessionContext context;
  final AppStrings text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${this.context.workspace.name} → ${this.context.project.name}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '${text.t('questionnaireVersion')} '
              '${this.context.questionnaireVersion.versionNumber}',
            ),
          ],
        ),
      ),
    );
  }
}

final class _FactRow extends StatelessWidget {
  const _FactRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text('$label：$value')),
      ],
    );
  }
}

String contactChannelLabel(AppStrings text, ContactChannel channel) {
  return switch (channel) {
    ContactChannel.faceToFace => text.t('channel.faceToFace'),
    ContactChannel.voiceCall => text.t('channel.voiceCall'),
    ContactChannel.videoCall => text.t('channel.videoCall'),
    ContactChannel.instantText => text.t('channel.instantText'),
    ContactChannel.asynchronousMessage => text.t('channel.asynchronousMessage'),
    ContactChannel.mixed => text.t('channel.mixed'),
    ContactChannel.otherDirect => text.t('channel.otherDirect'),
  };
}
