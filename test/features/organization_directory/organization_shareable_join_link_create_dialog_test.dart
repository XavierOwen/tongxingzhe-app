import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/app_session/app_session.dart';
import 'package:tongxingzhe_app/app_session/session_context_gateway.dart';
import 'package:tongxingzhe_app/features/organization_directory/organization_shareable_join_link_create_dialog.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/l10n/app_strings.dart';
import 'package:tongxingzhe_app/organization_directory/organization_directory.dart';
import 'package:tongxingzhe_app/organization_shareable_join/organization_shareable_join.dart';

void main() {
  testWidgets('首次提交生成 canonical UUID，成功显示五项并显式复制', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final clipboard = _ClipboardProbe();
    addTearDown(clipboard.close);
    final gateway = _Gateway([
      OrganizationShareableJoinLinkCreateSuccess(_receipt),
    ]);
    final ids = _Ids();
    await _open(tester, fixture.session, gateway, ids.next);

    expect(ids.count, 0);
    expect(clipboard.values, isEmpty);
    await tester.tap(_submit);
    await tester.pumpAndSettle();

    expect(ids.count, 1);
    expect(gateway.calls.single.linkId, _linkId);
    expect(
      gateway.calls.single.organizationWorkspaceId,
      _organization.organizationWorkspaceId,
    );
    for (final value in [
      _organization.organizationName,
      _organization.organizationWorkspaceId,
      _receipt.linkId,
      _receipt.issuedAtUtc.toUtc().toIso8601String(),
      _receipt.expiresAtUtc.toUtc().toIso8601String(),
    ]) {
      expect(find.text(value), findsOneWidget);
    }
    expect(clipboard.values, isEmpty);

    await tester.tap(_copy);
    await tester.pumpAndSettle();
    expect(clipboard.values, [_linkId]);
    expect(gateway.calls, hasLength(1));
  });

  testWidgets('复制失败可重试且不重新 create', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final clipboard = _ClipboardProbe()..fail = true;
    addTearDown(clipboard.close);
    final gateway = _Gateway([
      OrganizationShareableJoinLinkCreateSuccess(_receipt),
    ]);
    await _open(tester, fixture.session, gateway, _Ids().next);
    await tester.tap(_submit);
    await tester.pumpAndSettle();

    await tester.tap(_copy);
    await tester.pumpAndSettle();
    expect(
      find.text(
        const AppStrings('zh').t('organizationShareableLinkCreateCopyFailure'),
      ),
      findsOneWidget,
    );
    clipboard.fail = false;
    await tester.tap(_copy);
    await tester.pumpAndSettle();
    expect(clipboard.values, [_linkId, _linkId]);
    expect(gateway.calls, hasLength(1));
  });

  for (final uncertain in <OrganizationShareableJoinFailureCode?>[
    OrganizationShareableJoinFailureCode.networkUnavailable,
    OrganizationShareableJoinFailureCode.serviceUnavailable,
    OrganizationShareableJoinFailureCode.invalidResponse,
    OrganizationShareableJoinFailureCode.conflict,
    null,
  ]) {
    testWidgets('不确定 ${uncertain?.name ?? 'throw'} 固定 UUID，可保留后重试或确认放弃', (
      tester,
    ) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final gateway = _Gateway([
        uncertain == null
            ? StateError('secret provider detail')
            : OrganizationShareableJoinLinkCreateRejected(uncertain),
        OrganizationShareableJoinLinkCreateSuccess(_receipt),
      ]);
      final ids = _Ids();
      await _open(tester, fixture.session, gateway, ids.next);
      await tester.tap(_submit);
      await tester.pumpAndSettle();

      expect(_uncertain, findsOneWidget);
      expect(ids.count, 1);
      await tester.tap(_close);
      await tester.pump();
      expect(_keepRetry, findsOneWidget);
      expect(_discard, findsOneWidget);
      await tester.tap(_keepRetry);
      await tester.pump();
      await tester.tap(_submit);
      await tester.pumpAndSettle();

      expect(gateway.calls, hasLength(2));
      expect(gateway.calls.map((call) => call.linkId).toSet(), {_linkId});
      expect(
        gateway.calls.map((call) => call.organizationWorkspaceId).toSet(),
        {_organization.organizationWorkspaceId},
      );
      expect(ids.count, 1);
    });
  }

  testWidgets('不确定结果可确认放弃，且不关闭 gateway', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gateway = _Gateway(const [
      OrganizationShareableJoinLinkCreateRejected(
        OrganizationShareableJoinFailureCode.networkUnavailable,
      ),
    ]);
    await _open(tester, fixture.session, gateway, _Ids().next);
    await tester.tap(_submit);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(_discard, findsOneWidget);
    await tester.tap(_discard);
    await tester.pumpAndSettle();
    expect(
      find.byType(OrganizationShareableJoinLinkCreateDialog),
      findsNothing,
    );
    expect(gateway.closed, isFalse);
  });

  testWidgets('同账号切项目不失效；账号 ABA 永久失效并隔离迟到结果', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final pending = Completer<OrganizationShareableJoinLinkCreateResult>();
    final gateway = _Gateway([pending]);
    await _open(tester, fixture.session, gateway, _Ids().next);

    final switched = await fixture.session.selectProject('project-b');
    expect(switched, isA<SessionContextSuccess>());
    await tester.pumpAndSettle();
    expect(_submit, findsOneWidget);
    await tester.tap(_submit);
    await tester.pump();

    fixture.identity.emit(const IdentitySnapshot.signedOut());
    await tester.pumpAndSettle();
    fixture.identity.emit(_signedIn('subject-b'));
    await tester.pumpAndSettle();
    fixture.identity.emit(_signedIn('subject-a'));
    await tester.pumpAndSettle();
    expect(_submit, findsNothing);
    expect(_copy, findsNothing);
    pending.complete(OrganizationShareableJoinLinkCreateSuccess(_receipt));
    await tester.pumpAndSettle();
    expect(find.text(_receipt.linkId), findsNothing);
    expect(
      find.text(
        const AppStrings('zh').t('organizationShareableLinkCreateUnauthorized'),
      ),
      findsOneWidget,
    );
  });

  for (final code in const [
    OrganizationShareableJoinFailureCode.notConfigured,
    OrganizationShareableJoinFailureCode.invalidJson,
    OrganizationShareableJoinFailureCode.payloadTooLarge,
    OrganizationShareableJoinFailureCode.invalidRequest,
    OrganizationShareableJoinFailureCode.forbidden,
  ]) {
    for (final localeCode in const ['zh', 'en']) {
      testWidgets('${code.name} $localeCode 显示固定脱敏失败', (tester) async {
        final fixture = await _Fixture.create();
        addTearDown(fixture.close);
        final gateway = _Gateway([
          OrganizationShareableJoinLinkCreateRejected(code),
        ]);
        await _open(
          tester,
          fixture.session,
          gateway,
          _Ids().next,
          localeCode: localeCode,
        );
        await tester.tap(_submit);
        await tester.pumpAndSettle();
        expect(
          find.text(
            AppStrings(
              localeCode,
            ).t('organizationShareableLinkCreateFailure.${code.name}'),
          ),
          findsOneWidget,
        );
        expect(find.textContaining('secret'), findsNothing);
        expect(gateway.calls, hasLength(1));
      });
    }
  }

  testWidgets('unauthorized 永久失效', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gateway = _Gateway(const [
      OrganizationShareableJoinLinkCreateRejected(
        OrganizationShareableJoinFailureCode.unauthorized,
      ),
    ]);
    await _open(tester, fixture.session, gateway, _Ids().next);
    await tester.tap(_submit);
    await tester.pumpAndSettle();
    expect(_submit, findsNothing);
    expect(_copy, findsNothing);
    expect(
      find.text(
        const AppStrings('zh').t('organizationShareableLinkCreateUnauthorized'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('账号失效清除回执并忽略迟到复制状态', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final clipboard = _ClipboardProbe()..pending = Completer<void>();
    addTearDown(clipboard.close);
    final gateway = _Gateway([
      OrganizationShareableJoinLinkCreateSuccess(_receipt),
    ]);
    await _open(tester, fixture.session, gateway, _Ids().next);
    await tester.tap(_submit);
    await tester.pumpAndSettle();
    await tester.tap(_copy);
    await tester.pump();

    fixture.identity.emit(const IdentitySnapshot.signedOut());
    await tester.pump();
    expect(find.text(_receipt.linkId), findsNothing);
    expect(_copy, findsNothing);

    clipboard.pending!.complete();
    await tester.pumpAndSettle();
    expect(
      find.text(
        const AppStrings('zh').t('organizationShareableLinkCreateCopySuccess'),
      ),
      findsNothing,
    );
    expect(find.text(_receipt.linkId), findsNothing);
  });

  testWidgets('非法 generator 不触网', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gateway = _Gateway();
    await _open(tester, fixture.session, gateway, () => 'not-a-uuid');
    await tester.tap(_submit);
    await tester.pumpAndSettle();
    expect(gateway.calls, isEmpty);
    expect(
      find.text(
        const AppStrings(
          'zh',
        ).t('organizationShareableLinkCreateInvalidRequest'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('提交中忽略重复提交和关闭', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final pending = Completer<OrganizationShareableJoinLinkCreateResult>();
    final gateway = _Gateway([pending]);
    await _open(tester, fixture.session, gateway, _Ids().next);
    await tester.tap(_submit);
    await tester.tap(_submit, warnIfMissed: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(gateway.calls, hasLength(1));
    expect(
      find.byType(OrganizationShareableJoinLinkCreateDialog),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(_submit).onPressed, isNull);
    pending.complete(OrganizationShareableJoinLinkCreateSuccess(_receipt));
    await tester.pumpAndSettle();
  });

  testWidgets('320x568、200% 字号无异常且操作可达', (tester) async {
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
        OrganizationShareableJoinLinkCreateRejected(
          OrganizationShareableJoinFailureCode.networkUnavailable,
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
    for (final target in [_submit, _close]) {
      final rect = tester.getSemantics(target).rect;
      expect(rect.width, greaterThanOrEqualTo(48));
      expect(rect.height, greaterThanOrEqualTo(48));
    }
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
    semantics.dispose();
  });
}

final _launcher = find.byKey(
  const ValueKey('open-organization-shareable-link-create'),
);
final _submit = find.byKey(
  const ValueKey('organization-shareable-link-create-submit'),
);
final _copy = find.byKey(
  const ValueKey('organization-shareable-link-create-copy'),
);
final _close = find.byKey(
  const ValueKey('organization-shareable-link-create-close'),
);
final _status = find.byKey(
  const ValueKey('organization-shareable-link-create-status'),
);
final _uncertain = find.byKey(
  const ValueKey('organization-shareable-link-create-uncertain'),
);
final _keepRetry = find.byKey(
  const ValueKey('organization-shareable-link-create-keep-retry'),
);
final _discard = find.byKey(
  const ValueKey('organization-shareable-link-create-discard'),
);

Future<void> _open(
  WidgetTester tester,
  AppSession session,
  OrganizationShareableJoinGateway gateway,
  String Function() linkIdGenerator, {
  OrganizationDirectoryEntry organization = _organization,
  String localeCode = 'zh',
  TextScaler textScaler = TextScaler.noScaling,
}) async {
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
            key: const ValueKey('open-organization-shareable-link-create'),
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => OrganizationShareableJoinLinkCreateDialog(
                text: AppStrings(localeCode),
                organization: organization,
                gateway: gateway,
                appSession: session,
                linkIdGenerator: linkIdGenerator,
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(_launcher);
  await tester.pumpAndSettle();
}

final class _Gateway implements OrganizationShareableJoinGateway {
  _Gateway([Iterable<Object> results = const []])
    : _results = Queue.of(results);

  final Queue<Object> _results;
  final calls = <({String linkId, String organizationWorkspaceId})>[];
  var closed = false;

  @override
  Future<OrganizationShareableJoinLinkCreateResult> createLink({
    required String linkId,
    required String organizationWorkspaceId,
  }) async {
    calls.add((
      linkId: linkId,
      organizationWorkspaceId: organizationWorkspaceId,
    ));
    if (_results.isEmpty) {
      return const OrganizationShareableJoinLinkCreateRejected(
        OrganizationShareableJoinFailureCode.notConfigured,
      );
    }
    final next = _results.removeFirst();
    if (next is Completer<OrganizationShareableJoinLinkCreateResult>) {
      return next.future;
    }
    if (next is OrganizationShareableJoinLinkCreateResult) return next;
    throw next;
  }

  @override
  Future<void> close() async => closed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unused shareable join operation');
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
            await pending?.future;
          }
          return null;
        });
  }

  final values = <String>[];
  var fail = false;
  Completer<void>? pending;

  void close() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  }
}

final class _Ids {
  var count = 0;

  String next() => [_linkId, _otherLinkId][count++];
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
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unused identity operation');
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
  ) async => SessionContextSuccess(_contextAWithProjectB);

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unused context operation');
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
const _linkId = 'abcdefab-cdef-4abc-8def-abcdefabcdef';
const _otherLinkId = 'abcdefab-cdef-4abc-8def-abcdefabcdea';

final _receipt = OrganizationShareableJoinLinkCreateReceipt(
  organizationShareableJoinLinkContractId:
      'organization-shareable-join-link:v1',
  linkId: _linkId,
  organizationWorkspaceId: _organization.organizationWorkspaceId,
  issuedAtUtc: DateTime.utc(2030, 1, 2, 4, 5, 6),
  expiresAtUtc: DateTime.utc(2030, 1, 9, 4, 5, 6),
);

const _contextA = TrustedSessionContext(
  appUserId: '99999999-9999-4999-8999-999999999999',
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

const _contextAWithProjectB = TrustedSessionContext(
  appUserId: '99999999-9999-4999-8999-999999999999',
  workspace: WorkspaceContext(
    id: '21111111-1111-4111-8111-111111111111',
    kind: WorkspaceKind.personal,
    name: '个人空间',
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

const _contextB = TrustedSessionContext(
  appUserId: '12222222-2222-4222-8222-222222222222',
  workspace: WorkspaceContext(
    id: '22222222-2222-4222-8222-222222222222',
    kind: WorkspaceKind.personal,
    name: '个人空间乙',
  ),
  project: ProjectContext(
    id: '32333333-3333-4333-8333-333333333333',
    name: '项目丙',
  ),
  questionnaireVersion: QuestionnaireVersionContext(
    id: '42333333-3333-4333-8333-333333333333',
    versionNumber: 3,
  ),
  capabilities: {},
);
