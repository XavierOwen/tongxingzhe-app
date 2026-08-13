import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _ledgerVersion = 1;
const _ledgerOverrideEnvironmentKey = 'AUTH_SPIKE_LEDGER_PATH';
final _digestPattern = RegExp(r'^[a-f0-9]{64}$');
final _syntheticEmailPattern = RegExp(
  r'^auth-spike-[a-z0-9][a-z0-9._+-]*@[a-z0-9][a-z0-9.-]*\.[a-z0-9]+$',
);

void main(List<String> arguments) {
  try {
    final configPath = _readConfigPath(arguments);
    final claim = _readClaim(File(configPath));
    final ledger = _ledgerFile();
    _claimOnce(ledger, claim);
    stdout.writeln('claimed');
  } on _SpentEmailException {
    stderr.writeln('这个合成注册邮箱已在本机用于该 Supabase 项目。请换新的合成测试邮箱。');
    exitCode = 1;
  } on _InvalidInputException catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
  } on Object {
    stderr.writeln(
      '无法安全读取或更新本机注册尝试记录；Flutter 未启动。'
      '请保留记录文件，并按手册检查权限或损坏。',
    );
    exitCode = 1;
  }
}

String _readConfigPath(List<String> arguments) {
  if (arguments.length != 2 || arguments.first != '--config') {
    throw const _InvalidInputException(
      '用法：dart tool/claim_supabase_auth_spike_email.dart '
      '--config <config>',
    );
  }
  return arguments.last;
}

({String project, String email}) _readClaim(File configFile) {
  Object? decoded;
  try {
    decoded = jsonDecode(configFile.readAsStringSync());
  } on Object {
    throw const _InvalidInputException('无法读取认证探针配置。');
  }
  if (decoded is! Map<String, dynamic>) {
    throw const _InvalidInputException('认证探针配置必须是 JSON object。');
  }
  if (decoded['AUTH_SPIKE_MODE'] != 'signup_request') {
    throw const _InvalidInputException('本机注册地址占用只接受 signup_request 配置。');
  }

  final rawProject = decoded['SUPABASE_URL'];
  final rawEmail = decoded['AUTH_SPIKE_EMAIL'];
  if (rawProject is! String || rawEmail is! String) {
    throw const _InvalidInputException(
      'signup_request 配置需要 SUPABASE_URL 和 AUTH_SPIKE_EMAIL。',
    );
  }
  return (
    project: _canonicalProject(rawProject),
    email: _canonicalEmail(rawEmail),
  );
}

String _canonicalProject(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      !uri.hasScheme ||
      !uri.hasAuthority ||
      (uri.scheme.toLowerCase() != 'https' &&
          uri.scheme.toLowerCase() != 'http') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    throw const _InvalidInputException(
      'SUPABASE_URL 必须是没有用户信息、查询、片段或子路径的 HTTP(S) 地址。',
    );
  }

  final scheme = uri.scheme.toLowerCase();
  final host = uri.host.toLowerCase();
  final defaultPort =
      (scheme == 'https' && uri.port == 443) ||
      (scheme == 'http' && uri.port == 80);
  final port = uri.hasPort && !defaultPort ? ':${uri.port}' : '';
  return '$scheme://$host$port';
}

String _canonicalEmail(String value) {
  final trimmed = value.trim();
  if (trimmed.codeUnits.any((unit) => unit > 0x7f)) {
    throw const _InvalidInputException('AUTH_SPIKE_EMAIL 必须使用 ASCII 合成测试地址。');
  }
  final canonical = trimmed.toLowerCase();
  if (!_syntheticEmailPattern.hasMatch(canonical)) {
    throw const _InvalidInputException(
      'signup_request 只接受带 auth-spike- 前缀的合成测试邮箱。',
    );
  }
  return canonical;
}

File _ledgerFile() {
  final override = Platform.environment[_ledgerOverrideEnvironmentKey];
  if (override != null && override.isNotEmpty) {
    final file = File(_platformAbsolutePath(override));
    if (!file.isAbsolute) {
      throw const _InvalidInputException('AUTH_SPIKE_LEDGER_PATH 必须是绝对路径。');
    }
    return file;
  }

  String basePath;
  if (Platform.isMacOS) {
    basePath =
        '${_requiredEnvironmentDirectory('HOME')}'
        '/Library/Application Support';
  } else if (Platform.isWindows) {
    basePath = _requiredEnvironmentDirectory('LOCALAPPDATA');
  } else {
    final xdgStateHome = Platform.environment['XDG_STATE_HOME'];
    basePath = xdgStateHome != null && xdgStateHome.isNotEmpty
        ? xdgStateHome
        : '${_requiredEnvironmentDirectory('HOME')}/.local/state';
  }
  return File('$basePath/tongxingzhe/auth-spike/spent-signup-emails-v1.json');
}

String _platformAbsolutePath(String value) {
  if (!Platform.isWindows) {
    return value;
  }
  final msysDrivePath = RegExp(r'^/([a-zA-Z])(?:/(.*))?$').firstMatch(value);
  if (msysDrivePath == null) {
    return value;
  }
  final drive = msysDrivePath.group(1)!.toUpperCase();
  final remainder = (msysDrivePath.group(2) ?? '').replaceAll('/', r'\');
  return remainder.isEmpty ? '$drive:\\' : '$drive:\\$remainder';
}

String _requiredEnvironmentDirectory(String key) {
  final value = Platform.environment[key];
  if (value == null || value.isEmpty) {
    throw _InvalidInputException('找不到用户状态目录：缺少 $key。');
  }
  return value;
}

void _claimOnce(File ledger, ({String project, String email}) claim) {
  ledger.parent.createSync(recursive: true);
  final ledgerWasMissing = !ledger.existsSync();
  final lock = ledger.openSync(mode: FileMode.append);
  try {
    lock.lockSync(FileLock.blockingExclusive);
    final entries = _readLedger(lock, allowEmpty: ledgerWasMissing);
    final digest = sha256
        .convert(utf8.encode('v1\u0000${claim.project}\u0000${claim.email}'))
        .toString();
    if (entries.any((entry) => entry.digest == digest)) {
      throw const _SpentEmailException();
    }

    _appendEntry(
      lock,
      isNewLedger: entries.isEmpty,
      entry: _LedgerEntry(digest, DateTime.now().toUtc()),
    );
  } finally {
    try {
      lock.unlockSync();
    } on Object {
      // Closing the file still releases the operating-system lock.
    }
    lock.closeSync();
  }
}

List<_LedgerEntry> _readLedger(
  RandomAccessFile ledger, {
  required bool allowEmpty,
}) {
  final length = ledger.lengthSync();
  if (length == 0) {
    if (allowEmpty) {
      return const [];
    }
    throw const FormatException('empty existing ledger');
  }
  ledger.setPositionSync(0);
  final bytes = ledger.readSync(length);
  final contents = utf8.decode(bytes, allowMalformed: false);
  if (!contents.endsWith('\n')) {
    throw const FormatException('truncated ledger');
  }

  final lines = const LineSplitter().convert(contents);
  if (lines.length < 2) {
    throw const FormatException('missing ledger entries');
  }
  final Object? header = jsonDecode(lines.first);
  if (header is! Map<String, dynamic> ||
      header.length != 2 ||
      header['type'] != 'tongxingzhe_auth_spike_signup_ledger' ||
      header['version'] != _ledgerVersion) {
    throw const FormatException('invalid ledger header');
  }

  return lines
      .skip(1)
      .map((line) {
        final Object? value = jsonDecode(line);
        if (value is! Map<String, dynamic> ||
            value.length != 2 ||
            value['digest'] is! String ||
            value['claimedAtUtc'] is! String) {
          throw const FormatException('invalid ledger entry');
        }
        final digest = value['digest'] as String;
        final claimedAt = DateTime.tryParse(value['claimedAtUtc'] as String);
        if (!_digestPattern.hasMatch(digest) ||
            claimedAt == null ||
            !claimedAt.isUtc) {
          throw const FormatException('invalid ledger entry');
        }
        return _LedgerEntry(digest, claimedAt);
      })
      .toList(growable: false);
}

void _appendEntry(
  RandomAccessFile ledger, {
  required bool isNewLedger,
  required _LedgerEntry entry,
}) {
  final buffer = StringBuffer();
  if (isNewLedger) {
    buffer.writeln(
      jsonEncode({
        'type': 'tongxingzhe_auth_spike_signup_ledger',
        'version': _ledgerVersion,
      }),
    );
  }
  buffer.writeln(
    jsonEncode({
      'digest': entry.digest,
      'claimedAtUtc': entry.claimedAt.toIso8601String(),
    }),
  );
  ledger.setPositionSync(ledger.lengthSync());
  ledger.writeStringSync(buffer.toString());
  ledger.flushSync();
}

final class _LedgerEntry {
  const _LedgerEntry(this.digest, this.claimedAt);

  final String digest;
  final DateTime claimedAt;
}

final class _InvalidInputException implements Exception {
  const _InvalidInputException(this.message);

  final String message;
}

final class _SpentEmailException implements Exception {
  const _SpentEmailException();
}
