import 'package:flutter/material.dart';

import '../identity/identity_session.dart';
import '../l10n/app_strings.dart';

/// 正式邮箱认证入口。
///
/// 本页只调用 [IdentitySession]，不读取 Supabase 类型。认证结果经过
/// `AppSession` 解析可信业务上下文后，根 Widget 才允许进入正式主框架。
final class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.localeCode,
    required this.identitySession,
  });

  final String localeCode;
  final IdentitySession identitySession;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

final class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  IdentityFailureCode? _failureCode;
  var _busy = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = AppStrings(widget.localeCode);
    if (widget.identitySession.current.stage == IdentityStage.unavailable) {
      return _UnavailableAuthScreen(text: text);
    }

    return Scaffold(
      appBar: AppBar(title: Text(text.t('appTitle'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: AutofillGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.verified_user_outlined, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      text.t('authSignInTitle'),
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(text.t('authSignInBody'), textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    TextFormField(
                      key: const ValueKey('auth-email'),
                      controller: _emailController,
                      enabled: !_busy,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      decoration: InputDecoration(
                        labelText: text.t('email'),
                        prefixIcon: const Icon(Icons.email_outlined),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? text.t('authEmailRequired')
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('auth-password'),
                      controller: _passwordController,
                      enabled: !_busy,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: text.t('password'),
                        prefixIcon: const Icon(Icons.lock_outline),
                      ),
                      validator: (value) => value == null || value.isEmpty
                          ? text.t('authPasswordRequired')
                          : null,
                      onFieldSubmitted: (_) => _signIn(),
                    ),
                    if (_failureCode case final failure?) ...[
                      const SizedBox(height: 12),
                      Text(
                        _failureMessage(text, failure),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _signIn,
                      child: _busy
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(text.t('login')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _signIn() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _busy = true;
      _failureCode = null;
    });
    final result = await widget.identitySession.signIn(
      email: _emailController.text,
      password: _passwordController.text,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _failureCode = switch (result) {
        IdentitySuccess<IdentitySnapshot>() => null,
        IdentityRejected<IdentitySnapshot>(:final failure) => failure.code,
      };
    });
  }

  String _failureMessage(AppStrings text, IdentityFailureCode code) {
    return switch (code) {
      IdentityFailureCode.invalidCredentials => text.t('authInvalid'),
      IdentityFailureCode.emailNotConfirmed => text.t('authEmailNotConfirmed'),
      IdentityFailureCode.rateLimited => text.t('authRateLimited'),
      IdentityFailureCode.networkUnavailable => text.t(
        'authNetworkUnavailable',
      ),
      IdentityFailureCode.notConfigured => text.t('productionAuthPending'),
      _ => text.t('authProviderRejected'),
    };
  }
}

final class _UnavailableAuthScreen extends StatelessWidget {
  const _UnavailableAuthScreen({required this.text});

  final AppStrings text;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(text.t('appTitle'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.verified_user_outlined, size: 48),
                const SizedBox(height: 16),
                Text(
                  text.t('productionAuthPending'),
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  text.t('productionAuthPendingBody'),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
