import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/app_session/app_session.dart';
import 'package:tongxingzhe_app/app_session/session_context_gateway.dart';
import 'package:tongxingzhe_app/features/targets/personal_target_merge_directory_read_controller.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/privacy/offline_pii_vault.dart';
import 'package:tongxingzhe_app/targets/personal_target_merge_directory.dart';
import 'package:tongxingzhe_app/targets/promotion_target.dart';

import '../../support/fake_identity_session.dart';
import '../../support/fake_runtime_values.dart';
import '../../support/fake_session_context_gateway.dart';

void main() {
  test(
    'starts without reading and selects only the current page with original UUID spelling',
    () async {
      final h = await _Harness.start();
      addTearDown(h.close);
      expect(h.gateway.requests, isEmpty);
      expect(h.controller.selectGeneration(_generationA), isFalse);
      final read = h.controller.read();
      expect(h.controller.selectGeneration(_generationA), isFalse);
      final page = _directory(_generationA.toUpperCase());
      h.gateway.requests.single.complete(page);
      await read;
      expect(h.controller.selectedGenerationId, isNull);
      expect(h.controller.selectGeneration(_generationA), isTrue);
      expect(h.controller.selectedGenerationId, _generationA.toUpperCase());
      expect(h.controller.selectGeneration(_generationB), isFalse);
      expect(h.controller.selectedGenerationId, _generationA.toUpperCase());
      expect(h.controller.selectGeneration(null), isTrue);
      expect(h.controller.selectedGenerationId, isNull);
    },
  );
  test(
    'paging captures its cursor and clears held directory and selection before dispatch',
    () async {
      final h = await _Harness.start();
      addTearDown(h.close);
      var pending = h.controller.read();
      h.gateway.requests.single.complete(_directory(_generationA));
      await pending;
      expect(h.controller.selectGeneration(_generationA), isTrue);
      pending = h.controller.read(afterGenerationId: _generationA);
      expect(h.controller.directory, isNull);
      expect(h.controller.selectedGenerationId, isNull);
      expect(h.gateway.requests.last.afterGenerationId, _generationA);
      expect(h.controller.selectGeneration(_generationA), isFalse);
      h.gateway.requests.last.complete(_directory(_generationB));
      await pending;
      expect(h.controller.selectGeneration(_generationA), isFalse);
      expect(h.controller.selectGeneration(_generationB), isTrue);
      pending = h.controller.read();
      expect(h.gateway.requests.last.afterGenerationId, isNull);
      expect(h.controller.directory, isNull);
      expect(h.controller.selectedGenerationId, isNull);
      h.gateway.requests.last.complete(_directory(_generationA));
      await pending;
    },
  );
  test(
    'selection rechecks current scope before queued identity events arrive',
    () async {
      final h = await _Harness.start();
      addTearDown(h.close);
      final read = h.controller.read();
      h.gateway.requests.single.complete(_directory(_generationA));
      await read;
      expect(h.controller.selectGeneration(_generationA), isTrue);
      h.identity.emit(_identity(subject: 'other'));
      expect(h.controller.selectGeneration(_generationA), isFalse);
      expect(h.controller.directory, isNull);
      expect(h.controller.selectedGenerationId, isNull);
    },
  );

  test(
    'explicit read captures scope and never refreshes or closes borrowed resources',
    () async {
      final h = await _Harness.start();
      addTearDown(h.close);
      final contextCalls = h.contextGateway.receivedTokens.length;

      final pending = h.controller.read();

      expect(h.controller.loading, isTrue);
      expect(h.controller.selectedGenerationId, isNull);
      expect(h.gateway.requests.single.subject, 'owner');
      expect(h.gateway.requests.single.workspaceId, _context().workspace.id);
      expect(h.gateway.requests.single.projectId, _context().project.id);
      expect(h.gateway.requests.single.afterGenerationId, isNull);
      expect(h.gateway.requests.single.isCurrent(), isTrue);
      final directory = _directory(_generationA);
      h.gateway.requests.single.complete(directory);
      await pending;

      expect(h.controller.loading, isFalse);
      expect(h.controller.directory, same(directory));
      expect(h.controller.failure, isNull);
      expect(h.contextGateway.receivedTokens, hasLength(contextCalls));
      h.controller.dispose();
      expect(h.controller.directory, isNull);
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
      await h.controller.read();
      expect(h.gateway.requests, isEmpty);
      expect(h.controller.directory, isNull);
      expect(
        h.controller.failure,
        PersonalTargetMergeDirectoryFailure.forbidden,
      );
    });
  }

  test('not-ready and signed-out sessions do not call the gateway', () async {
    final h = await _Harness.start(startSession: false);
    addTearDown(h.close);
    await h.controller.read();
    expect(h.gateway.requests, isEmpty);
    await h.session.start();
    h.identity.emit(const IdentitySnapshot.signedOut());
    await h.controller.read();
    expect(h.gateway.requests, isEmpty);
    expect(
      h.controller.failure,
      PersonalTargetMergeDirectoryFailure.unauthenticated,
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
      await h.controller.read();
      expect(h.gateway.requests, isEmpty);
      h.identity.emit(_identity(expiresAt: now.add(const Duration(hours: 1))));
      await _flush();
      expect(h.session.current.fromOfflineCache, isFalse);
      expect(h.controller.directory, isNull);
      final pending = h.controller.read();
      h.gateway.requests.single.complete(_directory(_generationA));
      await pending;
      expect(h.controller.directory, isNotNull);
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
      '${entry.key} change clears held directory and ABA cannot revive pending results',
      () async {
        final h = await _Harness.start();
        addTearDown(h.close);
        var pending = h.controller.read();
        h.gateway.requests.last.complete(_directory(_generationA));
        await pending;
        await h.select(entry.value);
        expect(h.controller.directory, isNull);
        expect(h.controller.selectedGenerationId, isNull);
        await h.select(_context());
        expect(h.controller.directory, isNull);

        pending = h.controller.read();
        final request = h.gateway.requests.last;
        await h.select(entry.value);
        await h.select(_context());
        expect(request.isCurrent(), isFalse);
        request.complete(_directory(_generationA));
        await pending;
        expect(h.controller.directory, isNull);
        expect(
          h.controller.failure,
          PersonalTargetMergeDirectoryFailure.requestInvalidated,
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
        final pending = h.controller.read();
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
          request.complete(_directory(_generationA));
        }
        await pending;
        expect(h.controller.directory, isNull);
        expect(
          h.controller.failure,
          PersonalTargetMergeDirectoryFailure.requestInvalidated,
        );
      },
    );
  }

  test('sign-out removes a held directory', () async {
    final h = await _Harness.start();
    addTearDown(h.close);
    final pending = h.controller.read();
    h.gateway.requests.single.complete(_directory(_generationA));
    await pending;
    h.identity.emit(const IdentitySnapshot.signedOut());
    await _flush();
    expect(h.controller.directory, isNull);
    expect(h.controller.loading, isFalse);
  });

  test(
    'same-subject token metadata updates preserve ready directory and pending fence',
    () async {
      final h = await _Harness.start();
      addTearDown(h.close);
      var pending = h.controller.read();
      final directory = _directory(_generationA);
      h.gateway.requests.last.complete(directory);
      await pending;
      final contextCalls = h.contextGateway.receivedTokens.length;
      h.identity.emit(
        _identity(expiresAt: DateTime.utc(2031), email: 'updated@example.test'),
      );
      await _flush();
      expect(h.controller.directory, same(directory));
      expect(h.contextGateway.receivedTokens, hasLength(contextCalls));
      pending = h.controller.read();
      h.identity.emit(_identity(expiresAt: DateTime.utc(2032)));
      await _flush();
      expect(h.gateway.requests.last.isCurrent(), isTrue);
      h.gateway.requests.last.complete(directory);
      await pending;
      expect(h.controller.directory, same(directory));
    },
  );

  for (final sameSelector in [false, true]) {
    for (final lateError in [false, true]) {
      test(
        'latest request wins with ${sameSelector ? 'same' : 'new'} selector and late ${lateError ? 'error' : 'success'}',
        () async {
          final h = await _Harness.start();
          addTearDown(h.close);
          var ready = h.controller.read();
          h.gateway.requests.last.complete(_directory(_generationA));
          await ready;
          final old = h.controller.read();
          expect(h.controller.directory, isNull);
          final secondId = sameSelector ? _generationA : _generationB;
          ready = h.controller.read(afterGenerationId: secondId);
          expect(h.controller.directory, isNull);
          expect(h.controller.selectedGenerationId, isNull);
          final latest = _directory(secondId);
          h.gateway.requests.last.complete(latest);
          await ready;
          final stale = h.gateway.requests[h.gateway.requests.length - 2];
          expect(stale.isCurrent(), isFalse);
          if (lateError) {
            stale.result.complete(
              const PersonalTargetMergeDirectoryRejected(
                PersonalTargetMergeDirectoryFailure.forbidden,
              ),
            );
          } else {
            stale.complete(_directory(_generationA));
          }
          await old;
          expect(h.controller.directory, same(latest));
          expect(h.controller.failure, isNull);
        },
      );
    }
  }

  test('current typed and thrown failures remain value-free', () async {
    final h = await _Harness.start();
    addTearDown(h.close);
    var pending = h.controller.read();
    h.gateway.requests.last.result.complete(
      const PersonalTargetMergeDirectoryRejected(
        PersonalTargetMergeDirectoryFailure.networkUnavailable,
      ),
    );
    await pending;
    expect(
      h.controller.failure,
      PersonalTargetMergeDirectoryFailure.networkUnavailable,
    );
    pending = h.controller.read();
    h.gateway.requests.last.result.completeError(
      StateError('synthetic private body'),
    );
    await pending;
    expect(
      h.controller.failure,
      PersonalTargetMergeDirectoryFailure.serviceUnavailable,
    );
    expect(h.controller.directory, isNull);
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
          final controller = PersonalTargetMergeDirectoryReadController(
            identitySession: observed,
            appSession: h.session,
            gateway: h.gateway,
          );
          addTearDown(controller.dispose);
          var pending = controller.read();
          h.gateway.requests.last.complete(_directory(_generationA));
          await pending;
          if (inFlight) pending = controller.read();
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
          expect(controller.directory, isNull);
          expect(controller.loading, isFalse);
          expect(h.gateway.requests.last.isCurrent(), isFalse);
          if (inFlight) {
            h.gateway.requests.last.complete(_directory(_generationA));
            await pending;
          }
          final requestCount = h.gateway.requests.length;
          await controller.read();
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
        final pending = h.controller.read();
        if (!inFlight) {
          h.gateway.requests.last.complete(_directory(_generationA));
          await pending;
        }
        await h.session.close();
        await _flush();
        expect(h.session.current.stage, AppSessionStage.ready);
        expect(h.controller.loading, isFalse);
        expect(h.gateway.requests.last.isCurrent(), isFalse);
        if (inFlight) {
          h.gateway.requests.last.complete(_directory(_generationA));
          await pending;
        }
        expect(h.controller.directory, isNull);
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
      final pending = h.controller.read();
      final beforeDispose = notifications;
      h.controller.dispose();
      h.identity.emit(const IdentitySnapshot.signedOut());
      await _flush();
      h.gateway.requests.last.complete(_directory(_generationA));
      await pending;
      await h.controller.read(afterGenerationId: _generationB);
      expect(notifications, beforeDispose);
      expect(h.controller.directory, isNull);
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

PersonalTargetMergeDirectory _directory(String generationId) =>
    PersonalTargetMergeDirectory(
      workspaceId: _context().workspace.id,
      projectId: _context().project.id,
      nextCursor: generationId,
      items: [
        PersonalTargetMergeDirectoryItem(
          generationId: generationId,
          targetType: PromotionTargetType.person,
          retainedTargetId: 'target-a',
          memberTargetIds: const ['target-a', 'target-b'],
          reviewDueAtUtc: DateTime.utc(2027),
        ),
      ],
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
  final PersonalTargetMergeDirectoryReadController controller;

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
    final controller = PersonalTargetMergeDirectoryReadController(
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
    this.afterGenerationId,
    this.isCurrent,
  );
  final String subject;
  final String workspaceId;
  final String projectId;
  final String? afterGenerationId;
  final bool Function() isCurrent;
  final result = Completer<PersonalTargetMergeDirectoryResult>();
  void complete(PersonalTargetMergeDirectory directory) =>
      result.complete(PersonalTargetMergeDirectoryReady(directory));
}

final class _Gateway implements PersonalTargetMergeDirectoryGateway {
  final requests = <_Request>[];
  bool closed = false;
  @override
  Future<PersonalTargetMergeDirectoryResult> read({
    required String expectedSubject,
    required String workspaceId,
    required String projectId,
    String? afterGenerationId,
    required bool Function() requestIsCurrent,
  }) {
    final request = _Request(
      expectedSubject,
      workspaceId,
      projectId,
      afterGenerationId,
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
