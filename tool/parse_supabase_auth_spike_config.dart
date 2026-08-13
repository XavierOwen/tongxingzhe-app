import 'dart:convert';
import 'dart:io';

const _guardedKeys = <String>[
  'AUTH_SPIKE_MODE',
  'AUTH_SPIKE_EMAIL',
  'AUTH_SPIKE_SIGNUP_CONFIRM_NEW_SYNTHETIC_ACCOUNT',
];

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln(
      '用法：dart tool/parse_supabase_auth_spike_config.dart <config>',
    );
    exitCode = 64;
    return;
  }

  try {
    final decoded = jsonDecode(File(arguments.single).readAsStringSync());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('配置必须是 JSON object');
    }

    final values = _guardedKeys.map((key) {
      if (!decoded.containsKey(key)) {
        return '';
      }

      final value = decoded[key];
      if (value is String) {
        _validateValue(key, value);
        return value;
      }
      if (value is bool) {
        return value.toString();
      }
      throw FormatException('$key 必须是字符串或布尔值');
    });

    // Shell runner 只需要这些三个非密码字段；不要把配置中的密码、OTP 或
    // 其他字段打印到 stdout。
    stdout.write(values.join('\t'));
  } on Object catch (error) {
    stderr.writeln('无法读取 AUTH_SPIKE_CONFIG：${_errorMessage(error)}');
    exitCode = 1;
  }
}

void _validateValue(String key, String value) {
  if (value.contains('\t') || value.contains('\n') || value.contains('\r')) {
    throw FormatException('$key 不能包含换行或 tab');
  }
}

String _errorMessage(Object error) {
  if (error is FormatException) {
    return error.message;
  }
  return error.toString();
}
