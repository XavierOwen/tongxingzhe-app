import 'package:flutter/material.dart';

import 'app/tongxingzhe_app.dart';
import 'legacy_demo/legacy_auth_screen.dart';
import 'legacy_demo/legacy_demo_dependencies.dart';

/// 显式启动 legacy 原型，供学习现有 UI 和回归测试使用。
///
/// 正式构建必须使用 `lib/main.dart`，不得把这个入口打包为 production。
void main() {
  runApp(
    TongxingzheApp(
      dependencies: LegacyDemoDependencies.create(),
      signedOutScreenBuilder: (context, controller) {
        return LegacyAuthScreen(controller: controller);
      },
    ),
  );
}
