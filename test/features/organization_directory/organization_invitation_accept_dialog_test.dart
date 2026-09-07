import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/app_session/app_session.dart';
import 'package:tongxingzhe_app/app_session/session_context_gateway.dart';
import 'package:tongxingzhe_app/features/organization_directory/organization_invitation_accept_dialog.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/l10n/app_strings.dart';
import 'package:tongxingzhe_app/organization_directed_account_invitation/organization_directed_account_invitation.dart';

void main() {
  testWidgets(
    'preview canonical invitation, then accept only after confirmation',
    (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final gateway = _Gateway(
        previews: [
          OrganizationDirectedAccountInvitationPreviewSuccess(_preview),
        ],
        accepts: [OrganizationDirectedAccountInvitationAcceptSuccess(_receipt)],
      );
      final result = _ResultBox();
      await _open(tester, fixture.session, gateway, result: result);
      expect(tester.widget(_previewAction), isA<FilledButton>());
      expect(tester.widget(_closeAction), isA<TextButton>());

      await tester.enterText(
        _invitationIdField,
        '  ${_invitationId.toUpperCase()}  ',
      );
      await tester.tap(_previewAction);
      await tester.pumpAndSettle();

      expect(gateway.previewCalls, [_invitationId]);
      expect(gateway.acceptCalls, isEmpty);
      expect(find.text(_preview.organizationName), findsOneWidget);
      expect(find.textContaining('2030-01-08'), findsOneWidget);
      expect(
        find.text(
          const AppStrings('zh').t('organizationInvitationMembershipNotice'),
        ),
        findsOneWidget,
      );
      expect(tester.widget(_acceptAction), isA<FilledButton>());
      expect(tester.widget(_editAction), isA<TextButton>());
      expect(_acceptAction, findsOneWidget);

      await tester.tap(_acceptAction);
      await tester.pumpAndSettle();

      expect(gateway.previewCalls, [_invitationId]);
      expect(gateway.acceptCalls, [_invitationId]);
      expect(result.receipt, same(_receipt));
      expect(find.byType(OrganizationInvitationAcceptDialog), findsNothing);
    },
  );

  testWidgets(
    'edit clears the old preview before another invitation can load',
    (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final gateway = _Gateway(
        previews: [
          OrganizationDirectedAccountInvitationPreviewSuccess(_preview),
          OrganizationDirectedAccountInvitationPreviewSuccess(_otherPreview),
        ],
      );
      await _open(tester, fixture.session, gateway);

      await _loadPreview(tester, _invitationId);
      await tester.tap(_editAction);
      await tester.pump();
      expect(find.text(_preview.organizationName), findsNothing);
      expect(_invitationIdField, findsOneWidget);
      expect(gateway.acceptCalls, isEmpty);

      await tester.enterText(_invitationIdField, _otherInvitationId);
      await tester.tap(_previewAction);
      await tester.pumpAndSettle();
      expect(gateway.previewCalls, [_invitationId, _otherInvitationId]);
      expect(find.text(_otherPreview.organizationName), findsOneWidget);
    },
  );

  testWidgets('invalid invitation ID stays local and editable', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gateway = _Gateway();
    const text = AppStrings('zh');
    await _open(tester, fixture.session, gateway);

    await tester.enterText(_invitationIdField, 'not-a-uuid');
    await tester.tap(_previewAction);
    await tester.pump();

    expect(gateway.previewCalls, isEmpty);
    expect(
      find.text(text.t('organizationInvitationInvalidId')),
      findsOneWidget,
    );
    expect(_invitationIdField, findsOneWidget);
    expect(_uncertain, findsNothing);
  });

  testWidgets(
    'preview failure stays editable and closing needs no discard confirmation',
    (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final gateway = _Gateway(
        previews: [
          OrganizationDirectedAccountInvitationPreviewRejected(
            OrganizationDirectedAccountInvitationFailureCode.networkUnavailable,
          ),
          OrganizationDirectedAccountInvitationPreviewSuccess(_otherPreview),
        ],
      );
      await _open(tester, fixture.session, gateway);

      await _loadPreview(tester, _invitationId);
      expect(_invitationIdField, findsOneWidget);
      expect(_uncertain, findsNothing);
      await tester.enterText(_invitationIdField, _otherInvitationId);
      await tester.tap(_previewAction);
      await tester.pumpAndSettle();
      expect(gateway.previewCalls, [_invitationId, _otherInvitationId]);

      await tester.tap(_editAction);
      await tester.pump();
      await tester.tap(_closeAction);
      await tester.pumpAndSettle();
      expect(find.byType(OrganizationInvitationAcceptDialog), findsNothing);
      expect(_discardAction, findsNothing);
    },
  );

  testWidgets(
    'uncertain accept retries the same intent without another preview',
    (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final gateway = _Gateway(
        previews: [
          OrganizationDirectedAccountInvitationPreviewSuccess(_preview),
        ],
        accepts: [
          OrganizationDirectedAccountInvitationAcceptRejected(
            OrganizationDirectedAccountInvitationFailureCode.networkUnavailable,
          ),
          OrganizationDirectedAccountInvitationAcceptSuccess(_receipt),
        ],
      );
      final result = _ResultBox();
      await _open(tester, fixture.session, gateway, result: result);
      await _loadPreview(tester, _invitationId);

      await tester.tap(_acceptAction);
      await tester.pumpAndSettle();
      expect(_uncertain, findsOneWidget);
      expect(find.text(_preview.organizationName), findsOneWidget);
      expect(gateway.previewCalls, [_invitationId]);

      await tester.tap(_acceptAction);
      await tester.pumpAndSettle();
      expect(gateway.previewCalls, [_invitationId]);
      expect(gateway.acceptCalls, [_invitationId, _invitationId]);
      expect(result.receipt, same(_receipt));
    },
  );

  testWidgets('uncertain close requires explicit keep or discard', (
    tester,
  ) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gateway = _Gateway(
      previews: [OrganizationDirectedAccountInvitationPreviewSuccess(_preview)],
      accepts: [
        OrganizationDirectedAccountInvitationAcceptRejected(
          OrganizationDirectedAccountInvitationFailureCode.invalidResponse,
        ),
      ],
    );
    await _open(tester, fixture.session, gateway);
    await _loadPreview(tester, _invitationId);
    await tester.tap(_acceptAction);
    await tester.pumpAndSettle();

    await tester.tap(_closeAction);
    await tester.pump();
    expect(_keepRetryAction, findsOneWidget);
    expect(_discardAction, findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(_keepRetryAction);
    await tester.pump();
    expect(_uncertain, findsOneWidget);
    expect(_acceptAction, findsOneWidget);

    await tester.tap(_closeAction);
    await tester.pump();
    await tester.tap(_discardAction);
    await tester.pumpAndSettle();
    expect(find.byType(OrganizationInvitationAcceptDialog), findsNothing);
  });

  testWidgets('busy preview and accept prevent duplicate work and closing', (
    tester,
  ) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final previewPending =
        Completer<OrganizationDirectedAccountInvitationPreviewResult>();
    final acceptPending =
        Completer<OrganizationDirectedAccountInvitationAcceptResult>();
    final gateway = _Gateway(
      previews: [previewPending],
      accepts: [acceptPending],
    );
    await _open(tester, fixture.session, gateway);

    await tester.enterText(_invitationIdField, _invitationId);
    await tester.tap(_previewAction);
    await tester.tap(_previewAction, warnIfMissed: false);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(gateway.previewCalls, [_invitationId]);
    expect(find.byType(OrganizationInvitationAcceptDialog), findsOneWidget);
    expect(tester.widget<TextButton>(_closeAction).onPressed, isNull);

    previewPending.complete(
      OrganizationDirectedAccountInvitationPreviewSuccess(_preview),
    );
    await tester.pumpAndSettle();
    await tester.tap(_acceptAction);
    await tester.tap(_acceptAction, warnIfMissed: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(gateway.acceptCalls, [_invitationId]);
    expect(find.byType(OrganizationInvitationAcceptDialog), findsOneWidget);
    expect(tester.widget<TextButton>(_closeAction).onPressed, isNull);

    acceptPending.complete(
      OrganizationDirectedAccountInvitationAcceptSuccess(_receipt),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('session invalidation clears preview and ignores late results', (
    tester,
  ) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final previewPending =
        Completer<OrganizationDirectedAccountInvitationPreviewResult>();
    final gateway = _Gateway(previews: [previewPending]);
    await _open(tester, fixture.session, gateway);
    await tester.enterText(_invitationIdField, _invitationId);
    await tester.tap(_previewAction);
    await tester.pump();

    fixture.identity.emit(const IdentitySnapshot.signedOut());
    await tester.pumpAndSettle();
    expect(_invitationIdField, findsNothing);
    expect(_previewAction, findsNothing);
    expect(_acceptAction, findsNothing);

    previewPending.complete(
      OrganizationDirectedAccountInvitationPreviewSuccess(_preview),
    );
    await tester.pumpAndSettle();
    expect(find.text(_preview.organizationName), findsNothing);
    expect(find.byType(OrganizationInvitationAcceptDialog), findsOneWidget);
  });

  testWidgets(
    'session invalidation during accept never publishes old success',
    (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final acceptPending =
          Completer<OrganizationDirectedAccountInvitationAcceptResult>();
      final gateway = _Gateway(
        previews: [
          OrganizationDirectedAccountInvitationPreviewSuccess(_preview),
        ],
        accepts: [acceptPending],
      );
      final result = _ResultBox();
      await _open(tester, fixture.session, gateway, result: result);
      await _loadPreview(tester, _invitationId);
      await tester.tap(_acceptAction);
      await tester.pump();

      fixture.identity.emit(_signedIn('subject-b'));
      await tester.pumpAndSettle();
      expect(find.text(_preview.organizationName), findsNothing);
      expect(_acceptAction, findsNothing);

      acceptPending.complete(
        OrganizationDirectedAccountInvitationAcceptSuccess(_receipt),
      );
      await tester.pumpAndSettle();
      expect(result.receipt, isNull);
      expect(find.byType(OrganizationInvitationAcceptDialog), findsOneWidget);
    },
  );

  for (final code in OrganizationDirectedAccountInvitationFailureCode.values) {
    testWidgets('preview ${code.name} displays its stable redacted failure', (
      tester,
    ) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final gateway = _Gateway(
        previews: [OrganizationDirectedAccountInvitationPreviewRejected(code)],
      );
      const text = AppStrings('zh');
      await _open(tester, fixture.session, gateway);
      await _loadPreview(tester, _invitationId);

      expect(
        find.text(
          text.t(
            code ==
                    OrganizationDirectedAccountInvitationFailureCode
                        .unauthorized
                ? 'organizationInvitationUnauthorized'
                : 'organizationInvitationFailure.${code.name}',
          ),
        ),
        findsOneWidget,
      );
      expect(
        _invitationIdField,
        code == OrganizationDirectedAccountInvitationFailureCode.unauthorized
            ? findsNothing
            : findsOneWidget,
      );
      expect(_uncertain, findsNothing);
    });

    testWidgets('accept ${code.name} displays its stable redacted failure', (
      tester,
    ) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final gateway = _Gateway(
        previews: [
          OrganizationDirectedAccountInvitationPreviewSuccess(_preview),
        ],
        accepts: [OrganizationDirectedAccountInvitationAcceptRejected(code)],
      );
      const text = AppStrings('zh');
      await _open(tester, fixture.session, gateway);
      await _loadPreview(tester, _invitationId);
      await tester.tap(_acceptAction);
      await tester.pumpAndSettle();

      expect(
        find.text(
          text.t(
            code ==
                    OrganizationDirectedAccountInvitationFailureCode
                        .unauthorized
                ? 'organizationInvitationUnauthorized'
                : 'organizationInvitationFailure.${code.name}',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.text(_preview.organizationName),
        code == OrganizationDirectedAccountInvitationFailureCode.unauthorized
            ? findsNothing
            : findsOneWidget,
      );
      final uncertain =
          code ==
              OrganizationDirectedAccountInvitationFailureCode.unauthorized ||
          code ==
              OrganizationDirectedAccountInvitationFailureCode
                  .serviceUnavailable ||
          code ==
              OrganizationDirectedAccountInvitationFailureCode
                  .networkUnavailable ||
          code ==
              OrganizationDirectedAccountInvitationFailureCode.invalidResponse;
      expect(_uncertain, uncertain ? findsOneWidget : findsNothing);
    });
  }

  testWidgets('status and uncertain messages are live regions', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final semantics = tester.ensureSemantics();
    final previewPending =
        Completer<OrganizationDirectedAccountInvitationPreviewResult>();
    final gateway = _Gateway(
      previews: [previewPending],
      accepts: const [
        OrganizationDirectedAccountInvitationAcceptRejected(
          OrganizationDirectedAccountInvitationFailureCode.serviceUnavailable,
        ),
      ],
    );
    await _open(tester, fixture.session, gateway);
    await tester.enterText(_invitationIdField, _invitationId);
    await tester.tap(_previewAction);
    await tester.pump();
    _expectLiveRegion(tester, _status);

    previewPending.complete(
      OrganizationDirectedAccountInvitationPreviewSuccess(_preview),
    );
    await tester.pumpAndSettle();
    await tester.tap(_acceptAction);
    await tester.pumpAndSettle();
    _expectLiveRegion(tester, _status);
    _expectLiveRegion(tester, _uncertain);
    semantics.dispose();
  });

  testWidgets('narrow large text and English dark remain usable', (
    tester,
  ) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final semantics = tester.ensureSemantics();
    _useNarrowLargeText(tester);
    final longPreview = OrganizationDirectedAccountInvitationPreview(
      organizationInvitationPreviewContractId: _previewContractId,
      invitationId: _invitationId,
      organizationName: '很长的组织原始名称 ${List.filled(60, '界').join()}',
      expiresAtUtc: DateTime.utc(2030, 1, 8),
    );
    final gateway = _Gateway(
      previews: [
        OrganizationDirectedAccountInvitationPreviewSuccess(longPreview),
      ],
      accepts: const [
        OrganizationDirectedAccountInvitationAcceptRejected(
          OrganizationDirectedAccountInvitationFailureCode.networkUnavailable,
        ),
      ],
    );
    await _open(
      tester,
      fixture.session,
      gateway,
      textScaler: TextScaler.linear(2),
    );
    for (final target in [_closeAction, _previewAction]) {
      _expectMinimumTouchTarget(tester, target);
    }
    await _loadPreview(tester, _invitationId);
    for (final target in [_closeAction, _editAction, _acceptAction]) {
      _expectMinimumTouchTarget(tester, target);
    }
    final actionTop = tester.getRect(_editAction).top;
    for (final expiry in [
      find.text(const AppStrings('zh').t('organizationInvitationExpiresAt')),
      find.text('2030-01-08T00:00:00.000Z'),
    ]) {
      expect(
        tester.getRect(expiry).bottom,
        lessThanOrEqualTo(actionTop),
        reason: '$expiry is hidden below the fixed action area',
      );
    }
    await tester.tap(_acceptAction);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    for (final target in [_closeAction, _acceptAction]) {
      _expectMinimumTouchTarget(tester, target);
    }
    final dialogTop = tester
        .getRect(find.byType(OrganizationInvitationAcceptDialog))
        .top;
    final actionsTop = tester.getRect(_acceptAction).top;
    for (final message in [_uncertain, _status]) {
      final rect = tester.getRect(message);
      expect(rect.top, lessThan(actionsTop));
      expect(rect.bottom, greaterThan(dialogTop));
    }
    await tester.tap(_closeAction);
    await tester.pump();
    await tester.tap(_discardAction);
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(1280, 900);
    await _open(
      tester,
      fixture.session,
      _Gateway(
        previews: [
          OrganizationDirectedAccountInvitationPreviewSuccess(_preview),
        ],
      ),
      localeCode: 'en',
      themeMode: ThemeMode.dark,
    );
    await _loadPreview(tester, _invitationId);
    expect(tester.takeException(), isNull);
    expect(find.text(_preview.organizationName), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('Tab, Enter, and Escape keep native dialog paths', (
    tester,
  ) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gateway = _Gateway(
      previews: [OrganizationDirectedAccountInvitationPreviewSuccess(_preview)],
      accepts: [OrganizationDirectedAccountInvitationAcceptSuccess(_receipt)],
    );
    final result = _ResultBox();
    await _pumpLauncher(tester, fixture.session, gateway, result: result);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_hasPrimaryFocus(_invitationIdField), isTrue);

    await tester.enterText(_invitationIdField, _invitationId);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(gateway.previewCalls, [_invitationId]);
    await _focusByTabbing(tester, _acceptAction);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(result.receipt, same(_receipt));
    expect(_hasPrimaryFocus(_launcher), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(OrganizationInvitationAcceptDialog), findsNothing);
    expect(_hasPrimaryFocus(_launcher), isTrue);
  });

  testWidgets('disposed dialog ignores a late preview', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final pending =
        Completer<OrganizationDirectedAccountInvitationPreviewResult>();
    final gateway = _Gateway(previews: [pending]);
    await _open(tester, fixture.session, gateway);
    await tester.enterText(_invitationIdField, _invitationId);
    await tester.tap(_previewAction);
    await tester.pump();

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    pending.complete(
      OrganizationDirectedAccountInvitationPreviewSuccess(_preview),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

final _launcher = find.byKey(
  const ValueKey('open-organization-invitation-accept'),
);
final _invitationIdField = find.byKey(
  const ValueKey('organization-invitation-id'),
);
final _previewAction = find.byKey(
  const ValueKey('organization-invitation-preview'),
);
final _acceptAction = find.byKey(
  const ValueKey('organization-invitation-accept'),
);
final _editAction = find.byKey(const ValueKey('organization-invitation-edit'));
final _closeAction = find.byKey(
  const ValueKey('organization-invitation-close'),
);
final _status = find.byKey(const ValueKey('organization-invitation-status'));
final _uncertain = find.byKey(
  const ValueKey('organization-invitation-uncertain'),
);
final _keepRetryAction = find.byKey(
  const ValueKey('organization-invitation-keep-retry'),
);
final _discardAction = find.byKey(
  const ValueKey('organization-invitation-discard'),
);

Future<void> _loadPreview(WidgetTester tester, String invitationId) async {
  await tester.enterText(_invitationIdField, invitationId);
  await tester.tap(_previewAction);
  await tester.pumpAndSettle();
}

Future<void> _open(
  WidgetTester tester,
  AppSession session,
  OrganizationDirectedAccountInvitationGateway gateway, {
  _ResultBox? result,
  String localeCode = 'zh',
  TextScaler textScaler = TextScaler.noScaling,
  ThemeMode themeMode = ThemeMode.light,
}) async {
  await _pumpLauncher(
    tester,
    session,
    gateway,
    result: result,
    localeCode: localeCode,
    textScaler: textScaler,
    themeMode: themeMode,
  );
  await tester.tap(_launcher);
  await tester.pumpAndSettle();
}

Future<void> _pumpLauncher(
  WidgetTester tester,
  AppSession session,
  OrganizationDirectedAccountInvitationGateway gateway, {
  _ResultBox? result,
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
            key: const ValueKey('open-organization-invitation-accept'),
            onPressed: () async {
              final receipt =
                  await showDialog<
                    OrganizationDirectedAccountInvitationAcceptReceipt
                  >(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => OrganizationInvitationAcceptDialog(
                      text: AppStrings(localeCode),
                      gateway: gateway,
                      appSession: session,
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

void _useNarrowLargeText(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 568);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

void _expectLiveRegion(WidgetTester tester, Finder finder) {
  expect(
    tester.getSemantics(finder).getSemanticsData().flagsCollection.isLiveRegion,
    isTrue,
  );
}

void _expectMinimumTouchTarget(WidgetTester tester, Finder finder) {
  final rect = tester.getSemantics(finder).rect;
  expect(rect.width, greaterThanOrEqualTo(48), reason: '$finder width');
  expect(rect.height, greaterThanOrEqualTo(48), reason: '$finder height');
}

bool _hasPrimaryFocus(Finder finder) {
  final target = finder.evaluate().single;
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

Future<void> _focusByTabbing(WidgetTester tester, Finder target) async {
  for (var i = 0; i < 12; i++) {
    if (_hasPrimaryFocus(target)) return;
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  }
  fail('Tab sequence did not reach $target');
}

final class _ResultBox {
  OrganizationDirectedAccountInvitationAcceptReceipt? receipt;
}

final class _Gateway implements OrganizationDirectedAccountInvitationGateway {
  _Gateway({
    Iterable<Object> previews = const [],
    Iterable<Object> accepts = const [],
  }) : _previews = Queue.of(previews),
       _accepts = Queue.of(accepts);

  final Queue<Object> _previews;
  final Queue<Object> _accepts;
  final List<String> previewCalls = [];
  final List<String> acceptCalls = [];

  @override
  Future<OrganizationDirectedAccountInvitationPreviewResult> preview({
    required String invitationId,
  }) {
    previewCalls.add(invitationId);
    if (_previews.isEmpty) {
      return Future.value(
        const OrganizationDirectedAccountInvitationPreviewRejected(
          OrganizationDirectedAccountInvitationFailureCode.notConfigured,
        ),
      );
    }
    return _next<OrganizationDirectedAccountInvitationPreviewResult>(
      _previews.removeFirst(),
    );
  }

  @override
  Future<OrganizationDirectedAccountInvitationAcceptResult> accept({
    required String invitationId,
  }) {
    acceptCalls.add(invitationId);
    if (_accepts.isEmpty) {
      return Future.value(
        const OrganizationDirectedAccountInvitationAcceptRejected(
          OrganizationDirectedAccountInvitationFailureCode.notConfigured,
        ),
      );
    }
    return _next<OrganizationDirectedAccountInvitationAcceptResult>(
      _accepts.removeFirst(),
    );
  }

  Future<T> _next<T>(Object next) {
    if (next is Completer<T>) return next.future;
    if (next is T) return Future.value(next as T);
    return Future.error(next);
  }

  @override
  Future<OrganizationDirectedAccountInvitationCreateResult> create({
    required String invitationId,
    required String organizationWorkspaceId,
    required String targetAppUserId,
  }) => throw UnsupportedError('unused test-only create');

  @override
  Future<void> close() async {}
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
      throw UnsupportedError('unused test-only identity method');
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
  appUserId: '51111111-1111-4111-8111-111111111111',
  workspace: WorkspaceContext(
    id: '61111111-1111-4111-8111-111111111111',
    kind: WorkspaceKind.personal,
    name: '个人空间乙',
  ),
  project: ProjectContext(
    id: '71111111-1111-4111-8111-111111111111',
    name: '项目乙',
  ),
  questionnaireVersion: QuestionnaireVersionContext(
    id: '81111111-1111-4111-8111-111111111111',
    versionNumber: 2,
  ),
  capabilities: {},
);

const _previewContractId =
    'organization-directed-account-invitation-preview:v1';
const _invitationId = 'abcdefab-cdef-0abc-0def-abcdefabcdef';
const _otherInvitationId = 'abcdefab-cdef-0abc-0def-abcdefabcdea';
const _workspaceId = 'abcdefab-cdef-0abc-0def-abcdefabcdeb';
const _membershipId = 'abcdefab-cdef-0abc-0def-abcdefabcdec';

final _preview = OrganizationDirectedAccountInvitationPreview(
  organizationInvitationPreviewContractId: _previewContractId,
  invitationId: _invitationId,
  organizationName: '权威组织名',
  expiresAtUtc: DateTime.utc(2030, 1, 8),
);
final _otherPreview = OrganizationDirectedAccountInvitationPreview(
  organizationInvitationPreviewContractId: _previewContractId,
  invitationId: _otherInvitationId,
  organizationName: '另一组织',
  expiresAtUtc: DateTime.utc(2030, 2, 8),
);
final _receipt = OrganizationDirectedAccountInvitationAcceptReceipt(
  organizationInvitationContractId:
      'organization-directed-account-invitation:v1',
  invitationId: _invitationId,
  organizationWorkspaceId: _workspaceId,
  organizationMembershipId: _membershipId,
  acceptedAtUtc: DateTime.utc(2030, 1, 2, 4, 5, 6),
);
