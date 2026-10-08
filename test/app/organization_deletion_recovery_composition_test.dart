import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/app/app_dependencies.dart';
import 'package:tongxingzhe_app/app/tongxingzhe_app.dart';
import 'package:tongxingzhe_app/data/local_database.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/organization_deletion_recovery/organization_deletion_recovery.dart';
import 'package:tongxingzhe_app/platform/platform_capabilities.dart';

import '../support/fake_identity_session.dart';
import '../support/fake_platform_capabilities.dart';
import '../support/fake_runtime_values.dart';
import '../support/fake_session_context_gateway.dart';

void main() {
  test(
    'AppDependencies injects the shared identity into the recovery gateway',
    () async {
      final database = LocalDatabase(NativeDatabase.memory());
      final identity = FakeIdentitySession();
      final gateway = _TrackingGateway();
      IdentitySession? receivedIdentity;
      final dependencies = AppDependencies(
        databaseFactory: SingleDatabaseFactory(database),
        clock: FixedClock(DateTime.utc(2030, 1, 2)),
        idGenerator: CountingIdGenerator(),
        identitySessionFactory: FakeIdentitySessionFactory(identity),
        sessionContextGateway: FakeSessionContextGateway(),
        platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
        organizationDeletionRecoveryGatewayBuilder: (session) {
          receivedIdentity = session;
          return gateway;
        },
      );

      final startup = await dependencies.start();
      expect(startup, isA<AppStartupReady>());
      final ready = startup as AppStartupReady;
      expect(identical(receivedIdentity, ready.identitySession), isTrue);
      expect(
        identical(ready.organizationDeletionRecoveryGateway, gateway),
        isTrue,
      );
      await ready.organizationDeletionRecoveryGateway.close();
      expect(gateway.closeCount, 1);
      await ready.appSession.close();
      await ready.identitySession.close();
      await database.close();
    },
  );

  testWidgets('TongxingzheApp closes the recovery gateway once on removal', (
    tester,
  ) async {
    final database = LocalDatabase(NativeDatabase.memory());
    final gateway = _TrackingGateway();
    final dependencies = AppDependencies(
      databaseFactory: SingleDatabaseFactory(database),
      clock: FixedClock(DateTime.utc(2030, 1, 2)),
      idGenerator: CountingIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(FakeIdentitySession()),
      sessionContextGateway: FakeSessionContextGateway(),
      platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
      organizationDeletionRecoveryGatewayBuilder: (_) => gateway,
    );
    addTearDown(database.close);

    await tester.pumpWidget(TongxingzheApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(gateway.closeCount, 1);
  });

  testWidgets('removal during startup closes gateways created after the wait', (
    tester,
  ) async {
    final database = LocalDatabase(NativeDatabase.memory());
    final capabilityWait = _BlockingPlatformCapabilitiesProvider();
    final gateway = _TrackingGateway();
    var builderCalls = 0;
    final dependencies = AppDependencies(
      databaseFactory: SingleDatabaseFactory(database),
      clock: FixedClock(DateTime.utc(2030, 1, 2)),
      idGenerator: CountingIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(FakeIdentitySession()),
      sessionContextGateway: FakeSessionContextGateway(),
      platformCapabilitiesProvider: capabilityWait,
      organizationDeletionRecoveryGatewayBuilder: (_) {
        builderCalls++;
        return gateway;
      },
    );
    addTearDown(database.close);

    await tester.pumpWidget(TongxingzheApp(dependencies: dependencies));
    await tester.pump();
    expect(capabilityWait.loadCalls, 1);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    capabilityWait.complete();
    await tester.pumpAndSettle();

    expect(builderCalls, 1);
    expect(gateway.closeCount, 1);
  });
}

final class _TrackingGateway implements OrganizationDeletionRecoveryGateway {
  int closeCount = 0;

  @override
  Future<OrganizationDeletionRecoveryResult<List<String>>>
  listDeletionEligibleOrganizations() async =>
      const OrganizationDeletionRecoverySuccess([]);

  @override
  Future<
    OrganizationDeletionRecoveryResult<OrganizationDeletionRecoveryDirectory>
  >
  listRecoverableOrganizations() async =>
      const OrganizationDeletionRecoveryRejected(
        OrganizationDeletionRecoveryFailureCode.notConfigured,
      );

  @override
  Future<OrganizationDeletionRecoveryResult<OrganizationDeletionRequestReceipt>>
  requestDeletion({
    required String requestId,
    required String organizationWorkspaceId,
  }) async => const OrganizationDeletionRecoveryRejected(
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
  Future<void> close() async {
    closeCount++;
  }
}

final class _BlockingPlatformCapabilitiesProvider
    implements PlatformCapabilitiesProvider {
  final _completion = Completer<PlatformCapabilities>();
  var loadCalls = 0;

  @override
  Future<PlatformCapabilities> load() {
    loadCalls++;
    return _completion.future;
  }

  void complete() => _completion.complete(fullyAvailableTestCapabilities);
}
