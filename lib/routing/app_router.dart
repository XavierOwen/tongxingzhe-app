import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_route.dart';

typedef AppRootRouteBuilder =
    Widget Function(
      BuildContext context,
      AppRoute route,
      ValueListenable<ContactPageClosedEvent> contactPageClosedEvents,
    );

typedef AppContactRouteBuilder =
    Widget Function(
      BuildContext context,
      String? draftId,
      String? sourceAttemptId,
    );

typedef AppContactDetailRouteBuilder =
    Widget Function(BuildContext context, String contactId);

/// 一次接触表单或详情页关闭后的路由结果。
///
/// 首页每次都刷新接触事实。只有 [submitted] 为 `true` 时显示提交成功提示。
final class ContactPageClosedEvent {
  const ContactPageClosedEvent({
    required this.sequence,
    required this.submitted,
  });

  const ContactPageClosedEvent.initial() : sequence = 0, submitted = false;

  final int sequence;
  final bool submitted;
}

/// 管理顶层地址、浏览器历史和接触表单页栈的路由模块。
///
/// 表单使用真实的 Navigator page，因此系统返回、浏览器返回和
/// AppBar 返回都会经过同一个 PopScope 草稿保存合同。
final class AppRouterDelegate extends RouterDelegate<AppRoute>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<AppRoute> {
  AppRouterDelegate({
    required this.rootBuilder,
    required this.contactBuilder,
    required this.contactDetailBuilder,
  });

  final AppRootRouteBuilder rootBuilder;
  final AppContactRouteBuilder contactBuilder;
  final AppContactDetailRouteBuilder contactDetailBuilder;
  final ValueNotifier<ContactPageClosedEvent> _contactPageClosedEvents =
      ValueNotifier(const ContactPageClosedEvent.initial());

  @override
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  AppRoute _route = AppRoute.today;
  AppRoute? _routeAfterContactOverlayPop;

  @override
  AppRoute get currentConfiguration => _route;

  void go(AppRoute route) {
    if (route == _route) {
      return;
    }
    _route = route;
    notifyListeners();
  }

  @override
  Future<void> setNewRoutePath(AppRoute configuration) async {
    if (_route == configuration) {
      return;
    }
    final navigator = navigatorKey.currentState;
    if (_route.isContactOverlay && navigator != null) {
      _routeAfterContactOverlayPop = configuration;
      final popped = await navigator.maybePop();
      if (popped) {
        return;
      }
      _routeAfterContactOverlayPop = null;
      return;
    }
    go(configuration);
  }

  @override
  Future<bool> popRoute() async {
    if (!_route.isContactOverlay) {
      return false;
    }
    return navigatorKey.currentState?.maybePop() ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navigatorKey,
      pages: [
        MaterialPage<void>(
          key: const ValueKey('app-root-route'),
          name: _rootLocation,
          child: rootBuilder(context, _route, _contactPageClosedEvents),
        ),
        if (_route.isContactEntry)
          MaterialPage<bool>(
            key: ValueKey(_route.location),
            name: _route.location,
            onPopInvoked: _contactOverlayPopped,
            child: contactBuilder(
              context,
              _route.draftId,
              _route.sourceAttemptId,
            ),
          ),
        if (_route.isContactDetail)
          MaterialPage<void>(
            key: ValueKey(_route.location),
            name: _route.location,
            onPopInvoked: (didPop, _) => _contactOverlayPopped(didPop, false),
            child: contactDetailBuilder(context, _route.contactId!),
          ),
      ],
      onDidRemovePage: (_) {},
    );
  }

  String get _rootLocation => switch (_route.primaryIndex) {
    0 => AppRoute.today.location,
    1 => AppRoute.contacts.location,
    2 => AppRoute.targets.location,
    _ => AppRoute.analysis.location,
  };

  void _contactOverlayPopped(bool didPop, bool? submitted) {
    if (!didPop) {
      return;
    }
    final destination = _routeAfterContactOverlayPop ?? AppRoute.contacts;
    _routeAfterContactOverlayPop = null;
    _contactPageClosedEvents.value = ContactPageClosedEvent(
      sequence: _contactPageClosedEvents.value.sequence + 1,
      submitted: submitted ?? false,
    );
    go(destination);
  }

  @override
  void dispose() {
    _contactPageClosedEvents.dispose();
    super.dispose();
  }
}
