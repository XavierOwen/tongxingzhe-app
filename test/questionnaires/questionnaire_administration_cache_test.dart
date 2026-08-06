import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/data/local_database.dart';
import 'package:tongxingzhe_app/questionnaires/questionnaire_administration.dart';
import 'package:tongxingzhe_app/questionnaires/questionnaire_administration_cache.dart';
import 'package:tongxingzhe_app/questionnaires/questionnaire_contract.dart';

void main() {
  test(
    'failed network save restores the Drift working copy on next load',
    () async {
      final database = LocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final remote = _Remote();
      final gateway = CachedQuestionnaireAdministrationGateway(
        database: database,
        remote: remote,
      );
      final changed = QuestionnaireVersion(
        id: _serverDraft.id,
        projectId: _serverDraft.projectId,
        versionNumber: _serverDraft.revision,
        questions: [_question('本机未上传的文字')],
      );

      final failed = await gateway.saveDraft(
        draft: _serverDraft,
        definition: changed,
      );
      expect(failed, isA<QuestionnaireAdministrationRejected>());

      final loaded = await gateway.load();
      final snapshot =
          (loaded
                  as QuestionnaireAdministrationSuccess<
                    QuestionnaireAdministrationSnapshot
                  >)
              .value;
      expect(snapshot.drafts.single.hasLocalChanges, isTrue);
      expect(
        snapshot.drafts.single.definition.questions.single.prompt,
        '本机未上传的文字',
      );
    },
  );

  test('successful publication removes the local working copy', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final remote = _Remote()..publishSucceeds = true;
    final gateway = CachedQuestionnaireAdministrationGateway(
      database: database,
      remote: remote,
    );
    await gateway.saveDraft(
      draft: _serverDraft,
      definition: _serverDraft.definition,
    );

    await gateway.publish(
      draft: _serverDraft,
      requestId: 'request-1',
      publicationNote: '发布',
    );

    expect(
      await database.select(database.dbQuestionnaireDraftWorkingCopies).get(),
      isEmpty,
    );
  });
}

final class _Remote implements QuestionnaireAdministrationGateway {
  var publishSucceeds = false;

  @override
  Future<QuestionnaireAdministrationResult<QuestionnaireAdministrationSnapshot>>
  load() async => QuestionnaireAdministrationSuccess(
    QuestionnaireAdministrationSnapshot(
      currentVersionId: _current.id,
      versions: const [],
      drafts: [_serverDraft],
    ),
  );

  @override
  Future<QuestionnaireAdministrationResult<QuestionnaireDesignDraft>>
  saveDraft({
    required QuestionnaireDesignDraft draft,
    required QuestionnaireVersion definition,
  }) async => const QuestionnaireAdministrationRejected(
    QuestionnaireAdministrationFailureCode.networkUnavailable,
  );

  @override
  Future<QuestionnaireAdministrationResult<QuestionnairePublication>> publish({
    required QuestionnaireDesignDraft draft,
    required String requestId,
    required String publicationNote,
  }) async => publishSucceeds
      ? QuestionnaireAdministrationSuccess(
          QuestionnairePublication(
            summary: QuestionnairePublishedVersionSummary(
              id: 'version-2',
              versionNumber: 2,
              isCurrent: true,
              publishedAtUtc: DateTime.utc(2026, 8, 6),
              publishedByAppUserId: 'manager-1',
              publicationNote: publicationNote,
            ),
            version: QuestionnaireVersion(
              id: 'version-2',
              projectId: draft.projectId,
              versionNumber: 2,
              questions: draft.definition.questions,
            ),
          ),
        )
      : const QuestionnaireAdministrationRejected(
          QuestionnaireAdministrationFailureCode.networkUnavailable,
        );

  @override
  Future<QuestionnaireAdministrationResult<QuestionnaireDesignDraft>>
  createDraft({String? sourceVersionId}) async =>
      QuestionnaireAdministrationSuccess(_serverDraft);

  @override
  Future<QuestionnaireVersion?> readPublishedVersion(String versionId) async =>
      _current;

  @override
  Future<void> close() async {}
}

QuestionnaireQuestion _question(String prompt) => QuestionnaireQuestion(
  id: 'question-1',
  position: 1,
  prompt: prompt,
  type: QuestionnaireQuestionType.boolean,
  required: false,
  allowUnknown: false,
  allowRefused: true,
  allowNotApplicable: true,
);

final _current = QuestionnaireVersion(
  id: 'version-1',
  projectId: 'project-1',
  versionNumber: 1,
  questions: [_question('服务端文字')],
);

final _serverDraft = QuestionnaireDesignDraft(
  id: 'draft-1',
  projectId: 'project-1',
  sourceVersionId: 'version-1',
  revision: 1,
  updatedAtUtc: DateTime.utc(2026, 8, 6),
  definition: QuestionnaireVersion(
    id: 'draft-1',
    projectId: 'project-1',
    versionNumber: 1,
    questions: [_question('服务端文字')],
  ),
);
