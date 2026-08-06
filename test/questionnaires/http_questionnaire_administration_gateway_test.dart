import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/questionnaires/http_questionnaire_administration_gateway.dart';
import 'package:tongxingzhe_app/questionnaires/questionnaire_administration.dart';
import 'package:tongxingzhe_app/questionnaires/questionnaire_contract.dart';

import '../support/fake_identity_session.dart';

void main() {
  test('loads version and draft administration contracts', () async {
    final gateway = HttpQuestionnaireAdministrationGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: _signedInIdentity(),
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/v1/questionnaire-administration');
        expect(
          request.headers['authorization'],
          'Bearer test-only-access-token',
        );
        return http.Response(
          jsonEncode({
            'current_version_id': 'version-1',
            'versions': [
              {
                'questionnaire_version_id': 'version-1',
                'version_number': 1,
                'is_current': true,
                'published_at': '2026-08-06T00:00:00Z',
                'published_by_app_user_id': null,
                'publication_note': null,
              },
            ],
            'drafts': [
              {
                'draft_id': 'draft-1',
                'project_id': 'project-1',
                'source_version_id': 'version-1',
                'revision': 2,
                'updated_at': '2026-08-06T01:00:00Z',
                'definition': {'questions': []},
              },
            ],
          }),
          200,
        );
      }),
    );

    final result = await gateway.load();
    expect(result, isA<QuestionnaireAdministrationSuccess>());
    final snapshot =
        (result
                as QuestionnaireAdministrationSuccess<
                  QuestionnaireAdministrationSnapshot
                >)
            .value;
    expect(snapshot.currentVersionId, 'version-1');
    expect(snapshot.versions.single.isCurrent, isTrue);
    expect(snapshot.drafts.single.revision, 2);
  });

  test('maps a concurrent edit to a stable revision conflict', () async {
    final gateway = HttpQuestionnaireAdministrationGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: _signedInIdentity(),
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {'code': 'questionnaire_draft_revision_conflict'},
          }),
          409,
        ),
      ),
    );
    final draft = QuestionnaireDesignDraft(
      id: 'draft-1',
      projectId: 'project-1',
      sourceVersionId: null,
      revision: 1,
      updatedAtUtc: DateTime.utc(2026, 8, 6),
      definition: _emptyVersion,
    );

    final result = await gateway.saveDraft(
      draft: draft,
      definition: _emptyVersion,
    );
    expect(
      (result as QuestionnaireAdministrationRejected).code,
      QuestionnaireAdministrationFailureCode.revisionConflict,
    );
  });
}

final _emptyVersion = QuestionnaireVersion(
  id: 'draft-1',
  projectId: 'project-1',
  versionNumber: 1,
  questions: const [],
);

FakeIdentitySession _signedInIdentity() => FakeIdentitySession(
  initial: const IdentitySnapshot(
    stage: IdentityStage.signedIn,
    principal: IdentityPrincipal(
      externalSubject: 'test-subject',
      email: 'test@example.test',
    ),
  ),
);
