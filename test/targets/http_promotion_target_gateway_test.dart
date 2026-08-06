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
              'authorized_at': '2026-08-06T12:00:00Z',
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
    final success =
        result as PromotionTargetSuccess<List<PromotionTargetProfile>>;
    final targets = success.value;
    expect(targets.single.displayName, '王小明');
    expect(success.authorizedAtUtc, DateTime.utc(2026, 8, 6, 12));
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

  test('creates and ends a person-to-institution relationship', () async {
    var requestNumber = 0;
    final gateway = HttpPromotionTargetGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: _signedInIdentity(),
      client: MockClient((request) async {
        requestNumber += 1;
        if (requestNumber == 1) {
          expect(request.method, 'POST');
          expect(
            request.url.path,
            '/v1/promotion-target-institution-relationships',
          );
          expect(jsonDecode(request.body), {
            'person_target_id': '44444444-4444-4444-8444-444444444444',
            'institution_target_id': '55555555-5555-4555-8555-555555555555',
            'relationship_kind': 'employment_representative',
            'role_description': '项目协调员',
            'mutation_id': 'institution-create-1',
          });
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'duplicate': false,
                'relationship': _institutionRelationshipDocument(),
              }),
            ),
            201,
          );
        }
        expect(request.method, 'POST');
        expect(
          request.url.path,
          '/v1/promotion-target-institution-relationships/'
          '77777777-7777-4777-8777-777777777777/end',
        );
        expect(jsonDecode(request.body), {
          'expected_revision': 1,
          'mutation_id': 'institution-end-1',
        });
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'duplicate': false,
              'relationship': _institutionRelationshipDocument(ended: true),
            }),
          ),
          200,
        );
      }),
    );

    final created = await gateway.createInstitutionRelationship(
      personTargetId: '44444444-4444-4444-8444-444444444444',
      institutionTargetId: '55555555-5555-4555-8555-555555555555',
      kind: TargetInstitutionRelationshipKind.employmentRepresentative,
      roleDescription: '项目协调员',
      mutationId: 'institution-create-1',
    );
    final ended = await gateway.endInstitutionRelationship(
      relationshipId: '77777777-7777-4777-8777-777777777777',
      expectedRevision: 1,
      mutationId: 'institution-end-1',
    );

    expect(
      (created as PromotionTargetSuccess<TargetInstitutionRelationship>)
          .value
          .kind,
      TargetInstitutionRelationshipKind.employmentRepresentative,
    );
    expect(
      (ended as PromotionTargetSuccess<TargetInstitutionRelationship>)
          .value
          .status,
      TargetInstitutionRelationshipStatus.ended,
    );
  });
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

Map<String, Object?> _institutionRelationshipDocument({bool ended = false}) => {
  'relationship_id': '77777777-7777-4777-8777-777777777777',
  'person_target_id': '44444444-4444-4444-8444-444444444444',
  'institution_target_id': '55555555-5555-4555-8555-555555555555',
  'relationship_kind': 'employment_representative',
  'role_description': '项目协调员',
  'started_at': '2026-08-06T12:00:00Z',
  'ended_at': ended ? '2026-08-07T12:00:00Z' : null,
  'status': ended ? 'ended' : 'active',
  'revision_number': ended ? 2 : 1,
  'history': [
    if (ended)
      {
        'revision_number': 2,
        'event_type': 'ended',
        'old_status': 'active',
        'new_status': 'ended',
        'ended_at': '2026-08-07T12:00:00Z',
        'changed_by_app_user_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'changed_at': '2026-08-07T12:00:00Z',
      },
    {
      'revision_number': 1,
      'event_type': 'created',
      'old_status': null,
      'new_status': 'active',
      'ended_at': null,
      'changed_by_app_user_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'changed_at': '2026-08-06T12:00:00Z',
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
