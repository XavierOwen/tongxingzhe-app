import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/identity/supabase/supabase_identity_session.dart';

import '../support/fake_identity_session.dart';

void main() {
  group('Supabase client configuration', () {
    test('拒绝把新格式 secret key 放进 Flutter', () {
      expect(
        () => SupabaseClientConfiguration(
          url: 'https://example.supabase.co',
          publishableKey: 'sb_secret_never_ship_this',
        ),
        throwsA(
          isA<SupabaseConfigurationException>().having(
            (error) => error.code,
            'code',
            'server_secret_must_not_enter_flutter',
          ),
        ),
      );
    });

    test('拒绝 legacy JWT service_role key', () {
      final header = _base64UrlJson({'alg': 'HS256', 'typ': 'JWT'});
      final payload = _base64UrlJson({'role': 'service_role'});

      expect(
        () => SupabaseClientConfiguration(
          url: 'https://example.supabase.co',
          publishableKey: '$header.$payload.synthetic-signature',
        ),
        throwsA(isA<SupabaseConfigurationException>()),
      );
    });

    test('允许 HTTPS publishable key 与本地 CLI HTTP', () {
      expect(
        SupabaseClientConfiguration(
          url: 'https://example.supabase.co',
          publishableKey: 'sb_publishable_synthetic',
        ).url,
        'https://example.supabase.co',
      );
      expect(
        SupabaseClientConfiguration(
          url: 'http://127.0.0.1:54321',
          publishableKey: 'synthetic-anon-key',
        ).url,
        'http://127.0.0.1:54321',
      );
    });
  });

  test('test-only Identity fake 可制造完整恢复流程和稳定失败', () async {
    final identity = FakeIdentitySession();

    final signUp = await identity.signUp(
      email: ' Learner@Example.Test ',
      password: 'not-recorded',
    );
    expect(
      (signUp as IdentitySuccess<IdentitySnapshot>).value.stage,
      IdentityStage.awaitingEmailConfirmation,
    );

    final confirmed = await identity.confirmSignUpOtp(
      email: 'Learner@Example.Test',
      otp: '123456',
    );
    expect(
      (confirmed as IdentitySuccess<IdentitySnapshot>).value.principal?.email,
      'learner@example.test',
    );

    identity.rejectNextWith = const IdentityFailure(
      code: IdentityFailureCode.networkUnavailable,
    );
    final refresh = await identity.refresh();
    expect(
      (refresh as IdentityRejected<IdentitySnapshot>).failure.code,
      IdentityFailureCode.networkUnavailable,
    );

    await identity.close();
  });
}

String _base64UrlJson(Map<String, Object?> value) {
  return base64UrlEncode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
}
