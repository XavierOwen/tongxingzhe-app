import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/app_session/app_session.dart';
import 'package:tongxingzhe_app/app_session/session_context_gateway.dart';
import 'package:tongxingzhe_app/features/organization_directory/organization_invitation_create_dialog.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/l10n/app_strings.dart';
import 'package:tongxingzhe_app/organization_directed_account_invitation/organization_directed_account_invitation.dart';
import 'package:tongxingzhe_app/organization_directory/organization_directory.dart';

void main() {
  testWidgets('只接受 UUID，首次有效提交才生成 invitation UUID', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gateway = _Gateway([
      OrganizationDirectedAccountInvitationCreateSuccess(_receipt),
    ]);
    final ids = _Ids();
    await _open(tester, fixture.session, gateway, ids.next);

    for (final invalid in [
      '',
      'not-a-uuid',
      'subject-a',
      'person@example.test',
    ]) {
      await tester.enterText(_target, invalid);
      await tester.tap(_submit);
      await tester.pump();
      expect(gateway.calls, isEmpty);
      expect(ids.count, 0);
      expect(
        find.text(
          const AppStrings('zh').t('organizationInvitationCreateInvalidTarget'),
        ),
        findsOneWidget,
      );
    }

    await tester.enterText(_target, _targetAppUserId);
    await tester.tap(_submit);
    await tester.pumpAndSettle();
    expect(ids.count, 1);
    expect(gateway.calls.single.invitationId, _invitationId);
    expect(
      gateway.calls.single.organizationWorkspaceId,
      _organization.organizationWorkspaceId,
    );
    expect(gateway.calls.single.targetAppUserId, _targetAppUserId);
    expect(find.text(_organization.organizationName), findsOneWidget);
    expect(find.text(_receipt.invitationId), findsOneWidget);
  });

  testWidgets('提交进行中忽略重复点击、Enter 和关闭', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final pending =
        Completer<OrganizationDirectedAccountInvitationCreateResult>();
    final gateway = _Gateway([pending]);
    await _open(tester, fixture.session, gateway, _Ids().next);

    await tester.enterText(_target, _targetAppUserId);
    await tester.tap(_submit);
    await tester.tap(_submit, warnIfMissed: false);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(gateway.calls, hasLength(1));
    expect(find.byType(OrganizationInvitationCreateDialog), findsOneWidget);
    expect(tester.widget<FilledButton>(_submit).onPressed, isNull);
    expect(
      find.text(
        const AppStrings('zh').t('organizationInvitationCreateSubmitting'),
      ),
      findsOneWidget,
    );

    pending.complete(
      OrganizationDirectedAccountInvitationCreateSuccess(_receipt),
    );
    await tester.pumpAndSettle();
    expect(find.text(_receipt.invitationId), findsOneWidget);
  });

  testWidgets('销毁对话框后忽略迟到创建结果且不关闭 gateway', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final pending =
        Completer<OrganizationDirectedAccountInvitationCreateResult>();
    final gateway = _Gateway([pending]);
    await _open(tester, fixture.session, gateway, _Ids().next);
    await tester.enterText(_target, _targetAppUserId);
    await tester.tap(_submit);
    await tester.pump();
    expect(gateway.calls, hasLength(1));

    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(
      OrganizationDirectedAccountInvitationCreateSuccess(_receipt),
    );
    await tester.pumpAndSettle();

    expect(find.byType(OrganizationInvitationCreateDialog), findsNothing);
    expect(find.text(_receipt.invitationId), findsNothing);
    expect(
      find.text(const AppStrings('zh').t('organizationInvitationCreateRetry')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    expect(gateway.closed, isFalse);
  });

  for (final uncertain in [
    OrganizationDirectedAccountInvitationFailureCode.networkUnavailable,
    OrganizationDirectedAccountInvitationFailureCode.serviceUnavailable,
    OrganizationDirectedAccountInvitationFailureCode.invalidResponse,
    OrganizationDirectedAccountInvitationFailureCode.conflict,
    null,
  ]) {
    testWidgets(
      '不确定 ${uncertain?.name ?? 'throw'} 后固定组织、收件人和 invitation UUID，明确失败也不解冻',
      (tester) async {
        final fixture = await _Fixture.create();
        addTearDown(fixture.close);
        final first = uncertain == null
            ? StateError('secret provider detail')
            : OrganizationDirectedAccountInvitationCreateRejected(uncertain);
        final gateway = _Gateway([
          first,
          const OrganizationDirectedAccountInvitationCreateRejected(
            OrganizationDirectedAccountInvitationFailureCode.forbidden,
          ),
          OrganizationDirectedAccountInvitationCreateSuccess(_receipt),
        ]);
        final ids = _Ids();
        await _open(tester, fixture.session, gateway, ids.next);

        await tester.enterText(_target, _targetAppUserId);
        await tester.tap(_submit);
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(_target).readOnly, isTrue);
        expect(_uncertain, findsOneWidget);
        expect(
          find.text(_organization.organizationWorkspaceId),
          findsOneWidget,
        );

        await tester.tap(_submit);
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(_target).readOnly, isTrue);
        expect(_uncertain, findsOneWidget);

        await tester.tap(_submit);
        await tester.pumpAndSettle();
        expect(gateway.calls, hasLength(3));
        expect(gateway.calls.map((call) => call.invitationId).toSet(), {
          _invitationId,
        });
        expect(
          gateway.calls.map((call) => call.organizationWorkspaceId).toSet(),
          {_organization.organizationWorkspaceId},
        );
        expect(gateway.calls.map((call) => call.targetAppUserId).toSet(), {
          _targetAppUserId,
        });
        expect(ids.count, 1);
      },
    );
  }

  testWidgets('不确定关闭必须显式保留或放弃', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gateway = _Gateway([
      const OrganizationDirectedAccountInvitationCreateRejected(
        OrganizationDirectedAccountInvitationFailureCode.networkUnavailable,
      ),
    ]);
    await _open(tester, fixture.session, gateway, _Ids().next);
    await tester.enterText(_target, _targetAppUserId);
    await tester.tap(_submit);
    await tester.pumpAndSettle();

    await tester.tap(_close);
    await tester.pump();
    expect(_keepRetry, findsOneWidget);
    expect(_discard, findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(_keepRetry);
    await tester.pump();
    expect(_uncertain, findsOneWidget);
    expect(tester.widget<TextField>(_target).readOnly, isTrue);

    await tester.tap(_close);
    await tester.pump();
    await tester.tap(_discard);
    await tester.pumpAndSettle();
    expect(find.byType(OrganizationInvitationCreateDialog), findsNothing);
    expect(gateway.closed, isFalse);
  });

  testWidgets('成功保留五字段回执，复制失败可重试且不重新创建', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final clipboard = _ClipboardProbe();
    addTearDown(clipboard.close);
    final gateway = _Gateway([
      OrganizationDirectedAccountInvitationCreateSuccess(_receipt),
    ]);
    await _open(tester, fixture.session, gateway, _Ids().next);
    await tester.enterText(_target, _targetAppUserId);
    await tester.tap(_submit);
    await tester.pumpAndSettle();

    for (final value in [
      _receipt.invitationId,
      _receipt.issuedAtUtc.toUtc().toIso8601String(),
      _receipt.expiresAtUtc.toUtc().toIso8601String(),
    ]) {
      expect(find.text(value), findsOneWidget);
    }
    expect(_target, findsNothing);

    clipboard.fail = true;
    await tester.tap(_copy);
    await tester.pumpAndSettle();
    expect(clipboard.values, [_receipt.invitationId]);
    expect(find.byKey(_statusKey), findsOneWidget);
    clipboard.fail = false;
    await tester.tap(_copy);
    await tester.pumpAndSettle();
    expect(clipboard.values, [_receipt.invitationId, _receipt.invitationId]);
    expect(gateway.calls, hasLength(1));
    await tester.tap(_close);
    await tester.pumpAndSettle();
    expect(find.byType(OrganizationInvitationCreateDialog), findsNothing);
  });

  testWidgets('登出和账号 ABA 清除输入、回执并忽略迟到结果', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final pending =
        Completer<OrganizationDirectedAccountInvitationCreateResult>();
    final gateway = _Gateway([pending]);
    final clipboard = _ClipboardProbe();
    addTearDown(clipboard.close);
    await _open(tester, fixture.session, gateway, _Ids().next);
    await tester.enterText(_target, _targetAppUserId);
    await tester.tap(_submit);
    await tester.pump();

    fixture.identity.emit(const IdentitySnapshot.signedOut());
    await tester.pumpAndSettle();
    fixture.identity.emit(_signedIn('subject-b'));
    await tester.pumpAndSettle();
    fixture.identity.emit(_signedIn('subject-a'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(_submit, findsNothing);
    expect(_copy, findsNothing);
    pending.complete(
      OrganizationDirectedAccountInvitationCreateSuccess(_receipt),
    );
    await tester.pumpAndSettle();
    expect(find.text(_receipt.invitationId), findsNothing);
    expect(clipboard.values, isEmpty);
    expect(find.byType(OrganizationInvitationCreateDialog), findsOneWidget);
  });

  for (final code in OrganizationDirectedAccountInvitationFailureCode.values) {
    for (final localeCode in ['zh', 'en']) {
      testWidgets('${code.name} $localeCode 显示固定脱敏创建失败', (tester) async {
        final fixture = await _Fixture.create();
        addTearDown(fixture.close);
        final gateway = _Gateway([
          OrganizationDirectedAccountInvitationCreateRejected(code),
        ]);
        await _open(
          tester,
          fixture.session,
          gateway,
          _Ids().next,
          localeCode: localeCode,
        );
        await tester.enterText(_target, _targetAppUserId);
        await tester.tap(_submit);
        await tester.pumpAndSettle();
        expect(
          find.text(
            AppStrings(localeCode).t(
              code ==
                      OrganizationDirectedAccountInvitationFailureCode
                          .unauthorized
                  ? 'organizationInvitationCreateUnauthorized'
                  : 'organizationInvitationCreateFailure.${code.name}',
            ),
          ),
          findsOneWidget,
        );
        expect(find.byType(OrganizationInvitationCreateDialog), findsOneWidget);
        expect(find.textContaining('secret'), findsNothing);
        expect(find.textContaining('provider'), findsNothing);
      });
    }
  }

  testWidgets('键盘可打开、提交和 Escape 关闭并返回入口焦点', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gateway = _Gateway([
      OrganizationDirectedAccountInvitationCreateSuccess(_receipt),
    ]);
    await _pumpLauncher(tester, fixture.session, gateway, _Ids().next);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_hasPrimaryFocus(tester, _target), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(OrganizationInvitationCreateDialog), findsNothing);
    expect(_hasPrimaryFocus(tester, _launcher), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_hasPrimaryFocus(tester, _target), isTrue);
    await tester.enterText(_target, _targetAppUserId);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(gateway.calls, hasLength(1));
    await tester.tap(_close);
    await tester.pumpAndSettle();
    expect(find.byType(OrganizationInvitationCreateDialog), findsNothing);
    expect(_hasPrimaryFocus(tester, _launcher), isTrue);
  });

  testWidgets('320x568、200% 字号保留完整标签并显示失败状态', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final semantics = tester.ensureSemantics();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await _open(
      tester,
      fixture.session,
      _Gateway(const [
        OrganizationDirectedAccountInvitationCreateRejected(
          OrganizationDirectedAccountInvitationFailureCode.networkUnavailable,
        ),
      ]),
      _Ids().next,
      organization: OrganizationDirectoryEntry(
        organizationWorkspaceId: _organization.organizationWorkspaceId,
        organizationName: '很长的组织名称 ${List.filled(60, '界').join()}',
      ),
      textScaler: TextScaler.linear(2),
    );
    expect(tester.takeException(), isNull);
    expect(
      find.text(
        const AppStrings('zh').t('organizationInvitationCreateTargetId'),
      ),
      findsOneWidget,
    );
    for (final target in [_submit, _close]) {
      final rect = tester.getSemantics(target).rect;
      expect(rect.width, greaterThanOrEqualTo(48), reason: '$target width');
      expect(rect.height, greaterThanOrEqualTo(48), reason: '$target height');
    }
    expect(find.textContaining('很长的组织名称'), findsOneWidget);

    await tester.enterText(_target, _targetAppUserId);
    await tester.tap(_submit);
    await tester.pumpAndSettle();
    final contentViewport = tester.getRect(
      find.descendant(
        of: find.byType(OrganizationInvitationCreateDialog),
        matching: find.byType(SingleChildScrollView),
      ),
    );
    for (final status in [find.byKey(_statusKey), _uncertain]) {
      expect(
        tester
            .getSemantics(status)
            .getSemanticsData()
            .flagsCollection
            .isLiveRegion,
        isTrue,
      );
      final rect = tester.getRect(status);
      expect(
        rect.top,
        greaterThanOrEqualTo(contentViewport.top),
        reason: '$status top',
      );
      expect(
        rect.bottom,
        lessThanOrEqualTo(contentViewport.bottom),
        reason: '$status bottom',
      );
    }
    semantics.dispose();
  });
}

final _launcher = find.byKey(
  const ValueKey('open-organization-invitation-create'),
);
final _target = find.byKey(
  const ValueKey('organization-invitation-create-target-id'),
);
final _submit = find.byKey(
  const ValueKey('organization-invitation-create-submit'),
);
final _close = find.byKey(
  const ValueKey('organization-invitation-create-close'),
);
final _copy = find.byKey(const ValueKey('organization-invitation-create-copy'));
final _uncertain = find.byKey(
  const ValueKey('organization-invitation-create-uncertain'),
);
final _keepRetry = find.byKey(
  const ValueKey('organization-invitation-create-keep-retry'),
);
final _discard = find.byKey(
  const ValueKey('organization-invitation-create-discard'),
);
const _statusKey = ValueKey('organization-invitation-create-status');

Future<void> _open(
  WidgetTester tester,
  AppSession session,
  OrganizationDirectedAccountInvitationGateway gateway,
  String Function() invitationIdGenerator, {
  OrganizationDirectoryEntry organization = _organization,
  String localeCode = 'zh',
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await _pumpLauncher(
    tester,
    session,
    gateway,
    invitationIdGenerator,
    organization: organization,
    localeCode: localeCode,
    textScaler: textScaler,
  );
  await tester.tap(_launcher);
  await tester.pumpAndSettle();
}

Future<void> _pumpLauncher(
  WidgetTester tester,
  AppSession session,
  OrganizationDirectedAccountInvitationGateway gateway,
  String Function() invitationIdGenerator, {
  OrganizationDirectoryEntry organization = _organization,
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
            key: const ValueKey('open-organization-invitation-create'),
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => OrganizationInvitationCreateDialog(
                text: AppStrings(localeCode),
                organization: organization,
                gateway: gateway,
                appSession: session,
                invitationIdGenerator: invitationIdGenerator,
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

final class _Gateway implements OrganizationDirectedAccountInvitationGateway {
  _Gateway([Iterable<Object> results = const []])
    : _results = Queue.of(results);

  final Queue<Object> _results;
  final calls =
      <
        ({
          String invitationId,
          String organizationWorkspaceId,
          String targetAppUserId,
        })
      >[];
  var closed = false;

  @override
  Future<OrganizationDirectedAccountInvitationCreateResult> create({
    required String invitationId,
    required String organizationWorkspaceId,
    required String targetAppUserId,
  }) async {
    calls.add((
      invitationId: invitationId,
      organizationWorkspaceId: organizationWorkspaceId,
      targetAppUserId: targetAppUserId,
    ));
    if (_results.isEmpty) {
      return const OrganizationDirectedAccountInvitationCreateRejected(
        OrganizationDirectedAccountInvitationFailureCode.notConfigured,
      );
    }
    final next = _results.removeFirst();
    if (next is Completer<OrganizationDirectedAccountInvitationCreateResult>) {
      return next.future;
    }
    if (next is OrganizationDirectedAccountInvitationCreateResult) return next;
    throw next;
  }

  @override
  Future<OrganizationDirectedAccountInvitationPreviewResult> preview({
    required String invitationId,
  }) => throw UnsupportedError('unused create test preview');

  @override
  Future<OrganizationDirectedAccountInvitationAcceptResult> accept({
    required String invitationId,
  }) => throw UnsupportedError('unused create test accept');

  @override
  Future<void> close() async => closed = true;
}

final class _ClipboardProbe {
  _ClipboardProbe() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            values.add(
              (call.arguments! as Map<Object?, Object?>)['text']! as String,
            );
            if (fail) throw StateError('clipboard failed');
          }
          return null;
        });
  }

  final values = <String>[];
  var fail = false;

  void close() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  }
}

final class _Ids {
  var count = 0;

  String next() => [_invitationId, _otherInvitationId][count++];
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
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unused test identity method');
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

IdentitySnapshot _signedIn(String subject) => IdentitySnapshot(
  stage: IdentityStage.signedIn,
  principal: IdentityPrincipal(
    externalSubject: subject,
    email: '$subject@example.test',
  ),
  expiresAt: DateTime.utc(2030, subject == 'subject-a' ? 1 : 2),
);

const _organization = OrganizationDirectoryEntry(
  organizationWorkspaceId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  organizationName: '测试组织',
);
const _targetAppUserId = '99999999-9999-4999-8999-999999999999';
const _invitationId = 'abcdefab-cdef-4abc-8def-abcdefabcdef';
const _otherInvitationId = 'abcdefab-cdef-4abc-8def-abcdefabcdea';

final _receipt = OrganizationDirectedAccountInvitationCreateReceipt(
  organizationInvitationContractId:
      'organization-directed-account-invitation:v1',
  invitationId: _invitationId,
  organizationWorkspaceId: _organization.organizationWorkspaceId,
  issuedAtUtc: DateTime.utc(2030, 1, 2, 4, 5, 6),
  expiresAtUtc: DateTime.utc(2030, 1, 9, 4, 5, 6),
);

const _contextA = TrustedSessionContext(
  appUserId: _targetAppUserId,
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
    kind: WorkspaceKind.personal,
    name: '个人空间乙',
  ),
  project: ProjectContext(
    id: '32222222-2222-4222-8222-222222222222',
    name: '项目乙',
  ),
  questionnaireVersion: QuestionnaireVersionContext(
    id: '42222222-4222-4222-8222-222222222222',
    versionNumber: 2,
  ),
  capabilities: {},
);
