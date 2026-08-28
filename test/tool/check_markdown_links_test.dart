import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_markdown_links.dart' as markdown_links;

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('markdown_links_');
    _write(root, 'README.md', '# Home\n');
    _write(root, 'CONTEXT.md', '# Context\n');
    Directory('${root.path}/docs').createSync();
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  test('接受同页、跨文件、编码、inline code 和重复标题 anchor', () {
    _write(
      root,
      'docs/目标 file.md',
      '# Slice 6AK 如何固定跨版本区域映射证据\n'
          '## Slice 6AM 按报告截止点固定区域目标树上下文\n'
          '### `signup_request` 的发送前安全检查\n'
          '## Repeat\n'
          '## Repeat\n'
          '## 中文 标题\n'
          '## A ／ B → C – D — E  F\n',
    );
    _write(
      root,
      'docs/source.md',
      '# Source Heading\n'
          '[same](#source-heading)\n'
          '[6AK](%E7%9B%AE%E6%A0%87%20file.md#slice-6ak-如何固定跨版本区域映射证据)\n'
          '[6AM](目标%20file.md?raw=1#slice-6am-按报告截止点固定区域目标树上下文)\n'
          '[signup](目标%20file.md#signup_request-的发送前安全检查)\n'
          '[duplicate](目标%20file.md#repeat-1)\n'
          '[encoded](目标%20file.md#%E4%B8%AD%E6%96%87-%E6%A0%87%E9%A2%98)\n'
          '[punctuation](目标%20file.md#a--b--c--d--e--f)\n',
    );

    expect(markdown_links.checkMarkdownLinks(root), isEmpty);
  });

  test('报告缺失文件、缺失 fragment、错误重复后缀和非法编码', () {
    _write(root, 'docs/target.md', '# Repeat\n# Repeat\n');
    _write(
      root,
      'docs/source.md',
      '[missing file](missing.md#none)\n'
          '[missing fragment](target.md#none)\n'
          '[wrong duplicate](target.md#repeat-2)\n'
          '[same page](#none)\n'
          '[bad encoding](target.md#bad%ZZ)\n',
    );

    final failures = markdown_links.checkMarkdownLinks(root);

    expect(failures, hasLength(5));
    for (var line = 1; line <= 5; line += 1) {
      expect(failures, contains(startsWith('docs/source.md:$line ->')));
    }
  });

  test('忽略外链和 fence 内链接，且 fence 内标题不生成 anchor', () {
    _write(
      root,
      'docs/target.md',
      '# Visible\n'
          '```md\n'
          '# Hidden\n'
          '```\n',
    );
    _write(
      root,
      'docs/source.md',
      '[visible](target.md#visible)\n'
          '[hidden](target.md#hidden)\n'
          '[external](https://example.com/page#missing)\n'
          '[uppercase external](HTTPS://example.com/page#missing)\n'
          '[email](MAILTO:user@example.com)\n'
          '[protocol relative](//example.com/page#missing)\n'
          '~~~md\n'
          '[ignored](missing.md#none)\n'
          '~~~\n',
    );

    expect(markdown_links.checkMarkdownLinks(root), [
      'docs/source.md:2 -> target.md#hidden',
    ]);
  });

  test('拒绝解析到仓库根目录外的本地链接', () {
    final outside = File('${root.path}_outside.md')
      ..writeAsStringSync('# Outside\n');
    addTearDown(() {
      if (outside.existsSync()) {
        outside.deleteSync();
      }
    });
    final outsideName = outside.uri.pathSegments.last;
    _write(root, 'docs/source.md', '[outside](../../$outsideName#outside)\n');

    expect(markdown_links.checkMarkdownLinks(root), [
      'docs/source.md:1 -> ../../$outsideName#outside',
    ]);
  });

  test('非法 UTF-8 和空字节只报告失败，不崩溃', () {
    _write(
      root,
      'docs/source.md',
      '[bad utf8](target.md#%FF)\n[null byte](bad%00path.md)\n',
    );

    expect(markdown_links.checkMarkdownLinks(root), hasLength(2));
  });

  test('不读取指向仓库外的 Markdown source symlink', () {
    final outside = Directory.systemTemp.createTempSync('markdown_outside_');
    addTearDown(() => outside.deleteSync(recursive: true));
    _write(outside, 'README.md', '[outside](missing.md)\n');
    _write(outside, 'nested/source.md', '[outside](missing.md)\n');

    File('${root.path}/README.md').deleteSync();
    Link('${root.path}/README.md').createSync('${outside.path}/README.md');
    Link('${root.path}/docs/outside').createSync('${outside.path}/nested');

    expect(markdown_links.checkMarkdownLinks(root), [
      'README.md -> unreadable source',
    ]);
  });
}

void _write(Directory root, String relativePath, String contents) {
  final file = File('${root.path}/$relativePath');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
}
