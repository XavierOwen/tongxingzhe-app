import 'dart:async';

import 'package:tongxingzhe_app/identity/identity_session.dart';

/// 只存在于 test/，Flutter production build 不会编译这个 fake。
final class FakeIdentitySessionFactory implements IdentitySessionFactory {
  FakeIdentitySessionFactory(this.session);

  final FakeIdentitySession session;

  @override
  Future<IdentitySession> open() async => session;
}

final class FakeIdentitySession implements IdentitySession {
  FakeIdentitySession({
    IdentitySnapshot initial = const IdentitySnapshot.signedOut(),
  }) : _current = initial;

  final StreamController<IdentitySnapshot> _changes =
      StreamController<IdentitySnapshot>.broadcast();
  IdentitySnapshot _current;
  IdentityFailure? rejectNextWith;
  bool isClosed = false;

  @override
  IdentitySnapshot get current => _current;

  @override
  Stream<IdentitySnapshot> get changes => _changes.stream;

  @override
  Future<IdentityResult<IdentitySnapshot>> restore() => _complete(_current);

  @override
  Future<IdentityResult<IdentitySnapshot>> signUp({
    required String email,
    required String password,
  }) {
    return _complete(
      IdentitySnapshot(
        stage: IdentityStage.awaitingEmailConfirmation,
        principal: IdentityPrincipal(
          externalSubject: 'test-subject',
          email: email.trim().toLowerCase(),
        ),
      ),
    );
  }

  @override
  Future<IdentityResult<IdentitySnapshot>> confirmSignUpOtp({
    required String email,
    required String otp,
  }) => _complete(_signedIn(email));

  @override
  Future<IdentityResult<IdentitySnapshot>> signIn({
    required String email,
    required String password,
  }) => _complete(_signedIn(email));

  @override
  Future<IdentityResult<IdentitySnapshot>> requestPasswordRecovery({
    required String email,
  }) =>
      _complete(const IdentitySnapshot(stage: IdentityStage.recoveryCodeSent));

  @override
  Future<IdentityResult<IdentitySnapshot>> confirmPasswordRecoveryOtp({
    required String email,
    required String otp,
  }) => _complete(
    IdentitySnapshot(
      stage: IdentityStage.changingRecoveredPassword,
      principal: _principal(email),
    ),
  );

  @override
  Future<IdentityResult<IdentitySnapshot>> updateRecoveredPassword({
    required String newPassword,
  }) {
    final email = _current.principal?.email ?? 'fake@example.test';
    return _complete(_signedIn(email));
  }

  @override
  Future<IdentityResult<IdentitySnapshot>> refresh() => _complete(_current);

  @override
  Future<IdentityResult<IdentitySnapshot>> signOut() {
    return _complete(const IdentitySnapshot.signedOut());
  }

  @override
  Future<IdentityResult<IdentityAccessToken>> accessToken({
    bool forceRefresh = false,
  }) async {
    final failure = _takeFailure();
    if (failure != null) {
      return IdentityRejected(failure);
    }
    if (!_current.isAuthenticated) {
      return const IdentityRejected(
        IdentityFailure(code: IdentityFailureCode.sessionMissing),
      );
    }
    return IdentitySuccess(
      IdentityAccessToken(
        value: 'test-only-access-token',
        expiresAt: DateTime.utc(2030, 1, 2, 4, 4),
      ),
    );
  }

  @override
  Future<void> close() async {
    if (isClosed) {
      return;
    }
    isClosed = true;
    await _changes.close();
  }

  Future<IdentityResult<IdentitySnapshot>> _complete(
    IdentitySnapshot next,
  ) async {
    final failure = _takeFailure();
    if (failure != null) {
      return IdentityRejected(failure);
    }
    _current = next;
    _changes.add(next);
    return IdentitySuccess(next);
  }

  IdentityFailure? _takeFailure() {
    final failure = rejectNextWith;
    rejectNextWith = null;
    return failure;
  }

  IdentitySnapshot _signedIn(String email) {
    return IdentitySnapshot(
      stage: IdentityStage.signedIn,
      principal: _principal(email),
      expiresAt: DateTime.utc(2030, 1, 2, 4, 4),
    );
  }

  IdentityPrincipal _principal(String email) {
    return IdentityPrincipal(
      externalSubject: 'test-subject',
      email: email.trim().toLowerCase(),
    );
  }
}
