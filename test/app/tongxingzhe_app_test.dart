import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/app/app_dependencies.dart';
import 'package:tongxingzhe_app/app/tongxingzhe_app.dart';
import 'package:tongxingzhe_app/app_session/session_context_gateway.dart';
import 'package:tongxingzhe_app/data/local_database.dart';
import 'package:tongxingzhe_app/data/local_database_factory.dart';
import 'package:tongxingzhe_app/device/device_time_zone.dart';
import 'package:tongxingzhe_app/features/contact_journal/contact_models.dart';
import 'package:tongxingzhe_app/foundation/runtime_values.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
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

    expect(find.text('个人空间 → 我的推广项目'), findsOneWidget);
    expect(find.text('今日'), findsWidgets);
    expect(find.text('接触'), findsOneWidget);
    expect(find.text('对象'), findsOneWidget);
    expect(find.text('分析'), findsOneWidget);
    expect(find.text('记录接触'), findsOneWidget);
    expect(find.text('正式认证尚未配置'), findsNothing);
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
    expect(find.text('兴趣 3：1 场'), findsOneWidget);
    expect(find.text('视频通话：1 场'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -220));
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

final class _FakeLocationCapture implements ContactLocationCapture {
  const _FakeLocationCapture(this.snapshot);

  final LocationSnapshot snapshot;

  @override
  Future<LocationSnapshot> captureCurrentPosition() async => snapshot;
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
