import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/screens/production_home_shell.dart';

void main() {
  for (final size in [const Size(320, 568), const Size(360, 640)]) {
    testWidgets('${size.width.toInt()} 宽标准文字不产生紧凑外壳布局异常', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_layoutOnlyApp());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('紧凑外壳保留完整上下文语义并按视觉顺序遍历焦点', (tester) async {
    final semantics = tester.ensureSemantics();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    var selectedIndex = 0;
    var pageActionCount = 0;
    const contextLabel = '很长的工作空间名称 → 很长的推广项目名称';

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: StatefulBuilder(
          builder: (context, setState) => CompactProductionHomeScaffold(
            contextLabel: contextLabel,
            appBarActions: [
              IconButton(
                key: const ValueKey('project-menu'),
                tooltip: '切换推广项目',
                onPressed: () {},
                icon: const Icon(Icons.swap_horiz_outlined),
              ),
            ],
            body: ListView(
              children: [
                TextButton(
                  key: const ValueKey('page-action-one'),
                  onPressed: () => pageActionCount += 1,
                  child: const Text('页面动作一'),
                ),
                TextButton(
                  key: const ValueKey('page-action-two'),
                  onPressed: () {},
                  child: const Text('页面动作二'),
                ),
              ],
            ),
            floatingActionButton: FloatingActionButton.extended(
              key: const ValueKey('record-contact'),
              onPressed: () {},
              icon: const Icon(Icons.add_comment_outlined),
              label: const Text('记录接触'),
            ),
            selectedIndex: selectedIndex,
            onDestinationSelected: (index) => setState(() {
              selectedIndex = index;
            }),
            destinations: const [
              NavigationDestination(
                key: ValueKey('nav-today'),
                icon: Icon(Icons.today_outlined),
                label: '今日',
              ),
              NavigationDestination(
                key: ValueKey('nav-contacts'),
                icon: Icon(Icons.forum_outlined),
                label: '接触',
              ),
              NavigationDestination(
                key: ValueKey('nav-targets'),
                icon: Icon(Icons.people_outline),
                label: '对象',
              ),
              NavigationDestination(
                key: ValueKey('nav-analysis'),
                icon: Icon(Icons.insights_outlined),
                label: '分析',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel(contextLabel), findsOneWidget);

    await _tabTo(tester, find.byKey(const ValueKey('project-menu')));
    await _tabTo(tester, find.byKey(const ValueKey('page-action-one')));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(pageActionCount, 1);
    await _tabTo(tester, find.byKey(const ValueKey('page-action-two')));
    await _tabTo(tester, find.byKey(const ValueKey('record-contact')));
    await _tabTo(tester, find.byKey(const ValueKey('nav-today')));
    await _tabTo(tester, find.byKey(const ValueKey('nav-contacts')));

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(selectedIndex, 1);
    expect(
      tester
          .getSemantics(find.text('接触'))
          .getSemanticsData()
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );

    await _shiftTabTo(tester, find.byKey(const ValueKey('nav-today')));
    semantics.dispose();
  });
}

Widget _layoutOnlyApp() => MaterialApp(
  home: CompactProductionHomeScaffold(
    contextLabel: '工作空间 → 推广项目',
    appBarActions: [
      IconButton(
        tooltip: '切换推广项目',
        onPressed: () {},
        icon: const Icon(Icons.swap_horiz_outlined),
      ),
    ],
    body: const SingleChildScrollView(
      child: Padding(padding: EdgeInsets.all(16), child: Text('今日页面')),
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () {},
      icon: const Icon(Icons.add_comment_outlined),
      label: const Text('记录接触'),
    ),
    selectedIndex: 0,
    onDestinationSelected: (_) {},
    destinations: const [
      NavigationDestination(icon: Icon(Icons.today_outlined), label: '今日'),
      NavigationDestination(icon: Icon(Icons.forum_outlined), label: '接触'),
      NavigationDestination(icon: Icon(Icons.people_outline), label: '对象'),
      NavigationDestination(icon: Icon(Icons.insights_outlined), label: '分析'),
    ],
  ),
);

Future<void> _tabTo(WidgetTester tester, Finder target) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.pump();
  expect(_containsPrimaryFocus(tester, target), isTrue);
}

Future<void> _shiftTabTo(WidgetTester tester, Finder target) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump();
  expect(_containsPrimaryFocus(tester, target), isTrue);
}

bool _containsPrimaryFocus(WidgetTester tester, Finder finder) {
  final target = tester.element(finder);
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused is! Element) return false;
  if (identical(focused, target)) return true;
  var contains = false;
  focused.visitAncestorElements((ancestor) {
    if (identical(ancestor, target)) {
      contains = true;
      return false;
    }
    return true;
  });
  return contains;
}
