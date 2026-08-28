import 'dart:io';

final _markdownLink = RegExp(r'!?\[[^\]]*\]\(([^)]+)\)');
final _atxHeading = RegExp(r'^\s{0,3}#{1,6}\s+(.+?)\s*$');
final _nonSlugCharacter = RegExp(r'[^\p{L}\p{M}\p{N}_ -]', unicode: true);
final _externalScheme = RegExp(
  r'^(?:https?|mailto|tel):',
  caseSensitive: false,
);

/// 检查仓库内 Markdown 的相对文件链接和本地 ATX 标题 anchor。
void main() {
  final root = Directory.current.absolute;
  final failures = checkMarkdownLinks(root);

  if (failures.isNotEmpty) {
    stderr.writeln('Markdown 相对链接检查失败：');
    for (final failure in failures) {
      stderr.writeln('- $failure');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln('Markdown 链接通过：检查了 ${_markdownFiles(root).length} 个文件。');
}

List<String> checkMarkdownLinks(Directory root) {
  root = root.absolute;
  final rootPath = root.resolveSymbolicLinksSync();
  final markdownFiles = _markdownFiles(root);
  final anchorsByPath = <String, Set<String>>{};
  final failures = <String>[];

  Set<String> anchorsFor(String path) {
    return anchorsByPath.putIfAbsent(path, () => _markdownAnchors(File(path)));
  }

  for (final markdown in markdownFiles) {
    if (!_isRegularFileWithin(rootPath, markdown.path)) {
      failures.add(
        '${_relativeTo(root.path, markdown.path)} -> unreadable source',
      );
      continue;
    }
    for (final (:lineNumber, :text) in _markdownContentLines(markdown)) {
      for (final match in _markdownLink.allMatches(text)) {
        var target = match.group(1)!.trim();
        if (target.startsWith('<') && target.endsWith('>')) {
          target = target.substring(1, target.length - 1);
        }
        if (_isExternal(target)) {
          continue;
        }

        final hashIndex = target.indexOf('#');
        final encodedFragment = hashIndex < 0
            ? null
            : target.substring(hashIndex + 1);
        final pathAndQuery = hashIndex < 0
            ? target
            : target.substring(0, hashIndex);
        final encodedPath = pathAndQuery.split('?').first;
        final decodedPath = _decodeComponent(encodedPath);
        final decodedFragment = encodedFragment == null
            ? null
            : _decodeComponent(encodedFragment);
        if (decodedPath == null ||
            (encodedFragment != null && decodedFragment == null)) {
          failures.add(
            '${_relativeTo(root.path, markdown.path)}:$lineNumber -> $target',
          );
          continue;
        }

        final entityPath = decodedPath.isEmpty
            ? markdown.path
            : decodedPath.startsWith('/')
            ? decodedPath
            : '${markdown.parent.path}/$decodedPath';
        try {
          final entityType = FileSystemEntity.typeSync(entityPath);
          if (entityType == FileSystemEntityType.notFound) {
            failures.add(
              '${_relativeTo(root.path, markdown.path)}:$lineNumber -> $target',
            );
            continue;
          }

          final resolvedPath = _resolveEntityPath(entityPath, entityType);
          if (!_isWithin(rootPath, resolvedPath)) {
            failures.add(
              '${_relativeTo(root.path, markdown.path)}:$lineNumber -> $target',
            );
            continue;
          }

          if (decodedFragment != null &&
              decodedFragment.isNotEmpty &&
              entityType == FileSystemEntityType.file &&
              resolvedPath.endsWith('.md') &&
              !anchorsFor(resolvedPath).contains(decodedFragment)) {
            failures.add(
              '${_relativeTo(root.path, markdown.path)}:$lineNumber -> $target',
            );
          }
        } on ArgumentError {
          failures.add(
            '${_relativeTo(root.path, markdown.path)}:$lineNumber -> $target',
          );
        } on FileSystemException {
          failures.add(
            '${_relativeTo(root.path, markdown.path)}:$lineNumber -> $target',
          );
        }
      }
    }
  }

  return failures;
}

List<File> _markdownFiles(Directory root) {
  final markdownFiles = <File>[
    File('${root.path}/README.md'),
    File('${root.path}/CONTEXT.md'),
    ...Directory('${root.path}/docs')
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((file) => file.path.endsWith('.md')),
  ]..sort((a, b) => a.path.compareTo(b.path));
  return markdownFiles;
}

Set<String> _markdownAnchors(File markdown) {
  final anchors = <String>{};
  final duplicateCounts = <String, int>{};
  for (final line in _markdownContentLines(markdown)) {
    final match = _atxHeading.firstMatch(line.text);
    if (match == null) {
      continue;
    }
    final heading = match.group(1)!.replaceFirst(RegExp(r'\s+#+\s*$'), '');
    final base = _headingAnchor(heading);
    if (base.isEmpty) {
      continue;
    }
    final duplicate = duplicateCounts.update(
      base,
      (count) => count + 1,
      ifAbsent: () => 0,
    );
    anchors.add(duplicate == 0 ? base : '$base-$duplicate');
  }
  return anchors;
}

Iterable<({int lineNumber, String text})> _markdownContentLines(
  File markdown,
) sync* {
  String? fence;
  final lines = markdown.readAsLinesSync();
  for (var index = 0; index < lines.length; index += 1) {
    final text = lines[index];
    final trimmed = text.trimLeft();
    final marker = trimmed.startsWith('```')
        ? '```'
        : trimmed.startsWith('~~~')
        ? '~~~'
        : null;
    if (marker != null) {
      if (fence == null) {
        fence = marker;
      } else if (fence == marker) {
        fence = null;
      }
      continue;
    }
    if (fence == null) {
      yield (lineNumber: index + 1, text: text);
    }
  }
}

String _headingAnchor(String heading) {
  return heading
      .toLowerCase()
      .replaceAll(_nonSlugCharacter, '')
      .replaceAll(' ', '-');
}

String? _decodeComponent(String value) {
  for (var index = 0; index < value.length; index += 1) {
    if (value[index] != '%') {
      continue;
    }
    if (index + 2 >= value.length ||
        int.tryParse(value.substring(index + 1, index + 3), radix: 16) ==
            null) {
      return null;
    }
    index += 2;
  }
  try {
    final encoded = Uri.encodeComponent(value).replaceAllMapped(
      RegExp(r'%25([0-9A-Fa-f]{2})'),
      (match) => '%${match.group(1)}',
    );
    return Uri.decodeComponent(encoded);
  } on ArgumentError catch (_) {
    return null;
  } on FormatException catch (_) {
    return null;
  }
}

bool _isRegularFileWithin(String root, String path) {
  try {
    return FileSystemEntity.typeSync(path, followLinks: false) ==
            FileSystemEntityType.file &&
        _isWithin(root, File(path).resolveSymbolicLinksSync());
  } on FileSystemException {
    return false;
  } on ArgumentError {
    return false;
  }
}

String _resolveEntityPath(String path, FileSystemEntityType type) {
  return type == FileSystemEntityType.directory
      ? Directory(path).resolveSymbolicLinksSync()
      : File(path).resolveSymbolicLinksSync();
}

bool _isWithin(String root, String path) {
  final prefix = root.endsWith(Platform.pathSeparator)
      ? root
      : '$root${Platform.pathSeparator}';
  return path == root || path.startsWith(prefix);
}

bool _isExternal(String target) {
  return target.startsWith('//') || _externalScheme.hasMatch(target);
}

String _relativeTo(String root, String path) {
  final prefix = root.endsWith(Platform.pathSeparator)
      ? root
      : '$root${Platform.pathSeparator}';
  return path.startsWith(prefix) ? path.substring(prefix.length) : path;
}
