import 'dart:io';

/// 从正式入口沿本项目 import 图检查，证明 legacy Demo 实现不可达。
///
/// 这不是通用 Dart parser；它只处理本仓库使用的 relative import 和
/// `package:tongxingzhe_app/` import。若以后引入 code generation／conditional
/// local import，应先扩展本检查再改生产入口。
void main() {
  final repositoryRoot = Directory.current.absolute;
  final libraryRoot = Directory('${repositoryRoot.path}/lib');
  final entrypoint = File('${libraryRoot.path}/main.dart');
  final pending = <File>[entrypoint];
  final visited = <String>{};
  final violations = <String>[];

  while (pending.isNotEmpty) {
    final pendingSource = pending.removeLast();
    if (!pendingSource.existsSync()) {
      violations.add('找不到 production import：${pendingSource.absolute.path}');
      continue;
    }
    final source = File(pendingSource.resolveSymbolicLinksSync());
    final normalizedPath = source.path;
    if (!visited.add(normalizedPath)) {
      continue;
    }

    final relativePath = _relativeTo(repositoryRoot.path, normalizedPath);
    if (relativePath.startsWith('lib/legacy_demo/')) {
      violations.add('production import 图触达 legacy Demo：$relativePath');
    }

    final contents = source.readAsStringSync();
    if (contents.contains("package:crypto/crypto.dart") ||
        RegExp(r'\bmd5\s*\.').hasMatch(contents)) {
      violations.add('production import 图触达 MD5：$relativePath');
    }
    if (RegExp(r'''['"](?:admin[123]|user[12])['"]''').hasMatch(contents)) {
      violations.add('production import 图含默认演示账号：$relativePath');
    }

    for (final uri in _localImports(contents)) {
      final imported = _resolveImport(
        importingFile: source,
        uri: uri,
        libraryRoot: libraryRoot,
      );
      if (imported != null) {
        pending.add(imported);
      }
    }
  }

  if (violations.isNotEmpty) {
    stderr.writeln('Production boundary 检查失败：');
    for (final violation in violations) {
      stderr.writeln('- $violation');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln('Production boundary 通过：检查了 ${visited.length} 个 Dart 文件。');
}

Iterable<String> _localImports(String source) sync* {
  final directive = RegExp(
    r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
    multiLine: true,
  );
  for (final match in directive.allMatches(source)) {
    final uri = match.group(1)!;
    if (uri.startsWith('package:tongxingzhe_app/') ||
        (!uri.startsWith('dart:') && !uri.startsWith('package:'))) {
      yield uri;
    }
  }
}

File? _resolveImport({
  required File importingFile,
  required String uri,
  required Directory libraryRoot,
}) {
  if (uri.startsWith('package:tongxingzhe_app/')) {
    final relative = uri.substring('package:tongxingzhe_app/'.length);
    return File('${libraryRoot.path}/$relative').absolute;
  }
  if (!uri.contains(':')) {
    return File('${importingFile.parent.path}/$uri').absolute;
  }
  return null;
}

String _relativeTo(String root, String path) {
  final prefix = root.endsWith(Platform.pathSeparator)
      ? root
      : '$root${Platform.pathSeparator}';
  return path.startsWith(prefix) ? path.substring(prefix.length) : path;
}
