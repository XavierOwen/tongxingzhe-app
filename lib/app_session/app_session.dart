import 'dart:async';

import '../identity/identity_session.dart';
import 'session_context_gateway.dart';

enum AppSessionStage { unavailable, signedOut, resolvingContext, ready, failed }

final class AppSessionSnapshot {
  const AppSessionSnapshot({
    required this.stage,
    this.identity,
    this.context,
    this.identityFailure,
    this.contextFailure,
  });

  const AppSessionSnapshot.unavailable()
    : this(stage: AppSessionStage.unavailable);

  const AppSessionSnapshot.signedOut() : this(stage: AppSessionStage.signedOut);

  final AppSessionStage stage;
  final IdentitySnapshot? identity;
  final TrustedSessionContext? context;
  final IdentityFailureCode? identityFailure;
  final SessionContextFailureCode? contextFailure;

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
  }) => AppSession._(identitySession, contextGateway);

  AppSession._(this._identitySession, this._contextGateway);

  final IdentitySession _identitySession;
  final SessionContextGateway _contextGateway;
  final StreamController<AppSessionSnapshot> _changes =
      StreamController<AppSessionSnapshot>.broadcast();
  StreamSubscription<IdentitySnapshot>? _identitySubscription;
  AppSessionSnapshot _current = const AppSessionSnapshot.unavailable();
  String? _lastIdentityKey;
  Future<void>? _lastIdentityWork;
  int _generation = 0;
  bool _started = false;
  bool _closed = false;

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

    switch (identity.stage) {
      case IdentityStage.unavailable:
        _publish(const AppSessionSnapshot.unavailable());
        return;
      case IdentityStage.signedOut:
      case IdentityStage.awaitingEmailConfirmation:
      case IdentityStage.recoveryCodeSent:
      case IdentityStage.changingRecoveredPassword:
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
          case SessionContextSuccess(:final context):
            _publish(
              AppSessionSnapshot(
                stage: AppSessionStage.ready,
                identity: identity,
                context: context,
              ),
            );
          case SessionContextRejected(:final code):
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

  bool _isCurrent(int generation) => !_closed && generation == _generation;

  void _publish(AppSessionSnapshot next) {
    if (_closed) {
      return;
    }
    _current = next;
    _changes.add(next);
  }

  String _identityKey(IdentitySnapshot identity) {
    final principal = identity.principal;
    return '${identity.stage.name}|${principal?.externalSubject ?? ''}|'
        '${identity.expiresAt?.toUtc().toIso8601String() ?? ''}';
  }
}
