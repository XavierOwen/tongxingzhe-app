import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/app_session/app_session.dart';
import 'package:tongxingzhe_app/app_session/session_context_gateway.dart';
import 'package:tongxingzhe_app/features/organization_directory/organization_shareable_join_application_submit_dialog.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/l10n/app_strings.dart';
import 'package:tongxingzhe_app/organization_shareable_join/organization_shareable_join.dart';

void main() {
  testWidgets('borrowed session retirement fences a late application receipt', (
    tester,
  ) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final pending =
        Completer<OrganizationShareableJoinApplicationSubmitResult>();
    final gateway = _Gateway(
      previews: [OrganizationShareableJoinLinkPreviewSuccess(_previewReceipt)],
      submits: [pending],
    );
    await _open(tester, fixture.session, gateway, _Ids().next);
    await tester.enterText(_linkField, _linkId);
    await tester.tap(_preview);
    await tester.pumpAndSettle();
    await tester.tap(_submit);
    await tester.pump();
    await tester.runAsync(fixture.session.close);
    await tester.pumpAndSettle();
    expect(_submit, findsNothing);
    pending.complete(
      OrganizationShareableJoinApplicationSubmitSuccess(_submitReceipt),
    );
    await tester.pumpAndSettle();
    expect(find.text(_submitReceipt.applicationId), findsNothing);
    expect(_copy, findsNothing);
    expect(gateway.closed, isFalse);
  });

  testWidgets(
    'borrowed session retirement hides the submitted application receipt',
    (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final gateway = _Gateway(
        previews: [
          OrganizationShareableJoinLinkPreviewSuccess(_previewReceipt),
        ],
        submits: [
          OrganizationShareableJoinApplicationSubmitSuccess(_submitReceipt),
        ],
      );
      await _open(tester, fixture.session, gateway, _Ids().next);
      await tester.enterText(_linkField, _linkId);
      await tester.tap(_preview);
      await tester.pumpAndSettle();
      await tester.tap(_submit);
      await tester.pumpAndSettle();
      expect(find.text(_submitReceipt.applicationId), findsOneWidget);
      await tester.runAsync(fixture.session.close);
      await tester.pumpAndSettle();
      expect(find.text(_submitReceipt.applicationId), findsNothing);
      expect(find.text(_previewReceipt.organizationName), findsNothing);
      expect(_submit, findsNothing);
      expect(_copy, findsNothing);
      expect(gateway.closed, isFalse);
    },
  );

  testWidgets('preview 后明确 submit，成功留窗并显式复制 application UUID', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final clipboard = _ClipboardProbe();
    addTearDown(clipboard.close);
    final gateway = _Gateway(
      previews: [OrganizationShareableJoinLinkPreviewSuccess(_previewReceipt)],
      submits: [
        OrganizationShareableJoinApplicationSubmitSuccess(_submitReceipt),
      ],
    );
    final ids = _Ids();
    await _open(tester, fixture.session, gateway, ids.next);

    await tester.enterText(_linkField, '  ${_linkId.toUpperCase()}  ');
    await tester.tap(_preview);
    await tester.pumpAndSettle();

    expect(gateway.previewCalls, [_linkId]);
    expect(gateway.submitCalls, isEmpty);
    expect(ids.count, 0);
    expect(find.text(_previewReceipt.organizationName), findsOneWidget);
    expect(
      find.text(_previewReceipt.expiresAtUtc.toIso8601String()),
      findsOneWidget,
    );

    await tester.tap(_submit);
    await tester.pumpAndSettle();

    expect(ids.count, 1);
    expect(gateway.submitCalls.single, (
      applicationId: _applicationId,
      linkId: _linkId,
    ));
    for (final value in [
      _previewReceipt.organizationName,
      _submitReceipt.applicationId,
      _submitReceipt.linkId,
      _submitReceipt.organizationWorkspaceId,
      _submitReceipt.submittedAtUtc.toIso8601String(),
      _submitReceipt.expiresAtUtc.toIso8601String(),
    ]) {
      expect(find.text(value), findsOneWidget);
    }
    expect(clipboard.values, isEmpty);

    await tester.tap(_copy);
    await tester.pumpAndSettle();
    expect(clipboard.values, [_applicationId]);
    expect(gateway.submitCalls, hasLength(1));
  });

  for (final uncertain in <OrganizationShareableJoinFailureCode?>[
    OrganizationShareableJoinFailureCode.networkUnavailable,
    OrganizationShareableJoinFailureCode.serviceUnavailable,
    OrganizationShareableJoinFailureCode.invalidResponse,
    null,
  ]) {
    testWidgets(
      '${uncertain?.name ?? 'throw'} 不确定结果锁定 link 与 application UUID',
      (tester) async {
        final fixture = await _Fixture.create();
        addTearDown(fixture.close);
        final gateway = _Gateway(
          previews: [
            OrganizationShareableJoinLinkPreviewSuccess(_previewReceipt),
          ],
          submits: [
            uncertain == null
                ? StateError('secret provider detail')
                : OrganizationShareableJoinApplicationSubmitRejected(uncertain),
            OrganizationShareableJoinApplicationSubmitSuccess(_submitReceipt),
          ],
        );
        final ids = _Ids();
        await _previewAndSubmit(tester, fixture.session, gateway, ids.next);

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

        expect(gateway.previewCalls, [_linkId]);
        expect(gateway.submitCalls, hasLength(2));
        expect(gateway.submitCalls.toSet(), {
          (applicationId: _applicationId, linkId: _linkId),
        });
        expect(ids.count, 1);
      },
    );
  }

  testWidgets('conflict 是稳定拒绝，重试不生成新意图', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gateway = _Gateway(
      previews: [OrganizationShareableJoinLinkPreviewSuccess(_previewReceipt)],
      submits: const [
        OrganizationShareableJoinApplicationSubmitRejected(
          OrganizationShareableJoinFailureCode.conflict,
        ),
        OrganizationShareableJoinApplicationSubmitRejected(
          OrganizationShareableJoinFailureCode.conflict,
        ),
      ],
    );
    final ids = _Ids();
    await _previewAndSubmit(tester, fixture.session, gateway, ids.next);

    expect(_uncertain, findsNothing);
    expect(find.textContaining('secret'), findsNothing);
    await tester.tap(_submit);
    await tester.pumpAndSettle();
    expect(ids.count, 1);
    expect(gateway.previewCalls, hasLength(1));
    expect(gateway.submitCalls.toSet(), {
      (applicationId: _applicationId, linkId: _linkId),
    });
  });

  testWidgets('不确定结果后收到 conflict 会结束不确定状态', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gateway = _Gateway(
      previews: [OrganizationShareableJoinLinkPreviewSuccess(_previewReceipt)],
      submits: const [
        OrganizationShareableJoinApplicationSubmitRejected(
          OrganizationShareableJoinFailureCode.networkUnavailable,
        ),
        OrganizationShareableJoinApplicationSubmitRejected(
          OrganizationShareableJoinFailureCode.conflict,
        ),
      ],
    );
    final ids = _Ids();
    await _previewAndSubmit(tester, fixture.session, gateway, ids.next);
    expect(_uncertain, findsOneWidget);

    await tester.tap(_submit);
    await tester.pumpAndSettle();
    expect(_uncertain, findsNothing);
    expect(ids.count, 1);
    expect(gateway.previewCalls, [_linkId]);
    expect(gateway.submitCalls.toSet(), {
      (applicationId: _applicationId, linkId: _linkId),
    });

    await tester.tap(_close);
    await tester.pumpAndSettle();
    expect(
      find.byType(OrganizationShareableJoinApplicationSubmitDialog),
      findsNothing,
    );
    expect(_discard, findsNothing);
  });

  testWidgets('同账号切项目有效；ABA 清空并隔离迟到 preview', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final pending = Completer<OrganizationShareableJoinLinkPreviewResult>();
    final gateway = _Gateway(previews: [pending]);
    await _open(tester, fixture.session, gateway, _Ids().next);

    final switched = await fixture.session.selectProject('project-b');
    expect(switched, isA<SessionContextSuccess>());
    await tester.pumpAndSettle();
    await tester.enterText(_linkField, _linkId);
    await tester.tap(_preview);
    await tester.pump();

    fixture.identity.emit(const IdentitySnapshot.signedOut());
    await tester.pumpAndSettle();
    fixture.identity.emit(_signedIn('subject-b'));
    await tester.pumpAndSettle();
    fixture.identity.emit(_signedIn('subject-a'));
    await tester.pumpAndSettle();
    pending.complete(
      OrganizationShareableJoinLinkPreviewSuccess(_previewReceipt),
    );
    await tester.pumpAndSettle();

    expect(_linkField, findsNothing);
    expect(_submit, findsNothing);
    expect(find.text(_previewReceipt.organizationName), findsNothing);
    expect(
      find.text(
        const AppStrings(
          'zh',
        ).t('organizationShareableApplicationUnauthorized'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('账号失效清除回执并忽略迟到 Clipboard 结果', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final clipboard = _ClipboardProbe()..pending = Completer<void>();
    addTearDown(clipboard.close);
    final gateway = _Gateway(
      previews: [OrganizationShareableJoinLinkPreviewSuccess(_previewReceipt)],
      submits: [
        OrganizationShareableJoinApplicationSubmitSuccess(_submitReceipt),
      ],
    );
    await _previewAndSubmit(tester, fixture.session, gateway, _Ids().next);
    await tester.tap(_copy);
    await tester.pump();

    fixture.identity.emit(const IdentitySnapshot.signedOut());
    await tester.pump();
    expect(find.text(_applicationId), findsNothing);
    expect(find.text(_previewReceipt.organizationName), findsNothing);
    expect(_copy, findsNothing);
    clipboard.pending!.complete();
    await tester.pumpAndSettle();
    expect(
      find.text(
        const AppStrings('zh').t('organizationShareableApplicationCopySuccess'),
      ),
      findsNothing,
    );
  });

  testWidgets('复制失败只重试 Clipboard，不重新 submit', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final clipboard = _ClipboardProbe()..fail = true;
    addTearDown(clipboard.close);
    final gateway = _Gateway(
      previews: [OrganizationShareableJoinLinkPreviewSuccess(_previewReceipt)],
      submits: [
        OrganizationShareableJoinApplicationSubmitSuccess(_submitReceipt),
      ],
    );
    await _previewAndSubmit(tester, fixture.session, gateway, _Ids().next);

    await tester.tap(_copy);
    await tester.pumpAndSettle();
    expect(
      find.text(
        const AppStrings('zh').t('organizationShareableApplicationCopyFailure'),
      ),
      findsOneWidget,
    );
    clipboard.fail = false;
    await tester.tap(_copy);
    await tester.pumpAndSettle();
    expect(clipboard.values, [_applicationId, _applicationId]);
    expect(gateway.submitCalls, hasLength(1));
  });

  testWidgets('账号失效清除申请意图并忽略迟到 submit', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final pending =
        Completer<OrganizationShareableJoinApplicationSubmitResult>();
    final gateway = _Gateway(
      previews: [OrganizationShareableJoinLinkPreviewSuccess(_previewReceipt)],
      submits: [pending],
    );
    await _open(tester, fixture.session, gateway, _Ids().next);
    await tester.enterText(_linkField, _linkId);
    await tester.tap(_preview);
    await tester.pumpAndSettle();
    await tester.tap(_submit);
    await tester.pump();

    fixture.identity.emit(const IdentitySnapshot.signedOut());
    await tester.pump();
    pending.complete(
      OrganizationShareableJoinApplicationSubmitSuccess(_submitReceipt),
    );
    await tester.pumpAndSettle();

    expect(find.text(_applicationId), findsNothing);
    expect(find.text(_previewReceipt.organizationName), findsNothing);
    expect(_copy, findsNothing);
    expect(
      find.text(
        const AppStrings(
          'zh',
        ).t('organizationShareableApplicationUnauthorized'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Enter 可 preview，非法 UUID 不触网', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gateway = _Gateway(
      previews: [OrganizationShareableJoinLinkPreviewSuccess(_previewReceipt)],
    );
    await _open(tester, fixture.session, gateway, _Ids().next);

    await tester.enterText(_linkField, 'not-a-uuid');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(gateway.previewCalls, isEmpty);

    await tester.enterText(_linkField, _linkId);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(gateway.previewCalls, [_linkId]);
    expect(_submit, findsOneWidget);
  });

  testWidgets('320x568、200% 字号无异常且状态可达', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final semantics = tester.ensureSemantics();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final gateway = _Gateway(
      previews: [
        OrganizationShareableJoinLinkPreviewSuccess(
          OrganizationShareableJoinLinkPreviewReceipt(
            organizationShareableJoinLinkPreviewContractId:
                'organization-shareable-join-link-preview:v1',
            linkId: _linkId,
            organizationName: '很长的组织名称 ${List.filled(60, '界').join()}',
            expiresAtUtc: DateTime.utc(2030, 1, 9),
          ),
        ),
      ],
      submits: const [
        OrganizationShareableJoinApplicationSubmitRejected(
          OrganizationShareableJoinFailureCode.networkUnavailable,
        ),
      ],
    );
    await _open(
      tester,
      fixture.session,
      gateway,
      _Ids().next,
      textScaler: TextScaler.linear(2),
    );
    await tester.enterText(_linkField, _linkId);
    await tester.tap(_preview);
    await tester.pumpAndSettle();
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

  for (final localeCode in ['zh', 'en']) {
    testWidgets('$localeCode 软键盘与 200% 字号保留完整输入区', (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      tester.view.viewInsets = const FakeViewPadding(bottom: 307);
      tester.view.padding = const FakeViewPadding(top: 24);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.view.resetPadding);

      await _open(
        tester,
        fixture.session,
        _Gateway(),
        _Ids().next,
        localeCode: localeCode,
        textScaler: TextScaler.linear(2),
      );
      await tester.enterText(_linkField, _linkId);
      await tester.ensureVisible(_linkField);
      await tester.pumpAndSettle();

      final viewport = find.ancestor(
        of: _linkField,
        matching: find.byType(SingleChildScrollView),
      );
      expect(viewport, findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(viewport).height,
        greaterThanOrEqualTo(tester.getSize(_linkField).height),
      );
      for (final action in [_close, _preview]) {
        final rect = tester.getRect(action);
        expect(rect.bottom, lessThanOrEqualTo(568 - 307));
        expect(rect.height, greaterThanOrEqualTo(48));
        expect(rect.width, greaterThanOrEqualTo(48));
      }
    });
  }
}

final _launcher = find.byKey(
  const ValueKey('open-organization-shareable-application'),
);
final _linkField = find.byKey(
  const ValueKey('organization-shareable-application-link-field'),
);
final _preview = find.byKey(
  const ValueKey('organization-shareable-application-preview'),
);
final _submit = find.byKey(
  const ValueKey('organization-shareable-application-submit'),
);
final _copy = find.byKey(
  const ValueKey('organization-shareable-application-copy'),
);
final _close = find.byKey(
  const ValueKey('organization-shareable-application-close'),
);
final _status = find.byKey(
  const ValueKey('organization-shareable-application-status'),
);
final _uncertain = find.byKey(
  const ValueKey('organization-shareable-application-uncertain'),
);
final _keepRetry = find.byKey(
  const ValueKey('organization-shareable-application-keep-retry'),
);
final _discard = find.byKey(
  const ValueKey('organization-shareable-application-discard'),
);

Future<void> _previewAndSubmit(
  WidgetTester tester,
  AppSession session,
  _Gateway gateway,
  String Function() idGenerator,
) async {
  await _open(tester, session, gateway, idGenerator);
  await tester.enterText(_linkField, _linkId);
  await tester.tap(_preview);
  await tester.pumpAndSettle();
  await tester.tap(_submit);
  await tester.pumpAndSettle();
}

Future<void> _open(
  WidgetTester tester,
  AppSession session,
  OrganizationShareableJoinGateway gateway,
  String Function() idGenerator, {
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
            key: const ValueKey('open-organization-shareable-application'),
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => OrganizationShareableJoinApplicationSubmitDialog(
                text: AppStrings(localeCode),
                gateway: gateway,
                appSession: session,
                applicationIdGenerator: idGenerator,
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
  _Gateway({
    Iterable<Object> previews = const [],
    Iterable<Object> submits = const [],
  }) : _previews = Queue.of(previews),
       _submits = Queue.of(submits);

  final Queue<Object> _previews;
  final Queue<Object> _submits;
  final previewCalls = <String>[];
  final submitCalls = <({String applicationId, String linkId})>[];
  var closed = false;

  @override
  Future<OrganizationShareableJoinLinkPreviewResult> previewLink({
    required String linkId,
  }) async {
    previewCalls.add(linkId);
    final next = _previews.removeFirst();
    if (next is Completer<OrganizationShareableJoinLinkPreviewResult>) {
      return next.future;
    }
    if (next is OrganizationShareableJoinLinkPreviewResult) return next;
    throw next;
  }

  @override
  Future<OrganizationShareableJoinApplicationSubmitResult> submitApplication({
    required String applicationId,
    required String linkId,
  }) async {
    submitCalls.add((applicationId: applicationId, linkId: linkId));
    final next = _submits.removeFirst();
    if (next is Completer<OrganizationShareableJoinApplicationSubmitResult>) {
      return next.future;
    }
    if (next is OrganizationShareableJoinApplicationSubmitResult) return next;
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
  Completer<void>? pending;
  var fail = false;

  void close() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  }
}

final class _Ids {
  var count = 0;

  String next() {
    count += 1;
    return _applicationId;
  }
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
  ) async => const SessionContextSuccess(_contextAWithProjectB);

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

const _linkId = 'abcdefab-cdef-4abc-8def-abcdefabcdef';
const _applicationId = '12345678-1234-4234-8234-123456789abc';

final _previewReceipt = OrganizationShareableJoinLinkPreviewReceipt(
  organizationShareableJoinLinkPreviewContractId:
      'organization-shareable-join-link-preview:v1',
  linkId: _linkId,
  organizationName: '测试组织',
  expiresAtUtc: DateTime.utc(2030, 1, 9, 4, 5, 6),
);

final _submitReceipt = OrganizationShareableJoinApplicationSubmitReceipt(
  organizationShareableJoinApplicationContractId:
      'organization-shareable-join-application:v1',
  applicationId: _applicationId,
  linkId: _linkId,
  organizationWorkspaceId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  submittedAtUtc: DateTime.utc(2030, 1, 2, 4, 5, 6),
  expiresAtUtc: DateTime.utc(2030, 1, 16, 4, 5, 6),
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
