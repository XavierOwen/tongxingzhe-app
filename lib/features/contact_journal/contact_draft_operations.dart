part of 'contact_journal.dart';

/// 接触草稿生命周期的内部实现。
///
/// 这些 extension 方法仍属于 ContactJournal 的公开接口。独立文件只分开实现，
/// 不建立第二个数据库 seam，也不允许 Widget 直接操作草稿表。
extension ContactDraftOperations on ContactJournal {
  /// 自动保存当前接触表单；尚无有意义输入时返回 `null` 且不创建草稿。
  ///
  /// 项目、问卷等上下文本身不算填写内容。该判断由模块统一完成，避免不同
  /// 页面各自决定何时创建空草稿。
  Future<ContactDraft?> saveDraft(ContactDraftInput input) async {
    _validateDraftInput(input);
    await _validateResolvedRegion(input.location);
    if (input.draftId == null && !_hasMeaningfulDraftContent(input)) {
      return null;
    }
    if (input.draftId != null) {
      return _updateDraft(input);
    }

    final draftId = _idGenerator.next();
    final savedAtUtc = _clock.now().toUtc();
    const localRevision = 1;
    const serverRevision = 0;
    final location = _contactLocationColumns(input.location);
    try {
      await _database.transaction(() async {
        await _database
            .into(_database.dbContactDrafts)
            .insert(
              DbContactDraftsCompanion.insert(
                draftId: draftId,
                appUserId: input.appUserId,
                workspaceId: input.workspaceId,
                projectId: input.projectId,
                questionnaireVersionId: input.questionnaireVersionId,
                createdAtUtc: savedAtUtc,
                updatedAtUtc: savedAtUtc,
                occurredAtUtc: Value(input.occurredAtUtc),
                occurredTimeZone: Value(input.occurredTimeZone),
                channel: Value(input.channel?.storageValue),
                channelDetail: Value(input.channelDetail),
                locationKind: Value(location.kind),
                placeName: Value(location.placeName),
                smallestRegionId: Value(location.smallestRegionId),
                regionTreeVersion: Value(location.regionTreeVersion),
                latitude: Value(location.latitude),
                longitude: Value(location.longitude),
                locationAccuracyMeters: Value(location.accuracyMeters),
                locationSourceKind: Value(location.sourceKind),
                locationSourceLatitude: Value(location.sourceLatitude),
                locationSourceLongitude: Value(location.sourceLongitude),
                locationSourceAccuracyMeters: Value(
                  location.sourceAccuracyMeters,
                ),
                locationSourceResolverContractVersion: Value(
                  location.sourceResolverContractVersion,
                ),
                locationSourceRegionTreeContentFingerprint: Value(
                  location.sourceRegionTreeContentFingerprint,
                ),
                reachCount: Value(input.reachCount),
                interestLevel: Value(input.interestLevel),
                syncMode: Value(input.syncMode.storageValue),
                localRevision: const Value(localRevision),
                serverRevision: const Value(serverRevision),
                sourceAttemptId: Value(input.sourceAttemptId),
                upgradedFromDraftId: Value(input.upgradedFromDraftId),
              ),
            );
        await _replaceDraftAnswers(draftId, input.answers);
        await _replaceDraftTargetLinks(draftId, input.targetLinks);
        await _replaceDraftRegionAssignment(draftId, input.location);
        if (input.syncMode == ContactDraftSyncMode.accountPrivate) {
          await _enqueueDraftUpsert(
            input: input,
            draftId: draftId,
            draftCreatedAtUtc: savedAtUtc,
            createdAtUtc: savedAtUtc,
            localRevision: localRevision,
            baseRevision: serverRevision,
          );
        }
      });
    } catch (error, stackTrace) {
      throw ContactPersistenceException(
        code: 'contact_draft_save_failed',
        cause: error,
        stackTrace: stackTrace,
      );
    }

    return ContactDraft(
      draftId: draftId,
      appUserId: input.appUserId,
      workspaceId: input.workspaceId,
      projectId: input.projectId,
      questionnaireVersionId: input.questionnaireVersionId,
      createdAtUtc: savedAtUtc,
      updatedAtUtc: savedAtUtc,
      occurredAtUtc: input.occurredAtUtc,
      occurredTimeZone: input.occurredTimeZone,
      channel: input.channel,
      channelDetail: input.channelDetail,
      location: input.location,
      reachCount: input.reachCount,
      interestLevel: input.interestLevel,
      answers: List.unmodifiable(input.answers),
      targetLinks: List.unmodifiable(input.targetLinks),
      syncMode: input.syncMode,
      localRevision: localRevision,
      serverRevision: serverRevision,
      conflictOfDraftId: null,
      sourceAttemptId: input.sourceAttemptId,
      upgradedFromDraftId: input.upgradedFromDraftId,
    );
  }

  Future<ContactDraft> _updateDraft(ContactDraftInput input) async {
    final savedAtUtc = _clock.now().toUtc();
    final location = _contactLocationColumns(input.location);
    try {
      return await _database.transaction(() async {
        final query = _database.select(_database.dbContactDrafts)
          ..where(
            (row) =>
                row.draftId.equals(input.draftId!) &
                row.appUserId.equals(input.appUserId),
          );
        final existing = await query.getSingleOrNull();
        if (existing == null) {
          throw const ContactValidationException('contact_draft_not_found');
        }
        if (existing.abandonedAtUtc != null) {
          throw const ContactValidationException('contact_draft_abandoned');
        }
        if (existing.workspaceId != input.workspaceId ||
            existing.projectId != input.projectId ||
            existing.questionnaireVersionId != input.questionnaireVersionId ||
            existing.sourceAttemptId != input.sourceAttemptId ||
            existing.upgradedFromDraftId != input.upgradedFromDraftId) {
          throw const ContactValidationException(
            'contact_draft_context_immutable',
          );
        }
        if (existing.syncMode != input.syncMode.storageValue &&
            await _hasAttemptedUnconfirmedDraftCommand(existing.draftId)) {
          throw const ContactValidationException(
            'draft_sync_transition_waiting_for_confirmation',
          );
        }
        final localRevision = existing.localRevision + 1;

        await (_database.update(
          _database.dbContactDrafts,
        )..where((row) => row.draftId.equals(existing.draftId))).write(
          DbContactDraftsCompanion(
            updatedAtUtc: Value(savedAtUtc),
            occurredAtUtc: Value(input.occurredAtUtc),
            occurredTimeZone: Value(input.occurredTimeZone),
            channel: Value(input.channel?.storageValue),
            channelDetail: Value(input.channelDetail),
            locationKind: Value(location.kind),
            placeName: Value(location.placeName),
            smallestRegionId: Value(location.smallestRegionId),
            regionTreeVersion: Value(location.regionTreeVersion),
            latitude: Value(location.latitude),
            longitude: Value(location.longitude),
            locationAccuracyMeters: Value(location.accuracyMeters),
            locationSourceKind: Value(location.sourceKind),
            locationSourceLatitude: Value(location.sourceLatitude),
            locationSourceLongitude: Value(location.sourceLongitude),
            locationSourceAccuracyMeters: Value(location.sourceAccuracyMeters),
            locationSourceResolverContractVersion: Value(
              location.sourceResolverContractVersion,
            ),
            locationSourceRegionTreeContentFingerprint: Value(
              location.sourceRegionTreeContentFingerprint,
            ),
            reachCount: Value(input.reachCount),
            interestLevel: Value(input.interestLevel),
            syncMode: Value(input.syncMode.storageValue),
            localRevision: Value(localRevision),
          ),
        );
        await _replaceDraftAnswers(existing.draftId, input.answers);
        await _replaceDraftTargetLinks(existing.draftId, input.targetLinks);
        await _replaceDraftRegionAssignment(existing.draftId, input.location);
        if (input.syncMode == ContactDraftSyncMode.accountPrivate) {
          await _deleteUnsentDraftDeletes(existing.draftId);
          await _enqueueDraftUpsert(
            input: input,
            draftId: existing.draftId,
            draftCreatedAtUtc: existing.createdAtUtc.toUtc(),
            createdAtUtc: savedAtUtc,
            localRevision: localRevision,
            baseRevision: existing.serverRevision,
          );
        } else {
          await _prepareRemoteDraftDelete(
            existing,
            deviceId: input.deviceId,
            createdAtUtc: savedAtUtc,
          );
        }
        return ContactDraft(
          draftId: existing.draftId,
          appUserId: existing.appUserId,
          workspaceId: existing.workspaceId,
          projectId: existing.projectId,
          questionnaireVersionId: existing.questionnaireVersionId,
          createdAtUtc: existing.createdAtUtc.toUtc(),
          updatedAtUtc: savedAtUtc,
          occurredAtUtc: input.occurredAtUtc,
          occurredTimeZone: input.occurredTimeZone,
          channel: input.channel,
          channelDetail: input.channelDetail,
          location: input.location,
          reachCount: input.reachCount,
          interestLevel: input.interestLevel,
          answers: List.unmodifiable(input.answers),
          targetLinks: List.unmodifiable(input.targetLinks),
          syncMode: input.syncMode,
          localRevision: localRevision,
          serverRevision: existing.serverRevision,
          conflictOfDraftId: existing.conflictOfDraftId,
          sourceAttemptId: existing.sourceAttemptId,
          upgradedFromDraftId: existing.upgradedFromDraftId,
        );
      });
    } on ContactValidationException {
      rethrow;
    } catch (error, stackTrace) {
      throw ContactPersistenceException(
        code: 'contact_draft_save_failed',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// 按稳定 ID 读取创建者仍在填写的草稿。
  ///
  /// 查询不使用当前项目筛选。草稿创建后保留原项目归属，调用者切换项目不会
  /// 使稳定地址失效。其他用户和已放弃草稿都返回 `null`。
  Future<ContactDraft?> draftByIdForOwner({
    required String draftId,
    required String appUserId,
  }) async {
    final query = _database.select(_database.dbContactDrafts)
      ..where(
        (row) =>
            row.draftId.equals(draftId) &
            row.appUserId.equals(appUserId) &
            row.abandonedAtUtc.isNull(),
      );
    final row = await query.getSingleOrNull();
    if (row == null) {
      return null;
    }
    final answerQuery = _database.select(_database.dbContactDraftAnswers)
      ..where((answer) => answer.draftId.equals(draftId))
      ..orderBy([(answer) => OrderingTerm.asc(answer.questionId)]);
    return _draftFromRow(
      row,
      await answerQuery.get(),
      await _draftTargetLinkRows(draftId),
    );
  }

  /// 列出一位创建者仍在填写的全部私有草稿，最近修改的排在前面。
  Future<List<ContactDraft>> listDrafts({required String appUserId}) async {
    final query = _database.select(_database.dbContactDrafts)
      ..where(
        (row) => row.appUserId.equals(appUserId) & row.abandonedAtUtc.isNull(),
      )
      ..orderBy([
        (row) => OrderingTerm.desc(row.updatedAtUtc),
        (row) => OrderingTerm.asc(row.draftId),
      ]);
    final rows = await query.get();
    if (rows.isEmpty) {
      return const [];
    }
    final draftIds = [for (final row in rows) row.draftId];
    final answerQuery = _database.select(_database.dbContactDraftAnswers)
      ..where((row) => row.draftId.isIn(draftIds))
      ..orderBy([
        (row) => OrderingTerm.asc(row.draftId),
        (row) => OrderingTerm.asc(row.questionId),
      ]);
    final answerRows = await answerQuery.get();
    final targetLinkRows = await (_database.select(
      _database.dbContactDraftTargetLinks,
    )..where((row) => row.draftId.isIn(draftIds))).get();
    final answersByDraftId = <String, List<DbContactDraftAnswer>>{};
    for (final answer in answerRows) {
      answersByDraftId.putIfAbsent(answer.draftId, () => []).add(answer);
    }
    final targetLinksByDraftId = <String, List<DbContactDraftTargetLink>>{};
    for (final link in targetLinkRows) {
      targetLinksByDraftId.putIfAbsent(link.draftId, () => []).add(link);
    }
    return [
      for (final row in rows)
        _draftFromRow(
          row,
          answersByDraftId[row.draftId] ?? const [],
          targetLinksByDraftId[row.draftId] ?? const [],
        ),
    ];
  }

  /// 把本人旧问卷草稿复制为当前目标版本的新草稿，原草稿保持不变。
  ///
  /// [copiedAnswers] 必须先由问卷升级规划器按审计兼容关系产生。本方法再次
  /// 对目标定义验证这些答案，并用来源草稿与目标版本生成稳定 ID，使中断后的
  /// 重试返回同一份新草稿。
  Future<ContactDraft> upgradeDraft({
    required String sourceDraftId,
    required String appUserId,
    required String deviceId,
    required QuestionnaireVersion targetVersion,
    required List<QuestionnaireAnswer> copiedAnswers,
  }) async {
    if (sourceDraftId.trim().isEmpty ||
        appUserId.trim().isEmpty ||
        deviceId.trim().isEmpty) {
      throw const ContactValidationException('contact_draft_upgrade_invalid');
    }
    final parsedTarget = QuestionnaireContract.parseVersion(
      QuestionnaireContract.versionToJson(targetVersion),
    );
    final copiedIds = copiedAnswers.map((answer) => answer.questionId).toSet();
    if (copiedIds.length != copiedAnswers.length) {
      throw const ContactValidationException('duplicate_question_answer');
    }
    final evaluation = QuestionnaireCatalog.evaluate(
      parsedTarget,
      copiedAnswers,
    );
    if (evaluation.errors.any(
          (error) => copiedIds.contains(error.questionId),
        ) ||
        evaluation.answers
                .where(
                  (answer) =>
                      copiedIds.contains(answer.questionId) &&
                      answer.stateReason != questionnaireRuleSkippedReason,
                )
                .length !=
            copiedAnswers.length) {
      throw const ContactValidationException(
        'contact_draft_upgrade_answers_invalid',
      );
    }
    final normalizedAnswers = [
      for (final question in parsedTarget.questions)
        for (final answer in evaluation.answers)
          if (answer.questionId == question.id &&
              copiedIds.contains(answer.questionId) &&
              answer.stateReason != questionnaireRuleSkippedReason)
            answer,
    ];
    final targetDraftId =
        '$sourceDraftId:questionnaire-upgrade:${parsedTarget.id}';
    final createdAtUtc = _clock.now().toUtc();
    try {
      return await _database.transaction(() async {
        final sourceQuery = _database.select(_database.dbContactDrafts)
          ..where(
            (row) =>
                row.draftId.equals(sourceDraftId) &
                row.appUserId.equals(appUserId) &
                row.abandonedAtUtc.isNull(),
          );
        final sourceRow = await sourceQuery.getSingleOrNull();
        if (sourceRow == null) {
          throw const ContactValidationException('contact_draft_not_found');
        }
        if (sourceRow.conflictOfDraftId != null ||
            sourceRow.projectId != parsedTarget.projectId ||
            sourceRow.questionnaireVersionId == parsedTarget.id) {
          throw const ContactValidationException(
            'contact_draft_upgrade_invalid',
          );
        }
        final targetVersionQuery =
            _database.select(_database.dbQuestionnaireVersions)..where(
              (row) =>
                  row.questionnaireVersionId.equals(parsedTarget.id) &
                  row.projectId.equals(parsedTarget.projectId) &
                  row.versionNumber.equals(parsedTarget.versionNumber) &
                  row.status.equals('published'),
            );
        if (await targetVersionQuery.getSingleOrNull() == null) {
          throw const ContactValidationException(
            'questionnaire_target_not_installed',
          );
        }
        final existingQuery = _database.select(_database.dbContactDrafts)
          ..where(
            (row) =>
                row.draftId.equals(targetDraftId) &
                row.appUserId.equals(appUserId) &
                row.abandonedAtUtc.isNull(),
          );
        final existing = await existingQuery.getSingleOrNull();
        if (existing != null) {
          final answerQuery = _database.select(_database.dbContactDraftAnswers)
            ..where((row) => row.draftId.equals(targetDraftId));
          final answerRows = await answerQuery.get();
          final answersById = {
            for (final row in answerRows) row.questionId: row,
          };
          return _draftFromRow(existing, [
            for (final question in parsedTarget.questions)
              ?answersById[question.id],
          ], await _draftTargetLinkRows(targetDraftId));
        }

        final source = _draftFromRow(
          sourceRow,
          await (_database.select(
            _database.dbContactDraftAnswers,
          )..where((row) => row.draftId.equals(sourceDraftId))).get(),
          await _draftTargetLinkRows(sourceDraftId),
        );
        final location = _contactLocationColumns(source.location);
        const localRevision = 1;
        const serverRevision = 0;
        await _database
            .into(_database.dbContactDrafts)
            .insert(
              DbContactDraftsCompanion.insert(
                draftId: targetDraftId,
                appUserId: source.appUserId,
                workspaceId: source.workspaceId,
                projectId: source.projectId,
                questionnaireVersionId: parsedTarget.id,
                createdAtUtc: createdAtUtc,
                updatedAtUtc: createdAtUtc,
                occurredAtUtc: Value(source.occurredAtUtc),
                occurredTimeZone: Value(source.occurredTimeZone),
                channel: Value(source.channel?.storageValue),
                channelDetail: Value(source.channelDetail),
                locationKind: Value(location.kind),
                placeName: Value(location.placeName),
                smallestRegionId: Value(location.smallestRegionId),
                regionTreeVersion: Value(location.regionTreeVersion),
                latitude: Value(location.latitude),
                longitude: Value(location.longitude),
                locationAccuracyMeters: Value(location.accuracyMeters),
                locationSourceKind: Value(location.sourceKind),
                locationSourceLatitude: Value(location.sourceLatitude),
                locationSourceLongitude: Value(location.sourceLongitude),
                locationSourceAccuracyMeters: Value(
                  location.sourceAccuracyMeters,
                ),
                locationSourceResolverContractVersion: Value(
                  location.sourceResolverContractVersion,
                ),
                locationSourceRegionTreeContentFingerprint: Value(
                  location.sourceRegionTreeContentFingerprint,
                ),
                reachCount: Value(source.reachCount),
                interestLevel: Value(source.interestLevel),
                syncMode: Value(source.syncMode.storageValue),
                localRevision: const Value(localRevision),
                serverRevision: const Value(serverRevision),
                sourceAttemptId: Value(source.sourceAttemptId),
                upgradedFromDraftId: Value(sourceDraftId),
              ),
            );
        await _replaceDraftAnswers(targetDraftId, normalizedAnswers);
        await _replaceDraftTargetLinks(targetDraftId, source.targetLinks);
        await _replaceDraftRegionAssignment(targetDraftId, source.location);
        final upgraded = ContactDraft(
          draftId: targetDraftId,
          appUserId: source.appUserId,
          workspaceId: source.workspaceId,
          projectId: source.projectId,
          questionnaireVersionId: parsedTarget.id,
          createdAtUtc: createdAtUtc,
          updatedAtUtc: createdAtUtc,
          occurredAtUtc: source.occurredAtUtc,
          occurredTimeZone: source.occurredTimeZone,
          channel: source.channel,
          channelDetail: source.channelDetail,
          location: source.location,
          reachCount: source.reachCount,
          interestLevel: source.interestLevel,
          answers: normalizedAnswers,
          targetLinks: source.targetLinks,
          syncMode: source.syncMode,
          localRevision: localRevision,
          serverRevision: serverRevision,
          conflictOfDraftId: null,
          sourceAttemptId: source.sourceAttemptId,
          upgradedFromDraftId: sourceDraftId,
        );
        if (upgraded.syncMode == ContactDraftSyncMode.accountPrivate) {
          await _enqueueDraftUpsert(
            input: _draftInputFromStored(upgraded, deviceId),
            draftId: targetDraftId,
            draftCreatedAtUtc: createdAtUtc,
            createdAtUtc: createdAtUtc,
            localRevision: localRevision,
            baseRevision: serverRevision,
          );
        }
        return upgraded;
      });
    } on ContactValidationException {
      rethrow;
    } catch (error, stackTrace) {
      throw ContactPersistenceException(
        code: 'contact_draft_upgrade_failed',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// 本人明确放弃一份草稿，并返回持久化的短时撤销期限。
  Future<ContactDraftAbandonmentReceipt> abandonDraft({
    required String draftId,
    required String appUserId,
    required String deviceId,
  }) async {
    final abandonedAtUtc = _clock.now().toUtc();
    final undoUntilUtc = abandonedAtUtc.add(ContactJournal._abandonUndoWindow);
    try {
      await _database.transaction(() async {
        final query = _database.select(_database.dbContactDrafts)
          ..where(
            (row) =>
                row.draftId.equals(draftId) &
                row.appUserId.equals(appUserId) &
                row.abandonedAtUtc.isNull(),
          );
        final existing = await query.getSingleOrNull();
        if (existing == null) {
          throw const ContactValidationException('contact_draft_not_found');
        }
        await (_database.update(
          _database.dbContactDrafts,
        )..where((row) => row.draftId.equals(draftId))).write(
          DbContactDraftsCompanion(
            updatedAtUtc: Value(abandonedAtUtc),
            abandonedAtUtc: Value(abandonedAtUtc),
            undoUntilUtc: Value(undoUntilUtc),
          ),
        );
        await _prepareRemoteDraftDelete(
          existing,
          deviceId: deviceId,
          createdAtUtc: abandonedAtUtc,
        );
      });
    } on ContactValidationException {
      rethrow;
    } catch (error, stackTrace) {
      throw ContactPersistenceException(
        code: 'contact_draft_abandon_failed',
        cause: error,
        stackTrace: stackTrace,
      );
    }
    return ContactDraftAbandonmentReceipt(
      draftId: draftId,
      undoUntilUtc: undoUntilUtc,
    );
  }

  /// 在回执期限内撤销一次草稿放弃；过期后保持隐藏。
  Future<ContactDraft> undoAbandonDraft({
    required String draftId,
    required String appUserId,
    required String deviceId,
  }) async {
    final restoredAtUtc = _clock.now().toUtc();
    try {
      return await _database.transaction(() async {
        final query = _database.select(_database.dbContactDrafts)
          ..where(
            (row) =>
                row.draftId.equals(draftId) & row.appUserId.equals(appUserId),
          );
        final existing = await query.getSingleOrNull();
        if (existing == null || existing.abandonedAtUtc == null) {
          throw const ContactValidationException('contact_draft_not_found');
        }
        if (restoredAtUtc.isAfter(existing.undoUntilUtc!.toUtc())) {
          throw const ContactValidationException('contact_draft_undo_expired');
        }
        final localRevision = existing.localRevision + 1;
        await (_database.update(
          _database.dbContactDrafts,
        )..where((row) => row.draftId.equals(draftId))).write(
          DbContactDraftsCompanion(
            updatedAtUtc: Value(restoredAtUtc),
            abandonedAtUtc: const Value(null),
            undoUntilUtc: const Value(null),
            localRevision: Value(localRevision),
          ),
        );
        final restored = await query.getSingle();
        final answerQuery = _database.select(_database.dbContactDraftAnswers)
          ..where((row) => row.draftId.equals(draftId));
        final answers = await answerQuery.get();
        final restoredDraft = _draftFromRow(
          restored,
          answers,
          await _draftTargetLinkRows(draftId),
        );
        await _deleteUnsentDraftDeletes(draftId);
        if (restoredDraft.syncMode == ContactDraftSyncMode.accountPrivate) {
          await _enqueueDraftUpsert(
            input: _draftInputFromStored(restoredDraft, deviceId),
            draftId: draftId,
            draftCreatedAtUtc: restoredDraft.createdAtUtc,
            createdAtUtc: restoredAtUtc,
            localRevision: localRevision,
            baseRevision: restoredDraft.serverRevision,
          );
        }
        return restoredDraft;
      });
    } on ContactValidationException {
      rethrow;
    } catch (error, stackTrace) {
      throw ContactPersistenceException(
        code: 'contact_draft_undo_failed',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _validateDraftInput(ContactDraftInput input) {
    if (input.appUserId.trim().isEmpty ||
        input.workspaceId.trim().isEmpty ||
        input.projectId.trim().isEmpty ||
        input.questionnaireVersionId.trim().isEmpty) {
      throw const ContactValidationException('contact_context_required');
    }
    if (input.deviceId.trim().isEmpty) {
      throw const ContactValidationException('contact_device_required');
    }
    if (input.sourceAttemptId != null &&
        input.sourceAttemptId!.trim().isEmpty) {
      throw const ContactValidationException('source_attempt_id_invalid');
    }
    if (input.upgradedFromDraftId != null &&
        (input.upgradedFromDraftId!.trim().isEmpty ||
            input.upgradedFromDraftId == input.draftId)) {
      throw const ContactValidationException('upgraded_from_draft_id_invalid');
    }
    if (input.occurredAtUtc != null && !input.occurredAtUtc!.isUtc) {
      throw const ContactValidationException('occurred_at_must_be_utc');
    }
    if ((input.occurredAtUtc == null) !=
        (input.occurredTimeZone == null ||
            input.occurredTimeZone!.trim().isEmpty)) {
      throw const ContactValidationException('draft_occurrence_incomplete');
    }
    if (input.reachCount != null && input.reachCount! < 1) {
      throw const ContactValidationException('reach_count_must_be_positive');
    }
    if (input.interestLevel != null &&
        (input.interestLevel! < 0 || input.interestLevel! > 4)) {
      throw const ContactValidationException('interest_level_out_of_range');
    }
    _validateLocationWhenPresent(input.location);
    final questionIds = <String>{};
    for (final answer in input.answers) {
      if (answer.questionId.trim().isEmpty) {
        throw const ContactValidationException('question_id_required');
      }
      if (!questionIds.add(answer.questionId)) {
        throw const ContactValidationException('duplicate_question_answer');
      }
    }
    _validateTargetLinks(input.targetLinks);
  }

  bool _hasMeaningfulDraftContent(ContactDraftInput input) {
    return input.sourceAttemptId != null ||
        input.occurredAtUtc != null ||
        input.channel != null ||
        (input.channelDetail?.trim().isNotEmpty ?? false) ||
        input.location != null ||
        input.reachCount != null ||
        input.interestLevel != null ||
        input.answers.isNotEmpty ||
        input.targetLinks.isNotEmpty ||
        input.syncMode != ContactDraftSyncMode.accountPrivate;
  }

  /// 同一份尚未发送的自动保存只保留最新快照，避免每次按键都上传一条命令。
  Future<void> _enqueueDraftUpsert({
    required ContactDraftInput input,
    required String draftId,
    required DateTime draftCreatedAtUtc,
    required DateTime createdAtUtc,
    required int localRevision,
    required int baseRevision,
  }) async {
    await _deleteUnsentDraftUpserts(draftId);
    final location = _contactLocationColumns(input.location);
    final payload = jsonEncode({
      'draft_id': draftId,
      'workspace_id': input.workspaceId,
      'project_id': input.projectId,
      'questionnaire_version_id': input.questionnaireVersionId,
      'source_attempt_id': input.sourceAttemptId,
      'upgraded_from_draft_id': input.upgradedFromDraftId,
      'created_at_utc': draftCreatedAtUtc.toIso8601String(),
      'updated_at_utc': createdAtUtc.toIso8601String(),
      'occurred_at_utc': input.occurredAtUtc?.toIso8601String(),
      'occurred_time_zone': input.occurredTimeZone,
      'channel': input.channel?.storageValue,
      'channel_detail': input.channelDetail,
      'location': input.location == null
          ? null
          : {
              'kind': location.kind,
              'place_name': location.placeName,
              'smallest_region_id': location.smallestRegionId,
              'region_tree_version': location.regionTreeVersion,
              'latitude': location.latitude,
              'longitude': location.longitude,
              'accuracy_meters': location.accuracyMeters,
            },
      'location_source': _locationSourceWirePayload(input.location),
      'reach_count': input.reachCount,
      'interest_level': input.interestLevel,
      'answers': [
        for (final answer in input.answers)
          QuestionnaireAnswerCodec.toJson(answer),
      ],
      'target_links': _targetLinkPayload(input.targetLinks),
    });
    await _database
        .into(_database.dbSyncOutbox)
        .insert(
          DbSyncOutboxCompanion.insert(
            commandId: '$draftId:draft-upsert:$localRevision',
            protocolVersion: 1,
            commandType: 'draft.upsert.v1',
            deviceId: input.deviceId,
            aggregateId: draftId,
            appUserId: Value(input.appUserId),
            workspaceId: Value(input.workspaceId),
            projectId: Value(input.projectId),
            baseRevision: baseRevision,
            payloadJson: payload,
            createdAtUtc: createdAtUtc,
            status: 'pending',
            nextAttemptAtUtc: createdAtUtc,
          ),
        );
  }

  Future<void> _deleteUnsentDraftUpserts(String draftId) async {
    await (_database.delete(_database.dbSyncOutbox)..where(
          (row) =>
              row.aggregateId.equals(draftId) &
              row.commandType.equals('draft.upsert.v1') &
              row.status.equals('pending') &
              row.attemptCount.equals(0),
        ))
        .go();
  }

  Future<void> _prepareRemoteDraftDelete(
    DbContactDraft draft, {
    required String deviceId,
    required DateTime createdAtUtc,
  }) async {
    await _deleteUnsentDraftUpserts(draft.draftId);
    if (draft.syncMode != ContactDraftSyncMode.accountPrivate.storageValue ||
        draft.serverRevision == 0) {
      return;
    }
    await _deleteUnsentDraftDeletes(draft.draftId);
    await _database
        .into(_database.dbSyncOutbox)
        .insert(
          DbSyncOutboxCompanion.insert(
            commandId:
                '${draft.draftId}:draft-delete:'
                '${draft.serverRevision + 1}',
            protocolVersion: 1,
            commandType: 'draft.delete.v1',
            deviceId: deviceId,
            aggregateId: draft.draftId,
            appUserId: Value(draft.appUserId),
            workspaceId: Value(draft.workspaceId),
            projectId: Value(draft.projectId),
            baseRevision: draft.serverRevision,
            payloadJson: jsonEncode({
              'draft_id': draft.draftId,
              'workspace_id': draft.workspaceId,
              'project_id': draft.projectId,
            }),
            createdAtUtc: createdAtUtc,
            status: 'pending',
            nextAttemptAtUtc: createdAtUtc,
          ),
        );
  }

  Future<void> _deleteUnsentDraftDeletes(String draftId) async {
    await (_database.delete(_database.dbSyncOutbox)..where(
          (row) =>
              row.aggregateId.equals(draftId) &
              row.commandType.equals('draft.delete.v1') &
              row.status.equals('pending') &
              row.attemptCount.equals(0),
        ))
        .go();
  }

  Future<bool> _hasAttemptedUnconfirmedDraftCommand(String draftId) async {
    final query = _database.select(_database.dbSyncOutbox)
      ..where(
        (row) =>
            row.aggregateId.equals(draftId) &
            (row.commandType.equals('draft.upsert.v1') |
                row.commandType.equals('draft.delete.v1')) &
            row.status.isNotValue('completed') &
            row.attemptCount.isBiggerThanValue(0),
      );
    return (await query.get()).isNotEmpty;
  }

  ContactDraftInput _draftInputFromStored(ContactDraft draft, String deviceId) {
    return ContactDraftInput(
      draftId: draft.draftId,
      deviceId: deviceId,
      appUserId: draft.appUserId,
      workspaceId: draft.workspaceId,
      projectId: draft.projectId,
      questionnaireVersionId: draft.questionnaireVersionId,
      sourceAttemptId: draft.sourceAttemptId,
      upgradedFromDraftId: draft.upgradedFromDraftId,
      occurredAtUtc: draft.occurredAtUtc,
      occurredTimeZone: draft.occurredTimeZone,
      channel: draft.channel,
      channelDetail: draft.channelDetail,
      location: draft.location,
      reachCount: draft.reachCount,
      interestLevel: draft.interestLevel,
      answers: draft.answers,
      targetLinks: draft.targetLinks,
      syncMode: draft.syncMode,
    );
  }

  Future<void> _replaceDraftAnswers(
    String draftId,
    List<QuestionnaireAnswer> answers,
  ) async {
    await (_database.delete(
      _database.dbContactDraftAnswers,
    )..where((row) => row.draftId.equals(draftId))).go();
    for (final answer in answers) {
      final columns = QuestionnaireAnswerCodec.toColumns(answer);
      await _database
          .into(_database.dbContactDraftAnswers)
          .insert(
            DbContactDraftAnswersCompanion.insert(
              draftId: draftId,
              questionId: columns.questionId,
              answerState: columns.state,
              answerStateReason: Value(columns.stateReason),
              answerType: columns.type,
              booleanValue: Value(columns.booleanValue),
              textValue: Value(columns.textValue),
              numberValue: Value(columns.numberValue),
              multiChoiceValueJson: Value(columns.multiChoiceValueJson),
            ),
          );
    }
  }

  Future<void> _replaceDraftTargetLinks(
    String draftId,
    List<ContactTargetLink> targetLinks,
  ) async {
    await (_database.delete(
      _database.dbContactDraftTargetLinks,
    )..where((row) => row.draftId.equals(draftId))).go();
    for (final link in targetLinks) {
      await _database
          .into(_database.dbContactDraftTargetLinks)
          .insert(
            DbContactDraftTargetLinksCompanion.insert(
              draftId: draftId,
              targetId: link.targetId,
              targetType: link.targetType.storageValue,
              responseLevel: Value(link.responseLevel),
              followUpConsent: link.followUpConsent.storageValue,
              institutionRepresentativeConfirmed:
                  link.institutionRepresentativeConfirmed,
              confirmStageZero: link.confirmStageZero,
            ),
          );
    }
  }

  Future<List<DbContactDraftTargetLink>> _draftTargetLinkRows(String draftId) {
    final query = _database.select(_database.dbContactDraftTargetLinks)
      ..where((row) => row.draftId.equals(draftId))
      ..orderBy([(row) => OrderingTerm.asc(row.targetId)]);
    return query.get();
  }

  ContactDraft _draftFromRow(
    DbContactDraft row,
    List<DbContactDraftAnswer> answerRows,
    List<DbContactDraftTargetLink> targetLinkRows,
  ) {
    return ContactDraft(
      draftId: row.draftId,
      appUserId: row.appUserId,
      workspaceId: row.workspaceId,
      projectId: row.projectId,
      questionnaireVersionId: row.questionnaireVersionId,
      // Native SQLite 可按设备本地时区重建同一瞬间；领域接口统一返回 UTC，
      // 避免调用者把时区表现差异误当成草稿时间发生了变化。
      createdAtUtc: row.createdAtUtc.toUtc(),
      updatedAtUtc: row.updatedAtUtc.toUtc(),
      occurredAtUtc: row.occurredAtUtc?.toUtc(),
      occurredTimeZone: row.occurredTimeZone,
      channel: row.channel == null
          ? null
          : ContactChannel.fromStorage(row.channel!),
      channelDetail: row.channelDetail,
      location: _draftLocationFromRow(row),
      reachCount: row.reachCount,
      interestLevel: row.interestLevel,
      answers: [
        for (final answer in answerRows)
          QuestionnaireAnswerCodec.fromColumns(
            questionId: answer.questionId,
            state: answer.answerState,
            stateReason: answer.answerStateReason,
            type: answer.answerType,
            booleanValue: answer.booleanValue,
            textValue: answer.textValue,
            numberValue: answer.numberValue,
            multiChoiceValueJson: answer.multiChoiceValueJson,
          ),
      ],
      targetLinks: [
        for (final link in targetLinkRows)
          ContactTargetLink(
            targetId: link.targetId,
            targetType: PromotionTargetType.values.singleWhere(
              (type) => type.storageValue == link.targetType,
            ),
            responseLevel: link.responseLevel,
            followUpConsent: ContactFollowUpConsent.fromStorage(
              link.followUpConsent,
            ),
            institutionRepresentativeConfirmed:
                link.institutionRepresentativeConfirmed,
            confirmStageZero: link.confirmStageZero,
          ),
      ],
      syncMode: ContactDraftSyncMode.fromStorage(row.syncMode),
      localRevision: row.localRevision,
      serverRevision: row.serverRevision,
      conflictOfDraftId: row.conflictOfDraftId,
      sourceAttemptId: row.sourceAttemptId,
      upgradedFromDraftId: row.upgradedFromDraftId,
    );
  }

  ContactLocation? _draftLocationFromRow(DbContactDraft row) {
    return switch (row.locationKind) {
      null => null,
      'resolved' => ResolvedContactLocation(
        placeName: row.placeName!,
        smallestRegionId: row.smallestRegionId!,
        regionTreeVersion: row.regionTreeVersion!,
        source: _capturedSourceFromColumns(
          kind: row.locationSourceKind,
          latitude: row.locationSourceLatitude,
          longitude: row.locationSourceLongitude,
          accuracyMeters: row.locationSourceAccuracyMeters,
          resolverContractVersion: row.locationSourceResolverContractVersion,
          regionTreeContentFingerprint:
              row.locationSourceRegionTreeContentFingerprint,
        ),
      ),
      'not_applicable' => const NotApplicableContactLocation(),
      'pending_resolution' => PendingContactLocation(
        latitude: row.latitude!,
        longitude: row.longitude!,
        accuracyMeters: row.locationAccuracyMeters,
      ),
      final unsupported => throw StateError(
        'unsupported_contact_location_kind:$unsupported',
      ),
    };
  }

  ({
    String? kind,
    String? placeName,
    String? smallestRegionId,
    String? regionTreeVersion,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
    String? sourceKind,
    double? sourceLatitude,
    double? sourceLongitude,
    double? sourceAccuracyMeters,
    String? sourceResolverContractVersion,
    String? sourceRegionTreeContentFingerprint,
  })
  _contactLocationColumns(ContactLocation? location) {
    return switch (location) {
      null => (
        kind: null,
        placeName: null,
        smallestRegionId: null,
        regionTreeVersion: null,
        latitude: null,
        longitude: null,
        accuracyMeters: null,
        sourceKind: null,
        sourceLatitude: null,
        sourceLongitude: null,
        sourceAccuracyMeters: null,
        sourceResolverContractVersion: null,
        sourceRegionTreeContentFingerprint: null,
      ),
      final ResolvedContactLocation resolved => (
        kind: 'resolved',
        placeName: resolved.placeName,
        smallestRegionId: resolved.smallestRegionId,
        regionTreeVersion: resolved.regionTreeVersion,
        latitude: null,
        longitude: null,
        accuracyMeters: null,
        sourceKind: resolved.source == null ? null : 'captured_coordinates',
        sourceLatitude: resolved.source?.latitude,
        sourceLongitude: resolved.source?.longitude,
        sourceAccuracyMeters: resolved.source?.accuracyMeters,
        sourceResolverContractVersion: resolved.source?.resolverContractVersion,
        sourceRegionTreeContentFingerprint:
            resolved.source?.regionTreeContentFingerprint,
      ),
      NotApplicableContactLocation() => (
        kind: 'not_applicable',
        placeName: null,
        smallestRegionId: null,
        regionTreeVersion: null,
        latitude: null,
        longitude: null,
        accuracyMeters: null,
        sourceKind: null,
        sourceLatitude: null,
        sourceLongitude: null,
        sourceAccuracyMeters: null,
        sourceResolverContractVersion: null,
        sourceRegionTreeContentFingerprint: null,
      ),
      final PendingContactLocation pending => (
        kind: 'pending_resolution',
        placeName: null,
        smallestRegionId: null,
        regionTreeVersion: null,
        latitude: pending.latitude,
        longitude: pending.longitude,
        accuracyMeters: pending.accuracyMeters,
        sourceKind: null,
        sourceLatitude: null,
        sourceLongitude: null,
        sourceAccuracyMeters: null,
        sourceResolverContractVersion: null,
        sourceRegionTreeContentFingerprint: null,
      ),
    };
  }

  Map<String, Object?>? _locationSourceWirePayload(ContactLocation? location) {
    final source = switch (location) {
      final ResolvedContactLocation resolved => resolved.source,
      _ => null,
    };
    if (source == null) {
      return null;
    }
    return {
      'kind': 'captured_coordinates',
      'latitude': source.latitude,
      'longitude': source.longitude,
      'accuracy_meters': source.accuracyMeters,
      'resolver_contract_version': source.resolverContractVersion,
      'region_tree_content_fingerprint': source.regionTreeContentFingerprint,
    };
  }

  CapturedCoordinatesLocationSource? _capturedSourceFromColumns({
    required String? kind,
    required double? latitude,
    required double? longitude,
    required double? accuracyMeters,
    required String? resolverContractVersion,
    required String? regionTreeContentFingerprint,
  }) {
    if (kind == null) {
      return null;
    }
    if (kind != 'captured_coordinates' ||
        latitude == null ||
        longitude == null ||
        resolverContractVersion == null ||
        regionTreeContentFingerprint == null) {
      throw const FormatException('invalid stored contact location source');
    }
    return CapturedCoordinatesLocationSource(
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracyMeters,
      resolverContractVersion: resolverContractVersion,
      regionTreeContentFingerprint: regionTreeContentFingerprint,
    );
  }

  void _validateLocationWhenPresent(ContactLocation? location) {
    if (location case final PendingContactLocation pending) {
      final accuracy = pending.accuracyMeters;
      if (!pending.latitude.isFinite ||
          pending.latitude < -90 ||
          pending.latitude > 90 ||
          !pending.longitude.isFinite ||
          pending.longitude < -180 ||
          pending.longitude > 180 ||
          (accuracy != null && (!accuracy.isFinite || accuracy < 0))) {
        throw const ContactValidationException('invalid_pending_location');
      }
    }
    if (location case final ResolvedContactLocation resolved) {
      if (resolved.placeName.trim().isEmpty ||
          resolved.smallestRegionId.trim().isEmpty ||
          resolved.regionTreeVersion.trim().isEmpty) {
        throw const ContactValidationException('resolved_location_required');
      }
      final source = resolved.source;
      if (source != null &&
          (!source.latitude.isFinite ||
              source.latitude < -90 ||
              source.latitude > 90 ||
              !source.longitude.isFinite ||
              source.longitude < -180 ||
              source.longitude > 180 ||
              (source.accuracyMeters != null &&
                  (!source.accuracyMeters!.isFinite ||
                      source.accuracyMeters! < 0)) ||
              source.resolverContractVersion !=
                  'canonical-region-resolution:v1' ||
              !RegExp(
                r'^[0-9a-f]{64}$',
              ).hasMatch(source.regionTreeContentFingerprint))) {
        throw const ContactValidationException('invalid_location_source');
      }
    }
  }

  /// 把本人拥有的完整草稿原子转换为匿名接触。
  ///
  /// 输入中的归属 ID 来自草稿；本地保存不代表远端授权成功。成功时会在同一
  /// 事务写入当前投影、首个 revision 和唯一同步命令，再删除草稿。任一步失败
  /// 都会回滚，数据库错误转换为稳定的 [ContactPersistenceException]。
  Future<ContactSubmissionReceipt> submitDraft({
    required String draftId,
    required String appUserId,
    required String deviceId,
  }) async {
    try {
      return await _database.transaction(() async {
        final draftQuery = _database.select(_database.dbContactDrafts)
          ..where(
            (row) =>
                row.draftId.equals(draftId) &
                row.appUserId.equals(appUserId) &
                row.abandonedAtUtc.isNull(),
          );
        final draftRow = await draftQuery.getSingleOrNull();
        if (draftRow == null) {
          throw const ContactValidationException('contact_draft_not_found');
        }
        final answerQuery = _database.select(_database.dbContactDraftAnswers)
          ..where((row) => row.draftId.equals(draftId));
        final draft = _draftFromRow(
          draftRow,
          await answerQuery.get(),
          await _draftTargetLinkRows(draftId),
        );
        if (draft.isConflictCopy) {
          throw const ContactValidationException(
            'contact_draft_conflict_requires_resolution',
          );
        }
        if (draft.occurredAtUtc == null ||
            draft.occurredTimeZone == null ||
            draft.channel == null ||
            draft.location == null ||
            draft.reachCount == null ||
            draft.interestLevel == null) {
          throw const ContactValidationException('contact_draft_incomplete');
        }
        final submission = AnonymousContactSubmission(
          appUserId: draft.appUserId,
          workspaceId: draft.workspaceId,
          projectId: draft.projectId,
          questionnaireVersionId: draft.questionnaireVersionId,
          deviceId: deviceId,
          occurredAtUtc: draft.occurredAtUtc!,
          occurredTimeZone: draft.occurredTimeZone!,
          channel: draft.channel!,
          channelDetail: draft.channelDetail,
          location: draft.location!,
          reachCount: draft.reachCount!,
          interestLevel: draft.interestLevel!,
          answers: draft.answers,
          targetLinks: draft.targetLinks,
          sourceAttemptId: draft.sourceAttemptId,
        );
        _validateSubmission(submission);
        await _validateResolvedRegion(submission.location);
        final contactId = _idGenerator.next();
        final revisionId = _idGenerator.next();
        final commandId = _idGenerator.next();
        final submittedAtUtc = _clock.now().toUtc();
        await _writeSubmission(
          submission: submission,
          contactId: contactId,
          revisionId: revisionId,
          commandId: commandId,
          submittedAtUtc: submittedAtUtc,
        );
        await _prepareRemoteDraftDelete(
          draftRow,
          deviceId: deviceId,
          createdAtUtc: submittedAtUtc,
        );
        await (_database.delete(
          _database.dbContactDraftAnswers,
        )..where((row) => row.draftId.equals(draftId))).go();
        await (_database.delete(
          _database.dbContactDraftTargetLinks,
        )..where((row) => row.draftId.equals(draftId))).go();
        await _regionCatalog.clearDraftAssignment(draftId);
        await (_database.delete(
          _database.dbContactDrafts,
        )..where((row) => row.draftId.equals(draftId))).go();
        return ContactSubmissionReceipt(
          contactId: contactId,
          revisionNumber: 1,
          syncState: LocalSyncState.pending,
        );
      });
    } on ContactValidationException {
      rethrow;
    } catch (error, stackTrace) {
      throw ContactPersistenceException(
        code: 'contact_submission_failed',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _replaceDraftRegionAssignment(
    String draftId,
    ContactLocation? location,
  ) async {
    await _regionCatalog.clearDraftAssignment(draftId);
    if (location case final ResolvedContactLocation resolved) {
      await _regionCatalog.assignDraft(
        draftId: draftId,
        regionId: resolved.smallestRegionId,
        treeVersion: resolved.regionTreeVersion,
      );
    }
  }
}
