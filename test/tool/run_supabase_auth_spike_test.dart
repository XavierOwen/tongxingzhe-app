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

  test('signup_request 缺少一次性确认时在 Flutter 启动前拒绝', () async {
    final run = await _runNativeRunner(
      config: _signupConfig(email: 'auth-spike-run-01@example.test'),
    );

    expect(run.result.exitCode, isNot(0));
    expect(
      run.result.stderr,
      contains('AUTH_SPIKE_SIGNUP_CONFIRM_NEW_SYNTHETIC_ACCOUNT'),
    );
    expect(File(run.flutterMarkerPath).existsSync(), isFalse);
  });

  test('signup_request 的确认字段不是 true 时拒绝', () async {
    final run = await _runNativeRunner(
      config: _signupConfig(
        email: 'auth-spike-run-02@example.test',
        acknowledge: false,
      ),
    );

    expect(run.result.exitCode, isNot(0));
    expect(
      run.result.stderr,
      contains('AUTH_SPIKE_SIGNUP_CONFIRM_NEW_SYNTHETIC_ACCOUNT=true'),
    );
    expect(File(run.flutterMarkerPath).existsSync(), isFalse);
  });

  test('signup_request 拒绝普通地址和示例占位地址，且不接触网络', () async {
    for (final email in <String>[
      'person@example.com',
      'synthetic-test-account@example.test',
    ]) {
      final run = await _runNativeRunner(
        config: _signupConfig(email: email, acknowledge: true),
      );

      expect(run.result.exitCode, isNot(0), reason: email);
      expect(
        run.result.stderr,
        contains('synthetic-test email'),
        reason: email,
      );
      expect(File(run.flutterMarkerPath).existsSync(), isFalse, reason: email);
    }
  });

  test('signup_request 在没有 python3 时接受带 auth-spike 标记的合成地址', () async {
    final run = await _runNativeRunner(
      config: _signupConfig(
        email: 'auth-spike-run-20260813@example.test',
        acknowledge: true,
      ),
    );

    expect(run.result.exitCode, 0, reason: '${run.result.stderr}');
    expect(File(run.flutterMarkerPath).existsSync(), isTrue);
  });

  test('session 模式在没有 python3 时继续接受已有的普通测试账号', () async {
    final run = await _runNativeRunner(
      config: '''{
  "AUTH_SPIKE_MODE": "session",
  "AUTH_SPIKE_EMAIL": "confirmed-account@example.com",
  "AUTH_SPIKE_PASSWORD": "confirmed-password"
}
''',
    );

    expect(run.result.exitCode, 0, reason: '${run.result.stderr}');
    expect(File(run.flutterMarkerPath).existsSync(), isTrue);
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

String _signupConfig({required String email, bool? acknowledge}) {
  final confirmation = acknowledge == null
      ? ''
      : ',\n  "AUTH_SPIKE_SIGNUP_CONFIRM_NEW_SYNTHETIC_ACCOUNT": "${acknowledge ? 'true' : 'false'}"';
  return '''{
  "AUTH_SPIKE_MODE": "signup_request",
  "AUTH_SPIKE_EMAIL": "$email",
  "AUTH_SPIKE_PASSWORD": "synthetic-password"$confirmation
}
''';
}

Future<({ProcessResult result, String flutterMarkerPath})> _runNativeRunner({
  required String config,
}) async {
  final temporaryDirectory = await Directory.systemTemp.createTemp(
    'tongxingzhe-auth-spike-signup-',
  );
  addTearDown(() => temporaryDirectory.delete(recursive: true));

  final fakeBinDirectory = Directory('${temporaryDirectory.path}/fake-bin');
  final secretsDirectory = Directory('${temporaryDirectory.path}/secrets');
  await fakeBinDirectory.create();
  await secretsDirectory.create();

  final flutterMarker = File('${temporaryDirectory.path}/flutter-started.txt');
  await _writeExecutable(
    '${fakeBinDirectory.path}/flutter',
    '#!/usr/bin/env bash\nprintf "started" > "\${FLUTTER_MARKER}"\n',
  );
  // 若 runner 误回退到 Python，所有 signup/session 场景都应立即失败。
  await _writeExecutable(
    '${fakeBinDirectory.path}/python3',
    '#!/usr/bin/env bash\nprintf "python3 must not be called" >&2\nexit 97\n',
  );

  final configFile = File('${secretsDirectory.path}/config.json');
  await configFile.writeAsString(config);

  final result = await Process.run(
    'bash',
    const ['tool/run_supabase_auth_spike.sh'],
    workingDirectory: Directory.current.path,
    environment: {
      ...Platform.environment,
      'PATH': '${fakeBinDirectory.path}:${Platform.environment['PATH']}',
      'AUTH_SPIKE_DEVICE': 'physical-ios-device',
      'AUTH_SPIKE_CONFIG': configFile.path,
      'FLUTTER_MARKER': flutterMarker.path,
    },
  );

  return (result: result, flutterMarkerPath: flutterMarker.path);
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
