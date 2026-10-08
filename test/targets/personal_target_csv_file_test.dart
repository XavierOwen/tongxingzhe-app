import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:file_selector/file_selector.dart';
import 'package:tongxingzhe_app/targets/personal_target_csv_file.dart';
import 'package:tongxingzhe_app/targets/personal_target_csv_import.dart';

void main() {
  test('cancel returns null without reading a file', () async {
    expect(await readPersonalTargetCsvFile(null), isNull);
  });

  test('reads exactly 1 MiB from an unknown-length stream', () async {
    final bytes = Uint8List(personalTargetCsvImportMaxFileBytes);
    final read = await readPersonalTargetCsvBytes(
      Stream<List<int>>.value(bytes),
    );
    expect(read.length, personalTargetCsvImportMaxFileBytes);
  });

  test('reads selected XFile bytes through its stream', () async {
    final file = XFile.fromData(Uint8List.fromList([1, 2, 3]));
    expect(await readPersonalTargetCsvFile(file), [1, 2, 3]);
  });

  test('rejects a stream that actually exceeds 1 MiB', () async {
    final stream = Stream<List<int>>.fromIterable([
      List<int>.filled(personalTargetCsvImportMaxFileBytes, 0),
      [1],
    ]);
    await expectLater(
      readPersonalTargetCsvBytes(stream),
      throwsA(isA<PersonalTargetCsvFileTooLarge>()),
    );
  });
}
