import 'dart:io';

/// 检查仓库内 Markdown 的相对文件链接；HTTP、mailto 与页内 anchor 不访问网络。
void main() {
  final root = Directory.current.absolute;
  final markdownFiles = <File>[
    File('${root.path}/README.md'),
    File('${root.path}/CONTEXT.md'),
    ...Directory('${root.path}/docs')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.md')),
  ]..sort((a, b) => a.path.compareTo(b.path));
  final failures = <String>[];
  final markdownLink = RegExp(r'!?\[[^\]]*\]\(([^)]+)\)');

  for (final markdown in markdownFiles) {
    final lines = markdown.readAsLinesSync();
    var inFence = false;
    for (var index = 0; index < lines.length; index += 1) {
      final line = lines[index];
      if (line.trimLeft().startsWith('```')) {
        inFence = !inFence;
        continue;
      }
      if (inFence) {
        continue;
      }
      for (final match in markdownLink.allMatches(line)) {
        var target = match.group(1)!.trim();
        if (target.startsWith('<') && target.endsWith('>')) {
          target = target.substring(1, target.length - 1);
        }
        if (_isExternalOrAnchor(target)) {
          continue;
        }
        target = target.split('#').first.split('?').first;
        if (target.isEmpty) {
          continue;
        }
        final decoded = Uri.decodeComponent(target);
        final entityPath = decoded.startsWith('/')
            ? decoded
            : '${markdown.parent.path}/$decoded';
        if (FileSystemEntity.typeSync(entityPath) ==
            FileSystemEntityType.notFound) {
          failures.add(
            '${_relativeTo(root.path, markdown.path)}:${index + 1} -> $target',
          );
        }
      }
    }
  }

  if (failures.isNotEmpty) {
    stderr.writeln('Markdown 相对链接检查失败：');
    for (final failure in failures) {
      stderr.writeln('- $failure');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln('Markdown 链接通过：检查了 ${markdownFiles.length} 个文件。');
}

bool _isExternalOrAnchor(String target) {
  return target.startsWith('#') ||
      target.startsWith('http://') ||
      target.startsWith('https://') ||
      target.startsWith('mailto:') ||
      target.startsWith('tel:');
}

String _relativeTo(String root, String path) {
  final prefix = root.endsWith(Platform.pathSeparator)
      ? root
      : '$root${Platform.pathSeparator}';
  return path.startsWith(prefix) ? path.substring(prefix.length) : path;
}
