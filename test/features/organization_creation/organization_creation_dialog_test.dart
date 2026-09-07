import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/app_session/app_session.dart';
import 'package:tongxingzhe_app/app_session/session_context_gateway.dart';
import 'package:tongxingzhe_app/features/organization_creation/organization_creation_dialog.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/l10n/app_strings.dart';
import 'package:tongxingzhe_app/organization_creation/organization_creation.dart';

void main() {
  testWidgets('名称本地检查保留有效原文本，首次有效提交才生成请求 ID', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gateway = _Gateway([OrganizationCreationSuccess(_receipt)]);
    final ids = _Ids();
    final result = _ResultBox();
    await _open(tester, fixture.session, gateway, ids.next, result: result);

    await tester.enterText(_name, '   ');
    await tester.tap(_submit);
    await tester.pump();
    expect(gateway.calls, isEmpty);
    expect(ids.count, 0);
    expect(
      find.text(const AppStrings('zh').t('organizationCreateNameInvalid')),
      findsOneWidget,
    );

    await tester.enterText(_name, ' ${List.filled(121, '界').join()} ');
    await tester.tap(_submit);
    await tester.pump();
    expect(gateway.calls, isEmpty);
    expect(ids.count, 0);

    const rawName = '  同行者组织  ';
    await tester.enterText(_name, rawName);
    await tester.tap(_submit);
    await tester.pumpAndSettle();

    expect(gateway.calls.single.displayName, rawName);
    expect(gateway.calls.single.requestId, 'request-1');
    expect(ids.count, 1);
    expect(result.receipt, same(_receipt));
    expect(gateway.closed, isFalse);
  });

  testWidgets('不确定意图保持冻结，后续明确拒绝也继续使用同一参数', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gateway = _Gateway([
      const OrganizationCreationRejected(
        OrganizationCreationFailureCode.serviceUnavailable,
      ),
      const OrganizationCreationRejected(
        OrganizationCreationFailureCode.forbidden,
      ),
      OrganizationCreationSuccess(_receipt),
    ]);
    final ids = _Ids();
    await _open(tester, fixture.session, gateway, ids.next);

    await tester.enterText(_name, '原名称');
    await tester.tap(_submit);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(_name).readOnly, isTrue);
    expect(
      find.text(const AppStrings('zh').t('organizationCreateUncertain')),
      findsOneWidget,
    );

    await tester.enterText(_name, '模拟迟到输入');
    await tester.tap(_submit);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(_name).readOnly, isTrue);
    expect(
      find.text(const AppStrings('zh').t('organizationCreateUncertain')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('organization-create-cancel')));
    await tester.pump();
    expect(
      find.text(const AppStrings('zh').t('organizationCreateDiscardTitle')),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('organization-create-keep-retry')),
    );
    await tester.pump();
    await tester.tap(_submit);
    await tester.pumpAndSettle();

    expect(gateway.calls, hasLength(3));
    expect(gateway.calls.map((call) => call.requestId).toSet(), {'request-1'});
    expect(gateway.calls.map((call) => call.displayName).toSet(), {'原名称'});
    expect(ids.count, 1);
  });

  testWidgets('放弃不确定请求在同一对话框确认后关闭', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gateway = _Gateway([
      const OrganizationCreationRejected(
        OrganizationCreationFailureCode.networkUnavailable,
      ),
    ]);
    await _open(tester, fixture.session, gateway, _Ids().next);
    await tester.enterText(_name, '可能已创建');
    await tester.tap(_submit);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(
      find.text(const AppStrings('zh').t('organizationCreateDiscardTitle')),
      findsOneWidget,
    );
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('organization-create-discard')));
    await tester.pumpAndSettle();
    expect(find.byType(OrganizationCreationDialog), findsNothing);
  });

  testWidgets('请求进行中忽略重复点击、Enter、取消和 Escape', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final pending = Completer<OrganizationCreationResult>();
    final gateway = _Gateway([pending]);
    final result = _ResultBox();
    await _open(tester, fixture.session, gateway, _Ids().next, result: result);
    await tester.enterText(_name, '忙碌状态');
    await tester.tap(_submit);
    await tester.pump();

    await tester.tap(_submit, warnIfMissed: false);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(gateway.calls, hasLength(1));
    expect(find.byType(OrganizationCreationDialog), findsOneWidget);
    expect(tester.widget<FilledButton>(_submit).onPressed, isNull);
    expect(
      find.text(const AppStrings('zh').t('organizationCreating')),
      findsOneWidget,
    );

    pending.complete(OrganizationCreationSuccess(_receipt));
    await tester.pumpAndSettle();
    expect(result.receipt, same(_receipt));
  });

  testWidgets('明确拒绝允许编辑；同名重试复用 ID，改名才换 ID', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gateway = _Gateway([
      const OrganizationCreationRejected(
        OrganizationCreationFailureCode.invalidRequest,
      ),
      const OrganizationCreationRejected(
        OrganizationCreationFailureCode.forbidden,
      ),
      OrganizationCreationSuccess(_receipt),
    ]);
    final ids = _Ids();
    await _open(tester, fixture.session, gateway, ids.next);

    await tester.enterText(_name, '名称甲');
    await tester.tap(_submit);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(_name).readOnly, isFalse);

    await tester.tap(_submit);
    await tester.pumpAndSettle();
    await tester.enterText(_name, '名称乙');
    await tester.tap(_submit);
    await tester.pumpAndSettle();

    expect(gateway.calls[0].requestId, gateway.calls[1].requestId);
    expect(gateway.calls[2].requestId, isNot(gateway.calls[1].requestId));
    expect(ids.count, 2);
  });

  for (final code in OrganizationCreationFailureCode.values) {
    testWidgets('${code.name} 显示固定脱敏提示并保留对话框', (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final gateway = _Gateway([OrganizationCreationRejected(code)]);
      const text = AppStrings('zh');
      await _open(tester, fixture.session, gateway, _Ids().next);
      await tester.enterText(_name, '失败测试');
      await tester.tap(_submit);
      await tester.pumpAndSettle();

      expect(
        find.text(text.t('organizationCreateFailure.${code.name}')),
        findsOneWidget,
      );
      expect(find.byType(OrganizationCreationDialog), findsOneWidget);
    });
  }

  testWidgets('未知异常只显示 invalidResponse，不泄露异常文本', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gateway = _Gateway([StateError('secret provider detail')]);
    const text = AppStrings('zh');
    await _open(tester, fixture.session, gateway, _Ids().next);
    await tester.enterText(_name, '异常测试');
    await tester.tap(_submit);
    await tester.pumpAndSettle();

    expect(
      find.text(
        text.t(
          'organizationCreateFailure.${OrganizationCreationFailureCode.invalidResponse.name}',
        ),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('secret'), findsNothing);
    expect(find.textContaining('provider'), findsNothing);
  });

  testWidgets('退出身份会清空旧名称并忽略迟到成功', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final pending = Completer<OrganizationCreationResult>();
    final gateway = _Gateway([pending]);
    final result = _ResultBox();
    await _open(tester, fixture.session, gateway, _Ids().next, result: result);
    await tester.enterText(_name, '旧身份名称');
    await tester.tap(_submit);
    await tester.pump();

    fixture.identity.emit(const IdentitySnapshot.signedOut());
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(
      find.text(
        const AppStrings('zh').t('organizationCreateFailure.unauthorized'),
      ),
      findsOneWidget,
    );

    pending.complete(OrganizationCreationSuccess(_receipt));
    await tester.pumpAndSettle();
    expect(result.receipt, isNull);
    expect(find.byType(OrganizationCreationDialog), findsOneWidget);
  });

  testWidgets('appUser 切换会移除旧表单并忽略迟到成功', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final pending = Completer<OrganizationCreationResult>();
    final gateway = _Gateway([pending]);
    final result = _ResultBox();
    await _open(tester, fixture.session, gateway, _Ids().next, result: result);
    await tester.enterText(_name, '账号甲名称');
    await tester.tap(_submit);
    await tester.pump();

    fixture.identity.emit(_signedIn('subject-b'));
    await tester.pumpAndSettle();
    expect(fixture.session.current.context?.appUserId, _contextB.appUserId);
    expect(find.byType(TextField), findsNothing);

    pending.complete(OrganizationCreationSuccess(_receipt));
    await tester.pumpAndSettle();
    expect(result.receipt, isNull);
    expect(find.byType(OrganizationCreationDialog), findsOneWidget);
  });

  testWidgets('键盘可打开、提交和取消，对话框关闭后焦点返回入口', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gateway = _Gateway([OrganizationCreationSuccess(_receipt)]);
    await _pumpLauncher(tester, fixture.session, gateway, _Ids().next);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_hasPrimaryFocus(tester, _name), isTrue);

    await tester.enterText(_name, '键盘提交');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(gateway.calls, hasLength(1));
    expect(_hasPrimaryFocus(tester, _launcher), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(OrganizationCreationDialog), findsNothing);
    expect(_hasPrimaryFocus(tester, _launcher), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(OrganizationCreationDialog), findsNothing);
    expect(_hasPrimaryFocus(tester, _launcher), isTrue);
  });

  testWidgets('进行中和失败状态是 live region', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final semantics = tester.ensureSemantics();
    final pending = Completer<OrganizationCreationResult>();
    final gateway = _Gateway([pending]);
    await _open(tester, fixture.session, gateway, _Ids().next);
    await tester.enterText(_name, '读屏状态');
    await tester.tap(_submit);
    await tester.pump();

    final status = find.byKey(const ValueKey('organization-create-status'));
    expect(
      tester
          .getSemantics(status)
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
    pending.complete(
      const OrganizationCreationRejected(
        OrganizationCreationFailureCode.invalidRequest,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .getSemantics(status)
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
    semantics.dispose();
  });

  testWidgets('中英文在窄屏 200% 字号和宽屏均无 overflow', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await _open(
      tester,
      fixture.session,
      _Gateway(),
      _Ids().next,
      localeCode: 'zh',
      textScaler: TextScaler.linear(2),
    );
    expect(tester.takeException(), isNull);
    expect(
      find.text(const AppStrings('zh').t('organizationCreateHelp')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('organization-create-cancel')));
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(1280, 900);
    await _open(
      tester,
      fixture.session,
      _Gateway(),
      _Ids().next,
      localeCode: 'en',
    );
    expect(tester.takeException(), isNull);
    expect(
      find.text(const AppStrings('en').t('organizationCreateHelp')),
      findsOneWidget,
    );
    expect(
      const AppStrings('en').t('organizationCreate'),
      isNot(const AppStrings('zh').t('organizationCreate')),
    );
  });

  testWidgets('主要触控目标至少为 48 logical pixels', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final semantics = tester.ensureSemantics();
    await _open(tester, fixture.session, _Gateway(), _Ids().next);

    for (final target in [
      _submit,
      find.byKey(const ValueKey('organization-create-cancel')),
    ]) {
      final rect = tester.getSemantics(target).rect;
      expect(rect.width, greaterThanOrEqualTo(48), reason: '$target width');
      expect(rect.height, greaterThanOrEqualTo(48), reason: '$target height');
    }
    semantics.dispose();
  });
}

final _name = find.byKey(const ValueKey('organization-name'));
final _submit = find.byKey(const ValueKey('organization-create-submit'));
final _launcher = find.byKey(const ValueKey('open-organization-create'));

Future<void> _open(
  WidgetTester tester,
  AppSession session,
  OrganizationCreationGateway gateway,
  String Function() requestIdGenerator, {
  _ResultBox? result,
  String localeCode = 'zh',
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await _pumpLauncher(
    tester,
    session,
    gateway,
    requestIdGenerator,
    result: result,
    localeCode: localeCode,
    textScaler: textScaler,
  );
  await tester.tap(_launcher);
  await tester.pumpAndSettle();
}

Future<void> _pumpLauncher(
  WidgetTester tester,
  AppSession session,
  OrganizationCreationGateway gateway,
  String Function() requestIdGenerator, {
  _ResultBox? result,
  String localeCode = 'zh',
  TextScaler textScaler = TextScaler.noScaling,
}) => tester.pumpWidget(
  MaterialApp(
    theme: ThemeData(useMaterial3: true),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScaler),
      child: child!,
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            key: const ValueKey('open-organization-create'),
            onPressed: () async {
              final receipt = await showDialog<OrganizationCreationReceipt>(
                context: context,
                barrierDismissible: false,
                builder: (_) => OrganizationCreationDialog(
                  text: AppStrings(localeCode),
                  gateway: gateway,
                  appSession: session,
                  requestIdGenerator: requestIdGenerator,
                ),
              );
              result?.receipt = receipt;
            },
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
  Future<void> close() async {}

  @override
  Future<SessionContextResult> selectProject(
    IdentityAccessToken accessToken,
    String projectId,
  ) async =>
      const SessionContextRejected(SessionContextFailureCode.serverRejected);

  @override
  Future<SessionContextResult> createPersonalProject(
    IdentityAccessToken accessToken,
    String displayName,
  ) async =>
      const SessionContextRejected(SessionContextFailureCode.serverRejected);
}

final class _Gateway implements OrganizationCreationGateway {
  _Gateway([Iterable<Object> results = const []])
    : _results = Queue.of(results);

  final Queue<Object> _results;
  final List<({String requestId, String displayName})> calls = [];
  var closed = false;

  @override
  Future<OrganizationCreationResult> create({
    required String requestId,
    required String displayName,
  }) async {
    calls.add((requestId: requestId, displayName: displayName));
    if (_results.isEmpty) {
      return const OrganizationCreationRejected(
        OrganizationCreationFailureCode.notConfigured,
      );
    }
    final next = _results.removeFirst();
    if (next is Completer<OrganizationCreationResult>) return next.future;
    if (next is OrganizationCreationResult) return next;
    throw next;
  }

  @override
  Future<void> close() async => closed = true;
}

final class _Ids {
  var count = 0;

  String next() => 'request-${++count}';
}

final class _ResultBox {
  OrganizationCreationReceipt? receipt;
}

IdentitySnapshot _signedIn(String subject) => IdentitySnapshot(
  stage: IdentityStage.signedIn,
  principal: IdentityPrincipal(
    externalSubject: subject,
    email: '$subject@example.test',
  ),
  expiresAt: DateTime.utc(2030, subject == 'subject-a' ? 1 : 2),
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

final _receipt = OrganizationCreationReceipt(
  creationContractId: 'organization-creation:v1',
  organizationWorkspaceId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  organizationMembershipId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  organizationOwnerAssignmentId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  createdAtUtc: DateTime.utc(2026, 9, 6, 12),
);
