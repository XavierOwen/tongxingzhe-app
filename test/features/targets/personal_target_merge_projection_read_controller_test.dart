import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/app_session/app_session.dart';
import 'package:tongxingzhe_app/app_session/session_context_gateway.dart';
import 'package:tongxingzhe_app/features/targets/personal_target_merge_projection_read_controller.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/privacy/offline_pii_vault.dart';
import 'package:tongxingzhe_app/targets/personal_target_merge_projection.dart';
import 'package:tongxingzhe_app/targets/promotion_target.dart';

import '../../support/fake_identity_session.dart';
import '../../support/fake_runtime_values.dart';
import '../../support/fake_session_context_gateway.dart';

void main() {
  test(
    'explicit read captures scope and never refreshes or closes borrowed resources',
    () async {
      final h = await _Harness.start();
      addTearDown(h.close);
      final contextCalls = h.contextGateway.receivedTokens.length;

      final pending = h.controller.read(_generationA);

      expect(h.controller.loading, isTrue);
      expect(h.controller.selectedGenerationId, _generationA);
      expect(h.gateway.requests.single.subject, 'owner');
      expect(h.gateway.requests.single.workspaceId, _context().workspace.id);
      expect(h.gateway.requests.single.projectId, _context().project.id);
      expect(h.gateway.requests.single.generationId, _generationA);
      expect(h.gateway.requests.single.isCurrent(), isTrue);
      final projection = _projection(_generationA);
      h.gateway.requests.single.complete(projection);
      await pending;

      expect(h.controller.loading, isFalse);
      expect(h.controller.projection, same(projection));
      expect(h.controller.failure, isNull);
      expect(h.contextGateway.receivedTokens, hasLength(contextCalls));
      h.controller.dispose();
      expect(h.controller.projection, isNull);
      expect(h.identity.isClosed, isFalse);
      expect(h.contextGateway.isClosed, isFalse);
      expect(h.gateway.closed, isFalse);
      expect(h.session.current.stage, AppSessionStage.ready);
    },
  );

  for (final entry in <String, TrustedSessionContext>{
    'organization': _context(kind: WorkspaceKind.organization),
    'missing view capability': _context(
      capabilities: {'manage_assigned_target_merges'},
    ),
    'missing merge capability': _context(
      capabilities: {'view_assigned_target_pii'},
    ),
  }.entries) {
    test('local read gate rejects ${entry.key}', () async {
      final h = await _Harness.start(context: entry.value);
      addTearDown(h.close);
      await h.controller.read(_generationA);
      expect(h.gateway.requests, isEmpty);
      expect(h.controller.projection, isNull);
      expect(
        h.controller.failure,
        PersonalTargetMergeProjectionFailure.forbidden,
      );
    });
  }

  test('not-ready and signed-out sessions do not call the gateway', () async {
    final h = await _Harness.start(startSession: false);
    addTearDown(h.close);
    await h.controller.read(_generationA);
    expect(h.gateway.requests, isEmpty);
    await h.session.start();
    h.identity.emit(const IdentitySnapshot.signedOut());
    await h.controller.read(_generationA);
    expect(h.gateway.requests, isEmpty);
    expect(
      h.controller.failure,
      PersonalTargetMergeProjectionFailure.unauthenticated,
    );
  });

  test(
    'offline-cache context is refused until an explicit online read',
    () async {
      final now = DateTime.utc(2026, 8, 20, 12);
      final vault = OfflinePiiVault(
        secureStore: _SecureStore(),
        lockStore: _LockStore(),
        clock: FixedClock(now),
        installationId: 'synthetic-controller',
      );
      await vault.replace(
        externalSubject: 'owner',
        context: _context(),
        assignedTargets: const [],
        authorizedAtUtc: now,
      );
      final h = await _Harness.start(vault: vault, offline: true);
      addTearDown(h.close);
      expect(h.session.current.fromOfflineCache, isTrue);
      await h.controller.read(_generationA);
      expect(h.gateway.requests, isEmpty);
      h.identity.emit(_identity(expiresAt: now.add(const Duration(hours: 1))));
      await _flush();
      expect(h.session.current.fromOfflineCache, isFalse);
      expect(h.controller.projection, isNull);
      final pending = h.controller.read(_generationA);
      h.gateway.requests.single.complete(_projection(_generationA));
      await pending;
      expect(h.controller.projection, isNotNull);
    },
  );

  for (final entry in <String, TrustedSessionContext>{
    'actor': _context(actorId: 'other-actor'),
    'workspace': _context(workspaceId: 'other-workspace'),
    'project': _context(projectId: 'other-project'),
    'view capability': _context(
      capabilities: {'manage_assigned_target_merges'},
    ),
    'merge capability': _context(capabilities: {'view_assigned_target_pii'}),
    'workspace kind': _context(kind: WorkspaceKind.organization),
  }.entries) {
    test(
      '${entry.key} change clears held projection and ABA cannot revive pending results',
      () async {
        final h = await _Harness.start();
        addTearDown(h.close);
        var pending = h.controller.read(_generationA);
        h.gateway.requests.last.complete(_projection(_generationA));
        await pending;
        await h.select(entry.value);
        expect(h.controller.projection, isNull);
        expect(h.controller.selectedGenerationId, isNull);
        await h.select(_context());
        expect(h.controller.projection, isNull);

        pending = h.controller.read(_generationA);
        final request = h.gateway.requests.last;
        await h.select(entry.value);
        await h.select(_context());
        expect(request.isCurrent(), isFalse);
        request.complete(_projection(_generationA));
        await pending;
        expect(h.controller.projection, isNull);
        expect(
          h.controller.failure,
          PersonalTargetMergeProjectionFailure.requestInvalidated,
        );
      },
    );
  }

  for (final lateError in [false, true]) {
    test(
      'identity ABA ignores late ${lateError ? 'failure' : 'success'} even when current already recovered',
      () async {
        final h = await _Harness.start();
        addTearDown(h.close);
        final pending = h.controller.read(_generationA);
        h.identity.emit(_identity(subject: 'other'));
        h.identity.emit(_identity());
        expect(h.identity.current.principal!.externalSubject, 'owner');
        await _flush();
        final request = h.gateway.requests.single;
        expect(request.isCurrent(), isFalse);
        if (lateError) {
          request.result.completeError(
            StateError('synthetic PII must not escape'),
          );
        } else {
          request.complete(_projection(_generationA));
        }
        await pending;
        expect(h.controller.projection, isNull);
        expect(
          h.controller.failure,
          PersonalTargetMergeProjectionFailure.requestInvalidated,
        );
      },
    );
  }

  test('sign-out removes a held projection', () async {
    final h = await _Harness.start();
    addTearDown(h.close);
    final pending = h.controller.read(_generationA);
    h.gateway.requests.single.complete(_projection(_generationA));
    await pending;
    h.identity.emit(const IdentitySnapshot.signedOut());
    await _flush();
    expect(h.controller.projection, isNull);
    expect(h.controller.loading, isFalse);
  });

  test(
    'same-subject token metadata updates preserve ready projection and pending fence',
    () async {
      final h = await _Harness.start();
      addTearDown(h.close);
      var pending = h.controller.read(_generationA);
      final projection = _projection(_generationA);
      h.gateway.requests.last.complete(projection);
      await pending;
      final contextCalls = h.contextGateway.receivedTokens.length;
      h.identity.emit(
        _identity(expiresAt: DateTime.utc(2031), email: 'updated@example.test'),
      );
      await _flush();
      expect(h.controller.projection, same(projection));
      expect(h.contextGateway.receivedTokens, hasLength(contextCalls));
      pending = h.controller.read(_generationA);
      h.identity.emit(_identity(expiresAt: DateTime.utc(2032)));
      await _flush();
      expect(h.gateway.requests.last.isCurrent(), isTrue);
      h.gateway.requests.last.complete(projection);
      await pending;
      expect(h.controller.projection, same(projection));
    },
  );

  for (final sameSelector in [false, true]) {
    for (final lateError in [false, true]) {
      test(
        'latest request wins with ${sameSelector ? 'same' : 'new'} selector and late ${lateError ? 'error' : 'success'}',
        () async {
          final h = await _Harness.start();
          addTearDown(h.close);
          var ready = h.controller.read(_generationA);
          h.gateway.requests.last.complete(_projection(_generationA));
          await ready;
          final old = h.controller.read(_generationA);
          expect(h.controller.projection, isNull);
          final secondId = sameSelector ? _generationA : _generationB;
          ready = h.controller.read(secondId);
          expect(h.controller.projection, isNull);
          expect(h.controller.selectedGenerationId, secondId);
          final latest = _projection(secondId);
          h.gateway.requests.last.complete(latest);
          await ready;
          final stale = h.gateway.requests[h.gateway.requests.length - 2];
          expect(stale.isCurrent(), isFalse);
          if (lateError) {
            stale.result.complete(
              const PersonalTargetMergeProjectionRejected(
                PersonalTargetMergeProjectionFailure.forbidden,
              ),
            );
          } else {
            stale.complete(_projection(_generationA));
          }
          await old;
          expect(h.controller.projection, same(latest));
          expect(h.controller.failure, isNull);
        },
      );
    }
  }

  test('current typed and thrown failures remain value-free', () async {
    final h = await _Harness.start();
    addTearDown(h.close);
    var pending = h.controller.read(_generationA);
    h.gateway.requests.last.result.complete(
      const PersonalTargetMergeProjectionRejected(
        PersonalTargetMergeProjectionFailure.networkUnavailable,
      ),
    );
    await pending;
    expect(
      h.controller.failure,
      PersonalTargetMergeProjectionFailure.networkUnavailable,
    );
    pending = h.controller.read(_generationA);
    h.gateway.requests.last.result.completeError(
      StateError('synthetic private body'),
    );
    await pending;
    expect(
      h.controller.failure,
      PersonalTargetMergeProjectionFailure.serviceUnavailable,
    );
    expect(h.controller.projection, isNull);
  });

  for (final error in [false, true]) {
    for (final inFlight in [false, true]) {
      test(
        'identity stream ${error ? 'error' : 'done'} retires ${inFlight ? 'pending' : 'held'} data despite ready getters',
        () async {
          final h = await _Harness.start();
          addTearDown(h.close);
          final observed = _IdentityEvents(h.identity);
          addTearDown(observed.closeEvents);
          final controller = PersonalTargetMergeProjectionReadController(
            identitySession: observed,
            appSession: h.session,
            gateway: h.gateway,
          );
          addTearDown(controller.dispose);
          var pending = controller.read(_generationA);
          h.gateway.requests.last.complete(_projection(_generationA));
          await pending;
          if (inFlight) pending = controller.read(_generationA);
          if (error) {
            observed.events.addError(
              StateError('synthetic identity stream error'),
            );
          } else {
            await observed.closeEvents();
          }
          await _flush();
          expect(h.session.current.stage, AppSessionStage.ready);
          expect(observed.current.stage, IdentityStage.signedIn);
          expect(controller.projection, isNull);
          expect(controller.loading, isFalse);
          expect(h.gateway.requests.last.isCurrent(), isFalse);
          if (inFlight) {
            h.gateway.requests.last.complete(_projection(_generationA));
            await pending;
          }
          final requestCount = h.gateway.requests.length;
          await controller.read(_generationA);
          expect(h.gateway.requests, hasLength(requestCount));
          expect(observed.closedByBorrower, isFalse);
        },
      );
    }
  }

  for (final inFlight in [false, true]) {
    test(
      'AppSession done retires ${inFlight ? 'pending' : 'held'} data while current remains ready',
      () async {
        final h = await _Harness.start();
        addTearDown(h.close);
        final pending = h.controller.read(_generationA);
        if (!inFlight) {
          h.gateway.requests.last.complete(_projection(_generationA));
          await pending;
        }
        await h.session.close();
        await _flush();
        expect(h.session.current.stage, AppSessionStage.ready);
        expect(h.controller.loading, isFalse);
        expect(h.gateway.requests.last.isCurrent(), isFalse);
        if (inFlight) {
          h.gateway.requests.last.complete(_projection(_generationA));
          await pending;
        }
        expect(h.controller.projection, isNull);
      },
    );
  }

  test(
    'dispose cancels subscriptions and ignores future responses without notifications',
    () async {
      final h = await _Harness.start();
      addTearDown(h.close);
      var notifications = 0;
      h.controller.addListener(() => notifications++);
      final pending = h.controller.read(_generationA);
      final beforeDispose = notifications;
      h.controller.dispose();
      h.identity.emit(const IdentitySnapshot.signedOut());
      await _flush();
      h.gateway.requests.last.complete(_projection(_generationA));
      await pending;
      await h.controller.read(_generationB);
      expect(notifications, beforeDispose);
      expect(h.controller.projection, isNull);
      expect(h.controller.loading, isFalse);
      expect(h.gateway.requests, hasLength(1));
      expect(h.gateway.closed, isFalse);
      expect(h.identity.isClosed, isFalse);
    },
  );
}

const _generationA = '7e900000-0000-4000-8000-000000000101';
const _generationB = '7e900000-0000-4000-8000-000000000102';

IdentitySnapshot _identity({
  String subject = 'owner',
  String email = 'owner@example.test',
  DateTime? expiresAt,
}) => IdentitySnapshot(
  stage: IdentityStage.signedIn,
  principal: IdentityPrincipal(externalSubject: subject, email: email),
  expiresAt: expiresAt ?? DateTime.utc(2030),
);

TrustedSessionContext _context({
  String? actorId,
  String? workspaceId,
  String? projectId,
  WorkspaceKind kind = WorkspaceKind.personal,
  Set<String> capabilities = const {
    'view_assigned_target_pii',
    'manage_assigned_target_merges',
  },
}) => TrustedSessionContext(
  appUserId: actorId ?? syntheticSessionContext.appUserId,
  workspace: WorkspaceContext(
    id: workspaceId ?? syntheticSessionContext.workspace.id,
    kind: kind,
    name: 'Synthetic workspace',
  ),
  project: ProjectContext(
    id: projectId ?? syntheticSessionContext.project.id,
    name: 'Synthetic project',
  ),
  questionnaireVersion: syntheticSessionContext.questionnaireVersion,
  capabilities: capabilities,
);

PersonalTargetMergeProjection _projection(String generationId) =>
    PersonalTargetMergeProjection(
      generationId: generationId,
      workspaceId: _context().workspace.id,
      projectId: _context().project.id,
      targetType: PromotionTargetType.person,
      retainedTargetId: 'target-a',
      displayNameSourceTargetId: 'target-a',
      phoneSourceTargetId: 'target-b',
      emailSourceTargetId: 'target-a',
      displayName: 'Synthetic source',
      phone: null,
      email: null,
      reviewDueAtUtc: DateTime.utc(2027),
      sources: const [],
    );

Future<void> _flush() => Future<void>.delayed(Duration.zero);

final class _Harness {
  _Harness(
    this.identity,
    this.contextGateway,
    this.session,
    this.gateway,
    this.controller,
  );
  final FakeIdentitySession identity;
  final FakeSessionContextGateway contextGateway;
  final AppSession session;
  final _Gateway gateway;
  final PersonalTargetMergeProjectionReadController controller;

  static Future<_Harness> start({
    TrustedSessionContext? context,
    bool startSession = true,
    OfflinePiiVault? vault,
    bool offline = false,
  }) async {
    final identity = FakeIdentitySession(initial: _identity());
    if (offline) {
      identity.rejectNextAccessTokenWith = const IdentityFailure(
        code: IdentityFailureCode.networkUnavailable,
      );
    }
    final contexts = FakeSessionContextGateway(
      context: context ?? _context(),
      selectedContexts: {},
    );
    final session = AppSession(
      identitySession: identity,
      contextGateway: contexts,
      offlinePiiVault: vault,
    );
    if (startSession) await session.start();
    final gateway = _Gateway();
    final controller = PersonalTargetMergeProjectionReadController(
      identitySession: identity,
      appSession: session,
      gateway: gateway,
    );
    return _Harness(identity, contexts, session, gateway, controller);
  }

  Future<void> select(TrustedSessionContext context) async {
    contextGateway.selectedContexts[context.project.id] = context;
    await session.selectProject(context.project.id);
    await _flush();
  }

  Future<void> close() async {
    controller.dispose();
    await session.close();
    await identity.close();
  }
}

final class _Request {
  _Request(
    this.subject,
    this.workspaceId,
    this.projectId,
    this.generationId,
    this.isCurrent,
  );
  final String subject;
  final String workspaceId;
  final String projectId;
  final String generationId;
  final bool Function() isCurrent;
  final result = Completer<PersonalTargetMergeProjectionResult>();
  void complete(PersonalTargetMergeProjection projection) =>
      result.complete(PersonalTargetMergeProjectionReady(projection));
}

final class _Gateway implements PersonalTargetMergeProjectionGateway {
  final requests = <_Request>[];
  bool closed = false;
  @override
  Future<PersonalTargetMergeProjectionResult> read({
    required String expectedSubject,
    required String workspaceId,
    required String projectId,
    required String generationId,
    required bool Function() requestIsCurrent,
  }) {
    final request = _Request(
      expectedSubject,
      workspaceId,
      projectId,
      generationId,
      requestIsCurrent,
    );
    requests.add(request);
    return request.result.future;
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

final class _IdentityEvents implements IdentitySession {
  _IdentityEvents(this.identity);
  final FakeIdentitySession identity;
  final events = StreamController<IdentitySnapshot>.broadcast();
  bool closedByBorrower = false;
  @override
  IdentitySnapshot get current => identity.current;
  @override
  Stream<IdentitySnapshot> get changes => events.stream;
  @override
  Future<void> close() async {
    closedByBorrower = true;
  }

  Future<void> closeEvents() async {
    if (!events.isClosed) await events.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unused identity method');
}

final class _SecureStore implements SecureValueStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

final class _LockStore implements OfflinePiiLockStore {
  final values = <String, OfflinePiiLock>{};
  @override
  Future<OfflinePiiLock?> read(String scopeKey) async => values[scopeKey];
  @override
  Future<void> write(String scopeKey, OfflinePiiLock lock) async {
    values[scopeKey] = lock;
  }

  @override
  Future<void> clear(String scopeKey) async {
    values.remove(scopeKey);
  }
}
