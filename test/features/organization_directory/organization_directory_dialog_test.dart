import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/app_session/app_session.dart';
import 'package:tongxingzhe_app/app_session/session_context_gateway.dart';
import 'package:tongxingzhe_app/features/organization_directory/organization_directory_dialog.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/l10n/app_strings.dart';
import 'package:tongxingzhe_app/organization_directory/organization_directory.dart';

void main() {
  testWidgets('打开只读一次，按原顺序显示可选名称与完整 UUID', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gateway = _Gateway([
      OrganizationDirectorySuccess(const [_organizationA, _organizationB]),
    ]);

    await _open(tester, fixture.session, gateway);

    expect(gateway.listCalls, 1);
    expect(
      tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .map((text) => text.data),
      [
        _organizationA.organizationName,
        _organizationA.organizationWorkspaceId,
        _organizationB.organizationName,
        _organizationB.organizationWorkspaceId,
      ],
    );
    for (final text in tester.widgetList<SelectableText>(
      find.byType(SelectableText),
    )) {
      expect(text.maxLines, isNull);
    }
    expect(gateway.closed, isFalse);
  });

  testWidgets('初始读取允许关闭，防止重复刷新并忽略迟到结果', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final pending = Completer<OrganizationDirectoryResult>();
    final gateway = _Gateway([pending]);
    await _open(tester, fixture.session, gateway, settle: false);

    expect(
      find.text(const AppStrings('zh').t('organizationDirectoryLoading')),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(_refresh).onPressed, isNull);
    expect(tester.widget<TextButton>(_close).onPressed, isNotNull);
    await tester.tap(_refresh, warnIfMissed: false);
    await tester.pump();
    expect(gateway.listCalls, 1);

    await tester.tap(_close);
    await tester.pumpAndSettle();
    expect(find.byType(OrganizationDirectoryDialog), findsNothing);
    expect(fixture.session.current.stage, AppSessionStage.ready);
    expect(gateway.closed, isFalse);

    pending.complete(OrganizationDirectorySuccess(const [_organizationA]));
    await tester.pumpAndSettle();
    expect(find.text(_organizationA.organizationName), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('刷新先清除旧快照，失败不冒充空目录且可再试', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final pending = Completer<OrganizationDirectoryResult>();
    final gateway = _Gateway([
      OrganizationDirectorySuccess(const [_organizationA]),
      pending,
      OrganizationDirectorySuccess(const [_organizationB]),
    ]);
    const text = AppStrings('zh');
    await _open(tester, fixture.session, gateway);
    expect(find.text(_organizationA.organizationName), findsOneWidget);

    await tester.tap(_refresh);
    await tester.pump();
    expect(find.text(_organizationA.organizationName), findsNothing);
    expect(find.text(text.t('organizationDirectoryLoading')), findsOneWidget);
    await tester.tap(_refresh, warnIfMissed: false);
    expect(gateway.listCalls, 2);

    pending.complete(
      const OrganizationDirectoryRejected(
        OrganizationDirectoryFailureCode.networkUnavailable,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(text.t('organizationDirectoryNetworkUnavailable')),
      findsOneWidget,
    );
    expect(find.text(text.t('organizationDirectoryEmpty')), findsNothing);
    expect(find.text(_organizationA.organizationName), findsNothing);

    await tester.tap(_refresh);
    await tester.pumpAndSettle();
    expect(gateway.listCalls, 3);
    expect(find.text(_organizationB.organizationName), findsOneWidget);
  });

  testWidgets('成功空目录与失败状态分开', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gateway = _Gateway([OrganizationDirectorySuccess(const [])]);
    const text = AppStrings('zh');
    await _open(tester, fixture.session, gateway);

    expect(find.text(text.t('organizationDirectoryEmpty')), findsOneWidget);
    expect(
      find.text(text.t('organizationDirectoryInvalidResponse')),
      findsNothing,
    );
  });

  for (final code in OrganizationDirectoryFailureCode.values) {
    testWidgets('${code.name} 显示对应脱敏提示而不是空目录', (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final gateway = _Gateway([OrganizationDirectoryRejected(code)]);
      const text = AppStrings('zh');
      await _open(tester, fixture.session, gateway);

      expect(find.text(_failureText(text, code)), findsOneWidget);
      expect(find.text(text.t('organizationDirectoryEmpty')), findsNothing);
      expect(find.byType(OrganizationDirectoryDialog), findsOneWidget);
    });
  }

  testWidgets('未知异常只显示 invalidResponse，不泄露原文', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gateway = _Gateway([StateError('secret provider detail')]);
    const text = AppStrings('zh');
    await _open(tester, fixture.session, gateway);

    expect(
      find.text(text.t('organizationDirectoryInvalidResponse')),
      findsOneWidget,
    );
    expect(find.textContaining('secret'), findsNothing);
    expect(find.textContaining('provider'), findsNothing);
  });

  testWidgets('会话不再 ready 时清空并永久禁用该窗口的读取', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final pending = Completer<OrganizationDirectoryResult>();
    final gateway = _Gateway([pending]);
    await _open(tester, fixture.session, gateway, settle: false);

    fixture.identity.emit(const IdentitySnapshot.signedOut());
    await tester.pumpAndSettle();
    expect(
      find.text(const AppStrings('zh').t('organizationDirectoryUnauthorized')),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(_refresh).onPressed, isNull);

    fixture.identity.emit(_signedIn('subject-a'));
    await tester.pumpAndSettle();
    expect(fixture.session.current.stage, AppSessionStage.ready);
    expect(tester.widget<FilledButton>(_refresh).onPressed, isNull);
    await tester.tap(_refresh, warnIfMissed: false);
    expect(gateway.listCalls, 1);

    pending.complete(OrganizationDirectorySuccess(const [_organizationA]));
    await tester.pumpAndSettle();
    expect(find.text(_organizationA.organizationName), findsNothing);
    expect(
      find.text(const AppStrings('zh').t('organizationDirectoryUnauthorized')),
      findsOneWidget,
    );
  });

  testWidgets('换账号清除旧目录，同账号切换项目不重读', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gateway = _Gateway([
      OrganizationDirectorySuccess(const [_organizationA]),
    ]);
    await _open(tester, fixture.session, gateway);

    await fixture.session.selectProject(_contextAOtherProject.project.id);
    await tester.pumpAndSettle();
    expect(fixture.session.current.context, _contextAOtherProject);
    expect(find.text(_organizationA.organizationName), findsOneWidget);
    expect(gateway.listCalls, 1);

    fixture.identity.emit(_signedIn('subject-b'));
    await tester.pumpAndSettle();
    expect(fixture.session.current.context?.appUserId, _contextB.appUserId);
    expect(find.text(_organizationA.organizationName), findsNothing);
    expect(tester.widget<FilledButton>(_refresh).onPressed, isNull);
  });

  testWidgets('状态为 live region，按键关闭后焦点返回入口', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final semantics = tester.ensureSemantics();
    await _pumpLauncher(tester, fixture.session, _Gateway());

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    final status = find.byKey(const ValueKey('organization-directory-status'));
    expect(
      tester
          .getSemantics(status)
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(OrganizationDirectoryDialog), findsNothing);
    expect(_hasPrimaryFocus(tester, _launcher), isTrue);
    semantics.dispose();
  });

  testWidgets('中英文在窄屏 200% 字号、长内容与宽屏暗色下无 overflow', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final organizations = List.generate(
      12,
      (index) => OrganizationDirectoryEntry(
        organizationWorkspaceId:
            '123e4567-e89b-12d3-a456-${index.toString().padLeft(12, '0')}',
        organizationName:
            '很长的组织原始名称不应被省略 $index ${List.filled(20, '界').join()}',
      ),
    );
    await _open(
      tester,
      fixture.session,
      _Gateway([OrganizationDirectorySuccess(organizations)]),
      textScaler: TextScaler.linear(2),
    );
    expect(tester.takeException(), isNull);
    expect(find.text(organizations.last.organizationName), findsOneWidget);
    expect(
      find.text(organizations.last.organizationWorkspaceId),
      findsOneWidget,
    );
    await tester.tap(_close);
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(1280, 900);
    await _open(
      tester,
      fixture.session,
      _Gateway([
        OrganizationDirectorySuccess(const [_organizationA]),
      ]),
      localeCode: 'en',
      themeMode: ThemeMode.dark,
    );
    expect(tester.takeException(), isNull);
    expect(
      find.text(const AppStrings('en').t('organizationDirectoryHelp')),
      findsOneWidget,
    );
  });

  testWidgets('关闭与刷新触控目标至少为 48 logical pixels', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final semantics = tester.ensureSemantics();
    await _open(
      tester,
      fixture.session,
      _Gateway([
        OrganizationDirectorySuccess(const [_organizationA]),
      ]),
    );

    for (final target in [_close, _refresh]) {
      final rect = tester.getSemantics(target).rect;
      expect(rect.width, greaterThanOrEqualTo(48), reason: '$target width');
      expect(rect.height, greaterThanOrEqualTo(48), reason: '$target height');
    }
    semantics.dispose();
  });
}

final _launcher = find.byKey(const ValueKey('open-organization-directory'));
final _refresh = find.byKey(const ValueKey('organization-directory-refresh'));
final _close = find.byKey(const ValueKey('organization-directory-close'));

Future<void> _open(
  WidgetTester tester,
  AppSession session,
  OrganizationDirectoryGateway gateway, {
  bool settle = true,
  String localeCode = 'zh',
  TextScaler textScaler = TextScaler.noScaling,
  ThemeMode themeMode = ThemeMode.light,
}) async {
  await _pumpLauncher(
    tester,
    session,
    gateway,
    localeCode: localeCode,
    textScaler: textScaler,
    themeMode: themeMode,
  );
  await tester.tap(_launcher);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _pumpLauncher(
  WidgetTester tester,
  AppSession session,
  OrganizationDirectoryGateway gateway, {
  String localeCode = 'zh',
  TextScaler textScaler = TextScaler.noScaling,
  ThemeMode themeMode = ThemeMode.light,
}) => tester.pumpWidget(
  MaterialApp(
    theme: ThemeData(useMaterial3: true),
    darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
    themeMode: themeMode,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScaler),
      child: child!,
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            key: const ValueKey('open-organization-directory'),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => OrganizationDirectoryDialog(
                text: AppStrings(localeCode),
                gateway: gateway,
                appSession: session,
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  ),
);

bool _hasPrimaryFocus(WidgetTester tester, Finder finder) {
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

String _failureText(AppStrings text, OrganizationDirectoryFailureCode code) =>
    switch (code) {
      OrganizationDirectoryFailureCode.notConfigured => text.t(
        'organizationDirectoryNotConfigured',
      ),
      OrganizationDirectoryFailureCode.unauthorized => text.t(
        'organizationDirectoryUnauthorized',
      ),
      OrganizationDirectoryFailureCode.invalidRequest => text.t(
        'organizationDirectoryInvalidRequest',
      ),
      OrganizationDirectoryFailureCode.forbidden => text.t(
        'organizationDirectoryForbidden',
      ),
      OrganizationDirectoryFailureCode.serviceUnavailable => text.t(
        'organizationDirectoryServiceUnavailable',
      ),
      OrganizationDirectoryFailureCode.networkUnavailable => text.t(
        'organizationDirectoryNetworkUnavailable',
      ),
      OrganizationDirectoryFailureCode.invalidResponse => text.t(
        'organizationDirectoryInvalidResponse',
      ),
    };

final class _Fixture {
  _Fixture(this.identity, this.session);

  final _IdentitySession identity;
  final AppSession session;

  static Future<_Fixture> create() async {
    final identity = _IdentitySession(_signedIn('subject-a'));
    final session = AppSession(
      identitySession: identity,
      contextGateway: _ContextGateway(),
    );
    await session.start();
    return _Fixture(identity, session);
  }

  Future<void> close() async {
    await session.close();
    await identity.close();
  }
}

final class _IdentitySession implements IdentitySession {
  _IdentitySession(this._current);

  final _changes = StreamController<IdentitySnapshot>.broadcast();
  IdentitySnapshot _current;

  void emit(IdentitySnapshot snapshot) {
    _current = snapshot;
    _changes.add(snapshot);
  }

  @override
  IdentitySnapshot get current => _current;

  @override
  Stream<IdentitySnapshot> get changes => _changes.stream;

  @override
  Future<IdentityResult<IdentitySnapshot>> restore() async =>
      IdentitySuccess(_current);

  @override
  Future<IdentityResult<IdentityAccessToken>> accessToken({
    bool forceRefresh = false,
  }) async => IdentitySuccess(
    IdentityAccessToken(
      value: _current.principal!.externalSubject,
      expiresAt: _current.expiresAt,
    ),
  );

  @override
  Future<void> close() => _changes.close();

  @override
  Future<IdentityResult<IdentitySnapshot>> signOut() async {
    const snapshot = IdentitySnapshot.signedOut();
    emit(snapshot);
    return const IdentitySuccess(snapshot);
  }

  @override
  Future<IdentityResult<IdentitySnapshot>> refresh() async =>
      IdentitySuccess(_current);

  @override
  Future<IdentityResult<IdentitySnapshot>> signIn({
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<IdentityResult<IdentitySnapshot>> signUp({
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<IdentityResult<IdentitySnapshot>> confirmSignUpOtp({
    required String email,
    required String otp,
  }) => throw UnimplementedError();

  @override
  Future<IdentityResult<IdentitySnapshot>> requestPasswordRecovery({
    required String email,
  }) => throw UnimplementedError();

  @override
  Future<IdentityResult<IdentitySnapshot>> confirmPasswordRecoveryOtp({
    required String email,
    required String otp,
  }) => throw UnimplementedError();

  @override
  Future<IdentityResult<IdentitySnapshot>> updateRecoveredPassword({
    required String newPassword,
  }) => throw UnimplementedError();
}

final class _ContextGateway implements SessionContextGateway {
  @override
  Future<SessionContextResult> resolve(IdentityAccessToken accessToken) async =>
      SessionContextSuccess(
        accessToken.value == 'subject-b' ? _contextB : _contextA,
      );

  @override
  Future<SessionContextResult> selectProject(
    IdentityAccessToken accessToken,
    String projectId,
  ) async => SessionContextSuccess(_contextAOtherProject);

  @override
  Future<SessionContextResult> createPersonalProject(
    IdentityAccessToken accessToken,
    String displayName,
  ) async =>
      const SessionContextRejected(SessionContextFailureCode.serverRejected);

  @override
  Future<void> close() async {}
}

final class _Gateway implements OrganizationDirectoryGateway {
  _Gateway([Iterable<Object> results = const []])
    : _results = Queue.of(results);

  final Queue<Object> _results;
  var listCalls = 0;
  var closed = false;

  @override
  Future<OrganizationDirectoryResult> list() async {
    listCalls += 1;
    if (_results.isEmpty) {
      return const OrganizationDirectoryRejected(
        OrganizationDirectoryFailureCode.notConfigured,
      );
    }
    final next = _results.removeFirst();
    if (next is Completer<OrganizationDirectoryResult>) return next.future;
    if (next is OrganizationDirectoryResult) return next;
    throw next;
  }

  @override
  Future<void> close() async => closed = true;
}

IdentitySnapshot _signedIn(String subject) => IdentitySnapshot(
  stage: IdentityStage.signedIn,
  principal: IdentityPrincipal(
    externalSubject: subject,
    email: '$subject@example.test',
  ),
  expiresAt: DateTime.utc(2030, subject == 'subject-a' ? 1 : 2),
);

const _organizationA = OrganizationDirectoryEntry(
  organizationWorkspaceId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  organizationName: '  同名组织  ',
);
const _organizationB = OrganizationDirectoryEntry(
  organizationWorkspaceId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  organizationName: '  同名组织  ',
);

const _contextA = TrustedSessionContext(
  appUserId: '11111111-1111-4111-8111-111111111111',
  workspace: WorkspaceContext(
    id: '21111111-1111-4111-8111-111111111111',
    kind: WorkspaceKind.personal,
    name: '个人空间',
  ),
  project: ProjectContext(
    id: '31111111-1111-4111-8111-111111111111',
    name: '项目甲',
  ),
  questionnaireVersion: QuestionnaireVersionContext(
    id: '41111111-1111-4111-8111-111111111111',
    versionNumber: 1,
  ),
  capabilities: {},
);

const _contextAOtherProject = TrustedSessionContext(
  appUserId: '11111111-1111-4111-8111-111111111111',
  workspace: WorkspaceContext(
    id: '21111111-1111-4111-8111-111111111111',
    kind: WorkspaceKind.personal,
    name: '个人空间',
  ),
  project: ProjectContext(
    id: '31111111-1111-4111-8111-111111111112',
    name: '项目丙',
  ),
  questionnaireVersion: QuestionnaireVersionContext(
    id: '41111111-1111-4111-8111-111111111112',
    versionNumber: 2,
  ),
  capabilities: {},
);

const _contextB = TrustedSessionContext(
  appUserId: '12222222-2222-4222-8222-222222222222',
  workspace: WorkspaceContext(
    id: '22222222-2222-4222-8222-222222222222',
    kind: WorkspaceKind.organization,
    name: '组织空间',
  ),
  project: ProjectContext(
    id: '32222222-2222-4222-8222-222222222222',
    name: '项目乙',
  ),
  questionnaireVersion: QuestionnaireVersionContext(
    id: '42222222-2222-4222-8222-222222222222',
    versionNumber: 2,
  ),
  capabilities: {},
);
