import 'dart:io';

/// 从正式入口沿本项目 import 图检查，证明 legacy Demo 实现不可达。
///
/// 这不是通用 Dart parser；它只处理本仓库使用的 import、export 和 part
/// directive，以及其中的 relative URI 和 `package:tongxingzhe_app/` URI。
void main() {
  final repositoryRoot = Directory.current.absolute;
  final report = inspectProductionBoundary(repositoryRoot);

  if (report.violations.isNotEmpty) {
    stderr.writeln('Production boundary 检查失败：');
    for (final violation in report.violations) {
      stderr.writeln('- $violation');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'Production boundary 通过：检查了 ${report.visitedFileCount} 个 Dart 文件。',
  );
}

final class ProductionBoundaryReport {
  const ProductionBoundaryReport({
    required this.visitedFileCount,
    required this.violations,
  });

  final int visitedFileCount;
  final List<String> violations;
}

ProductionBoundaryReport inspectProductionBoundary(Directory repositoryRoot) {
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
    if (RegExp(r'\bmd5\s*\.').hasMatch(contents)) {
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

  return ProductionBoundaryReport(
    visitedFileCount: visited.length,
    violations: List.unmodifiable(violations),
  );
}

Iterable<String> _localImports(String source) sync* {
  final directive = RegExp(
    r'''^[ \t]*(?:import|export|part(?!\s+of\b))\s+([^;]+);''',
    multiLine: true,
  );
  final uriLiteral = RegExp(r'''['"]([^'"]+)['"]''');
  for (final match in directive.allMatches(source)) {
    for (final uriMatch in uriLiteral.allMatches(match.group(1)!)) {
      final uri = uriMatch.group(1)!;
      if (uri.startsWith('package:tongxingzhe_app/') ||
          (!uri.startsWith('dart:') && !uri.startsWith('package:'))) {
        yield uri;
      }
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
