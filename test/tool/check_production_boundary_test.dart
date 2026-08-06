import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_production_boundary.dart' as boundary;

void main() {
  test('production boundary 允许 SHA-256 但仍拒绝 MD5', () async {
    final temporaryRoot = await Directory.systemTemp.createTemp(
      'tongxingzhe-production-boundary-',
    );
    addTearDown(() => temporaryRoot.delete(recursive: true));
    final library = Directory('${temporaryRoot.path}/lib')..createSync();
    File(
      '${library.path}/main.dart',
    ).writeAsStringSync("import 'sha_scope.dart';\nvoid main() {}\n");
    final scope = File('${library.path}/sha_scope.dart');
    scope.writeAsStringSync(
      "import 'package:crypto/crypto.dart';\n"
      "final value = sha256.convert([1, 2, 3]);\n",
    );

    final shaReport = boundary.inspectProductionBoundary(temporaryRoot);

    expect(shaReport.violations, isEmpty);

    scope.writeAsStringSync(
      "import 'package:crypto/crypto.dart';\n"
      "final value = md5.convert([1, 2, 3]);\n",
    );
    final md5Report = boundary.inspectProductionBoundary(temporaryRoot);

    expect(md5Report.violations, hasLength(1));
    expect(md5Report.violations.single, contains('MD5'));
  });
}
