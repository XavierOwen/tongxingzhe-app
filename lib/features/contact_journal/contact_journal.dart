import 'dart:convert';

import 'package:drift/drift.dart';

import '../../data/local_database.dart';
import '../../foundation/runtime_values.dart';
import '../../regions/region_catalog.dart';
import '../../regions/region_models.dart';
import 'contact_models.dart';

part 'contact_draft_operations.dart';

/// 负责匿名接触本地事实的深模块。
///
/// 调用者只表达保存草稿或提交接触，不分别写接触、revision 或 Outbox。草稿保存
/// 返回 [ContactDraft]；正式提交在一个 Drift transaction 中协调所有正式表，
/// 因而 UI 只有在收到 [ContactSubmissionReceipt] 后才能显示“已提交”。
final class ContactJournal {
  static const _abandonUndoWindow = Duration(seconds: 10);

  factory ContactJournal({
    required LocalDatabase database,
    required AppClock clock,
    required IdGenerator idGenerator,
  }) {
    return ContactJournal._(
      database,
      clock,
      idGenerator,
      RegionCatalog(database),
    );
  }

  ContactJournal._(
    this._database,
    this._clock,
    this._idGenerator,
    this._regionCatalog,
  );

  final LocalDatabase _database;
  final AppClock _clock;
  final IdGenerator _idGenerator;
  final RegionCatalog _regionCatalog;

  /// 原子保存一次未获回应的直接联络及其待同步命令。
  Future<ContactAttemptReceipt> recordContactAttempt(
    ContactAttemptSubmission submission,
  ) async {
    _validateAttemptSubmission(submission);
    final attemptId = _idGenerator.next();
    final commandId = _idGenerator.next();
    final submittedAtUtc = _clock.now().toUtc();
    try {
      await _database.transaction(() async {
        await _database
            .into(_database.dbContactAttempts)
            .insert(
              DbContactAttemptsCompanion.insert(
                attemptId: attemptId,
                appUserId: submission.appUserId,
                workspaceId: submission.workspaceId,
                projectId: submission.projectId,
                occurredAtUtc: submission.occurredAtUtc,
                occurredTimeZone: submission.occurredTimeZone,
                firstSubmittedAtUtc: submittedAtUtc,
                channel: submission.channel.storageValue,
                channelDetail: Value(submission.channelDetail),
              ),
            );
        final payload = jsonEncode({
          'attempt_id': attemptId,
          'workspace_id': submission.workspaceId,
          'project_id': submission.projectId,
          'occurred_at_utc': submission.occurredAtUtc.toIso8601String(),
          'occurred_time_zone': submission.occurredTimeZone,
          'channel': submission.channel.storageValue,
          'channel_detail': submission.channelDetail,
        });
        await _database
            .into(_database.dbSyncOutbox)
            .insert(
              DbSyncOutboxCompanion.insert(
                commandId: commandId,
                protocolVersion: 1,
                commandType: 'contact.attempt.submit.v1',
                deviceId: submission.deviceId,
                aggregateId: attemptId,
                appUserId: Value(submission.appUserId),
                workspaceId: Value(submission.workspaceId),
                projectId: Value(submission.projectId),
                baseRevision: 0,
                payloadJson: payload,
                createdAtUtc: submittedAtUtc,
                status: 'pending',
                nextAttemptAtUtc: submittedAtUtc,
              ),
            );
      });
    } catch (error, stackTrace) {
      throw ContactPersistenceException(
        code: 'contact_attempt_save_failed',
        cause: error,
        stackTrace: stackTrace,
      );
    }
    return ContactAttemptReceipt(
      attemptId: attemptId,
      syncState: LocalSyncState.pending,
    );
  }

  /// 列出当前个人项目中的接触尝试，最近发生的排在前面。
  Future<List<ContactAttempt>> listContactAttempts({
    required String appUserId,
    required String workspaceId,
    required String projectId,
  }) async {
    final query = _database.select(_database.dbContactAttempts)
      ..where(
        (row) =>
            row.appUserId.equals(appUserId) &
            row.workspaceId.equals(workspaceId) &
            row.projectId.equals(projectId),
      )
      ..orderBy([
        (row) => OrderingTerm.desc(row.occurredAtUtc),
        (row) => OrderingTerm.asc(row.attemptId),
      ]);
    return [
      for (final row in await query.get())
        ContactAttempt(
          attemptId: row.attemptId,
          appUserId: row.appUserId,
          workspaceId: row.workspaceId,
          projectId: row.projectId,
          occurredAtUtc: row.occurredAtUtc.toUtc(),
          occurredTimeZone: row.occurredTimeZone,
          firstSubmittedAtUtc: row.firstSubmittedAtUtc.toUtc(),
          channel: ContactChannel.fromStorage(row.channel),
          channelDetail: row.channelDetail,
          linkedContactId: row.linkedContactId,
        ),
    ];
  }

  Future<ContactAttempt?> contactAttemptByIdForOwner({
    required String attemptId,
    required String appUserId,
  }) async {
    final query = _database.select(_database.dbContactAttempts)
      ..where(
        (row) =>
            row.attemptId.equals(attemptId) & row.appUserId.equals(appUserId),
      );
    final row = await query.getSingleOrNull();
    if (row == null) {
      return null;
    }
    return ContactAttempt(
      attemptId: row.attemptId,
      appUserId: row.appUserId,
      workspaceId: row.workspaceId,
      projectId: row.projectId,
      occurredAtUtc: row.occurredAtUtc.toUtc(),
      occurredTimeZone: row.occurredTimeZone,
      firstSubmittedAtUtc: row.firstSubmittedAtUtc.toUtc(),
      channel: ContactChannel.fromStorage(row.channel),
      channelDetail: row.channelDetail,
      linkedContactId: row.linkedContactId,
    );
  }

  /// 直接提交不经过草稿的完整匿名接触。
  Future<ContactSubmissionReceipt> submitAnonymousContact(
    AnonymousContactSubmission submission,
  ) async {
    _validateSubmission(submission);
    await _validateResolvedRegion(submission.location);
    final contactId = _idGenerator.next();
    final revisionId = _idGenerator.next();
    final commandId = _idGenerator.next();
    final submittedAtUtc = _clock.now().toUtc();

    try {
      await _database.transaction(() async {
        await _writeSubmission(
          submission: submission,
          contactId: contactId,
          revisionId: revisionId,
          commandId: commandId,
          submittedAtUtc: submittedAtUtc,
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

    return ContactSubmissionReceipt(
      contactId: contactId,
      revisionNumber: 1,
      syncState: LocalSyncState.pending,
    );
  }

  Future<void> _writeSubmission({
    required AnonymousContactSubmission submission,
    required String contactId,
    required String revisionId,
    required String commandId,
    required DateTime submittedAtUtc,
  }) async {
    final sourceAttempt = await _availableSourceAttempt(submission);
    final location = _contactLocationColumns(submission.location);
    await _database
        .into(_database.dbContactRecords)
        .insert(
          DbContactRecordsCompanion.insert(
            contactId: contactId,
            appUserId: submission.appUserId,
            workspaceId: submission.workspaceId,
            projectId: submission.projectId,
            questionnaireVersionId: submission.questionnaireVersionId,
            occurredAtUtc: submission.occurredAtUtc,
            occurredTimeZone: submission.occurredTimeZone,
            firstSubmittedAtUtc: submittedAtUtc,
            channel: submission.channel.storageValue,
            channelDetail: Value(submission.channelDetail),
            locationKind: location.kind!,
            placeName: Value(location.placeName),
            smallestRegionId: Value(location.smallestRegionId),
            regionTreeVersion: Value(location.regionTreeVersion),
            latitude: Value(location.latitude),
            longitude: Value(location.longitude),
            locationAccuracyMeters: Value(location.accuracyMeters),
            reachCount: submission.reachCount,
            interestLevel: submission.interestLevel,
            currentRevision: 1,
            lifecycleStatus: 'active',
          ),
        );

    if (submission.location case final ResolvedContactLocation resolved) {
      await _regionCatalog.assignContact(
        contactId: contactId,
        regionId: resolved.smallestRegionId,
        treeVersion: resolved.regionTreeVersion,
      );
    }

    if (sourceAttempt != null) {
      final linked =
          await (_database.update(_database.dbContactAttempts)..where(
                (row) =>
                    row.attemptId.equals(sourceAttempt.attemptId) &
                    row.linkedContactId.isNull(),
              ))
              .write(
                DbContactAttemptsCompanion(linkedContactId: Value(contactId)),
              );
      if (linked != 1) {
        throw const ContactValidationException('source_attempt_already_linked');
      }
    }

    await _database
        .into(_database.dbContactRevisions)
        .insert(
          DbContactRevisionsCompanion.insert(
            revisionId: revisionId,
            contactId: contactId,
            revisionNumber: 1,
            revisedByAppUserId: submission.appUserId,
            revisedAtUtc: submittedAtUtc,
            occurredAtUtc: submission.occurredAtUtc,
            occurredTimeZone: submission.occurredTimeZone,
            channel: submission.channel.storageValue,
            channelDetail: Value(submission.channelDetail),
            locationKind: location.kind!,
            placeName: Value(location.placeName),
            smallestRegionId: Value(location.smallestRegionId),
            regionTreeVersion: Value(location.regionTreeVersion),
            latitude: Value(location.latitude),
            longitude: Value(location.longitude),
            locationAccuracyMeters: Value(location.accuracyMeters),
            reachCount: submission.reachCount,
            interestLevel: submission.interestLevel,
          ),
        );

    for (final answer in submission.answers) {
      final booleanAnswer = answer as BooleanQuestionnaireAnswer;
      await _database
          .into(_database.dbContactAnswers)
          .insert(
            DbContactAnswersCompanion.insert(
              contactId: contactId,
              revisionNumber: 1,
              questionId: booleanAnswer.questionId,
              answerState: booleanAnswer.state.storageValue,
              answerType: 'boolean',
              booleanValue: Value(booleanAnswer.value),
            ),
          );
    }

    final payload = jsonEncode({
      'contact_id': contactId,
      'workspace_id': submission.workspaceId,
      'project_id': submission.projectId,
      'questionnaire_version_id': submission.questionnaireVersionId,
      'source_attempt_id': submission.sourceAttemptId,
      'occurred_at_utc': submission.occurredAtUtc.toIso8601String(),
      'occurred_time_zone': submission.occurredTimeZone,
      'channel': submission.channel.storageValue,
      'channel_detail': submission.channelDetail,
      'location': {
        'kind': location.kind,
        'place_name': location.placeName,
        'smallest_region_id': location.smallestRegionId,
        'region_tree_version': location.regionTreeVersion,
        'latitude': location.latitude,
        'longitude': location.longitude,
        'accuracy_meters': location.accuracyMeters,
      },
      'reach_count': submission.reachCount,
      'interest_level': submission.interestLevel,
      'answers': [
        for (final answer in submission.answers)
          switch (answer) {
            final BooleanQuestionnaireAnswer booleanAnswer => {
              'question_id': booleanAnswer.questionId,
              'state': booleanAnswer.state.storageValue,
              'type': 'boolean',
              'value': booleanAnswer.value,
            },
          },
      ],
    });
    await _database
        .into(_database.dbSyncOutbox)
        .insert(
          DbSyncOutboxCompanion.insert(
            commandId: commandId,
            protocolVersion: 1,
            commandType: 'contact.submit.v1',
            deviceId: submission.deviceId,
            aggregateId: contactId,
            appUserId: Value(submission.appUserId),
            workspaceId: Value(submission.workspaceId),
            projectId: Value(submission.projectId),
            baseRevision: 0,
            payloadJson: payload,
            createdAtUtc: submittedAtUtc,
            status: 'pending',
            nextAttemptAtUtc: submittedAtUtc,
          ),
        );
  }

  void _validateSubmission(AnonymousContactSubmission submission) {
    if (submission.appUserId.trim().isEmpty ||
        submission.workspaceId.trim().isEmpty ||
        submission.projectId.trim().isEmpty ||
        submission.questionnaireVersionId.trim().isEmpty) {
      throw const ContactValidationException('contact_context_required');
    }
    if (submission.deviceId.trim().isEmpty) {
      throw const ContactValidationException('contact_device_required');
    }
    if (submission.sourceAttemptId != null &&
        submission.sourceAttemptId!.trim().isEmpty) {
      throw const ContactValidationException('source_attempt_id_invalid');
    }
    if (!submission.occurredAtUtc.isUtc) {
      throw const ContactValidationException('occurred_at_must_be_utc');
    }
    if (submission.occurredTimeZone.trim().isEmpty) {
      throw const ContactValidationException('occurred_time_zone_required');
    }
    if (submission.reachCount < 1) {
      throw const ContactValidationException('reach_count_must_be_positive');
    }
    if (submission.interestLevel < 0 || submission.interestLevel > 4) {
      throw const ContactValidationException('interest_level_out_of_range');
    }
    if (submission.channel == ContactChannel.otherDirect &&
        (submission.channelDetail == null ||
            submission.channelDetail!.trim().isEmpty)) {
      throw const ContactValidationException('other_channel_detail_required');
    }
    final questionIds = <String>{};
    for (final answer in submission.answers) {
      if (answer.questionId.trim().isEmpty) {
        throw const ContactValidationException('question_id_required');
      }
      if (!questionIds.add(answer.questionId)) {
        throw const ContactValidationException('duplicate_question_answer');
      }
    }
    if (submission.location case final PendingContactLocation pending) {
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
    if (submission.location case final ResolvedContactLocation resolved) {
      if (resolved.placeName.trim().isEmpty ||
          resolved.smallestRegionId.trim().isEmpty ||
          resolved.regionTreeVersion.trim().isEmpty) {
        throw const ContactValidationException('resolved_location_required');
      }
    }
    if (submission.channel == ContactChannel.faceToFace &&
        submission.location is NotApplicableContactLocation) {
      throw const ContactValidationException('face_to_face_location_required');
    }
  }

  void _validateAttemptSubmission(ContactAttemptSubmission submission) {
    if (submission.appUserId.trim().isEmpty ||
        submission.workspaceId.trim().isEmpty ||
        submission.projectId.trim().isEmpty) {
      throw const ContactValidationException('contact_context_required');
    }
    if (submission.deviceId.trim().isEmpty) {
      throw const ContactValidationException('contact_device_required');
    }
    if (!submission.occurredAtUtc.isUtc) {
      throw const ContactValidationException('occurred_at_must_be_utc');
    }
    if (submission.occurredTimeZone.trim().isEmpty) {
      throw const ContactValidationException('occurred_time_zone_required');
    }
    if (submission.channel == ContactChannel.otherDirect &&
        (submission.channelDetail == null ||
            submission.channelDetail!.trim().isEmpty)) {
      throw const ContactValidationException('other_channel_detail_required');
    }
  }

  Future<DbContactAttempt?> _availableSourceAttempt(
    AnonymousContactSubmission submission,
  ) async {
    final attemptId = submission.sourceAttemptId;
    if (attemptId == null) {
      return null;
    }
    final query = _database.select(_database.dbContactAttempts)
      ..where(
        (row) =>
            row.attemptId.equals(attemptId) &
            row.appUserId.equals(submission.appUserId) &
            row.workspaceId.equals(submission.workspaceId) &
            row.projectId.equals(submission.projectId),
      );
    final attempt = await query.getSingleOrNull();
    if (attempt == null) {
      throw const ContactValidationException('source_attempt_not_found');
    }
    if (attempt.linkedContactId != null) {
      throw const ContactValidationException('source_attempt_already_linked');
    }
    return attempt;
  }

  /// 读取一条接触的当前有效视图。
  ///
  /// 找不到 ID 时返回 `null`。此接口隐藏 Drift row 与 Outbox 表，使 UI 不会
  /// 依赖数据库实现细节。
  Future<ContactRecord?> contactById(String contactId) async {
    final query = _database.select(_database.dbContactRecords)
      ..where((row) => row.contactId.equals(contactId));
    final row = await query.getSingleOrNull();
    if (row == null) {
      return null;
    }

    final answerQuery = _database.select(_database.dbContactAnswers)
      ..where(
        (answer) =>
            answer.contactId.equals(contactId) &
            answer.revisionNumber.equals(row.currentRevision),
      )
      ..orderBy([(answer) => OrderingTerm.asc(answer.questionId)]);
    final answerRows = await answerQuery.get();

    return ContactRecord(
      contactId: row.contactId,
      revisionNumber: row.currentRevision,
      channel: ContactChannel.fromStorage(row.channel),
      channelDetail: row.channelDetail,
      location: switch (row.locationKind) {
        'resolved' => ResolvedContactLocation(
          placeName: row.placeName!,
          smallestRegionId: row.smallestRegionId!,
          regionTreeVersion: row.regionTreeVersion!,
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
      },
      reachCount: row.reachCount,
      interestLevel: row.interestLevel,
      syncState: LocalSyncState.pending,
      answers: [
        for (final answer in answerRows)
          switch (answer.answerType) {
            'boolean' => _booleanAnswerFromRow(
              questionId: answer.questionId,
              state: answer.answerState,
              value: answer.booleanValue,
            ),
            final unsupported => throw StateError(
              'unsupported_questionnaire_answer_type:$unsupported',
            ),
          },
      ],
    );
  }

  Future<void> _validateResolvedRegion(ContactLocation? location) async {
    if (location is! ResolvedContactLocation) {
      return;
    }
    try {
      await _regionCatalog.requireAnalyzableRegion(
        regionId: location.smallestRegionId,
        treeVersion: location.regionTreeVersion,
      );
    } on RegionCatalogException catch (error) {
      throw ContactValidationException(error.code);
    }
  }

  /// 汇总当前用户在一个项目和 UTC 半开区间 `[fromUtc, untilUtc)` 的接触。
  ///
  /// SQL 只纳入 `active` 的已提交接触，并按实际发生时间归属。返回值把接触
  /// 场次、触达人数、兴趣分布和仍未完成同步的接触数分开，避免混用单位。
  Future<PersonalContactSummary> summarizePersonalContacts({
    required String appUserId,
    required String workspaceId,
    required String projectId,
    required DateTime fromUtc,
    required DateTime untilUtc,
  }) async {
    if (!fromUtc.isUtc || !untilUtc.isUtc || !fromUtc.isBefore(untilUtc)) {
      throw const ContactValidationException('invalid_summary_period');
    }
    final queryResult = await _database.transaction(() async {
      final summary = await _database
          .readPersonalContactSummary(
            appUserId,
            workspaceId,
            projectId,
            fromUtc,
            untilUtc,
          )
          .getSingle();
      final channels = await _database
          .readPersonalContactChannelSummary(
            appUserId,
            workspaceId,
            projectId,
            fromUtc,
            untilUtc,
          )
          .get();
      return (summary: summary, channels: channels);
    });
    final channelDistribution = List<int>.filled(
      ContactChannel.values.length,
      0,
    );
    for (final channelRow in queryResult.channels) {
      final channel = ContactChannel.fromStorage(channelRow.channel);
      channelDistribution[channel.index] = channelRow.contactSessionCount;
    }
    final row = queryResult.summary;

    return PersonalContactSummary(
      contactSessionCount: row.contactSessionCount,
      reachCount: row.reachCount,
      interestDistribution: [
        row.interest0Count,
        row.interest1Count,
        row.interest2Count,
        row.interest3Count,
        row.interest4Count,
      ],
      pendingSyncCount: row.pendingSyncCount,
      channelDistribution: channelDistribution,
      latestOccurredAtUtc: row.latestOccurredAtUtc?.toUtc(),
    );
  }

  BooleanQuestionnaireAnswer _booleanAnswerFromRow({
    required String questionId,
    required String state,
    required bool? value,
  }) {
    return switch (QuestionnaireAnswerState.fromStorage(state)) {
      QuestionnaireAnswerState.answered => BooleanQuestionnaireAnswer(
        questionId: questionId,
        value: value!,
      ),
      QuestionnaireAnswerState.unknown => BooleanQuestionnaireAnswer.unknown(
        questionId: questionId,
      ),
      QuestionnaireAnswerState.refused => BooleanQuestionnaireAnswer.refused(
        questionId: questionId,
      ),
      QuestionnaireAnswerState.notApplicable =>
        BooleanQuestionnaireAnswer.notApplicable(questionId: questionId),
      QuestionnaireAnswerState.unanswered =>
        BooleanQuestionnaireAnswer.unanswered(questionId: questionId),
    };
  }
}
