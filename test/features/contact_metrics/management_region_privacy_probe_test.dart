import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/features/contact_metrics/management_region_privacy_probe.dart';

void main() {
  test('Dart 与 PostgreSQL 共用全部区域隐私威胁场景', () async {
    final fixture = await _loadFixture();
    final base = fixture.singleWhere((row) => row.scenario == 'base').patch;

    for (final row in fixture) {
      if (row.expectedStatus == 'malformed') {
        expect(
          () => ManagementRegionPrivacyProbeV1.assess({...base, ...row.patch}),
          throwsArgumentError,
          reason: row.scenario,
        );
        continue;
      }
      final assessment = ManagementRegionPrivacyProbeV1.assess({
        ...base,
        ...row.patch,
      });

      expect(assessment.resultStatus, row.expectedStatus, reason: row.scenario);
      expect(assessment.reasonCodes, row.expectedReasons, reason: row.scenario);
      expect(assessment.toJson().keys, {
        'probe_id',
        'query_fingerprint',
        'result_status',
        'reason_codes',
      });
      expect(
        jsonEncode(assessment.toJson()),
        isNot(
          matches(
            RegExp(
              'value_count|contributor|latitude|longitude|city-a|campus-a|regions-v[12]',
            ),
          ),
        ),
      );
    }
  });

  test('有原始来源时待解析和非线下地点可保持不同并合法排除', () async {
    final fixture = await _loadFixture();
    final base = fixture.singleWhere((row) => row.scenario == 'base').patch;

    final assessment = ManagementRegionPrivacyProbeV1.assess(base);

    expect(assessment.resultStatus, 'approved');
    expect(assessment.reasonCodes, isEmpty);
  });

  test('缺字段、额外字段、负数和伪造隐藏值属于 malformed', () async {
    final fixture = await _loadFixture();
    final base = fixture.singleWhere((row) => row.scenario == 'base').patch;

    final extra = _copy(base)..['unexpected'] = true;
    final missing = _copy(base)..remove('tree_version');
    final negative = _copy(base);
    _firstCell(negative)['value_count'] = -1;
    final leakedSuppressed = _copy(base);
    _firstCell(leakedSuppressed)
      ..['privacy_status'] = 'suppressed'
      ..['value_count'] = 9;

    for (final probe in [extra, missing, negative, leakedSuppressed]) {
      expect(
        () => ManagementRegionPrivacyProbeV1.assess(probe),
        throwsArgumentError,
      );
    }
  });
}

final class _FixtureRow {
  const _FixtureRow({
    required this.scenario,
    required this.patch,
    required this.expectedStatus,
    required this.expectedReasons,
  });

  final String scenario;
  final Map<String, Object?> patch;
  final String expectedStatus;
  final List<String> expectedReasons;
}

Future<List<_FixtureRow>> _loadFixture() async {
  final lines = await File(
    'backend/database/fixtures/shared/management_region_privacy_v1.csv',
  ).readAsLines();
  const header = 'scenario,probe_patch,expected_status,expected_reason_codes';
  if (lines.isEmpty || lines.first != header) {
    throw const FormatException('invalid region privacy fixture header');
  }
  return [
    for (final line in lines.skip(1))
      if (line.trim().isNotEmpty) _fixtureRow(_csvFields(line)),
  ];
}

_FixtureRow _fixtureRow(List<String> fields) {
  if (fields.length != 4) {
    throw const FormatException('invalid region privacy fixture row');
  }
  return _FixtureRow(
    scenario: fields[0],
    patch: Map<String, Object?>.from(jsonDecode(fields[1]) as Map),
    expectedStatus: fields[2],
    expectedReasons: List<String>.from(jsonDecode(fields[3]) as List),
  );
}

List<String> _csvFields(String line) {
  final fields = <String>[];
  final field = StringBuffer();
  var quoted = false;
  for (var index = 0; index < line.length; index += 1) {
    final character = line[index];
    if (character == '"') {
      if (quoted && index + 1 < line.length && line[index + 1] == '"') {
        field.write('"');
        index += 1;
      } else {
        quoted = !quoted;
      }
    } else if (character == ',' && !quoted) {
      fields.add(field.toString());
      field.clear();
    } else {
      field.write(character);
    }
  }
  if (quoted) throw const FormatException('unterminated CSV field');
  fields.add(field.toString());
  return fields;
}

Map<String, Object?> _copy(Map<String, Object?> source) =>
    Map<String, Object?>.from(jsonDecode(jsonEncode(source)) as Map);

Map<dynamic, dynamic> _firstCell(Map<String, Object?> probe) {
  final reports = probe['reports']! as List<Object?>;
  final report = reports.first as Map<dynamic, dynamic>;
  final cells = report['cells']! as List<Object?>;
  return cells.first as Map<dynamic, dynamic>;
}
