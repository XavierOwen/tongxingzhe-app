import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/app_session/app_session.dart';
import 'package:tongxingzhe_app/features/organization_directory/organization_deletion_request_dialog.dart';
import 'package:tongxingzhe_app/foundation/runtime_values.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/l10n/app_strings.dart';
import 'package:tongxingzhe_app/organization_deletion_recovery/organization_deletion_recovery.dart';
import 'package:tongxingzhe_app/organization_directory/organization_directory.dart';
import 'package:tongxingzhe_app/privacy/offline_pii_vault.dart';

import '../../support/fake_identity_session.dart';
import '../../support/fake_session_context_gateway.dart';

void main() {
  testWidgets(
    'explicit request clears cache before every attempt, reuses id, and returns receipt',
    (tester) async {
      final store = _SecureStore();
      final fixture = await _Fixture.create(store);
      addTearDown(fixture.close);
      store.readCount = 0;
      final gateway = _RecoveryGateway(store, [
        const OrganizationDeletionRecoveryRejected(
          OrganizationDeletionRecoveryFailureCode.networkUnavailable,
        ),
        const OrganizationDeletionRecoverySuccess(
          OrganizationDeletionRequestReceipt(
            organizationWorkspaceId: _workspaceId,
            deletionRequestId: _requestId,
            effectiveAtUtc: '2026-10-03T12:00:00.000000Z',
            purgeAfterUtc: '2026-11-02T12:00:00.000000Z',
          ),
        ),
      ]);
      var generatedIds = 0;
      final returned = await _open(
        tester,
        fixture,
        gateway,
        requestIdGenerator: () {
          generatedIds++;
          return _requestId;
        },
      );

      expect(gateway.requests, isEmpty);
      await tester.tap(
        find.byKey(const ValueKey('organization-deletion-request-confirm')),
      );
      await tester.pumpAndSettle();
      expect(gateway.requests, hasLength(1));
      expect(gateway.cacheReadCounts, [1]);
      expect(
        find.text(
          const AppStrings('zh').t('organizationDeletionRequestUncertain'),
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('organization-deletion-request-confirm')),
      );
      await tester.pumpAndSettle();
      expect(gateway.requests, [
        (requestId: _requestId, organizationWorkspaceId: _workspaceId),
        (requestId: _requestId, organizationWorkspaceId: _workspaceId),
      ]);
      expect(generatedIds, 1);
      expect(gateway.cacheReadCounts, [1, 2]);
      expect(find.text('2026-10-03T12:00:00.000000Z'), findsOneWidget);
      expect(find.text('2026-11-02T12:00:00.000000Z'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('organization-deletion-request-done')),
      );
      await tester.pumpAndSettle();
      expect(returned.isCompleted, isTrue);
      final receipt = await returned.future;
      expect(receipt?.organizationWorkspaceId, _workspaceId);
      expect(receipt?.deletionRequestId, _requestId);
    },
  );

  testWidgets('cache clearing failure sends no deletion request', (
    tester,
  ) async {
    final store = _SecureStore();
    final fixture = await _Fixture.create(store);
    addTearDown(fixture.close);
    store.failRead = true;
    final gateway = _RecoveryGateway(store, const []);
    await _open(tester, fixture, gateway);

    await tester.tap(
      find.byKey(const ValueKey('organization-deletion-request-confirm')),
    );
    await tester.pumpAndSettle();
    expect(gateway.requests, isEmpty);
    expect(
      find.text(
        const AppStrings('zh').t('organizationDeletionRequestCacheClearFailed'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'English dialog scrolls and confirms through semantics on narrow screen',
    (tester) async {
      final store = _SecureStore();
      final fixture = await _Fixture.create(store);
      addTearDown(fixture.close);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final semantics = tester.ensureSemantics();
      final gateway = _RecoveryGateway(store, const [
        OrganizationDeletionRecoverySuccess(
          OrganizationDeletionRequestReceipt(
            organizationWorkspaceId: _workspaceId,
            deletionRequestId: _requestId,
            effectiveAtUtc: '2026-10-03T12:00:00.000000Z',
            purgeAfterUtc: '2026-11-02T12:00:00.000000Z',
          ),
        ),
      ]);
      await _open(
        tester,
        fixture,
        gateway,
        localeCode: 'en',
        organization: OrganizationDirectoryEntry(
          organizationWorkspaceId: _workspaceId,
          organizationName:
              'A very long organization name ${List.filled(30, 'word').join(' ')}',
        ),
        textScaler: TextScaler.linear(2),
      );
      expect(find.semantics.scrollable(axis: Axis.vertical), findsWidgets);
      expect(tester.takeException(), isNull);
      tester.semantics.tap(find.semantics.byLabel('Clear cache and submit'));
      await tester.pumpAndSettle();
      expect(gateway.requests, hasLength(1));
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets(
    'signout fences a late deletion receipt and clears request data',
    (tester) async {
      final store = _SecureStore();
      final fixture = await _Fixture.create(store);
      addTearDown(fixture.close);
      final pending =
          Completer<
            OrganizationDeletionRecoveryResult<
              OrganizationDeletionRequestReceipt
            >
          >();
      final gateway = _RecoveryGateway(store, [pending]);
      await _open(
        tester,
        fixture,
        gateway,
        requestIdGenerator: () => _requestId,
      );
      await tester.tap(
        find.byKey(const ValueKey('organization-deletion-request-confirm')),
      );
      await tester.pump();
      expect(gateway.requests, hasLength(1));

      await fixture.identity.signOut();
      await tester.pumpAndSettle();
      expect(
        find.text(
          const AppStrings('zh').t('organizationDeletionRequestUnauthorized'),
        ),
        findsOneWidget,
      );
      expect(find.text(_workspaceId), findsNothing);
      pending.complete(
        const OrganizationDeletionRecoverySuccess(
          OrganizationDeletionRequestReceipt(
            organizationWorkspaceId: _workspaceId,
            deletionRequestId: _requestId,
            effectiveAtUtc: '2026-10-03T12:00:00.000000Z',
            purgeAfterUtc: '2026-11-02T12:00:00.000000Z',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(_workspaceId), findsNothing);
      expect(find.text('2026-10-03T12:00:00.000000Z'), findsNothing);
    },
  );
}

Future<Completer<OrganizationDeletionRequestReceipt?>> _open(
  WidgetTester tester,
  _Fixture fixture,
  OrganizationDeletionRecoveryGateway gateway, {
  String Function() requestIdGenerator = _defaultRequestId,
  String localeCode = 'zh',
  OrganizationDirectoryEntry organization = _organization,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  final returned = Completer<OrganizationDeletionRequestReceipt?>();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: Scaffold(
            body: Center(
              child: FilledButton(
                key: const ValueKey('open-deletion-request'),
                onPressed: () async {
                  final receipt =
                      await showDialog<OrganizationDeletionRequestReceipt>(
                        context: context,
                        builder: (_) => OrganizationDeletionRequestDialog(
                          text: AppStrings(localeCode),
                          organization: organization,
                          gateway: gateway,
                          appSession: fixture.session,
                          requestIdGenerator: requestIdGenerator,
                        ),
                      );
                  if (!returned.isCompleted) returned.complete(receipt);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open-deletion-request')));
  await tester.pumpAndSettle();
  return returned;
}

String _defaultRequestId() => _requestId;

final class _Fixture {
  _Fixture(this.identity, this.contextGateway, this.session);

  final FakeIdentitySession identity;
  final FakeSessionContextGateway contextGateway;
  final AppSession session;

  static Future<_Fixture> create(_SecureStore secureStore) async {
    final identity = FakeIdentitySession(
      initial: IdentitySnapshot(
        stage: IdentityStage.signedIn,
        principal: const IdentityPrincipal(
          externalSubject: 'request-dialog-test-subject',
          email: 'request-dialog@example.test',
        ),
        expiresAt: DateTime.utc(2030),
      ),
    );
    final contextGateway = FakeSessionContextGateway();
    final session = AppSession(
      identitySession: identity,
      contextGateway: contextGateway,
      offlinePiiVault: OfflinePiiVault(
        secureStore: secureStore,
        lockStore: _LockStore(),
        clock: const _FixedClock(),
        installationId: 'organization-deletion-request-test',
      ),
    );
    await session.start();
    return _Fixture(identity, contextGateway, session);
  }

  Future<void> close() async {
    await session.close();
    await identity.close();
  }
}

final class _RecoveryGateway implements OrganizationDeletionRecoveryGateway {
  _RecoveryGateway(this.store, Iterable<Object> results)
    : _results = Queue.of(results);

  final _SecureStore store;
  final Queue<Object> _results;
  final requests = <({String requestId, String organizationWorkspaceId})>[];
  final cacheReadCounts = <int>[];

  @override
  Future<OrganizationDeletionRecoveryResult<OrganizationDeletionRequestReceipt>>
  requestDeletion({
    required String requestId,
    required String organizationWorkspaceId,
  }) async {
    requests.add((
      requestId: requestId,
      organizationWorkspaceId: organizationWorkspaceId,
    ));
    cacheReadCounts.add(store.readCount);
    if (_results.isEmpty) {
      return const OrganizationDeletionRecoveryRejected(
        OrganizationDeletionRecoveryFailureCode.notConfigured,
      );
    }
    final result = _results.removeFirst();
    if (result
        is Completer<
          OrganizationDeletionRecoveryResult<OrganizationDeletionRequestReceipt>
        >) {
      return result.future;
    }
    if (result
        is OrganizationDeletionRecoveryResult<
          OrganizationDeletionRequestReceipt
        >) {
      return result;
    }
    throw result;
  }

  @override
  Future<
    OrganizationDeletionRecoveryResult<OrganizationDeletionRecoveryDirectory>
  >
  listRecoverableOrganizations() async =>
      const OrganizationDeletionRecoveryRejected(
        OrganizationDeletionRecoveryFailureCode.notConfigured,
      );

  @override
  Future<OrganizationDeletionRecoveryResult<OrganizationRestorationReceipt>>
  restore({
    required String requestId,
    required String organizationWorkspaceId,
    required String deletionRequestId,
  }) async => const OrganizationDeletionRecoveryRejected(
    OrganizationDeletionRecoveryFailureCode.notConfigured,
  );

  @override
  Future<void> close() async {}
}

final class _SecureStore implements SecureValueStore {
  final values = <String, String>{};
  var readCount = 0;
  var failRead = false;

  @override
  Future<String?> read(String key) async {
    readCount++;
    if (failRead) throw StateError('synthetic cache read failure');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

final class _LockStore implements OfflinePiiLockStore {
  final locks = <String, OfflinePiiLock>{};

  @override
  Future<void> clear(String scopeKey) async => locks.remove(scopeKey);

  @override
  Future<OfflinePiiLock?> read(String scopeKey) async => locks[scopeKey];

  @override
  Future<void> write(String scopeKey, OfflinePiiLock lock) async {
    locks[scopeKey] = lock;
  }
}

final class _FixedClock implements AppClock {
  const _FixedClock();

  @override
  DateTime now() => DateTime.utc(2026, 10, 3);
}

const _workspaceId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _requestId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const _organization = OrganizationDirectoryEntry(
  organizationWorkspaceId: _workspaceId,
  organizationName: 'Test organization',
);
