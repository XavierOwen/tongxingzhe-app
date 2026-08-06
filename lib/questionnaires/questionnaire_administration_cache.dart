import 'dart:convert';

import 'package:drift/drift.dart';

import '../data/local_database.dart';
import 'questionnaire_administration.dart';
import 'questionnaire_contract.dart';
import 'questionnaire_metric_compatibility.dart';

/// 在网络请求前保存管理者主动提交的工作副本，但不模拟服务端发布成功。
final class CachedQuestionnaireAdministrationGateway
    implements
        QuestionnaireAdministrationGateway,
        QuestionnaireMetricCompatibilityGateway {
  factory CachedQuestionnaireAdministrationGateway({
    required LocalDatabase database,
    required QuestionnaireAdministrationGateway remote,
  }) => CachedQuestionnaireAdministrationGateway._(database, remote);

  const CachedQuestionnaireAdministrationGateway._(
    this._database,
    this._remote,
  );

  final LocalDatabase _database;
  final QuestionnaireAdministrationGateway _remote;

  @override
  Future<QuestionnaireAdministrationResult<QuestionnaireAdministrationSnapshot>>
  load() async {
    final result = await _remote.load();
    if (result case QuestionnaireAdministrationSuccess<
      QuestionnaireAdministrationSnapshot
    >(
      :final value,
    )) {
      final drafts = <QuestionnaireDesignDraft>[];
      for (final serverDraft in value.drafts) {
        drafts.add(await _mergeServerDraft(serverDraft));
      }
      return QuestionnaireAdministrationSuccess(
        QuestionnaireAdministrationSnapshot(
          currentVersionId: value.currentVersionId,
          versions: value.versions,
          drafts: drafts,
        ),
      );
    }
    return result;
  }

  @override
  Future<QuestionnaireAdministrationResult<QuestionnaireDesignDraft>>
  createDraft({String? sourceVersionId}) async {
    final result = await _remote.createDraft(sourceVersionId: sourceVersionId);
    if (result
        case QuestionnaireAdministrationSuccess<QuestionnaireDesignDraft>(
          :final value,
        )) {
      await _store(value, value.definition, hasLocalChanges: false);
    }
    return result;
  }

  @override
  Future<QuestionnaireAdministrationResult<QuestionnaireDesignDraft>>
  saveDraft({
    required QuestionnaireDesignDraft draft,
    required QuestionnaireVersion definition,
  }) async {
    await _store(draft, definition, hasLocalChanges: true);
    final result = await _remote.saveDraft(
      draft: draft,
      definition: definition,
    );
    if (result
        case QuestionnaireAdministrationSuccess<QuestionnaireDesignDraft>(
          :final value,
        )) {
      await _store(value, value.definition, hasLocalChanges: false);
    }
    return result;
  }

  @override
  Future<QuestionnaireAdministrationResult<QuestionnairePublication>> publish({
    required QuestionnaireDesignDraft draft,
    required String requestId,
    required String publicationNote,
  }) async {
    final result = await _remote.publish(
      draft: draft,
      requestId: requestId,
      publicationNote: publicationNote,
    );
    if (result
        is QuestionnaireAdministrationSuccess<QuestionnairePublication>) {
      await (_database.delete(
        _database.dbQuestionnaireDraftWorkingCopies,
      )..where((row) => row.questionnaireDraftId.equals(draft.id))).go();
    }
    return result;
  }

  @override
  Future<QuestionnaireVersion?> readPublishedVersion(String versionId) =>
      _remote.readPublishedVersion(versionId);

  QuestionnaireMetricCompatibilityGateway? get _metricRemote =>
      _remote is QuestionnaireMetricCompatibilityGateway
      ? _remote as QuestionnaireMetricCompatibilityGateway
      : null;

  @override
  Future<
    QuestionnaireAdministrationResult<QuestionnaireMetricCompatibilitySnapshot>
  >
  loadMetricCompatibility() =>
      _metricRemote?.loadMetricCompatibility() ??
      Future.value(
        const QuestionnaireAdministrationRejected(
          QuestionnaireAdministrationFailureCode.networkUnavailable,
        ),
      );

  @override
  Future<
    QuestionnaireAdministrationResult<QuestionnaireMetricCompatibilityEvent>
  >
  recordMetricCompatibility({
    required String metricId,
    required String metricLabel,
    required QuestionnaireMetricAnalysisOperation analysisOperation,
    required QuestionnaireMetricQuestionReference reference,
    required QuestionnaireMetricQuestionReference candidate,
    required QuestionnaireMetricDecision decision,
    required String reason,
    required String requestId,
  }) =>
      _metricRemote?.recordMetricCompatibility(
        metricId: metricId,
        metricLabel: metricLabel,
        analysisOperation: analysisOperation,
        reference: reference,
        candidate: candidate,
        decision: decision,
        reason: reason,
        requestId: requestId,
      ) ??
      Future.value(
        const QuestionnaireAdministrationRejected(
          QuestionnaireAdministrationFailureCode.networkUnavailable,
        ),
      );

  @override
  Future<
    QuestionnaireAdministrationResult<QuestionnaireMetricCompatibilityEvent>
  >
  revokeMetricCompatibility({
    required String eventId,
    required String reason,
    required String requestId,
  }) =>
      _metricRemote?.revokeMetricCompatibility(
        eventId: eventId,
        reason: reason,
        requestId: requestId,
      ) ??
      Future.value(
        const QuestionnaireAdministrationRejected(
          QuestionnaireAdministrationFailureCode.networkUnavailable,
        ),
      );

  Future<QuestionnaireDesignDraft> _mergeServerDraft(
    QuestionnaireDesignDraft serverDraft,
  ) async {
    final query = _database.select(_database.dbQuestionnaireDraftWorkingCopies)
      ..where((row) => row.questionnaireDraftId.equals(serverDraft.id));
    final cached = await query.getSingleOrNull();
    if (cached != null &&
        cached.baseRevision == serverDraft.revision &&
        cached.hasLocalChanges) {
      try {
        return QuestionnaireDesignDraft(
          id: serverDraft.id,
          projectId: serverDraft.projectId,
          sourceVersionId: serverDraft.sourceVersionId,
          revision: serverDraft.revision,
          updatedAtUtc: cached.updatedAtUtc,
          definition: QuestionnaireContract.parseVersion(
            jsonDecode(cached.definitionJson),
          ),
          hasLocalChanges: true,
        );
      } on FormatException {
        // A corrupt cache cannot replace the server contract; overwrite it
        // below with the validated server draft.
      }
    }
    await _store(serverDraft, serverDraft.definition, hasLocalChanges: false);
    return serverDraft;
  }

  Future<void> _store(
    QuestionnaireDesignDraft draft,
    QuestionnaireVersion definition, {
    required bool hasLocalChanges,
  }) => _database
      .into(_database.dbQuestionnaireDraftWorkingCopies)
      .insertOnConflictUpdate(
        DbQuestionnaireDraftWorkingCopiesCompanion.insert(
          questionnaireDraftId: draft.id,
          projectId: draft.projectId,
          sourceVersionId: Value(draft.sourceVersionId),
          baseRevision: draft.revision,
          definitionJson: jsonEncode(
            QuestionnaireContract.versionToJson(definition),
          ),
          hasLocalChanges: hasLocalChanges,
          updatedAtUtc: DateTime.now().toUtc(),
        ),
      );

  @override
  Future<void> close() => _remote.close();
}
