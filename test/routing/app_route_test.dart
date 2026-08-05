import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/routing/app_route.dart';

void main() {
  const parser = AppRouteInformationParser();

  test('主页和接触编辑器都有稳定往返地址', () async {
    final cases = <String, AppRoute>{
      '/today': AppRoute.today,
      '/contacts': AppRoute.contacts,
      '/contacts/new': AppRoute.newContact,
      '/contacts/drafts/draft%20one': const AppRoute.contactDraft('draft one'),
      '/targets': AppRoute.targets,
      '/analysis': AppRoute.analysis,
    };

    for (final entry in cases.entries) {
      final parsed = await parser.parseRouteInformation(
        RouteInformation(uri: Uri.parse(entry.key)),
      );
      expect(parsed, entry.value);
      expect(parser.restoreRouteInformation(parsed).uri.path, entry.key);
    }
  });

  test('根地址和未知地址都安全回到今日', () async {
    for (final path in ['/', '/not-a-real-page']) {
      final parsed = await parser.parseRouteInformation(
        RouteInformation(uri: Uri.parse(path)),
      );
      expect(parsed, AppRoute.today);
    }
  });
}
