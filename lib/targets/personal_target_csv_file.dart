import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import 'personal_target_csv_import.dart';

final class PersonalTargetCsvFileTooLarge implements Exception {
  const PersonalTargetCsvFileTooLarge();
}

Future<Uint8List?> readPersonalTargetCsvFile(XFile? file) =>
    file == null ? Future.value() : readPersonalTargetCsvBytes(file.openRead());

Future<Uint8List> readPersonalTargetCsvBytes(Stream<List<int>> stream) async {
  final builder = BytesBuilder(copy: false);
  var length = 0;
  await for (final chunk in stream) {
    final remaining = personalTargetCsvImportMaxFileBytes + 1 - length;
    if (chunk.length > remaining) {
      builder.add(chunk.sublist(0, remaining));
      throw const PersonalTargetCsvFileTooLarge();
    }
    builder.add(chunk);
    length += chunk.length;
    if (length > personalTargetCsvImportMaxFileBytes) {
      throw const PersonalTargetCsvFileTooLarge();
    }
  }
  return builder.takeBytes();
}
