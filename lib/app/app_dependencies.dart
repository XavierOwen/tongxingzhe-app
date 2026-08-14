import '../app_session/app_session.dart';
import '../app_session/http_session_context_gateway.dart';
import '../app_session/session_context_gateway.dart';
import '../data/local_database.dart';
import '../data/local_database_factory.dart';
import '../data/drift_current_relationship_stage_snapshot_store.dart';
import '../device/device_identity_store.dart';
import '../device/device_time_zone.dart';
import '../features/contact_journal/contact_journal.dart';
import '../features/contact_metrics/current_relationship_stage.dart';
import '../features/contact_metrics/current_relationship_stage_gateway.dart';
import '../features/contact_metrics/http_personal_follow_up_consent_ratio_gateway.dart';
import '../features/contact_metrics/http_relationship_stage_change_summary_gateway.dart';
import '../features/contact_metrics/personal_follow_up_consent_ratio.dart';
import '../features/contact_metrics/relationship_stage_change_summary.dart';
import '../foundation/runtime_values.dart';
import '../identity/identity_session.dart';
import '../identity/supabase/supabase_identity_session.dart';
import '../management_reports/http_management_report_gateway.dart';
import '../management_reports/management_report_gateway.dart';
import '../platform/platform_capabilities.dart';
import '../plans/http_personal_action_plan_gateway.dart';
import '../plans/personal_action_plan.dart';
import '../plans/personal_planning_cache.dart';
import '../privacy/drift_offline_pii_lock_store.dart';
import '../privacy/flutter_secure_value_store.dart';
import '../privacy/offline_pii_vault.dart';
import '../privacy/secure_value_store_capability_probe.dart';
import '../project_settings/http_personal_follow_up_consent_opt_in_gateway.dart';
import '../project_settings/personal_follow_up_consent_opt_in.dart';
import '../questionnaires/http_questionnaire_remote_source.dart';
import '../questionnaires/http_questionnaire_administration_gateway.dart';
import '../questionnaires/questionnaire_administration.dart';
import '../questionnaires/questionnaire_administration_cache.dart';
import '../questionnaires/questionnaire_contract.dart';
import '../regions/contact_region_resolver.dart';
import '../reminders/drift_device_reminder_preference_store.dart';
import '../reminders/flutter_reminder_notification_scheduler.dart';
import '../reminders/http_personal_action_reminder_gateway.dart';
import '../reminders/personal_action_reminder.dart';
import '../services/location_service.dart';
import '../sync/http_sync_transport.dart';
import '../sync/sync_engine_factory.dart';
import '../sync/sync_transport.dart';
import '../targets/http_promotion_target_gateway.dart';
import '../targets/offline_promotion_target_gateway.dart';
import '../targets/promotion_target.dart';
import 'app_controller.dart';
import 'legacy_demo_access.dart';
import 'private_session_data_guard.dart';

/// App 唯一的 composition root。
///
/// 它集中决定正式数据库、时钟和 ID 实现，并把数据库打开／Controller 加载
/// 转成调用者可处理的结果，避免启动异常被 FutureBuilder 当成成功。
final class AppDependencies {
  const AppDependencies({
    required this.databaseFactory,
    required this.clock,
    required this.idGenerator,
    required this.identitySessionFactory,
    required this.sessionContextGateway,
    required this.platformCapabilitiesProvider,
    this.timeZoneProvider = const FlutterDeviceTimeZoneProvider(),
    this.locationCapture = const LocationService(),
    this.syncTransportBuilder,
    this.regionResolverBuilder,
    this.questionnaireRemoteSourceBuilder,
    this.questionnaireAdministrationBuilder,
    this.promotionTargetGatewayBuilder,
    this.personalActionPlanGatewayBuilder,
    this.personalActionReminderGatewayBuilder,
    this.personalFollowUpConsentOptInGatewayBuilder,
    this.personalFollowUpConsentRatioGatewayBuilder,
    this.personalRelationshipStageChangeSummaryGatewayBuilder,
    this.managementReportGatewayBuilder,
    this.currentRelationshipStageGatewayBuilder,
    this.reminderSchedulerBuilder = productionReminderNotificationScheduler,
    this.offlinePiiSecureStore,
    this.legacyDemoAccess,
  });

  factory AppDependencies.production() {
    final secureStore = FlutterSecureValueStore();
    return AppDependencies(
      databaseFactory: const DriftLocalDatabaseFactory(),
      clock: const SystemClock(),
      idGenerator: SecureIdGenerator(),
      identitySessionFactory: productionIdentitySessionFactory(),
      sessionContextGateway: productionSessionContextGateway(),
      platformCapabilitiesProvider: FlutterPlatformCapabilitiesProvider(
        secureStorageProbe: SecureValueStoreCapabilityProbe(
          store: secureStore,
          idGenerator: SecureIdGenerator(),
        ),
      ),
      syncTransportBuilder: productionSyncTransport,
      regionResolverBuilder: productionContactRegionResolver,
      questionnaireRemoteSourceBuilder: productionQuestionnaireRemoteSource,
      questionnaireAdministrationBuilder: productionQuestionnaireAdministration,
      promotionTargetGatewayBuilder: productionPromotionTargetGateway,
      personalActionPlanGatewayBuilder: productionPersonalActionPlanGateway,
      personalActionReminderGatewayBuilder:
          productionPersonalActionReminderGateway,
      personalFollowUpConsentOptInGatewayBuilder:
          productionPersonalFollowUpConsentOptInGateway,
      personalFollowUpConsentRatioGatewayBuilder:
          productionPersonalFollowUpConsentRatioGateway,
      personalRelationshipStageChangeSummaryGatewayBuilder:
          productionPersonalRelationshipStageChangeSummaryGateway,
      managementReportGatewayBuilder: productionManagementReportGateway,
      currentRelationshipStageGatewayBuilder:
          productionCurrentRelationshipStageGateway,
      offlinePiiSecureStore: secureStore,
    );
  }

  final LocalDatabaseFactory databaseFactory;
  final AppClock clock;
  final IdGenerator idGenerator;
  final IdentitySessionFactory identitySessionFactory;
  final SessionContextGateway sessionContextGateway;
  final PlatformCapabilitiesProvider platformCapabilitiesProvider;
  final DeviceTimeZoneProvider timeZoneProvider;
  final ContactLocationCapture locationCapture;
  final SyncTransport? Function(IdentitySession)? syncTransportBuilder;
  final ContactRegionResolver Function(IdentitySession, LocalDatabase)?
  regionResolverBuilder;
  final QuestionnaireRemoteSource? Function(IdentitySession)?
  questionnaireRemoteSourceBuilder;
  final QuestionnaireAdministrationGateway Function(IdentitySession)?
  questionnaireAdministrationBuilder;
  final PromotionTargetGateway Function(IdentitySession)?
  promotionTargetGatewayBuilder;
  final PersonalActionPlanGateway Function(IdentitySession)?
  personalActionPlanGatewayBuilder;
  final PersonalActionReminderGateway Function(IdentitySession)?
  personalActionReminderGatewayBuilder;
  final PersonalFollowUpConsentOptInGateway Function(
    IdentitySession,
    String Function(),
  )?
  personalFollowUpConsentOptInGatewayBuilder;
  final PersonalFollowUpConsentRatioGateway Function(IdentitySession)?
  personalFollowUpConsentRatioGatewayBuilder;
  final PersonalRelationshipStageChangeSummaryGateway Function(IdentitySession)?
  personalRelationshipStageChangeSummaryGatewayBuilder;
  final ManagementReportGateway Function(IdentitySession)?
  managementReportGatewayBuilder;
  final CurrentRelationshipStageGateway Function(IdentitySession)?
  currentRelationshipStageGatewayBuilder;
  final ReminderNotificationScheduler Function(AppPlatform)
  reminderSchedulerBuilder;
  final SecureValueStore? offlinePiiSecureStore;

  /// 临时兼容 legacy demo；正式 composition root 永远不提供此 Adapter。
  final LegacyDemoAccess? legacyDemoAccess;

  Future<AppStartupResult> start() async {
    LocalDatabase? database;
    IdentitySession? identitySession;
    AppSession? appSession;
    SyncEngineFactory? syncEngineFactory;
    ContactRegionResolver? regionResolver;
    QuestionnaireCatalog? questionnaireCatalog;
    QuestionnaireAdministrationGateway? questionnaireAdministration;
    PromotionTargetGateway? promotionTargetGateway;
    PersonalActionPlanGateway? personalActionPlanGateway;
    PersonalActionReminderGateway? personalActionReminderGateway;
    PersonalFollowUpConsentOptInGateway? personalFollowUpConsentOptInGateway;
    PersonalFollowUpConsentRatioGateway? personalFollowUpConsentRatioGateway;
    PersonalRelationshipStageChangeSummaryGateway?
    personalRelationshipStageChangeSummaryGateway;
    ManagementReportGateway? managementReportGateway;
    CurrentRelationshipStageGateway? currentRelationshipStageGateway;
    ReminderNotificationScheduler? reminderNotificationScheduler;
    PrivateSessionDataGuard? privateSessionDataGuard;
    OfflinePiiVault? offlinePiiVault;
    try {
      identitySession = await identitySessionFactory.open();
    } catch (error, stackTrace) {
      await sessionContextGateway.close();
      return AppStartupFailed(
        AppStartupFailure(
          code: error is SupabaseConfigurationException
              ? 'identity_configuration_invalid'
              : 'identity_initialization_failed',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }

    PlatformCapabilities platformCapabilities;
    try {
      platformCapabilities = await platformCapabilitiesProvider.load();
    } catch (error, stackTrace) {
      await identitySession.close();
      await sessionContextGateway.close();
      return AppStartupFailed(
        AppStartupFailure(
          code: 'platform_capability_detection_failed',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }

    try {
      database = databaseFactory.open();
      final controller = AppController(
        database: database,
        clock: clock,
        idGenerator: idGenerator,
        legacyDemoAccess: legacyDemoAccess,
      );
      final contactJournal = ContactJournal(
        database: database,
        clock: clock,
        idGenerator: idGenerator,
      );
      await controller.load();
      final deviceId = await DeviceIdentityStore(
        database,
        idGenerator,
      ).loadOrCreate();
      final platformPolicy = PlatformPolicy.from(platformCapabilities);
      final secureStore = offlinePiiSecureStore;
      if (platformPolicy.canPersistSensitiveTargets && secureStore != null) {
        offlinePiiVault = OfflinePiiVault(
          secureStore: secureStore,
          lockStore: DriftOfflinePiiLockStore(database),
          clock: clock,
          installationId: deviceId,
        );
      }
      final syncTransport = syncTransportBuilder?.call(identitySession);
      if (syncTransport != null) {
        syncEngineFactory = SyncEngineFactory(
          database: database,
          clock: clock,
          idGenerator: idGenerator,
          transport: syncTransport,
          jitter: SecureSyncJitter(),
        );
      }
      regionResolver =
          regionResolverBuilder?.call(identitySession, database) ??
          const DeferredContactRegionResolver();
      questionnaireCatalog = QuestionnaireCatalog(
        database: database,
        remoteSource: questionnaireRemoteSourceBuilder?.call(identitySession),
      );
      questionnaireAdministration = CachedQuestionnaireAdministrationGateway(
        database: database,
        remote:
            questionnaireAdministrationBuilder?.call(identitySession) ??
            const DeferredQuestionnaireAdministrationGateway(),
      );
      appSession = AppSession(
        identitySession: identitySession,
        contextGateway: sessionContextGateway,
        offlinePiiVault: offlinePiiVault,
      );
      await appSession.start();
      managementReportGateway =
          managementReportGatewayBuilder?.call(identitySession) ??
          const DeferredManagementReportGateway();
      currentRelationshipStageGateway =
          currentRelationshipStageGatewayBuilder?.call(identitySession) ??
          const DeferredCurrentRelationshipStageGateway();
      final currentRelationshipStageRepository =
          CurrentRelationshipStageRepository(
            gateway: currentRelationshipStageGateway,
            store: DriftCurrentRelationshipStageSnapshotStore(database),
          );
      final remoteTargetGateway =
          promotionTargetGatewayBuilder?.call(identitySession) ??
          const DeferredPromotionTargetGateway();
      promotionTargetGateway = offlinePiiVault == null
          ? remoteTargetGateway
          : OfflinePromotionTargetGateway(
              remote: remoteTargetGateway,
              vault: offlinePiiVault,
              externalSubject: () {
                final subject =
                    identitySession!.current.principal?.externalSubject;
                if (subject == null) {
                  throw StateError('offline_pii_identity_missing');
                }
                return subject;
              },
              currentContext: () {
                final context = appSession!.current.context;
                if (context == null) {
                  throw StateError('offline_pii_context_missing');
                }
                return context;
              },
            );
      final planningCache = DriftPersonalPlanningCache(database);
      reminderNotificationScheduler = reminderSchedulerBuilder(
        platformCapabilities.platform,
      );
      Future<void> cancelReminderForScope(PersonalPlanningScope scope) async {
        await reminderNotificationScheduler!.cancel(
          scheduleKey: personalActionReminderScheduleKey(
            DeviceReminderScope(
              appUserId: scope.appUserId,
              workspaceId: scope.workspaceId,
              projectId: scope.projectId,
              deviceId: deviceId,
            ),
          ),
        );
      }

      PersonalPlanningScope? currentPlanningScope() {
        final snapshot = appSession!.current;
        final context = snapshot.context;
        if (snapshot.stage != AppSessionStage.ready || context == null) {
          return null;
        }
        return PersonalPlanningScope(
          appUserId: context.appUserId,
          workspaceId: context.workspace.id,
          projectId: context.project.id,
        );
      }

      personalActionPlanGateway = CachedPersonalActionPlanGateway(
        remote:
            personalActionPlanGatewayBuilder?.call(identitySession) ??
            const DeferredPersonalActionPlanGateway(),
        cache: planningCache,
        scopeProvider: currentPlanningScope,
        clock: clock,
        onAuthorizationRevoked: cancelReminderForScope,
      );
      personalActionReminderGateway = CachedPersonalActionReminderGateway(
        remote:
            personalActionReminderGatewayBuilder?.call(identitySession) ??
            const DeferredPersonalActionReminderGateway(),
        cache: planningCache,
        scopeProvider: currentPlanningScope,
        clock: clock,
        onAuthorizationRevoked: cancelReminderForScope,
      );
      personalFollowUpConsentOptInGateway =
          personalFollowUpConsentOptInGatewayBuilder?.call(identitySession, () {
            final snapshot = appSession!.current;
            final context = snapshot.context;
            if (snapshot.stage != AppSessionStage.ready || context == null) {
              throw StateError('personal_project_settings_scope_unavailable');
            }
            return context.project.id;
          }) ??
          const DeferredPersonalFollowUpConsentOptInGateway();
      personalFollowUpConsentRatioGateway =
          personalFollowUpConsentRatioGatewayBuilder?.call(identitySession) ??
          const DeferredPersonalFollowUpConsentRatioGateway();
      personalRelationshipStageChangeSummaryGateway =
          personalRelationshipStageChangeSummaryGatewayBuilder?.call(
            identitySession,
          ) ??
          const DeferredPersonalRelationshipStageChangeSummaryGateway();
      privateSessionDataGuard = await PrivateSessionDataGuard.start(
        appSession: appSession,
        scheduler: reminderNotificationScheduler,
        planningCache: planningCache,
      );
      return AppStartupReady(
        controller: controller,
        clock: clock,
        contactJournal: contactJournal,
        deviceId: deviceId,
        syncEngineFactory: syncEngineFactory,
        identitySession: identitySession,
        appSession: appSession,
        platformCapabilities: platformCapabilities,
        platformPolicy: platformPolicy,
        locationCapture: locationCapture,
        timeZoneProvider: timeZoneProvider,
        regionResolver: regionResolver,
        questionnaireCatalog: questionnaireCatalog,
        questionnaireAdministration: questionnaireAdministration,
        promotionTargetGateway: promotionTargetGateway,
        personalActionPlanGateway: personalActionPlanGateway,
        personalActionReminderGateway: personalActionReminderGateway,
        personalFollowUpConsentOptInGateway:
            personalFollowUpConsentOptInGateway,
        personalFollowUpConsentRatioGateway:
            personalFollowUpConsentRatioGateway,
        personalRelationshipStageChangeSummaryGateway:
            personalRelationshipStageChangeSummaryGateway,
        managementReportGateway: managementReportGateway,
        currentRelationshipStageGateway: currentRelationshipStageGateway,
        currentRelationshipStageRepository: currentRelationshipStageRepository,
        deviceReminderPreferenceStore: DriftDeviceReminderPreferenceStore(
          database,
        ),
        reminderNotificationScheduler: reminderNotificationScheduler,
        privateSessionDataGuard: privateSessionDataGuard,
        idGenerator: idGenerator,
      );
    } catch (error, stackTrace) {
      await database?.close();
      await syncEngineFactory?.close();
      await regionResolver?.close();
      await questionnaireCatalog?.close();
      await questionnaireAdministration?.close();
      await promotionTargetGateway?.close();
      await personalActionPlanGateway?.close();
      await personalActionReminderGateway?.close();
      await personalFollowUpConsentOptInGateway?.close();
      await personalFollowUpConsentRatioGateway?.close();
      await personalRelationshipStageChangeSummaryGateway?.close();
      await managementReportGateway?.close();
      await currentRelationshipStageGateway?.close();
      await privateSessionDataGuard?.close();
      await reminderNotificationScheduler?.close();
      await appSession?.close();
      if (appSession == null) {
        await sessionContextGateway.close();
      }
      await identitySession.close();
      return AppStartupFailed(
        AppStartupFailure(
          code: 'local_database_initialization_failed',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}

sealed class AppStartupResult {
  const AppStartupResult();
}

final class AppStartupReady extends AppStartupResult {
  const AppStartupReady({
    required this.controller,
    required this.clock,
    required this.contactJournal,
    required this.deviceId,
    required this.syncEngineFactory,
    required this.identitySession,
    required this.appSession,
    required this.platformCapabilities,
    required this.platformPolicy,
    required this.locationCapture,
    required this.timeZoneProvider,
    required this.regionResolver,
    required this.questionnaireCatalog,
    required this.questionnaireAdministration,
    required this.promotionTargetGateway,
    required this.personalActionPlanGateway,
    required this.personalActionReminderGateway,
    required this.personalFollowUpConsentOptInGateway,
    required this.personalFollowUpConsentRatioGateway,
    required this.personalRelationshipStageChangeSummaryGateway,
    required this.managementReportGateway,
    required this.currentRelationshipStageGateway,
    required this.currentRelationshipStageRepository,
    required this.deviceReminderPreferenceStore,
    required this.reminderNotificationScheduler,
    required this.privateSessionDataGuard,
    required this.idGenerator,
  });

  final AppController controller;
  final AppClock clock;
  final ContactJournal contactJournal;
  final String deviceId;
  final SyncEngineFactory? syncEngineFactory;
  final IdentitySession identitySession;
  final AppSession appSession;
  final PlatformCapabilities platformCapabilities;
  final PlatformPolicy platformPolicy;
  final ContactLocationCapture locationCapture;
  final DeviceTimeZoneProvider timeZoneProvider;
  final ContactRegionResolver regionResolver;
  final QuestionnaireCatalog questionnaireCatalog;
  final QuestionnaireAdministrationGateway questionnaireAdministration;
  final PromotionTargetGateway promotionTargetGateway;
  final PersonalActionPlanGateway personalActionPlanGateway;
  final PersonalActionReminderGateway personalActionReminderGateway;
  final PersonalFollowUpConsentOptInGateway personalFollowUpConsentOptInGateway;
  final PersonalFollowUpConsentRatioGateway personalFollowUpConsentRatioGateway;
  final PersonalRelationshipStageChangeSummaryGateway
  personalRelationshipStageChangeSummaryGateway;
  final ManagementReportGateway managementReportGateway;
  final CurrentRelationshipStageGateway currentRelationshipStageGateway;
  final CurrentRelationshipStageRepository currentRelationshipStageRepository;
  final DeviceReminderPreferenceStore deviceReminderPreferenceStore;
  final ReminderNotificationScheduler reminderNotificationScheduler;
  final PrivateSessionDataGuard privateSessionDataGuard;
  final IdGenerator idGenerator;
}

final class AppStartupFailed extends AppStartupResult {
  const AppStartupFailed(this.failure);

  final AppStartupFailure failure;
}

/// 启动失败的稳定外部表示。
///
/// [cause] 和 [stackTrace] 只供诊断；UI 和测试依据稳定 [code] 决定表现，
/// 不解析第三方数据库异常文字。
final class AppStartupFailure {
  const AppStartupFailure({
    required this.code,
    required this.cause,
    required this.stackTrace,
  });

  final String code;
  final Object cause;
  final StackTrace stackTrace;
}
