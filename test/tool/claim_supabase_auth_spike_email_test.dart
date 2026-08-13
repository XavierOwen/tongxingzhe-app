import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('等价 project/email 只能占用一次，不同项目可分别占用', () async {
    final scenario = await _ClaimScenario.create();
    addTearDown(scenario.dispose);

    final first = await scenario.claim(
      project: 'HTTPS://PROJECT-ONE.SUPABASE.CO/',
      email: ' Auth-Spike-Canonical-01@Example.Test ',
    );
    final duplicate = await scenario.claim(
      project: 'https://project-one.supabase.co',
      email: 'auth-spike-canonical-01@example.test',
      extraEnvironment: const {
        'AUTH_SPIKE_FORCE_REUSE': 'true',
        'AUTH_SPIKE_SKIP_LEDGER': 'true',
        'AUTH_SPIKE_CLEAR_LEDGER': 'true',
      },
    );
    final otherProject = await scenario.claim(
      project: 'https://project-two.supabase.co',
      email: 'auth-spike-canonical-01@example.test',
    );
    final literalPlusTag = await scenario.claim(
      project: 'https://project-one.supabase.co',
      email: 'auth-spike-canonical-01+next@example.test',
    );

    expect(first.exitCode, 0, reason: '${first.stderr}');
    expect(duplicate.exitCode, isNot(0));
    expect(duplicate.stderr, contains('换新的合成测试邮箱'));
    expect(otherProject.exitCode, 0, reason: '${otherProject.stderr}');
    expect(literalPlusTag.exitCode, 0, reason: '${literalPlusTag.stderr}');

    final ledgerText = await scenario.ledger.readAsString();
    expect(ledgerText, isNot(contains('project-one')));
    expect(ledgerText, isNot(contains('canonical-01')));
    expect(ledgerText, isNot(contains('synthetic-password')));
    expect(ledgerText, isNot(contains('publishable-test-key')));
    expect('${first.stdout}${first.stderr}', isNot(contains('canonical-01')));
    expect(
      '${duplicate.stdout}${duplicate.stderr}',
      isNot(contains('canonical-01')),
    );
    final ledgerLines = const LineSplitter().convert(ledgerText);
    final header = jsonDecode(ledgerLines.first) as Map<String, dynamic>;
    expect(header['version'], 1);
    expect(ledgerLines.skip(1), hasLength(3));
  });

  test('截断、未知版本或无效记录时失败关闭且不改写 ledger', () async {
    for (final damaged in <String>[
      '',
      '{"type":"tongxingzhe_auth_spike_signup_ledger","version":1}\n'
          '{"digest":"truncated"',
      '{"type":"tongxingzhe_auth_spike_signup_ledger","version":2}\n'
          '{"digest":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",'
          '"claimedAtUtc":"2026-08-13T00:00:00.000Z"}\n',
      '{"type":"tongxingzhe_auth_spike_signup_ledger","version":1}\n'
          '{"digest":"not-a-digest","claimedAtUtc":"2026-08-13T00:00:00.000Z"}\n',
    ]) {
      final scenario = await _ClaimScenario.create();
      addTearDown(scenario.dispose);
      await scenario.ledger.writeAsString(damaged);

      final result = await scenario.claim(
        project: 'https://project-one.supabase.co',
        email: 'auth-spike-damaged-01@example.test',
      );

      expect(result.exitCode, isNot(0), reason: damaged);
      expect(result.stderr, contains('检查权限或损坏'));
      expect(await scenario.ledger.readAsString(), damaged);
    }
  });

  test('并发占用相同 project/email 时只有一个进程成功', () async {
    final scenario = await _ClaimScenario.create();
    addTearDown(scenario.dispose);
    final config = await scenario.writeConfig(
      project: 'https://project-one.supabase.co',
      email: 'auth-spike-concurrent-01@example.test',
    );

    final first = await scenario.startClaim(config);
    final second = await scenario.startClaim(config);
    final results = await Future.wait([_collect(first), _collect(second)]);

    expect(
      results.map((result) => result.exitCode).where((code) => code == 0),
      hasLength(1),
    );
    expect(
      results.map((result) => result.exitCode).where((code) => code != 0),
      hasLength(1),
    );
  });

  test('持锁进程终止后操作系统释放 ledger 锁', () async {
    final scenario = await _ClaimScenario.create();
    addTearDown(scenario.dispose);
    final initialClaim = await scenario.claim(
      project: 'https://project-one.supabase.co',
      email: 'auth-spike-before-lock-kill-01@example.test',
    );
    expect(initialClaim.exitCode, 0, reason: '${initialClaim.stderr}');
    final lockHolder = File('${scenario.directory.path}/hold_lock.dart');
    await lockHolder.writeAsString('''
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final file = File(arguments.single).openSync(mode: FileMode.append);
  file.lockSync(FileLock.exclusive);
  stdout.writeln('locked');
  await stdin.first;
}
''');
    final holder = await Process.start('dart', [
      lockHolder.path,
      scenario.ledger.path,
    ]);
    addTearDown(() {
      holder.kill();
    });
    final ready = await holder.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first
        .timeout(const Duration(seconds: 10));
    expect(ready, 'locked');
    expect(holder.kill(), isTrue);
    await holder.exitCode;

    final result = await scenario.claim(
      project: 'https://project-one.supabase.co',
      email: 'auth-spike-after-kill-01@example.test',
    );

    expect(result.exitCode, 0, reason: '${result.stderr}');
  });

  test('Windows Git Bash drive 路径可作为绝对 ledger override', () async {
    final scenario = await _ClaimScenario.create();
    addTearDown(scenario.dispose);
    final nativePath = scenario.ledger.path.replaceAll(r'\', '/');
    final drivePath = RegExp(r'^([a-zA-Z]):/(.*)$').firstMatch(nativePath);
    expect(drivePath, isNotNull, reason: nativePath);
    final gitBashPath =
        '/${drivePath!.group(1)!.toLowerCase()}/${drivePath.group(2)}';

    final result = await scenario.claim(
      project: 'https://project-one.supabase.co',
      email: 'auth-spike-git-bash-01@example.test',
      ledgerOverride: gitBashPath,
    );

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(scenario.ledger.existsSync(), isTrue);
  }, skip: !Platform.isWindows);

  test('默认 ledger 位于用户状态目录', () async {
    final scenario = await _ClaimScenario.create();
    addTearDown(scenario.dispose);
    final stateHome = Directory('${scenario.directory.path}/user-state');
    final expectedLedger = Platform.isMacOS
        ? File(
            '${stateHome.path}/Library/Application Support/'
            'tongxingzhe/auth-spike/spent-signup-emails-v1.json',
          )
        : File(
            '${stateHome.path}/tongxingzhe/auth-spike/'
            'spent-signup-emails-v1.json',
          );

    final result = await scenario.claim(
      project: 'https://project-one.supabase.co',
      email: 'auth-spike-default-path-01@example.test',
      useDefaultLedger: true,
      extraEnvironment: {
        'HOME': stateHome.path,
        'LOCALAPPDATA': stateHome.path,
        'XDG_STATE_HOME': stateHome.path,
      },
    );

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(expectedLedger.existsSync(), isTrue);
  });

  test('ledger 路径不可写入文件时失败关闭', () async {
    final scenario = await _ClaimScenario.create();
    addTearDown(scenario.dispose);
    final directoryInsteadOfFile = Directory(
      '${scenario.directory.path}/ledger-is-a-directory',
    );
    await directoryInsteadOfFile.create();

    final result = await scenario.claim(
      project: 'https://project-one.supabase.co',
      email: 'auth-spike-io-failure-01@example.test',
      ledgerOverride: directoryInsteadOfFile.path,
    );

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('Flutter 未启动'));
    expect(directoryInsteadOfFile.existsSync(), isTrue);
  });
}

Future<ProcessResult> _collect(Process process) async {
  final stdoutText = await utf8.decoder.bind(process.stdout).join();
  final stderrText = await utf8.decoder.bind(process.stderr).join();
  final exitCode = await process.exitCode;
  return ProcessResult(process.pid, exitCode, stdoutText, stderrText);
}

final class _ClaimScenario {
  _ClaimScenario._(this.directory);

  final Directory directory;

  File get ledger => File('${directory.path}/spent-email-ledger.json');

  static Future<_ClaimScenario> create() async {
    return _ClaimScenario._(
      await Directory.systemTemp.createTemp('tongxingzhe-auth-claim-'),
    );
  }

  Future<void> dispose() => directory.delete(recursive: true);

  Future<ProcessResult> claim({
    required String project,
    required String email,
    Map<String, String> extraEnvironment = const {},
    String? ledgerOverride,
    bool useDefaultLedger = false,
  }) async {
    final config = await writeConfig(project: project, email: email);
    final environment = <String, String>{
      ...Platform.environment,
      ...extraEnvironment,
    };
    if (useDefaultLedger) {
      environment.remove('AUTH_SPIKE_LEDGER_PATH');
    } else {
      environment['AUTH_SPIKE_LEDGER_PATH'] = ledgerOverride ?? ledger.path;
    }
    return Process.run(
      'dart',
      ['tool/claim_supabase_auth_spike_email.dart', '--config', config.path],
      workingDirectory: Directory.current.path,
      environment: environment,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
  }

  Future<Process> startClaim(File config) {
    return Process.start(
      'dart',
      ['tool/claim_supabase_auth_spike_email.dart', '--config', config.path],
      workingDirectory: Directory.current.path,
      environment: {
        ...Platform.environment,
        'AUTH_SPIKE_LEDGER_PATH': ledger.path,
      },
    );
  }

  Future<File> writeConfig({
    required String project,
    required String email,
  }) async {
    final config = File(
      '${directory.path}/config-${DateTime.now().microsecondsSinceEpoch}.json',
    );
    await config.writeAsString(
      jsonEncode({
        'AUTH_SPIKE_MODE': 'signup_request',
        'SUPABASE_URL': project,
        'AUTH_SPIKE_EMAIL': email,
        'AUTH_SPIKE_PASSWORD': 'synthetic-password',
        'SUPABASE_PUBLISHABLE_KEY': 'publishable-test-key',
      }),
    );
    return config;
  }
}
