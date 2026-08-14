import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app_session/app_session.dart';
import '../app_session/session_context_gateway.dart';
import '../device/device_time_zone.dart';
import '../foundation/runtime_values.dart';
import '../features/contact_attempt/contact_attempt_entry_screen.dart';
import '../features/contact_entry/contact_channel_label.dart';
import '../features/contact_journal/contact_journal.dart';
import '../features/contact_journal/contact_models.dart';
import '../features/contact_metrics/metric_contract.dart';
import '../features/contact_metrics/current_relationship_stage.dart';
import '../features/contact_metrics/current_relationship_stage_panel.dart';
import '../features/contact_metrics/personal_contact_overview.dart';
import '../features/contact_metrics/personal_follow_up_consent_ratio.dart';
import '../features/contact_metrics/personal_follow_up_consent_ratio_panel.dart';
import '../features/contact_metrics/personal_interest_ratio_trend_panel.dart';
import '../features/contact_metrics/relationship_stage_change_summary.dart';
import '../features/contact_metrics/relationship_stage_change_summary_panel.dart';
import '../features/home/production_home_view_model.dart';
import '../features/plans/personal_action_plan_panel.dart';
import '../features/project_settings/personal_follow_up_consent_opt_in_screen.dart';
import '../features/reminders/personal_action_reminder_panel.dart';
import '../features/questionnaire_admin/questionnaire_admin_screen.dart';
import '../features/targets/promotion_target_directory_page.dart';
import '../features/management_reports/management_report_browser.dart';
import '../l10n/app_strings.dart';
import '../management_reports/management_report_gateway.dart';
import '../management_reports/management_report_export_delivery.dart';
import '../plans/personal_action_plan.dart';
import '../project_settings/personal_follow_up_consent_opt_in.dart';
import '../reminders/personal_action_reminder.dart';
import '../questionnaires/questionnaire_administration.dart';
import '../routing/app_router.dart';
import '../services/location_service.dart';
import '../sync/sync_engine_factory.dart';
import '../targets/promotion_target.dart';

/// 正式产品的四项主框架。
///
/// 这个 Widget 只接收 Backend 已验证的当前上下文。它不读取 external subject，
/// 也不从 legacy Controller 推导项目归属。
final class ProductionHomeShell extends StatefulWidget {
  const ProductionHomeShell({
    super.key,
    required this.controller,
    required this.appSession,
    required this.context,
    required this.contactJournal,
    required this.deviceId,
    required this.syncEngineFactory,
    required this.locationCapture,
    required this.clock,
    required this.timeZoneProvider,
    required this.selectedIndex,
    required this.contactPageClosedEvents,
    required this.questionnaireAdministration,
    required this.promotionTargetGateway,
    required this.personalActionPlanGateway,
    required this.personalActionReminderGateway,
    required this.personalFollowUpConsentOptInGateway,
    required this.personalFollowUpConsentRatioGateway,
    required this.personalRelationshipStageChangeSummaryGateway,
    required this.managementReportGateway,
    required this.managementReportExportDelivery,
    required this.currentRelationshipStageRepository,
    required this.deviceReminderPreferenceStore,
    required this.reminderNotificationScheduler,
    required this.idGenerator,
    required this.onDestinationSelected,
    required this.onOpenContactEntry,
    required this.onOpenContactFromAttempt,
    required this.onOpenContactDetail,
  });

  final AppController controller;
  final AppSession appSession;
  final TrustedSessionContext context;
  final ContactJournal contactJournal;
  final String deviceId;
  final SyncEngineFactory? syncEngineFactory;
  final ContactLocationCapture locationCapture;
  final AppClock clock;
  final DeviceTimeZoneProvider timeZoneProvider;
  final int selectedIndex;
  final ValueListenable<ContactPageClosedEvent> contactPageClosedEvents;
  final QuestionnaireAdministrationGateway questionnaireAdministration;
  final PromotionTargetGateway promotionTargetGateway;
  final PersonalActionPlanGateway personalActionPlanGateway;
  final PersonalActionReminderGateway personalActionReminderGateway;
  final PersonalFollowUpConsentOptInGateway personalFollowUpConsentOptInGateway;
  final PersonalFollowUpConsentRatioGateway personalFollowUpConsentRatioGateway;
  final PersonalRelationshipStageChangeSummaryGateway
  personalRelationshipStageChangeSummaryGateway;
  final ManagementReportGateway managementReportGateway;
  final ManagementReportExportDelivery managementReportExportDelivery;
  final CurrentRelationshipStageRepository currentRelationshipStageRepository;
  final DeviceReminderPreferenceStore deviceReminderPreferenceStore;
  final ReminderNotificationScheduler reminderNotificationScheduler;
  final IdGenerator idGenerator;
  final ValueChanged<int> onDestinationSelected;
  final ValueChanged<ContactDraft?> onOpenContactEntry;
  final ValueChanged<ContactAttempt> onOpenContactFromAttempt;
  final ValueChanged<ContactRecord> onOpenContactDetail;

  @override
  State<ProductionHomeShell> createState() => _ProductionHomeShellState();
}

final class _ProductionHomeShellState extends State<ProductionHomeShell>
    with WidgetsBindingObserver {
  late ProductionHomeViewModel _viewModel;
  late int _handledContactPageEvent;
  var _handledNoticeId = 0;
  var _planningRevision = 0;
  var _personalAnalyticsRefreshRevision = 0;
  late bool _wasSynchronizing;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _handledContactPageEvent = widget.contactPageClosedEvents.value.sequence;
    widget.contactPageClosedEvents.addListener(_contactPageClosed);
    _viewModel = _createViewModel()..addListener(_viewStateChanged);
    _wasSynchronizing = _viewModel.state.isSynchronizing;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_viewModel.initialize());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.contactPageClosedEvents.removeListener(_contactPageClosed);
    _viewModel
      ..removeListener(_viewStateChanged)
      ..dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (mounted) {
        setState(() => _personalAnalyticsRefreshRevision++);
      }
      unawaited(_viewModel.appResumed());
    }
  }

  @override
  void didUpdateWidget(covariant ProductionHomeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contactPageClosedEvents != widget.contactPageClosedEvents) {
      oldWidget.contactPageClosedEvents.removeListener(_contactPageClosed);
      _handledContactPageEvent = widget.contactPageClosedEvents.value.sequence;
      widget.contactPageClosedEvents.addListener(_contactPageClosed);
    }
    if (oldWidget.syncEngineFactory != widget.syncEngineFactory ||
        oldWidget.contactJournal != widget.contactJournal ||
        oldWidget.controller != widget.controller ||
        oldWidget.appSession != widget.appSession ||
        oldWidget.deviceId != widget.deviceId ||
        oldWidget.currentRelationshipStageRepository !=
            widget.currentRelationshipStageRepository ||
        !_sameScope(oldWidget.context, widget.context)) {
      _viewModel
        ..removeListener(_viewStateChanged)
        ..dispose();
      _viewModel = _createViewModel()..addListener(_viewStateChanged);
      _wasSynchronizing = _viewModel.state.isSynchronizing;
      _handledNoticeId = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_viewModel.initialize());
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings(widget.controller.localeCode);
    final homeState = _viewModel.state;
    final recentSevenDaysPeriod = personalSummaryPeriodBounds(
      period: PersonalSummaryPeriod.recentSevenDays,
      now: widget.controller.now(),
    );
    final destinations = [
      _Destination(Icons.today_outlined, strings.t('today')),
      _Destination(Icons.forum_outlined, strings.t('navContacts')),
      _Destination(Icons.people_outline, strings.t('navTargets')),
      _Destination(Icons.insights_outlined, strings.t('navAnalysis')),
    ];
    final pages = [
      _PersonalSummaryPage(
        controller: widget.controller,
        period: PersonalSummaryPeriod.today,
        snapshot: homeState.today,
        isLoading: homeState.isLoading,
        loadFailed: homeState.loadFailed,
        personalPlanPanel: Column(
          children: [
            PersonalActionReminderPanel(
              key: ValueKey(
                'personal-reminder/'
                '${widget.context.appUserId}/'
                '${widget.context.workspace.id}/'
                '${widget.context.project.id}/'
                '${widget.deviceId}',
              ),
              text: strings,
              scope: DeviceReminderScope(
                appUserId: widget.context.appUserId,
                workspaceId: widget.context.workspace.id,
                projectId: widget.context.project.id,
                deviceId: widget.deviceId,
              ),
              gateway: widget.personalActionReminderGateway,
              planGateway: widget.personalActionPlanGateway,
              projectName: widget.context.project.name,
              preferenceStore: widget.deviceReminderPreferenceStore,
              scheduler: widget.reminderNotificationScheduler,
              timeZoneProvider: widget.timeZoneProvider,
              idGenerator: widget.idGenerator,
              planningRevision: _planningRevision,
            ),
            const SizedBox(height: 16),
            PersonalActionPlanPanel(
              text: strings,
              scopeKey:
                  '${widget.context.appUserId}/'
                  '${widget.context.workspace.id}/'
                  '${widget.context.project.id}',
              gateway: widget.personalActionPlanGateway,
              timeZoneProvider: widget.timeZoneProvider,
              idGenerator: widget.idGenerator,
              onPlanningStateChanged: _planningStateChanged,
            ),
          ],
        ),
        personalConsentRatioPanel: null,
        personalInterestRatioTrendPanel: null,
        currentRelationshipStagePanel: null,
        relationshipStageChangePanel: null,
      ),
      _ContactsPage(
        controller: widget.controller,
        projectOptions: homeState.projectOptions,
        snapshot: homeState.contacts,
        isLoading: homeState.isLoading,
        loadFailed: homeState.loadFailed,
        isSynchronizing: homeState.isSynchronizing,
        syncFailed: homeState.syncFailed,
        onOpenDraft: _openContactEntry,
        onAbandonDraft: (draft) => unawaited(_viewModel.abandonDraft(draft)),
        onRecordAttempt: _openContactAttemptEntry,
        onRecordResponse: widget.onOpenContactFromAttempt,
        onOpenContact: widget.onOpenContactDetail,
      ),
      PromotionTargetDirectoryPage(
        text: strings,
        gateway: widget.promotionTargetGateway,
        idGenerator: widget.idGenerator,
        clock: widget.clock,
        scopeKey: '${widget.context.workspace.id}/${widget.context.project.id}',
        canCreate: widget.context.capabilities.contains('create_target'),
        canConfigureStageAliases: widget.context.capabilities.contains(
          'manage_analysis_definitions',
        ),
        canManageRelationship: widget.context.capabilities.contains(
          'manage_assigned_target_follow_up',
        ),
        canManageInstitutionRelationships: widget.context.capabilities.contains(
          'manage_assigned_target_relations',
        ),
      ),
      _AnalysisPage(
        text: strings,
        personalSummary: _PersonalSummaryPage(
          controller: widget.controller,
          period: PersonalSummaryPeriod.recentSevenDays,
          snapshot: homeState.recentSevenDays,
          isLoading: homeState.isLoading,
          loadFailed: homeState.loadFailed,
          personalPlanPanel: null,
          personalInterestRatioTrendPanel:
              widget.context.workspace.kind == WorkspaceKind.personal
              ? PersonalInterestRatioTrendPanel(
                  text: strings,
                  comparison: homeState.interestRatioTrend,
                  isLoading: homeState.interestRatioTrendIsLoading,
                  loadFailed: homeState.interestRatioTrendLoadFailed,
                  onRetry: () =>
                      unawaited(_viewModel.retryInterestRatioTrend()),
                )
              : null,
          personalConsentRatioPanel:
              widget.context.workspace.kind == WorkspaceKind.personal &&
                  homeState.recentSevenDays != null
              ? PersonalFollowUpConsentRatioPanel(
                  key: ValueKey(
                    'personal-consent-ratio/'
                    '${widget.context.project.id}/'
                    '${homeState.recentSevenDays!.fromUtc.toIso8601String()}/'
                    '${homeState.recentSevenDays!.untilUtc.toIso8601String()}',
                  ),
                  text: strings,
                  gateway: widget.personalFollowUpConsentRatioGateway,
                  projectId: widget.context.project.id,
                  fromUtc: homeState.recentSevenDays!.fromUtc,
                  untilUtc: homeState.recentSevenDays!.untilUtc,
                  refreshRevision: _personalAnalyticsRefreshRevision,
                )
              : null,
          currentRelationshipStagePanel: CurrentRelationshipStagePanel(
            text: strings,
            result: homeState.currentRelationshipStage,
            isLoading: homeState.relationshipStageIsLoading,
            loadFailed: homeState.relationshipStageLoadFailed,
          ),
          relationshipStageChangePanel:
              widget.context.workspace.kind == WorkspaceKind.personal
              ? RelationshipStageChangeSummaryPanel(
                  key: ValueKey(
                    'relationship-stage-change/'
                    '${widget.context.project.id}/'
                    '${recentSevenDaysPeriod.fromUtc.toIso8601String()}/'
                    '${recentSevenDaysPeriod.untilUtc.toIso8601String()}',
                  ),
                  text: strings,
                  gateway: widget.personalRelationshipStageChangeSummaryGateway,
                  projectId: widget.context.project.id,
                  fromUtc: recentSevenDaysPeriod.fromUtc,
                  untilUtc: recentSevenDaysPeriod.untilUtc,
                  refreshRevision: _personalAnalyticsRefreshRevision,
                )
              : null,
        ),
        managementReports: ManagementReportBrowser(
          text: strings,
          gateway: widget.managementReportGateway,
          exportDelivery: widget.managementReportExportDelivery,
        ),
      ),
    ];

    final contextLabel =
        '${widget.context.workspace.name} → ${widget.context.project.name}';
    final appBarActions = [
      PopupMenuButton<String>(
        key: const ValueKey('project-context-menu'),
        tooltip: strings.t('projectMenu'),
        onSelected: _handleProjectMenuSelection,
        itemBuilder: (context) => [
          for (final option in homeState.projectOptions)
            PopupMenuItem<String>(
              value: option.id,
              child: Row(
                children: [
                  if (option.isSelected)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(Icons.check, size: 18),
                    )
                  else
                    const SizedBox(width: 26),
                  Text(option.name),
                ],
              ),
            ),
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            value: _createProjectMenuValue,
            child: Row(
              children: [
                const Icon(Icons.add, size: 18),
                const SizedBox(width: 8),
                Text(strings.t('createProject')),
              ],
            ),
          ),
          if (widget.context.workspace.kind == WorkspaceKind.personal) ...[
            const PopupMenuDivider(),
            PopupMenuItem<String>(
              key: const ValueKey('project-settings-menu-item'),
              value: _projectSettingsMenuValue,
              child: Row(
                children: [
                  const Icon(Icons.settings_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text(strings.t('projectSettings')),
                ],
              ),
            ),
          ],
          if (widget.context.capabilities.contains(
            questionnaireManagementCapability,
          )) ...[
            const PopupMenuDivider(),
            PopupMenuItem<String>(
              value: _manageQuestionnaireMenuValue,
              child: Row(
                children: [
                  const Icon(Icons.schema_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text(strings.t('questionnaireManage')),
                ],
              ),
            ),
          ],
        ],
        icon: const Icon(Icons.swap_horiz_outlined),
      ),
    ];
    final floatingActionButton =
        widget.context.capabilities.contains('record_contact')
        ? FloatingActionButton.extended(
            onPressed: () => _openContactEntry(null),
            icon: const Icon(Icons.add_comment_outlined),
            label: Text(strings.t('recordContact')),
          )
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return CompactProductionHomeScaffold(
            contextLabel: contextLabel,
            appBarActions: appBarActions,
            body: pages[widget.selectedIndex],
            floatingActionButton: floatingActionButton,
            selectedIndex: widget.selectedIndex,
            onDestinationSelected: _select,
            destinations: [
              for (final destination in destinations)
                NavigationDestination(
                  icon: Icon(destination.icon),
                  label: destination.label,
                ),
            ],
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: _ProductionContextTitle(label: contextLabel),
            actions: appBarActions,
          ),
          body: Row(
            children: [
              NavigationRail(
                selectedIndex: widget.selectedIndex,
                onDestinationSelected: _select,
                labelType: NavigationRailLabelType.all,
                destinations: [
                  for (final destination in destinations)
                    NavigationRailDestination(
                      icon: Icon(destination.icon),
                      label: Text(destination.label),
                    ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: pages[widget.selectedIndex]),
            ],
          ),
          floatingActionButton: floatingActionButton,
        );
      },
    );
  }

  void _select(int index) {
    widget.onDestinationSelected(index);
  }

  void _planningStateChanged() {
    if (!mounted) return;
    setState(() => _planningRevision++);
  }

  Future<void> _openContactEntry(ContactDraft? draft) async {
    if (draft != null && !await _viewModel.ensureDraftContext(draft)) {
      return;
    }
    if (!mounted) {
      return;
    }
    widget.onOpenContactEntry(draft);
  }

  Future<void> _openContactAttemptEntry() async {
    final recorded = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog.fullscreen(
        child: ContactAttemptEntryScreen(
          controller: widget.controller,
          clock: widget.clock,
          timeZoneProvider: widget.timeZoneProvider,
          context: widget.context,
          contactJournal: widget.contactJournal,
          deviceId: widget.deviceId,
        ),
      ),
    );
    if (recorded == true && mounted) {
      await _viewModel.contactAttemptRecorded();
    }
  }

  Future<void> _handleProjectMenuSelection(String value) async {
    if (value == _projectSettingsMenuValue) {
      await _openProjectSettings();
      return;
    }
    if (value == _manageQuestionnaireMenuValue) {
      await _manageQuestionnaire();
      return;
    }
    if (value == _createProjectMenuValue) {
      await _createProject();
      return;
    }
    await _viewModel.selectProject(value);
  }

  Future<void> _openProjectSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (routeContext) => PersonalFollowUpConsentOptInScreen(
          text: AppStrings(widget.controller.localeCode),
          projectId: widget.context.project.id,
          gateway: widget.personalFollowUpConsentOptInGateway,
          requestIdGenerator: SecureConsentOptInRequestIdGenerator(),
        ),
      ),
    );
    if (mounted) {
      setState(() => _personalAnalyticsRefreshRevision++);
    }
  }

  Future<void> _manageQuestionnaire() async {
    final published = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog.fullscreen(
        child: QuestionnaireAdminScreen(
          controller: widget.controller,
          gateway: widget.questionnaireAdministration,
          idGenerator: widget.idGenerator,
        ),
      ),
    );
    if (published == true && mounted) {
      await _viewModel.refreshCurrentProject();
    }
  }

  Future<void> _createProject() async {
    final text = AppStrings(widget.controller.localeCode);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _CreateProjectDialog(text: text),
    );
    if (name == null || !mounted) {
      return;
    }
    await _viewModel.createPersonalProject(name);
  }

  void _contactPageClosed() {
    final event = widget.contactPageClosedEvents.value;
    if (event.sequence <= _handledContactPageEvent) {
      return;
    }
    _handledContactPageEvent = event.sequence;
    if (!mounted) {
      return;
    }
    unawaited(_viewModel.contactPageClosed(submitted: event.submitted));
  }

  ProductionHomeViewModel _createViewModel() {
    return ProductionHomeViewModel.production(
      appSession: widget.appSession,
      context: widget.context,
      contactJournal: widget.contactJournal,
      deviceId: widget.deviceId,
      syncEngineFactory: widget.syncEngineFactory,
      relationshipStageRepository: widget.currentRelationshipStageRepository,
      now: widget.controller.now,
    );
  }

  void _viewStateChanged() {
    if (!mounted) {
      return;
    }
    final state = _viewModel.state;
    final synchronizationCompleted =
        _wasSynchronizing && !state.isSynchronizing;
    _wasSynchronizing = state.isSynchronizing;
    setState(() {
      if (synchronizationCompleted) {
        _personalAnalyticsRefreshRevision++;
      }
    });
    final notice = state.notice;
    if (notice == null || notice.id <= _handledNoticeId) {
      return;
    }
    _handledNoticeId = notice.id;
    WidgetsBinding.instance.addPostFrameCallback((_) => _showNotice(notice));
  }

  void _showNotice(ProductionHomeNotice notice) {
    if (!mounted) {
      return;
    }
    final text = AppStrings(widget.controller.localeCode);
    final messenger = ScaffoldMessenger.of(context);
    switch (notice.kind) {
      case ProductionHomeNoticeKind.contactSubmitted:
        messenger.showSnackBar(
          SnackBar(content: Text(text.t('contactSubmitted'))),
        );
      case ProductionHomeNoticeKind.contactAttemptRecorded:
        messenger.showSnackBar(
          SnackBar(content: Text(text.t('contactAttemptSaved'))),
        );
      case ProductionHomeNoticeKind.draftAbandoned:
        final draft = notice.draft;
        if (draft != null) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(text.t('draftAbandoned')),
              duration: const Duration(seconds: 10),
              action: SnackBarAction(
                label: text.t('undo'),
                onPressed: () => unawaited(_viewModel.undoAbandonDraft(draft)),
              ),
            ),
          );
        }
      case ProductionHomeNoticeKind.draftAbandonFailed:
        messenger.showSnackBar(
          SnackBar(content: Text(text.t('draftAbandonFailed'))),
        );
      case ProductionHomeNoticeKind.draftUndoFailed:
        messenger.showSnackBar(
          SnackBar(content: Text(text.t('draftUndoFailed'))),
        );
      case ProductionHomeNoticeKind.projectChangeFailed:
        messenger.showSnackBar(
          SnackBar(content: Text(text.t('projectChangeFailed'))),
        );
    }
    _viewModel.clearNotice(notice.id);
  }

  bool _sameScope(TrustedSessionContext first, TrustedSessionContext second) {
    return first.appUserId == second.appUserId &&
        first.workspace.id == second.workspace.id &&
        first.project.id == second.project.id;
  }
}

final class _AnalysisPage extends StatefulWidget {
  const _AnalysisPage({
    required this.text,
    required this.personalSummary,
    required this.managementReports,
  });

  final AppStrings text;
  final Widget personalSummary;
  final Widget managementReports;

  @override
  State<_AnalysisPage> createState() => _AnalysisPageState();
}

final class _AnalysisPageState extends State<_AnalysisPage> {
  var _showManagementReports = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  key: const ValueKey('personal-analysis-view'),
                  label: Text(widget.text.t('recentSevenDays')),
                  selected: !_showManagementReports,
                  onSelected: (_) => setState(() {
                    _showManagementReports = false;
                  }),
                ),
                ChoiceChip(
                  key: const ValueKey('management-report-view'),
                  label: Text(widget.text.t('managementReportTitle')),
                  selected: _showManagementReports,
                  onSelected: (_) => setState(() {
                    _showManagementReports = true;
                  }),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: _showManagementReports
              ? widget.managementReports
              : widget.personalSummary,
        ),
      ],
    );
  }
}

/// 小于 900 逻辑像素时使用的无业务逻辑外壳。
///
/// 独立组件让关键手机宽度可以直接验证 AppBar、页面、记录入口和底部导航的
/// 布局与焦点顺序，不需要在 Widget 测试中重建整套 session 与 gateway。
final class CompactProductionHomeScaffold extends StatelessWidget {
  const CompactProductionHomeScaffold({
    super.key,
    required this.contextLabel,
    required this.appBarActions,
    required this.body,
    required this.floatingActionButton,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  final String contextLabel;
  final List<Widget> appBarActions;
  final Widget body;
  final Widget? floatingActionButton;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationDestination> destinations;

  @override
  Widget build(BuildContext context) {
    final scaledLabelSize = MediaQuery.textScalerOf(context).scale(14);
    final extraNavigationHeight =
        (scaledLabelSize - 14).clamp(0, 14).toDouble() * 2;
    return FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: Scaffold(
        appBar: AppBar(
          title: _ProductionContextTitle(label: contextLabel),
          actions: appBarActions,
        ),
        body: body,
        floatingActionButton: floatingActionButton,
        bottomNavigationBar: NavigationBar(
          height: 80 + extraNavigationHeight,
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          destinations: destinations,
        ),
      ),
    );
  }
}

final class _ProductionContextTitle extends StatelessWidget {
  const _ProductionContextTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      header: true,
      label: label,
      excludeSemantics: true,
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

const _createProjectMenuValue = '__create_personal_project__';
const _manageQuestionnaireMenuValue = '__manage_questionnaire__';
const _projectSettingsMenuValue = '__project_settings__';

/// 对话框自行持有输入控制器，关闭动画结束后再随 State 一起释放。
final class _CreateProjectDialog extends StatefulWidget {
  const _CreateProjectDialog({required this.text});

  final AppStrings text;

  @override
  State<_CreateProjectDialog> createState() => _CreateProjectDialogState();
}

final class _CreateProjectDialogState extends State<_CreateProjectDialog> {
  final TextEditingController _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.text.t('createProject')),
      content: TextField(
        key: const ValueKey('new-project-name'),
        controller: _nameController,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(labelText: widget.text.t('projectName')),
        onSubmitted: _submit,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.text.t('cancel')),
        ),
        FilledButton(
          onPressed: () => _submit(_nameController.text),
          child: Text(widget.text.t('create')),
        ),
      ],
    );
  }

  void _submit(String value) {
    final normalized = value.trim();
    if (normalized.isNotEmpty) {
      Navigator.of(context).pop(normalized);
    }
  }
}

/// 从同一份已提交接触事实生成“今日”和最近七日的个人反馈。
///
/// 时间边界和同步覆盖由 [PersonalContactOverviewRepository] 统一计算；页面
/// 只把同一单位的结果显示出来。
final class _PersonalSummaryPage extends StatelessWidget {
  const _PersonalSummaryPage({
    required this.controller,
    required this.period,
    required this.snapshot,
    required this.isLoading,
    required this.loadFailed,
    required this.personalPlanPanel,
    required this.personalConsentRatioPanel,
    required this.personalInterestRatioTrendPanel,
    required this.currentRelationshipStagePanel,
    required this.relationshipStageChangePanel,
  });

  final AppController controller;
  final PersonalSummaryPeriod period;
  final PersonalSummarySnapshot? snapshot;
  final bool isLoading;
  final bool loadFailed;
  final Widget? personalPlanPanel;
  final Widget? personalConsentRatioPanel;
  final Widget? personalInterestRatioTrendPanel;
  final Widget? currentRelationshipStagePanel;
  final Widget? relationshipStageChangePanel;

  @override
  Widget build(BuildContext context) {
    final text = AppStrings(controller.localeCode);
    final result = snapshot;
    if (result == null) {
      final summaryStatus = isLoading && !loadFailed
          ? const Center(child: CircularProgressIndicator())
          : Center(child: Text(text.t('summaryLoadFailed')));
      final relationshipPanel = currentRelationshipStagePanel;
      final stageChangePanel = relationshipStageChangePanel;
      final trendPanel = personalInterestRatioTrendPanel;
      if (relationshipPanel == null &&
          stageChangePanel == null &&
          trendPanel == null) {
        return summaryStatus;
      }
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            text.t('recentSevenDays'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          summaryStatus,
          if (trendPanel != null) ...[const SizedBox(height: 16), trendPanel],
          if (relationshipPanel != null) ...[
            const SizedBox(height: 16),
            relationshipPanel,
          ],
          if (stageChangePanel != null) ...[
            const SizedBox(height: 16),
            stageChangePanel,
          ],
        ],
      );
    }
    final summary = result.summary;
    final interestOrdinalSummary =
        result.metric(CoreMetricCatalog.interestOrdinalSummary.reference).value
            as OrdinalSummaryMetricValue;
    final interestLevelRatios =
        result.metric(CoreMetricCatalog.interestLevelRatios.reference).value
            as RatioMetricValue;
    final interestRatioValues = interestLevelRatios.values;
    final interestThreeFourRatio =
        result.metric(CoreMetricCatalog.interestThreeFourRatio.reference).value
            as SubsetRatioMetricValue;
    final interestZeroRatio =
        result.metric(CoreMetricCatalog.interestZeroRatio.reference).value
            as SubsetRatioMetricValue;
    final targetResponseCount =
        result.metric(CoreMetricCatalog.targetResponses.reference).value
            as CountMetricValue;
    final targetResponseDistribution =
        result
                .metric(CoreMetricCatalog.targetResponseDistribution.reference)
                .value
            as TargetResponseDistributionMetricValue;
    final targetResponseOrdinalSummary =
        result
                .metric(
                  CoreMetricCatalog.targetResponseOrdinalSummary.reference,
                )
                .value
            as OrdinalSummaryMetricValue;
    final targetResponseLevelRatios =
        result
                .metric(CoreMetricCatalog.targetResponseLevelRatios.reference)
                .value
            as RatioMetricValue;
    final targetResponseRatioValues = targetResponseLevelRatios.values;
    final targetResponseMedianLevel = targetResponseOrdinalSummary.medianLevel;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          period == PersonalSummaryPeriod.today
              ? text.t('today')
              : text.t('recentSevenDays'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(text.t('statisticsUseUtcDays')),
        const SizedBox(height: 8),
        Text(text.t('personalAnalyticsFactNotice')),
        const SizedBox(height: 16),
        _SummaryFactCard(
          icon: Icons.forum_outlined,
          label: period == PersonalSummaryPeriod.today
              ? text.t('todayContactSessions')
              : text.t('sevenDayContactSessions'),
          value: summary.contactSessionCount,
        ),
        _SummaryFactCard(
          icon: Icons.groups_outlined,
          label: period == PersonalSummaryPeriod.today
              ? text.t('todayReachCount')
              : text.t('sevenDayReachCount'),
          value: summary.reachCount,
        ),
        _SummaryFactCard(
          icon: Icons.sync_outlined,
          label: text.t('pendingSync'),
          value: summary.pendingSyncCount,
        ),
        if (personalPlanPanel != null) ...[
          const SizedBox(height: 8),
          personalPlanPanel!,
          const SizedBox(height: 16),
        ],
        if (period == PersonalSummaryPeriod.recentSevenDays) ...[
          if (personalInterestRatioTrendPanel != null) ...[
            const SizedBox(height: 8),
            personalInterestRatioTrendPanel!,
            const SizedBox(height: 16),
          ],
          const SizedBox(height: 8),
          Semantics(
            header: true,
            child: Text(
              text.t('interestDistribution'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 8),
          for (var level = 0; level <= 4; level++)
            Text(
              text.format('interestRatioRow', {
                'level': level,
                'count': interestOrdinalSummary.counts[level],
                'unit': text.t('contactSessionUnit'),
                'numerator': interestRatioValues[level].numerator,
                'denominator': interestRatioValues[level].denominator,
                'percentage': _formatPercentageBasisPoints(
                  text,
                  interestRatioValues[level].percentageBasisPoints,
                ),
              }),
            ),
          const SizedBox(height: 16),
          Semantics(
            header: true,
            child: Text(
              text.t('interestSubsetRatios'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 8),
          _InterestSubsetRatioText(
            text: text,
            label: text.t('interestThreeFourRatio'),
            value: interestThreeFourRatio,
          ),
          _InterestSubsetRatioText(
            text: text,
            label: text.t('interestZeroRatio'),
            value: interestZeroRatio,
          ),
          const SizedBox(height: 8),
          Text(
            text.format('interestRatioCoverage', {
              'unknown': interestThreeFourRatio.unknownCount,
              'refused': interestThreeFourRatio.refusedCount,
              'notApplicable': interestThreeFourRatio.notApplicableCount,
              'unanswered': interestThreeFourRatio.unansweredCount,
              'excluded': interestThreeFourRatio.excludedCount,
            }),
          ),
          const SizedBox(height: 8),
          Text(
            interestOrdinalSummary.medianLevel == null
                ? text.t('noInterestMedianLevel')
                : '${text.t('interestMedianLevel')}：'
                      '${interestOrdinalSummary.medianLevel}',
          ),
          Text(text.t('interestMedianHelp')),
          const SizedBox(height: 16),
          Semantics(
            header: true,
            child: Text(
              text.t('targetResponseDistribution'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 8),
          Text(text.t('targetResponseDistributionHelp')),
          const SizedBox(height: 8),
          for (var level = 0; level <= 4; level++)
            Text(
              text.format('targetResponseRow', {
                'level': level,
                'count': targetResponseDistribution.counts[level],
                'numerator': targetResponseRatioValues[level].numerator,
                'denominator': targetResponseRatioValues[level].denominator,
                'percentage': _formatPercentageBasisPoints(
                  text,
                  targetResponseRatioValues[level].percentageBasisPoints,
                ),
              }),
            ),
          const SizedBox(height: 8),
          Text(
            text.format('targetResponseCoverage', {
              'answered': targetResponseCount.value,
              'unknown': targetResponseLevelRatios.unknownCount,
              'refused': targetResponseLevelRatios.refusedCount,
              'notApplicable': targetResponseLevelRatios.notApplicableCount,
              'unanswered': targetResponseLevelRatios.unansweredCount,
              'excluded': targetResponseLevelRatios.excludedCount,
            }),
          ),
          const SizedBox(height: 8),
          Text(
            targetResponseMedianLevel == null
                ? text.t('noTargetResponseMedianLevel')
                : text.format('targetResponseMedianLevel', {
                    'level': targetResponseMedianLevel,
                    'answered': targetResponseOrdinalSummary.totalCount,
                  }),
          ),
          Text(text.t('targetResponseMedianHelp')),
          const SizedBox(height: 16),
          Text(
            text.t('channelSources'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final channel in ContactChannel.values)
            if (summary.channelDistribution[channel.index] > 0)
              Text(
                '${contactChannelLabel(text, channel)}：'
                '${summary.channelDistribution[channel.index]} '
                '${text.t('contactSessionUnit')}',
              ),
          const SizedBox(height: 16),
          Text(
            summary.latestOccurredAtUtc == null
                ? text.t('noRecentContact')
                : '${text.t('latestContact')} '
                      '${summary.latestOccurredAtUtc!.toIso8601String()}',
          ),
          const SizedBox(height: 8),
          Text(
            '${text.t('syncCoverage')} '
            '${result.syncedContactSessionCount} / '
            '${result.syncCoverageDenominator}',
          ),
          if (currentRelationshipStagePanel != null) ...[
            const SizedBox(height: 16),
            currentRelationshipStagePanel!,
          ],
          if (relationshipStageChangePanel != null) ...[
            const SizedBox(height: 16),
            relationshipStageChangePanel!,
          ],
          if (personalConsentRatioPanel != null) ...[
            const SizedBox(height: 16),
            personalConsentRatioPanel!,
          ],
        ],
      ],
    );
  }
}

final class _InterestSubsetRatioText extends StatelessWidget {
  const _InterestSubsetRatioText({
    required this.text,
    required this.label,
    required this.value,
  });

  final AppStrings text;
  final String label;
  final SubsetRatioMetricValue value;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.format('interestSubsetRatioRow', {
        'label': label,
        'numerator': value.numerator,
        'denominator': value.denominator,
        'percentage': _formatPercentageBasisPoints(
          text,
          value.percentageBasisPoints,
        ),
      }),
    );
  }
}

String _formatPercentageBasisPoints(AppStrings text, int? basisPoints) {
  if (basisPoints == null) return text.t('interestRatioUnavailable');
  final whole = basisPoints ~/ 100;
  final fraction = (basisPoints % 100).toString().padLeft(2, '0');
  return '$whole.$fraction%';
}

final class _SummaryFactCard extends StatelessWidget {
  const _SummaryFactCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(leading: Icon(icon), title: Text('$label $value')),
    );
  }
}

final class _Destination {
  const _Destination(this.icon, this.label);

  final IconData icon;
  final String label;
}

final class _ContactsPage extends StatelessWidget {
  const _ContactsPage({
    required this.controller,
    required this.projectOptions,
    required this.snapshot,
    required this.isLoading,
    required this.loadFailed,
    required this.isSynchronizing,
    required this.syncFailed,
    required this.onOpenDraft,
    required this.onAbandonDraft,
    required this.onRecordAttempt,
    required this.onRecordResponse,
    required this.onOpenContact,
  });

  final AppController controller;
  final List<ProductionHomeProjectOption> projectOptions;
  final ContactOverviewSnapshot? snapshot;
  final bool isLoading;
  final bool loadFailed;
  final bool isSynchronizing;
  final bool syncFailed;
  final ValueChanged<ContactDraft?> onOpenDraft;
  final ValueChanged<ContactDraft> onAbandonDraft;
  final VoidCallback onRecordAttempt;
  final ValueChanged<ContactAttempt> onRecordResponse;
  final ValueChanged<ContactRecord> onOpenContact;

  @override
  Widget build(BuildContext context) {
    final text = AppStrings(controller.localeCode);
    final result = snapshot;
    if (result == null) {
      if (loadFailed) {
        return Center(child: Text(text.t('summaryLoadFailed')));
      }
      if (isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(child: Text(text.t('summaryLoadFailed')));
    }
    final drafts = result.drafts;
    final attempts = result.attempts;
    final contacts = result.contacts;
    final health = result.syncHealth;
    final onlyOnDevice =
        health?.onlyOnDeviceCount ?? result.todaySummary.pendingSyncCount;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '${text.t('todayContactSessions')} '
          '${result.todaySummary.contactSessionCount}',
        ),
        const SizedBox(height: 4),
        Text('${text.t('onlyOnThisDevice')} $onlyOnDevice'),
        if (isSynchronizing) Text(text.t('syncing')),
        if (syncFailed) Text(text.t('syncFailed')),
        if (health != null && health.syncingCount > 0)
          Text('${text.t('syncing')} ${health.syncingCount}'),
        if (health != null && health.retryingCount > 0)
          Text('${text.t('retryingSync')} ${health.retryingCount}'),
        if (health != null && health.permanentFailureCount > 0)
          Text(
            '${text.t('syncPermanentlyRejected')} '
            '${health.permanentFailureCount}',
          ),
        if (health != null && health.needsResolutionCount > 0)
          Text(
            '${text.t('syncNeedsResolution')} '
            '${health.needsResolutionCount}',
          ),
        if (health != null && health.completedCount > 0)
          Text('${text.t('synced')} ${health.completedCount}'),
        const SizedBox(height: 24),
        Text(
          '${text.t('submittedContacts')} (${contacts.length})',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(text.t('submittedContactsHelp')),
        const SizedBox(height: 12),
        if (contacts.isEmpty)
          Text(text.t('noSubmittedContacts'))
        else
          for (final contact in contacts)
            Card(
              child: ListTile(
                key: ValueKey('contact-record-${contact.contactId}'),
                leading: Icon(
                  contact.lifecycleStatus == ContactLifecycleStatus.active
                      ? Icons.forum_outlined
                      : Icons.block_outlined,
                ),
                title: Text(contactChannelLabel(text, contact.channel)),
                subtitle: Text(
                  '${contact.occurredAtUtc.toIso8601String()}\n'
                  '${text.t('reachCount')} ${contact.reachCount} · '
                  '${text.t('interestLevel')} ${contact.interestLevel} · '
                  '${text.t('revision')} ${contact.revisionNumber}',
                ),
                trailing:
                    contact.lifecycleStatus == ContactLifecycleStatus.voided
                    ? Text(text.t('contactVoided'))
                    : const Icon(Icons.chevron_right),
                onTap: () => onOpenContact(contact),
              ),
            ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                '${text.t('contactAttempts')} (${attempts.length})',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            OutlinedButton.icon(
              key: const ValueKey('record-contact-attempt'),
              onPressed: onRecordAttempt,
              icon: const Icon(Icons.phone_missed_outlined),
              label: Text(text.t('recordContactAttempt')),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(text.t('contactAttemptMetricsHelp')),
        const SizedBox(height: 12),
        if (attempts.isEmpty)
          Text(text.t('noContactAttempts'))
        else
          for (final attempt in attempts)
            Card(
              child: ListTile(
                leading: const Icon(Icons.phone_missed_outlined),
                title: Text(contactChannelLabel(text, attempt.channel)),
                subtitle: Text(
                  '${attempt.occurredAtUtc.toIso8601String()}\n'
                  '${text.t('attemptReachedNobody')}',
                ),
                trailing: attempt.linkedContactId == null
                    ? TextButton(
                        onPressed: () => onRecordResponse(attempt),
                        child: Text(text.t('recordResponseContact')),
                      )
                    : Text(text.t('attemptLinkedToContact')),
              ),
            ),
        const SizedBox(height: 24),
        Text(
          '${text.t('drafts')} (${drafts.length})',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        if (drafts.isEmpty)
          Text(text.t('noDrafts'))
        else
          for (final draft in drafts)
            Card(
              child: ListTile(
                leading: const Icon(Icons.edit_note_outlined),
                title: Text(
                  draft.channel == null
                      ? text.t('unfinishedDraft')
                      : contactChannelLabel(text, draft.channel!),
                ),
                subtitle: Text(_draftDetails(text, draft)),
                trailing: IconButton(
                  tooltip: text.t('abandonDraft'),
                  onPressed: () => onAbandonDraft(draft),
                  icon: const Icon(Icons.delete_outline),
                ),
                onTap: () => onOpenDraft(draft),
              ),
            ),
      ],
    );
  }

  String _draftDetails(AppStrings text, ContactDraft draft) {
    final optionsByProjectId = {
      for (final option in projectOptions) option.id: option,
    };
    final draftOption = optionsByProjectId[draft.projectId];
    final project = draftOption?.name ?? draft.projectId;
    final questionnaire =
        draftOption?.questionnaireVersionId == draft.questionnaireVersionId
        ? draftOption!.questionnaireVersionNumber.toString()
        : draft.questionnaireVersionId;
    return [
      '${text.t('draftProject')}：$project',
      '${text.t('draftOccurred')}：'
          '${draft.occurredAtUtc?.toUtc().toIso8601String() ?? text.t('draftNotSet')}',
      '${text.t('draftUpdated')}：'
          '${draft.updatedAtUtc.toUtc().toIso8601String()}',
      '${text.t('questionnaireVersion')}：$questionnaire',
      '${text.t('draftCompletion')}：'
          '${draft.completedCoreFactCount} / ${draft.requiredCoreFactCount}',
    ].join('\n');
  }
}
