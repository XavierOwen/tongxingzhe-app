import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final path in {
    'macos/Runner/DebugProfile.entitlements',
    'macos/Runner/Release.entitlements',
  }) {
    test('$path 允许连接 Supabase HTTPS 服务', () {
      final contents = File(path).readAsStringSync();

      expect(
        _hasBooleanEntitlement(contents, 'com.apple.security.network.client'),
        isTrue,
        reason: '沙箱 App 必须允许连接 Supabase HTTPS 服务。',
      );
    });

    test('$path 允许使用 Keychain 安全存储', () {
      final contents = File(path).readAsStringSync();

      expect(
        _hasEmptyArrayEntitlement(contents, 'keychain-access-groups'),
        isTrue,
        reason: 'flutter_secure_storage 需要 Keychain Sharing capability。',
      );
    });
  }
}

bool _hasBooleanEntitlement(String contents, String key) {
  return RegExp(
    '<key>${RegExp.escape(key)}</key>\\s*<true\\s*/>',
  ).hasMatch(contents);
}

bool _hasEmptyArrayEntitlement(String contents, String key) {
  return RegExp(
    '<key>${RegExp.escape(key)}</key>\\s*<array\\s*/>',
  ).hasMatch(contents);
}
