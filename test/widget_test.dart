import 'package:flutter/material.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tongxingzhe_app/app/app_controller.dart';
import 'package:tongxingzhe_app/data/local_database.dart';
import 'package:tongxingzhe_app/main.dart';

void main() {
  testWidgets('starts at login, switches language, and logs in', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = AppController(
      database: LocalDatabase(NativeDatabase.memory()),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(TongxingzheApp(controller: controller));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('同行者'), findsOneWidget);
    expect(find.text('登录'), findsWidgets);

    await tester.tap(find.text('EN'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Outreach Companion'), findsOneWidget);
    expect(find.text('Login'), findsWidgets);

    await tester.enterText(find.byType(EditableText).at(0), 'admin1');
    await tester.enterText(find.byType(EditableText).at(1), 'admin1');
    await tester.tap(find.widgetWithText(FilledButton, 'Login'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Quick Record'), findsOneWidget);

    await tester.tap(find.text('Charts'));
    await tester.pumpAndSettle();
    expect(find.text('By day'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final analyticsList = find.byType(ListView).first;
    await tester.drag(analyticsList, const Offset(0, -650));
    await tester.pumpAndSettle();
    expect(find.text('By area'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.drag(analyticsList, const Offset(0, -360));
    await tester.pumpAndSettle();
    expect(find.text('By identity'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
