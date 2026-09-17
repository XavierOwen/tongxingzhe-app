import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/app_session/app_session.dart';
import 'package:tongxingzhe_app/app_session/session_context_gateway.dart';
import 'package:tongxingzhe_app/features/organization_directory/organization_project_membership_assignment_dialog.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/l10n/app_strings.dart';
import 'package:tongxingzhe_app/organization_project_membership_assignment/organization_project_membership_assignment.dart';

void main() {
  testWidgets(
    'review/edit never creates request; explicit assign and retry retain exact four-selector intent',
    (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      var generated = 0;
      final gateway = _Gateway([
        const OrganizationProjectMembershipAssignmentRejected(
          OrganizationProjectMembershipAssignmentFailureCode.networkUnavailable,
        ),
        OrganizationProjectMembershipAssignmentSuccess(_receipt()),
      ]);
      await _open(
        tester,
        fixture.session,
        gateway,
        requestIdGenerator: () {
          generated += 1;
          return _requestId.toUpperCase();
        },
      );
      await _enter(tester, uppercase: true);
      await tester.tap(_review);
      await tester.pumpAndSettle();
      expect(generated, 0);
      expect(gateway.calls, isEmpty);
      expect(find.text(_projectId), findsOneWidget);
      expect(find.text(_targetId), findsOneWidget);
      await tester.tap(_edit);
      await tester.pumpAndSettle();
      await tester.tap(_review);
      await tester.pumpAndSettle();
      expect(generated, 0);
      await tester.tap(_submit);
      await tester.pumpAndSettle();
      expect(_edit, findsNothing);
      expect(_projectField, findsNothing);
      expect(_targetField, findsNothing);
      expect(_uncertain, findsOneWidget);
      await tester.tap(_submit);
      await tester.pumpAndSettle();
      expect(generated, 1);
      expect(gateway.calls, hasLength(2));
      expect(gateway.calls.toSet(), {_intent});
      expect(gateway.closed, isFalse);
      expect(fixture.context.selectCalls, 0);
    },
  );

  for (final invalid in [
    '',
    'not-a-uuid',
    ' $_projectId',
    '$_projectId ',
    'https://example.test/$_projectId',
  ]) {
    for (final project in [true, false]) {
      testWidgets(
        'local ${project ? 'project' : 'parent'} rejects opaque selector without trimming: $invalid',
        (tester) async {
          final fixture = await _Fixture.create();
          addTearDown(fixture.close);
          final gateway = _Gateway([]);
          var generated = 0;
          await _open(
            tester,
            fixture.session,
            gateway,
            requestIdGenerator: () {
              generated += 1;
              return _requestId;
            },
          );
          await tester.enterText(_projectField, project ? invalid : _projectId);
          await tester.enterText(_targetField, project ? _targetId : invalid);
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pumpAndSettle();
          expect(_submit, findsNothing);
          expect(gateway.calls, isEmpty);
          expect(generated, 0);
          expect(
            find.text(
              _text(project ? 'InvalidProject' : 'InvalidTargetMembership'),
            ),
            findsOneWidget,
          );
        },
      );
    }
  }

  testWidgets('invalid fixed organization prevents review and network', (
    tester,
  ) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gateway = _Gateway([]);
    await _open(
      tester,
      fixture.session,
      gateway,
      organizationId: ' $_organizationId',
    );
    await _enter(tester);
    await tester.tap(_review);
    await tester.pumpAndSettle();
    expect(_submit, findsNothing);
    expect(gateway.calls, isEmpty);
    expect(find.text(_text('InvalidOrganization')), findsOneWidget);
  });

  for (final throws in [false, true]) {
    testWidgets(
      'invalid/throwing generator sends nothing and leaves selectors editable: $throws',
      (tester) async {
        final fixture = await _Fixture.create();
        addTearDown(fixture.close);
        final gateway = _Gateway([
          OrganizationProjectMembershipAssignmentSuccess(_receipt()),
        ]);
        var generated = 0;
        await _open(
          tester,
          fixture.session,
          gateway,
          requestIdGenerator: () {
            generated += 1;
            if (generated == 1) {
              if (throws) throw StateError('secret generator detail');
              return 'invalid';
            }
            return _requestId;
          },
        );
        await _enter(tester);
        await tester.tap(_review);
        await tester.pumpAndSettle();
        await tester.tap(_submit);
        await tester.pumpAndSettle();
        expect(gateway.calls, isEmpty);
        expect(_edit, findsOneWidget);
        expect(_uncertain, findsNothing);
        expect(find.textContaining('secret'), findsNothing);
        await tester.tap(_edit);
        await tester.pumpAndSettle();
        const revised = '77777777-7777-4777-8777-777777777777';
        await tester.enterText(_projectField, revised);
        await tester.tap(_review);
        await tester.pumpAndSettle();
        await tester.tap(_submit);
        await tester.pumpAndSettle();
        expect(generated, 2);
        expect(gateway.calls.single.projectId, revised);
      },
    );
  }

  testWidgets(
    'Enter only reviews; unsubmitted Escape closes without generating request',
    (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final gateway = _Gateway([]);
      var generated = 0;
      await _open(
        tester,
        fixture.session,
        gateway,
        requestIdGenerator: () {
          generated += 1;
          return _requestId;
        },
      );
      await _enter(tester);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(_submit, findsOneWidget);
      expect(gateway.calls, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(_dialog, findsNothing);
      expect(generated, 0);
    },
  );

  for (final finite in [false, true]) {
    testWidgets(
      'success displays seven historical fields and explicit ${finite ? 'UTC end' : 'null end'}, without clipboard/refetch/switch/close',
      (tester) async {
        final fixture = await _Fixture.create();
        addTearDown(fixture.close);
        final receipt = _receipt(finite: finite);
        final gateway = _Gateway([
          OrganizationProjectMembershipAssignmentSuccess(receipt),
        ]);
        final clipboard = <Object?>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'Clipboard.setData') {
                clipboard.add(call.arguments);
              }
              return null;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null),
        );
        await _confirmAndSubmit(tester, fixture.session, gateway);
        for (final value in [
          receipt.projectMembershipAssignmentContractId,
          receipt.organizationWorkspaceId,
          receipt.projectId,
          receipt.organizationMembershipId,
          receipt.projectMembershipId,
          receipt.activeFromUtc.toUtc().toIso8601String(),
          receipt.inactiveFromUtc?.toUtc().toIso8601String() ??
              _text('NullEnd'),
          _text('FreshnessNotice'),
        ]) {
          expect(find.text(value), findsOneWidget);
        }
        expect(_dialog, findsOneWidget);
        expect(_submit, findsNothing);
        expect(clipboard, isEmpty);
        expect(fixture.context.resolveCalls, 1);
        expect(fixture.context.selectCalls, 0);
        await tester.tap(_close);
        await tester.pumpAndSettle();
        expect(gateway.closed, isFalse);
      },
    );
  }

  for (final code
      in OrganizationProjectMembershipAssignmentFailureCode.values) {
    testWidgets(
      'stable localized ${code.name} and exactly three uncertain failures',
      (tester) async {
        final fixture = await _Fixture.create();
        addTearDown(fixture.close);
        final gateway = _Gateway([
          OrganizationProjectMembershipAssignmentRejected(code),
        ]);
        await _confirmAndSubmit(tester, fixture.session, gateway);
        final uncertain = [
          OrganizationProjectMembershipAssignmentFailureCode.networkUnavailable,
          OrganizationProjectMembershipAssignmentFailureCode.serviceUnavailable,
          OrganizationProjectMembershipAssignmentFailureCode.invalidResponse,
        ].contains(code);
        expect(_uncertain, uncertain ? findsOneWidget : findsNothing);
        expect(_edit, findsNothing);
        expect(_projectField, findsNothing);
        expect(_targetField, findsNothing);
        if (code ==
            OrganizationProjectMembershipAssignmentFailureCode.unauthorized) {
          expect(find.byType(SelectableText), findsNothing);
          expect(_submit, findsNothing);
          expect(find.text(_text('Unauthorized')), findsOneWidget);
        } else {
          expect(find.text(_text('Failure.${code.name}')), findsOneWidget);
          expect(_submit, findsOneWidget);
        }
      },
    );
  }

  testWidgets(
    'throw is uncertain and hides details; Escape keep-retry preserves exact intent',
    (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final gateway = _Gateway([
        StateError('secret provider detail'),
        OrganizationProjectMembershipAssignmentSuccess(_receipt()),
      ]);
      await _confirmAndSubmit(tester, fixture.session, gateway);
      expect(find.textContaining('secret'), findsNothing);
      expect(_uncertain, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(_discard, findsOneWidget);
      for (final action in [_keepRetry, _discard]) {
        _expectTarget(tester, action);
        var reachable = false;
        for (var i = 0; i < 6; i += 1) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          reachable = reachable || _hasFocus(tester, action);
        }
        expect(reachable, isTrue);
      }
      await tester.tap(_keepRetry);
      await tester.pumpAndSettle();
      await tester.tap(_submit);
      await tester.pumpAndSettle();
      expect(gateway.calls.toSet(), {_intent});
      expect(_uncertain, findsNothing);
    },
  );

  testWidgets(
    'stable conflict ends previous uncertainty without changing intent',
    (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final gateway = _Gateway(const [
        OrganizationProjectMembershipAssignmentRejected(
          OrganizationProjectMembershipAssignmentFailureCode.networkUnavailable,
        ),
        OrganizationProjectMembershipAssignmentRejected(
          OrganizationProjectMembershipAssignmentFailureCode.conflict,
        ),
      ]);
      await _confirmAndSubmit(tester, fixture.session, gateway);
      expect(_uncertain, findsOneWidget);
      await tester.tap(_submit);
      await tester.pumpAndSettle();
      expect(_uncertain, findsNothing);
      expect(_edit, findsNothing);
      expect(gateway.calls.toSet(), {_intent});
      await tester.tap(_close);
      await tester.pumpAndSettle();
      expect(_dialog, findsNothing);
      expect(_discard, findsNothing);
    },
  );

  testWidgets(
    'system Back requires explicit uncertain abandonment and does not close gateway',
    (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final gateway = _Gateway(const [
        OrganizationProjectMembershipAssignmentRejected(
          OrganizationProjectMembershipAssignmentFailureCode.serviceUnavailable,
        ),
      ]);
      await _confirmAndSubmit(tester, fixture.session, gateway);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_discard, findsOneWidget);
      await tester.tap(_discard);
      await tester.pumpAndSettle();
      expect(_dialog, findsNothing);
      expect(gateway.calls, hasLength(1));
      expect(gateway.closed, isFalse);
    },
  );

  testWidgets('busy blocks duplicate callback, close, Escape and system Back', (
    tester,
  ) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final pending = Completer<OrganizationProjectMembershipAssignmentResult>();
    final gateway = _Gateway([pending]);
    await _open(tester, fixture.session, gateway);
    await _enter(tester);
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
      OrganizationProjectMembershipAssignmentSuccess(_receipt()),
    );
    await tester.pumpAndSettle();
    expect(find.text(_membershipId), findsOneWidget);
  });

  testWidgets(
    'fixed organization survives widget update and same-account project/token changes',
    (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final organization = ValueNotifier(_organizationId.toUpperCase());
      addTearDown(organization.dispose);
      final pending =
          Completer<OrganizationProjectMembershipAssignmentResult>();
      final gateway = _Gateway([pending]);
      await _open(
        tester,
        fixture.session,
        gateway,
        organizations: organization,
      );
      await _enter(tester);
      await tester.tap(_review);
      await tester.pumpAndSettle();
      await fixture.session.selectProject('project-b');
      organization.value = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
      await tester.pumpAndSettle();
      await tester.tap(_submit);
      await tester.pump();
      final identity = fixture.identity.current;
      fixture.identity.emit(
        IdentitySnapshot(
          stage: IdentityStage.signedIn,
          principal: identity.principal,
          expiresAt: identity.expiresAt!.add(const Duration(hours: 1)),
        ),
      );
      await tester.pump();
      pending.complete(
        OrganizationProjectMembershipAssignmentSuccess(_receipt()),
      );
      await tester.pumpAndSettle();
      expect(gateway.calls, [_intent]);
      expect(find.text(organization.value), findsNothing);
      expect(find.text(_membershipId), findsOneWidget);
      expect(fixture.context.selectCalls, 1);
    },
  );

  for (final transition in ['logout', 'switch', 'ABA']) {
    testWidgets(
      '$transition clears all selectors and discards late success permanently',
      (tester) async {
        final fixture = await _Fixture.create();
        addTearDown(fixture.close);
        final pending =
            Completer<OrganizationProjectMembershipAssignmentResult>();
        final gateway = _Gateway([pending]);
        await _open(tester, fixture.session, gateway);
        await _enter(tester);
        await tester.tap(_review);
        await tester.pumpAndSettle();
        await tester.tap(_submit);
        await tester.pump();
        fixture.identity.emit(
          transition == 'logout'
              ? const IdentitySnapshot.signedOut()
              : _signedIn('subject-b'),
        );
        await tester.pumpAndSettle();
        if (transition == 'ABA') {
          fixture.identity.emit(_signedIn('subject-a'));
          await tester.pumpAndSettle();
        }
        pending.complete(
          OrganizationProjectMembershipAssignmentSuccess(_receipt()),
        );
        await tester.pumpAndSettle();
        expect(find.byType(SelectableText), findsNothing);
        expect(_projectField, findsNothing);
        expect(_targetField, findsNothing);
        expect(_submit, findsNothing);
        expect(_uncertain, findsNothing);
        expect(find.text(_text('Unauthorized')), findsOneWidget);
      },
    );
  }

  testWidgets('logout removes an already displayed historical receipt', (
    tester,
  ) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    await _confirmAndSubmit(
      tester,
      fixture.session,
      _Gateway([OrganizationProjectMembershipAssignmentSuccess(_receipt())]),
    );
    fixture.identity.emit(const IdentitySnapshot.signedOut());
    await tester.pumpAndSettle();
    fixture.identity.emit(_signedIn('subject-a'));
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsNothing);
    expect(_submit, findsNothing);
  });

  testWidgets(
    'disposed dialog ignores a late failure and never closes borrowed gateway',
    (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final pending =
          Completer<OrganizationProjectMembershipAssignmentResult>();
      final gateway = _Gateway([pending]);
      await _open(tester, fixture.session, gateway);
      await _enter(tester);
      await tester.tap(_review);
      await tester.pumpAndSettle();
      await tester.tap(_submit);
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      pending.completeError(StateError('secret late failure'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(gateway.closed, isFalse);
    },
  );

  testWidgets(
    'keyboard review path and every ordinary action keeps 48px targets',
    (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      await _open(tester, fixture.session, _Gateway([]));
      await _enter(tester);
      for (final action in [_close, _review]) {
        _expectTarget(tester, action);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(_hasFocus(tester, _close), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(_hasFocus(tester, _review), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      for (final action in [_close, _edit, _submit]) {
        _expectTarget(tester, action);
      }
    },
  );

  for (final locale in ['zh', 'en']) {
    testWidgets(
      '$locale IME 320x568 safe-top24/bottom307 at 200%: both fields and actions reachable',
      (tester) async {
        final fixture = await _Fixture.create();
        addTearDown(fixture.close);
        _smallViewport(tester, ime: true);
        await _open(
          tester,
          fixture.session,
          _Gateway([]),
          locale: locale,
          textScaler: const TextScaler.linear(2),
        );
        await _enter(tester);
        for (final field in [_projectField, _targetField]) {
          await tester.ensureVisible(field);
          await tester.pumpAndSettle();
          final viewport = find.ancestor(
            of: field,
            matching: find.byType(SingleChildScrollView),
          );
          expect(tester.takeException(), isNull);
          expect(
            tester.getSize(viewport).height,
            greaterThanOrEqualTo(tester.getSize(field).height),
          );
        }
        for (final action in [_close, _review]) {
          _expectTarget(tester, action);
          expect(tester.getRect(action).bottom, lessThanOrEqualTo(568 - 307));
        }
        await tester.tap(_review);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final action in [_close, _edit, _submit]) {
          _expectTarget(tester, action);
        }
      },
    );

    testWidgets(
      '$locale small viewport at 200% covers busy/uncertain/discard/success/session states',
      (tester) async {
        final fixture = await _Fixture.create();
        addTearDown(fixture.close);
        _smallViewport(tester);
        final semantics = tester.ensureSemantics();
        final pending =
            Completer<OrganizationProjectMembershipAssignmentResult>();
        final gateway = _Gateway([
          pending,
          OrganizationProjectMembershipAssignmentSuccess(
            _receipt(finite: true),
          ),
        ]);
        await _open(
          tester,
          fixture.session,
          gateway,
          locale: locale,
          textScaler: const TextScaler.linear(2),
        );
        await _enter(tester);
        await tester.tap(_review);
        await tester.pumpAndSettle();
        await tester.tap(_submit);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        pending.complete(
          const OrganizationProjectMembershipAssignmentRejected(
            OrganizationProjectMembershipAssignmentFailureCode
                .networkUnavailable,
          ),
        );
        await tester.pumpAndSettle();
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
        }
        await tester.tap(_close);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(_keepRetry);
        await tester.pumpAndSettle();
        await tester.tap(_submit);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text(_membershipId));
        expect(tester.takeException(), isNull);
        fixture.identity.emit(const IdentitySnapshot.signedOut());
        await tester.pumpAndSettle();
        expect(find.byType(SelectableText), findsNothing);
        await tester.ensureVisible(_status);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );
  }
}

Finder _key(String suffix) =>
    find.byKey(ValueKey('organization-project-membership-assignment-$suffix'));
final _dialog = _key('dialog');
final _projectField = _key('project-field');
final _targetField = _key('target-field');
final _review = _key('review');
final _submit = _key('submit');
final _edit = _key('edit');
final _close = _key('close');
final _status = _key('status');
final _uncertain = _key('uncertain');
final _keepRetry = _key('keep-retry');
final _discard = _key('discard');
String _text(String suffix) =>
    const AppStrings('zh').t('organizationProjectMembershipAssignment$suffix');

void _expectTarget(WidgetTester tester, Finder action) {
  final size = tester.getSize(action);
  expect(size.width, greaterThanOrEqualTo(48));
  expect(size.height, greaterThanOrEqualTo(48));
}

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

void _smallViewport(WidgetTester tester, {bool ime = false}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 568);
  if (ime) {
    tester.view.viewInsets = const FakeViewPadding(bottom: 307);
    tester.view.padding = const FakeViewPadding(top: 24);
  }
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetViewInsets);
  addTearDown(tester.view.resetPadding);
}

Future<void> _enter(WidgetTester tester, {bool uppercase = false}) async {
  await tester.enterText(
    _projectField,
    uppercase ? _projectId.toUpperCase() : _projectId,
  );
  await tester.enterText(
    _targetField,
    uppercase ? _targetId.toUpperCase() : _targetId,
  );
}

Future<void> _confirmAndSubmit(
  WidgetTester tester,
  AppSession session,
  _Gateway gateway,
) async {
  await _open(tester, session, gateway);
  await _enter(tester);
  await tester.tap(_review);
  await tester.pumpAndSettle();
  await tester.tap(_submit);
  await tester.pumpAndSettle();
}

Future<void> _open(
  WidgetTester tester,
  AppSession session,
  OrganizationProjectMembershipAssignmentGateway gateway, {
  String locale = 'zh',
  String organizationId = _organizationId,
  ValueNotifier<String>? organizations,
  TextScaler textScaler = TextScaler.noScaling,
  String Function()? requestIdGenerator,
}) async {
  Widget dialog(String organization) =>
      OrganizationProjectMembershipAssignmentDialog(
        text: AppStrings(locale),
        organizationWorkspaceId: organization,
        gateway: gateway,
        appSession: session,
        requestIdGenerator: requestIdGenerator ?? () => _requestId,
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
            key: const ValueKey('open-assignment'),
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => organizations == null
                  ? dialog(organizationId)
                  : ValueListenableBuilder<String>(
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
  await tester.tap(find.byKey(const ValueKey('open-assignment')));
  await tester.pumpAndSettle();
}

typedef _Intent = ({
  String requestId,
  String organizationWorkspaceId,
  String projectId,
  String targetOrganizationMembershipId,
});

final class _Gateway implements OrganizationProjectMembershipAssignmentGateway {
  _Gateway(Iterable<Object> results) : _results = Queue.of(results);
  final Queue<Object> _results;
  final calls = <_Intent>[];
  var closed = false;
  @override
  Future<OrganizationProjectMembershipAssignmentResult> assign({
    required String requestId,
    required String organizationWorkspaceId,
    required String projectId,
    required String targetOrganizationMembershipId,
  }) async {
    calls.add((
      requestId: requestId,
      organizationWorkspaceId: organizationWorkspaceId,
      projectId: projectId,
      targetOrganizationMembershipId: targetOrganizationMembershipId,
    ));
    final next = _results.removeFirst();
    if (next is Completer<OrganizationProjectMembershipAssignmentResult>) {
      return next.future;
    }
    if (next is OrganizationProjectMembershipAssignmentResult) return next;
    throw next;
  }

  @override
  Future<void> close() async => closed = true;
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
  var resolveCalls = 0;
  @override
  Future<SessionContextResult> resolve(IdentityAccessToken token) async {
    resolveCalls += 1;
    return SessionContextSuccess(_context(token.value));
  }

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
  expiresAt: DateTime.utc(2030),
);
const _organizationId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _projectId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _targetId = 'abcdefab-cdef-4abc-8def-abcdefabcdef';
const _membershipId = '66666666-6666-4666-8666-666666666666';
const _requestId = '12345678-1234-4234-8234-123456789abc';
const _intent = (
  requestId: _requestId,
  organizationWorkspaceId: _organizationId,
  projectId: _projectId,
  targetOrganizationMembershipId: _targetId,
);
OrganizationProjectMembershipAssignmentReceipt _receipt({
  bool finite = false,
}) => OrganizationProjectMembershipAssignmentReceipt(
  projectMembershipAssignmentContractId:
      'organization-project-membership-assignment:v1',
  organizationWorkspaceId: _organizationId,
  projectId: _projectId,
  organizationMembershipId: _targetId,
  projectMembershipId: _membershipId,
  activeFromUtc: DateTime.parse('2001-01-02T12:05:06.123Z'),
  inactiveFromUtc: finite ? DateTime.parse('2002-01-02T12:05:06.123Z') : null,
);
