/// Flutter 业务模块看到的身份状态，不包含 Supabase／Cognito SDK 类型。
enum IdentityStage {
  /// 本地开发没有提供认证配置；不是“登录失败”。
  unavailable,

  signedOut,
  awaitingEmailConfirmation,
  recoveryCodeSent,
  changingRecoveredPassword,
  signedIn,
}

/// 已通过外部认证商确认的身份摘要。
///
/// [externalSubject] 是外部 token 的 subject；Backend 会把它映射为自己的
/// `app_user_id`。Flutter 不使用 email 或 subject 推导权限。
final class IdentityPrincipal {
  const IdentityPrincipal({required this.externalSubject, required this.email});

  final String externalSubject;
  final String? email;
}

/// UI 可观察的稳定身份快照；access token 不进入 ViewState。
final class IdentitySnapshot {
  const IdentitySnapshot({required this.stage, this.principal, this.expiresAt});

  const IdentitySnapshot.unavailable() : this(stage: IdentityStage.unavailable);

  const IdentitySnapshot.signedOut() : this(stage: IdentityStage.signedOut);

  final IdentityStage stage;
  final IdentityPrincipal? principal;

  /// UTC token 过期时间；`null` 表示当前没有 session 或 provider 未提供。
  final DateTime? expiresAt;

  bool get isAuthenticated => stage == IdentityStage.signedIn;
}

/// App 自己拥有的错误分类；界面和业务不得解析认证商的英文异常字符串。
enum IdentityFailureCode {
  notConfigured,
  invalidCredentials,
  emailNotConfirmed,
  otpInvalidOrExpired,
  emailAlreadyRegistered,
  weakPassword,
  rateLimited,
  networkUnavailable,
  sessionMissing,
  providerRejected,
  unknown,
}

final class IdentityFailure {
  const IdentityFailure({
    required this.code,
    this.providerCode,
    this.cause,
    this.stackTrace,
  });

  final IdentityFailureCode code;

  /// 只供日志与 spike 证据使用，不作为 UI 分支条件。
  final String? providerCode;
  final Object? cause;
  final StackTrace? stackTrace;
}

sealed class IdentityResult<T> {
  const IdentityResult();
}

final class IdentitySuccess<T> extends IdentityResult<T> {
  const IdentitySuccess(this.value);

  final T value;
}

final class IdentityRejected<T> extends IdentityResult<T> {
  const IdentityRejected(this.failure);

  final IdentityFailure failure;
}

/// 只交给 Backend HTTP Adapter 的 bearer token。
///
/// Widget、ViewModel 和领域规则不应读取或保存它。
final class IdentityAccessToken {
  const IdentityAccessToken({required this.value, required this.expiresAt});

  final String value;
  final DateTime? expiresAt;
}

/// 外部认证边界。
///
/// 输入 email 均在 Adapter 内 trim／normalize；密码和 OTP 只透传给认证商，
/// 不写入 Drift、日志或 analytics。所有方法可能执行网络请求并返回稳定错误。
abstract interface class IdentitySession {
  IdentitySnapshot get current;

  Stream<IdentitySnapshot> get changes;

  /// 从安全存储恢复 session；过期 session 会尝试刷新。
  Future<IdentityResult<IdentitySnapshot>> restore();

  /// 注册邮箱＋密码。开启邮箱确认时成功状态为 awaitingEmailConfirmation。
  Future<IdentityResult<IdentitySnapshot>> signUp({
    required String email,
    required String password,
  });

  /// 验证注册邮件中的 App 内 OTP；不会依赖业务层解析 deep link。
  Future<IdentityResult<IdentitySnapshot>> confirmSignUpOtp({
    required String email,
    required String otp,
  });

  Future<IdentityResult<IdentitySnapshot>> signIn({
    required String email,
    required String password,
  });

  /// 请求恢复 OTP。Supabase 项目邮件模板必须输出 `Token` 而非只输出链接。
  Future<IdentityResult<IdentitySnapshot>> requestPasswordRecovery({
    required String email,
  });

  /// 验证恢复 OTP；成功后处于 changingRecoveredPassword，随后必须改密码。
  Future<IdentityResult<IdentitySnapshot>> confirmPasswordRecoveryOtp({
    required String email,
    required String otp,
  });

  Future<IdentityResult<IdentitySnapshot>> updateRecoveredPassword({
    required String newPassword,
  });

  Future<IdentityResult<IdentitySnapshot>> refresh();

  Future<IdentityResult<IdentitySnapshot>> signOut();

  Future<IdentityResult<IdentityAccessToken>> accessToken({
    bool forceRefresh = false,
  });

  Future<void> close();
}

/// Composition root 使用的身份工厂；测试可在这里插入 test-only fake。
abstract interface class IdentitySessionFactory {
  Future<IdentitySession> open();
}

/// 没有配置真实认证时的显式状态，不冒充成功的 fake。
final class UnavailableIdentitySessionFactory
    implements IdentitySessionFactory {
  const UnavailableIdentitySessionFactory();

  @override
  Future<IdentitySession> open() async => const UnavailableIdentitySession();
}

final class UnavailableIdentitySession implements IdentitySession {
  const UnavailableIdentitySession();

  static const _snapshot = IdentitySnapshot.unavailable();
  static const _failure = IdentityFailure(
    code: IdentityFailureCode.notConfigured,
  );

  @override
  IdentitySnapshot get current => _snapshot;

  @override
  Stream<IdentitySnapshot> get changes => Stream.value(_snapshot);

  @override
  Future<IdentityResult<IdentityAccessToken>> accessToken({
    bool forceRefresh = false,
  }) async => const IdentityRejected(_failure);

  @override
  Future<void> close() async {}

  @override
  Future<IdentityResult<IdentitySnapshot>> confirmPasswordRecoveryOtp({
    required String email,
    required String otp,
  }) async => const IdentityRejected(_failure);

  @override
  Future<IdentityResult<IdentitySnapshot>> confirmSignUpOtp({
    required String email,
    required String otp,
  }) async => const IdentityRejected(_failure);

  @override
  Future<IdentityResult<IdentitySnapshot>> refresh() async =>
      const IdentityRejected(_failure);

  @override
  Future<IdentityResult<IdentitySnapshot>> requestPasswordRecovery({
    required String email,
  }) async => const IdentityRejected(_failure);

  @override
  Future<IdentityResult<IdentitySnapshot>> restore() async =>
      const IdentitySuccess(_snapshot);

  @override
  Future<IdentityResult<IdentitySnapshot>> signIn({
    required String email,
    required String password,
  }) async => const IdentityRejected(_failure);

  @override
  Future<IdentityResult<IdentitySnapshot>> signOut() async =>
      const IdentitySuccess(_snapshot);

  @override
  Future<IdentityResult<IdentitySnapshot>> signUp({
    required String email,
    required String password,
  }) async => const IdentityRejected(_failure);

  @override
  Future<IdentityResult<IdentitySnapshot>> updateRecoveredPassword({
    required String newPassword,
  }) async => const IdentityRejected(_failure);
}
