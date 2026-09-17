import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/app_session/app_session.dart';
import 'package:tongxingzhe_app/app_session/session_context_gateway.dart';
import 'package:tongxingzhe_app/features/organization_directory/organization_shareable_join_application_directory_dialog.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/l10n/app_strings.dart';
import 'package:tongxingzhe_app/organization_directory/organization_directory.dart';
import 'package:tongxingzhe_app/organization_shareable_join/organization_shareable_join.dart';

void main() {
  testWidgets(
    'reads fixed organization once; expansion is readonly and refresh is explicit',
    (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final gateway = _Gateway([_success(), _success(empty: true)]);
      await _open(tester, fixture.session, gateway);
      expect(gateway.reads, [_workspace]);
      expect(gateway.approvals, isEmpty);
      expect(find.text(_application), findsOneWidget);
      await tester.ensureVisible(_details);
      await tester.tap(_details);
      await tester.pumpAndSettle();
      for (final value in [
        _link,
        _record.submittedAtUtc.toIso8601String(),
        _record.expiresAtUtc.toIso8601String(),
      ]) {
        expect(find.text(value), findsOneWidget);
      }
      expect(gateway.reads, [_workspace]);
      await tester.tap(_refresh);
      await tester.pumpAndSettle();
      expect(gateway.reads, [_workspace, _workspace]);
      expect(find.text(_application), findsNothing);
      expect(
        find.text(
          const AppStrings(
            'zh',
          ).t('organizationShareableApplicationDirectoryEmpty'),
        ),
        findsOneWidget,
      );
      await tester.tap(_close);
      await tester.pumpAndSettle();
      expect(gateway.closed, isFalse);
      expect(fixture.context.selectCalls, 0);
    },
  );

  testWidgets(
    'selection only prefills; review and explicit approval remain separate; close never rereads',
    (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final gateway = _Gateway([_success()]);
      final writes = <Object?>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') writes.add(call.arguments);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await _open(tester, fixture.session, gateway);
      await _openApproval(tester);
      expect(
        tester.widget<TextField>(_approvalField).controller!.text,
        _application,
      );
      expect(gateway.approvals, isEmpty);
      expect(_approvalSubmit, findsNothing);
      await tester.tap(_approvalReview);
      await tester.pumpAndSettle();
      expect(gateway.approvals, isEmpty);
      await tester.tap(_approvalSubmit);
      await tester.pumpAndSettle();
      expect(gateway.approvals, [
        (workspace: _workspace, application: _application),
      ]);
      expect(find.text(_membership), findsOneWidget);
      await tester.tap(_approvalClose);
      await tester.pumpAndSettle();
      expect(gateway.reads, [_workspace]);
      expect(
        find.text(
          const AppStrings(
            'zh',
          ).t('organizationShareableApplicationDirectoryApprovalClosed'),
        ),
        findsOneWidget,
      );
      expect(writes, isEmpty);
      expect(fixture.context.selectCalls, 0);
      expect(gateway.closed, isFalse);
    },
  );

  for (final code in OrganizationShareableJoinFailureCode.values) {
    testWidgets('typed ${code.name} rejection clears records and is readable', (
      tester,
    ) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final gateway = _Gateway([
        _success(),
        OrganizationShareableJoinApplicationDirectoryRejected(code),
      ]);
      await _open(tester, fixture.session, gateway);
      await tester.tap(_refresh);
      await tester.pumpAndSettle();
      expect(find.text(_application), findsNothing);
      final key = code == OrganizationShareableJoinFailureCode.unauthorized
          ? 'organizationShareableApplicationDirectorySessionExpired'
          : 'organizationShareableApplicationDirectoryFailure.${code.name}';
      expect(find.text(const AppStrings('zh').t(key)), findsOneWidget);
      expect(
        tester.widget<FilledButton>(_refresh).onPressed == null,
        code == OrganizationShareableJoinFailureCode.unauthorized,
      );
    });
  }

  testWidgets(
    'thrown read is typed invalid response; refresh remains explicit',
    (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final gateway = _Gateway([
        StateError('private detail'),
        _success(empty: true),
      ]);
      await _open(tester, fixture.session, gateway);
      expect(
        find.text(
          const AppStrings('zh').t(
            'organizationShareableApplicationDirectoryFailure.invalidResponse',
          ),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('private detail'), findsNothing);
      await tester.tap(_refresh);
      await tester.pumpAndSettle();
      expect(gateway.reads.length, 2);
    },
  );

  for (final transition in ['logout', 'switch', 'ABA']) {
    testWidgets(
      '$transition fences late reads and cannot restore old records',
      (tester) async {
        final fixture = await _Fixture.create();
        addTearDown(fixture.close);
        final pending =
            Completer<OrganizationShareableJoinApplicationDirectoryResult>();
        final gateway = _Gateway([pending]);
        await _open(tester, fixture.session, gateway, settle: false);
        await _changeIdentity(tester, fixture, transition);
        pending.complete(_success());
        await tester.pumpAndSettle();
        expect(find.text(_application), findsNothing);
        expect(find.text(_workspace), findsNothing);
        expect(tester.widget<FilledButton>(_refresh).onPressed, isNull);
        expect(gateway.reads, [_workspace]);
      },
    );
  }

  testWidgets(
    'identity change during nested approval clears old list; late close cannot restore notice',
    (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final gateway = _Gateway([_success()]);
      await _open(tester, fixture.session, gateway);
      await _openApproval(tester);
      await _changeIdentity(tester, fixture, 'ABA');
      await tester.tap(_approvalClose);
      await tester.pumpAndSettle();
      expect(find.text(_application), findsNothing);
      expect(find.text(_workspace), findsNothing);
      expect(
        find.text(
          const AppStrings(
            'zh',
          ).t('organizationShareableApplicationDirectoryApprovalClosed'),
        ),
        findsNothing,
      );
      expect(gateway.approvals, isEmpty);
      expect(gateway.reads, [_workspace]);
    },
  );

  testWidgets(
    'same-account project selection preserves fixed organization and late read',
    (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final pending =
          Completer<OrganizationShareableJoinApplicationDirectoryResult>();
      final gateway = _Gateway([pending]);
      await _open(tester, fixture.session, gateway, settle: false);
      await fixture.session.selectProject(_projectB);
      await tester.pump();
      pending.complete(_success());
      await tester.pumpAndSettle();
      expect(find.text(_application), findsOneWidget);
      expect(gateway.reads, [_workspace]);
    },
  );

  testWidgets(
    'close during loading fences late read and never closes borrowed gateway',
    (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final pending =
          Completer<OrganizationShareableJoinApplicationDirectoryResult>();
      final gateway = _Gateway([pending]);
      await _open(tester, fixture.session, gateway, settle: false);
      await tester.tap(_close);
      await tester.pumpAndSettle();
      pending.complete(_success());
      await tester.pumpAndSettle();
      expect(_dialog, findsNothing);
      expect(tester.takeException(), isNull);
      expect(gateway.closed, isFalse);
    },
  );

  for (final locale in ['zh', 'en']) {
    testWidgets(
      '$locale narrow 200% layout scrolls, has heading/live region and 48dp actions',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fixture = await _Fixture.create();
        addTearDown(fixture.close);
        final semantics = tester.ensureSemantics();
        final gateway = _Gateway([_success()]);
        await _open(tester, fixture.session, gateway, locale: locale, scale: 2);
        expect(tester.takeException(), isNull);
        final status = find.byKey(
          const ValueKey('organization-shareable-application-directory-status'),
        );
        expect(
          tester
              .getSemantics(status)
              .getSemanticsData()
              .flagsCollection
              .isLiveRegion,
          isTrue,
        );
        final heading = find.text(
          AppStrings(
            locale,
          ).t('organizationShareableApplicationDirectoryTitle'),
        );
        expect(
          tester
              .getSemantics(heading)
              .getSemanticsData()
              .flagsCollection
              .isHeader,
          isTrue,
        );
        for (final action in [_close, _refresh]) {
          expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
        }
        await tester.ensureVisible(_details);
        await tester.tap(_details);
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.text(_record.expiresAtUtc.toIso8601String()),
        );
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(_recordReview);
        expect(tester.getSize(_recordReview).height, greaterThanOrEqualTo(48));
        await tester.tap(_recordReview);
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(_approvalField).controller!.text,
          _application,
        );
        await tester.ensureVisible(_approvalClose);
        await tester.tap(_approvalClose);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(_dialog, findsNothing);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );
  }
}

const _workspace = '11111111-1111-4111-8111-111111111111';
const _application = '22222222-2222-4222-8222-222222222222';
const _link = '33333333-3333-4333-8333-333333333333';
const _membership = '44444444-4444-4444-8444-444444444444';
const _projectB = '55555555-5555-4555-8555-555555555555';
const _organization = OrganizationDirectoryEntry(
  organizationWorkspaceId: _workspace,
  organizationName: '同行组织',
);
final _record = OrganizationShareableJoinApplicationDirectoryRecord(
  applicationId: _application,
  linkId: _link,
  submittedAtUtc: DateTime.utc(2026, 9, 17),
  expiresAtUtc: DateTime.utc(2026, 9, 24),
);
OrganizationShareableJoinApplicationDirectorySuccess _success({
  bool empty = false,
}) => OrganizationShareableJoinApplicationDirectorySuccess(
  OrganizationShareableJoinApplicationDirectoryReceipt(
    organizationShareableJoinApplicationDirectoryContractId:
        'organization-shareable-join-application-directory:v1',
    organizationWorkspaceId: _workspace,
    observedAtUtc: DateTime.utc(2026, 9, 18),
    applications: empty ? [] : [_record],
  ),
);
Finder _key(String key) => find.byKey(ValueKey(key));
final _dialog = _key('organization-shareable-application-directory-dialog');
final _close = _key('organization-shareable-application-directory-close');
final _refresh = _key('organization-shareable-application-directory-refresh');
final _details = _key(
  'organization-shareable-application-directory-details-$_application',
);
final _recordReview = _key(
  'organization-shareable-application-directory-review-$_application',
);
final _approvalField = _key(
  'organization-shareable-approval-application-field',
);
final _approvalReview = _key('organization-shareable-approval-review');
final _approvalSubmit = _key('organization-shareable-approval-submit');
final _approvalClose = _key('organization-shareable-approval-close');

Future<void> _openApproval(WidgetTester tester) async {
  await tester.ensureVisible(_recordReview);
  await tester.tap(_recordReview);
  await tester.pumpAndSettle();
}

Future<void> _open(
  WidgetTester tester,
  AppSession session,
  _Gateway gateway, {
  String locale = 'zh',
  double scale = 1,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) =>
                  OrganizationShareableJoinApplicationDirectoryDialog(
                    text: AppStrings(locale),
                    organization: _organization,
                    gateway: gateway,
                    appSession: session,
                  ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _changeIdentity(
  WidgetTester tester,
  _Fixture fixture,
  String transition,
) async {
  fixture.identity.emit(
    transition == 'switch'
        ? _signedIn('b')
        : const IdentitySnapshot.signedOut(),
  );
  await tester.pumpAndSettle();
  if (transition == 'ABA') {
    fixture.identity.emit(_signedIn('a'));
    await tester.pumpAndSettle();
  }
}

final class _Gateway implements OrganizationShareableJoinGateway {
  _Gateway(Iterable<Object> results) : results = Queue.of(results);
  final Queue<Object> results;
  final reads = <String>[];
  final approvals = <({String workspace, String application})>[];
  var closed = false;
  @override
  Future<OrganizationShareableJoinApplicationDirectoryResult>
  listPendingApplications({required String organizationWorkspaceId}) async {
    reads.add(organizationWorkspaceId);
    final result = results.removeFirst();
    if (result
        is Completer<OrganizationShareableJoinApplicationDirectoryResult>) {
      return result.future;
    }
    if (result is OrganizationShareableJoinApplicationDirectoryResult) {
      return result;
    }
    throw result;
  }

  @override
  Future<OrganizationShareableJoinApplicationApproveResult> approveApplication({
    required String organizationWorkspaceId,
    required String applicationId,
  }) async {
    approvals.add((
      workspace: organizationWorkspaceId,
      application: applicationId,
    ));
    return OrganizationShareableJoinApplicationApproveSuccess(
      OrganizationShareableJoinApplicationApproveReceipt(
        organizationShareableJoinApplicationContractId:
            'organization-shareable-join-application:v1',
        applicationId: applicationId,
        organizationWorkspaceId: organizationWorkspaceId,
        organizationMembershipId: _membership,
        approvedAtUtc: DateTime.utc(2026, 9, 18),
      ),
    );
  }

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unused operation');
}

final class _Fixture {
  _Fixture(this.identity, this.session, this.context);
  final _Identity identity;
  final AppSession session;
  final _Context context;
  static Future<_Fixture> create() async {
    final identity = _Identity();
    final context = _Context();
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

final class _Identity implements IdentitySession {
  final controller = StreamController<IdentitySnapshot>.broadcast();
  IdentitySnapshot snapshot = _signedIn('a');
  void emit(IdentitySnapshot value) {
    snapshot = value;
    controller.add(value);
  }

  @override
  IdentitySnapshot get current => snapshot;
  @override
  Stream<IdentitySnapshot> get changes => controller.stream;
  @override
  Future<IdentityResult<IdentitySnapshot>> restore() async =>
      IdentitySuccess(snapshot);
  @override
  Future<IdentityResult<IdentityAccessToken>> accessToken({
    bool forceRefresh = false,
  }) async => IdentitySuccess(
    IdentityAccessToken(
      value: snapshot.principal!.externalSubject,
      expiresAt: snapshot.expiresAt,
    ),
  );
  @override
  Future<void> close() => controller.close();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unused identity operation');
}

IdentitySnapshot _signedIn(String subject) => IdentitySnapshot(
  stage: IdentityStage.signedIn,
  principal: IdentityPrincipal(
    externalSubject: subject,
    email: '$subject@example.test',
  ),
  expiresAt: DateTime.utc(2030),
);

final class _Context implements SessionContextGateway {
  var selectCalls = 0;
  TrustedSessionContext value(String user, {String project = _application}) =>
      TrustedSessionContext(
        appUserId: user == 'a' ? _membership : _link,
        workspace: const WorkspaceContext(
          id: _link,
          kind: WorkspaceKind.personal,
          name: 'Personal',
        ),
        project: ProjectContext(id: project, name: 'Project'),
        questionnaireVersion: const QuestionnaireVersionContext(
          id: _application,
          versionNumber: 1,
        ),
        capabilities: {},
      );
  @override
  Future<SessionContextResult> resolve(IdentityAccessToken token) async =>
      SessionContextSuccess(value(token.value));
  @override
  Future<SessionContextResult> selectProject(
    IdentityAccessToken token,
    String projectId,
  ) async {
    selectCalls++;
    return SessionContextSuccess(value(token.value, project: projectId));
  }

  @override
  Future<void> close() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unused context operation');
}
