import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/app_session/app_session.dart';
import 'package:tongxingzhe_app/app_session/session_context_gateway.dart';
import 'package:tongxingzhe_app/features/organization_directory/organization_shareable_join_application_approve_dialog.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/l10n/app_strings.dart';
import 'package:tongxingzhe_app/organization_directory/organization_directory.dart';
import 'package:tongxingzhe_app/organization_shareable_join/organization_shareable_join.dart';

void main() {
  testWidgets('本地规范 UUID 后单独确认，成功留窗显示完整审批回执', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gateway = _Gateway([
      OrganizationShareableJoinApplicationApproveSuccess(_receipt),
    ]);
    final clipboardWrites = <Object?>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardWrites.add(call.arguments);
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await _open(tester, fixture.session, gateway);
    await tester.enterText(_field, '  ${_applicationId.toUpperCase()}  ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(gateway.calls, isEmpty);
    expect(_field, findsNothing);
    expect(_edit, findsOneWidget);
    expect(find.text(_applicationId), findsOneWidget);
    await tester.tap(_edit);
    await tester.pumpAndSettle();
    expect(_field, findsOneWidget);
    await tester.tap(_review);
    await tester.pumpAndSettle();
    await tester.tap(_submit);
    await tester.pumpAndSettle();

    expect(gateway.calls, [
      (applicationId: _applicationId, organizationWorkspaceId: _organizationId),
    ]);
    for (final value in [
      _organization.organizationName,
      _receipt.applicationId,
      _receipt.organizationWorkspaceId,
      _receipt.organizationMembershipId,
      _receipt.approvedAtUtc.toUtc().toIso8601String(),
    ]) {
      expect(find.text(value), findsOneWidget);
    }
    expect(_dialog, findsOneWidget);
    expect(_submit, findsNothing);
    expect(clipboardWrites, isEmpty);
    expect(gateway.closed, isFalse);
    expect(fixture.context.selectCalls, 0);
    await tester.tap(_close);
    await tester.pumpAndSettle();
    expect(gateway.closed, isFalse);
  });

  testWidgets('非法 UUID 和 URL 不触网；输入 Enter 只进入确认', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gateway = _Gateway([]);
    await _open(tester, fixture.session, gateway);
    for (final invalid in [
      '',
      'not-a-uuid',
      'https://example.test/$_applicationId',
    ]) {
      await tester.enterText(_field, invalid);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        find.text(
          const AppStrings(
            'zh',
          ).t('organizationShareableApprovalInvalidApplication'),
        ),
        findsOneWidget,
      );
      expect(_submit, findsNothing);
    }
    await tester.enterText(_field, _applicationId);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(_submit, findsOneWidget);
    expect(gateway.calls, isEmpty);
  });

  for (final code in OrganizationShareableJoinFailureCode.values) {
    testWidgets('${code.name} 使用稳定提示，且只指定三类失败不确定', (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final gateway = _Gateway([
        OrganizationShareableJoinApplicationApproveRejected(code),
      ]);
      await _confirmAndSubmit(tester, fixture.session, gateway);
      final uncertain = [
        OrganizationShareableJoinFailureCode.networkUnavailable,
        OrganizationShareableJoinFailureCode.serviceUnavailable,
        OrganizationShareableJoinFailureCode.invalidResponse,
      ].contains(code);
      expect(_uncertain, uncertain ? findsOneWidget : findsNothing);
      expect(_edit, findsNothing);
      expect(_field, findsNothing);
      if (code == OrganizationShareableJoinFailureCode.unauthorized) {
        expect(find.text(_applicationId), findsNothing);
        expect(find.text(_organization.organizationName), findsNothing);
        expect(find.text(_organizationId), findsNothing);
        expect(_submit, findsNothing);
        expect(
          find.text(
            const AppStrings(
              'zh',
            ).t('organizationShareableApprovalUnauthorized'),
          ),
          findsOneWidget,
        );
      } else {
        expect(
          find.text(
            const AppStrings(
              'zh',
            ).t('organizationShareableApprovalFailure.${code.name}'),
          ),
          findsOneWidget,
        );
        expect(_submit, findsOneWidget);
      }
    });
  }

  testWidgets('throw 不显示原文；Escape 请求保留或丢弃同一重试意图', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gateway = _Gateway([
      StateError('secret provider detail'),
      OrganizationShareableJoinApplicationApproveSuccess(_receipt),
    ]);
    await _confirmAndSubmit(tester, fixture.session, gateway);
    expect(find.textContaining('secret'), findsNothing);
    expect(_uncertain, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_keepRetry, findsOneWidget);
    expect(_discard, findsOneWidget);
    await tester.tap(_keepRetry);
    await tester.pumpAndSettle();
    await tester.tap(_submit);
    await tester.pumpAndSettle();
    expect(gateway.calls, hasLength(2));
    expect(gateway.calls.toSet(), {
      (applicationId: _applicationId, organizationWorkspaceId: _organizationId),
    });
    expect(_uncertain, findsNothing);
  });

  testWidgets('不确定到稳定 conflict 清除不确定性，仍锁定相同 intent', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gateway = _Gateway(const [
      OrganizationShareableJoinApplicationApproveRejected(
        OrganizationShareableJoinFailureCode.networkUnavailable,
      ),
      OrganizationShareableJoinApplicationApproveRejected(
        OrganizationShareableJoinFailureCode.conflict,
      ),
    ]);
    await _confirmAndSubmit(tester, fixture.session, gateway);
    expect(_uncertain, findsOneWidget);
    await tester.tap(_submit);
    await tester.pumpAndSettle();
    expect(_uncertain, findsNothing);
    expect(_edit, findsNothing);
    expect(gateway.calls.toSet(), {
      (applicationId: _applicationId, organizationWorkspaceId: _organizationId),
    });
    await tester.tap(_close);
    await tester.pumpAndSettle();
    expect(_dialog, findsNothing);
    expect(_discard, findsNothing);
  });

  testWidgets('系统返回也要求丢弃确认，明确丢弃后关闭', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gateway = _Gateway(const [
      OrganizationShareableJoinApplicationApproveRejected(
        OrganizationShareableJoinFailureCode.serviceUnavailable,
      ),
    ]);
    await _confirmAndSubmit(tester, fixture.session, gateway);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_dialog, findsOneWidget);
    expect(_discard, findsOneWidget);
    await tester.tap(_discard);
    await tester.pumpAndSettle();
    expect(_dialog, findsNothing);
    expect(gateway.calls, hasLength(1));
    expect(gateway.closed, isFalse);
  });

  testWidgets('busy 阻止重复调用、关闭、Escape 与系统返回', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final pending =
        Completer<OrganizationShareableJoinApplicationApproveResult>();
    final gateway = _Gateway([pending]);
    await _open(tester, fixture.session, gateway);
    await tester.enterText(_field, _applicationId);
    await tester.tap(_review);
    await tester.pumpAndSettle();
    final submit = tester.widget<FilledButton>(_submit).onPressed!;
    submit();
    submit();
    await tester.pump();
    expect(gateway.calls, hasLength(1));
    expect(tester.widget<FilledButton>(_submit).onPressed, isNull);
    expect(tester.widget<TextButton>(_close).onPressed, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_dialog, findsOneWidget);
    expect(_discard, findsNothing);
    pending.complete(
      OrganizationShareableJoinApplicationApproveSuccess(_receipt),
    );
    await tester.pumpAndSettle();
    expect(find.text(_receipt.organizationMembershipId), findsOneWidget);
  });

  testWidgets('同账号项目变化保留审批；捕获组织不随 widget 更新改变', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final organizations = ValueNotifier(_organization);
    addTearDown(organizations.dispose);
    final gateway = _Gateway(const [
      OrganizationShareableJoinApplicationApproveRejected(
        OrganizationShareableJoinFailureCode.forbidden,
      ),
      OrganizationShareableJoinApplicationApproveRejected(
        OrganizationShareableJoinFailureCode.forbidden,
      ),
    ]);
    await _open(tester, fixture.session, gateway, organizations: organizations);
    await tester.enterText(_field, _applicationId);
    await tester.tap(_review);
    await tester.pumpAndSettle();
    expect(
      await fixture.session.selectProject('project-b'),
      isA<SessionContextSuccess>(),
    );
    organizations.value = const OrganizationDirectoryEntry(
      organizationWorkspaceId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      organizationName: '另一个组织',
    );
    await tester.pumpAndSettle();
    await tester.tap(_submit);
    await tester.pumpAndSettle();
    await tester.tap(_submit);
    await tester.pumpAndSettle();
    expect(gateway.calls.toSet(), {
      (applicationId: _applicationId, organizationWorkspaceId: _organizationId),
    });
    expect(find.text('另一个组织'), findsNothing);
  });

  for (final aba in [false, true]) {
    testWidgets('${aba ? 'ABA' : '切账号'} 清空敏感状态并隔离迟到审批回执', (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final pending =
          Completer<OrganizationShareableJoinApplicationApproveResult>();
      final gateway = _Gateway([pending]);
      await _open(tester, fixture.session, gateway);
      await tester.enterText(_field, _applicationId);
      await tester.tap(_review);
      await tester.pumpAndSettle();
      await tester.tap(_submit);
      await tester.pump();
      fixture.identity.emit(_signedIn('subject-b'));
      await tester.pumpAndSettle();
      if (aba) {
        fixture.identity.emit(_signedIn('subject-a'));
        await tester.pumpAndSettle();
      }
      pending.complete(
        OrganizationShareableJoinApplicationApproveSuccess(_receipt),
      );
      await tester.pumpAndSettle();
      for (final value in [
        _applicationId,
        _organizationId,
        _organization.organizationName,
        _receipt.organizationMembershipId,
      ]) {
        expect(find.text(value), findsNothing);
      }
      expect(_submit, findsNothing);
      expect(_uncertain, findsNothing);
      expect(
        find.text(
          const AppStrings('zh').t('organizationShareableApprovalUnauthorized'),
        ),
        findsOneWidget,
      );
    });
  }

  testWidgets('注销清空已成功回执与本地输入，不能在重新登录后恢复', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gateway = _Gateway([
      OrganizationShareableJoinApplicationApproveSuccess(_receipt),
    ]);
    await _confirmAndSubmit(tester, fixture.session, gateway);
    fixture.identity.emit(const IdentitySnapshot.signedOut());
    await tester.pumpAndSettle();
    fixture.identity.emit(_signedIn('subject-a'));
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsNothing);
    expect(_field, findsNothing);
    expect(_submit, findsNothing);
  });

  testWidgets('Tab 可达核对按钮且各动作触控目标至少 48 logical pixels', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gateway = _Gateway([
      OrganizationShareableJoinApplicationApproveSuccess(_receipt),
    ]);
    await _open(tester, fixture.session, gateway);
    await tester.enterText(_field, _applicationId);
    for (final action in [_close, _review]) {
      final size = tester.getSize(action);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    expect(_hasFocus(tester, _close), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    expect(_hasFocus(tester, _review), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(gateway.calls, isEmpty);
    expect(_submit, findsOneWidget);
    for (final action in [_close, _edit, _submit]) {
      final size = tester.getSize(action);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
  });

  for (final locale in ['zh', 'en']) {
    testWidgets('$locale 320x568 / 200% 全阶段无溢出且状态可达', (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final semantics = tester.ensureSemantics();
      final organizations = ValueNotifier(
        OrganizationDirectoryEntry(
          organizationWorkspaceId: _organizationId,
          organizationName:
              'Long organization 很长的组织名称 ${List.filled(60, '界').join()}',
        ),
      );
      addTearDown(organizations.dispose);
      final gateway = _Gateway([
        const OrganizationShareableJoinApplicationApproveRejected(
          OrganizationShareableJoinFailureCode.networkUnavailable,
        ),
        OrganizationShareableJoinApplicationApproveSuccess(_receipt),
      ]);
      await _open(
        tester,
        fixture.session,
        gateway,
        locale: locale,
        textScaler: TextScaler.linear(2),
        organizations: organizations,
      );
      expect(tester.takeException(), isNull);
      await tester.enterText(_field, _applicationId);
      await tester.tap(_review);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(_submit);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final target in [_status, _uncertain]) {
        expect(
          tester
              .getSemantics(target)
              .getSemanticsData()
              .flagsCollection
              .isLiveRegion,
          isTrue,
        );
        await tester.ensureVisible(target);
        expect(tester.getRect(target).isEmpty, isFalse);
      }
      await tester.tap(_close);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(_keepRetry);
      await tester.pumpAndSettle();
      await tester.tap(_submit);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text(_receipt.organizationMembershipId), findsOneWidget);
      semantics.dispose();
    });
  }
}

final _dialog = find.byKey(
  const ValueKey('organization-shareable-approval-dialog'),
);
final _field = find.byKey(
  const ValueKey('organization-shareable-approval-application-field'),
);
final _review = find.byKey(
  const ValueKey('organization-shareable-approval-review'),
);
final _submit = find.byKey(
  const ValueKey('organization-shareable-approval-submit'),
);
final _edit = find.byKey(
  const ValueKey('organization-shareable-approval-edit'),
);
final _close = find.byKey(
  const ValueKey('organization-shareable-approval-close'),
);
final _status = find.byKey(
  const ValueKey('organization-shareable-approval-status'),
);
final _uncertain = find.byKey(
  const ValueKey('organization-shareable-approval-uncertain'),
);
final _keepRetry = find.byKey(
  const ValueKey('organization-shareable-approval-keep-retry'),
);
final _discard = find.byKey(
  const ValueKey('organization-shareable-approval-discard'),
);

bool _hasFocus(WidgetTester tester, Finder finder) {
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

Future<void> _confirmAndSubmit(
  WidgetTester tester,
  AppSession session,
  _Gateway gateway,
) async {
  await _open(tester, session, gateway);
  await tester.enterText(_field, _applicationId);
  await tester.tap(_review);
  await tester.pumpAndSettle();
  await tester.tap(_submit);
  await tester.pumpAndSettle();
}

Future<void> _open(
  WidgetTester tester,
  AppSession session,
  OrganizationShareableJoinGateway gateway, {
  String locale = 'zh',
  TextScaler textScaler = TextScaler.noScaling,
  ValueNotifier<OrganizationDirectoryEntry>? organizations,
}) async {
  Widget dialog(OrganizationDirectoryEntry organization) =>
      OrganizationShareableJoinApplicationApproveDialog(
        text: AppStrings(locale),
        organization: organization,
        gateway: gateway,
        appSession: session,
      );
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: FilledButton(
            key: const ValueKey('open-approval'),
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => organizations == null
                  ? dialog(_organization)
                  : ValueListenableBuilder<OrganizationDirectoryEntry>(
                      valueListenable: organizations,
                      builder: (_, organization, _) => dialog(organization),
                    ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open-approval')));
  await tester.pumpAndSettle();
}

final class _Gateway implements OrganizationShareableJoinGateway {
  _Gateway(Iterable<Object> results) : _results = Queue.of(results);
  final Queue<Object> _results;
  final calls = <({String applicationId, String organizationWorkspaceId})>[];
  var closed = false;

  @override
  Future<OrganizationShareableJoinApplicationApproveResult> approveApplication({
    required String applicationId,
    required String organizationWorkspaceId,
  }) async {
    calls.add((
      applicationId: applicationId,
      organizationWorkspaceId: organizationWorkspaceId,
    ));
    final next = _results.removeFirst();
    if (next is Completer<OrganizationShareableJoinApplicationApproveResult>) {
      return next.future;
    }
    if (next is OrganizationShareableJoinApplicationApproveResult) return next;
    throw next;
  }

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unused shareable join operation');
}

final class _Fixture {
  _Fixture(this.identity, this.session, this.context);
  final _IdentitySession identity;
  final AppSession session;
  final _ContextGateway context;

  static Future<_Fixture> create() async {
    final identity = _IdentitySession(_signedIn('subject-a'));
    final context = _ContextGateway();
    final session = AppSession(
      identitySession: identity,
      contextGateway: context,
    );
    await session.start();
    return _Fixture(identity, session, context);
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
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unused identity operation');
}

final class _ContextGateway implements SessionContextGateway {
  var selectCalls = 0;
  @override
  Future<SessionContextResult> resolve(IdentityAccessToken token) async =>
      SessionContextSuccess(_context(token.value));
  @override
  Future<SessionContextResult> selectProject(
    IdentityAccessToken token,
    String projectId,
  ) async {
    selectCalls += 1;
    return SessionContextSuccess(_context(token.value, projectB: true));
  }

  @override
  Future<void> close() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unused context operation');
}

TrustedSessionContext _context(String subject, {bool projectB = false}) =>
    TrustedSessionContext(
      appUserId: subject == 'subject-a'
          ? '99999999-9999-4999-8999-999999999999'
          : '12222222-2222-4222-8222-222222222222',
      workspace: const WorkspaceContext(
        id: '21111111-1111-4111-8111-111111111111',
        kind: WorkspaceKind.personal,
        name: '个人空间',
      ),
      project: ProjectContext(
        id: projectB
            ? '32222222-2222-4222-8222-222222222222'
            : '31111111-1111-4111-8111-111111111111',
        name: '项目',
      ),
      questionnaireVersion: const QuestionnaireVersionContext(
        id: '41111111-1111-4111-8111-111111111111',
        versionNumber: 1,
      ),
      capabilities: {},
    );

IdentitySnapshot _signedIn(String subject) => IdentitySnapshot(
  stage: IdentityStage.signedIn,
  principal: IdentityPrincipal(
    externalSubject: subject,
    email: '$subject@example.test',
  ),
  expiresAt: DateTime.utc(2030, subject == 'subject-a' ? 1 : 2),
);

const _applicationId = 'abcdefab-cdef-4abc-8def-abcdefabcdef';
const _organizationId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _organization = OrganizationDirectoryEntry(
  organizationWorkspaceId: _organizationId,
  organizationName: '测试组织',
);
final _receipt = OrganizationShareableJoinApplicationApproveReceipt(
  organizationShareableJoinApplicationContractId:
      'organization-shareable-join-application:v1',
  applicationId: _applicationId,
  organizationWorkspaceId: _organizationId,
  organizationMembershipId: '12345678-1234-4234-8234-123456789abc',
  approvedAtUtc: DateTime.parse('2030-01-02T12:05:06.123+08:00'),
);
