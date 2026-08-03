import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../identity_session.dart';

const supabaseUrlEnvironmentName = 'SUPABASE_URL';
const supabasePublishableKeyEnvironmentName = 'SUPABASE_PUBLISHABLE_KEY';

/// 读取 compile-time `--dart-define`，但不在仓库内保存任何环境值。
///
/// 两个值都缺少时返回 unavailable，方便本地安全启动；只缺一个或误放
/// `service_role`／secret key 时让启动明确失败。
IdentitySessionFactory productionIdentitySessionFactory() {
  const url = String.fromEnvironment(supabaseUrlEnvironmentName);
  const publishableKey = String.fromEnvironment(
    supabasePublishableKeyEnvironmentName,
  );

  if (url.isEmpty && publishableKey.isEmpty) {
    return const UnavailableIdentitySessionFactory();
  }

  try {
    return SupabaseIdentitySessionFactory(
      configuration: SupabaseClientConfiguration(
        url: url,
        publishableKey: publishableKey,
      ),
    );
  } on SupabaseConfigurationException catch (error) {
    return _InvalidIdentitySessionFactory(error);
  }
}

final class SupabaseClientConfiguration {
  SupabaseClientConfiguration({
    required this.url,
    required this.publishableKey,
  }) {
    _validate();
  }

  final String url;

  /// Supabase publishable／legacy anon key 可放进客户端；secret／service-role 不可。
  final String publishableKey;

  void _validate() {
    final uri = Uri.tryParse(url);
    final isLocal =
        uri?.host == 'localhost' ||
        uri?.host == '127.0.0.1' ||
        uri?.host == '::1';
    final validScheme =
        uri?.scheme == 'https' || (isLocal && uri?.scheme == 'http');
    if (uri == null || uri.host.isEmpty || !validScheme) {
      throw const SupabaseConfigurationException('invalid_supabase_url');
    }
    if (publishableKey.isEmpty) {
      throw const SupabaseConfigurationException(
        'missing_supabase_publishable_key',
      );
    }
    if (publishableKey.startsWith('sb_secret_') ||
        _legacyJwtRole(publishableKey) == 'service_role') {
      throw const SupabaseConfigurationException(
        'server_secret_must_not_enter_flutter',
      );
    }
  }

  String? _legacyJwtRole(String key) {
    final parts = key.split('.');
    if (parts.length != 3) {
      return null;
    }
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      return payload is Map<String, dynamic>
          ? payload['role'] as String?
          : null;
    } on Object {
      return null;
    }
  }
}

final class SupabaseConfigurationException implements Exception {
  const SupabaseConfigurationException(this.code);

  final String code;

  @override
  String toString() => 'SupabaseConfigurationException($code)';
}

final class _InvalidIdentitySessionFactory implements IdentitySessionFactory {
  const _InvalidIdentitySessionFactory(this.error);

  final SupabaseConfigurationException error;

  @override
  Future<IdentitySession> open() => Future.error(error);
}

/// Supabase SDK 只存在于这个 Adapter；业务模块只看 [IdentitySession]。
final class SupabaseIdentitySessionFactory implements IdentitySessionFactory {
  SupabaseIdentitySessionFactory({
    required this.configuration,
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final SupabaseClientConfiguration configuration;
  final FlutterSecureStorage _secureStorage;

  @override
  Future<IdentitySession> open() async {
    WidgetsFlutterBinding.ensureInitialized();
    final localStorage = SecureSupabaseLocalStorage(
      _secureStorage,
      'tongxingzhe.supabase.session',
    );
    final pkceStorage = SecureSupabasePkceStorage(
      _secureStorage,
      'tongxingzhe.supabase.pkce.',
    );
    final supabase = await Supabase.initialize(
      url: configuration.url,
      publishableKey: configuration.publishableKey,
      authOptions: FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        autoRefreshToken: true,
        localStorage: localStorage,
        pkceAsyncStorage: pkceStorage,
      ),
    );
    return SupabaseIdentitySession(
      client: supabase.client,
      disposeSupabase: supabase.dispose,
    );
  }
}

final class SupabaseIdentitySession implements IdentitySession {
  SupabaseIdentitySession({
    required SupabaseClient client,
    required this._disposeSupabase,
  }) : _client = client,
       _current = _snapshotFromSession(client.auth.currentSession) {
    _subscription = _client.auth.onAuthStateChange.listen(
      _onProviderState,
      onError: _onProviderStreamError,
    );
  }

  final SupabaseClient _client;
  final Future<void> Function() _disposeSupabase;
  final StreamController<IdentitySnapshot> _changes =
      StreamController<IdentitySnapshot>.broadcast();
  late final StreamSubscription<AuthState> _subscription;
  IdentitySnapshot _current;
  bool _closed = false;

  @override
  IdentitySnapshot get current => _current;

  @override
  Stream<IdentitySnapshot> get changes => _changes.stream;

  @override
  Future<IdentityResult<IdentitySnapshot>> restore() {
    return _guard(() async {
      final session = _client.auth.currentSession;
      if (session == null) {
        return _setCurrent(const IdentitySnapshot.signedOut());
      }
      if (session.isExpired) {
        final response = await _client.auth.refreshSession();
        return _requireSession(response.session);
      }
      return _setCurrent(_snapshotFromSession(session));
    });
  }

  @override
  Future<IdentityResult<IdentitySnapshot>> signUp({
    required String email,
    required String password,
  }) {
    return _guard(() async {
      final response = await _client.auth.signUp(
        email: _normalizeEmail(email),
        password: password,
      );
      final session = response.session;
      if (session != null) {
        return _setCurrent(_snapshotFromSession(session));
      }
      final user = response.user;
      return _setCurrent(
        IdentitySnapshot(
          stage: IdentityStage.awaitingEmailConfirmation,
          principal: user == null
              ? null
              : IdentityPrincipal(externalSubject: user.id, email: user.email),
        ),
      );
    });
  }

  @override
  Future<IdentityResult<IdentitySnapshot>> confirmSignUpOtp({
    required String email,
    required String otp,
  }) {
    return _guard(() async {
      final response = await _client.auth.verifyOTP(
        email: _normalizeEmail(email),
        token: otp.trim(),
        type: OtpType.signup,
      );
      return _requireSession(response.session);
    });
  }

  @override
  Future<IdentityResult<IdentitySnapshot>> signIn({
    required String email,
    required String password,
  }) {
    return _guard(() async {
      final response = await _client.auth.signInWithPassword(
        email: _normalizeEmail(email),
        password: password,
      );
      return _requireSession(response.session);
    });
  }

  @override
  Future<IdentityResult<IdentitySnapshot>> requestPasswordRecovery({
    required String email,
  }) {
    return _guard(() async {
      await _client.auth.resetPasswordForEmail(_normalizeEmail(email));
      return _setCurrent(
        const IdentitySnapshot(stage: IdentityStage.recoveryCodeSent),
      );
    });
  }

  @override
  Future<IdentityResult<IdentitySnapshot>> confirmPasswordRecoveryOtp({
    required String email,
    required String otp,
  }) {
    return _guard(() async {
      final response = await _client.auth.verifyOTP(
        email: _normalizeEmail(email),
        token: otp.trim(),
        type: OtpType.recovery,
      );
      final session = response.session;
      if (session == null) {
        throw AuthSessionMissingException();
      }
      return _setCurrent(
        _snapshotFromSession(
          session,
          stage: IdentityStage.changingRecoveredPassword,
        ),
      );
    });
  }

  @override
  Future<IdentityResult<IdentitySnapshot>> updateRecoveredPassword({
    required String newPassword,
  }) {
    return _guard(() async {
      if (_client.auth.currentSession == null) {
        throw AuthSessionMissingException();
      }
      await _client.auth.updateUser(UserAttributes(password: newPassword));
      return _requireSession(_client.auth.currentSession);
    });
  }

  @override
  Future<IdentityResult<IdentitySnapshot>> refresh() {
    return _guard(() async {
      final response = await _client.auth.refreshSession();
      return _requireSession(response.session);
    });
  }

  @override
  Future<IdentityResult<IdentitySnapshot>> signOut() {
    return _guard(() async {
      await _client.auth.signOut();
      return _setCurrent(const IdentitySnapshot.signedOut());
    });
  }

  @override
  Future<IdentityResult<IdentityAccessToken>> accessToken({
    bool forceRefresh = false,
  }) async {
    try {
      var session = _client.auth.currentSession;
      if (session == null) {
        throw AuthSessionMissingException();
      }
      if (forceRefresh || session.isExpired) {
        session = (await _client.auth.refreshSession()).session;
      }
      if (session == null) {
        throw AuthSessionMissingException();
      }
      return IdentitySuccess(
        IdentityAccessToken(
          value: session.accessToken,
          expiresAt: _expiresAt(session),
        ),
      );
    } on Object catch (error, stackTrace) {
      return IdentityRejected(_mapFailure(error, stackTrace));
    }
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _subscription.cancel();
    await _changes.close();
    await _disposeSupabase();
  }

  Future<IdentityResult<IdentitySnapshot>> _guard(
    Future<IdentitySnapshot> Function() operation,
  ) async {
    try {
      return IdentitySuccess(await operation());
    } on Object catch (error, stackTrace) {
      return IdentityRejected(_mapFailure(error, stackTrace));
    }
  }

  IdentitySnapshot _requireSession(Session? session) {
    if (session == null) {
      throw AuthSessionMissingException();
    }
    return _setCurrent(_snapshotFromSession(session));
  }

  IdentitySnapshot _setCurrent(IdentitySnapshot snapshot) {
    _current = snapshot;
    if (!_changes.isClosed) {
      _changes.add(snapshot);
    }
    return snapshot;
  }

  void _onProviderState(AuthState state) {
    final snapshot = switch (state.event) {
      AuthChangeEvent.passwordRecovery => _snapshotFromSession(
        state.session,
        stage: IdentityStage.changingRecoveredPassword,
      ),
      AuthChangeEvent.signedOut => const IdentitySnapshot.signedOut(),
      _ => _snapshotFromSession(state.session),
    };
    _setCurrent(snapshot);
  }

  void _onProviderStreamError(Object error, StackTrace stackTrace) {
    // Stream 错误不伪造成 signed-out；下一次显式操作会返回稳定 failure。
  }

  static IdentitySnapshot _snapshotFromSession(
    Session? session, {
    IdentityStage stage = IdentityStage.signedIn,
  }) {
    if (session == null) {
      return const IdentitySnapshot.signedOut();
    }
    return IdentitySnapshot(
      stage: stage,
      principal: IdentityPrincipal(
        externalSubject: session.user.id,
        email: session.user.email,
      ),
      expiresAt: _expiresAt(session),
    );
  }

  static DateTime? _expiresAt(Session session) {
    final seconds = session.expiresAt;
    return seconds == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  }

  static String _normalizeEmail(String email) => email.trim().toLowerCase();

  static IdentityFailure _mapFailure(Object error, StackTrace stackTrace) {
    if (error is AuthRetryableFetchException) {
      // SDK 同时用这个类型表示“未收到 HTTP response”和“服务器 5xx”。
      // 只有前者是设备网络不可用；后者必须保留为认证商拒绝证据。
      final statusCode = error.statusCode;
      return IdentityFailure(
        code: statusCode == null
            ? IdentityFailureCode.networkUnavailable
            : IdentityFailureCode.providerRejected,
        providerCode: statusCode == null ? null : 'http_$statusCode',
        cause: error,
        stackTrace: stackTrace,
      );
    }
    if (error is! AuthException) {
      return IdentityFailure(
        code: IdentityFailureCode.unknown,
        cause: error,
        stackTrace: stackTrace,
      );
    }

    final code = error.code;
    final stableCode = switch (code) {
      'invalid_credentials' => IdentityFailureCode.invalidCredentials,
      'email_not_confirmed' => IdentityFailureCode.emailNotConfirmed,
      'otp_expired' ||
      'flow_state_expired' ||
      'bad_code_verifier' => IdentityFailureCode.otpInvalidOrExpired,
      'email_exists' ||
      'user_already_exists' => IdentityFailureCode.emailAlreadyRegistered,
      'weak_password' => IdentityFailureCode.weakPassword,
      'over_request_rate_limit' ||
      'over_email_send_rate_limit' ||
      'over_sms_send_rate_limit' => IdentityFailureCode.rateLimited,
      'request_timeout' => IdentityFailureCode.networkUnavailable,
      'session_not_found' ||
      'session_expired' ||
      'session_missing' => IdentityFailureCode.sessionMissing,
      _ when error is AuthSessionMissingException =>
        IdentityFailureCode.sessionMissing,
      _ => IdentityFailureCode.providerRejected,
    };
    return IdentityFailure(
      code: stableCode,
      providerCode: code,
      cause: error,
      stackTrace: stackTrace,
    );
  }
}

/// Supabase 默认 SharedPreferences 不满足 native session 的安全存储要求。
/// 这个实现把完整 session JSON 交给各平台的安全存储 Adapter。
final class SecureSupabaseLocalStorage extends LocalStorage {
  const SecureSupabaseLocalStorage(this._storage, this._key);

  final FlutterSecureStorage _storage;
  final String _key;

  @override
  Future<void> initialize() async {
    WidgetsFlutterBinding.ensureInitialized();
  }

  @override
  Future<String?> accessToken() => _storage.read(key: _key);

  @override
  Future<bool> hasAccessToken() => _storage.containsKey(key: _key);

  @override
  Future<void> persistSession(String persistSessionString) {
    return _storage.write(key: _key, value: persistSessionString);
  }

  @override
  Future<void> removePersistedSession() => _storage.delete(key: _key);
}

/// PKCE verifier 和 session 一样属于短期秘密，不落入 SharedPreferences。
final class SecureSupabasePkceStorage extends GotrueAsyncStorage {
  const SecureSupabasePkceStorage(this._storage, this._keyPrefix);

  final FlutterSecureStorage _storage;
  final String _keyPrefix;

  String _namespaced(String key) => '$_keyPrefix$key';

  @override
  Future<String?> getItem({required String key}) {
    return _storage.read(key: _namespaced(key));
  }

  @override
  Future<void> removeItem({required String key}) {
    return _storage.delete(key: _namespaced(key));
  }

  @override
  Future<void> setItem({required String key, required String value}) {
    return _storage.write(key: _namespaced(key), value: value);
  }
}
