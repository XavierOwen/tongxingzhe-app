import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/features/contact_metrics/personal_follow_up_consent_ratio.dart';
import 'package:tongxingzhe_app/features/contact_metrics/personal_follow_up_consent_ratio_panel.dart';
import 'package:tongxingzhe_app/l10n/app_strings.dart';

void main() {
  testWidgets('320 px 与 200% 字号显示比例及完整覆盖', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final semantics = tester.ensureSemantics();
    final gateway = _QueueGateway([
      PersonalFollowUpConsentRatioGatewaySuccess(_ready()),
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
    expect(find.text('后续联系同意占比'), findsOneWidget);
    expect(find.text('明确同意：2 / 3（66.67%）'), findsOneWidget);
    expect(find.text('覆盖：未知 0；拒答 1；不适用 1；未回答 2；排除 0'), findsOneWidget);
    expect(find.bySemanticsLabel('明确同意：2 / 3（66.67%）'), findsOneWidget);
    expect(gateway.calls.single.projectId, _projectId);
    semantics.dispose();
  });

  testWidgets('not enabled 不伪造数值或覆盖', (tester) async {
    final gateway = _QueueGateway([
      const PersonalFollowUpConsentRatioGatewaySuccess(
        PersonalFollowUpConsentRatioNotEnabled(projectId: _projectId),
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: _panel(gateway: gateway)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('当前项目未启用'), findsOneWidget);
    expect(find.textContaining('0 / 0'), findsNothing);
    expect(find.textContaining('覆盖：'), findsNothing);
  });

  testWidgets('空分母显示 0 / 0 且不显示 0%', (tester) async {
    final gateway = _QueueGateway([
      PersonalFollowUpConsentRatioGatewaySuccess(_ready(yes: 0, no: 0)),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: _panel(gateway: gateway)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('明确同意：0 / 0（暂无可计算比例）'), findsOneWidget);
    expect(find.textContaining('0%'), findsNothing);
  });

  testWidgets('Tab、Shift-Tab、Enter、Space 和 Escape 保持稳定路径', (tester) async {
    final gateway = _QueueGateway([
      const PersonalFollowUpConsentRatioGatewayRejected(
        PersonalFollowUpConsentRatioFailureCode.networkUnavailable,
      ),
      const PersonalFollowUpConsentRatioGatewayRejected(
        PersonalFollowUpConsentRatioFailureCode.networkUnavailable,
      ),
      PersonalFollowUpConsentRatioGatewaySuccess(_ready()),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              _panel(gateway: gateway),
              TextButton(
                key: const ValueKey('after-consent-ratio-panel'),
                onPressed: () {},
                child: const Text('下一项'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final retry = find.byKey(const ValueKey('personal-consent-ratio-retry'));
    expect(retry, findsOneWidget);

    await _focusByTabbing(tester, retry);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(_containsPrimaryFocus(tester, retry), isTrue);
    expect(gateway.calls, hasLength(1));

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(gateway.calls, hasLength(2));
    expect(retry, findsOneWidget);

    await _focusByTabbing(
      tester,
      find.byKey(const ValueKey('after-consent-ratio-panel')),
    );
    await _shiftTabTo(tester, retry);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();

    expect(find.text('明确同意：2 / 3（66.67%）'), findsOneWidget);
    expect(gateway.calls, hasLength(3));
  });

  testWidgets('项目切换后忽略旧 scope 的迟到响应', (tester) async {
    final gateway = _CompletingGateway();
    var projectId = _projectId;
    var refreshRevision = 0;
    late StateSetter update;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return PersonalFollowUpConsentRatioPanel(
                text: const AppStrings('zh'),
                gateway: gateway,
                projectId: projectId,
                fromUtc: _fromUtc,
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
      const PersonalFollowUpConsentRatioGatewaySuccess(
        PersonalFollowUpConsentRatioNotEnabled(projectId: _projectId),
      ),
    );
    await tester.pump();
    expect(find.textContaining('当前项目未启用'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    gateway.completers[1].complete(
      PersonalFollowUpConsentRatioGatewaySuccess(
        _ready(projectId: _secondProjectId),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('明确同意：2 / 3（66.67%）'), findsOneWidget);

    update(() => refreshRevision++);
    await tester.pump();
    expect(gateway.calls, hasLength(3));
    gateway.completers[2].complete(
      const PersonalFollowUpConsentRatioGatewaySuccess(
        PersonalFollowUpConsentRatioNotEnabled(projectId: _secondProjectId),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('当前项目未启用'), findsOneWidget);
  });
}

Widget _panel({required PersonalFollowUpConsentRatioGateway gateway}) =>
    PersonalFollowUpConsentRatioPanel(
      text: const AppStrings('zh'),
      gateway: gateway,
      projectId: _projectId,
      fromUtc: _fromUtc,
      untilUtc: _untilUtc,
      refreshRevision: 0,
    );

PersonalFollowUpConsentRatioReady _ready({
  String projectId = _projectId,
  int yes = 2,
  int no = 1,
}) => PersonalFollowUpConsentRatioReady(
  projectId: projectId,
  metric: consentRatioMetricResult(
    fromUtc: _fromUtc,
    untilUtc: _untilUtc,
    dataCutoffUtc: DateTime.utc(2030, 1, 8, 1),
    retrievedAtUtc: DateTime.utc(2030, 1, 8, 2),
    yesCount: yes,
    noCount: no,
    unknownCount: 0,
    refusedCount: 1,
    notApplicableCount: 1,
    unansweredCount: 2,
    excludedCount: 0,
  ),
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

final class _QueueGateway implements PersonalFollowUpConsentRatioGateway {
  _QueueGateway(this.results);

  final List<PersonalFollowUpConsentRatioGatewayResult> results;
  final List<_Call> calls = [];
  var _index = 0;

  @override
  Future<PersonalFollowUpConsentRatioGatewayResult> load({
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

final class _CompletingGateway implements PersonalFollowUpConsentRatioGateway {
  final List<_Call> calls = [];
  final List<Completer<PersonalFollowUpConsentRatioGatewayResult>> completers =
      [];

  @override
  Future<PersonalFollowUpConsentRatioGatewayResult> load({
    required String projectId,
    required DateTime fromUtc,
    required DateTime untilUtc,
  }) {
    calls.add(_Call(projectId, fromUtc, untilUtc));
    final completer = Completer<PersonalFollowUpConsentRatioGatewayResult>();
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
