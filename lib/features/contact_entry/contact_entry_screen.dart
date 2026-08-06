import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app_session/session_context_gateway.dart';
import '../../device/device_time_zone.dart';
import '../../foundation/runtime_values.dart';
import '../../l10n/app_strings.dart';
import '../../questionnaires/questionnaire_contract.dart';
import '../../questionnaires/questionnaire_draft_upgrade.dart';
import '../../regions/contact_region_resolver.dart';
import '../../services/location_service.dart';
import '../../targets/promotion_target.dart';
import '../contact_journal/contact_journal.dart';
import '../contact_journal/contact_models.dart';
import 'contact_channel_label.dart';
import 'contact_entry_view_model.dart';
import 'contact_target_links_editor.dart';
import 'questionnaire_form.dart';

typedef ContactDraftUpgradeAction =
    Future<ContactDraft> Function({
      required String sourceDraftId,
      required String appUserId,
      required String deviceId,
      required QuestionnaireVersion targetVersion,
      required List<QuestionnaireAnswer> copiedAnswers,
    });

/// 正式接触表单的首个渐进式切片。
///
/// Widget 只提交当前表单快照。草稿 ID、transaction 和创建时固定的归属由
/// [ContactJournal] 处理。
final class ContactEntryScreen extends StatefulWidget {
  const ContactEntryScreen({
    super.key,
    required this.controller,
    required this.clock,
    required this.context,
    required this.contactJournal,
    required this.deviceId,
    required this.locationCapture,
    required this.timeZoneProvider,
    this.initialDraft,
    this.entryStore,
    this.regionResolver = const DeferredContactRegionResolver(),
    this.sourceAttempt,
    this.questionnaireVersion,
    this.currentQuestionnaireVersion,
    this.auditedUpgradeCompatibilities = const [],
    this.upgradeDraft,
    this.targetGateway,
  });

  final AppController controller;
  final AppClock clock;
  final TrustedSessionContext context;
  final ContactJournal contactJournal;
  final String deviceId;
  final ContactLocationCapture locationCapture;
  final DeviceTimeZoneProvider timeZoneProvider;
  final ContactDraft? initialDraft;
  final ContactEntryStore? entryStore;
  final ContactRegionResolver regionResolver;
  final ContactAttempt? sourceAttempt;
  final QuestionnaireVersion? questionnaireVersion;
  final QuestionnaireVersion? currentQuestionnaireVersion;
  final List<AuditedQuestionnaireAnswerCompatibility>
  auditedUpgradeCompatibilities;
  final ContactDraftUpgradeAction? upgradeDraft;
  final PromotionTargetGateway? targetGateway;

  @override
  State<ContactEntryScreen> createState() => _ContactEntryScreenState();
}

final class _ContactEntryScreenState extends State<ContactEntryScreen>
    with WidgetsBindingObserver {
  late final TextEditingController _reachController;
  late final TextEditingController _channelDetailController;
  late final ContactEntryViewModel _viewModel;
  var _allowPop = false;
  var _showingQuestionnaireClearDialog = false;
  var _questionnaireFormGeneration = 0;
  var _isUpgradingQuestionnaire = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reachController = TextEditingController(
      text: widget.initialDraft?.reachCount?.toString() ?? '',
    );
    _channelDetailController = TextEditingController(
      text: widget.initialDraft?.channelDetail ?? '',
    );
    _viewModel = ContactEntryViewModel(
      clock: widget.clock,
      timeZoneProvider: widget.timeZoneProvider,
      context: widget.context,
      deviceId: widget.deviceId,
      store:
          widget.entryStore ?? ContactJournalEntryStore(widget.contactJournal),
      locationCapture: widget.locationCapture,
      regionResolver: widget.regionResolver,
      sourceAttemptId: widget.sourceAttempt?.attemptId,
      initialChannel: widget.sourceAttempt?.channel,
      questionnaireVersion: widget.questionnaireVersion,
      targetGateway: widget.targetGateway,
    )..addListener(_onViewStateChanged);
    unawaited(_viewModel.initialize(draft: widget.initialDraft));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _viewModel
      ..removeListener(_onViewStateChanged)
      ..dispose();
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
      unawaited(_viewModel.flushDraft());
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = AppStrings(widget.controller.localeCode);
    final entryState = _viewModel.state;
    if (!entryState.isReady) {
      return Scaffold(
        appBar: AppBar(title: Text(text.t('recordContact'))),
        body: Center(
          child: entryState.initializationFailure == null
              ? const CircularProgressIndicator()
              : Text(text.t(entryState.initializationFailure!)),
        ),
      );
    }
    return PopScope<bool>(
      canPop: _allowPop || !entryState.hasUnsavedChanges,
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
        appBar: AppBar(title: Text(text.t('recordContact'))),
        body: ListView(
          // 固定提交栏会覆盖 Scaffold 底部区域；额外留白让最后一个输入控件
          // 可以完整滚到提交栏上方，在小屏幕和键盘弹出时仍可操作。
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          children: [
            _ContextCard(
              context: widget.context,
              text: text,
              questionnaireVersion: entryState.questionnaireVersion,
            ),
            if (widget.initialDraft != null &&
                entryState.questionnaireVersion?.id !=
                    widget.context.questionnaireVersion.id) ...[
              const SizedBox(height: 12),
              Card(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                child: ListTile(
                  key: const ValueKey('old-questionnaire-version'),
                  leading: const Icon(Icons.history_outlined),
                  title: Text(text.t('draftUsesOldQuestionnaire')),
                  subtitle: Text(text.t('draftUsesOldQuestionnaireHelp')),
                  trailing:
                      widget.currentQuestionnaireVersion == null ||
                          entryState.isConflictCopy
                      ? null
                      : FilledButton.tonal(
                          key: const ValueKey('preview-questionnaire-upgrade'),
                          onPressed: _isUpgradingQuestionnaire
                              ? null
                              : _previewQuestionnaireUpgrade,
                          child: Text(text.t('questionnaireUpgradePreview')),
                        ),
                ),
              ),
            ],
            if (entryState.sourceAttemptId != null) ...[
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.reply_outlined),
                  title: Text(text.t('contactFromAttempt')),
                  subtitle: Text(text.t('contactFromAttemptHelp')),
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (entryState.isConflictCopy)
              _ConflictDraftCard(text: text)
            else
              SegmentedButton<ContactDraftSyncMode>(
                key: const ValueKey('draft-sync-mode'),
                segments: [
                  ButtonSegment(
                    value: ContactDraftSyncMode.accountPrivate,
                    icon: const Icon(Icons.devices_outlined),
                    label: Text(text.t('draftSyncAccountPrivate')),
                  ),
                  ButtonSegment(
                    value: ContactDraftSyncMode.deviceOnly,
                    icon: const Icon(Icons.phone_iphone_outlined),
                    label: Text(text.t('draftSyncDeviceOnly')),
                  ),
                ],
                selected: {entryState.syncMode},
                onSelectionChanged: (selection) {
                  _viewModel.setSyncMode(selection.single);
                },
              ),
            const SizedBox(height: 6),
            Text(
              entryState.isConflictCopy
                  ? text.t('draftConflictHelp')
                  : entryState.syncMode == ContactDraftSyncMode.accountPrivate
                  ? text.t('draftSyncAccountPrivateHelp')
                  : text.t('draftSyncDeviceOnlyHelp'),
            ),
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
                    selected: entryState.channel == channel,
                    onSelected: (_) => _viewModel.setChannel(channel),
                  ),
              ],
            ),
            if (entryState.channel == ContactChannel.otherDirect) ...[
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('contact-channel-detail'),
                controller: _channelDetailController,
                decoration: InputDecoration(
                  labelText: text.t('otherChannelDetail'),
                  helperText: text.t('otherChannelDetailHelp'),
                  prefixIcon: const Icon(Icons.edit_outlined),
                ),
                onChanged: _viewModel.setChannelDetail,
              ),
            ],
            const SizedBox(height: 16),
            _FactRow(
              icon: Icons.schedule_outlined,
              label: text.t('occurredAt'),
              value: entryState.occurredAtUtc!.toIso8601String(),
              trailing: IconButton(
                key: const ValueKey('edit-occurred-at'),
                tooltip: text.t('editOccurredAt'),
                onPressed: _editOccurredAt,
                icon: const Icon(Icons.edit_calendar_outlined),
              ),
            ),
            const SizedBox(height: 8),
            _FactRow(
              icon: Icons.public_outlined,
              label: text.t('occurredTimeZone'),
              value: entryState.occurredTimeZone!,
            ),
            const SizedBox(height: 8),
            _FactRow(
              icon: Icons.place_outlined,
              label: text.t('location'),
              value: _locationLabel(text, entryState.location),
            ),
            if (entryState.channel == ContactChannel.faceToFace ||
                entryState.channel == ContactChannel.mixed) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: entryState.isCapturingLocation
                      ? null
                      : _captureLocation,
                  icon: entryState.isCapturingLocation
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location_outlined),
                  label: Text(
                    entryState.isCapturingLocation
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
              onChanged: _viewModel.setReachCountText,
            ),
            const SizedBox(height: 16),
            Text(text.t('singleContactInterest')),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: [
                for (var level = 0; level <= 4; level++)
                  ButtonSegment(value: level, label: Text('$level')),
              ],
              selected: entryState.interestLevel == null
                  ? const <int>{}
                  : {entryState.interestLevel!},
              emptySelectionAllowed: true,
              onSelectionChanged: (selection) {
                if (selection.isNotEmpty) {
                  _viewModel.setInterestLevel(selection.single);
                }
              },
            ),
            const SizedBox(height: 12),
            Text(
              '${entryState.completedCoreFactCount} / '
              '${entryState.requiredCoreFactCount}',
              textAlign: TextAlign.end,
            ),
            const SizedBox(height: 12),
            ContactTargetLinksEditor(
              text: text,
              targetLinks: entryState.targetLinks,
              assignedTargets: entryState.assignedTargets,
              isLoading:
                  entryState.targetLoadState == ContactTargetLoadState.loading,
              loadFailed:
                  entryState.targetLoadState == ContactTargetLoadState.failed,
              hasLoaded:
                  entryState.targetLoadState == ContactTargetLoadState.loaded,
              onAdd: _addTarget,
              onRemove: _viewModel.unlinkTarget,
              onResponseChanged: _viewModel.setTargetResponse,
              onConsentChanged: _viewModel.setTargetFollowUpConsent,
              onRepresentativeChanged:
                  _viewModel.setInstitutionRepresentativeConfirmed,
              onRetry: _viewModel.loadAssignedTargets,
            ),
            if (entryState.questionnaireVersion case final version?) ...[
              const SizedBox(height: 24),
              QuestionnaireForm(
                key: ValueKey(_questionnaireFormGeneration),
                text: text,
                version: version,
                answers: entryState.answers,
                errors: entryState.questionnaireEvaluation.errors,
                visibleQuestionIds:
                    entryState.questionnaireEvaluation.visibleQuestionIds,
                onValueChanged: (question, value) {
                  if (_viewModel.setQuestionnaireValue(question, value)) {
                    unawaited(_confirmQuestionnaireClear());
                  }
                },
                onStateChanged: (question, answerState) {
                  if (_viewModel.setQuestionnaireState(question, answerState)) {
                    unawaited(_confirmQuestionnaireClear());
                  }
                },
              ),
              Text(
                '${text.t('questionnaireCompletion')}：'
                '${entryState.completedQuestionCount} / '
                '${entryState.questionCount}',
                textAlign: TextAlign.end,
              ),
            ],
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Icon(_saveIcon(entryState.saveState), size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(_saveLabel(text, entryState.saveState))),
                if (entryState.saveState == ContactDraftSaveState.failed)
                  IconButton(
                    key: const ValueKey('retry-draft-save'),
                    tooltip: text.t('retry'),
                    onPressed: () => unawaited(_viewModel.retrySave()),
                    icon: const Icon(Icons.refresh_outlined),
                  ),
                FilledButton(
                  onPressed: entryState.canSubmit ? _submit : null,
                  child: entryState.isSubmitting
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

  Future<void> _addTarget(PromotionTargetProfile target) async {
    var confirmed = false;
    if (!target.hasCurrentProjectRelationship) {
      confirmed =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(
                AppStrings(
                  widget.controller.localeCode,
                ).t('confirmTargetProjectEntry'),
              ),
              content: Text(
                AppStrings(
                  widget.controller.localeCode,
                ).t('confirmTargetProjectEntryHelp'),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(
                    AppStrings(widget.controller.localeCode).t('cancel'),
                  ),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(
                    AppStrings(widget.controller.localeCode).t('confirm'),
                  ),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed || !mounted) return;
    }
    _viewModel.linkTarget(target, confirmStageZero: confirmed);
  }

  IconData _saveIcon(ContactDraftSaveState state) => switch (state) {
    ContactDraftSaveState.untouched => Icons.edit_outlined,
    ContactDraftSaveState.waiting ||
    ContactDraftSaveState.saving => Icons.sync_outlined,
    ContactDraftSaveState.saved => Icons.cloud_done_outlined,
    ContactDraftSaveState.failed => Icons.error_outline,
  };

  String _saveLabel(AppStrings text, ContactDraftSaveState state) {
    return switch (state) {
      ContactDraftSaveState.untouched => text.t('draftStartsAfterInput'),
      ContactDraftSaveState.waiting ||
      ContactDraftSaveState.saving => text.t('saving'),
      ContactDraftSaveState.saved => text.t('saved'),
      ContactDraftSaveState.failed => text.t('draftSaveFailed'),
    };
  }

  void _onViewStateChanged() {
    if (mounted) {
      final detail = _viewModel.state.channelDetail;
      if (_channelDetailController.text != detail) {
        _channelDetailController.value = TextEditingValue(
          text: detail,
          selection: TextSelection.collapsed(offset: detail.length),
        );
      }
      setState(() {});
    }
  }

  Future<void> _editOccurredAt() async {
    final currentLocal = _viewModel.state.occurredAtUtc!.toLocal();
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: currentLocal,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (selectedDate == null || !mounted) {
      return;
    }
    final selectedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(currentLocal),
    );
    if (selectedTime == null || !mounted) {
      return;
    }
    _viewModel.setOccurredAtLocal(
      DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        selectedTime.hour,
        selectedTime.minute,
      ),
    );
  }

  Future<void> _captureLocation() async {
    final failureCode = await _viewModel.captureLocation();
    if (!mounted) {
      return;
    }
    if (failureCode != null) {
      final text = AppStrings(widget.controller.localeCode);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(text.t(failureCode))));
    }
  }

  Future<void> _confirmQuestionnaireClear() async {
    if (_showingQuestionnaireClearDialog || !mounted) {
      return;
    }
    _showingQuestionnaireClearDialog = true;
    final text = AppStrings(widget.controller.localeCode);
    final pending = _viewModel.state.pendingQuestionnaireAnswersToClear;
    final questions = {
      for (final question
          in widget.questionnaireVersion?.questions ??
              const <QuestionnaireQuestion>[])
        question.id: question,
    };
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(text.t('questionnaireClearTitle')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(text.t('questionnaireClearMessage')),
              const SizedBox(height: 8),
              for (final answer in pending)
                Text(
                  '• ${questions[answer.questionId]?.prompt ?? answer.questionId}',
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(text.t('cancel')),
          ),
          FilledButton(
            key: const ValueKey('confirm-questionnaire-clear'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(text.t('questionnaireClearConfirm')),
          ),
        ],
      ),
    );
    _showingQuestionnaireClearDialog = false;
    if (!mounted) {
      return;
    }
    if (confirmed != true) {
      _viewModel.cancelQuestionnaireClear();
      setState(() => _questionnaireFormGeneration++);
      return;
    }
    _viewModel.confirmQuestionnaireClear();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text.t('questionnaireAnswersCleared')),
        action: SnackBarAction(
          label: text.t('undo'),
          onPressed: () {
            _viewModel.undoQuestionnaireClear();
            setState(() => _questionnaireFormGeneration++);
          },
        ),
      ),
    );
  }

  Future<void> _previewQuestionnaireUpgrade() async {
    if (_isUpgradingQuestionnaire) {
      return;
    }
    setState(() => _isUpgradingQuestionnaire = true);
    await _viewModel.flushDraft();
    if (!mounted) {
      return;
    }
    final state = _viewModel.state;
    final sourceDraft = state.draft;
    final sourceVersion = state.questionnaireVersion;
    final targetVersion = widget.currentQuestionnaireVersion;
    final text = AppStrings(widget.controller.localeCode);
    if (sourceDraft == null ||
        sourceVersion == null ||
        targetVersion == null ||
        state.saveState == ContactDraftSaveState.failed) {
      setState(() => _isUpgradingQuestionnaire = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text.t('questionnaireUpgradeSaveFirstFailed'))),
      );
      return;
    }

    final QuestionnaireDraftUpgradePlan plan;
    try {
      plan = QuestionnaireDraftUpgradePlanner.plan(
        source: sourceVersion,
        target: targetVersion,
        sourceAnswers: sourceDraft.answers,
        compatibilities: widget.auditedUpgradeCompatibilities,
      );
    } on FormatException {
      setState(() => _isUpgradingQuestionnaire = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text.t('questionnaireUpgradeUnavailable'))),
      );
      return;
    }

    final sourceQuestions = {
      for (final question in sourceVersion.questions) question.id: question,
    };
    final targetQuestions = {
      for (final question in targetVersion.questions) question.id: question,
    };
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(text.t('questionnaireUpgradeTitle')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(text.t('questionnaireUpgradeKeepsOriginal')),
              const SizedBox(height: 16),
              _UpgradePlanSection(
                title: text.t('questionnaireUpgradeRetained'),
                emptyLabel: text.t('questionnaireUpgradeNoneRetained'),
                items: [
                  for (final retained in plan.retained)
                    '${sourceQuestions[retained.sourceQuestionId]?.prompt ?? retained.sourceQuestionId} → '
                        '${targetQuestions[retained.targetQuestionId]?.prompt ?? retained.targetQuestionId}',
                ],
              ),
              const SizedBox(height: 12),
              _UpgradePlanSection(
                title: text.t('questionnaireUpgradeRequiresConfirmation'),
                items: [
                  for (final id in plan.requiresConfirmationQuestionIds)
                    targetQuestions[id]?.prompt ?? id,
                ],
              ),
              const SizedBox(height: 12),
              _UpgradePlanSection(
                title: text.t('questionnaireUpgradeCannotCopy'),
                items: [
                  for (final id in plan.cannotCopySourceQuestionIds)
                    sourceQuestions[id]?.prompt ?? id,
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(text.t('cancel')),
          ),
          FilledButton(
            key: const ValueKey('confirm-questionnaire-upgrade'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(text.t('questionnaireUpgradeCreateDraft')),
          ),
        ],
      ),
    );
    if (!mounted) {
      return;
    }
    if (confirmed != true) {
      setState(() => _isUpgradingQuestionnaire = false);
      return;
    }

    try {
      final action = widget.upgradeDraft ?? widget.contactJournal.upgradeDraft;
      await action(
        sourceDraftId: sourceDraft.draftId,
        appUserId: sourceDraft.appUserId,
        deviceId: widget.deviceId,
        targetVersion: targetVersion,
        copiedAnswers: plan.copiedAnswers,
      );
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(text.t('questionnaireUpgradeCreated')),
          content: Text(text.t('questionnaireUpgradeCreatedHelp')),
          actions: [
            FilledButton(
              key: const ValueKey('finish-questionnaire-upgrade'),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(text.t('questionnaireUpgradeBackToDrafts')),
            ),
          ],
        ),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _isUpgradingQuestionnaire = false;
        _allowPop = true;
      });
      Navigator.of(context).pop(false);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _isUpgradingQuestionnaire = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text.t('questionnaireUpgradeFailed'))),
      );
    }
  }

  String _locationLabel(AppStrings text, ContactLocation? location) {
    return switch (location) {
      NotApplicableContactLocation() => text.t('locationNotApplicable'),
      final PendingContactLocation pending =>
        '${pending.latitude.toStringAsFixed(6)}, '
            '${pending.longitude.toStringAsFixed(6)}'
            '${pending.accuracyMeters == null ? '' : '\n${text.t('locationAccuracy')} ${pending.accuracyMeters!.toStringAsFixed(1)} m'}'
            '\n${text.t('locationPendingResolution')}',
      final ResolvedContactLocation resolved => resolved.placeName,
      null => text.t('locationRequired'),
    };
  }

  Future<void> _onPopInvoked(bool didPop, bool? result) async {
    if (didPop || _allowPop) {
      return;
    }
    final canLeave = await _viewModel.canLeaveAfterSave();
    if (!mounted || !canLeave) {
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
    final submitted = await _viewModel.submit();
    if (!mounted) {
      return;
    }
    if (submitted) {
      Navigator.of(context).pop(true);
      return;
    }
    final text = AppStrings(widget.controller.localeCode);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(text.t('contactSubmissionFailed'))));
  }
}

final class _UpgradePlanSection extends StatelessWidget {
  const _UpgradePlanSection({
    required this.title,
    required this.items,
    this.emptyLabel,
  });

  final String title;
  final List<String> items;
  final String? emptyLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        if (items.isEmpty)
          Text(emptyLabel ?? '—')
        else
          for (final item in items) Text('• $item'),
      ],
    );
  }
}

final class _ConflictDraftCard extends StatelessWidget {
  const _ConflictDraftCard({required this.text});

  final AppStrings text;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: ListTile(
        leading: const Icon(Icons.call_split_outlined),
        title: Text(text.t('draftConflictCopy')),
      ),
    );
  }
}

final class _ContextCard extends StatelessWidget {
  const _ContextCard({
    required this.context,
    required this.text,
    required this.questionnaireVersion,
  });

  final TrustedSessionContext context;
  final AppStrings text;
  final QuestionnaireVersion? questionnaireVersion;

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
              '${questionnaireVersion?.versionNumber ?? this.context.questionnaireVersion.versionNumber}',
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
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text('$label：$value')),
        ?trailing,
      ],
    );
  }
}
