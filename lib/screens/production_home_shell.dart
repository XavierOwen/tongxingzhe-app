import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app_session/app_session.dart';
import '../app_session/session_context_gateway.dart';
import '../features/contact_entry/contact_entry_screen.dart';
import '../features/contact_journal/contact_journal.dart';
import '../features/contact_journal/contact_models.dart';
import '../features/contact_metrics/personal_contact_overview.dart';
import '../l10n/app_strings.dart';
import '../services/location_service.dart';
import '../sync/foreground_sync_coordinator.dart';
import '../sync/sync_engine_factory.dart';

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
    required this.selectedIndex,
    required this.contactSubmissionEvents,
    required this.onDestinationSelected,
    required this.onOpenContactEntry,
  });

  final AppController controller;
  final AppSession appSession;
  final TrustedSessionContext context;
  final ContactJournal contactJournal;
  final String deviceId;
  final SyncEngineFactory? syncEngineFactory;
  final ContactLocationCapture locationCapture;
  final int selectedIndex;
  final ValueListenable<int> contactSubmissionEvents;
  final ValueChanged<int> onDestinationSelected;
  final ValueChanged<ContactDraft?> onOpenContactEntry;

  @override
  State<ProductionHomeShell> createState() => _ProductionHomeShellState();
}

final class _ProductionHomeShellState extends State<ProductionHomeShell>
    with WidgetsBindingObserver {
  late final ForegroundSyncCoordinator _syncCoordinator;
  late PersonalContactOverviewRepository _overviewRepository;
  late int _handledSubmissionEvent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _handledSubmissionEvent = widget.contactSubmissionEvents.value;
    widget.contactSubmissionEvents.addListener(_contactSubmitted);
    _syncCoordinator = ForegroundSyncCoordinator(worker: _createSyncWorker())
      ..addListener(_syncStateChanged);
    _overviewRepository = _createOverviewRepository();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_syncCoordinator.synchronize());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.contactSubmissionEvents.removeListener(_contactSubmitted);
    _syncCoordinator
      ..removeListener(_syncStateChanged)
      ..dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncCoordinator.synchronize());
    }
  }

  @override
  void didUpdateWidget(covariant ProductionHomeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contactSubmissionEvents != widget.contactSubmissionEvents) {
      oldWidget.contactSubmissionEvents.removeListener(_contactSubmitted);
      _handledSubmissionEvent = widget.contactSubmissionEvents.value;
      widget.contactSubmissionEvents.addListener(_contactSubmitted);
    }
    if (oldWidget.syncEngineFactory != widget.syncEngineFactory ||
        !_sameScope(oldWidget.context, widget.context)) {
      _syncCoordinator.replaceWorker(_createSyncWorker());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_syncCoordinator.synchronize());
      });
    }
    if (oldWidget.contactJournal != widget.contactJournal ||
        oldWidget.controller != widget.controller) {
      _overviewRepository = _createOverviewRepository();
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings(widget.controller.localeCode);
    final destinations = [
      _Destination(Icons.today_outlined, strings.t('today')),
      _Destination(Icons.forum_outlined, strings.t('navContacts')),
      _Destination(Icons.people_outline, strings.t('navTargets')),
      _Destination(Icons.insights_outlined, strings.t('navAnalysis')),
    ];
    final pages = [
      _PersonalSummaryPage(
        controller: widget.controller,
        context: widget.context,
        repository: _overviewRepository,
        period: PersonalSummaryPeriod.today,
      ),
      _ContactsPage(
        controller: widget.controller,
        context: widget.context,
        availableContexts: widget.appSession.current.availableContexts,
        repository: _overviewRepository,
        onOpenDraft: _openContactEntry,
        onAbandonDraft: _abandonDraft,
      ),
      _PlaceholderPage(
        icon: Icons.people_outline,
        title: strings.t('navTargets'),
        body: strings.t('targetsPending'),
      ),
      _PersonalSummaryPage(
        controller: widget.controller,
        context: widget.context,
        repository: _overviewRepository,
        period: PersonalSummaryPeriod.recentSevenDays,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.context.workspace.name} → ${widget.context.project.name}',
        ),
        actions: [
          PopupMenuButton<String>(
            key: const ValueKey('project-context-menu'),
            tooltip: strings.t('projectMenu'),
            onSelected: _handleProjectMenuSelection,
            itemBuilder: (context) => [
              for (final available
                  in widget.appSession.current.availableContexts)
                PopupMenuItem<String>(
                  value: available.project.id,
                  child: Row(
                    children: [
                      if (available.project.id == widget.context.project.id)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Icon(Icons.check, size: 18),
                        )
                      else
                        const SizedBox(width: 26),
                      Text(available.project.name),
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
            ],
            icon: const Icon(Icons.swap_horiz_outlined),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 900) {
            return Row(
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
            );
          }
          return pages[widget.selectedIndex];
        },
      ),
      floatingActionButton:
          widget.context.capabilities.contains('record_contact')
          ? FloatingActionButton.extended(
              onPressed: () => _openContactEntry(null),
              icon: const Icon(Icons.add_comment_outlined),
              label: Text(strings.t('recordContact')),
            )
          : null,
      bottomNavigationBar: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 900) {
            return const SizedBox.shrink();
          }
          return NavigationBar(
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
        },
      ),
    );
  }

  void _select(int index) {
    widget.onDestinationSelected(index);
  }

  Future<void> _openContactEntry(ContactDraft? draft) async {
    if (draft != null && draft.projectId != widget.context.project.id) {
      final result = await widget.appSession.selectProject(draft.projectId);
      if (result is SessionContextRejected) {
        if (mounted) {
          _showProjectFailure();
        }
        return;
      }
    }
    if (!mounted) {
      return;
    }
    widget.onOpenContactEntry(draft);
  }

  Future<void> _handleProjectMenuSelection(String value) async {
    if (value == _createProjectMenuValue) {
      await _createProject();
      return;
    }
    if (value == widget.context.project.id) {
      return;
    }
    final result = await widget.appSession.selectProject(value);
    if (result is SessionContextRejected && mounted) {
      _showProjectFailure();
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
    final result = await widget.appSession.createPersonalProject(name);
    if (result is SessionContextRejected && mounted) {
      _showProjectFailure();
    }
  }

  void _showProjectFailure() {
    final text = AppStrings(widget.controller.localeCode);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(text.t('projectChangeFailed'))));
  }

  void _contactSubmitted() {
    final event = widget.contactSubmissionEvents.value;
    if (event <= _handledSubmissionEvent) {
      return;
    }
    _handledSubmissionEvent = event;
    if (!mounted) {
      return;
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final text = AppStrings(widget.controller.localeCode);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(text.t('contactSubmitted'))));
      unawaited(_syncCoordinator.synchronize());
    });
  }

  Future<void> _abandonDraft(ContactDraft draft) async {
    final text = AppStrings(widget.controller.localeCode);
    try {
      await widget.contactJournal.abandonDraft(
        draftId: draft.draftId,
        appUserId: widget.context.appUserId,
        deviceId: widget.deviceId,
      );
      if (!mounted) {
        return;
      }
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(text.t('draftAbandoned')),
          duration: const Duration(seconds: 10),
          action: SnackBarAction(
            label: text.t('undo'),
            onPressed: () => unawaited(_undoAbandonDraft(draft)),
          ),
        ),
      );
      unawaited(_syncCoordinator.synchronize());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(text.t('draftAbandonFailed'))));
      }
    }
  }

  Future<void> _undoAbandonDraft(ContactDraft draft) async {
    final text = AppStrings(widget.controller.localeCode);
    try {
      await widget.contactJournal.undoAbandonDraft(
        draftId: draft.draftId,
        appUserId: widget.context.appUserId,
        deviceId: widget.deviceId,
      );
      if (mounted) {
        setState(() {});
        unawaited(_syncCoordinator.synchronize());
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(text.t('draftUndoFailed'))));
      }
    }
  }

  ForegroundSyncWorker? _createSyncWorker() {
    final engine = widget.syncEngineFactory?.create(widget.context);
    return engine == null ? null : SyncEngineForegroundWorker(engine);
  }

  PersonalContactOverviewRepository _createOverviewRepository() {
    return PersonalContactOverviewRepository(
      source: ContactJournalOverviewSource(widget.contactJournal),
      now: widget.controller.now,
      loadSyncHealth: _syncCoordinator.health,
    );
  }

  void _syncStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  bool _sameScope(TrustedSessionContext first, TrustedSessionContext second) {
    return first.appUserId == second.appUserId &&
        first.workspace.id == second.workspace.id &&
        first.project.id == second.project.id;
  }
}

const _createProjectMenuValue = '__create_personal_project__';

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
    required this.context,
    required this.repository,
    required this.period,
  });

  final AppController controller;
  final TrustedSessionContext context;
  final PersonalContactOverviewRepository repository;
  final PersonalSummaryPeriod period;

  @override
  Widget build(BuildContext context) {
    final text = AppStrings(controller.localeCode);
    return FutureBuilder<PersonalSummarySnapshot>(
      future: repository.loadSummary(context: this.context, period: period),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text(text.t('summaryLoadFailed')));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final result = snapshot.requireData;
        final summary = result.summary;
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
            if (period == PersonalSummaryPeriod.recentSevenDays) ...[
              const SizedBox(height: 8),
              Text(
                text.t('interestDistribution'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              for (var level = 0; level <= 4; level++)
                Text(
                  '${text.t('interestLevel')} $level：'
                  '${summary.interestDistribution[level]} '
                  '${text.t('contactSessionUnit')}',
                ),
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
            ],
          ],
        );
      },
    );
  }
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

final class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(body, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

final class _ContactsPage extends StatelessWidget {
  const _ContactsPage({
    required this.controller,
    required this.context,
    required this.availableContexts,
    required this.repository,
    required this.onOpenDraft,
    required this.onAbandonDraft,
  });

  final AppController controller;
  final TrustedSessionContext context;
  final List<TrustedSessionContext> availableContexts;
  final PersonalContactOverviewRepository repository;
  final ValueChanged<ContactDraft?> onOpenDraft;
  final ValueChanged<ContactDraft> onAbandonDraft;

  @override
  Widget build(BuildContext context) {
    final text = AppStrings(controller.localeCode);
    return FutureBuilder<ContactOverviewSnapshot>(
      future: repository.loadContacts(context: this.context),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final result = snapshot.requireData;
        final drafts = result.drafts;
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
            if (health != null && health.syncingCount > 0)
              Text('${text.t('syncing')} ${health.syncingCount}'),
            if (health != null && health.retryingCount > 0)
              Text('${text.t('retryingSync')} ${health.retryingCount}'),
            if (health != null && health.permanentFailureCount > 0)
              Text('${text.t('syncFailed')} ${health.permanentFailureCount}'),
            if (health != null && health.needsResolutionCount > 0)
              Text(
                '${text.t('syncNeedsResolution')} '
                '${health.needsResolutionCount}',
              ),
            if (health != null && health.completedCount > 0)
              Text('${text.t('synced')} ${health.completedCount}'),
            const SizedBox(height: 16),
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
      },
    );
  }

  String _draftDetails(AppStrings text, ContactDraft draft) {
    final contextsByProjectId = {
      for (final available in availableContexts)
        available.project.id: available,
    };
    final draftContext = contextsByProjectId[draft.projectId];
    final project = draftContext?.project.name ?? draft.projectId;
    final questionnaire =
        draftContext?.questionnaireVersion.id == draft.questionnaireVersionId
        ? draftContext!.questionnaireVersion.versionNumber.toString()
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
