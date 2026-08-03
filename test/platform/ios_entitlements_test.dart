import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const entitlementPaths = {
    'ios/Runner/DebugProfile.entitlements',
    'ios/Runner/Release.entitlements',
  };

  for (final path in entitlementPaths) {
    test('$path 允许使用 Keychain 安全存储', () {
      final file = File(path);

      expect(
        file.existsSync(),
        isTrue,
        reason: 'iOS Runner 必须声明 Keychain Sharing entitlement。',
      );
      expect(
        _hasEmptyArrayEntitlement(
          file.readAsStringSync(),
          'keychain-access-groups',
        ),
        isTrue,
        reason: 'flutter_secure_storage 需要 Keychain Sharing capability。',
      );
    });
  }

  test('Runner 的三种 build configuration 使用对应 entitlement', () {
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();

    expect(
      _occurrenceCount(
        project,
        'CODE_SIGN_ENTITLEMENTS = Runner/DebugProfile.entitlements;',
      ),
      2,
      reason: 'Debug 与 Profile 必须使用可访问 Keychain 的 entitlement。',
    );
    expect(
      _occurrenceCount(
        project,
        'CODE_SIGN_ENTITLEMENTS = Runner/Release.entitlements;',
      ),
      1,
      reason: 'Release 必须使用与发布签名一致的 entitlement。',
    );
  });
}

bool _hasEmptyArrayEntitlement(String contents, String key) {
  return RegExp(
    '<key>${RegExp.escape(key)}</key>\\s*<array\\s*/>',
  ).hasMatch(contents);
}

int _occurrenceCount(String contents, String pattern) {
  return pattern.allMatches(contents).length;
}
