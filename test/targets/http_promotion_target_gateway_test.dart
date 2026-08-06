import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/targets/http_promotion_target_gateway.dart';
import 'package:tongxingzhe_app/targets/promotion_target.dart';

import '../support/fake_identity_session.dart';

void main() {
  test(
    'creates a target with bearer auth and a server-generated target id',
    () async {
      final gateway = HttpPromotionTargetGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: _signedInIdentity(),
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/v1/promotion-targets');
          expect(
            request.headers['authorization'],
            'Bearer test-only-access-token',
          );
          expect(jsonDecode(request.body), {
            'target_type': 'institution',
            'display_name': '社区中心',
            'phone': null,
            'email': 'contact@example.test',
            'request_id': 'request-1',
          });
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'target': {
                  'target_id': '44444444-4444-4444-8444-444444444444',
                  'target_type': 'institution',
                  'display_name': '社区中心',
                  'phone': null,
                  'email': 'contact@example.test',
                  'created_at': '2026-08-06T12:00:00Z',
                },
              }),
            ),
            201,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final result = await gateway.create(
        type: PromotionTargetType.institution,
        displayName: '社区中心',
        phone: null,
        email: 'contact@example.test',
        requestId: 'request-1',
      );

      final target =
          (result as PromotionTargetSuccess<PromotionTargetProfile>).value;
      expect(target.id, '44444444-4444-4444-8444-444444444444');
      expect(target.type, PromotionTargetType.institution);
    },
  );

  test('loads only the assigned profiles returned by the server', () async {
    final gateway = HttpPromotionTargetGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: _signedInIdentity(),
      client: MockClient((request) async {
        expect(request.method, 'GET');
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'targets': [
                {
                  'target_id': '44444444-4444-4444-8444-444444444444',
                  'target_type': 'person',
                  'display_name': '王小明',
                  'phone': null,
                  'email': null,
                  'created_at': '2026-08-06T12:00:00Z',
                },
              ],
            }),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final result = await gateway.loadAssigned();
    final targets =
        (result as PromotionTargetSuccess<List<PromotionTargetProfile>>).value;
    expect(targets.single.displayName, '王小明');
  });

  test('updates a relationship with expected revision and mutation id', () async {
    final gateway = HttpPromotionTargetGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: _signedInIdentity(),
      client: MockClient((request) async {
        expect(request.method, 'PATCH');
        expect(
          request.url.path,
          '/v1/promotion-targets/44444444-4444-4444-8444-444444444444/relationship',
        );
        expect(jsonDecode(request.body), {
          'expected_revision': 2,
          'stage': 4,
          'lifecycle_status': 'active',
          'follow_up_note': '已安排下次会面',
          'reason_code': 'progress_update',
          'reason_detail': null,
          'mutation_id': 'relationship-change-1',
          'resolved_conflict_id': null,
        });
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'relationship': _relationshipDocument(stage: 4, revision: 3),
              'duplicate': false,
              'accepted_revision': 3,
            }),
          ),
          200,
        );
      }),
    );

    final result = await gateway.updateRelationship(
      targetId: '44444444-4444-4444-8444-444444444444',
      expectedRevision: 2,
      stage: 4,
      lifecycleStatus: PromotionTargetRelationshipLifecycle.active,
      followUpNote: '已安排下次会面',
      reason: PromotionTargetRelationshipReason.progressUpdate,
      reasonDetail: null,
      mutationId: 'relationship-change-1',
      resolvedConflictId: null,
    );

    expect(
      (result as PromotionTargetSuccess<PromotionTargetRelationship>)
          .value
          .stage,
      4,
    );
  });

  test(
    'returns the server version for an explicit relationship conflict',
    () async {
      final gateway = HttpPromotionTargetGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: _signedInIdentity(),
        client: MockClient(
          (_) async => http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'error': {'code': 'promotion_target_relationship_conflict'},
                'conflict_id': '66666666-6666-4666-8666-666666666666',
                'conflicting_fields': ['stage'],
                'current': _relationshipDocument(stage: 3, revision: 4),
                'proposed': {
                  'expected_revision': 2,
                  'stage': 4,
                  'display_stage': 8,
                  'lifecycle_status': 'active',
                  'follow_up_note': null,
                  'reason_code': 'progress_update',
                  'reason_detail': null,
                },
              }),
            ),
            409,
          ),
        ),
      );

      final result = await gateway.updateRelationship(
        targetId: '44444444-4444-4444-8444-444444444444',
        expectedRevision: 2,
        stage: 4,
        lifecycleStatus: PromotionTargetRelationshipLifecycle.active,
        followUpNote: null,
        reason: PromotionTargetRelationshipReason.progressUpdate,
        reasonDetail: null,
        mutationId: 'relationship-change-2',
        resolvedConflictId: null,
      );

      expect(
        (result as PromotionTargetConflict<PromotionTargetRelationship>)
            .current
            .revisionNumber,
        4,
      );
    },
  );
}

Map<String, Object?> _relationshipDocument({
  required int stage,
  required int revision,
}) => {
  'target_id': '44444444-4444-4444-8444-444444444444',
  'project_id': '22222222-2222-4222-8222-222222222222',
  'stage': stage,
  'display_stage': stage * 2,
  'lifecycle_status': 'active',
  'follow_up_note': '已安排下次会面',
  'revision_number': revision,
  'updated_at': '2026-08-06T13:00:00Z',
  'stage_aliases': [
    for (var value = 0; value <= 4; value++)
      {'stage': value, 'display_stage': value * 2, 'display_name': null},
  ],
  'history': [
    {
      'revision_number': revision,
      'old_stage': stage == 0 ? null : stage - 1,
      'new_stage': stage,
      'old_lifecycle_status': stage == 0 ? null : 'active',
      'new_lifecycle_status': 'active',
      'follow_up_note': '已安排下次会面',
      'changed_fields': ['stage', 'follow_up_note'],
      'reason_code': stage == 0 ? 'project_entry' : 'progress_update',
      'reason_detail': null,
      'changed_by_app_user_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'changed_at': '2026-08-06T13:00:00Z',
    },
  ],
};

FakeIdentitySession _signedInIdentity() => FakeIdentitySession(
  initial: const IdentitySnapshot(
    stage: IdentityStage.signedIn,
    principal: IdentityPrincipal(
      externalSubject: 'test-subject',
      email: 'test@example.test',
    ),
  ),
);
