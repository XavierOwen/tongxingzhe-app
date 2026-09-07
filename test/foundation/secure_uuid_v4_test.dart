import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/foundation/runtime_values.dart';

void main() {
  test('generates distinct canonical lowercase UUID v4 values', () {
    final first = secureUuidV4();
    final second = secureUuidV4();

    expect(
      first,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(second, isNot(first));
  });
}
