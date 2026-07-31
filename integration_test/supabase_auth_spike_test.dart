import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/identity/supabase/supabase_identity_session.dart';

const _mode = String.fromEnvironment('AUTH_SPIKE_MODE');
const _email = String.fromEnvironment('AUTH_SPIKE_EMAIL');
const _password = String.fromEnvironment('AUTH_SPIKE_PASSWORD');
const _otp = String.fromEnvironment('AUTH_SPIKE_OTP');
const _newPassword = String.fromEnvironment('AUTH_SPIKE_NEW_PASSWORD');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Supabase Auth 真实设备合同探针', (tester) async {
    _requireConfiguration();
    final factory = productionIdentitySessionFactory();
    var session = await factory.open();

    try {
      switch (_mode) {
        case 'session':
          await _verifySessionLifecycle(session, factory);
          // lifecycle 内已经关闭第一个 session，并接管第二个 session 的释放。
          session = const UnavailableIdentitySession();
          break;
        case 'signup_request':
          final result = await session.signUp(
            email: _email,
            password: _password,
          );
          expect(
            _success(result).stage,
            IdentityStage.awaitingEmailConfirmation,
          );
          break;
        case 'signup_confirm':
          final result = await session.confirmSignUpOtp(
            email: _email,
            otp: _otp,
          );
          expect(_success(result).stage, IdentityStage.signedIn);
          _success(await session.signOut());
          break;
        case 'recovery_request':
          final result = await session.requestPasswordRecovery(email: _email);
          expect(_success(result).stage, IdentityStage.recoveryCodeSent);
          break;
        case 'recovery_confirm':
          final confirmed = await session.confirmPasswordRecoveryOtp(
            email: _email,
            otp: _otp,
          );
          expect(
            _success(confirmed).stage,
            IdentityStage.changingRecoveredPassword,
          );
          final updated = await session.updateRecoveredPassword(
            newPassword: _newPassword,
          );
          expect(_success(updated).stage, IdentityStage.signedIn);
          _success(await session.signOut());
          break;
        default:
          fail('未知 AUTH_SPIKE_MODE：$_mode');
      }
    } finally {
      await session.close();
    }
  });
}

Future<void> _verifySessionLifecycle(
  IdentitySession firstSession,
  IdentitySessionFactory factory,
) async {
  final signedIn = await firstSession.signIn(
    email: _email,
    password: _password,
  );
  expect(_success(signedIn).stage, IdentityStage.signedIn);

  final refreshed = await firstSession.refresh();
  expect(_success(refreshed).stage, IdentityStage.signedIn);

  final token = _success(await firstSession.accessToken(forceRefresh: true));
  expect(token.value, isNotEmpty);
  await firstSession.close();

  final restoredSession = await factory.open();
  try {
    final restored = await restoredSession.restore();
    expect(_success(restored).stage, IdentityStage.signedIn);
    expect(
      _success(await restoredSession.signOut()).stage,
      IdentityStage.signedOut,
    );
  } finally {
    await restoredSession.close();
  }
}

T _success<T>(IdentityResult<T> result) {
  return switch (result) {
    IdentitySuccess<T>(:final value) => value,
    IdentityRejected<T>(:final failure) => fail(
      'Identity 操作失败：${failure.code.name}; '
      'provider=${failure.providerCode ?? 'none'}',
    ),
  };
}

void _requireConfiguration() {
  const url = String.fromEnvironment(supabaseUrlEnvironmentName);
  const publishableKey = String.fromEnvironment(
    supabasePublishableKeyEnvironmentName,
  );
  if (url.isEmpty ||
      publishableKey.isEmpty ||
      _mode.isEmpty ||
      _email.isEmpty) {
    fail('缺少 Supabase spike 配置；请通过 --dart-define-from-file 提供。');
  }
  if ({'session', 'signup_request'}.contains(_mode) && _password.isEmpty) {
    fail('$_mode 需要 AUTH_SPIKE_PASSWORD。');
  }
  if ({'signup_confirm', 'recovery_confirm'}.contains(_mode) && _otp.isEmpty) {
    fail('$_mode 需要 AUTH_SPIKE_OTP。');
  }
  if (_mode == 'recovery_confirm' && _newPassword.isEmpty) {
    fail('recovery_confirm 需要 AUTH_SPIKE_NEW_PASSWORD。');
  }
}
