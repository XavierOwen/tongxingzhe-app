import 'package:flutter/foundation.dart';

import '../../foundation/runtime_values.dart';
import '../../questionnaires/questionnaire_administration.dart';
import '../../questionnaires/questionnaire_contract.dart';

enum QuestionnaireAdminStage {
  loading,
  ready,
  saving,
  publishing,
  failed,
  published,
}

final class QuestionnaireAdminViewState {
  QuestionnaireAdminViewState({
    required this.stage,
    required this.snapshot,
    required this.currentVersion,
    required this.draft,
    required this.definition,
    required Iterable<QuestionnaireAnswer> previewAnswers,
    required this.previewEvaluation,
    required this.isDirty,
    required this.failureCode,
    required this.publication,
  }) : previewAnswers = List.unmodifiable(previewAnswers);

  const QuestionnaireAdminViewState.loading()
    : stage = QuestionnaireAdminStage.loading,
      snapshot = null,
      currentVersion = null,
      draft = null,
      definition = null,
      previewAnswers = const [],
      previewEvaluation = null,
      isDirty = false,
      failureCode = null,
      publication = null;

  final QuestionnaireAdminStage stage;
  final QuestionnaireAdministrationSnapshot? snapshot;
  final QuestionnaireVersion? currentVersion;
  final QuestionnaireDesignDraft? draft;
  final QuestionnaireVersion? definition;
  final List<QuestionnaireAnswer> previewAnswers;
  final QuestionnaireEvaluation? previewEvaluation;
  final bool isDirty;
  final QuestionnaireAdministrationFailureCode? failureCode;
  final QuestionnairePublication? publication;

  bool get isBusy =>
      stage == QuestionnaireAdminStage.loading ||
      stage == QuestionnaireAdminStage.saving ||
      stage == QuestionnaireAdminStage.publishing;

  List<QuestionnaireDifference> get differences =>
      currentVersion == null || definition == null
      ? const []
      : QuestionnaireDesign.differences(currentVersion!, definition!);

  QuestionnaireAdminViewState copyWith({
    QuestionnaireAdminStage? stage,
    QuestionnaireAdministrationSnapshot? snapshot,
    QuestionnaireVersion? currentVersion,
    QuestionnaireDesignDraft? draft,
    bool clearDraft = false,
    QuestionnaireVersion? definition,
    bool clearDefinition = false,
    Iterable<QuestionnaireAnswer>? previewAnswers,
    QuestionnaireEvaluation? previewEvaluation,
    bool clearPreview = false,
    bool? isDirty,
    QuestionnaireAdministrationFailureCode? failureCode,
    bool clearFailure = false,
    QuestionnairePublication? publication,
  }) => QuestionnaireAdminViewState(
    stage: stage ?? this.stage,
    snapshot: snapshot ?? this.snapshot,
    currentVersion: currentVersion ?? this.currentVersion,
    draft: clearDraft ? null : draft ?? this.draft,
    definition: clearDefinition ? null : definition ?? this.definition,
    previewAnswers: clearPreview
        ? const []
        : previewAnswers ?? this.previewAnswers,
    previewEvaluation: clearPreview
        ? null
        : previewEvaluation ?? this.previewEvaluation,
    isDirty: isDirty ?? this.isDirty,
    failureCode: clearFailure ? null : failureCode ?? this.failureCode,
    publication: publication ?? this.publication,
  );
}

final class QuestionnaireAdminViewModel extends ChangeNotifier {
  factory QuestionnaireAdminViewModel({
    required QuestionnaireAdministrationGateway gateway,
    required IdGenerator idGenerator,
  }) => QuestionnaireAdminViewModel._(gateway, idGenerator);

  QuestionnaireAdminViewModel._(this._gateway, this._idGenerator);

  final QuestionnaireAdministrationGateway _gateway;
  final IdGenerator _idGenerator;
  QuestionnaireAdminViewState _state =
      const QuestionnaireAdminViewState.loading();
  bool _disposed = false;

  QuestionnaireAdminViewState get state => _state;

  Future<void> initialize() async {
    _publish(const QuestionnaireAdminViewState.loading());
    final result = await _gateway.load();
    if (result case QuestionnaireAdministrationRejected(:final code)) {
      _fail(code);
      return;
    }
    final snapshot =
        (result
                as QuestionnaireAdministrationSuccess<
                  QuestionnaireAdministrationSnapshot
                >)
            .value;
    final current = await _gateway.readPublishedVersion(
      snapshot.currentVersionId,
    );
    if (current == null) {
      _fail(QuestionnaireAdministrationFailureCode.networkUnavailable);
      return;
    }
    _publish(
      QuestionnaireAdminViewState(
        stage: QuestionnaireAdminStage.ready,
        snapshot: snapshot,
        currentVersion: current,
        draft: null,
        definition: null,
        previewAnswers: const [],
        previewEvaluation: null,
        isDirty: false,
        failureCode: null,
        publication: null,
      ),
    );
  }

  void openDraft(QuestionnaireDesignDraft draft) {
    final evaluation = QuestionnaireCatalog.evaluate(
      draft.definition,
      const [],
    );
    _publish(
      _state.copyWith(
        stage: QuestionnaireAdminStage.ready,
        draft: draft,
        definition: draft.definition,
        previewAnswers: evaluation.answers,
        previewEvaluation: evaluation,
        isDirty: draft.hasLocalChanges,
        clearFailure: true,
      ),
    );
  }

  void closeDraft() {
    _publish(
      _state.copyWith(
        stage: QuestionnaireAdminStage.ready,
        clearDraft: true,
        clearDefinition: true,
        clearPreview: true,
        isDirty: false,
        clearFailure: true,
      ),
    );
  }

  Future<void> createDraft({String? sourceVersionId}) async {
    _publish(
      _state.copyWith(
        stage: QuestionnaireAdminStage.saving,
        clearFailure: true,
      ),
    );
    final result = await _gateway.createDraft(sourceVersionId: sourceVersionId);
    switch (result) {
      case QuestionnaireAdministrationRejected(:final code):
        _fail(code);
      case QuestionnaireAdministrationSuccess(:final value):
        final draft = value;
        final snapshot = _state.snapshot!;
        final evaluation = QuestionnaireCatalog.evaluate(
          draft.definition,
          const [],
        );
        _publish(
          _state.copyWith(
            stage: QuestionnaireAdminStage.ready,
            snapshot: QuestionnaireAdministrationSnapshot(
              currentVersionId: snapshot.currentVersionId,
              versions: snapshot.versions,
              drafts: [draft, ...snapshot.drafts],
            ),
            draft: draft,
            definition: draft.definition,
            previewAnswers: evaluation.answers,
            previewEvaluation: evaluation,
            isDirty: false,
            clearFailure: true,
          ),
        );
    }
  }

  void addQuestion(QuestionnaireQuestion question) {
    final definition = _state.definition;
    if (definition == null) return;
    _replaceQuestions([...definition.questions, question]);
  }

  void updateQuestion(QuestionnaireQuestion question) {
    final definition = _state.definition;
    if (definition == null) return;
    _replaceQuestions([
      for (final existing in definition.questions)
        if (existing.id == question.id) question else existing,
    ]);
  }

  void removeQuestion(String questionId) {
    final definition = _state.definition;
    if (definition == null) return;
    _replaceQuestions([
      for (final question in definition.questions)
        if (question.id != questionId) question,
    ]);
  }

  void moveQuestion(String questionId, int offset) {
    final definition = _state.definition;
    if (definition == null) return;
    final questions = [...definition.questions];
    final index = questions.indexWhere((question) => question.id == questionId);
    final target = index + offset;
    if (index < 0 || target < 0 || target >= questions.length) return;
    final moved = questions.removeAt(index);
    questions.insert(target, moved);
    _replaceQuestions(questions);
  }

  Future<bool> save() async {
    final draft = _state.draft;
    final definition = _state.definition;
    if (draft == null || definition == null) return false;
    _publish(
      _state.copyWith(
        stage: QuestionnaireAdminStage.saving,
        clearFailure: true,
      ),
    );
    final result = await _gateway.saveDraft(
      draft: draft,
      definition: definition,
    );
    switch (result) {
      case QuestionnaireAdministrationRejected(:final code):
        _fail(code);
        return false;
      case QuestionnaireAdministrationSuccess(:final value):
        final saved = value;
        _publish(
          _state.copyWith(
            stage: QuestionnaireAdminStage.ready,
            draft: saved,
            definition: saved.definition,
            isDirty: false,
            clearFailure: true,
          ),
        );
        return true;
    }
  }

  Future<bool> publish(String publicationNote) async {
    if (_state.isDirty && !await save()) return false;
    final draft = _state.draft;
    final definition = _state.definition;
    if (draft == null || definition == null) return false;
    try {
      QuestionnaireDesign.validateForPublication(definition);
    } on FormatException {
      _fail(QuestionnaireAdministrationFailureCode.invalidDefinition);
      return false;
    }
    _publish(
      _state.copyWith(
        stage: QuestionnaireAdminStage.publishing,
        clearFailure: true,
      ),
    );
    final result = await _gateway.publish(
      draft: draft,
      requestId: _idGenerator.next(),
      publicationNote: publicationNote.trim(),
    );
    switch (result) {
      case QuestionnaireAdministrationRejected(:final code):
        _fail(code);
        return false;
      case QuestionnaireAdministrationSuccess(:final value):
        final publication = value;
        _publish(
          _state.copyWith(
            stage: QuestionnaireAdminStage.published,
            publication: publication,
            currentVersion: publication.version,
            isDirty: false,
            clearFailure: true,
          ),
        );
        return true;
    }
  }

  void setPreviewValue(QuestionnaireQuestion question, Object value) {
    _setPreviewAnswer(_answerWithValue(question, value));
  }

  void setPreviewState(
    QuestionnaireQuestion question,
    QuestionnaireAnswerState state,
  ) {
    _setPreviewAnswer(_answerWithState(question, state));
  }

  void _setPreviewAnswer(QuestionnaireAnswer answer) {
    final definition = _state.definition;
    if (definition == null) return;
    final transition = QuestionnaireCatalog.previewAnswerChange(
      definition,
      _state.previewAnswers,
      answer,
    );
    final evaluation = QuestionnaireCatalog.evaluate(
      definition,
      transition.answers,
    );
    _publish(
      _state.copyWith(
        previewAnswers: evaluation.answers,
        previewEvaluation: evaluation,
      ),
    );
  }

  void _replaceQuestions(List<QuestionnaireQuestion> questions) {
    final draft = _state.draft!;
    final normalized = <QuestionnaireQuestion>[];
    for (var index = 0; index < questions.length; index += 1) {
      normalized.add(_withPosition(questions[index], index + 1));
    }
    final positions = {
      for (final question in normalized) question.id: question.position,
    };
    // Reordering or deleting a source can invalidate the forward-only rule
    // contract. Preserve unaffected rules and remove only invalid references.
    final safeQuestions = [
      for (final question in normalized)
        if (question.displayRule?.conditions.every(
              (condition) =>
                  (positions[condition.sourceQuestionId] ?? 1 << 30) <
                  question.position,
            ) ??
            true)
          question
        else
          _copyQuestion(question, displayRule: null, replaceDisplayRule: true),
    ];
    final definition = QuestionnaireVersion(
      id: draft.id,
      projectId: draft.projectId,
      versionNumber: draft.revision,
      questions: safeQuestions,
    );
    final evaluation = QuestionnaireCatalog.evaluate(definition, const []);
    _publish(
      _state.copyWith(
        stage: QuestionnaireAdminStage.ready,
        definition: definition,
        previewAnswers: evaluation.answers,
        previewEvaluation: evaluation,
        isDirty: true,
        clearFailure: true,
      ),
    );
  }

  QuestionnaireQuestion _withPosition(
    QuestionnaireQuestion question,
    int position,
  ) => _copyQuestion(question, position: position);

  void _fail(QuestionnaireAdministrationFailureCode code) {
    _publish(
      _state.copyWith(stage: QuestionnaireAdminStage.failed, failureCode: code),
    );
  }

  void _publish(QuestionnaireAdminViewState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

QuestionnaireQuestion _copyQuestion(
  QuestionnaireQuestion value, {
  int? position,
  QuestionnaireVisibilityRule? displayRule,
  bool replaceDisplayRule = false,
}) => QuestionnaireQuestion(
  id: value.id,
  position: position ?? value.position,
  prompt: value.prompt,
  type: value.type,
  required: value.required,
  allowUnknown: value.allowUnknown,
  allowRefused: value.allowRefused,
  allowNotApplicable: value.allowNotApplicable,
  options: value.options,
  minimumSelections: value.minimumSelections,
  maximumSelections: value.maximumSelections,
  numberKind: value.numberKind,
  unit: value.unit,
  minimum: value.minimum,
  maximum: value.maximum,
  maximumLength: value.maximumLength,
  displayRule: replaceDisplayRule ? displayRule : value.displayRule,
);

QuestionnaireAnswer _answerWithValue(
  QuestionnaireQuestion question,
  Object value,
) => switch (question.type) {
  QuestionnaireQuestionType.boolean => BooleanQuestionnaireAnswer(
    questionId: question.id,
    value: value as bool,
  ),
  QuestionnaireQuestionType.singleChoice => SingleChoiceQuestionnaireAnswer(
    questionId: question.id,
    value: value as String,
  ),
  QuestionnaireQuestionType.ordinalChoice => OrdinalChoiceQuestionnaireAnswer(
    questionId: question.id,
    value: value as String,
  ),
  QuestionnaireQuestionType.multiChoice => MultiChoiceQuestionnaireAnswer(
    questionId: question.id,
    value: value as List<String>,
  ),
  QuestionnaireQuestionType.number => NumberQuestionnaireAnswer(
    questionId: question.id,
    value: value as num,
  ),
  QuestionnaireQuestionType.date => DateQuestionnaireAnswer(
    questionId: question.id,
    value: value as String,
  ),
  QuestionnaireQuestionType.shortText => ShortTextQuestionnaireAnswer(
    questionId: question.id,
    value: value as String,
  ),
  QuestionnaireQuestionType.longText => LongTextQuestionnaireAnswer(
    questionId: question.id,
    value: value as String,
  ),
};

QuestionnaireAnswer _answerWithState(
  QuestionnaireQuestion question,
  QuestionnaireAnswerState state,
) {
  final value = QuestionnaireContract.parseAnswer({
    'question_id': question.id,
    'state': state.storageValue,
    'type': question.type.storageValue,
    'value': null,
  });
  return value;
}
