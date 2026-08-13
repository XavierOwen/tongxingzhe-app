import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/features/project_settings/personal_follow_up_consent_opt_in_screen.dart';
import 'package:tongxingzhe_app/l10n/app_strings.dart';
import 'package:tongxingzhe_app/project_settings/personal_follow_up_consent_opt_in.dart';

void main() {
  testWidgets('页面说明这是项目开关，不是对象同意，也不显示比例结果', (tester) async {
    final gateway = _FakeGateway();
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app(gateway));

    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.text('项目设置'), findsOneWidget);
    final loading = find.byKey(const ValueKey('consent-opt-in-loading'));
    expect(loading, findsOneWidget);
    expect(tester.getSemantics(loading).label, contains('正在读取项目开关'));

    gateway.completeLoad(
      PersonalFollowUpConsentOptInSuccess(_state(configuration: null)),
    );
    await tester.pumpAndSettle();

    expect(find.text('后续联系同意占比'), findsOneWidget);
    expect(find.textContaining('这个开关允许当前个人项目读取'), findsOneWidget);
    expect(find.textContaining('停用会保留审计历史'), findsOneWidget);
    expect(find.text('当前状态：从未启用'), findsOneWidget);
    expect(find.text('启用占比读取'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    expect(find.byKey(const ValueKey('consent-opt-in-toggle')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('网络错误是 live region，并提供重试后回到状态', (tester) async {
    final gateway = _FakeGateway(
      loadResult: const PersonalFollowUpConsentOptInRejected(
        PersonalFollowUpConsentOptInFailureCode.networkUnavailable,
      ),
    );
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();

    final error = find.text('无法连接项目服务。请检查网络后重试。');
    expect(error, findsOneWidget);
    expect(
      tester
          .getSemantics(error)
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );

    await tester.tap(find.byKey(const ValueKey('consent-opt-in-retry')));
    gateway.completeLoad(
      PersonalFollowUpConsentOptInSuccess(_state(configuration: null)),
    );
    await tester.pumpAndSettle();
    expect(find.text('当前状态：从未启用'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('无效请求与未配置服务使用不同提示', (tester) async {
    final gateway = _FakeGateway(
      loadResult: const PersonalFollowUpConsentOptInRejected(
        PersonalFollowUpConsentOptInFailureCode.invalidRequest,
      ),
    );
    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();

    expect(find.textContaining('未接受这次设置请求'), findsOneWidget);
    expect(find.text('项目开关服务尚未配置。'), findsNothing);
  });

  testWidgets('项目范围变化时忽略旧响应并读取新项目', (tester) async {
    final gateway = _FakeGateway();
    await tester.pumpWidget(_app(gateway, projectId: 'project-a'));

    await tester.pumpWidget(_app(gateway, projectId: 'project-b'));
    await tester.pump();
    gateway.completeLoad(
      PersonalFollowUpConsentOptInSuccess(
        _state(configuration: null, projectId: 'project-a'),
      ),
    );
    await tester.pump();
    expect(find.text('当前状态：从未启用'), findsNothing);

    gateway.completeLoad(
      PersonalFollowUpConsentOptInSuccess(
        _state(configuration: null, projectId: 'project-b'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('当前状态：从未启用'), findsOneWidget);
  });

  testWidgets('保存期间显示 loading，只有服务端成功后才显示已保存', (tester) async {
    final gateway = _FakeGateway();
    await tester.pumpWidget(_app(gateway));
    gateway.completeLoad(
      PersonalFollowUpConsentOptInSuccess(
        _state(configuration: _configuration(false)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('consent-opt-in-toggle')));
    await tester.pump();
    expect(find.text('正在保存项目开关'), findsOneWidget);
    expect(find.text('项目开关已保存'), findsNothing);
    expect(gateway.configureCalls, hasLength(1));

    gateway.completeConfigure(
      PersonalFollowUpConsentOptInSuccess(_configuration(true, version: 2)),
    );
    await tester.pumpAndSettle();
    expect(find.text('项目开关已保存'), findsOneWidget);
    expect(find.text('当前状态：已启用'), findsOneWidget);
  });

  testWidgets('保存失败保留旧状态，并用同一重试动作恢复', (tester) async {
    final gateway = _FakeGateway();
    await tester.pumpWidget(_app(gateway));
    gateway.completeLoad(
      PersonalFollowUpConsentOptInSuccess(
        _state(configuration: _configuration(false)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('consent-opt-in-toggle')));
    gateway.completeConfigure(
      const PersonalFollowUpConsentOptInRejected(
        PersonalFollowUpConsentOptInFailureCode.networkUnavailable,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('当前状态：已停用'), findsOneWidget);
    expect(find.byKey(const ValueKey('consent-opt-in-toggle')), findsOneWidget);
    expect(find.text('无法连接项目服务。请检查网络后重试。'), findsOneWidget);
    expect(find.byKey(const ValueKey('consent-opt-in-retry')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('consent-opt-in-retry')));
    expect(gateway.configureCalls, hasLength(2));
    expect(
      gateway.configureCalls[0].requestId,
      gateway.configureCalls[1].requestId,
    );
    gateway.completeConfigure(
      PersonalFollowUpConsentOptInSuccess(_configuration(true, version: 2)),
    );
    await tester.pumpAndSettle();
    expect(find.text('当前状态：已启用'), findsOneWidget);
  });

  testWidgets('320 宽和 200% 文字仍可操作，并支持 Enter、Space 与 Escape', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final gateway = _FakeGateway();
    await tester.pumpWidget(
      _app(gateway, textScaler: TextScaler.linear(2), routeLauncher: true),
    );
    final launcher = find.byKey(const ValueKey('open-consent-settings'));
    await _focusByTabbing(tester, launcher);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    gateway.completeLoad(
      PersonalFollowUpConsentOptInSuccess(
        _state(configuration: _configuration(false)),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('consent-opt-in-toggle')), findsOneWidget);

    final toggle = find.byKey(const ValueKey('consent-opt-in-toggle'));
    final close = find.byKey(const ValueKey('consent-opt-in-close'));
    await _focusByTabbing(tester, toggle);
    await _shiftTabTo(tester, close);
    await _focusByTabbing(tester, toggle);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(gateway.configureCalls, hasLength(1));
    gateway.completeConfigure(
      PersonalFollowUpConsentOptInSuccess(_configuration(true, version: 2)),
    );
    await tester.pumpAndSettle();

    await _focusByTabbing(
      tester,
      find.byKey(const ValueKey('consent-opt-in-toggle')),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(gateway.configureCalls, hasLength(2));
    gateway.completeConfigure(
      PersonalFollowUpConsentOptInSuccess(_configuration(false, version: 3)),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(PersonalFollowUpConsentOptInScreen), findsNothing);
    expect(_containsPrimaryFocus(tester, launcher), isTrue);
  });
}

Widget _app(
  _FakeGateway gateway, {
  TextScaler textScaler = TextScaler.noScaling,
  bool routeLauncher = false,
  String projectId = 'project-a',
}) {
  final screen = PersonalFollowUpConsentOptInScreen(
    text: const AppStrings('zh'),
    projectId: projectId,
    gateway: gateway,
    requestIdGenerator: _Ids(),
  );
  if (!routeLauncher) return MaterialApp(home: screen);
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScaler),
      child: child!,
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            key: const ValueKey('open-consent-settings'),
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute<void>(builder: (_) => screen));
            },
            child: const Text('打开'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _focusByTabbing(WidgetTester tester, Finder target) async {
  for (var i = 0; i < 8; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    if (_containsPrimaryFocus(tester, target)) return;
  }
  fail('Could not focus $target');
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

final class _Ids implements ConsentOptInRequestIdGenerator {
  var _next = 0;

  @override
  String next() => 'request-${++_next}';
}

final class _ConfigureCall {
  const _ConfigureCall({
    required this.expectedVersion,
    required this.enabled,
    required this.requestId,
  });

  final int expectedVersion;
  final bool enabled;
  final String requestId;
}

final class _FakeGateway implements PersonalFollowUpConsentOptInGateway {
  _FakeGateway({this.loadResult});

  PersonalFollowUpConsentOptInResult<PersonalFollowUpConsentOptInState>?
  loadResult;
  final _loads =
      <
        Completer<
          PersonalFollowUpConsentOptInResult<PersonalFollowUpConsentOptInState>
        >
      >[];
  final _configures =
      <
        Completer<
          PersonalFollowUpConsentOptInResult<
            PersonalFollowUpConsentOptInConfiguration
          >
        >
      >[];
  final configureCalls = <_ConfigureCall>[];

  @override
  Future<PersonalFollowUpConsentOptInResult<PersonalFollowUpConsentOptInState>>
  load() {
    final immediate = loadResult;
    loadResult = null;
    if (immediate != null) return Future.value(immediate);
    final completer =
        Completer<
          PersonalFollowUpConsentOptInResult<PersonalFollowUpConsentOptInState>
        >();
    _loads.add(completer);
    return completer.future;
  }

  @override
  Future<
    PersonalFollowUpConsentOptInResult<
      PersonalFollowUpConsentOptInConfiguration
    >
  >
  configure({
    required int expectedVersion,
    required bool enabled,
    required String requestId,
  }) {
    configureCalls.add(
      _ConfigureCall(
        expectedVersion: expectedVersion,
        enabled: enabled,
        requestId: requestId,
      ),
    );
    final completer =
        Completer<
          PersonalFollowUpConsentOptInResult<
            PersonalFollowUpConsentOptInConfiguration
          >
        >();
    _configures.add(completer);
    return completer.future;
  }

  void completeLoad(
    PersonalFollowUpConsentOptInResult<PersonalFollowUpConsentOptInState>
    result,
  ) {
    final completer = _loads.firstWhere((candidate) => !candidate.isCompleted);
    completer.complete(result);
  }

  void completeConfigure(
    PersonalFollowUpConsentOptInResult<
      PersonalFollowUpConsentOptInConfiguration
    >
    result,
  ) {
    final completer = _configures.firstWhere(
      (candidate) => !candidate.isCompleted,
    );
    completer.complete(result);
  }

  @override
  Future<void> close() async {}
}

PersonalFollowUpConsentOptInState _state({
  required PersonalFollowUpConsentOptInConfiguration? configuration,
  String projectId = 'project-a',
}) => PersonalFollowUpConsentOptInState(
  stateContractId: personalFollowUpConsentOptInStateContract,
  metricId: personalFollowUpConsentOptInMetric,
  projectId: projectId,
  status: configuration?.enabled == true
      ? PersonalFollowUpConsentOptInStatus.enabled
      : PersonalFollowUpConsentOptInStatus.notEnabled,
  configuration: configuration,
);

PersonalFollowUpConsentOptInConfiguration _configuration(
  bool enabled, {
  int version = 1,
  String projectId = 'project-a',
}) => PersonalFollowUpConsentOptInConfiguration(
  configurationContractId: personalFollowUpConsentOptInConfigurationContract,
  metricId: personalFollowUpConsentOptInMetric,
  projectId: projectId,
  versionNumber: version,
  expectedVersion: version - 1,
  enabled: enabled,
  requestId: 'server-request-$version',
  recordedAtUtc: DateTime.utc(2026, 8, 13),
);
