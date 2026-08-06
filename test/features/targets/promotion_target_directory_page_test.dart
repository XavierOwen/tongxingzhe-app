import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/features/targets/promotion_target_directory_page.dart';
import 'package:tongxingzhe_app/foundation/runtime_values.dart';
import 'package:tongxingzhe_app/l10n/app_strings.dart';
import 'package:tongxingzhe_app/targets/promotion_target.dart';

void main() {
  testWidgets(
    'anonymous contact remains available when the directory is empty',
    (tester) async {
      await tester.pumpWidget(_app(_MemoryGateway()));
      await tester.pumpAndSettle();

      expect(find.text('尚未建立推广对象'), findsOneWidget);
      expect(find.text('不建立对象不会影响记录接触。'), findsOneWidget);
    },
  );

  testWidgets('creation requires an explicit purpose confirmation', (
    tester,
  ) async {
    final gateway = _MemoryGateway();
    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('create-promotion-target')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('promotion-target-name')),
      '王小明',
    );

    var confirm = tester.widget<FilledButton>(
      find.byKey(const ValueKey('confirm-promotion-target')),
    );
    expect(confirm.onPressed, isNull);

    await tester.tap(
      find.byKey(const ValueKey('promotion-target-purpose-confirmed')),
    );
    await tester.pump();
    confirm = tester.widget<FilledButton>(
      find.byKey(const ValueKey('confirm-promotion-target')),
    );
    expect(confirm.onPressed, isNotNull);

    await tester.tap(find.byKey(const ValueKey('confirm-promotion-target')));
    await tester.pumpAndSettle();

    expect(gateway.createdName, '王小明');
    expect(gateway.requestId, 'request-1');
    expect(find.text('王小明'), findsOneWidget);
  });
}

Widget _app(PromotionTargetGateway gateway) => MaterialApp(
  home: Scaffold(
    body: PromotionTargetDirectoryPage(
      text: const AppStrings('zh'),
      gateway: gateway,
      idGenerator: _FixedIds(),
      canCreate: true,
    ),
  ),
);

final class _FixedIds implements IdGenerator {
  @override
  String next() => 'request-1';
}

final class _MemoryGateway implements PromotionTargetGateway {
  final targets = <PromotionTargetProfile>[];
  String? createdName;
  String? requestId;

  @override
  Future<PromotionTargetResult<List<PromotionTargetProfile>>>
  loadAssigned() async => PromotionTargetSuccess(List.of(targets));

  @override
  Future<PromotionTargetResult<PromotionTargetProfile>> create({
    required PromotionTargetType type,
    required String displayName,
    required String? phone,
    required String? email,
    required String requestId,
  }) async {
    createdName = displayName;
    this.requestId = requestId;
    final target = PromotionTargetProfile(
      id: 'target-1',
      type: type,
      displayName: displayName,
      phone: phone,
      email: email,
      createdAtUtc: DateTime.utc(2026, 8, 6),
    );
    targets.add(target);
    return PromotionTargetSuccess(target);
  }

  @override
  Future<void> close() async {}
}
