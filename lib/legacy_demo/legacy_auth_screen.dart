import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../l10n/app_strings.dart';

enum _AuthMode { login, register, forgot }

class LegacyAuthScreen extends StatefulWidget {
  const LegacyAuthScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<LegacyAuthScreen> createState() => _LegacyAuthScreenState();
}

class _LegacyAuthScreenState extends State<LegacyAuthScreen> {
  _AuthMode _mode = _AuthMode.login;
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _cityController = TextEditingController(text: 'Chicago, IL');
  bool _busy = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _displayNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = AppStrings(widget.controller.localeCode);
    final title = switch (_mode) {
      _AuthMode.login => text.t('login'),
      _AuthMode.register => text.t('register'),
      _AuthMode.forgot => text.t('forgotPassword'),
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(text.t('appTitle')),
        actions: [
          TextButton(
            onPressed: () {
              widget.controller.setLocale(
                widget.controller.localeCode == 'zh' ? 'en' : 'zh',
              );
            },
            child: Text(widget.controller.localeCode == 'zh' ? 'EN' : '中'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 20),
                      if (_mode != _AuthMode.forgot) ..._loginFields(text),
                      if (_mode == _AuthMode.register) ..._registerFields(text),
                      if (_mode == _AuthMode.forgot) ..._forgotFields(text),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _busy ? null : () => _submit(text),
                        child: _busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(title),
                      ),
                      const SizedBox(height: 8),
                      _modeSwitcher(text),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _DemoCredentialBar(
                busy: _busy,
                onLogin: _loginDemoUser,
                text: text,
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _loginFields(AppStrings text) {
    return [
      TextField(
        controller: _usernameController,
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          labelText: text.t('username'),
          prefixIcon: const Icon(Icons.person_outline),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _passwordController,
        obscureText: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _busy ? null : _submit(text),
        decoration: InputDecoration(
          labelText: text.t('password'),
          prefixIcon: const Icon(Icons.lock_outline),
        ),
      ),
    ];
  }

  List<Widget> _registerFields(AppStrings text) {
    return [
      const SizedBox(height: 12),
      TextField(
        controller: _confirmPasswordController,
        obscureText: true,
        decoration: InputDecoration(
          labelText: text.t('confirmPassword'),
          prefixIcon: const Icon(Icons.lock_reset_outlined),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _displayNameController,
        decoration: InputDecoration(
          labelText: text.t('displayName'),
          prefixIcon: const Icon(Icons.badge_outlined),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _emailController,
        keyboardType: TextInputType.emailAddress,
        decoration: InputDecoration(
          labelText: text.t('email'),
          prefixIcon: const Icon(Icons.mail_outline),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _phoneController,
        keyboardType: TextInputType.phone,
        decoration: InputDecoration(
          labelText: text.t('phone'),
          prefixIcon: const Icon(Icons.phone_outlined),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _cityController,
        decoration: InputDecoration(
          labelText: text.t('city'),
          prefixIcon: const Icon(Icons.location_city_outlined),
        ),
      ),
    ];
  }

  List<Widget> _forgotFields(AppStrings text) {
    return [
      TextField(
        controller: _displayNameController,
        decoration: InputDecoration(
          labelText: text.t('displayName'),
          prefixIcon: const Icon(Icons.badge_outlined),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _emailController,
        keyboardType: TextInputType.emailAddress,
        decoration: InputDecoration(
          labelText: text.t('email'),
          prefixIcon: const Icon(Icons.mail_outline),
        ),
      ),
    ];
  }

  Widget _modeSwitcher(AppStrings text) {
    Widget modeButton(_AuthMode mode, String labelKey) {
      return TextButton(
        onPressed: () => setState(() => _mode = mode),
        child: Text(text.t(labelKey)),
      );
    }

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        // Only show destinations that change the screen. In login mode this
        // avoids a second "Login" button that looked like a broken submit.
        if (_mode != _AuthMode.login) modeButton(_AuthMode.login, 'login'),
        if (_mode != _AuthMode.register)
          modeButton(_AuthMode.register, 'register'),
        if (_mode != _AuthMode.forgot)
          modeButton(_AuthMode.forgot, 'forgotPassword'),
      ],
    );
  }

  Future<void> _submit(AppStrings text) async {
    if (_mode == _AuthMode.login &&
        (_usernameController.text.trim().isEmpty ||
            _passwordController.text.isEmpty)) {
      _showSnack(text.t('authMissingFields'));
      return;
    }

    setState(() => _busy = true);
    try {
      final result = switch (_mode) {
        _AuthMode.login => await widget.controller.login(
          _usernameController.text,
          _passwordController.text,
        ),
        _AuthMode.register => await _register(text),
        _AuthMode.forgot => await widget.controller.requestPasswordReset(
          displayName: _displayNameController.text,
          email: _emailController.text,
        ),
      };
      if (!mounted) {
        return;
      }
      if (result.temporaryPassword != null) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(text.t('temporaryPassword')),
            content: SelectableText(result.temporaryPassword!),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: Text(text.t('login')),
              ),
            ],
          ),
        );
        if (!mounted) {
          return;
        }
        setState(() => _mode = _AuthMode.login);
      }
      _showSnack(text.t(result.messageKey));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<dynamic> _register(AppStrings text) async {
    if (_passwordController.text != _confirmPasswordController.text) {
      return const _LocalAuthResult('passwordMismatch');
    }
    return widget.controller.registerUser(
      username: _usernameController.text,
      displayName: _displayNameController.text,
      email: _emailController.text,
      phone: _phoneController.text,
      city: _cityController.text,
      password: _passwordController.text,
    );
  }

  Future<void> _loginDemoUser(String username) async {
    final text = AppStrings(widget.controller.localeCode);
    setState(() {
      _busy = true;
      _mode = _AuthMode.login;
      _usernameController.text = username;
      _passwordController.text = username;
    });

    try {
      final result = await widget.controller.loginDemoAccount(username);
      if (!mounted) {
        return;
      }
      _showSnack(text.t(result.messageKey));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _LocalAuthResult {
  const _LocalAuthResult(this.messageKey);

  final bool success = false;
  final String messageKey;
  final String? temporaryPassword = null;
}

class _DemoCredentialBar extends StatelessWidget {
  const _DemoCredentialBar({
    required this.busy,
    required this.onLogin,
    required this.text,
  });

  final bool busy;
  final Future<void> Function(String username) onLogin;
  final AppStrings text;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          text.t('demoAccounts'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final username in const [
              'admin1',
              'admin2',
              'admin3',
              'user1',
              'user2',
            ])
              ActionChip(
                avatar: Icon(
                  username.startsWith('admin')
                      ? Icons.admin_panel_settings_outlined
                      : Icons.person_outline,
                ),
                label: Text(username),
                onPressed: busy ? null : () => onLogin(username),
              ),
          ],
        ),
      ],
    );
  }
}
