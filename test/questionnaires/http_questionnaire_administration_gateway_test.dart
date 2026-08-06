import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/questionnaires/http_questionnaire_administration_gateway.dart';
import 'package:tongxingzhe_app/questionnaires/questionnaire_administration.dart';
import 'package:tongxingzhe_app/questionnaires/questionnaire_contract.dart';
import 'package:tongxingzhe_app/questionnaires/questionnaire_metric_compatibility.dart';

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
          headers: {'content-type': 'application/json; charset=utf-8'},
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

  test('loads stable metrics with comparison and sample previews', () async {
    final gateway = HttpQuestionnaireAdministrationGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: _signedInIdentity(),
      client: MockClient((request) async {
        expect(request.url.path, '/v1/questionnaire-metrics');
        return http.Response(
          jsonEncode({
            'metrics': [
              {
                'metric_id': 'metric-1',
                'metric_label': '接触兴趣',
                'analysis_operation': 'distribution',
                'active_members': [
                  {
                    'questionnaire_version_id': 'version-1',
                    'question_id': 'interest',
                  },
                ],
              },
            ],
            'available_questions': [
              {
                'reference': {
                  'questionnaire_version_id': 'version-1',
                  'question_id': 'interest',
                },
                'version_number': 1,
                'comparison_snapshot': _comparisonJson('兴趣程度'),
                'sample_count': 12,
                'trend_series': [
                  {'period_start': '2026-07-01', 'sample_count': 12},
                ],
              },
            ],
            'events': [],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final result = await gateway.loadMetricCompatibility();
    final snapshot =
        (result
                as QuestionnaireAdministrationSuccess<
                  QuestionnaireMetricCompatibilitySnapshot
                >)
            .value;
    expect(snapshot.metrics.single.id, 'metric-1');
    expect(snapshot.availableQuestions.single.comparison.prompt, '兴趣程度');
    expect(snapshot.availableQuestions.single.sampleCount, 12);
    expect(
      snapshot.availableQuestions.single.trendSeries.single.periodStart,
      '2026-07-01',
    );
  });
}

Map<String, Object?> _comparisonJson(String prompt) => {
  'definition': {
    'prompt': prompt,
    'question_type': 'single_choice',
    'required': true,
  },
  'options': [
    {'option_id': 'low', 'position': 1, 'label': '较低'},
    {'option_id': 'high', 'position': 2, 'label': '较高'},
  ],
  'time_scope': {'kind': 'all_recorded_contacts'},
  'answer_mode': {
    'allow_unknown': true,
    'allow_refused': true,
    'allow_not_applicable': false,
  },
};

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
