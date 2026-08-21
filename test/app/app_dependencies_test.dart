import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tongxingzhe_app/app/app_dependencies.dart';
import 'package:tongxingzhe_app/data/local_database.dart';
import 'package:tongxingzhe_app/data/local_database_factory.dart';
import 'package:tongxingzhe_app/device/device_identity_store.dart';
import 'package:tongxingzhe_app/features/contact_metrics/current_relationship_stage.dart';
import 'package:tongxingzhe_app/features/contact_metrics/http_personal_follow_up_consent_ratio_gateway.dart';
import 'package:tongxingzhe_app/features/contact_metrics/http_relationship_stage_change_summary_gateway.dart';
import 'package:tongxingzhe_app/features/contact_metrics/personal_follow_up_consent_ratio.dart';
import 'package:tongxingzhe_app/features/contact_metrics/relationship_stage_change_summary.dart';
import 'package:tongxingzhe_app/foundation/runtime_values.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/legacy_demo/legacy_demo_dependencies.dart';
import 'package:tongxingzhe_app/management_reports/current_city_report_gateway.dart';
import 'package:tongxingzhe_app/management_reports/management_report_export_delivery.dart';
import 'package:tongxingzhe_app/management_reports/management_report_gateway.dart';
import 'package:tongxingzhe_app/privacy/drift_offline_pii_lock_store.dart';
import 'package:tongxingzhe_app/privacy/offline_pii_vault.dart';
import 'package:tongxingzhe_app/project_settings/http_personal_follow_up_consent_opt_in_gateway.dart';
import 'package:tongxingzhe_app/project_settings/personal_follow_up_consent_opt_in.dart';
import 'package:tongxingzhe_app/targets/promotion_target.dart';

import '../support/fake_identity_session.dart';
import '../support/fake_platform_capabilities.dart';
import '../support/fake_session_context_gateway.dart';

void main() {
  test('正式启动不会创建 legacy 演示账号或记录', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    final dependencies = AppDependencies(
      databaseFactory: _SingleDatabaseFactory(database),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(FakeIdentitySession()),
      sessionContextGateway: FakeSessionContextGateway(),
      platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
    );

    final startup = await dependencies.start();

    expect(startup, isA<AppStartupReady>());
    final ready = startup as AppStartupReady;
    final controller = ready.controller;
    addTearDown(ready.identitySession.close);
    addTearDown(ready.appSession.close);
    addTearDown(controller.dispose);
    expect(controller.users, isEmpty);
    expect(controller.records, isEmpty);
    expect(
      ready.personalFollowUpConsentOptInGateway,
      isA<DeferredPersonalFollowUpConsentOptInGateway>(),
    );
    expect(
      ready.personalFollowUpConsentRatioGateway,
      isA<DeferredPersonalFollowUpConsentRatioGateway>(),
    );
    expect(
      ready.personalRelationshipStageChangeSummaryGateway,
      isA<DeferredPersonalRelationshipStageChangeSummaryGateway>(),
    );
    expect(
      ready.managementReportExportDelivery,
      isA<UnsupportedManagementReportExportDelivery>(),
    );

    final login = await controller.login('admin1', 'admin1');
    expect(login.success, isFalse);
    expect(login.messageKey, 'authUnavailableInProduction');
  });

  test('composition root 装配并释放后续联系同意占比 gateway', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    final gateway = _TrackingConsentOptInGateway();
    final dependencies = AppDependencies(
      databaseFactory: _SingleDatabaseFactory(database),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(FakeIdentitySession()),
      sessionContextGateway: FakeSessionContextGateway(),
      platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
      personalFollowUpConsentOptInGatewayBuilder: (_, _) => gateway,
    );

    final startup = await dependencies.start();

    expect(startup, isA<AppStartupReady>());
    final ready = startup as AppStartupReady;
    expect(
      identical(ready.personalFollowUpConsentOptInGateway, gateway),
      isTrue,
    );
    await ready.personalFollowUpConsentOptInGateway.close();
    expect(gateway.closeCount, 1);
    await ready.appSession.close();
    await ready.identitySession.close();
    ready.controller.dispose();
    await database.close();
  });

  test('composition root 装配并释放个人同意占比读取 gateway', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    final gateway = _TrackingConsentRatioGateway();
    final dependencies = AppDependencies(
      databaseFactory: _SingleDatabaseFactory(database),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(FakeIdentitySession()),
      sessionContextGateway: FakeSessionContextGateway(),
      platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
      personalFollowUpConsentRatioGatewayBuilder: (_) => gateway,
    );

    final startup = await dependencies.start();

    expect(startup, isA<AppStartupReady>());
    final ready = startup as AppStartupReady;
    expect(
      identical(ready.personalFollowUpConsentRatioGateway, gateway),
      isTrue,
    );
    await ready.personalFollowUpConsentRatioGateway.close();
    expect(gateway.closeCount, 1);
    await ready.appSession.close();
    await ready.identitySession.close();
    ready.controller.dispose();
    await database.close();
  });

  test('composition root 装配并释放个人阶段变更读取 gateway', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    final gateway = _TrackingRelationshipStageChangeSummaryGateway();
    final dependencies = AppDependencies(
      databaseFactory: _SingleDatabaseFactory(database),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(FakeIdentitySession()),
      sessionContextGateway: FakeSessionContextGateway(),
      platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
      personalRelationshipStageChangeSummaryGatewayBuilder: (_) => gateway,
    );

    final startup = await dependencies.start();

    expect(startup, isA<AppStartupReady>());
    final ready = startup as AppStartupReady;
    expect(
      identical(ready.personalRelationshipStageChangeSummaryGateway, gateway),
      isTrue,
    );
    await ready.personalRelationshipStageChangeSummaryGateway.close();
    expect(gateway.closeCount, 1);
    await ready.appSession.close();
    await ready.identitySession.close();
    ready.controller.dispose();
    await database.close();
  });

  test('composition root 保留显式注入的管理报告下载 adapter', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    final delivery = _TrackingManagementReportExportDelivery();
    final dependencies = AppDependencies(
      databaseFactory: _SingleDatabaseFactory(database),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(FakeIdentitySession()),
      sessionContextGateway: FakeSessionContextGateway(),
      platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
      managementReportExportDelivery: delivery,
    );

    final startup = await dependencies.start();

    expect(startup, isA<AppStartupReady>());
    final ready = startup as AppStartupReady;
    expect(identical(ready.managementReportExportDelivery, delivery), isTrue);
    await ready.appSession.close();
    await ready.identitySession.close();
    ready.controller.dispose();
    await database.close();
  });

  test('composition root 装配并释放 current-city gateway', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    final gateway = _TrackingCurrentCityReportGateway();
    final dependencies = AppDependencies(
      databaseFactory: _SingleDatabaseFactory(database),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(FakeIdentitySession()),
      sessionContextGateway: FakeSessionContextGateway(),
      platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
      currentCityReportGatewayBuilder: (_) => gateway,
    );

    final startup = await dependencies.start();

    expect(startup, isA<AppStartupReady>());
    final ready = startup as AppStartupReady;
    expect(identical(ready.currentCityReportGateway, gateway), isTrue);
    await ready.currentCityReportGateway.close();
    expect(gateway.closeCount, 1);
    await ready.appSession.close();
    await ready.identitySession.close();
    ready.controller.dispose();
    await database.close();
  });

  test('配置 Backend 时 composition root 把当前项目绑定到 HTTP gateway', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    final identity = FakeIdentitySession(
      initial: const IdentitySnapshot(
        stage: IdentityStage.signedIn,
        principal: IdentityPrincipal(
          externalSubject: 'external-subject-not-an-app-user-id',
          email: 'person@example.test',
        ),
      ),
    );
    IdentitySession? receivedIdentity;
    String Function()? receivedProjectId;
    final dependencies = AppDependencies(
      databaseFactory: _SingleDatabaseFactory(database),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(identity),
      sessionContextGateway: FakeSessionContextGateway(),
      platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
      personalFollowUpConsentOptInGatewayBuilder: (session, currentProjectId) {
        receivedIdentity = session;
        receivedProjectId = currentProjectId;
        return HttpPersonalFollowUpConsentOptInGateway(
          baseUri: Uri.parse('https://backend.example.test'),
          identitySession: session,
          client: MockClient((_) async => http.Response('', 503)),
          currentProjectId: currentProjectId,
        );
      },
    );

    final startup = await dependencies.start();

    expect(startup, isA<AppStartupReady>());
    final ready = startup as AppStartupReady;
    final gateway = ready.personalFollowUpConsentOptInGateway;
    addTearDown(gateway.close);
    addTearDown(ready.appSession.close);
    addTearDown(ready.identitySession.close);
    addTearDown(ready.controller.dispose);
    addTearDown(database.close);

    expect(identical(receivedIdentity, identity), isTrue);
    expect(receivedProjectId, isNotNull);
    expect(receivedProjectId!(), syntheticSessionContext.project.id);
    expect(gateway, isA<HttpPersonalFollowUpConsentOptInGateway>());
    expect(
      (gateway as HttpPersonalFollowUpConsentOptInGateway).currentProjectId(),
      syntheticSessionContext.project.id,
    );
  });

  test('数据库无法打开时返回稳定的启动失败结果', () async {
    final identity = FakeIdentitySession();
    final dependencies = AppDependencies(
      databaseFactory: const _ThrowingDatabaseFactory(),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(identity),
      sessionContextGateway: FakeSessionContextGateway(),
      platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
    );

    final startup = await dependencies.start();

    expect(startup, isA<AppStartupFailed>());
    final failure = (startup as AppStartupFailed).failure;
    expect(failure.code, 'local_database_initialization_failed');
    expect(failure.cause, isA<StateError>());
    expect(identity.isClosed, isTrue);
  });

  test('平台能力探测失败时释放身份并返回稳定结果', () async {
    final identity = FakeIdentitySession();
    final dependencies = AppDependencies(
      databaseFactory: const _ThrowingDatabaseFactory(),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(identity),
      sessionContextGateway: FakeSessionContextGateway(),
      platformCapabilitiesProvider: FakePlatformCapabilitiesProvider(
        failure: StateError('synthetic capability failure'),
      ),
    );

    final startup = await dependencies.start();

    expect(startup, isA<AppStartupFailed>());
    expect(
      (startup as AppStartupFailed).failure.code,
      'platform_capability_detection_failed',
    );
    expect(identity.isClosed, isTrue);
  });

  test('composition root 在后续启动失败时关闭已经装配的 gateways', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    final gateway = _TrackingManagementReportGateway();
    final currentCityGateway = _TrackingCurrentCityReportGateway();
    final relationshipGateway = _TrackingCurrentRelationshipStageGateway();
    final dependencies = AppDependencies(
      databaseFactory: _SingleDatabaseFactory(database),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(FakeIdentitySession()),
      sessionContextGateway: FakeSessionContextGateway(),
      platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
      managementReportGatewayBuilder: (_) => gateway,
      currentCityReportGatewayBuilder: (_) => currentCityGateway,
      currentRelationshipStageGatewayBuilder: (_) => relationshipGateway,
      reminderSchedulerBuilder: (_) => throw StateError('synthetic failure'),
    );

    final startup = await dependencies.start();

    expect(startup, isA<AppStartupFailed>());
    expect(gateway.closeCount, 1);
    expect(currentCityGateway.closeCount, 1);
    expect(relationshipGateway.closeCount, 1);
  });

  test('能力通过时 composition root 装配离线对象 gateway', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    final clock = _FixedClock(DateTime.utc(2030, 1, 2, 13));
    final ids = _SequenceIdGenerator();
    final installationId = await DeviceIdentityStore(
      database,
      ids,
    ).loadOrCreate();
    final secureStore = _MemorySecureValueStore();
    final vault = OfflinePiiVault(
      secureStore: secureStore,
      lockStore: DriftOfflinePiiLockStore(database),
      clock: clock,
      installationId: installationId,
    );
    await vault.replace(
      externalSubject: 'external-subject-not-an-app-user-id',
      context: syntheticSessionContext,
      assignedTargets: [_target],
      authorizedAtUtc: DateTime.utc(2030, 1, 2, 12),
    );
    final identity = FakeIdentitySession(
      initial: IdentitySnapshot(
        stage: IdentityStage.signedIn,
        principal: const IdentityPrincipal(
          externalSubject: 'external-subject-not-an-app-user-id',
          email: 'person@example.test',
        ),
        expiresAt: DateTime.utc(2030, 1, 3),
      ),
    );
    final dependencies = AppDependencies(
      databaseFactory: _SingleDatabaseFactory(database),
      clock: clock,
      idGenerator: ids,
      identitySessionFactory: FakeIdentitySessionFactory(identity),
      sessionContextGateway: FakeSessionContextGateway(),
      platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
      offlinePiiSecureStore: secureStore,
    );

    final startup = await dependencies.start();
    expect(startup, isA<AppStartupReady>());
    final ready = startup as AppStartupReady;
    addTearDown(ready.promotionTargetGateway.close);
    addTearDown(ready.identitySession.close);
    addTearDown(ready.appSession.close);
    addTearDown(ready.controller.dispose);

    final result = await ready.promotionTargetGateway.loadAssigned();

    expect(result, isA<PromotionTargetSuccess<List<PromotionTargetProfile>>>());
    final success =
        result as PromotionTargetSuccess<List<PromotionTargetProfile>>;
    expect(success.fromOfflineCache, isTrue);
    expect(success.value.single.displayName, '王小明');
  });

  test('legacy demo 只能通过独立 composition root 显式启用', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    final dependencies = LegacyDemoDependencies.create(
      databaseFactory: _SingleDatabaseFactory(database),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
    );

    final startup = await dependencies.start();

    expect(startup, isA<AppStartupReady>());
    final ready = startup as AppStartupReady;
    final controller = ready.controller;
    addTearDown(ready.identitySession.close);
    addTearDown(ready.appSession.close);
    addTearDown(controller.dispose);
    expect(controller.users, hasLength(5));
    expect(controller.records, hasLength(30));

    final login = await controller.loginDemoAccount('admin1');
    expect(login.success, isTrue);
  });
}

final class _SingleDatabaseFactory implements LocalDatabaseFactory {
  _SingleDatabaseFactory(this.database);

  final LocalDatabase database;

  @override
  LocalDatabase open() => database;
}

final class _FixedClock implements AppClock {
  const _FixedClock(this.value);

  final DateTime value;

  @override
  DateTime now() => value;
}

final class _ThrowingDatabaseFactory implements LocalDatabaseFactory {
  const _ThrowingDatabaseFactory();

  @override
  LocalDatabase open() => throw StateError('synthetic database failure');
}

final class _SequenceIdGenerator implements IdGenerator {
  var _next = 0;

  @override
  String next() => 'test-${_next++}';
}

final _target = PromotionTargetProfile(
  id: 'target-1',
  type: PromotionTargetType.person,
  displayName: '王小明',
  phone: null,
  email: null,
  createdAtUtc: DateTime.utc(2030, 1, 1),
);

final class _MemorySecureValueStore implements SecureValueStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

final class _TrackingManagementReportGateway
    implements ManagementReportGateway {
  var closeCount = 0;

  @override
  Future<void> close() async => closeCount++;

  @override
  Future<ManagementReportResult<ManagementAnalysisContextSnapshot>>
  loadContext() async =>
      const ManagementReportRejected(ManagementReportFailureCode.notConfigured);

  @override
  Future<ManagementReportResult<List<ManagementReportSnapshotSummary>>>
  listSnapshots(String projectId) async =>
      const ManagementReportRejected(ManagementReportFailureCode.notConfigured);

  @override
  Future<ManagementReportResult<ManagementReportSnapshot>> readSnapshot({
    required String projectId,
    required ManagementReportSnapshotSummary summary,
  }) async =>
      const ManagementReportRejected(ManagementReportFailureCode.notConfigured);

  @override
  Future<ManagementReportResult<ManagementReportExportArtifact>>
  exportSnapshot({
    required String projectId,
    required ManagementReportSnapshotSummary summary,
  }) async =>
      const ManagementReportRejected(ManagementReportFailureCode.notConfigured);

  @override
  Future<ManagementReportResult<ManagementAnalysisContextSnapshot>>
  selectContext(String projectId) async =>
      const ManagementReportRejected(ManagementReportFailureCode.notConfigured);
}

final class _TrackingCurrentCityReportGateway
    implements CurrentCityReportGateway {
  var closeCount = 0;

  @override
  Future<void> close() async => closeCount++;

  @override
  Future<CurrentCityReportResult<CurrentCityReportSnapshotDirectory>>
  listSnapshots(String projectId) async => const CurrentCityReportRejected(
    CurrentCityReportFailureCode.notConfigured,
  );

  @override
  Future<CurrentCityReportResult<CurrentCityReportSnapshot>> readSnapshot({
    required String projectId,
    required CurrentCityReportSnapshotSummary summary,
  }) async => const CurrentCityReportRejected(
    CurrentCityReportFailureCode.notConfigured,
  );
}

final class _TrackingManagementReportExportDelivery
    implements ManagementReportExportDelivery {
  @override
  bool get isAvailable => true;

  @override
  Future<ManagementReportExportDeliveryResult> requestDownload(
    ManagementReportExportArtifact artifact,
  ) async => const ManagementReportDownloadRequested();
}

final class _TrackingConsentOptInGateway
    implements PersonalFollowUpConsentOptInGateway {
  var closeCount = 0;

  @override
  Future<void> close() async => closeCount++;

  @override
  Future<PersonalFollowUpConsentOptInResult<PersonalFollowUpConsentOptInState>>
  load() async => const PersonalFollowUpConsentOptInRejected(
    PersonalFollowUpConsentOptInFailureCode.notConfigured,
  );

  @override
  Future<
    PersonalFollowUpConsentOptInResult<
      PersonalFollowUpConsentOptInConfiguration
    >
  >
  configure({
    required int expectedVersion,
    required bool enabled,
    required String requestId,
  }) async => const PersonalFollowUpConsentOptInRejected(
    PersonalFollowUpConsentOptInFailureCode.notConfigured,
  );
}

final class _TrackingConsentRatioGateway
    implements PersonalFollowUpConsentRatioGateway {
  var closeCount = 0;

  @override
  Future<void> close() async => closeCount++;

  @override
  Future<PersonalFollowUpConsentRatioGatewayResult> load({
    required String projectId,
    required DateTime fromUtc,
    required DateTime untilUtc,
  }) async => const PersonalFollowUpConsentRatioGatewayRejected(
    PersonalFollowUpConsentRatioFailureCode.notConfigured,
  );
}

final class _TrackingRelationshipStageChangeSummaryGateway
    implements PersonalRelationshipStageChangeSummaryGateway {
  var closeCount = 0;

  @override
  Future<void> close() async => closeCount++;

  @override
  Future<PersonalRelationshipStageChangeSummaryGatewayResult> load({
    required String projectId,
    required DateTime fromUtc,
    required DateTime untilUtc,
  }) async => const PersonalRelationshipStageChangeSummaryGatewayRejected(
    PersonalRelationshipStageChangeSummaryFailureCode.notConfigured,
  );
}

final class _TrackingCurrentRelationshipStageGateway
    implements CurrentRelationshipStageGateway {
  var closeCount = 0;

  @override
  Future<void> close() async => closeCount++;

  @override
  Future<CurrentRelationshipStageGatewayResult> load({
    required CurrentRelationshipStageScope scope,
  }) async => const CurrentRelationshipStageGatewayRejected(
    CurrentRelationshipStageGatewayFailureCode.notConfigured,
  );
}
