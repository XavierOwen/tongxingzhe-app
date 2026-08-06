import 'dart:async';

import '../identity/identity_session.dart';
import '../privacy/offline_pii_vault.dart';
import 'session_context_gateway.dart';

enum AppSessionStage { unavailable, signedOut, resolvingContext, ready, failed }

final class AppSessionSnapshot {
  const AppSessionSnapshot({
    required this.stage,
    this.identity,
    this.context,
    this.availableContexts = const [],
    this.identityFailure,
    this.contextFailure,
    this.fromOfflineCache = false,
  });

  const AppSessionSnapshot.unavailable()
    : this(stage: AppSessionStage.unavailable);

  const AppSessionSnapshot.signedOut() : this(stage: AppSessionStage.signedOut);

  final AppSessionStage stage;
  final IdentitySnapshot? identity;
  final TrustedSessionContext? context;
  final List<TrustedSessionContext> availableContexts;
  final IdentityFailureCode? identityFailure;
  final SessionContextFailureCode? contextFailure;
  final bool fromOfflineCache;

  bool get canRecordContact =>
      stage == AppSessionStage.ready &&
      context!.capabilities.contains('record_contact');
}

/// 把外部登录态解析为 App 可以使用的可信内部上下文。
///
/// 调用方只观察一个 snapshot。token 刷新、Backend 请求、并发注销和过期响应
/// 都留在模块内部。
final class AppSession {
  factory AppSession({
    required IdentitySession identitySession,
    required SessionContextGateway contextGateway,
    OfflinePiiVault? offlinePiiVault,
  }) => AppSession._(identitySession, contextGateway, offlinePiiVault);

  AppSession._(
    this._identitySession,
    this._contextGateway,
    this._offlinePiiVault,
  );

  final IdentitySession _identitySession;
  final SessionContextGateway _contextGateway;
  final OfflinePiiVault? _offlinePiiVault;
  final StreamController<AppSessionSnapshot> _changes =
      StreamController<AppSessionSnapshot>.broadcast();
  StreamSubscription<IdentitySnapshot>? _identitySubscription;
  AppSessionSnapshot _current = const AppSessionSnapshot.unavailable();
  String? _lastIdentityKey;
  Future<void>? _lastIdentityWork;
  int _generation = 0;
  bool _started = false;
  bool _closed = false;
  String? _lastSignedInSubject;

  AppSessionSnapshot get current => _current;

  Stream<AppSessionSnapshot> get changes => _changes.stream;

  Future<void> start() async {
    if (_started || _closed) {
      return;
    }
    _started = true;
    _identitySubscription = _identitySession.changes.listen(
      (identity) => unawaited(_applyIdentity(identity)),
    );

    final restored = await _identitySession.restore();
    switch (restored) {
      case IdentitySuccess<IdentitySnapshot>(:final value):
        await _applyIdentity(value);
      case IdentityRejected<IdentitySnapshot>(:final failure):
        final localIdentity = _identitySession.current;
        if (failure.code == IdentityFailureCode.networkUnavailable &&
            localIdentity.stage == IdentityStage.signedIn &&
            await _restoreOfflineContext(_generation, localIdentity)) {
          return;
        }
        await _revokeOfflinePiiForIdentityFailure(localIdentity, failure.code);
        _publish(
          AppSessionSnapshot(
            stage: AppSessionStage.failed,
            identityFailure: failure.code,
          ),
        );
    }
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _generation += 1;
    await _identitySubscription?.cancel();
    await _contextGateway.close();
    await _changes.close();
  }

  /// 切换到本人有权使用的推广项目，并采用 Backend 返回的问卷与能力上下文。
  Future<SessionContextResult> selectProject(String projectId) async {
    if (_current.stage != AppSessionStage.ready || projectId.trim().isEmpty) {
      return const SessionContextRejected(
        SessionContextFailureCode.serverRejected,
      );
    }
    final generation = ++_generation;
    final identity = _current.identity!;
    final tokenResult = await _identitySession.accessToken();
    if (!_isCurrent(generation)) {
      return const SessionContextRejected(
        SessionContextFailureCode.unauthorized,
      );
    }
    return switch (tokenResult) {
      IdentityRejected<IdentityAccessToken>(:final failure) =>
        SessionContextRejected(
          failure.code == IdentityFailureCode.networkUnavailable
              ? SessionContextFailureCode.networkUnavailable
              : SessionContextFailureCode.unauthorized,
        ),
      IdentitySuccess<IdentityAccessToken>(:final value) =>
        await _selectProject(generation, identity, value, projectId.trim()),
    };
  }

  /// 在个人空间创建推广项目，并立即切换到 Backend 建立的可信上下文。
  Future<SessionContextResult> createPersonalProject(String displayName) async {
    final normalizedName = displayName.trim();
    if (_current.stage != AppSessionStage.ready || normalizedName.isEmpty) {
      return const SessionContextRejected(
        SessionContextFailureCode.serverRejected,
      );
    }
    final generation = ++_generation;
    final identity = _current.identity!;
    final tokenResult = await _identitySession.accessToken();
    if (!_isCurrent(generation)) {
      return const SessionContextRejected(
        SessionContextFailureCode.unauthorized,
      );
    }
    switch (tokenResult) {
      case IdentityRejected<IdentityAccessToken>(:final failure):
        return SessionContextRejected(
          failure.code == IdentityFailureCode.networkUnavailable
              ? SessionContextFailureCode.networkUnavailable
              : SessionContextFailureCode.unauthorized,
        );
      case IdentitySuccess<IdentityAccessToken>(:final value):
        final result = await _contextGateway.createPersonalProject(
          value,
          normalizedName,
        );
        if (!_isCurrent(generation)) {
          return const SessionContextRejected(
            SessionContextFailureCode.unauthorized,
          );
        }
        switch (result) {
          case SessionContextSuccess(:final context, :final availableContexts):
            await _revokeOfflinePiiAfterContextChange(identity, context);
            _publish(
              AppSessionSnapshot(
                stage: AppSessionStage.ready,
                identity: identity,
                context: context,
                availableContexts: _withCurrent(context, availableContexts),
              ),
            );
          case SessionContextRejected():
            break;
        }
        return result;
    }
  }

  Future<SessionContextResult> _selectProject(
    int generation,
    IdentitySnapshot identity,
    IdentityAccessToken token,
    String projectId,
  ) async {
    final result = await _contextGateway.selectProject(token, projectId);
    if (!_isCurrent(generation)) {
      return const SessionContextRejected(
        SessionContextFailureCode.unauthorized,
      );
    }
    switch (result) {
      case SessionContextSuccess(:final context, :final availableContexts):
        await _revokeOfflinePiiAfterContextChange(identity, context);
        _publish(
          AppSessionSnapshot(
            stage: AppSessionStage.ready,
            identity: identity,
            context: context,
            availableContexts: _withCurrent(context, availableContexts),
          ),
        );
      case SessionContextRejected():
        break;
    }
    return result;
  }

  Future<void> _applyIdentity(IdentitySnapshot identity) async {
    if (_closed) {
      return;
    }
    final identityKey = _identityKey(identity);
    if (_lastIdentityKey == identityKey) {
      return _lastIdentityWork;
    }
    _lastIdentityKey = identityKey;
    final work = _resolveIdentity(identity);
    _lastIdentityWork = work;
    return work;
  }

  Future<void> _resolveIdentity(IdentitySnapshot identity) async {
    final generation = ++_generation;
    if (identity.stage == IdentityStage.signedIn) {
      final nextSubject = identity.principal?.externalSubject;
      final previousSubject = _lastSignedInSubject;
      if (previousSubject != null &&
          nextSubject != previousSubject &&
          _offlinePiiVault != null) {
        await _offlinePiiVault.revoke(
          previousSubject,
          OfflinePiiLockReason.signedOut,
        );
      }
      _lastSignedInSubject = nextSubject;
      if (nextSubject != null) {
        await _offlinePiiVault?.retryLockedDeletion(nextSubject);
      }
    }

    switch (identity.stage) {
      case IdentityStage.unavailable:
        _publish(const AppSessionSnapshot.unavailable());
        return;
      case IdentityStage.signedOut:
      case IdentityStage.awaitingEmailConfirmation:
      case IdentityStage.recoveryCodeSent:
      case IdentityStage.changingRecoveredPassword:
        final signedOutSubject = _lastSignedInSubject;
        _lastSignedInSubject = null;
        if (signedOutSubject != null) {
          await _offlinePiiVault?.revoke(
            signedOutSubject,
            OfflinePiiLockReason.signedOut,
          );
        }
        _publish(
          AppSessionSnapshot(
            stage: AppSessionStage.signedOut,
            identity: identity,
          ),
        );
        return;
      case IdentityStage.signedIn:
        _publish(
          AppSessionSnapshot(
            stage: AppSessionStage.resolvingContext,
            identity: identity,
          ),
        );
    }

    final tokenResult = await _identitySession.accessToken();
    if (!_isCurrent(generation)) {
      return;
    }
    switch (tokenResult) {
      case IdentityRejected<IdentityAccessToken>(:final failure):
        if (failure.code == IdentityFailureCode.networkUnavailable &&
            await _restoreOfflineContext(generation, identity)) {
          return;
        }
        await _revokeOfflinePiiForIdentityFailure(identity, failure.code);
        _publish(
          AppSessionSnapshot(
            stage: AppSessionStage.failed,
            identity: identity,
            identityFailure: failure.code,
          ),
        );
        return;
      case IdentitySuccess<IdentityAccessToken>(:final value):
        final contextResult = await _contextGateway.resolve(value);
        if (!_isCurrent(generation)) {
          return;
        }
        switch (contextResult) {
          case SessionContextSuccess(:final context, :final availableContexts):
            _publish(
              AppSessionSnapshot(
                stage: AppSessionStage.ready,
                identity: identity,
                context: context,
                availableContexts: _withCurrent(context, availableContexts),
              ),
            );
          case SessionContextRejected(:final code):
            if (code == SessionContextFailureCode.networkUnavailable &&
                await _restoreOfflineContext(generation, identity)) {
              return;
            }
            if (code == SessionContextFailureCode.unauthorized) {
              final subject = identity.principal?.externalSubject;
              if (subject != null) {
                await _offlinePiiVault?.revoke(
                  subject,
                  OfflinePiiLockReason.unauthorized,
                );
              }
            }
            _publish(
              AppSessionSnapshot(
                stage: AppSessionStage.failed,
                identity: identity,
                contextFailure: code,
              ),
            );
        }
    }
  }

  Future<bool> _restoreOfflineContext(
    int generation,
    IdentitySnapshot identity,
  ) async {
    final principal = identity.principal;
    final vault = _offlinePiiVault;
    if (principal == null || vault == null) return false;
    final cached = await vault.read(principal.externalSubject);
    if (!_isCurrent(generation) || cached is! OfflinePiiAvailable) {
      return false;
    }
    _lastSignedInSubject = principal.externalSubject;
    _publish(
      AppSessionSnapshot(
        stage: AppSessionStage.ready,
        identity: identity,
        context: cached.snapshot.context,
        availableContexts: [cached.snapshot.context],
        fromOfflineCache: true,
      ),
    );
    return true;
  }

  Future<void> _revokeOfflinePiiAfterContextChange(
    IdentitySnapshot identity,
    TrustedSessionContext nextContext,
  ) async {
    final previousContext = _current.context;
    final subject = identity.principal?.externalSubject;
    if (previousContext == null ||
        subject == null ||
        _offlinePiiVault == null ||
        (previousContext.workspace.id == nextContext.workspace.id &&
            previousContext.project.id == nextContext.project.id)) {
      return;
    }
    await _offlinePiiVault.revoke(subject, OfflinePiiLockReason.contextChanged);
  }

  Future<void> _revokeOfflinePiiForIdentityFailure(
    IdentitySnapshot identity,
    IdentityFailureCode failure,
  ) async {
    if (failure != IdentityFailureCode.sessionMissing &&
        failure != IdentityFailureCode.invalidCredentials) {
      return;
    }
    final subject = identity.principal?.externalSubject;
    if (subject == null) return;
    await _offlinePiiVault?.revoke(subject, OfflinePiiLockReason.unauthorized);
  }

  bool _isCurrent(int generation) => !_closed && generation == _generation;

  void _publish(AppSessionSnapshot next) {
    if (_closed) {
      return;
    }
    _current = next;
    _changes.add(next);
  }

  List<TrustedSessionContext> _withCurrent(
    TrustedSessionContext current,
    List<TrustedSessionContext> available,
  ) {
    if (available.any((item) => item.project.id == current.project.id)) {
      return List.unmodifiable(available);
    }
    return List.unmodifiable([current, ...available]);
  }

  String _identityKey(IdentitySnapshot identity) {
    final principal = identity.principal;
    return '${identity.stage.name}|${principal?.externalSubject ?? ''}|'
        '${identity.expiresAt?.toUtc().toIso8601String() ?? ''}';
  }
}
