import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../l10n/app_strings.dart';

/// 正式认证 UI 将在 Slice 1 通过 IdentitySession 实现。
///
/// 本页故意不提供 legacy username/password 字段；即使认证配置缺失，也不会
/// 回退到 MD5 或默认演示账号。
final class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final text = AppStrings(controller.localeCode);
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
