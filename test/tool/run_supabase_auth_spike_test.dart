import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Web 认证探针只让 ChromeDriver 启动一个浏览器', () async {
    final captured = await _captureFlutterArguments();
    final arguments = captured.arguments;
    final deviceFlagIndex = arguments.indexOf('--device-id');
    expect(deviceFlagIndex, isNonNegative);
    expect(
      arguments[deviceFlagIndex + 1],
      'web-server',
      reason: 'chrome device 会额外启动普通 Chrome，再与 HeadlessChrome 重复执行测试。',
    );
  });

  test('Web 跨进程恢复固定 origin 与 Chrome profile', () async {
    final (:arguments, :profilePath) = await _captureFlutterArguments();
    // 跨浏览器进程恢复要求前后两次运行使用同一个 origin 与 Chrome profile。
    final webPortFlagIndex = arguments.indexOf('--web-port');
    expect(webPortFlagIndex, isNonNegative);
    expect(arguments[webPortFlagIndex + 1], '57321');
    expect(
      arguments,
      contains('--web-hostname=127.0.0.1'),
      reason: 'hostname 或 port 改变都会让 Web 安全存储落入另一个 origin。',
    );
    expect(
      arguments,
      contains('--web-browser-flag=--user-data-dir=$profilePath'),
      reason: '临时 Chrome profile 会随进程消失，不能证明重启后恢复。',
    );
  });

  test('原生真机探针结束后保留 App 以维持开发者信任', () async {
    final arguments = await _captureNativeFlutterArguments();

    expect(
      arguments,
      contains('--no-uninstall'),
      reason: 'flutter test 默认卸载唯一的开发 App；iOS 随后会撤销该开发者信任。',
    );
  });
}

Future<({List<String> arguments, String profilePath})>
_captureFlutterArguments() async {
  // 通过公开 shell 入口验证真实命令组装，不调用脚本私有实现。
  final temporaryDirectory = await Directory.systemTemp.createTemp(
    'tongxingzhe-auth-spike-',
  );
  addTearDown(() => temporaryDirectory.delete(recursive: true));

  final fakeBinDirectory = Directory('${temporaryDirectory.path}/fake-bin');
  final secretsDirectory = Directory('${temporaryDirectory.path}/secrets');
  await fakeBinDirectory.create();
  await secretsDirectory.create();

  // curl 成功表示 4444 端口已有 driver，因此测试不启动真实 Chrome。
  await _writeExecutable(
    '${fakeBinDirectory.path}/curl',
    '#!/usr/bin/env bash\nexit 0\n',
  );
  await _writeExecutable(
    '${fakeBinDirectory.path}/chromedriver',
    '#!/usr/bin/env bash\nexit 0\n',
  );

  // fake Flutter 只记录 runner 传入的参数，不读取测试密钥。
  final capturedArguments = File(
    '${temporaryDirectory.path}/flutter-arguments.txt',
  );
  final webProfileDirectory = Directory(
    '${temporaryDirectory.path}/web-profile',
  );
  await _writeExecutable(
    '${fakeBinDirectory.path}/flutter',
    '#!/usr/bin/env bash\nprintf "%s\\n" "\$@" > "\${CAPTURE_PATH}"\n',
  );

  final configFile = File('${secretsDirectory.path}/config.json');
  await configFile.writeAsString('{}\n');

  final result = await Process.run(
    'bash',
    const ['tool/run_supabase_auth_spike.sh'],
    workingDirectory: Directory.current.path,
    environment: {
      ...Platform.environment,
      'PATH': '${fakeBinDirectory.path}:${Platform.environment['PATH']}',
      'AUTH_SPIKE_DEVICE': 'chrome',
      'AUTH_SPIKE_CONFIG': configFile.path,
      // 固定测试值，使断言不依赖开发机端口或仓库中的 .dart_tool 路径。
      'AUTH_SPIKE_WEB_PORT': '57321',
      'AUTH_SPIKE_WEB_PROFILE_DIR': webProfileDirectory.path,
      'CAPTURE_PATH': capturedArguments.path,
    },
  );

  expect(result.exitCode, 0, reason: '${result.stderr}');
  return (
    arguments: await capturedArguments.readAsLines(),
    profilePath: webProfileDirectory.path,
  );
}

Future<void> _writeExecutable(String path, String contents) async {
  final file = File(path);
  await file.writeAsString(contents);
  final result = await Process.run('chmod', ['+x', file.path]);
  if (result.exitCode != 0) {
    throw StateError('chmod 失败：${result.stderr}');
  }
}

Future<List<String>> _captureNativeFlutterArguments() async {
  // 原生分支同样通过公开 shell 入口验证，不实际构建或连接设备。
  final temporaryDirectory = await Directory.systemTemp.createTemp(
    'tongxingzhe-auth-spike-native-',
  );
  addTearDown(() => temporaryDirectory.delete(recursive: true));

  final fakeBinDirectory = Directory('${temporaryDirectory.path}/fake-bin');
  final secretsDirectory = Directory('${temporaryDirectory.path}/secrets');
  await fakeBinDirectory.create();
  await secretsDirectory.create();

  final capturedArguments = File(
    '${temporaryDirectory.path}/flutter-arguments.txt',
  );
  await _writeExecutable(
    '${fakeBinDirectory.path}/flutter',
    '#!/usr/bin/env bash\nprintf "%s\\n" "\$@" > "\${CAPTURE_PATH}"\n',
  );

  final configFile = File('${secretsDirectory.path}/config.json');
  await configFile.writeAsString('{}\n');

  final result = await Process.run(
    'bash',
    const ['tool/run_supabase_auth_spike.sh'],
    workingDirectory: Directory.current.path,
    environment: {
      ...Platform.environment,
      'PATH': '${fakeBinDirectory.path}:${Platform.environment['PATH']}',
      'AUTH_SPIKE_DEVICE': 'physical-ios-device',
      'AUTH_SPIKE_CONFIG': configFile.path,
      'CAPTURE_PATH': capturedArguments.path,
    },
  );

  expect(result.exitCode, 0, reason: '${result.stderr}');
  return capturedArguments.readAsLines();
}
