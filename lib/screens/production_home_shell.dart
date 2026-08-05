import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app_session/session_context_gateway.dart';
import '../features/contact_entry/contact_entry_screen.dart';
import '../features/contact_journal/contact_journal.dart';
import '../features/contact_journal/contact_models.dart';
import '../l10n/app_strings.dart';
import '../services/location_service.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_engine_factory.dart';
import '../sync/sync_models.dart';

/// 正式产品的四项主框架。
///
/// 这个 Widget 只接收 Backend 已验证的当前上下文。它不读取 external subject，
/// 也不从 legacy Controller 推导项目归属。
final class ProductionHomeShell extends StatefulWidget {
  const ProductionHomeShell({
    super.key,
    required this.controller,
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
  SyncEngine? _syncEngine;
  var _drainRunning = false;
  late int _handledSubmissionEvent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _handledSubmissionEvent = widget.contactSubmissionEvents.value;
    widget.contactSubmissionEvents.addListener(_contactSubmitted);
    _syncEngine = widget.syncEngineFactory?.create(widget.context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_drainAvailableCommands());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.contactSubmissionEvents.removeListener(_contactSubmitted);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_drainAvailableCommands());
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
      _syncEngine = widget.syncEngineFactory?.create(widget.context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_drainAvailableCommands());
      });
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
        contactJournal: widget.contactJournal,
        period: _SummaryPeriod.today,
      ),
      _ContactsPage(
        controller: widget.controller,
        context: widget.context,
        contactJournal: widget.contactJournal,
        syncEngine: _syncEngine,
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
        contactJournal: widget.contactJournal,
        period: _SummaryPeriod.recentSevenDays,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.context.workspace.name} → ${widget.context.project.name}',
        ),
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

  void _openContactEntry(ContactDraft? draft) {
    widget.onOpenContactEntry(draft);
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
      unawaited(_drainAvailableCommands());
    });
  }

  Future<void> _abandonDraft(ContactDraft draft) async {
    final text = AppStrings(widget.controller.localeCode);
    try {
      await widget.contactJournal.abandonDraft(
        draftId: draft.draftId,
        appUserId: widget.context.appUserId,
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
      );
      if (mounted) {
        setState(() {});
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(text.t('draftUndoFailed'))));
      }
    }
  }

  Future<void> _drainAvailableCommands() async {
    final engine = _syncEngine;
    if (engine == null || _drainRunning) {
      return;
    }
    _drainRunning = true;
    try {
      for (var sent = 0; sent < 20; sent++) {
        final result = await engine.drainOnce();
        if (mounted) {
          setState(() {});
        }
        if (result != SyncDrainResult.completed) {
          break;
        }
      }
      for (var received = 0; received < 20; received++) {
        final result = await engine.pullOnce();
        if (mounted) {
          setState(() {});
        }
        if (result != SyncPullApplyResult.applied) {
          break;
        }
      }
    } finally {
      _drainRunning = false;
    }
  }

  bool _sameScope(TrustedSessionContext first, TrustedSessionContext second) {
    return first.appUserId == second.appUserId &&
        first.workspace.id == second.workspace.id &&
        first.project.id == second.project.id;
  }
}

enum _SummaryPeriod { today, recentSevenDays }

/// 从同一份已提交接触事实生成“今日”和最近七日的个人反馈。
///
/// 当前上下文尚未定义项目报告时区，因此边界明确使用 UTC 自然日。以后加入
/// 项目时区时，只需替换 [_periodBounds]，页面不接触 Drift 或 SQL。
final class _PersonalSummaryPage extends StatelessWidget {
  const _PersonalSummaryPage({
    required this.controller,
    required this.context,
    required this.contactJournal,
    required this.period,
  });

  final AppController controller;
  final TrustedSessionContext context;
  final ContactJournal contactJournal;
  final _SummaryPeriod period;

  @override
  Widget build(BuildContext context) {
    final text = AppStrings(controller.localeCode);
    final bounds = _periodBounds(controller.now().toUtc());
    return FutureBuilder<PersonalContactSummary>(
      future: contactJournal.summarizePersonalContacts(
        appUserId: this.context.appUserId,
        workspaceId: this.context.workspace.id,
        projectId: this.context.project.id,
        fromUtc: bounds.fromUtc,
        untilUtc: bounds.untilUtc,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text(text.t('summaryLoadFailed')));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final summary = snapshot.requireData;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              period == _SummaryPeriod.today
                  ? text.t('today')
                  : text.t('recentSevenDays'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(text.t('statisticsUseUtcDays')),
            const SizedBox(height: 16),
            _SummaryFactCard(
              icon: Icons.forum_outlined,
              label: period == _SummaryPeriod.today
                  ? text.t('todayContactSessions')
                  : text.t('sevenDayContactSessions'),
              value: summary.contactSessionCount,
            ),
            _SummaryFactCard(
              icon: Icons.groups_outlined,
              label: period == _SummaryPeriod.today
                  ? text.t('todayReachCount')
                  : text.t('sevenDayReachCount'),
              value: summary.reachCount,
            ),
            _SummaryFactCard(
              icon: Icons.sync_outlined,
              label: text.t('pendingSync'),
              value: summary.pendingSyncCount,
            ),
            if (period == _SummaryPeriod.recentSevenDays) ...[
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
                '${summary.contactSessionCount - summary.pendingSyncCount} / '
                '${summary.contactSessionCount}',
              ),
            ],
          ],
        );
      },
    );
  }

  _UtcPeriod _periodBounds(DateTime nowUtc) {
    final tomorrowUtc = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day + 1);
    final todayUtc = tomorrowUtc.subtract(const Duration(days: 1));
    return switch (period) {
      _SummaryPeriod.today => _UtcPeriod(todayUtc, tomorrowUtc),
      _SummaryPeriod.recentSevenDays => _UtcPeriod(
        todayUtc.subtract(const Duration(days: 6)),
        tomorrowUtc,
      ),
    };
  }
}

final class _UtcPeriod {
  const _UtcPeriod(this.fromUtc, this.untilUtc);

  final DateTime fromUtc;
  final DateTime untilUtc;
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
    required this.contactJournal,
    required this.syncEngine,
    required this.onOpenDraft,
    required this.onAbandonDraft,
  });

  final AppController controller;
  final TrustedSessionContext context;
  final ContactJournal contactJournal;
  final SyncEngine? syncEngine;
  final ValueChanged<ContactDraft?> onOpenDraft;
  final ValueChanged<ContactDraft> onAbandonDraft;

  @override
  Widget build(BuildContext context) {
    final text = AppStrings(controller.localeCode);
    return FutureBuilder<
      ({
        List<ContactDraft> drafts,
        PersonalContactSummary todaySummary,
        SyncHealth? syncHealth,
      })
    >(
      future: _loadContactPage(),
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
    final project = draft.projectId == context.project.id
        ? context.project.name
        : draft.projectId;
    final questionnaire =
        draft.questionnaireVersionId == context.questionnaireVersion.id
        ? context.questionnaireVersion.versionNumber.toString()
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

  Future<
    ({
      List<ContactDraft> drafts,
      PersonalContactSummary todaySummary,
      SyncHealth? syncHealth,
    })
  >
  _loadContactPage() async {
    final nowUtc = controller.now().toUtc();
    final untilUtc = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day + 1);
    final fromUtc = untilUtc.subtract(const Duration(days: 1));
    final drafts = await contactJournal.listDrafts(
      appUserId: context.appUserId,
    );
    final todaySummary = await contactJournal.summarizePersonalContacts(
      appUserId: context.appUserId,
      workspaceId: context.workspace.id,
      projectId: context.project.id,
      fromUtc: fromUtc,
      untilUtc: untilUtc,
    );
    final syncHealth = await syncEngine?.health();
    return (drafts: drafts, todaySummary: todaySummary, syncHealth: syncHealth);
  }
}
