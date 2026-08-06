import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/features/questionnaire_admin/questionnaire_admin_view_model.dart';
import 'package:tongxingzhe_app/foundation/runtime_values.dart';
import 'package:tongxingzhe_app/questionnaires/questionnaire_administration.dart';
import 'package:tongxingzhe_app/questionnaires/questionnaire_contract.dart';

void main() {
  test('creates, edits, saves, previews, and publishes one draft', () async {
    final gateway = _FakeGateway();
    final viewModel = QuestionnaireAdminViewModel(
      gateway: gateway,
      idGenerator: _FixedIds(),
    );

    await viewModel.initialize();
    expect(viewModel.state.stage, QuestionnaireAdminStage.ready);
    await viewModel.createDraft();
    viewModel.addQuestion(_booleanQuestion);
    expect(viewModel.state.isDirty, isTrue);
    expect(await viewModel.save(), isTrue);

    viewModel.setPreviewValue(_booleanQuestion, true);
    expect(viewModel.state.previewEvaluation!.isValid, isTrue);
    expect(viewModel.state.previewAnswers.single.value, isTrue);

    expect(await viewModel.publish('首次正式设计'), isTrue);
    expect(viewModel.state.stage, QuestionnaireAdminStage.published);
    expect(gateway.lastPublicationRequestId, 'publication-request');
    expect(viewModel.state.publication!.summary.versionNumber, 2);
  });

  test(
    'removing a source question also removes a dependent display rule',
    () async {
      final viewModel = QuestionnaireAdminViewModel(
        gateway: _FakeGateway(),
        idGenerator: _FixedIds(),
      );
      await viewModel.initialize();
      await viewModel.createDraft();
      viewModel.addQuestion(_booleanQuestion);
      viewModel.addQuestion(_conditionalDetail);

      viewModel.removeQuestion('consent');
      expect(viewModel.state.definition!.questions.single.displayRule, isNull);
    },
  );

  test(
    'reordering keeps valid rules and removes only forward references',
    () async {
      final viewModel = QuestionnaireAdminViewModel(
        gateway: _FakeGateway(),
        idGenerator: _FixedIds(),
      );
      await viewModel.initialize();
      await viewModel.createDraft();
      viewModel.addQuestion(_booleanQuestion);
      viewModel.addQuestion(_conditionalDetail);
      viewModel.addQuestion(
        QuestionnaireQuestion(
          id: 'unrelated',
          position: 3,
          prompt: '其他问题',
          type: QuestionnaireQuestionType.boolean,
          required: false,
          allowUnknown: false,
          allowRefused: true,
          allowNotApplicable: true,
        ),
      );

      viewModel.moveQuestion('unrelated', -1);
      expect(
        viewModel.state.definition!.questions
            .firstWhere((question) => question.id == 'detail')
            .displayRule,
        isNotNull,
      );

      viewModel.moveQuestion('detail', -2);
      expect(
        viewModel.state.definition!.questions
            .firstWhere((question) => question.id == 'detail')
            .displayRule,
        isNull,
      );
    },
  );
}

final _booleanQuestion = QuestionnaireQuestion(
  id: 'consent',
  position: 1,
  prompt: '愿意继续了解吗？',
  type: QuestionnaireQuestionType.boolean,
  required: true,
  allowUnknown: false,
  allowRefused: true,
  allowNotApplicable: false,
);

final _conditionalDetail = QuestionnaireQuestion(
  id: 'detail',
  position: 2,
  prompt: '补充说明',
  type: QuestionnaireQuestionType.shortText,
  required: false,
  allowUnknown: false,
  allowRefused: true,
  allowNotApplicable: true,
  maximumLength: 120,
  displayRule: QuestionnaireVisibilityRule(
    match: QuestionnaireVisibilityMatch.all,
    conditions: const [
      QuestionnaireVisibilityCondition(
        sourceQuestionId: 'consent',
        operator: QuestionnaireVisibilityOperator.equals,
        operand: true,
      ),
    ],
  ),
);

final _currentVersion = QuestionnaireVersion(
  id: 'version-1',
  projectId: 'project-1',
  versionNumber: 1,
  questions: const [],
);

final class _FixedIds implements IdGenerator {
  @override
  String next() => 'publication-request';
}

final class _FakeGateway implements QuestionnaireAdministrationGateway {
  QuestionnaireDesignDraft? draft;
  String? lastPublicationRequestId;

  @override
  Future<QuestionnaireAdministrationResult<QuestionnaireAdministrationSnapshot>>
  load() async => QuestionnaireAdministrationSuccess(
    QuestionnaireAdministrationSnapshot(
      currentVersionId: _currentVersion.id,
      versions: [
        QuestionnairePublishedVersionSummary(
          id: _currentVersion.id,
          versionNumber: 1,
          isCurrent: true,
          publishedAtUtc: DateTime.utc(2026, 8, 6),
          publishedByAppUserId: null,
          publicationNote: null,
        ),
      ],
      drafts: const [],
    ),
  );

  @override
  Future<QuestionnaireVersion?> readPublishedVersion(String versionId) async =>
      _currentVersion;

  @override
  Future<QuestionnaireAdministrationResult<QuestionnaireDesignDraft>>
  createDraft({String? sourceVersionId}) async {
    draft = QuestionnaireDesignDraft(
      id: 'draft-1',
      projectId: 'project-1',
      sourceVersionId: sourceVersionId,
      revision: 1,
      updatedAtUtc: DateTime.utc(2026, 8, 6),
      definition: QuestionnaireVersion(
        id: 'draft-1',
        projectId: 'project-1',
        versionNumber: 1,
        questions: const [],
      ),
    );
    return QuestionnaireAdministrationSuccess(draft!);
  }

  @override
  Future<QuestionnaireAdministrationResult<QuestionnaireDesignDraft>>
  saveDraft({
    required QuestionnaireDesignDraft draft,
    required QuestionnaireVersion definition,
  }) async {
    this.draft = QuestionnaireDesignDraft(
      id: draft.id,
      projectId: draft.projectId,
      sourceVersionId: draft.sourceVersionId,
      revision: draft.revision + 1,
      updatedAtUtc: DateTime.utc(2026, 8, 6, 1),
      definition: QuestionnaireVersion(
        id: definition.id,
        projectId: definition.projectId,
        versionNumber: draft.revision + 1,
        questions: definition.questions,
      ),
    );
    return QuestionnaireAdministrationSuccess(this.draft!);
  }

  @override
  Future<QuestionnaireAdministrationResult<QuestionnairePublication>> publish({
    required QuestionnaireDesignDraft draft,
    required String requestId,
    required String publicationNote,
  }) async {
    lastPublicationRequestId = requestId;
    final version = QuestionnaireVersion(
      id: 'version-2',
      projectId: draft.projectId,
      versionNumber: 2,
      questions: draft.definition.questions,
    );
    return QuestionnaireAdministrationSuccess(
      QuestionnairePublication(
        summary: QuestionnairePublishedVersionSummary(
          id: version.id,
          versionNumber: 2,
          isCurrent: true,
          publishedAtUtc: DateTime.utc(2026, 8, 6, 2),
          publishedByAppUserId: 'manager-1',
          publicationNote: publicationNote,
        ),
        version: version,
      ),
    );
  }

  @override
  Future<void> close() async {}
}
