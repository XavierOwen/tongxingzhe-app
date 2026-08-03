import 'dart:convert';

import 'package:drift/drift.dart';

import '../../data/local_database.dart';
import '../../foundation/runtime_values.dart';
import 'contact_models.dart';

/// 负责匿名接触本地事实的深模块。
///
/// 调用者只提交完整行为，不分别写接触、revision 或 Outbox。模块在一个 Drift
/// transaction 中协调这些表；任一步失败都会回滚，因而 UI 只有在本方法返回
/// [ContactSubmissionReceipt] 后才能显示“已保存”。
final class ContactJournal {
  factory ContactJournal({
    required LocalDatabase database,
    required AppClock clock,
    required IdGenerator idGenerator,
  }) {
    return ContactJournal._(database, clock, idGenerator);
  }

  ContactJournal._(this._database, this._clock, this._idGenerator);

  final LocalDatabase _database;
  final AppClock _clock;
  final IdGenerator _idGenerator;

  /// 提交一条默认匿名的真实接触。
  ///
  /// 输入中的归属 ID 来自当前上下文；本地保存不代表远端授权成功。成功时会在
  /// 同一事务写入当前投影、首个 revision 和唯一同步命令。数据库错误转换成
  /// 稳定的 [ContactPersistenceException]，不会返回虚假的成功回执。
  Future<ContactSubmissionReceipt> submitAnonymousContact(
    AnonymousContactSubmission submission,
  ) async {
    _validateSubmission(submission);
    final contactId = _idGenerator.next();
    final revisionId = _idGenerator.next();
    final commandId = _idGenerator.next();
    final submittedAtUtc = _clock.now().toUtc();
    final location = switch (submission.location) {
      final ResolvedContactLocation resolved => (
        kind: 'resolved',
        placeName: resolved.placeName,
        smallestRegionId: resolved.smallestRegionId,
        latitude: null,
        longitude: null,
        accuracyMeters: null,
      ),
      NotApplicableContactLocation() => (
        kind: 'not_applicable',
        placeName: null,
        smallestRegionId: null,
        latitude: null,
        longitude: null,
        accuracyMeters: null,
      ),
      final PendingContactLocation pending => (
        kind: 'pending_resolution',
        placeName: null,
        smallestRegionId: null,
        latitude: pending.latitude,
        longitude: pending.longitude,
        accuracyMeters: pending.accuracyMeters,
      ),
    };

    try {
      await _database.transaction(() async {
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
                locationKind: location.kind,
                placeName: Value(location.placeName),
                smallestRegionId: Value(location.smallestRegionId),
                latitude: Value(location.latitude),
                longitude: Value(location.longitude),
                locationAccuracyMeters: Value(location.accuracyMeters),
                reachCount: submission.reachCount,
                interestLevel: submission.interestLevel,
                currentRevision: 1,
                lifecycleStatus: 'active',
              ),
            );

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
                locationKind: location.kind,
                placeName: Value(location.placeName),
                smallestRegionId: Value(location.smallestRegionId),
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
          'occurred_at_utc': submission.occurredAtUtc.toIso8601String(),
          'occurred_time_zone': submission.occurredTimeZone,
          'channel': submission.channel.storageValue,
          'channel_detail': submission.channelDetail,
          'location': {
            'kind': location.kind,
            'place_name': location.placeName,
            'smallest_region_id': location.smallestRegionId,
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

  void _validateSubmission(AnonymousContactSubmission submission) {
    if (submission.appUserId.trim().isEmpty ||
        submission.workspaceId.trim().isEmpty ||
        submission.projectId.trim().isEmpty ||
        submission.questionnaireVersionId.trim().isEmpty) {
      throw const ContactValidationException('contact_context_required');
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
          resolved.smallestRegionId.trim().isEmpty) {
        throw const ContactValidationException('resolved_location_required');
      }
    }
    if (submission.channel == ContactChannel.faceToFace &&
        submission.location is NotApplicableContactLocation) {
      throw const ContactValidationException('face_to_face_location_required');
    }
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
    final row = await _database
        .readPersonalContactSummary(
          appUserId,
          workspaceId,
          projectId,
          fromUtc,
          untilUtc,
        )
        .getSingle();

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
