import 'dart:async';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/app/app_dependencies.dart';
import 'package:tongxingzhe_app/app/tongxingzhe_app.dart';
import 'package:tongxingzhe_app/app_session/session_context_gateway.dart';
import 'package:tongxingzhe_app/data/local_database.dart';
import 'package:tongxingzhe_app/data/local_database_factory.dart';
import 'package:tongxingzhe_app/device/device_time_zone.dart';
import 'package:tongxingzhe_app/features/contact_journal/contact_journal.dart';
import 'package:tongxingzhe_app/features/contact_journal/contact_models.dart';
import 'package:tongxingzhe_app/features/contact_metrics/current_relationship_stage.dart';
import 'package:tongxingzhe_app/features/contact_metrics/personal_follow_up_consent_ratio.dart';
import 'package:tongxingzhe_app/features/contact_metrics/relationship_stage_change_summary.dart';
import 'package:tongxingzhe_app/foundation/runtime_values.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/management_reports/current_city_report_gateway.dart';
import 'package:tongxingzhe_app/management_reports/follow_up_consent_ratio_report_gateway.dart';
import 'package:tongxingzhe_app/management_reports/interest_report_gateway.dart';
import 'package:tongxingzhe_app/management_reports/management_report_gateway.dart';
import 'package:tongxingzhe_app/management_reports/original_region_report_gateway.dart';
import 'package:tongxingzhe_app/platform/platform_capabilities.dart';
import 'package:tongxingzhe_app/project_settings/personal_follow_up_consent_opt_in.dart';
import 'package:tongxingzhe_app/questionnaires/questionnaire_contract.dart';
import 'package:tongxingzhe_app/regions/contact_region_resolver.dart';
import 'package:tongxingzhe_app/regions/region_catalog.dart';
import 'package:tongxingzhe_app/regions/region_models.dart';
import 'package:tongxingzhe_app/services/location_service.dart';
import 'package:tongxingzhe_app/sync/sync_models.dart';
import 'package:tongxingzhe_app/sync/sync_transport.dart';

import '../support/fake_identity_session.dart';
import '../support/fake_platform_capabilities.dart';
import '../support/fake_session_context_gateway.dart';

void main() {
  testWidgets('启动尚未完成时移除 App 仍关闭后来取得的报告 gateway', (tester) async {
    final database = LocalDatabase(NativeDatabase.memory());
    final startupGate = _BlockingPlatformCapabilitiesProvider();
    final gateway = _TrackingFollowUpConsentRatioReportGateway();
    var builderCalls = 0;
    final dependencies = AppDependencies(
      databaseFactory: _SingleDatabaseFactory(database),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(FakeIdentitySession()),
      sessionContextGateway: FakeSessionContextGateway(),
      platformCapabilitiesProvider: startupGate,
      followUpConsentRatioReportGatewayBuilder: (_) {
        builderCalls++;
        return gateway;
      },
    );
    addTearDown(database.close);

    await tester.pumpWidget(TongxingzheApp(dependencies: dependencies));
    await tester.pump();
    expect(startupGate.loadCalls, 1);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    startupGate.complete();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(builderCalls, 1);
    expect(gateway.closeCount, 1);
  });

  test('deferred 后续联系同意占比 gateway 不触网且不冒充其他报告类型', () async {
    const gateway = DeferredFollowUpConsentRatioReportGateway();

    final directory = await gateway.listSnapshots(
      '33333333-3333-4333-8333-333333333333',
    );
    final detail = await gateway.readSnapshot(
      projectId: '33333333-3333-4333-8333-333333333333',
      summary: FollowUpConsentRatioReportSnapshotSummary(
        snapshotId: '55555555-5555-4555-8555-555555555555',
        reportId: 'management_follow_up_consent_ratio',
        reportVersion: 1,
        reportingTimeZone: 'UTC',
        dataCutoffUtc: DateTime.utc(2030, 1, 1),
        releasedAtUtc: DateTime.utc(2030, 1, 2),
      ),
    );

    expect(directory, isA<FollowUpConsentRatioReportRejected>());
    expect(
      (directory as FollowUpConsentRatioReportRejected).code,
      FollowUpConsentRatioReportFailureCode.notConfigured,
    );
    expect(detail, isA<FollowUpConsentRatioReportRejected>());
    expect(
      (detail as FollowUpConsentRatioReportRejected).code,
      FollowUpConsentRatioReportFailureCode.notConfigured,
    );
    expect(gateway, isA<FollowUpConsentRatioReportGateway>());
    expect(gateway, isNot(isA<CurrentCityReportGateway>()));
    expect(gateway, isNot(isA<InterestReportGateway>()));
    expect(gateway, isNot(isA<ManagementReportGateway>()));
    expect(gateway, isNot(isA<PersonalFollowUpConsentRatioGateway>()));
  });

  testWidgets('移除 TongxingzheApp 后关闭后续联系同意占比报告 gateway 恰好一次', (tester) async {
    final database = LocalDatabase(NativeDatabase.memory());
    final identity = FakeIdentitySession(
      initial: IdentitySnapshot(
        stage: IdentityStage.signedIn,
        principal: const IdentityPrincipal(
          externalSubject: 'external-subject-not-an-app-user-id',
          email: 'person@example.test',
        ),
        expiresAt: DateTime.utc(2030, 1, 2, 4, 4),
      ),
    );
    final gateway = _TrackingFollowUpConsentRatioReportGateway();
    final dependencies = AppDependencies(
      databaseFactory: _SingleDatabaseFactory(database),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(identity),
      sessionContextGateway: FakeSessionContextGateway(),
      platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
      questionnaireRemoteSourceBuilder: (_) =>
          const _EmptyPublishedQuestionnaireSource(),
      followUpConsentRatioReportGatewayBuilder: (_) => gateway,
      timeZoneProvider: const _FakeTimeZoneProvider('America/Chicago'),
    );
    addTearDown(database.close);

    await tester.pumpWidget(TongxingzheApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    expect(find.text('个人空间 → 我的推广项目'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(gateway.closeCount, 1);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(gateway.closeCount, 1);
  });

  testWidgets('可信上下文进入四项主框架并显示当前推广项目', (tester) async {
    final database = LocalDatabase(NativeDatabase.memory());
    final identity = FakeIdentitySession(
      initial: IdentitySnapshot(
        stage: IdentityStage.signedIn,
        principal: const IdentityPrincipal(
          externalSubject: 'external-subject-not-an-app-user-id',
          email: 'person@example.test',
        ),
        expiresAt: DateTime.utc(2030, 1, 2, 4, 4),
      ),
    );
    final ratioGateway = _ReadyConsentRatioGateway();
    final stageChangeGateway = _ReadyRelationshipStageChangeSummaryGateway();
    final currentCityGateway = _TrackingCurrentCityReportGateway();
    final interestGateway = _TrackingInterestReportGateway();
    final originalRegionGateway = _TrackingOriginalRegionReportGateway();
    final dependencies = AppDependencies(
      databaseFactory: _SingleDatabaseFactory(database),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(identity),
      sessionContextGateway: FakeSessionContextGateway(),
      platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
      questionnaireRemoteSourceBuilder: (_) =>
          const _EmptyPublishedQuestionnaireSource(),
      managementReportGatewayBuilder: (_) =>
          const _EmptyManagementReportGateway(),
      currentCityReportGatewayBuilder: (_) => currentCityGateway,
      interestReportGatewayBuilder: (_) => interestGateway,
      originalRegionReportGatewayBuilder: (_) => originalRegionGateway,
      currentRelationshipStageGatewayBuilder: (_) =>
          const _OneRelationshipStageGateway(),
      personalFollowUpConsentRatioGatewayBuilder: (_) => ratioGateway,
      personalRelationshipStageChangeSummaryGatewayBuilder: (_) =>
          stageChangeGateway,
      timeZoneProvider: const _FakeTimeZoneProvider('America/Chicago'),
    );

    await tester.pumpWidget(TongxingzheApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    addTearDown(database.close);

    expect(find.text('个人空间 → 我的推广项目'), findsOneWidget);
    expect(find.text('今日'), findsWidgets);
    expect(find.text('接触'), findsOneWidget);
    expect(find.text('对象'), findsOneWidget);
    expect(find.text('分析'), findsOneWidget);
    expect(find.text('记录接触'), findsOneWidget);
    expect(find.text('正式认证尚未配置'), findsNothing);

    await tester.tap(find.text('分析'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('current-relationship-stage-panel')),
      300,
    );
    await tester.pumpAndSettle();
    expect(find.text('当前关系阶段'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('personal-follow-up-consent-ratio-panel')),
      300,
    );
    await tester.pumpAndSettle();
    expect(find.text('明确同意：2 / 3（66.67%）'), findsOneWidget);
    expect(ratioGateway.calls, hasLength(1));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('relationship-stage-change-summary-panel')),
      300,
    );
    await tester.pumpAndSettle();
    expect(find.text('阶段变更事件：5 次'), findsOneWidget);
    expect(find.text('上升事件：3 次'), findsOneWidget);
    expect(find.text('下降事件：2 次'), findsOneWidget);
    expect(find.text('发生过变更的去重关系：4 个对象 × 项目关系'), findsOneWidget);
    expect(stageChangeGateway.calls, hasLength(1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(ratioGateway.calls, hasLength(2));
    expect(stageChangeGateway.calls, hasLength(2));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('management-report-view')),
      -300,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('management-report-view')));
    await tester.pumpAndSettle();
    expect(find.text('没有可读取管理报告的项目。'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(currentCityGateway.closeCount, 1);
    expect(interestGateway.closeCount, 1);
    expect(originalRegionGateway.closeCount, 1);
  });

  testWidgets('占比服务失败时最近七日本地事实仍可读', (tester) async {
    final database = LocalDatabase(NativeDatabase.memory());
    final semantics = tester.ensureSemantics();
    final identity = FakeIdentitySession(
      initial: IdentitySnapshot(
        stage: IdentityStage.signedIn,
        principal: const IdentityPrincipal(
          externalSubject: 'external-subject-not-an-app-user-id',
          email: 'person@example.test',
        ),
        expiresAt: DateTime.utc(2030, 1, 2, 4, 4),
      ),
    );
    final dependencies = AppDependencies(
      databaseFactory: _SingleDatabaseFactory(database),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(identity),
      sessionContextGateway: FakeSessionContextGateway(),
      platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
      questionnaireRemoteSourceBuilder: (_) =>
          const _EmptyPublishedQuestionnaireSource(),
      currentRelationshipStageGatewayBuilder: (_) =>
          const _OneRelationshipStageGateway(),
      personalFollowUpConsentRatioGatewayBuilder: (_) =>
          const _RejectedConsentRatioGateway(),
      personalRelationshipStageChangeSummaryGatewayBuilder: (_) =>
          const _RejectedRelationshipStageChangeSummaryGateway(),
      timeZoneProvider: const _FakeTimeZoneProvider('America/Chicago'),
    );

    await tester.pumpWidget(TongxingzheApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    addTearDown(database.close);

    await tester.tap(find.text('分析'));
    await tester.pumpAndSettle();

    expect(find.text('最近七日接触场次 0'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('personal-follow-up-consent-ratio-panel')),
      300,
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey('personal-follow-up-consent-ratio-panel'),
        ),
        matching: find.textContaining('无法连接分析服务'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('personal-consent-ratio-retry')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('relationship-stage-change-summary-panel')),
      300,
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey('relationship-stage-change-summary-panel'),
        ),
        matching: find.text('无法连接分析服务。请检查网络后重试。'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('relationship-stage-change-retry')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('current-relationship-stage-panel')),
      -300,
    );
    await tester.pumpAndSettle();
    expect(find.text('当前关系阶段'), findsOneWidget);
    expect(find.bySemanticsLabel('关系阶段 2：1 个对象项目关系'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('最近七日接触场次 0'), -300);
    await tester.pumpAndSettle();
    expect(find.text('最近七日接触场次 0'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('本地最近七日仍在载入时远端阶段变更独立显示', (tester) async {
    final database = LocalDatabase(NativeDatabase.memory());
    final identity = FakeIdentitySession(
      initial: IdentitySnapshot(
        stage: IdentityStage.signedIn,
        principal: const IdentityPrincipal(
          externalSubject: 'external-subject-not-an-app-user-id',
          email: 'person@example.test',
        ),
        expiresAt: DateTime.utc(2030, 1, 2, 4, 4),
      ),
    );
    final transport = _BlockingPullSyncTransport();
    final stageChangeGateway = _ReadyRelationshipStageChangeSummaryGateway();
    final dependencies = AppDependencies(
      databaseFactory: _SingleDatabaseFactory(database),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(identity),
      sessionContextGateway: FakeSessionContextGateway(),
      platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
      questionnaireRemoteSourceBuilder: (_) =>
          const _EmptyPublishedQuestionnaireSource(),
      syncTransportBuilder: (_) => transport,
      personalRelationshipStageChangeSummaryGatewayBuilder: (_) =>
          stageChangeGateway,
      timeZoneProvider: const _FakeTimeZoneProvider('America/Chicago'),
    );

    await tester.pumpWidget(TongxingzheApp(dependencies: dependencies));
    addTearDown(database.close);
    for (
      var attempt = 0;
      attempt < 20 && find.text('分析').evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tester.tap(find.text('分析'));
    for (
      var attempt = 0;
      attempt < 20 && stageChangeGateway.calls.isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(transport.pullCalls, 1);
    expect(stageChangeGateway.calls, hasLength(1));
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('relationship-stage-change-summary-panel')),
      300,
    );
    await tester.pump();
    expect(find.text('阶段变更事件：5 次'), findsOneWidget);

    transport.completePull(
      const SyncPullSucceeded(
        SyncPullBatch(changes: [], nextCursor: 'initial-cursor'),
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('App 恢复与同步完成分别刷新个人阶段变更', (tester) async {
    final database = LocalDatabase(NativeDatabase.memory());
    final identity = FakeIdentitySession(
      initial: IdentitySnapshot(
        stage: IdentityStage.signedIn,
        principal: const IdentityPrincipal(
          externalSubject: 'external-subject-not-an-app-user-id',
          email: 'person@example.test',
        ),
        expiresAt: DateTime.utc(2030, 1, 2, 4, 4),
      ),
    );
    final transport = _CompletingSyncTransport();
    final stageChangeGateway = _ReadyRelationshipStageChangeSummaryGateway();
    final clock = _FixedClock(DateTime.utc(2030, 1, 2, 3, 4));
    final dependencies = AppDependencies(
      databaseFactory: _SingleDatabaseFactory(database),
      clock: clock,
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(identity),
      sessionContextGateway: FakeSessionContextGateway(),
      platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
      questionnaireRemoteSourceBuilder: (_) =>
          const _EmptyPublishedQuestionnaireSource(),
      syncTransportBuilder: (_) => transport,
      personalRelationshipStageChangeSummaryGatewayBuilder: (_) =>
          stageChangeGateway,
      timeZoneProvider: const _FakeTimeZoneProvider('America/Chicago'),
    );

    await tester.pumpWidget(TongxingzheApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    addTearDown(database.close);

    await tester.tap(find.text('分析'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('relationship-stage-change-summary-panel')),
      300,
    );
    await tester.pumpAndSettle();
    expect(stageChangeGateway.calls, hasLength(1));

    await ContactJournal(
      database: database,
      clock: clock,
      idGenerator: _FixedIds([
        'resume-contact',
        'resume-revision',
        'resume-command',
      ]),
    ).submitAnonymousContact(
      AnonymousContactSubmission(
        appUserId: syntheticSessionContext.appUserId,
        workspaceId: syntheticSessionContext.workspace.id,
        projectId: syntheticSessionContext.project.id,
        questionnaireVersionId: syntheticSessionContext.questionnaireVersion.id,
        deviceId: 'resume-device',
        occurredAtUtc: DateTime.utc(2030, 1, 2, 3),
        occurredTimeZone: 'America/Chicago',
        channel: ContactChannel.videoCall,
        location: const NotApplicableContactLocation(),
        reachCount: 1,
        interestLevel: 2,
      ),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    for (
      var attempt = 0;
      attempt < 20 && transport.commands.isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(transport.commands, hasLength(1));
    expect(stageChangeGateway.calls, hasLength(2));

    transport.completePush(
      const SyncPushAccepted(serverCursor: 'test-cursor-1'),
    );
    await tester.pumpAndSettle();

    expect(stageChangeGateway.calls, hasLength(3));
  });

  testWidgets('项目菜单切换可信项目并采用该项目的问卷上下文', (tester) async {
    final database = LocalDatabase(NativeDatabase.memory());
    final identity = FakeIdentitySession(
      initial: IdentitySnapshot(
        stage: IdentityStage.signedIn,
        principal: const IdentityPrincipal(
          externalSubject: 'external-subject-not-an-app-user-id',
          email: 'person@example.test',
        ),
        expiresAt: DateTime.utc(2030, 1, 2, 4, 4),
      ),
    );
    final contextGateway = FakeSessionContextGateway(
      availableContexts: const [
        syntheticSessionContext,
        syntheticSecondSessionContext,
      ],
      selectedContexts: const {
        '55555555-5555-4555-8555-555555555555': syntheticSecondSessionContext,
      },
    );
    final dependencies = AppDependencies(
      databaseFactory: _SingleDatabaseFactory(database),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(identity),
      sessionContextGateway: contextGateway,
      platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
      questionnaireRemoteSourceBuilder: (_) =>
          const _EmptyPublishedQuestionnaireSource(),
      timeZoneProvider: const _FakeTimeZoneProvider('America/Chicago'),
    );

    await tester.pumpWidget(TongxingzheApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    addTearDown(database.close);

    await tester.tap(find.byKey(const ValueKey('project-context-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('校园推广').last);
    await tester.pumpAndSettle();

    expect(contextGateway.selectedProjectIds, [
      syntheticSecondSessionContext.project.id,
    ]);
    expect(find.text('个人空间 → 校园推广'), findsOneWidget);

    await tester.tap(find.text('记录接触'));
    await tester.pumpAndSettle();
    expect(find.text('问卷版本 2'), findsOneWidget);
  });

  testWidgets('个人项目菜单打开后续联系同意占比设置且不会自动启用', (tester) async {
    final database = LocalDatabase(NativeDatabase.memory());
    final identity = FakeIdentitySession(
      initial: IdentitySnapshot(
        stage: IdentityStage.signedIn,
        principal: const IdentityPrincipal(
          externalSubject: 'external-subject-not-an-app-user-id',
          email: 'person@example.test',
        ),
        expiresAt: DateTime.utc(2030, 1, 2, 4, 4),
      ),
    );
    final gateway = _ConsentOptInGateway(
      projectId: syntheticSessionContext.project.id,
    );
    final ratioGateway = _ReadyConsentRatioGateway();
    final stageChangeGateway = _ReadyRelationshipStageChangeSummaryGateway();
    final dependencies = AppDependencies(
      databaseFactory: _SingleDatabaseFactory(database),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(identity),
      sessionContextGateway: FakeSessionContextGateway(),
      platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
      personalFollowUpConsentOptInGatewayBuilder: (_, _) => gateway,
      personalFollowUpConsentRatioGatewayBuilder: (_) => ratioGateway,
      personalRelationshipStageChangeSummaryGatewayBuilder: (_) =>
          stageChangeGateway,
      timeZoneProvider: const _FakeTimeZoneProvider('America/Chicago'),
    );

    await tester.pumpWidget(TongxingzheApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    addTearDown(database.close);
    final semantics = tester.ensureSemantics();

    await tester.tap(find.text('分析'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('personal-follow-up-consent-ratio-panel')),
      300,
    );
    await tester.pumpAndSettle();
    expect(ratioGateway.calls, hasLength(1));
    expect(stageChangeGateway.calls, hasLength(1));

    final projectMenu = find.byKey(const ValueKey('project-context-menu'));
    final projectMenuSemantics = tester
        .getSemantics(find.byTooltip('切换推广项目'))
        .getSemanticsData();
    expect(projectMenuSemantics.flagsCollection.isButton, isTrue);
    expect(projectMenuSemantics.tooltip, '切换推广项目');

    final menuButton = find.byTooltip('切换推广项目');
    await _focusByTabbing(tester, menuButton);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    final settingsItem = find.byKey(
      const ValueKey('project-settings-menu-item'),
    );
    expect(settingsItem, findsOneWidget);
    final settingsItemSemantics = tester
        .getSemantics(settingsItem)
        .getSemanticsData();
    expect(settingsItemSemantics.flagsCollection.isButton, isTrue);
    expect(settingsItemSemantics.label, contains('项目设置'));

    await _focusByTabbing(tester, settingsItem);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('后续联系同意占比'), findsOneWidget);
    expect(find.text('当前状态：从未启用'), findsOneWidget);
    expect(gateway.configureCalls, 0);

    await _focusByTabbing(
      tester,
      find.byKey(const ValueKey('consent-opt-in-close')),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('consent-opt-in-close')), findsNothing);
    expect(find.text('当前状态：从未启用'), findsNothing);
    expect(_containsPrimaryFocus(tester, projectMenu), isTrue);
    expect(ratioGateway.calls, hasLength(2));
    expect(stageChangeGateway.calls, hasLength(2));
    semantics.dispose();
  });

  testWidgets('组织项目菜单不显示个人项目开关入口', (tester) async {
    final database = LocalDatabase(NativeDatabase.memory());
    final identity = FakeIdentitySession(
      initial: IdentitySnapshot(
        stage: IdentityStage.signedIn,
        principal: const IdentityPrincipal(
          externalSubject: 'external-subject-not-an-app-user-id',
          email: 'person@example.test',
        ),
        expiresAt: DateTime.utc(2030, 1, 2, 4, 4),
      ),
    );
    final ratioGateway = _ReadyConsentRatioGateway();
    final stageChangeGateway = _ReadyRelationshipStageChangeSummaryGateway();
    final dependencies = AppDependencies(
      databaseFactory: _SingleDatabaseFactory(database),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(identity),
      sessionContextGateway: FakeSessionContextGateway(
        context: _organizationSessionContext,
        availableContexts: const [_organizationSessionContext],
      ),
      platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
      personalFollowUpConsentRatioGatewayBuilder: (_) => ratioGateway,
      personalRelationshipStageChangeSummaryGatewayBuilder: (_) =>
          stageChangeGateway,
      timeZoneProvider: const _FakeTimeZoneProvider('America/Chicago'),
    );

    await tester.pumpWidget(TongxingzheApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    addTearDown(database.close);

    await tester.tap(find.byKey(const ValueKey('project-context-menu')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('project-settings-menu-item')),
      findsNothing,
    );
    expect(find.text('项目设置'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.text('分析'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('personal-follow-up-consent-ratio-panel')),
      findsNothing,
    );
    expect(ratioGateway.calls, isEmpty);
    expect(
      find.byKey(const ValueKey('relationship-stage-change-summary-panel')),
      findsNothing,
    );
    expect(stageChangeGateway.calls, isEmpty);
  });

  testWidgets('项目菜单创建个人推广项目并立即切换', (tester) async {
    final database = LocalDatabase(NativeDatabase.memory());
    final identity = FakeIdentitySession(
      initial: IdentitySnapshot(
        stage: IdentityStage.signedIn,
        principal: const IdentityPrincipal(
          externalSubject: 'external-subject-not-an-app-user-id',
          email: 'person@example.test',
        ),
        expiresAt: DateTime.utc(2030, 1, 2, 4, 4),
      ),
    );
    final contextGateway = FakeSessionContextGateway(
      createdContexts: const {'社区推广': syntheticSecondSessionContext},
    );
    final dependencies = AppDependencies(
      databaseFactory: _SingleDatabaseFactory(database),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(identity),
      sessionContextGateway: contextGateway,
      platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
      questionnaireRemoteSourceBuilder: (_) =>
          const _EmptyPublishedQuestionnaireSource(),
      timeZoneProvider: const _FakeTimeZoneProvider('America/Chicago'),
    );

    await tester.pumpWidget(TongxingzheApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    addTearDown(database.close);

    await tester.tap(find.byKey(const ValueKey('project-context-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('创建推广项目'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('new-project-name')),
      '社区推广',
    );
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();

    expect(contextGateway.createdProjectNames, ['社区推广']);
    expect(find.text('个人空间 → 校园推广'), findsOneWidget);
  });

  testWidgets('项目切换被拒绝时留在原项目并显示稳定提示', (tester) async {
    final database = LocalDatabase(NativeDatabase.memory());
    final identity = FakeIdentitySession(
      initial: IdentitySnapshot(
        stage: IdentityStage.signedIn,
        principal: const IdentityPrincipal(
          externalSubject: 'external-subject-not-an-app-user-id',
          email: 'person@example.test',
        ),
        expiresAt: DateTime.utc(2030, 1, 2, 4, 4),
      ),
    );
    final contextGateway = FakeSessionContextGateway(
      availableContexts: const [
        syntheticSessionContext,
        syntheticSecondSessionContext,
      ],
    );
    final dependencies = AppDependencies(
      databaseFactory: _SingleDatabaseFactory(database),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(identity),
      sessionContextGateway: contextGateway,
      platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
      questionnaireRemoteSourceBuilder: (_) =>
          const _EmptyPublishedQuestionnaireSource(),
      timeZoneProvider: const _FakeTimeZoneProvider('America/Chicago'),
    );

    await tester.pumpWidget(TongxingzheApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    addTearDown(database.close);

    // 启动后再拒绝，才能只覆盖用户发起的项目切换失败。
    contextGateway.rejectWith = SessionContextFailureCode.serverRejected;
    await tester.tap(find.byKey(const ValueKey('project-context-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('校园推广').last);
    await tester.pumpAndSettle();

    expect(find.text('个人空间 → 我的推广项目'), findsOneWidget);
    expect(find.text('无法切换或创建推广项目，请重试。'), findsOneWidget);
  });

  testWidgets('跨项目草稿显示原项目名称并在打开前恢复原上下文', (tester) async {
    final database = LocalDatabase(NativeDatabase.memory());
    final identity = FakeIdentitySession(
      initial: IdentitySnapshot(
        stage: IdentityStage.signedIn,
        principal: const IdentityPrincipal(
          externalSubject: 'external-subject-not-an-app-user-id',
          email: 'person@example.test',
        ),
        expiresAt: DateTime.utc(2030, 1, 2, 4, 4),
      ),
    );
    final contextGateway = FakeSessionContextGateway(
      availableContexts: const [
        syntheticSessionContext,
        syntheticSecondSessionContext,
      ],
      selectedContexts: const {
        '33333333-3333-4333-8333-333333333333': syntheticSessionContext,
        '55555555-5555-4555-8555-555555555555': syntheticSecondSessionContext,
      },
    );
    final dependencies = AppDependencies(
      databaseFactory: _SingleDatabaseFactory(database),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(identity),
      sessionContextGateway: contextGateway,
      platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
      questionnaireRemoteSourceBuilder: (_) =>
          const _EmptyPublishedQuestionnaireSource(),
      timeZoneProvider: const _FakeTimeZoneProvider('America/Chicago'),
    );

    await tester.pumpWidget(TongxingzheApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    addTearDown(database.close);

    await tester.tap(find.text('记录接触'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('视频通话'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('project-context-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('校园推广').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('项目：我的推广项目'), findsOneWidget);
    await tester.tap(find.text('视频通话'));
    await tester.pumpAndSettle();

    expect(contextGateway.selectedProjectIds, [
      syntheticSecondSessionContext.project.id,
      syntheticSessionContext.project.id,
    ]);
    expect(find.text('问卷版本 1'), findsOneWidget);
  });

  testWidgets('新接触显示设备时区和当前发布问卷', (tester) async {
    final database = LocalDatabase(NativeDatabase.memory());
    final identity = FakeIdentitySession(
      initial: IdentitySnapshot(
        stage: IdentityStage.signedIn,
        principal: const IdentityPrincipal(
          externalSubject: 'external-subject-not-an-app-user-id',
          email: 'person@example.test',
        ),
        expiresAt: DateTime.utc(2030, 1, 2, 4, 4),
      ),
    );
    final dependencies = AppDependencies(
      databaseFactory: _SingleDatabaseFactory(database),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(identity),
      sessionContextGateway: FakeSessionContextGateway(),
      platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
      questionnaireRemoteSourceBuilder: (_) =>
          const _OneQuestionPublishedSource(),
      timeZoneProvider: const _FakeTimeZoneProvider('America/Chicago'),
    );

    await tester.pumpWidget(TongxingzheApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    addTearDown(database.close);

    await tester.tap(find.text('记录接触'));
    await tester.pumpAndSettle();

    expect(find.textContaining('America/Chicago'), findsOneWidget);
    expect(find.byKey(const ValueKey('edit-occurred-at')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('是否同意后续联系？'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('是否同意后续联系？'), findsOneWidget);
    expect(find.textContaining('不应用来代替推广对象姓名'), findsOneWidget);
  });

  testWidgets('稳定地址可直达、跟随导航并保留表单返回语义', (tester) async {
    final database = LocalDatabase(NativeDatabase.memory());
    final identity = FakeIdentitySession(
      initial: IdentitySnapshot(
        stage: IdentityStage.signedIn,
        principal: const IdentityPrincipal(
          externalSubject: 'external-subject-not-an-app-user-id',
          email: 'person@example.test',
        ),
        expiresAt: DateTime.utc(2030, 1, 2, 4, 4),
      ),
    );
    final routeInformationProvider = PlatformRouteInformationProvider(
      initialRouteInformation: RouteInformation(uri: Uri.parse('/analysis')),
    );
    final dependencies = AppDependencies(
      databaseFactory: _SingleDatabaseFactory(database),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(identity),
      sessionContextGateway: FakeSessionContextGateway(),
      platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
      questionnaireRemoteSourceBuilder: (_) =>
          const _EmptyPublishedQuestionnaireSource(),
      timeZoneProvider: const _FakeTimeZoneProvider('America/Chicago'),
    );

    await tester.pumpWidget(
      TongxingzheApp(
        dependencies: dependencies,
        routeInformationProvider: routeInformationProvider,
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(database.close);
    addTearDown(routeInformationProvider.dispose);

    expect(find.text('最近七日接触场次 0'), findsOneWidget);
    expect(find.textContaining('个人数据'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('personal-interest-ratio-trend-panel')),
      findsOneWidget,
    );
    await _scrollUntilBuilt(
      tester,
      find.text('兴趣 3–4（明确愿意继续或主动提出／落实下一步）：0 / 0（暂无可计算比例）'),
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.textContaining('0 / 0（暂无可计算比例）'), findsWidgets);
    expect(
      find.text('兴趣 3–4（明确愿意继续或主动提出／落实下一步）：0 / 0（暂无可计算比例）'),
      findsOneWidget,
    );
    expect(find.text('兴趣 0（明确拒绝）：0 / 0（暂无可计算比例）'), findsOneWidget);
    expect(find.textContaining('比例覆盖'), findsWidgets);
    await _scrollUntilBuilt(
      tester,
      find.text('暂无中位等级'),
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('暂无中位等级'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('对象当次反应分布'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    final emptyTargetResponseRow = find.text('反应 2：0 条已填关联；0 / 0（暂无可计算比例）');
    await tester.scrollUntilVisible(
      emptyTargetResponseRow,
      80,
      scrollable: find.byType(Scrollable).last,
    );
    expect(emptyTargetResponseRow, findsOneWidget);
    final emptyTargetResponseCoverage = find.textContaining(
      '已填 0 条、未知 0、拒答 0、不适用 0、未回答 0、候选内排除 0 条对象关联',
    );
    await tester.scrollUntilVisible(
      emptyTargetResponseCoverage,
      80,
      scrollable: find.byType(Scrollable).last,
    );
    expect(emptyTargetResponseCoverage, findsOneWidget);
    expect(routeInformationProvider.value.uri.path, '/analysis');

    await tester.tap(find.text('接触'));
    await tester.pumpAndSettle();
    expect(routeInformationProvider.value.uri.path, '/contacts');

    await tester.tap(find.text('记录接触'));
    await tester.pumpAndSettle();
    expect(routeInformationProvider.value.uri.path, '/contacts/new');

    await tester.tap(find.text('视频通话'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(routeInformationProvider.value.uri.path, '/contacts');
    expect(find.text('草稿 (1)'), findsOneWidget);

    await tester.tap(find.text('记录接触'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('语音通话'));
    await tester.pump();

    await tester.binding.handlePushRoute('/analysis');
    await tester.pumpAndSettle();

    expect(routeInformationProvider.value.uri.path, '/analysis');
    expect(find.text('最近七日接触场次 0'), findsOneWidget);
    await tester.tap(find.text('接触'));
    await tester.pumpAndSettle();
    expect(find.text('草稿 (2)'), findsOneWidget);
  });

  testWidgets('兴趣比例在 320 宽和 200% 文字下可滚动且分组标题可识别', (tester) async {
    final semantics = tester.ensureSemantics();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final database = LocalDatabase(NativeDatabase.memory());
    final identity = FakeIdentitySession(
      initial: IdentitySnapshot(
        stage: IdentityStage.signedIn,
        principal: const IdentityPrincipal(
          externalSubject: 'external-subject-not-an-app-user-id',
          email: 'person@example.test',
        ),
        expiresAt: DateTime.utc(2030, 1, 2, 4, 4),
      ),
    );
    final routeInformationProvider = PlatformRouteInformationProvider(
      initialRouteInformation: RouteInformation(uri: Uri.parse('/analysis')),
    );
    final dependencies = AppDependencies(
      databaseFactory: _SingleDatabaseFactory(database),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(identity),
      sessionContextGateway: FakeSessionContextGateway(),
      platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
      questionnaireRemoteSourceBuilder: (_) =>
          const _EmptyPublishedQuestionnaireSource(),
      timeZoneProvider: const _FakeTimeZoneProvider('America/Chicago'),
    );

    await tester.pumpWidget(
      TongxingzheApp(
        dependencies: dependencies,
        routeInformationProvider: routeInformationProvider,
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(database.close);
    addTearDown(routeInformationProvider.dispose);

    final heading = find.text('单次兴趣分布');
    await _scrollUntilBuilt(
      tester,
      heading,
      scrollable: find.byType(Scrollable).last,
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getSemantics(heading).getSemanticsData().flagsCollection.isHeader,
      isTrue,
    );
    final subsetHeading = find.text('兴趣 3–4 与 0 占比');
    await tester.scrollUntilVisible(
      subsetHeading,
      120,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      tester
          .getSemantics(subsetHeading)
          .getSemanticsData()
          .flagsCollection
          .isHeader,
      isTrue,
    );
    expect(find.textContaining('0 / 0（暂无可计算比例）'), findsWidgets);
    final targetResponseHeading = find.text('对象当次反应分布');
    await tester.scrollUntilVisible(
      targetResponseHeading,
      120,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      tester
          .getSemantics(targetResponseHeading)
          .getSemanticsData()
          .flagsCollection
          .isHeader,
      isTrue,
    );
    final emptyTargetMedian = find.text('暂无对象当次反应中位等级');
    await tester.scrollUntilVisible(
      emptyTargetMedian,
      80,
      scrollable: find.byType(Scrollable).last,
    );
    expect(emptyTargetMedian, findsOneWidget);
    final targetMedianHelp = find.textContaining('偶数条取较低的真实等级');
    await tester.scrollUntilVisible(
      targetMedianHelp,
      80,
      scrollable: find.byType(Scrollable).last,
    );
    expect(targetMedianHelp, findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('英文兴趣子集比例在 320 宽和 200% 文字下保留标题语义', (tester) async {
    final semantics = tester.ensureSemantics();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final database = LocalDatabase(NativeDatabase.memory());
    await database
        .into(database.dbAppSettings)
        .insert(const DbAppSetting(key: 'localeCode', value: 'en'));
    final identity = FakeIdentitySession(
      initial: IdentitySnapshot(
        stage: IdentityStage.signedIn,
        principal: const IdentityPrincipal(
          externalSubject: 'external-subject-not-an-app-user-id',
          email: 'person@example.test',
        ),
        expiresAt: DateTime.utc(2030, 1, 2, 4, 4),
      ),
    );
    final routeInformationProvider = PlatformRouteInformationProvider(
      initialRouteInformation: RouteInformation(uri: Uri.parse('/analysis')),
    );
    final dependencies = AppDependencies(
      databaseFactory: _SingleDatabaseFactory(database),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(identity),
      sessionContextGateway: FakeSessionContextGateway(),
      platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
      questionnaireRemoteSourceBuilder: (_) =>
          const _EmptyPublishedQuestionnaireSource(),
      timeZoneProvider: const _FakeTimeZoneProvider('America/Chicago'),
    );

    await tester.pumpWidget(
      TongxingzheApp(
        dependencies: dependencies,
        routeInformationProvider: routeInformationProvider,
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(database.close);
    addTearDown(routeInformationProvider.dispose);

    final heading = find.text('Interest 3–4 and 0 ratios');
    await _scrollUntilBuilt(
      tester,
      heading,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      tester.getSemantics(heading).getSemanticsData().flagsCollection.isHeader,
      isTrue,
    );
    final highRow = find.text(
      'Interest 3–4 (willing to continue or taking the next step): '
      '0 / 0 (No calculable percentage)',
    );
    await _scrollUntilBuilt(
      tester,
      highRow,
      scrollable: find.byType(Scrollable).last,
    );
    expect(highRow, findsOneWidget);
    final zeroRow = find.text(
      'Interest 0 (explicit refusal): 0 / 0 (No calculable percentage)',
    );
    await _scrollUntilBuilt(
      tester,
      zeroRow,
      scrollable: find.byType(Scrollable).last,
    );
    expect(zeroRow, findsOneWidget);
    final targetResponseHeading = find.text('Target response distribution');
    await _scrollUntilBuilt(
      tester,
      targetResponseHeading,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      tester
          .getSemantics(targetResponseHeading)
          .getSemanticsData()
          .flagsCollection
          .isHeader,
      isTrue,
    );
    final emptyTargetResponseRow = find.text(
      'Response 2: 0 answered links; 0 / 0 (No calculable percentage)',
    );
    await tester.scrollUntilVisible(
      emptyTargetResponseRow,
      80,
      scrollable: find.byType(Scrollable).last,
    );
    expect(emptyTargetResponseRow, findsOneWidget);
    final emptyTargetMedian = find.text('No target response median level yet');
    await tester.scrollUntilVisible(
      emptyTargetMedian,
      80,
      scrollable: find.byType(Scrollable).last,
    );
    expect(emptyTargetMedian, findsOneWidget);
    final targetMedianHelp = find.textContaining('lower observed level');
    await tester.scrollUntilVisible(
      targetMedianHelp,
      80,
      scrollable: find.byType(Scrollable).last,
    );
    expect(targetMedianHelp, findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('个人分析页显示对象反应关联分布并单列未填写', (tester) async {
    final database = LocalDatabase(NativeDatabase.memory());
    await _seedTargetResponseFacts(database);
    final identity = FakeIdentitySession(
      initial: IdentitySnapshot(
        stage: IdentityStage.signedIn,
        principal: const IdentityPrincipal(
          externalSubject: 'external-subject-not-an-app-user-id',
          email: 'person@example.test',
        ),
        expiresAt: DateTime.utc(2030, 1, 2, 4, 4),
      ),
    );
    final routeInformationProvider = PlatformRouteInformationProvider(
      initialRouteInformation: RouteInformation(uri: Uri.parse('/analysis')),
    );
    final dependencies = AppDependencies(
      databaseFactory: _SingleDatabaseFactory(database),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(identity),
      sessionContextGateway: FakeSessionContextGateway(),
      platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
      questionnaireRemoteSourceBuilder: (_) =>
          const _EmptyPublishedQuestionnaireSource(),
      timeZoneProvider: const _FakeTimeZoneProvider('America/Chicago'),
    );

    await tester.pumpWidget(
      TongxingzheApp(
        dependencies: dependencies,
        routeInformationProvider: routeInformationProvider,
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(database.close);
    addTearDown(routeInformationProvider.dispose);

    await tester.scrollUntilVisible(
      find.text('对象当次反应分布'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    final neutralRow = find.text('反应 2：1 条已填关联；1 / 2（50.00%）');
    await tester.scrollUntilVisible(
      neutralRow,
      80,
      scrollable: find.byType(Scrollable).last,
    );
    expect(neutralRow, findsOneWidget);
    final nextStepRow = find.text('反应 4：1 条已填关联；1 / 2（50.00%）');
    await tester.scrollUntilVisible(
      nextStepRow,
      80,
      scrollable: find.byType(Scrollable).last,
    );
    expect(nextStepRow, findsOneWidget);
    final coverage = find.textContaining(
      '已填 2 条、未知 0、拒答 0、不适用 0、未回答 1、候选内排除 0 条对象关联',
    );
    await tester.scrollUntilVisible(
      coverage,
      80,
      scrollable: find.byType(Scrollable).last,
    );
    expect(coverage, findsOneWidget);
    expect(find.textContaining('未回答不算反应 2'), findsOneWidget);
    final median = find.text('对象当次反应中位等级：2（2 条已填关联）');
    await tester.scrollUntilVisible(
      median,
      80,
      scrollable: find.byType(Scrollable).last,
    );
    expect(median, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('不存在的草稿地址显示可返回错误而不是永久加载', (tester) async {
    final database = LocalDatabase(NativeDatabase.memory());
    final identity = FakeIdentitySession(
      initial: IdentitySnapshot(
        stage: IdentityStage.signedIn,
        principal: const IdentityPrincipal(
          externalSubject: 'external-subject-not-an-app-user-id',
          email: 'person@example.test',
        ),
        expiresAt: DateTime.utc(2030, 1, 2, 4, 4),
      ),
    );
    final routeInformationProvider = PlatformRouteInformationProvider(
      initialRouteInformation: RouteInformation(
        uri: Uri.parse('/contacts/drafts/missing-draft'),
      ),
    );
    final dependencies = AppDependencies(
      databaseFactory: _SingleDatabaseFactory(database),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(identity),
      sessionContextGateway: FakeSessionContextGateway(),
      platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
      questionnaireRemoteSourceBuilder: (_) =>
          const _EmptyPublishedQuestionnaireSource(),
      timeZoneProvider: const _FakeTimeZoneProvider('America/Chicago'),
    );

    await tester.pumpWidget(
      TongxingzheApp(
        dependencies: dependencies,
        routeInformationProvider: routeInformationProvider,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    addTearDown(database.close);
    addTearDown(routeInformationProvider.dispose);

    expect(find.text('找不到这份草稿，或它不属于当前项目。'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(BackButton), findsOneWidget);
  });

  testWidgets('未登录用户用邮箱密码取得可信上下文后进入主框架', (tester) async {
    final database = LocalDatabase(NativeDatabase.memory());
    final identity = FakeIdentitySession();
    final dependencies = AppDependencies(
      databaseFactory: _SingleDatabaseFactory(database),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(identity),
      sessionContextGateway: FakeSessionContextGateway(),
      platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
      questionnaireRemoteSourceBuilder: (_) =>
          const _EmptyPublishedQuestionnaireSource(),
      timeZoneProvider: const _FakeTimeZoneProvider('America/Chicago'),
    );

    await tester.pumpWidget(TongxingzheApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    addTearDown(database.close);

    expect(find.byKey(const ValueKey('auth-email')), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-password')), findsOneWidget);
    expect(find.text('admin1'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('auth-email')),
      'person@example.test',
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-password')),
      'test-password',
    );
    await tester.tap(find.text('登录'));
    await tester.pumpAndSettle();

    expect(find.text('个人空间 → 我的推广项目'), findsOneWidget);
    expect(find.text('记录接触'), findsOneWidget);
  });

  testWidgets('可信上下文失败时关闭记录入口并允许退出登录', (tester) async {
    final database = LocalDatabase(NativeDatabase.memory());
    final identity = FakeIdentitySession(
      initial: IdentitySnapshot(
        stage: IdentityStage.signedIn,
        principal: const IdentityPrincipal(
          externalSubject: 'external-subject-not-an-app-user-id',
          email: 'person@example.test',
        ),
        expiresAt: DateTime.utc(2030, 1, 2, 4, 4),
      ),
    );
    final dependencies = AppDependencies(
      databaseFactory: _SingleDatabaseFactory(database),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(identity),
      sessionContextGateway: FakeSessionContextGateway(
        rejectWith: SessionContextFailureCode.unauthorized,
      ),
      platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
      questionnaireRemoteSourceBuilder: (_) =>
          const _EmptyPublishedQuestionnaireSource(),
      timeZoneProvider: const _FakeTimeZoneProvider('America/Chicago'),
    );

    await tester.pumpWidget(TongxingzheApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    addTearDown(database.close);

    expect(find.text('无法载入当前推广项目'), findsOneWidget);
    expect(find.text('记录接触'), findsNothing);

    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('auth-email')), findsOneWidget);
  });

  testWidgets('首次选择渠道后自动保存草稿并在接触页恢复列表', (tester) async {
    final database = LocalDatabase(NativeDatabase.memory());
    final identity = FakeIdentitySession(
      initial: IdentitySnapshot(
        stage: IdentityStage.signedIn,
        principal: const IdentityPrincipal(
          externalSubject: 'external-subject-not-an-app-user-id',
          email: 'person@example.test',
        ),
        expiresAt: DateTime.utc(2030, 1, 2, 4, 4),
      ),
    );
    final dependencies = AppDependencies(
      databaseFactory: _SingleDatabaseFactory(database),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(identity),
      sessionContextGateway: FakeSessionContextGateway(),
      platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
      questionnaireRemoteSourceBuilder: (_) =>
          const _EmptyPublishedQuestionnaireSource(),
      timeZoneProvider: const _FakeTimeZoneProvider('America/Chicago'),
    );

    await tester.pumpWidget(TongxingzheApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    addTearDown(database.close);

    await tester.tap(find.text('记录接触'));
    await tester.pumpAndSettle();

    expect(find.text('问卷版本 1'), findsOneWidget);
    expect(find.text('选择接触渠道'), findsOneWidget);

    await tester.tap(find.text('视频通话'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('已保存'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('草稿 (1)'), findsOneWidget);
    expect(find.text('视频通话'), findsOneWidget);
    expect(find.textContaining('项目：我的推广项目'), findsOneWidget);
    expect(find.textContaining('发生：2030-01-02T03:04:00.000Z'), findsOneWidget);
    expect(find.textContaining('修改：2030-01-02T03:04:00.000Z'), findsOneWidget);
    expect(find.textContaining('问卷版本：1'), findsOneWidget);

    await tester.tap(find.text('视频通话'));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(find.text('3 / 5'), findsOneWidget);
    expect(find.text('已保存'), findsOneWidget);
  });

  testWidgets('放弃草稿后可从提示中撤销并恢复原内容', (tester) async {
    final database = LocalDatabase(NativeDatabase.memory());
    final identity = FakeIdentitySession(
      initial: IdentitySnapshot(
        stage: IdentityStage.signedIn,
        principal: const IdentityPrincipal(
          externalSubject: 'external-subject-not-an-app-user-id',
          email: 'person@example.test',
        ),
        expiresAt: DateTime.utc(2030, 1, 2, 4, 4),
      ),
    );
    final dependencies = AppDependencies(
      databaseFactory: _SingleDatabaseFactory(database),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(identity),
      sessionContextGateway: FakeSessionContextGateway(),
      platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
      questionnaireRemoteSourceBuilder: (_) =>
          const _EmptyPublishedQuestionnaireSource(),
      timeZoneProvider: const _FakeTimeZoneProvider('America/Chicago'),
    );

    await tester.pumpWidget(TongxingzheApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    addTearDown(database.close);

    await tester.tap(find.text('记录接触'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('视频通话'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    final discardDraftButton = find.byTooltip('放弃草稿');
    await tester.ensureVisible(discardDraftButton);
    await tester.pumpAndSettle();
    await tester.tap(discardDraftButton);
    await tester.pumpAndSettle();

    expect(find.text('草稿 (0)'), findsOneWidget);
    expect(find.text('草稿已放弃'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();

    expect(find.text('草稿 (1)'), findsOneWidget);
    expect(find.text('视频通话'), findsOneWidget);
  });

  testWidgets('修改草稿后立即返回也会先保存最后一次输入', (tester) async {
    final database = LocalDatabase(NativeDatabase.memory());
    final identity = FakeIdentitySession(
      initial: IdentitySnapshot(
        stage: IdentityStage.signedIn,
        principal: const IdentityPrincipal(
          externalSubject: 'external-subject-not-an-app-user-id',
          email: 'person@example.test',
        ),
        expiresAt: DateTime.utc(2030, 1, 2, 4, 4),
      ),
    );
    final dependencies = AppDependencies(
      databaseFactory: _SingleDatabaseFactory(database),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(identity),
      sessionContextGateway: FakeSessionContextGateway(),
      platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
      questionnaireRemoteSourceBuilder: (_) =>
          const _EmptyPublishedQuestionnaireSource(),
      timeZoneProvider: const _FakeTimeZoneProvider('America/Chicago'),
    );

    await tester.pumpWidget(TongxingzheApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    addTearDown(database.close);

    await tester.tap(find.text('记录接触'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('视频通话'));
    await tester.pump();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('草稿 (1)'), findsOneWidget);
    expect(find.text('视频通话'), findsOneWidget);
  });

  testWidgets('应用进入后台时立即保存尚在等待的草稿', (tester) async {
    final database = LocalDatabase(NativeDatabase.memory());
    final identity = FakeIdentitySession(
      initial: IdentitySnapshot(
        stage: IdentityStage.signedIn,
        principal: const IdentityPrincipal(
          externalSubject: 'external-subject-not-an-app-user-id',
          email: 'person@example.test',
        ),
        expiresAt: DateTime.utc(2030, 1, 2, 4, 4),
      ),
    );
    final dependencies = AppDependencies(
      databaseFactory: _SingleDatabaseFactory(database),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(identity),
      sessionContextGateway: FakeSessionContextGateway(),
      platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
      questionnaireRemoteSourceBuilder: (_) =>
          const _EmptyPublishedQuestionnaireSource(),
      timeZoneProvider: const _FakeTimeZoneProvider('America/Chicago'),
    );

    await tester.pumpWidget(TongxingzheApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    addTearDown(database.close);

    await tester.tap(find.text('记录接触'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('视频通话'));
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(find.text('已保存'), findsOneWidget);
  });

  testWidgets('纯线上匿名接触提交后移除草稿并显示成功反馈', (tester) async {
    final database = LocalDatabase(NativeDatabase.memory());
    final identity = FakeIdentitySession(
      initial: IdentitySnapshot(
        stage: IdentityStage.signedIn,
        principal: const IdentityPrincipal(
          externalSubject: 'external-subject-not-an-app-user-id',
          email: 'person@example.test',
        ),
        expiresAt: DateTime.utc(2030, 1, 2, 4, 4),
      ),
    );
    final dependencies = AppDependencies(
      databaseFactory: _SingleDatabaseFactory(database),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(identity),
      sessionContextGateway: FakeSessionContextGateway(),
      platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
      questionnaireRemoteSourceBuilder: (_) =>
          const _EmptyPublishedQuestionnaireSource(),
      timeZoneProvider: const _FakeTimeZoneProvider('America/Chicago'),
    );

    await tester.pumpWidget(TongxingzheApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    addTearDown(database.close);

    await tester.tap(find.text('记录接触'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('视频通话'));
    await tester.enterText(
      find.byKey(const ValueKey('contact-reach-count')),
      '2',
    );
    // 小屏幕上需要像真实用户一样向上滚动，避开固定提交栏。
    await tester.drag(find.byType(ListView), const Offset(0, -180));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('5 / 5'), findsOneWidget);

    await tester.tap(find.text('正式提交'));
    await tester.pumpAndSettle();

    expect(find.text('接触已提交'), findsOneWidget);
    expect(find.text('草稿 (0)'), findsOneWidget);
    expect(find.text('今日接触场次 1'), findsOneWidget);
    expect(find.text('仅本机 1'), findsOneWidget);

    await tester.tap(find.text('今日'));
    await tester.pumpAndSettle();

    expect(find.text('今日接触场次 1'), findsOneWidget);
    expect(find.text('今日触达人数 2'), findsOneWidget);
    expect(find.text('待同步 1'), findsOneWidget);

    await tester.tap(find.text('分析'));
    await tester.pumpAndSettle();

    expect(find.text('最近七日接触场次 1'), findsOneWidget);
    expect(find.text('最近七日触达人数 2'), findsOneWidget);
    await _scrollUntilBuilt(
      tester,
      find.text('兴趣 3：1 场；1 / 1（100.00%）'),
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('兴趣 3：1 场；1 / 1（100.00%）'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('中位等级：3'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      find.text('兴趣 3–4（明确愿意继续或主动提出／落实下一步）：1 / 1（100.00%）'),
      findsOneWidget,
    );
    expect(find.text('兴趣 0（明确拒绝）：0 / 1（0.00%）'), findsOneWidget);
    expect(find.text('中位等级：3'), findsOneWidget);
    expect(find.textContaining('不计算等级平均数'), findsOneWidget);
    expect(find.textContaining('未知 0、拒答 0、不适用 0、未回答 0'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('视频通话：1 场'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('视频通话：1 场'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('最近发生 2030-01-02T03:04:00.000Z'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(find.text('最近发生 2030-01-02T03:04:00.000Z'), findsOneWidget);
    expect(find.text('同步覆盖 0 / 1'), findsOneWidget);
  });

  testWidgets('联网提交经 ACK 后从仅本机变为已同步', (tester) async {
    final database = LocalDatabase(NativeDatabase.memory());
    final identity = FakeIdentitySession(
      initial: IdentitySnapshot(
        stage: IdentityStage.signedIn,
        principal: const IdentityPrincipal(
          externalSubject: 'external-subject-not-an-app-user-id',
          email: 'person@example.test',
        ),
        expiresAt: DateTime.utc(2030, 1, 2, 4, 4),
      ),
    );
    final transport = _AcceptingSyncTransport();
    final dependencies = AppDependencies(
      databaseFactory: _SingleDatabaseFactory(database),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(identity),
      sessionContextGateway: FakeSessionContextGateway(),
      platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
      questionnaireRemoteSourceBuilder: (_) =>
          const _EmptyPublishedQuestionnaireSource(),
      timeZoneProvider: const _FakeTimeZoneProvider('America/Chicago'),
      syncTransportBuilder: (_) => transport,
    );

    await tester.pumpWidget(TongxingzheApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    addTearDown(database.close);

    await tester.tap(find.text('记录接触'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('视频通话'));
    await tester.enterText(
      find.byKey(const ValueKey('contact-reach-count')),
      '2',
    );
    await tester.drag(find.byType(ListView), const Offset(0, -180));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('正式提交'));
    await tester.pumpAndSettle();

    expect(transport.commands, hasLength(1));
    expect(find.text('仅本机 0'), findsOneWidget);
    expect(find.text('已同步 1'), findsOneWidget);
  });

  testWidgets('首页区分等待重试、需要处理和永久拒绝', (tester) async {
    final database = LocalDatabase(NativeDatabase.memory());
    final identity = FakeIdentitySession(
      initial: IdentitySnapshot(
        stage: IdentityStage.signedIn,
        principal: const IdentityPrincipal(
          externalSubject: 'external-subject-not-an-app-user-id',
          email: 'person@example.test',
        ),
        expiresAt: DateTime.utc(2030, 1, 2, 4, 4),
      ),
    );
    final transport = _QueueingSyncTransport([
      const SyncPushRetryable(failureCode: 'network_unavailable'),
      const SyncPushConflict(failureCode: 'stale_revision'),
      const SyncPushPermanentFailure(failureCode: 'forbidden'),
    ]);
    final dependencies = AppDependencies(
      databaseFactory: _SingleDatabaseFactory(database),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(identity),
      sessionContextGateway: FakeSessionContextGateway(),
      platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
      questionnaireRemoteSourceBuilder: (_) =>
          const _EmptyPublishedQuestionnaireSource(),
      timeZoneProvider: const _FakeTimeZoneProvider('America/Chicago'),
      syncTransportBuilder: (_) => transport,
    );

    await tester.pumpWidget(TongxingzheApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    addTearDown(database.close);

    Future<void> submitContact() async {
      await tester.tap(find.text('记录接触'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('视频通话'));
      await tester.enterText(
        find.byKey(const ValueKey('contact-reach-count')),
        '2',
      );
      await tester.drag(find.byType(ListView), const Offset(0, -180));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      await tester.tap(find.text('正式提交'));
      await tester.pumpAndSettle();
    }

    await submitContact();
    await submitContact();
    await submitContact();

    expect(find.text('等待重试 1'), findsOneWidget);
    expect(find.text('需要处理 1'), findsOneWidget);
    expect(find.text('永久拒绝 1'), findsOneWidget);
  });

  testWidgets('启动时拉取其他设备的接触并刷新今日事实', (tester) async {
    final database = LocalDatabase(NativeDatabase.memory());
    final identity = FakeIdentitySession(
      initial: IdentitySnapshot(
        stage: IdentityStage.signedIn,
        principal: const IdentityPrincipal(
          externalSubject: 'external-subject-not-an-app-user-id',
          email: 'person@example.test',
        ),
        expiresAt: DateTime.utc(2030, 1, 2, 4, 4),
      ),
    );
    final transport = _AcceptingSyncTransport(
      pullReplies: [
        SyncPullSucceeded(
          SyncPullBatch(
            changes: [
              SyncRemoteChange(
                changeType: 'contact.submitted',
                revisionNumber: 1,
                payload: {
                  'contactId': 'other-device-contact',
                  'workspaceId': syntheticSessionContext.workspace.id,
                  'projectId': syntheticSessionContext.project.id,
                  'questionnaireVersionId':
                      syntheticSessionContext.questionnaireVersion.id,
                  'occurredAtUtc': '2030-01-02T02:30:00.000Z',
                  'occurredTimeZone': 'America/Chicago',
                  'firstSubmittedAtUtc': '2030-01-02T03:00:00.000Z',
                  'channel': 'voice_call',
                  'channelDetail': null,
                  'location': {'kind': 'not_applicable'},
                  'reachCount': 3,
                  'interestLevel': 2,
                  'answers': <Object?>[],
                },
              ),
            ],
            nextCursor: 'remote-cursor-1',
          ),
        ),
      ],
    );
    final dependencies = AppDependencies(
      databaseFactory: _SingleDatabaseFactory(database),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(identity),
      sessionContextGateway: FakeSessionContextGateway(),
      platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
      questionnaireRemoteSourceBuilder: (_) =>
          const _EmptyPublishedQuestionnaireSource(),
      timeZoneProvider: const _FakeTimeZoneProvider('America/Chicago'),
      syncTransportBuilder: (_) => transport,
    );

    await tester.pumpWidget(TongxingzheApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    addTearDown(database.close);

    expect(transport.pullCursors.first, isNull);
    expect(find.text('今日接触场次 1'), findsOneWidget);
    expect(find.text('今日触达人数 3'), findsOneWidget);
    expect(find.text('待同步 0'), findsOneWidget);
  });

  testWidgets('面对面接触取得坐标后才可正式提交', (tester) async {
    final database = LocalDatabase(NativeDatabase.memory());
    final identity = FakeIdentitySession(
      initial: IdentitySnapshot(
        stage: IdentityStage.signedIn,
        principal: const IdentityPrincipal(
          externalSubject: 'external-subject-not-an-app-user-id',
          email: 'person@example.test',
        ),
        expiresAt: DateTime.utc(2030, 1, 2, 4, 4),
      ),
    );
    final regionResolver = _ResolvedRegionResolver(database);
    final dependencies = AppDependencies(
      databaseFactory: _SingleDatabaseFactory(database),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(identity),
      sessionContextGateway: FakeSessionContextGateway(),
      platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
      questionnaireRemoteSourceBuilder: (_) =>
          const _EmptyPublishedQuestionnaireSource(),
      timeZoneProvider: const _FakeTimeZoneProvider('America/Chicago'),
      locationCapture: const _FakeLocationCapture(
        LocationSnapshot(
          latitude: 41.7897,
          longitude: -87.5997,
          accuracyMeters: 8.5,
        ),
      ),
      regionResolverBuilder: (_, _) => regionResolver,
    );

    await tester.pumpWidget(TongxingzheApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    addTearDown(database.close);

    await tester.tap(find.text('记录接触'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('面对面'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -180));
    await tester.pumpAndSettle();

    expect(find.textContaining('需要具体线下地点'), findsOneWidget);
    expect(find.text('获取当前坐标'), findsOneWidget);

    await tester.tap(find.text('获取当前坐标'));
    await tester.pumpAndSettle();

    expect(regionResolver.resolveCalls, 1);
    expect(regionResolver.lastError, isNull);
    expect(find.textContaining('芝加哥大学'), findsOneWidget);
    expect(find.textContaining('待匹配规范区域'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('contact-reach-count')),
      '1',
    );
    await tester.drag(find.byType(ListView), const Offset(0, -240));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('正式提交'));
    await tester.pumpAndSettle();

    expect(find.text('接触已提交'), findsOneWidget);
    expect(find.text('今日接触场次 1'), findsOneWidget);
  });

  testWidgets('其他直接渠道必须输入可分析的渠道说明', (tester) async {
    final database = LocalDatabase(NativeDatabase.memory());
    final identity = FakeIdentitySession(
      initial: IdentitySnapshot(
        stage: IdentityStage.signedIn,
        principal: const IdentityPrincipal(
          externalSubject: 'external-subject-not-an-app-user-id',
          email: 'person@example.test',
        ),
        expiresAt: DateTime.utc(2030, 1, 2, 4, 4),
      ),
    );
    final dependencies = AppDependencies(
      databaseFactory: _SingleDatabaseFactory(database),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(identity),
      sessionContextGateway: FakeSessionContextGateway(),
      platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
      questionnaireRemoteSourceBuilder: (_) =>
          const _EmptyPublishedQuestionnaireSource(),
      timeZoneProvider: const _FakeTimeZoneProvider('America/Chicago'),
    );

    await tester.pumpWidget(TongxingzheApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    addTearDown(database.close);

    await tester.tap(find.text('记录接触'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('其他直接渠道'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('contact-channel-detail')),
      findsOneWidget,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('2 / 5'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('contact-channel-detail')),
      '线上游戏语音房',
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('3 / 5'), findsOneWidget);
  });

  testWidgets('未接通尝试与后来真实接触使用两条清楚路径', (tester) async {
    final database = LocalDatabase(NativeDatabase.memory());
    final identity = FakeIdentitySession(
      initial: IdentitySnapshot(
        stage: IdentityStage.signedIn,
        principal: const IdentityPrincipal(
          externalSubject: 'external-subject-not-an-app-user-id',
          email: 'person@example.test',
        ),
        expiresAt: DateTime.utc(2030, 1, 2, 4, 4),
      ),
    );
    final dependencies = AppDependencies(
      databaseFactory: _SingleDatabaseFactory(database),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(identity),
      sessionContextGateway: FakeSessionContextGateway(),
      platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
      questionnaireRemoteSourceBuilder: (_) =>
          const _EmptyPublishedQuestionnaireSource(),
      timeZoneProvider: const _FakeTimeZoneProvider('America/Chicago'),
    );
    addTearDown(database.close);

    await tester.pumpWidget(TongxingzheApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    await tester.tap(find.text('接触'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('record-contact-attempt')));
    await tester.pumpAndSettle();

    expect(find.textContaining('不计触达'), findsWidgets);
    await tester.tap(find.text('语音通话'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存接触尝试'));
    await tester.pumpAndSettle();

    expect(find.text('接触尝试 (1)'), findsOneWidget);
    expect(find.textContaining('触达人数 0'), findsOneWidget);
    await tester.tap(find.text('记录后来回应'));
    await tester.pumpAndSettle();

    expect(find.text('这条接触来自一次较早的未接通尝试'), findsOneWidget);
    expect(find.textContaining('不会把尝试改写成接触'), findsOneWidget);
  });
}

final class _EmptyManagementReportGateway implements ManagementReportGateway {
  const _EmptyManagementReportGateway();

  @override
  Future<void> close() async {}

  @override
  Future<ManagementReportResult<ManagementAnalysisContextSnapshot>>
  loadContext() async => ManagementReportSuccess(
    ManagementAnalysisContextSnapshot(current: null, available: const []),
  );

  @override
  Future<ManagementReportResult<List<ManagementReportSnapshotSummary>>>
  listSnapshots(String projectId) async => const ManagementReportSuccess([]);

  @override
  Future<ManagementReportResult<ManagementReportSnapshot>> readSnapshot({
    required String projectId,
    required ManagementReportSnapshotSummary summary,
  }) async =>
      const ManagementReportRejected(ManagementReportFailureCode.notFound);

  @override
  Future<ManagementReportResult<ManagementReportExportArtifact>>
  exportSnapshot({
    required String projectId,
    required ManagementReportSnapshotSummary summary,
  }) async =>
      const ManagementReportRejected(ManagementReportFailureCode.notFound);

  @override
  Future<ManagementReportResult<ManagementAnalysisContextSnapshot>>
  selectContext(String projectId) async =>
      const ManagementReportRejected(ManagementReportFailureCode.unauthorized);
}

final class _TrackingFollowUpConsentRatioReportGateway
    implements FollowUpConsentRatioReportGateway {
  var closeCount = 0;

  @override
  Future<void> close() async => closeCount++;

  @override
  Future<
    FollowUpConsentRatioReportResult<
      FollowUpConsentRatioReportSnapshotDirectory
    >
  >
  listSnapshots(String projectId) async =>
      const FollowUpConsentRatioReportRejected(
        FollowUpConsentRatioReportFailureCode.notConfigured,
      );

  @override
  Future<FollowUpConsentRatioReportResult<FollowUpConsentRatioReportSnapshot>>
  readSnapshot({
    required String projectId,
    required FollowUpConsentRatioReportSnapshotSummary summary,
  }) async => const FollowUpConsentRatioReportRejected(
    FollowUpConsentRatioReportFailureCode.notConfigured,
  );
}

final class _BlockingPlatformCapabilitiesProvider
    implements PlatformCapabilitiesProvider {
  final Completer<PlatformCapabilities> _completion = Completer();
  var loadCalls = 0;

  @override
  Future<PlatformCapabilities> load() {
    loadCalls++;
    return _completion.future;
  }

  void complete() => _completion.complete(fullyAvailableTestCapabilities);
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

final class _TrackingInterestReportGateway implements InterestReportGateway {
  var closeCount = 0;

  @override
  Future<void> close() async => closeCount++;

  @override
  Future<InterestReportResult<InterestReportSnapshotDirectory>> listSnapshots(
    String projectId,
  ) async =>
      const InterestReportRejected(InterestReportFailureCode.notConfigured);

  @override
  Future<InterestReportResult<InterestReportSnapshot>> readSnapshot({
    required String projectId,
    required InterestReportSnapshotSummary summary,
  }) async =>
      const InterestReportRejected(InterestReportFailureCode.notConfigured);
}

final class _TrackingOriginalRegionReportGateway
    implements OriginalRegionReportGateway {
  var closeCount = 0;

  @override
  Future<void> close() async => closeCount++;

  @override
  Future<OriginalRegionReportResult<OriginalRegionReportSnapshotDirectory>>
  listSnapshots(String projectId) async => const OriginalRegionReportRejected(
    OriginalRegionReportFailureCode.notConfigured,
  );

  @override
  Future<OriginalRegionReportResult<OriginalRegionReportSnapshot>>
  readSnapshot({
    required String projectId,
    required OriginalRegionReportSnapshotSummary summary,
  }) async => const OriginalRegionReportRejected(
    OriginalRegionReportFailureCode.notConfigured,
  );
}

final class _OneRelationshipStageGateway
    implements CurrentRelationshipStageGateway {
  const _OneRelationshipStageGateway();

  @override
  Future<void> close() async {}

  @override
  Future<CurrentRelationshipStageGatewayResult> load({
    required CurrentRelationshipStageScope scope,
  }) async {
    final snapshotAt = DateTime.utc(2030, 1, 2, 3);
    return CurrentRelationshipStageGatewaySuccess(
      CurrentRelationshipStageSnapshot(
        scope: scope,
        snapshotAsOfUtc: snapshotAt,
        sourceDataCutoffUtc: snapshotAt,
        authorizedAtUtc: snapshotAt,
        lastSuccessfulSyncAtUtc: snapshotAt,
        coverage: CurrentRelationshipStageCoverage.known(
          totalCount: 1,
          pendingCount: 0,
        ),
        rows: [
          CurrentRelationshipStageRow(
            targetId: 'synthetic-target-1',
            relationshipProjectId: scope.projectId,
            assignedAppUserId: scope.appUserId,
            stage: 2,
            currentRevision: 1,
            updatedAtUtc: snapshotAt,
          ),
        ],
      ),
    );
  }
}

Future<void> _seedTargetResponseFacts(LocalDatabase database) async {
  const contactId = 'target-response-widget-contact';
  final occurredAt = DateTime.utc(2030, 1, 2, 2);
  await database.transaction(() async {
    await database
        .into(database.dbContactRecords)
        .insert(
          DbContactRecordsCompanion.insert(
            contactId: contactId,
            appUserId: syntheticSessionContext.appUserId,
            workspaceId: syntheticSessionContext.workspace.id,
            projectId: syntheticSessionContext.project.id,
            questionnaireVersionId:
                syntheticSessionContext.questionnaireVersion.id,
            occurredAtUtc: occurredAt,
            occurredTimeZone: 'America/Chicago',
            firstSubmittedAtUtc: occurredAt,
            channel: 'instant_text',
            locationKind: 'not_applicable',
            reachCount: 1,
            interestLevel: 2,
            currentRevision: 1,
            lifecycleStatus: 'active',
          ),
        );
    await database
        .into(database.dbContactRevisions)
        .insert(
          DbContactRevisionsCompanion.insert(
            revisionId: 'target-response-widget-revision',
            contactId: contactId,
            revisionNumber: 1,
            revisedByAppUserId: syntheticSessionContext.appUserId,
            revisedAtUtc: occurredAt,
            occurredAtUtc: occurredAt,
            occurredTimeZone: 'America/Chicago',
            channel: 'instant_text',
            locationKind: 'not_applicable',
            reachCount: 1,
            interestLevel: 2,
          ),
        );
    for (final fact in <({String id, int? response})>[
      (id: 'target-response-level-2', response: 2),
      (id: 'target-response-level-4', response: 4),
      (id: 'target-response-unanswered', response: null),
    ]) {
      await database
          .into(database.dbContactTargetLinks)
          .insert(
            DbContactTargetLinksCompanion.insert(
              contactId: contactId,
              revisionNumber: 1,
              targetId: fact.id,
              targetType: 'person',
              responseLevel: Value(fact.response),
              followUpConsent: 'unknown',
              institutionRepresentativeConfirmed: false,
              confirmStageZero: false,
            ),
          );
    }
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

final class _SequenceIdGenerator implements IdGenerator {
  var _next = 0;

  @override
  String next() => 'test-${_next++}';
}

final class _FixedIds implements IdGenerator {
  _FixedIds(List<String> values) : _values = [...values];

  final List<String> _values;

  @override
  String next() => _values.removeAt(0);
}

final class _FakeTimeZoneProvider implements DeviceTimeZoneProvider {
  const _FakeTimeZoneProvider(this.value);

  final String value;

  @override
  Future<String> currentIanaTimeZone() async => value;
}

/// 这些 App 级测试原本只验证空基础问卷下的导航和接触核心事实。
/// 显式远端保留该前提，同时让生产路由继续要求一个受权发布版本。
final class _EmptyPublishedQuestionnaireSource
    implements QuestionnaireRemoteSource {
  const _EmptyPublishedQuestionnaireSource();

  @override
  Future<QuestionnaireVersion?> fetchPublishedVersion(String versionId) async {
    final context =
        versionId == syntheticSecondSessionContext.questionnaireVersion.id
        ? syntheticSecondSessionContext
        : syntheticSessionContext;
    return QuestionnaireVersion(
      id: versionId,
      projectId: context.project.id,
      versionNumber: context.questionnaireVersion.versionNumber,
      questions: const [],
    );
  }

  @override
  Future<void> close() async {}
}

final class _OneQuestionPublishedSource implements QuestionnaireRemoteSource {
  const _OneQuestionPublishedSource();

  @override
  Future<QuestionnaireVersion?> fetchPublishedVersion(String versionId) async {
    return QuestionnaireVersion(
      id: versionId,
      projectId: syntheticSessionContext.project.id,
      versionNumber: syntheticSessionContext.questionnaireVersion.versionNumber,
      questions: [
        QuestionnaireQuestion(
          id: 'follow_up_consent',
          position: 1,
          prompt: '是否同意后续联系？',
          type: QuestionnaireQuestionType.boolean,
          required: true,
          allowUnknown: false,
          allowRefused: true,
          allowNotApplicable: false,
        ),
      ],
    );
  }

  @override
  Future<void> close() async {}
}

final class _AcceptingSyncTransport implements SyncTransport {
  _AcceptingSyncTransport({List<SyncPullResult> pullReplies = const []})
    : _pullReplies = [...pullReplies];

  final List<SyncCommand> commands = [];
  final List<SyncPullResult> _pullReplies;
  final List<String?> pullCursors = [];

  @override
  Future<void> close() async {}

  @override
  Future<SyncPullResult> pull({
    required SyncScope scope,
    required String? cursor,
    int limit = 100,
  }) async {
    pullCursors.add(cursor);
    if (_pullReplies.isNotEmpty) {
      return _pullReplies.removeAt(0);
    }
    return SyncPullSucceeded(
      SyncPullBatch(changes: const [], nextCursor: cursor),
    );
  }

  @override
  Future<SyncPushResult> push(SyncCommand command) async {
    commands.add(command);
    return const SyncPushAccepted(serverCursor: 'test-cursor-1');
  }
}

final class _QueueingSyncTransport implements SyncTransport {
  _QueueingSyncTransport(this._replies);

  final List<SyncPushResult> _replies;

  @override
  Future<void> close() async {}

  @override
  Future<SyncPullResult> pull({
    required SyncScope scope,
    required String? cursor,
    int limit = 100,
  }) async =>
      SyncPullSucceeded(SyncPullBatch(changes: const [], nextCursor: cursor));

  @override
  Future<SyncPushResult> push(SyncCommand command) async {
    return _replies.removeAt(0);
  }
}

final class _CompletingSyncTransport implements SyncTransport {
  final List<SyncCommand> commands = [];
  final _pushCompleter = Completer<SyncPushResult>();

  void completePush(SyncPushResult result) => _pushCompleter.complete(result);

  @override
  Future<void> close() async {}

  @override
  Future<SyncPullResult> pull({
    required SyncScope scope,
    required String? cursor,
    int limit = 100,
  }) async =>
      SyncPullSucceeded(SyncPullBatch(changes: const [], nextCursor: cursor));

  @override
  Future<SyncPushResult> push(SyncCommand command) {
    commands.add(command);
    return _pushCompleter.future;
  }
}

final class _BlockingPullSyncTransport implements SyncTransport {
  final _pullCompleter = Completer<SyncPullResult>();
  var pullCalls = 0;

  void completePull(SyncPullResult result) => _pullCompleter.complete(result);

  @override
  Future<void> close() async {}

  @override
  Future<SyncPullResult> pull({
    required SyncScope scope,
    required String? cursor,
    int limit = 100,
  }) {
    pullCalls++;
    return _pullCompleter.future;
  }

  @override
  Future<SyncPushResult> push(SyncCommand command) async =>
      const SyncPushAccepted(serverCursor: 'unexpected-push');
}

final class _FakeLocationCapture implements ContactLocationCapture {
  const _FakeLocationCapture(this.snapshot);

  final LocationSnapshot snapshot;

  @override
  Future<LocationSnapshot> captureCurrentPosition() async => snapshot;
}

Future<void> _focusByTabbing(WidgetTester tester, Finder target) async {
  for (var i = 0; i < 12; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    if (_containsPrimaryFocus(tester, target)) return;
  }
  fail('Could not focus $target');
}

Future<void> _scrollUntilBuilt(
  WidgetTester tester,
  Finder target, {
  required Finder scrollable,
}) async {
  for (var attempt = 0; attempt < 80 && target.evaluate().isEmpty; attempt++) {
    await tester.drag(scrollable, const Offset(0, -200));
    await tester.pumpAndSettle();
  }
  expect(target, findsOneWidget);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

bool _containsPrimaryFocus(WidgetTester tester, Finder finder) {
  final target = tester.element(finder);
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused is! Element) return false;
  if (identical(focused, target)) return true;
  var contains = false;
  focused.visitAncestorElements((ancestor) {
    if (identical(ancestor, target)) {
      contains = true;
      return false;
    }
    return true;
  });
  return contains;
}

const _organizationSessionContext = TrustedSessionContext(
  appUserId: '11111111-1111-4111-8111-111111111111',
  workspace: WorkspaceContext(
    id: '77777777-7777-4777-8777-777777777777',
    kind: WorkspaceKind.organization,
    name: '机构空间',
  ),
  project: ProjectContext(
    id: '88888888-8888-4888-8888-888888888888',
    name: '机构推广项目',
  ),
  questionnaireVersion: QuestionnaireVersionContext(
    id: '99999999-9999-4999-8999-999999999999',
    versionNumber: 1,
  ),
  capabilities: {'record_contact'},
);

final class _ConsentOptInGateway
    implements PersonalFollowUpConsentOptInGateway {
  _ConsentOptInGateway({required this.projectId});

  final String projectId;
  var configureCalls = 0;

  @override
  Future<PersonalFollowUpConsentOptInResult<PersonalFollowUpConsentOptInState>>
  load() async => PersonalFollowUpConsentOptInSuccess(
    PersonalFollowUpConsentOptInState(
      stateContractId: personalFollowUpConsentOptInStateContract,
      metricId: personalFollowUpConsentOptInMetric,
      projectId: projectId,
      status: PersonalFollowUpConsentOptInStatus.notEnabled,
      configuration: null,
    ),
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
  }) async {
    configureCalls++;
    return const PersonalFollowUpConsentOptInRejected(
      PersonalFollowUpConsentOptInFailureCode.serviceUnavailable,
    );
  }

  @override
  Future<void> close() async {}
}

final class _ReadyConsentRatioGateway
    implements PersonalFollowUpConsentRatioGateway {
  final List<String> calls = [];

  @override
  Future<PersonalFollowUpConsentRatioGatewayResult> load({
    required String projectId,
    required DateTime fromUtc,
    required DateTime untilUtc,
  }) async {
    calls.add(projectId);
    return PersonalFollowUpConsentRatioGatewaySuccess(
      PersonalFollowUpConsentRatioReady(
        projectId: projectId,
        metric: consentRatioMetricResult(
          fromUtc: fromUtc,
          untilUtc: untilUtc,
          dataCutoffUtc: untilUtc,
          retrievedAtUtc: untilUtc,
          yesCount: 2,
          noCount: 1,
          unknownCount: 0,
          refusedCount: 1,
          notApplicableCount: 1,
          unansweredCount: 2,
          excludedCount: 0,
        ),
      ),
    );
  }

  @override
  Future<void> close() async {}
}

final class _RejectedConsentRatioGateway
    implements PersonalFollowUpConsentRatioGateway {
  const _RejectedConsentRatioGateway();

  @override
  Future<PersonalFollowUpConsentRatioGatewayResult> load({
    required String projectId,
    required DateTime fromUtc,
    required DateTime untilUtc,
  }) async => const PersonalFollowUpConsentRatioGatewayRejected(
    PersonalFollowUpConsentRatioFailureCode.networkUnavailable,
  );

  @override
  Future<void> close() async {}
}

final class _ReadyRelationshipStageChangeSummaryGateway
    implements PersonalRelationshipStageChangeSummaryGateway {
  final List<String> calls = [];

  @override
  Future<PersonalRelationshipStageChangeSummaryGatewayResult> load({
    required String projectId,
    required DateTime fromUtc,
    required DateTime untilUtc,
  }) async {
    calls.add(projectId);
    return PersonalRelationshipStageChangeSummaryGatewaySuccess(
      PersonalRelationshipStageChangeSummary.fromCounts(
        projectId: projectId,
        fromUtc: fromUtc,
        untilUtc: untilUtc,
        dataCutoffUtc: untilUtc,
        authorizedAtUtc: untilUtc,
        retrievedAtUtc: untilUtc,
        eventCount: 5,
        distinctRelationshipCount: 4,
        upwardCount: 3,
        downwardCount: 2,
      ),
    );
  }

  @override
  Future<void> close() async {}
}

final class _RejectedRelationshipStageChangeSummaryGateway
    implements PersonalRelationshipStageChangeSummaryGateway {
  const _RejectedRelationshipStageChangeSummaryGateway();

  @override
  Future<PersonalRelationshipStageChangeSummaryGatewayResult> load({
    required String projectId,
    required DateTime fromUtc,
    required DateTime untilUtc,
  }) async => const PersonalRelationshipStageChangeSummaryGatewayRejected(
    PersonalRelationshipStageChangeSummaryFailureCode.networkUnavailable,
  );

  @override
  Future<void> close() async {}
}

final class _ResolvedRegionResolver implements ContactRegionResolver {
  _ResolvedRegionResolver(LocalDatabase database)
    : _catalog = RegionCatalog(database);

  final RegionCatalog _catalog;
  var resolveCalls = 0;
  Object? lastError;

  @override
  Future<ContactLocation> resolve(PendingContactLocation location) async {
    resolveCalls++;
    try {
      await _catalog.installSnapshot(
        const CanonicalRegionSnapshot(
          version: 'test-regions-v1',
          nodes: [
            CanonicalRegionNode(
              regionId: 'city-chicago',
              canonicalName: '芝加哥',
              kind: RegionKind.city,
            ),
            CanonicalRegionNode(
              regionId: 'institution-uchicago',
              parentRegionId: 'city-chicago',
              canonicalName: '芝加哥大学',
              kind: RegionKind.institution,
            ),
          ],
        ),
      );
    } catch (error) {
      lastError = error;
      rethrow;
    }
    return const ResolvedContactLocation(
      placeName: '芝加哥大学',
      smallestRegionId: 'institution-uchicago',
      regionTreeVersion: 'test-regions-v1',
    );
  }

  @override
  Future<void> close() async {}
}
