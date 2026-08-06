import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

enum AppRouteKind {
  today,
  contacts,
  targets,
  analysis,
  newContact,
  contactDraft,
  contactFromAttempt,
}

/// App 内可恢复的稳定地址。
///
/// 路径只表达导航事实。它不携带可伪造的用户、空间或项目
/// 权限；页面所用的这些值仍来自 [AppSession] 的可信上下文。
final class AppRoute {
  const AppRoute._(this.kind, [this.draftId, this.sourceAttemptId]);

  static const today = AppRoute._(AppRouteKind.today);
  static const contacts = AppRoute._(AppRouteKind.contacts);
  static const targets = AppRoute._(AppRouteKind.targets);
  static const analysis = AppRoute._(AppRouteKind.analysis);
  static const newContact = AppRoute._(AppRouteKind.newContact);

  const AppRoute.contactDraft(String draftId)
    : this._(AppRouteKind.contactDraft, draftId);

  const AppRoute.contactFromAttempt(String attemptId)
    : this._(AppRouteKind.contactFromAttempt, null, attemptId);

  final AppRouteKind kind;
  final String? draftId;
  final String? sourceAttemptId;

  bool get isContactEntry =>
      kind == AppRouteKind.newContact ||
      kind == AppRouteKind.contactDraft ||
      kind == AppRouteKind.contactFromAttempt;

  int get primaryIndex => switch (kind) {
    AppRouteKind.today => 0,
    AppRouteKind.contacts ||
    AppRouteKind.newContact ||
    AppRouteKind.contactDraft => 1,
    AppRouteKind.contactFromAttempt => 1,
    AppRouteKind.targets => 2,
    AppRouteKind.analysis => 3,
  };

  String get location => switch (kind) {
    AppRouteKind.today => '/today',
    AppRouteKind.contacts => '/contacts',
    AppRouteKind.targets => '/targets',
    AppRouteKind.analysis => '/analysis',
    AppRouteKind.newContact => '/contacts/new',
    AppRouteKind.contactDraft =>
      '/contacts/drafts/${Uri.encodeComponent(draftId!)}',
    AppRouteKind.contactFromAttempt =>
      '/contacts/attempts/${Uri.encodeComponent(sourceAttemptId!)}/contact',
  };

  @override
  bool operator ==(Object other) =>
      other is AppRoute &&
      other.kind == kind &&
      other.draftId == draftId &&
      other.sourceAttemptId == sourceAttemptId;

  @override
  int get hashCode => Object.hash(kind, draftId, sourceAttemptId);

  @override
  String toString() => 'AppRoute($location)';
}

/// URL 与类型化 [AppRoute] 之间的唯一转换边界。
final class AppRouteInformationParser extends RouteInformationParser<AppRoute> {
  const AppRouteInformationParser();

  @override
  Future<AppRoute> parseRouteInformation(RouteInformation routeInformation) {
    final segments = routeInformation.uri.pathSegments;
    final route = switch (segments) {
      [] => AppRoute.today,
      ['today'] => AppRoute.today,
      ['contacts'] => AppRoute.contacts,
      ['contacts', 'new'] => AppRoute.newContact,
      ['contacts', 'drafts', final draftId] when draftId.trim().isNotEmpty =>
        AppRoute.contactDraft(draftId),
      ['contacts', 'attempts', final attemptId, 'contact']
          when attemptId.trim().isNotEmpty =>
        AppRoute.contactFromAttempt(attemptId),
      ['targets'] => AppRoute.targets,
      ['analysis'] => AppRoute.analysis,
      _ => AppRoute.today,
    };
    return SynchronousFuture(route);
  }

  @override
  RouteInformation restoreRouteInformation(AppRoute configuration) {
    return RouteInformation(uri: Uri.parse(configuration.location));
  }
}
