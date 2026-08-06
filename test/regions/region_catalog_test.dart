import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/data/local_database.dart';
import 'package:tongxingzhe_app/features/contact_journal/contact_journal.dart';
import 'package:tongxingzhe_app/features/contact_journal/contact_models.dart';
import 'package:tongxingzhe_app/foundation/runtime_values.dart';
import 'package:tongxingzhe_app/regions/region_catalog.dart';
import 'package:tongxingzhe_app/regions/region_models.dart';

void main() {
  test('规范区域快照形成唯一父级树并从最小区域推导全部上级', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final catalog = RegionCatalog(database);

    await catalog.installSnapshot(_chicagoTree);

    final path = await catalog.ancestorPath(
      regionId: 'region-uchicago',
      treeVersion: 'regions-2030-01',
    );
    expect(path.map((node) => node.regionId), [
      'region-uchicago',
      'region-south-side',
      'region-chicago',
      'region-il',
    ]);
    expect(path.first.attributes, {'campus'});
  });

  test('规范区域快照拒绝环和不存在的父级', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final catalog = RegionCatalog(database);

    await expectLater(
      catalog.installSnapshot(
        const CanonicalRegionSnapshot(
          version: 'bad-tree',
          nodes: [
            CanonicalRegionNode(
              regionId: 'a',
              parentRegionId: 'b',
              canonicalName: 'A',
              kind: RegionKind.city,
            ),
            CanonicalRegionNode(
              regionId: 'b',
              parentRegionId: 'a',
              canonicalName: 'B',
              kind: RegionKind.adminArea,
            ),
          ],
        ),
      ),
      throwsA(
        isA<RegionCatalogException>().having(
          (error) => error.code,
          'code',
          'region_tree_cycle',
        ),
      ),
    );
  });

  test('已解析接触必须引用含城市上级的规范区域版本', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final catalog = RegionCatalog(database);
    final journal = ContactJournal(
      database: database,
      clock: const _FixedClock(),
      idGenerator: _SequenceIdGenerator([
        'contact-region',
        'revision-region',
        'command-region',
      ]),
    );
    final submission = AnonymousContactSubmission(
      appUserId: 'app-user-1',
      workspaceId: 'workspace-1',
      projectId: 'project-1',
      questionnaireVersionId: 'questionnaire-1',
      deviceId: 'device-1',
      occurredAtUtc: _FixedClock.value,
      occurredTimeZone: 'America/Chicago',
      channel: ContactChannel.faceToFace,
      location: ResolvedContactLocation(
        placeName: 'University of Chicago',
        smallestRegionId: 'region-uchicago',
        regionTreeVersion: 'regions-2030-01',
      ),
      reachCount: 1,
      interestLevel: 2,
    );

    await expectLater(
      journal.submitAnonymousContact(submission),
      throwsA(
        isA<ContactValidationException>().having(
          (error) => error.code,
          'code',
          'resolved_region_unknown',
        ),
      ),
    );

    await catalog.installSnapshot(_chicagoTree);
    await journal.submitAnonymousContact(submission);

    final assignments = await database
        .select(database.dbContactRegionAssignments)
        .get();
    expect(assignments, hasLength(1));
    expect(assignments.single.contactId, 'contact-region');
    expect(assignments.single.regionVersionKey, contains('region-uchicago'));
  });
}

const _chicagoTree = CanonicalRegionSnapshot(
  version: 'regions-2030-01',
  nodes: [
    CanonicalRegionNode(
      regionId: 'region-il',
      canonicalName: 'Illinois',
      kind: RegionKind.adminArea,
    ),
    CanonicalRegionNode(
      regionId: 'region-chicago',
      parentRegionId: 'region-il',
      canonicalName: 'Chicago',
      kind: RegionKind.city,
    ),
    CanonicalRegionNode(
      regionId: 'region-south-side',
      parentRegionId: 'region-chicago',
      canonicalName: 'Chicago South',
      kind: RegionKind.district,
    ),
    CanonicalRegionNode(
      regionId: 'region-uchicago',
      parentRegionId: 'region-south-side',
      canonicalName: 'University of Chicago',
      kind: RegionKind.institution,
      attributes: {'campus'},
    ),
  ],
);

final class _FixedClock implements AppClock {
  const _FixedClock();

  static final value = DateTime.utc(2030, 1, 8, 17);

  @override
  DateTime now() => value;
}

final class _SequenceIdGenerator implements IdGenerator {
  _SequenceIdGenerator(this.values);

  final List<String> values;
  var index = 0;

  @override
  String next() => values[index++];
}
