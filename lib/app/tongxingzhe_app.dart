import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../app_session/app_session.dart';
import '../app_session/session_context_gateway.dart';
import '../device/device_time_zone.dart';
import '../features/contact_journal/contact_journal.dart';
import '../features/contact_journal/contact_models.dart';
import '../features/contact_entry/contact_entry_screen.dart';
import '../features/contact_revision/contact_revision_screen.dart';
import '../foundation/runtime_values.dart';
import '../identity/identity_session.dart';
import '../l10n/app_strings.dart';
import '../questionnaires/questionnaire_contract.dart';
import '../questionnaires/questionnaire_administration.dart';
import '../regions/contact_region_resolver.dart';
import '../routing/app_route.dart';
import '../routing/app_router.dart';
import '../screens/auth_screen.dart';
import '../screens/home_shell.dart';
import '../screens/production_home_shell.dart';
import '../services/location_service.dart';
import '../sync/sync_engine_factory.dart';
import 'app_controller.dart';
import 'app_dependencies.dart';

typedef SignedOutScreenBuilder =
    Widget Function(BuildContext context, AppController controller);

class TongxingzheApp extends StatefulWidget {
  const TongxingzheApp({
    super.key,
    required this.dependencies,
    this.signedOutScreenBuilder,
    this.routeInformationProvider,
  });

  final AppDependencies dependencies;

  /// 只有 `main_demo.dart` 会注入 legacy 登录页；正式入口保持为 `null`。
  final SignedOutScreenBuilder? signedOutScreenBuilder;

  /// 正式运行时由 Flutter 连接系统 URL。测试可注入可控 provider
  /// 验证 deep link 和地址更新，不伪造业务上下文。
  final RouteInformationProvider? routeInformationProvider;

  @override
  State<TongxingzheApp> createState() => _TongxingzheAppState();
}

class _TongxingzheAppState extends State<TongxingzheApp> {
  late final Future<AppStartupResult> _startup;
  AppController? _controller;
  IdentitySession? _identitySession;
  AppSession? _appSession;
  SyncEngineFactory? _syncEngineFactory;
  ContactRegionResolver? _regionResolver;
  QuestionnaireCatalog? _questionnaireCatalog;
  QuestionnaireAdministrationGateway? _questionnaireAdministration;

  @override
  void initState() {
    super.initState();
    _startup = _start();
  }

  Future<AppStartupResult> _start() async {
    final result = await widget.dependencies.start();
    if (result case AppStartupReady(
      :final controller,
      :final identitySession,
      :final appSession,
      :final syncEngineFactory,
      :final regionResolver,
      :final questionnaireCatalog,
      :final questionnaireAdministration,
    )) {
      _controller = controller;
      _identitySession = identitySession;
      _appSession = appSession;
      _syncEngineFactory = syncEngineFactory;
      _regionResolver = regionResolver;
      _questionnaireCatalog = questionnaireCatalog;
      _questionnaireAdministration = questionnaireAdministration;
    }
    return result;
  }

  @override
  void dispose() {
    unawaited(_appSession?.close());
    unawaited(_identitySession?.close());
    unawaited(_syncEngineFactory?.close());
    unawaited(_regionResolver?.close());
    unawaited(_questionnaireCatalog?.close());
    unawaited(_questionnaireAdministration?.close());
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppStartupResult>(
      future: _startup,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(body: Center(child: CircularProgressIndicator())),
          );
        }

        return switch (snapshot.requireData) {
          AppStartupReady(
            :final controller,
            :final clock,
            :final contactJournal,
            :final deviceId,
            :final syncEngineFactory,
            :final identitySession,
            :final appSession,
            :final locationCapture,
            :final timeZoneProvider,
            :final regionResolver,
            :final questionnaireCatalog,
            :final questionnaireAdministration,
            :final idGenerator,
          ) =>
            _ReadyApp(
              controller: controller,
              clock: clock,
              contactJournal: contactJournal,
              deviceId: deviceId,
              syncEngineFactory: syncEngineFactory,
              identitySession: identitySession,
              appSession: appSession,
              locationCapture: locationCapture,
              timeZoneProvider: timeZoneProvider,
              regionResolver: regionResolver,
              questionnaireCatalog: questionnaireCatalog,
              questionnaireAdministration: questionnaireAdministration,
              idGenerator: idGenerator,
              signedOutScreenBuilder: widget.signedOutScreenBuilder,
              routeInformationProvider: widget.routeInformationProvider,
            ),
          AppStartupFailed(:final failure) => _StartupFailureApp(
            failure: failure,
          ),
        };
      },
    );
  }
}

class _ReadyApp extends StatefulWidget {
  const _ReadyApp({
    required this.controller,
    required this.clock,
    required this.contactJournal,
    required this.deviceId,
    required this.syncEngineFactory,
    required this.identitySession,
    required this.appSession,
    required this.locationCapture,
    required this.timeZoneProvider,
    required this.regionResolver,
    required this.questionnaireCatalog,
    required this.questionnaireAdministration,
    required this.idGenerator,
    required this.signedOutScreenBuilder,
    required this.routeInformationProvider,
  });

  final AppController controller;
  final AppClock clock;
  final ContactJournal contactJournal;
  final String deviceId;
  final SyncEngineFactory? syncEngineFactory;
  final IdentitySession identitySession;
  final AppSession appSession;
  final ContactLocationCapture locationCapture;
  final DeviceTimeZoneProvider timeZoneProvider;
  final ContactRegionResolver regionResolver;
  final QuestionnaireCatalog questionnaireCatalog;
  final QuestionnaireAdministrationGateway questionnaireAdministration;
  final IdGenerator idGenerator;
  final SignedOutScreenBuilder? signedOutScreenBuilder;
  final RouteInformationProvider? routeInformationProvider;

  @override
  State<_ReadyApp> createState() => _ReadyAppState();
}

final class _ReadyAppState extends State<_ReadyApp> {
  late final AppRouterDelegate _routerDelegate;

  @override
  void initState() {
    super.initState();
    _routerDelegate = AppRouterDelegate(
      rootBuilder: _buildRootRoute,
      contactBuilder: _buildContactRoute,
      contactDetailBuilder: _buildContactDetailRoute,
    );
  }

  @override
  void dispose() {
    _routerDelegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final locale = Locale(widget.controller.localeCode);
        final text = AppStrings(locale.languageCode);

        return MaterialApp.router(
          debugShowCheckedModeBanner: false,
          title: text.t('appTitle'),
          locale: locale,
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          themeMode: widget.controller.themeMode,
          theme: _theme(Brightness.light),
          darkTheme: _theme(Brightness.dark),
          routeInformationProvider: widget.routeInformationProvider,
          routeInformationParser: const AppRouteInformationParser(),
          routerDelegate: _routerDelegate,
        );
      },
    );
  }

  Widget _buildRootRoute(
    BuildContext context,
    AppRoute route,
    ValueListenable<ContactPageClosedEvent> contactPageClosedEvents,
  ) {
    final legacyBuilder = widget.signedOutScreenBuilder;
    if (legacyBuilder != null) {
      return widget.controller.isLoggedIn
          ? HomeShell(controller: widget.controller)
          : legacyBuilder(context, widget.controller);
    }
    return _SessionRoute(
      controller: widget.controller,
      identitySession: widget.identitySession,
      appSession: widget.appSession,
      readyBuilder: (context, trustedContext) => ProductionHomeShell(
        controller: widget.controller,
        appSession: widget.appSession,
        context: trustedContext,
        contactJournal: widget.contactJournal,
        deviceId: widget.deviceId,
        syncEngineFactory: widget.syncEngineFactory,
        locationCapture: widget.locationCapture,
        clock: widget.clock,
        timeZoneProvider: widget.timeZoneProvider,
        selectedIndex: route.primaryIndex,
        contactPageClosedEvents: contactPageClosedEvents,
        questionnaireAdministration: widget.questionnaireAdministration,
        idGenerator: widget.idGenerator,
        onDestinationSelected: (index) => _routerDelegate.go(switch (index) {
          0 => AppRoute.today,
          1 => AppRoute.contacts,
          2 => AppRoute.targets,
          _ => AppRoute.analysis,
        }),
        onOpenContactEntry: (draft) => _routerDelegate.go(
          draft == null
              ? AppRoute.newContact
              : AppRoute.contactDraft(draft.draftId),
        ),
        onOpenContactFromAttempt: (attempt) =>
            _routerDelegate.go(AppRoute.contactFromAttempt(attempt.attemptId)),
        onOpenContactDetail: (contact) =>
            _routerDelegate.go(AppRoute.contactDetail(contact.contactId)),
      ),
    );
  }

  Widget _buildContactRoute(
    BuildContext context,
    String? draftId,
    String? sourceAttemptId,
  ) {
    return _SessionRoute(
      controller: widget.controller,
      identitySession: widget.identitySession,
      appSession: widget.appSession,
      readyBuilder: (context, trustedContext) => _ContactEntryRoute(
        controller: widget.controller,
        clock: widget.clock,
        appSession: widget.appSession,
        context: trustedContext,
        contactJournal: widget.contactJournal,
        deviceId: widget.deviceId,
        locationCapture: widget.locationCapture,
        timeZoneProvider: widget.timeZoneProvider,
        regionResolver: widget.regionResolver,
        questionnaireCatalog: widget.questionnaireCatalog,
        draftId: draftId,
        sourceAttemptId: sourceAttemptId,
      ),
    );
  }

  Widget _buildContactDetailRoute(BuildContext context, String contactId) {
    return _SessionRoute(
      controller: widget.controller,
      identitySession: widget.identitySession,
      appSession: widget.appSession,
      readyBuilder: (context, trustedContext) => ContactRevisionScreen(
        controller: widget.controller,
        context: trustedContext,
        contactId: contactId,
        contactJournal: widget.contactJournal,
        deviceId: widget.deviceId,
        locationCapture: widget.locationCapture,
        timeZoneProvider: widget.timeZoneProvider,
        regionResolver: widget.regionResolver,
      ),
    );
  }
}

typedef _TrustedSessionBuilder =
    Widget Function(BuildContext context, TrustedSessionContext contextValue);

/// 所有可导航页共用的身份与可信上下文门。
final class _SessionRoute extends StatelessWidget {
  const _SessionRoute({
    required this.controller,
    required this.identitySession,
    required this.appSession,
    required this.readyBuilder,
  });

  final AppController controller;
  final IdentitySession identitySession;
  final AppSession appSession;
  final _TrustedSessionBuilder readyBuilder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppSessionSnapshot>(
      stream: appSession.changes,
      initialData: appSession.current,
      builder: (context, snapshot) {
        final session = snapshot.requireData;
        return switch (session.stage) {
          AppSessionStage.ready => readyBuilder(context, session.context!),
          AppSessionStage.resolvingContext => const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
          AppSessionStage.failed => _SessionFailureScreen(
            controller: controller,
            identitySession: identitySession,
            session: session,
          ),
          AppSessionStage.unavailable ||
          AppSessionStage.signedOut => AuthScreen(
            controller: controller,
            identitySession: identitySession,
          ),
        };
      },
    );
  }
}

/// 从私有草稿库解析稳定草稿地址，不让 Widget 直接读 Drift。
final class _ContactEntryRoute extends StatefulWidget {
  const _ContactEntryRoute({
    required this.controller,
    required this.clock,
    required this.appSession,
    required this.context,
    required this.contactJournal,
    required this.deviceId,
    required this.locationCapture,
    required this.timeZoneProvider,
    required this.regionResolver,
    required this.questionnaireCatalog,
    required this.draftId,
    required this.sourceAttemptId,
  });

  final AppController controller;
  final AppClock clock;
  final AppSession appSession;
  final TrustedSessionContext context;
  final ContactJournal contactJournal;
  final String deviceId;
  final ContactLocationCapture locationCapture;
  final DeviceTimeZoneProvider timeZoneProvider;
  final ContactRegionResolver regionResolver;
  final QuestionnaireCatalog questionnaireCatalog;
  final String? draftId;
  final String? sourceAttemptId;

  @override
  State<_ContactEntryRoute> createState() => _ContactEntryRouteState();
}

final class _ContactEntryRouteState extends State<_ContactEntryRoute> {
  late Future<ContactDraft?> _draft;
  late Future<ContactAttempt?> _sourceAttempt;
  final Map<String, Future<QuestionnaireVersion?>> _questionnaires = {};

  @override
  void initState() {
    super.initState();
    _draft = _loadDraft();
    _sourceAttempt = _loadSourceAttempt();
  }

  @override
  void didUpdateWidget(covariant _ContactEntryRoute oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.draftId != widget.draftId ||
        oldWidget.sourceAttemptId != widget.sourceAttemptId ||
        oldWidget.context.appUserId != widget.context.appUserId ||
        oldWidget.context.project.id != widget.context.project.id) {
      _questionnaires.clear();
      _draft = _loadDraft();
      _sourceAttempt = _loadSourceAttempt();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.draftId == null) {
      if (widget.sourceAttemptId == null) {
        return _screen(null, null);
      }
      return FutureBuilder<ContactAttempt?>(
        future: _sourceAttempt,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final attempt = snapshot.data;
          if (attempt == null || attempt.linkedContactId != null) {
            final text = AppStrings(widget.controller.localeCode);
            return Scaffold(
              appBar: AppBar(title: Text(text.t('recordContact'))),
              body: Center(child: Text(text.t('contactAttemptNotAvailable'))),
            );
          }
          return _screen(null, attempt);
        },
      );
    }
    return FutureBuilder<ContactDraft?>(
      future: _draft,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final draft = snapshot.data;
        if (draft == null) {
          final text = AppStrings(widget.controller.localeCode);
          return Scaffold(
            appBar: AppBar(title: Text(text.t('recordContact'))),
            body: Center(child: Text(text.t('draftNotFound'))),
          );
        }
        return _screen(draft, null);
      },
    );
  }

  Widget _screen(ContactDraft? draft, ContactAttempt? sourceAttempt) {
    final versionId =
        draft?.questionnaireVersionId ?? widget.context.questionnaireVersion.id;
    final questionnaire = _questionnaires.putIfAbsent(
      versionId,
      () => widget.questionnaireCatalog.resolvePublishedVersion(
        projectId: widget.context.project.id,
        versionId: versionId,
      ),
    );
    return FutureBuilder<QuestionnaireVersion?>(
      future: questionnaire,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final version = snapshot.data;
        if (snapshot.hasError || version == null) {
          final text = AppStrings(widget.controller.localeCode);
          return Scaffold(
            appBar: AppBar(title: Text(text.t('recordContact'))),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      text.t('questionnaireUnavailable'),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _questionnaires.remove(versionId);
                        });
                      },
                      icon: const Icon(Icons.refresh_outlined),
                      label: Text(text.t('retry')),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return ContactEntryScreen(
          controller: widget.controller,
          clock: widget.clock,
          context: widget.context,
          contactJournal: widget.contactJournal,
          deviceId: widget.deviceId,
          initialDraft: draft,
          locationCapture: widget.locationCapture,
          timeZoneProvider: widget.timeZoneProvider,
          regionResolver: widget.regionResolver,
          sourceAttempt: sourceAttempt,
          questionnaireVersion: version,
        );
      },
    );
  }

  Future<ContactDraft?> _loadDraft() async {
    final draftId = widget.draftId;
    if (draftId == null) {
      return null;
    }
    final draft = await widget.contactJournal.draftByIdForOwner(
      draftId: draftId,
      appUserId: widget.context.appUserId,
    );
    if (draft == null || draft.projectId == widget.context.project.id) {
      return draft;
    }
    final result = await widget.appSession.selectProject(draft.projectId);
    return result is SessionContextSuccess ? draft : null;
  }

  Future<ContactAttempt?> _loadSourceAttempt() async {
    final attemptId = widget.sourceAttemptId;
    if (attemptId == null) {
      return null;
    }
    final attempt = await widget.contactJournal.contactAttemptByIdForOwner(
      attemptId: attemptId,
      appUserId: widget.context.appUserId,
    );
    if (attempt == null || attempt.projectId == widget.context.project.id) {
      return attempt;
    }
    final result = await widget.appSession.selectProject(attempt.projectId);
    return result is SessionContextSuccess ? attempt : null;
  }
}

final class _SessionFailureScreen extends StatelessWidget {
  const _SessionFailureScreen({
    required this.controller,
    required this.identitySession,
    required this.session,
  });

  final AppController controller;
  final IdentitySession identitySession;
  final AppSessionSnapshot session;

  @override
  Widget build(BuildContext context) {
    final text = AppStrings(controller.localeCode);
    return Scaffold(
      appBar: AppBar(title: Text(text.t('appTitle'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_person_outlined,
                  size: 48,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  text.t('contextLoadFailedTitle'),
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(_failureMessage(text), textAlign: TextAlign.center),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: () => unawaited(identitySession.signOut()),
                  icon: const Icon(Icons.logout_outlined),
                  label: Text(text.t('logout')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _failureMessage(AppStrings text) {
    return switch (session.contextFailure) {
      SessionContextFailureCode.unauthorized => text.t('contextUnauthorized'),
      SessionContextFailureCode.networkUnavailable => text.t(
        'contextNetworkUnavailable',
      ),
      SessionContextFailureCode.notConfigured => text.t('contextNotConfigured'),
      SessionContextFailureCode.invalidResponse ||
      SessionContextFailureCode.serverRejected => text.t(
        'contextServerRejected',
      ),
      null => text.t('contextIdentityFailed'),
    };
  }
}

class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({required this.failure});

  final AppStartupFailure failure;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.storage_outlined, size: 40),
                const SizedBox(height: 16),
                const Text(
                  '本地数据库启动失败 / Local database startup failed',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                SelectableText(failure.code),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

ThemeData _theme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF14746F),
    brightness: brightness,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    visualDensity: VisualDensity.standard,
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    ),
  );
}
