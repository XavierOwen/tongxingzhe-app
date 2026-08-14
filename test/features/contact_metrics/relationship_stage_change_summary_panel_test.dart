import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/features/contact_metrics/relationship_stage_change_summary.dart';
import 'package:tongxingzhe_app/features/contact_metrics/relationship_stage_change_summary_panel.dart';
import 'package:tongxingzhe_app/l10n/app_strings.dart';

void main() {
  testWidgets('320 px 与 200% 字号显示四项个人事实和可信时间', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final semantics = tester.ensureSemantics();
    final gateway = _QueueGateway([
      PersonalRelationshipStageChangeSummaryGatewaySuccess(_summary()),
    ]);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 568),
          textScaler: TextScaler.linear(2),
        ),
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: _panel(gateway: gateway)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('关系阶段变更'), findsOneWidget);
    expect(find.text('阶段变更事件：5 次'), findsOneWidget);
    expect(find.text('上升事件：3 次'), findsOneWidget);
    expect(find.text('下降事件：2 次'), findsOneWidget);
    expect(find.text('发生过变更的去重关系：4 个对象 × 项目关系'), findsOneWidget);
    expect(
      find.text(
        '统计期间（UTC）：2030-01-01T00:00:00.000Z 至 '
        '2030-01-08T00:00:00.000Z，不含结束时刻',
      ),
      findsOneWidget,
    );
    expect(find.text('服务器数据截止：2030-01-08T01:00:00.000Z'), findsOneWidget);
    expect(find.bySemanticsLabel('阶段变更事件：5 次'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.text('关系阶段变更'))
          .getSemanticsData()
          .flagsCollection
          .isHeader,
      isTrue,
    );
    expect(gateway.calls.single.projectId, _projectId);
    semantics.dispose();
  });

  testWidgets('空期间诚实显示四个零', (tester) async {
    final gateway = _QueueGateway([
      PersonalRelationshipStageChangeSummaryGatewaySuccess(
        _summary(events: 0, relationships: 0, upward: 0, downward: 0),
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: _panel(gateway: gateway)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('阶段变更事件：0 次'), findsOneWidget);
    expect(find.text('上升事件：0 次'), findsOneWidget);
    expect(find.text('下降事件：0 次'), findsOneWidget);
    expect(find.text('发生过变更的去重关系：0 个对象 × 项目关系'), findsOneWidget);
    expect(find.textContaining('无法载入'), findsNothing);
  });

  testWidgets('英文文案不把方向称为成功或失败', (tester) async {
    final gateway = _QueueGateway([
      PersonalRelationshipStageChangeSummaryGatewaySuccess(_summary()),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RelationshipStageChangeSummaryPanel(
            text: const AppStrings('en'),
            gateway: gateway,
            projectId: _projectId,
            fromUtc: _fromUtc,
            untilUtc: _untilUtc,
            refreshRevision: 0,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Stage-change events: 5'), findsOneWidget);
    expect(find.text('Upward events: 3'), findsOneWidget);
    expect(find.text('Downward events: 2'), findsOneWidget);
    expect(find.text('Successful events: 3'), findsNothing);
    expect(find.text('Failed events: 2'), findsNothing);
  });

  testWidgets('Tab、Shift-Tab、Enter、Space 和 Escape 保持稳定重试路径', (tester) async {
    final gateway = _QueueGateway([
      const PersonalRelationshipStageChangeSummaryGatewayRejected(
        PersonalRelationshipStageChangeSummaryFailureCode.networkUnavailable,
      ),
      const PersonalRelationshipStageChangeSummaryGatewayRejected(
        PersonalRelationshipStageChangeSummaryFailureCode.networkUnavailable,
      ),
      PersonalRelationshipStageChangeSummaryGatewaySuccess(_summary()),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              _panel(gateway: gateway),
              TextButton(
                key: const ValueKey('after-stage-change-panel'),
                onPressed: () {},
                child: const Text('下一项'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final retry = find.byKey(const ValueKey('relationship-stage-change-retry'));

    await _focusByTabbing(tester, retry);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(_containsPrimaryFocus(tester, retry), isTrue);
    expect(gateway.calls, hasLength(1));

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(gateway.calls, hasLength(2));
    expect(_containsPrimaryFocus(tester, retry), isTrue);

    await _focusByTabbing(
      tester,
      find.byKey(const ValueKey('after-stage-change-panel')),
    );
    await _shiftTabTo(tester, retry);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();

    expect(find.text('阶段变更事件：5 次'), findsOneWidget);
    expect(gateway.calls, hasLength(3));
  });

  testWidgets('loading 可播报且卸载后忽略迟到响应', (tester) async {
    final semantics = tester.ensureSemantics();
    final gateway = _CompletingGateway();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: _panel(gateway: gateway)),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.bySemanticsLabel('正在载入关系阶段变更'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    gateway.completers.single.complete(
      PersonalRelationshipStageChangeSummaryGatewaySuccess(_summary()),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('阶段变更事件：5 次'), findsNothing);
    semantics.dispose();
  });

  testWidgets('项目、期间和刷新变化会丢弃旧 scope 的迟到响应', (tester) async {
    final gateway = _CompletingGateway();
    var projectId = _projectId;
    var fromUtc = _fromUtc;
    var refreshRevision = 0;
    late StateSetter update;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return RelationshipStageChangeSummaryPanel(
                text: const AppStrings('zh'),
                gateway: gateway,
                projectId: projectId,
                fromUtc: fromUtc,
                untilUtc: _untilUtc,
                refreshRevision: refreshRevision,
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(gateway.calls, hasLength(1));

    update(() => projectId = _secondProjectId);
    await tester.pump();
    expect(gateway.calls, hasLength(2));
    gateway.completers[0].complete(
      PersonalRelationshipStageChangeSummaryGatewaySuccess(_summary()),
    );
    await tester.pump();
    expect(find.text('阶段变更事件：5 次'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    gateway.completers[1].complete(
      PersonalRelationshipStageChangeSummaryGatewaySuccess(
        _summary(projectId: _secondProjectId),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('阶段变更事件：5 次'), findsOneWidget);

    update(() => fromUtc = DateTime.utc(2029, 12, 31));
    await tester.pump();
    expect(gateway.calls, hasLength(3));
    gateway.completers[2].complete(
      PersonalRelationshipStageChangeSummaryGatewaySuccess(
        _summary(
          projectId: _secondProjectId,
          fromUtc: DateTime.utc(2029, 12, 31),
        ),
      ),
    );
    await tester.pumpAndSettle();

    update(() => refreshRevision++);
    await tester.pump();
    expect(gateway.calls, hasLength(4));
    gateway.completers[3].complete(
      const PersonalRelationshipStageChangeSummaryGatewayRejected(
        PersonalRelationshipStageChangeSummaryFailureCode.serviceUnavailable,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('关系阶段变更暂时无法载入。'), findsOneWidget);

    final retry = find.byKey(const ValueKey('relationship-stage-change-retry'));
    await _focusByTabbing(tester, retry);
    update(() => refreshRevision++);
    await tester.pump();
    expect(gateway.calls, hasLength(5));
    gateway.completers[4].complete(
      const PersonalRelationshipStageChangeSummaryGatewayRejected(
        PersonalRelationshipStageChangeSummaryFailureCode.networkUnavailable,
      ),
    );
    await tester.pumpAndSettle();
    expect(_containsPrimaryFocus(tester, retry), isTrue);
  });
}

Widget _panel({
  required PersonalRelationshipStageChangeSummaryGateway gateway,
}) => RelationshipStageChangeSummaryPanel(
  text: const AppStrings('zh'),
  gateway: gateway,
  projectId: _projectId,
  fromUtc: _fromUtc,
  untilUtc: _untilUtc,
  refreshRevision: 0,
);

PersonalRelationshipStageChangeSummary _summary({
  String projectId = _projectId,
  DateTime? fromUtc,
  int events = 5,
  int relationships = 4,
  int upward = 3,
  int downward = 2,
}) => PersonalRelationshipStageChangeSummary.fromCounts(
  projectId: projectId,
  fromUtc: fromUtc ?? _fromUtc,
  untilUtc: _untilUtc,
  dataCutoffUtc: _cutoffUtc,
  authorizedAtUtc: _cutoffUtc,
  retrievedAtUtc: _retrievedAtUtc,
  eventCount: events,
  distinctRelationshipCount: relationships,
  upwardCount: upward,
  downwardCount: downward,
);

Future<void> _focusByTabbing(WidgetTester tester, Finder target) async {
  for (var index = 0; index < 20; index++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    if (_containsPrimaryFocus(tester, target)) return;
  }
  fail('Unable to focus $target');
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

final class _Call {
  const _Call(this.projectId, this.fromUtc, this.untilUtc);

  final String projectId;
  final DateTime fromUtc;
  final DateTime untilUtc;
}

final class _QueueGateway
    implements PersonalRelationshipStageChangeSummaryGateway {
  _QueueGateway(this.results);

  final List<PersonalRelationshipStageChangeSummaryGatewayResult> results;
  final List<_Call> calls = [];
  var _index = 0;

  @override
  Future<PersonalRelationshipStageChangeSummaryGatewayResult> load({
    required String projectId,
    required DateTime fromUtc,
    required DateTime untilUtc,
  }) async {
    calls.add(_Call(projectId, fromUtc, untilUtc));
    return results[_index++];
  }

  @override
  Future<void> close() async {}
}

final class _CompletingGateway
    implements PersonalRelationshipStageChangeSummaryGateway {
  final List<_Call> calls = [];
  final List<Completer<PersonalRelationshipStageChangeSummaryGatewayResult>>
  completers = [];

  @override
  Future<PersonalRelationshipStageChangeSummaryGatewayResult> load({
    required String projectId,
    required DateTime fromUtc,
    required DateTime untilUtc,
  }) {
    calls.add(_Call(projectId, fromUtc, untilUtc));
    final completer =
        Completer<PersonalRelationshipStageChangeSummaryGatewayResult>();
    completers.add(completer);
    return completer.future;
  }

  @override
  Future<void> close() async {}
}

const _projectId = '33333333-3333-4333-8333-333333333333';
const _secondProjectId = '44444444-4444-4444-8444-444444444444';
final _fromUtc = DateTime.utc(2030, 1, 1);
final _untilUtc = DateTime.utc(2030, 1, 8);
final _cutoffUtc = DateTime.utc(2030, 1, 8, 1);
final _retrievedAtUtc = DateTime.utc(2030, 1, 8, 2);
