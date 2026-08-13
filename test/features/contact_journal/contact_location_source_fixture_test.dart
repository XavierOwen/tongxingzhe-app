import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/data/local_database.dart';
import 'package:tongxingzhe_app/features/contact_journal/contact_journal.dart';
import 'package:tongxingzhe_app/features/contact_journal/contact_models.dart';
import 'package:tongxingzhe_app/foundation/runtime_values.dart';
import 'package:tongxingzhe_app/regions/region_catalog.dart';
import 'package:tongxingzhe_app/regions/region_models.dart';

void main() {
  test(
    'shared location source fixture preserves SQLite and Outbox facts',
    () async {
      final fixture = await _loadFixture();
      final database = LocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await RegionCatalog(database).installSnapshot(
        const CanonicalRegionSnapshot(
          version: 'regions-slice6v-v1',
          nodes: [
            CanonicalRegionNode(
              regionId: 'region-slice6v-country',
              canonicalName: 'Synthetic Country',
              kind: RegionKind.country,
            ),
            CanonicalRegionNode(
              regionId: 'region-slice6v-chicago',
              parentRegionId: 'region-slice6v-country',
              canonicalName: 'Chicago',
              kind: RegionKind.city,
            ),
            CanonicalRegionNode(
              regionId: 'region-slice6v-university',
              parentRegionId: 'region-slice6v-chicago',
              canonicalName: 'University of Chicago',
              kind: RegionKind.venue,
            ),
          ],
        ),
      );

      final ids = [
        for (final row in fixture) ...[
          'slice6v-${row.caseName}',
          'slice6v-${row.caseName}-revision',
          'slice6v-${row.caseName}-command',
        ],
      ];
      final journal = ContactJournal(
        database: database,
        clock: const _FixedClock(),
        idGenerator: _SequenceIdGenerator(ids),
      );

      for (var index = 0; index < fixture.length; index += 1) {
        final row = fixture[index];
        final contactId = 'slice6v-${row.caseName}';
        await journal.submitAnonymousContact(
          AnonymousContactSubmission(
            appUserId: 'synthetic-slice6v-owner',
            workspaceId: 'slice6v-workspace',
            projectId: 'slice6v-project',
            questionnaireVersionId: 'questionnaire-v1',
            deviceId: 'slice6v-device',
            occurredAtUtc: DateTime.utc(2030, 1, 8, 17, index),
            occurredTimeZone: 'America/Chicago',
            channel: ContactChannel.fromStorage(row.channel),
            location: row.location,
            reachCount: 1,
            interestLevel: 2,
          ),
        );

        final stored = await (database.select(
          database.dbContactRecords,
        )..where((record) => record.contactId.equals(contactId))).getSingle();
        final expectedSource = row.locationSource;
        expect(
          row.expectedEvidenceKind,
          expectedSource != null
              ? 'resolved_from_coordinates'
              : switch (row.location) {
                  ResolvedContactLocation() => 'resolved_region_only',
                  PendingContactLocation() => 'pending_coordinates',
                  NotApplicableContactLocation() => 'not_applicable',
                },
        );
        expect(stored.locationKind, row.locationKind);
        expect(stored.placeName, row.placeName);
        expect(stored.smallestRegionId, row.smallestRegionId);
        expect(stored.regionTreeVersion, row.regionTreeVersion);
        expect(stored.latitude, row.locationLatitude);
        expect(stored.longitude, row.locationLongitude);
        expect(stored.locationAccuracyMeters, row.locationAccuracyMeters);
        expect(
          stored.locationSourceKind,
          expectedSource == null ? isNull : 'captured_coordinates',
        );
        expect(stored.locationSourceLatitude, expectedSource?.latitude);
        expect(stored.locationSourceLongitude, expectedSource?.longitude);
        expect(
          stored.locationSourceAccuracyMeters,
          expectedSource?.accuracyMeters,
        );
        expect(
          stored.locationSourceResolverContractVersion,
          expectedSource?.resolverContractVersion,
        );
        expect(
          stored.locationSourceRegionTreeContentFingerprint,
          expectedSource?.regionTreeContentFingerprint,
        );

        final outbox =
            await (database.select(database.dbSyncOutbox)
                  ..where((command) => command.aggregateId.equals(contactId)))
                .getSingle();
        final payload = jsonDecode(outbox.payloadJson) as Map<String, dynamic>;
        expect(payload['location'], row.locationWire);
        expect(payload['location_source'], row.locationSourceWire);
        if (row.caseName == 'malformed_fingerprint') {
          // A 64-hex fingerprint is syntactically valid locally. Its meaning is
          // established by the published region tree on the remote boundary.
          expect(row.expectedFailureCode, 'invalid_location_source');
          expect(
            (payload['location_source']
                as Map<String, dynamic>)['region_tree_content_fingerprint'],
            '0' * 64,
          );
        }
      }
    },
  );
}

final class _FixtureRow {
  const _FixtureRow({
    required this.caseName,
    required this.channel,
    required this.location,
    required this.locationSource,
    required this.expectedEvidenceKind,
    required this.expectedFailureCode,
  });

  final String caseName;
  final String channel;
  final ContactLocation location;
  final CapturedCoordinatesLocationSource? locationSource;
  final String expectedEvidenceKind;
  final String expectedFailureCode;

  String get locationKind => switch (location) {
    ResolvedContactLocation() => 'resolved',
    PendingContactLocation() => 'pending_resolution',
    NotApplicableContactLocation() => 'not_applicable',
  };

  String? get placeName => switch (location) {
    ResolvedContactLocation value => value.placeName,
    _ => null,
  };

  String? get smallestRegionId => switch (location) {
    ResolvedContactLocation value => value.smallestRegionId,
    _ => null,
  };

  String? get regionTreeVersion => switch (location) {
    ResolvedContactLocation value => value.regionTreeVersion,
    _ => null,
  };

  double? get locationLatitude => switch (location) {
    PendingContactLocation value => value.latitude,
    _ => null,
  };

  double? get locationLongitude => switch (location) {
    PendingContactLocation value => value.longitude,
    _ => null,
  };

  double? get locationAccuracyMeters => switch (location) {
    PendingContactLocation value => value.accuracyMeters,
    _ => null,
  };

  Map<String, Object?> get locationWire => switch (location) {
    ResolvedContactLocation value => {
      'kind': 'resolved',
      'place_name': value.placeName,
      'smallest_region_id': value.smallestRegionId,
      'region_tree_version': value.regionTreeVersion,
      'latitude': null,
      'longitude': null,
      'accuracy_meters': null,
    },
    PendingContactLocation value => {
      'kind': 'pending_resolution',
      'place_name': null,
      'smallest_region_id': null,
      'region_tree_version': null,
      'latitude': value.latitude,
      'longitude': value.longitude,
      'accuracy_meters': value.accuracyMeters,
    },
    NotApplicableContactLocation() => {
      'kind': 'not_applicable',
      'place_name': null,
      'smallest_region_id': null,
      'region_tree_version': null,
      'latitude': null,
      'longitude': null,
      'accuracy_meters': null,
    },
  };

  Map<String, Object?>? get locationSourceWire => locationSource == null
      ? null
      : {
          'kind': 'captured_coordinates',
          'latitude': locationSource!.latitude,
          'longitude': locationSource!.longitude,
          'accuracy_meters': locationSource!.accuracyMeters,
          'resolver_contract_version': locationSource!.resolverContractVersion,
          'region_tree_content_fingerprint':
              locationSource!.regionTreeContentFingerprint,
        };
}

Future<List<_FixtureRow>> _loadFixture() async {
  final lines = await File(
    'backend/database/fixtures/shared/contact_location_source_v1.csv',
  ).readAsLines();
  const header =
      'case_name,channel,location_json,location_source_json,'
      'expected_evidence_kind,expected_failure_code';
  if (lines.isEmpty || lines.first != header) {
    throw const FormatException(
      'invalid contact location source fixture header',
    );
  }
  return [
    for (final line in lines.skip(1))
      if (line.trim().isNotEmpty) _parseFixtureRow(_csvFields(line)),
  ];
}

_FixtureRow _parseFixtureRow(List<String> fields) {
  if (fields.length != 6) {
    throw const FormatException('invalid contact location source fixture row');
  }
  final location = _locationFromJson(
    Map<String, Object?>.from(jsonDecode(fields[2]) as Map),
    fields[3].isEmpty
        ? null
        : Map<String, Object?>.from(jsonDecode(fields[3]) as Map),
  );
  final source = location is ResolvedContactLocation ? location.source : null;
  return _FixtureRow(
    caseName: fields[0],
    channel: fields[1],
    location: location,
    locationSource: source,
    expectedEvidenceKind: fields[4],
    expectedFailureCode: fields[5],
  );
}

ContactLocation _locationFromJson(
  Map<String, Object?> location,
  Map<String, Object?>? source,
) => switch (location['kind']) {
  'resolved' => ResolvedContactLocation(
    placeName: location['placeName']! as String,
    smallestRegionId: location['smallestRegionId']! as String,
    regionTreeVersion: location['regionTreeVersion']! as String,
    source: source == null ? null : _sourceFromJson(source),
  ),
  'pending_resolution' => PendingContactLocation(
    latitude: (location['latitude']! as num).toDouble(),
    longitude: (location['longitude']! as num).toDouble(),
    accuracyMeters: (location['accuracyMeters'] as num?)?.toDouble(),
  ),
  'not_applicable' => const NotApplicableContactLocation(),
  _ => throw FormatException(
    'unsupported fixture location ${location['kind']}',
  ),
};

CapturedCoordinatesLocationSource _sourceFromJson(
  Map<String, Object?> source,
) => CapturedCoordinatesLocationSource(
  latitude: (source['latitude']! as num).toDouble(),
  longitude: (source['longitude']! as num).toDouble(),
  accuracyMeters: (source['accuracyMeters'] as num?)?.toDouble(),
  resolverContractVersion: source['resolverContractVersion']! as String,
  regionTreeContentFingerprint:
      source['regionTreeContentFingerprint']! as String,
);

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

final class _FixedClock implements AppClock {
  const _FixedClock();

  @override
  DateTime now() => DateTime.utc(2030, 1, 8, 18, 30);
}

final class _SequenceIdGenerator implements IdGenerator {
  _SequenceIdGenerator(this.values);

  final List<String> values;
  var _index = 0;

  @override
  String next() => values[_index++];
}
