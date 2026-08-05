import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_route.dart';

typedef AppRootRouteBuilder =
    Widget Function(
      BuildContext context,
      AppRoute route,
      ValueListenable<int> contactSubmissionEvents,
    );

typedef AppContactRouteBuilder =
    Widget Function(BuildContext context, String? draftId);

/// 管理顶层地址、浏览器历史和接触表单页栈的路由模块。
///
/// 表单使用真实的 Navigator page，因此系统返回、浏览器返回和
/// AppBar 返回都会经过同一个 PopScope 草稿保存合同。
final class AppRouterDelegate extends RouterDelegate<AppRoute>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<AppRoute> {
  AppRouterDelegate({required this.rootBuilder, required this.contactBuilder});

  final AppRootRouteBuilder rootBuilder;
  final AppContactRouteBuilder contactBuilder;
  final ValueNotifier<int> _contactSubmissionEvents = ValueNotifier(0);

  @override
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  AppRoute _route = AppRoute.today;
  AppRoute? _routeAfterEntryPop;

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
    if (_route.isContactEntry && navigator != null) {
      _routeAfterEntryPop = configuration;
      final popped = await navigator.maybePop();
      if (popped) {
        return;
      }
      _routeAfterEntryPop = null;
      return;
    }
    go(configuration);
  }

  @override
  Future<bool> popRoute() async {
    if (!_route.isContactEntry) {
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
          child: rootBuilder(context, _route, _contactSubmissionEvents),
        ),
        if (_route.isContactEntry)
          MaterialPage<bool>(
            key: ValueKey(_route.location),
            name: _route.location,
            onPopInvoked: _contactPagePopped,
            child: contactBuilder(context, _route.draftId),
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

  void _contactPagePopped(bool didPop, bool? submitted) {
    if (!didPop) {
      return;
    }
    final destination = _routeAfterEntryPop ?? AppRoute.contacts;
    _routeAfterEntryPop = null;
    if (submitted ?? false) {
      _contactSubmissionEvents.value++;
    }
    go(destination);
  }

  @override
  void dispose() {
    _contactSubmissionEvents.dispose();
    super.dispose();
  }
}
