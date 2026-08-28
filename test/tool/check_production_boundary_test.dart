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

  test(
    'production boundary traverses part and conditional directive branches',
    () async {
      final temporaryRoot = await Directory.systemTemp.createTemp(
        'tongxingzhe-production-boundary-directives-',
      );
      addTearDown(() => temporaryRoot.delete(recursive: true));
      final library = Directory('${temporaryRoot.path}/lib')..createSync();
      File(
        '${library.path}/main.dart',
      ).writeAsStringSync("import 'root.dart';\nvoid main() {}\n");
      File('${library.path}/root.dart').writeAsStringSync(
        "import 'import_base.dart'\n"
        "    if (dart.library.io) 'import_io.dart';\n"
        "export 'export_base.dart'\n"
        "    if (dart.library.io) 'export_io.dart';\n"
        "part 'root_part.dart';\n",
      );

      const leafFileNames = <String>[
        'root_part.dart',
        'import_base.dart',
        'import_io.dart',
        'export_base.dart',
        'export_io.dart',
      ];
      for (final fileName in leafFileNames) {
        final partOf = fileName == 'root_part.dart'
            ? "part of 'must_not_be_traversed.dart';\n"
            : '';
        File(
          '${library.path}/$fileName',
        ).writeAsStringSync('${partOf}final value = md5.convert([1, 2, 3]);\n');
      }

      final report = boundary.inspectProductionBoundary(temporaryRoot);

      expect(report.violations, hasLength(5));
      expect(
        report.violations.where(
          (violation) => violation.contains('找不到 production import'),
        ),
        isEmpty,
      );
      for (final fileName in leafFileNames) {
        expect(
          report.violations.where((violation) => violation.contains(fileName)),
          hasLength(1),
          reason: 'expected a boundary violation for $fileName',
        );
      }
      expect(report.visitedFileCount, 7);
    },
  );
}
