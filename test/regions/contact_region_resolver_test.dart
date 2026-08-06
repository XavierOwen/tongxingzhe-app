import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tongxingzhe_app/data/local_database.dart';
import 'package:tongxingzhe_app/features/contact_journal/contact_models.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/regions/contact_region_resolver.dart';
import 'package:tongxingzhe_app/regions/region_catalog.dart';

import '../support/fake_identity_session.dart';

void main() {
  test('Backend 命中后安装规范父链并返回最小区域', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final identity = _signedInIdentity();
    final resolver = HttpContactRegionResolver(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: identity,
      regionCatalog: RegionCatalog(database),
      client: MockClient((request) async {
        expect(request.url.path, '/v1/regions/resolve');
        expect(
          request.headers['authorization'],
          'Bearer test-only-access-token',
        );
        expect(jsonDecode(request.body), {
          'latitude': 41.7897,
          'longitude': -87.5997,
        });
        return http.Response(jsonEncode(_resolvedBody), 200);
      }),
    );
    addTearDown(resolver.close);

    final result = await resolver.resolve(_pending);

    expect(
      result,
      const ResolvedContactLocation(
        placeName: 'University of Chicago',
        smallestRegionId: 'uchicago',
        regionTreeVersion: 'synthetic-v1',
      ),
    );
    final path = await RegionCatalog(
      database,
    ).ancestorPath(regionId: 'uchicago', treeVersion: 'synthetic-v1');
    expect(path.map((node) => node.regionId), ['uchicago', 'chicago']);
  });

  test('Backend 未命中时保留原坐标和待解析状态', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final resolver = HttpContactRegionResolver(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: _signedInIdentity(),
      regionCatalog: RegionCatalog(database),
      client: MockClient(
        (_) async => http.Response(jsonEncode({'result': 'pending'}), 202),
      ),
    );
    addTearDown(resolver.close);

    expect(await resolver.resolve(_pending), same(_pending));
  });

  test('Backend 拒绝旧 token 后强制刷新一次并重试', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final identity = _signedInIdentity();
    var requestCount = 0;
    final resolver = HttpContactRegionResolver(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: identity,
      regionCatalog: RegionCatalog(database),
      client: MockClient((_) async {
        requestCount++;
        return requestCount == 1
            ? http.Response('{}', 401)
            : http.Response(jsonEncode(_resolvedBody), 200);
      }),
    );
    addTearDown(resolver.close);

    expect(await resolver.resolve(_pending), isA<ResolvedContactLocation>());
    expect(requestCount, 2);
    expect(identity.accessTokenForceRefreshValues, [false, true]);
  });

  test('Backend 返回断裂父链时不接受伪造的已解析地点', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final resolver = HttpContactRegionResolver(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: _signedInIdentity(),
      regionCatalog: RegionCatalog(database),
      client: MockClient((_) async {
        final body = Map<String, Object?>.from(_resolvedBody);
        body['region_tree'] = {
          'version': 'synthetic-v1',
          'nodes': [
            {
              'region_id': 'uchicago',
              'parent_region_id': 'missing-city',
              'canonical_name': 'University of Chicago',
              'kind': 'institution',
              'attributes': ['campus'],
            },
          ],
        };
        return http.Response(jsonEncode(body), 200);
      }),
    );
    addTearDown(resolver.close);

    expect(await resolver.resolve(_pending), same(_pending));
  });
}

FakeIdentitySession _signedInIdentity() => FakeIdentitySession(
  initial: IdentitySnapshot(
    stage: IdentityStage.signedIn,
    principal: const IdentityPrincipal(
      externalSubject: 'subject',
      email: 'person@example.test',
    ),
    expiresAt: DateTime.utc(2030, 1, 2, 4),
  ),
);

const _pending = PendingContactLocation(
  latitude: 41.7897,
  longitude: -87.5997,
  accuracyMeters: 8.5,
);

const _resolvedBody = <String, Object?>{
  'result': 'resolved',
  'location': {
    'kind': 'resolved',
    'place_name': 'University of Chicago',
    'smallest_region_id': 'uchicago',
    'region_tree_version': 'synthetic-v1',
  },
  'region_tree': {
    'version': 'synthetic-v1',
    'nodes': [
      {
        'region_id': 'chicago',
        'parent_region_id': null,
        'canonical_name': 'Chicago',
        'kind': 'city',
        'attributes': <String>[],
      },
      {
        'region_id': 'uchicago',
        'parent_region_id': 'chicago',
        'canonical_name': 'University of Chicago',
        'kind': 'institution',
        'attributes': ['campus'],
      },
    ],
  },
};
