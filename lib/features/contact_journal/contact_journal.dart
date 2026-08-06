import 'dart:convert';

import 'package:drift/drift.dart';

import '../../data/local_database.dart';
import '../../foundation/runtime_values.dart';
import '../../questionnaires/questionnaire_answer_codec.dart';
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
            revisionKind: Value(ContactRevisionKind.submitted.storageValue),
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
      final columns = QuestionnaireAnswerCodec.toColumns(answer);
      await _database
          .into(_database.dbContactAnswers)
          .insert(
            DbContactAnswersCompanion.insert(
              contactId: contactId,
              revisionNumber: 1,
              questionId: columns.questionId,
              answerState: columns.state,
              answerType: columns.type,
              booleanValue: Value(columns.booleanValue),
              textValue: Value(columns.textValue),
              numberValue: Value(columns.numberValue),
              multiChoiceValueJson: Value(columns.multiChoiceValueJson),
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
          QuestionnaireAnswerCodec.toJson(answer),
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

  /// 追加一个更正快照，并原子更新当前投影和 Outbox。
  Future<ContactRevisionReceipt> correctContact(
    ContactCorrectionSubmission submission,
  ) async {
    _validateCorrectionSubmission(submission);
    await _validateResolvedRegion(submission.location);
    final revisionId = _idGenerator.next();
    final commandId = _idGenerator.next();
    final revisedAtUtc = _clock.now().toUtc();
    final reason = submission.reason.trim();

    try {
      final revisionNumber = await _database.transaction(() async {
        final current = await _ownedContact(
          contactId: submission.contactId,
          appUserId: submission.appUserId,
          workspaceId: submission.workspaceId,
          projectId: submission.projectId,
        );
        if (current == null) {
          throw const ContactValidationException('contact_not_found');
        }
        if (current.lifecycleStatus == 'voided') {
          throw const ContactValidationException('contact_already_voided');
        }
        await _rejectUnresolvedContactConflict(
          contactId: current.contactId,
          appUserId: submission.appUserId,
          workspaceId: submission.workspaceId,
          projectId: submission.projectId,
        );
        if (current.currentRevision != submission.baseRevision) {
          throw const ContactValidationException('contact_revision_conflict');
        }
        final nextRevision = current.currentRevision + 1;
        final location = _contactLocationColumns(submission.location);
        await _database
            .into(_database.dbContactRevisions)
            .insert(
              DbContactRevisionsCompanion.insert(
                revisionId: revisionId,
                contactId: current.contactId,
                revisionNumber: nextRevision,
                revisionKind: Value(ContactRevisionKind.corrected.storageValue),
                revisedByAppUserId: submission.appUserId,
                revisedAtUtc: revisedAtUtc,
                reason: Value(reason),
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
        await _insertAnswers(
          contactId: current.contactId,
          revisionNumber: nextRevision,
          answers: submission.answers,
        );
        await (_database.update(
          _database.dbContactRecords,
        )..where((row) => row.contactId.equals(current.contactId))).write(
          DbContactRecordsCompanion(
            occurredAtUtc: Value(submission.occurredAtUtc),
            occurredTimeZone: Value(submission.occurredTimeZone),
            channel: Value(submission.channel.storageValue),
            channelDetail: Value(submission.channelDetail),
            locationKind: Value(location.kind!),
            placeName: Value(location.placeName),
            smallestRegionId: Value(location.smallestRegionId),
            regionTreeVersion: Value(location.regionTreeVersion),
            latitude: Value(location.latitude),
            longitude: Value(location.longitude),
            locationAccuracyMeters: Value(location.accuracyMeters),
            reachCount: Value(submission.reachCount),
            interestLevel: Value(submission.interestLevel),
            currentRevision: Value(nextRevision),
          ),
        );
        await _updateContactRegion(
          contactId: current.contactId,
          location: submission.location,
        );
        final payload = jsonEncode({
          'contact_id': current.contactId,
          'workspace_id': submission.workspaceId,
          'project_id': submission.projectId,
          'reason': reason,
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
          'answers': _answerPayload(submission.answers),
        });
        await _insertOutboxCommand(
          commandId: commandId,
          commandType: 'contact.revise.v1',
          deviceId: submission.deviceId,
          aggregateId: current.contactId,
          appUserId: submission.appUserId,
          workspaceId: submission.workspaceId,
          projectId: submission.projectId,
          baseRevision: current.currentRevision,
          payload: payload,
          createdAtUtc: revisedAtUtc,
        );
        return nextRevision;
      });
      return ContactRevisionReceipt(
        contactId: submission.contactId,
        revisionNumber: revisionNumber,
        kind: ContactRevisionKind.corrected,
        syncState: LocalSyncState.pending,
      );
    } on ContactValidationException {
      rethrow;
    } catch (error, stackTrace) {
      throw ContactPersistenceException(
        code: 'contact_correction_failed',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// 追加作废 revision，并让当前投影退出正常统计。
  Future<ContactRevisionReceipt> voidContact(
    ContactVoidSubmission submission,
  ) async {
    _validateVoidSubmission(submission);
    final revisionId = _idGenerator.next();
    final commandId = _idGenerator.next();
    final revisedAtUtc = _clock.now().toUtc();
    final reason = submission.reason.trim();

    try {
      final revisionNumber = await _database.transaction(() async {
        final current = await _ownedContact(
          contactId: submission.contactId,
          appUserId: submission.appUserId,
          workspaceId: submission.workspaceId,
          projectId: submission.projectId,
        );
        if (current == null) {
          throw const ContactValidationException('contact_not_found');
        }
        if (current.lifecycleStatus == 'voided') {
          throw const ContactValidationException('contact_already_voided');
        }
        await _rejectUnresolvedContactConflict(
          contactId: current.contactId,
          appUserId: submission.appUserId,
          workspaceId: submission.workspaceId,
          projectId: submission.projectId,
        );
        if (current.currentRevision != submission.baseRevision) {
          throw const ContactValidationException('contact_revision_conflict');
        }
        final nextRevision = current.currentRevision + 1;
        await _database
            .into(_database.dbContactRevisions)
            .insert(
              DbContactRevisionsCompanion.insert(
                revisionId: revisionId,
                contactId: current.contactId,
                revisionNumber: nextRevision,
                revisionKind: Value(ContactRevisionKind.voided.storageValue),
                revisedByAppUserId: submission.appUserId,
                revisedAtUtc: revisedAtUtc,
                reason: Value(reason),
                occurredAtUtc: current.occurredAtUtc,
                occurredTimeZone: current.occurredTimeZone,
                channel: current.channel,
                channelDetail: Value(current.channelDetail),
                locationKind: current.locationKind,
                placeName: Value(current.placeName),
                smallestRegionId: Value(current.smallestRegionId),
                regionTreeVersion: Value(current.regionTreeVersion),
                latitude: Value(current.latitude),
                longitude: Value(current.longitude),
                locationAccuracyMeters: Value(current.locationAccuracyMeters),
                reachCount: current.reachCount,
                interestLevel: current.interestLevel,
              ),
            );
        final currentAnswers = await _answersForRevision(
          current.contactId,
          current.currentRevision,
        );
        await _insertAnswers(
          contactId: current.contactId,
          revisionNumber: nextRevision,
          answers: currentAnswers,
        );
        await (_database.update(
          _database.dbContactRecords,
        )..where((row) => row.contactId.equals(current.contactId))).write(
          DbContactRecordsCompanion(
            currentRevision: Value(nextRevision),
            lifecycleStatus: const Value('voided'),
          ),
        );
        final payload = jsonEncode({
          'contact_id': current.contactId,
          'workspace_id': submission.workspaceId,
          'project_id': submission.projectId,
          'reason': reason,
        });
        await _insertOutboxCommand(
          commandId: commandId,
          commandType: 'contact.void.v1',
          deviceId: submission.deviceId,
          aggregateId: current.contactId,
          appUserId: submission.appUserId,
          workspaceId: submission.workspaceId,
          projectId: submission.projectId,
          baseRevision: current.currentRevision,
          payload: payload,
          createdAtUtc: revisedAtUtc,
        );
        return nextRevision;
      });
      return ContactRevisionReceipt(
        contactId: submission.contactId,
        revisionNumber: revisionNumber,
        kind: ContactRevisionKind.voided,
        syncState: LocalSyncState.pending,
      );
    } on ContactValidationException {
      rethrow;
    } catch (error, stackTrace) {
      throw ContactPersistenceException(
        code: 'contact_void_failed',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// 列出本人对一条接触仍需明确处理的跨设备冲突。
  Future<List<ContactRevisionConflict>> listContactRevisionConflicts({
    required String contactId,
    required String appUserId,
  }) async {
    final contact = await contactByIdForOwner(
      contactId: contactId,
      appUserId: appUserId,
    );
    if (contact == null) {
      return const [];
    }
    final query = _database.select(_database.dbContactRevisionConflicts)
      ..where(
        (row) =>
            row.contactId.equals(contactId) &
            row.appUserId.equals(appUserId) &
            row.status.isNotValue('resolved'),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.createdAtUtc)]);
    return [for (final row in await query.get()) _conflictFromRow(row)];
  }

  /// 把使用者明确选择的冲突结果追加为新 revision。
  ///
  /// 同一 SQLite transaction 会完成 revision、当前投影、解决 command、原冲突
  /// command 状态和冲突状态；任一步失败时双方快照仍保持待处理。
  Future<ContactRevisionReceipt> resolveContactRevisionConflict(
    ContactConflictResolutionSubmission submission,
  ) async {
    final conflictQuery = _database.select(_database.dbContactRevisionConflicts)
      ..where((row) => row.conflictId.equals(submission.conflictId));
    final storedConflict = await conflictQuery.getSingleOrNull();
    if (storedConflict == null ||
        storedConflict.appUserId != submission.appUserId ||
        storedConflict.workspaceId != submission.workspaceId ||
        storedConflict.projectId != submission.projectId) {
      throw const ContactValidationException('contact_conflict_not_found');
    }
    if (storedConflict.status != 'pending') {
      throw const ContactValidationException(
        'contact_conflict_already_resolving',
      );
    }
    final snapshot = submission.snapshot;
    final correction = ContactCorrectionSubmission(
      contactId: storedConflict.contactId,
      appUserId: submission.appUserId,
      workspaceId: submission.workspaceId,
      projectId: submission.projectId,
      deviceId: submission.deviceId,
      baseRevision: storedConflict.currentRevision,
      reason: submission.reason,
      occurredAtUtc: snapshot.occurredAtUtc,
      occurredTimeZone: snapshot.occurredTimeZone,
      channel: snapshot.channel,
      channelDetail: snapshot.channelDetail,
      location: snapshot.location,
      reachCount: snapshot.reachCount,
      interestLevel: snapshot.interestLevel,
      answers: snapshot.answers,
    );
    _validateCorrectionSubmission(correction);
    await _validateResolvedRegion(snapshot.location);

    final revisionId = _idGenerator.next();
    final commandId = _idGenerator.next();
    final nowUtc = _clock.now().toUtc();
    final reason = submission.reason.trim();
    try {
      final revisionNumber = await _database.transaction(() async {
        final current = await _ownedContact(
          contactId: storedConflict.contactId,
          appUserId: submission.appUserId,
          workspaceId: submission.workspaceId,
          projectId: submission.projectId,
        );
        if (current == null) {
          throw const ContactValidationException('contact_not_found');
        }
        if (current.lifecycleStatus == 'voided') {
          throw const ContactValidationException('contact_already_voided');
        }
        if (current.currentRevision != storedConflict.currentRevision) {
          throw const ContactValidationException('contact_revision_conflict');
        }
        final nextRevision = current.currentRevision + 1;
        final location = _contactLocationColumns(snapshot.location);
        await _database
            .into(_database.dbContactRevisions)
            .insert(
              DbContactRevisionsCompanion.insert(
                revisionId: revisionId,
                contactId: current.contactId,
                revisionNumber: nextRevision,
                revisionKind: Value(ContactRevisionKind.corrected.storageValue),
                revisedByAppUserId: submission.appUserId,
                revisedAtUtc: nowUtc,
                reason: Value(reason),
                occurredAtUtc: snapshot.occurredAtUtc,
                occurredTimeZone: snapshot.occurredTimeZone,
                channel: snapshot.channel.storageValue,
                channelDetail: Value(snapshot.channelDetail),
                locationKind: location.kind!,
                placeName: Value(location.placeName),
                smallestRegionId: Value(location.smallestRegionId),
                regionTreeVersion: Value(location.regionTreeVersion),
                latitude: Value(location.latitude),
                longitude: Value(location.longitude),
                locationAccuracyMeters: Value(location.accuracyMeters),
                reachCount: snapshot.reachCount,
                interestLevel: snapshot.interestLevel,
              ),
            );
        await _insertAnswers(
          contactId: current.contactId,
          revisionNumber: nextRevision,
          answers: snapshot.answers,
        );
        await (_database.update(
          _database.dbContactRecords,
        )..where((row) => row.contactId.equals(current.contactId))).write(
          DbContactRecordsCompanion(
            occurredAtUtc: Value(snapshot.occurredAtUtc),
            occurredTimeZone: Value(snapshot.occurredTimeZone),
            channel: Value(snapshot.channel.storageValue),
            channelDetail: Value(snapshot.channelDetail),
            locationKind: Value(location.kind!),
            placeName: Value(location.placeName),
            smallestRegionId: Value(location.smallestRegionId),
            regionTreeVersion: Value(location.regionTreeVersion),
            latitude: Value(location.latitude),
            longitude: Value(location.longitude),
            locationAccuracyMeters: Value(location.accuracyMeters),
            reachCount: Value(snapshot.reachCount),
            interestLevel: Value(snapshot.interestLevel),
            currentRevision: Value(nextRevision),
          ),
        );
        await _updateContactRegion(
          contactId: current.contactId,
          location: snapshot.location,
        );
        await (_database.update(_database.dbSyncOutbox)
              ..where((row) => row.commandId.equals(storedConflict.commandId)))
            .write(
              DbSyncOutboxCompanion(
                status: const Value('completed'),
                lastFailureCode: const Value(null),
                completedAtUtc: Value(nowUtc),
              ),
            );
        await (_database.update(
              _database.dbContactRevisionConflicts,
            )..where((row) => row.conflictId.equals(storedConflict.conflictId)))
            .write(
              DbContactRevisionConflictsCompanion(
                status: const Value('resolution_pending'),
                resolutionCommandId: Value(commandId),
              ),
            );
        await _insertOutboxCommand(
          commandId: commandId,
          commandType: 'contact.resolve.v1',
          deviceId: submission.deviceId,
          aggregateId: current.contactId,
          appUserId: submission.appUserId,
          workspaceId: submission.workspaceId,
          projectId: submission.projectId,
          baseRevision: current.currentRevision,
          payload: jsonEncode({
            'conflict_id': storedConflict.conflictId,
            'contact_id': current.contactId,
            'workspace_id': submission.workspaceId,
            'project_id': submission.projectId,
            'reason': reason,
            'occurred_at_utc': snapshot.occurredAtUtc.toIso8601String(),
            'occurred_time_zone': snapshot.occurredTimeZone,
            'channel': snapshot.channel.storageValue,
            'channel_detail': snapshot.channelDetail,
            'location': {
              'kind': location.kind,
              'place_name': location.placeName,
              'smallest_region_id': location.smallestRegionId,
              'region_tree_version': location.regionTreeVersion,
              'latitude': location.latitude,
              'longitude': location.longitude,
              'accuracy_meters': location.accuracyMeters,
            },
            'reach_count': snapshot.reachCount,
            'interest_level': snapshot.interestLevel,
            'answers': _answerPayload(snapshot.answers),
          }),
          createdAtUtc: nowUtc,
        );
        return nextRevision;
      });
      return ContactRevisionReceipt(
        contactId: storedConflict.contactId,
        revisionNumber: revisionNumber,
        kind: ContactRevisionKind.corrected,
        syncState: LocalSyncState.pending,
      );
    } on ContactValidationException {
      rethrow;
    } catch (error, stackTrace) {
      throw ContactPersistenceException(
        code: 'contact_conflict_resolution_failed',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _insertOutboxCommand({
    required String commandId,
    required String commandType,
    required String deviceId,
    required String aggregateId,
    required String appUserId,
    required String workspaceId,
    required String projectId,
    required int baseRevision,
    required String payload,
    required DateTime createdAtUtc,
  }) async {
    await _database
        .into(_database.dbSyncOutbox)
        .insert(
          DbSyncOutboxCompanion.insert(
            commandId: commandId,
            protocolVersion: 1,
            commandType: commandType,
            deviceId: deviceId,
            aggregateId: aggregateId,
            appUserId: Value(appUserId),
            workspaceId: Value(workspaceId),
            projectId: Value(projectId),
            baseRevision: baseRevision,
            payloadJson: payload,
            createdAtUtc: createdAtUtc,
            status: 'pending',
            nextAttemptAtUtc: createdAtUtc,
          ),
        );
  }

  Future<void> _insertAnswers({
    required String contactId,
    required int revisionNumber,
    required List<QuestionnaireAnswer> answers,
  }) async {
    for (final answer in answers) {
      final columns = QuestionnaireAnswerCodec.toColumns(answer);
      await _database
          .into(_database.dbContactAnswers)
          .insert(
            DbContactAnswersCompanion.insert(
              contactId: contactId,
              revisionNumber: revisionNumber,
              questionId: columns.questionId,
              answerState: columns.state,
              answerType: columns.type,
              booleanValue: Value(columns.booleanValue),
              textValue: Value(columns.textValue),
              numberValue: Value(columns.numberValue),
              multiChoiceValueJson: Value(columns.multiChoiceValueJson),
            ),
          );
    }
  }

  Future<List<QuestionnaireAnswer>> _answersForRevision(
    String contactId,
    int revisionNumber,
  ) async {
    final query = _database.select(_database.dbContactAnswers)
      ..where(
        (row) =>
            row.contactId.equals(contactId) &
            row.revisionNumber.equals(revisionNumber),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.questionId)]);
    return [
      for (final row in await query.get())
        QuestionnaireAnswerCodec.fromColumns(
          questionId: row.questionId,
          state: row.answerState,
          type: row.answerType,
          booleanValue: row.booleanValue,
          textValue: row.textValue,
          numberValue: row.numberValue,
          multiChoiceValueJson: row.multiChoiceValueJson,
        ),
    ];
  }

  List<Map<String, Object?>> _answerPayload(
    List<QuestionnaireAnswer> answers,
  ) => [for (final answer in answers) QuestionnaireAnswerCodec.toJson(answer)];

  ContactRevisionConflict _conflictFromRow(DbContactRevisionConflict row) {
    final rawFields = jsonDecode(row.conflictingFieldsJson);
    if (rawFields is! List<Object?> ||
        rawFields.any((field) => field is! String)) {
      throw const FormatException('invalid stored conflict fields');
    }
    return ContactRevisionConflict(
      conflictId: row.conflictId,
      commandId: row.commandId,
      contactId: row.contactId,
      appUserId: row.appUserId,
      workspaceId: row.workspaceId,
      projectId: row.projectId,
      baseRevision: row.baseRevision,
      currentRevision: row.currentRevision,
      conflictingFields: List.unmodifiable(rawFields.cast<String>()),
      questionnaireVersionId: row.questionnaireVersionId,
      currentRevisionKind: ContactRevisionKind.fromStorage(
        row.currentRevisionKind,
      ),
      currentRevisedAtUtc: row.currentRevisedAtUtc.toUtc(),
      currentReason: row.currentReason,
      currentSnapshot: _storedConflictSnapshot(row.currentSnapshotJson),
      proposedSnapshot: _storedConflictSnapshot(row.proposedSnapshotJson),
      status: ContactRevisionConflictStatus.fromStorage(row.status),
    );
  }

  Future<void> _rejectUnresolvedContactConflict({
    required String contactId,
    required String appUserId,
    required String workspaceId,
    required String projectId,
  }) async {
    final query = _database.select(_database.dbContactRevisionConflicts)
      ..where(
        (row) =>
            row.contactId.equals(contactId) &
            row.appUserId.equals(appUserId) &
            row.workspaceId.equals(workspaceId) &
            row.projectId.equals(projectId) &
            row.status.isNotValue('resolved'),
      )
      ..limit(1);
    final conflict = await query.getSingleOrNull();
    if (conflict == null) {
      return;
    }
    throw ContactValidationException(
      conflict.status == 'pending'
          ? 'contact_conflict_requires_resolution'
          : 'contact_conflict_already_resolving',
    );
  }

  ContactConflictSnapshot _storedConflictSnapshot(String encoded) {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('invalid stored conflict snapshot');
    }
    final rawAnswers = decoded['answers'];
    if (rawAnswers is! List<Object?>) {
      throw const FormatException('invalid stored conflict answers');
    }
    return ContactConflictSnapshot(
      occurredAtUtc: DateTime.parse(
        decoded['occurredAtUtc']! as String,
      ).toUtc(),
      occurredTimeZone: decoded['occurredTimeZone']! as String,
      channel: ContactChannel.fromStorage(decoded['channel']! as String),
      channelDetail: decoded['channelDetail'] as String?,
      location: _storedConflictLocation(decoded['location']),
      reachCount: decoded['reachCount']! as int,
      interestLevel: decoded['interestLevel']! as int,
      answers: [for (final answer in rawAnswers) _storedConflictAnswer(answer)],
    );
  }

  ContactLocation _storedConflictLocation(Object? value) {
    if (value is! Map<String, Object?>) {
      throw const FormatException('invalid stored conflict location');
    }
    return switch (value['kind']) {
      'not_applicable' => const NotApplicableContactLocation(),
      'resolved' => ResolvedContactLocation(
        placeName: value['placeName']! as String,
        smallestRegionId: value['smallestRegionId']! as String,
        regionTreeVersion: value['regionTreeVersion']! as String,
      ),
      'pending_resolution' => PendingContactLocation(
        latitude: (value['latitude']! as num).toDouble(),
        longitude: (value['longitude']! as num).toDouble(),
        accuracyMeters: (value['accuracyMeters'] as num?)?.toDouble(),
      ),
      _ => throw const FormatException('invalid stored conflict location kind'),
    };
  }

  QuestionnaireAnswer _storedConflictAnswer(Object? value) {
    if (value is! Map<String, Object?>) {
      throw const FormatException('invalid stored conflict answer');
    }
    return QuestionnaireAnswerCodec.fromJson({
      'question_id': value['questionId'],
      'state': value['state'],
      'type': value['type'],
      'value': value['value'],
    });
  }

  Future<DbContactRecord?> _ownedContact({
    required String contactId,
    required String appUserId,
    required String workspaceId,
    required String projectId,
  }) {
    final query = _database.select(_database.dbContactRecords)
      ..where(
        (row) =>
            row.contactId.equals(contactId) &
            row.appUserId.equals(appUserId) &
            row.workspaceId.equals(workspaceId) &
            row.projectId.equals(projectId),
      );
    return query.getSingleOrNull();
  }

  Future<void> _updateContactRegion({
    required String contactId,
    required ContactLocation location,
  }) async {
    if (location case final ResolvedContactLocation resolved) {
      await _regionCatalog.assignContact(
        contactId: contactId,
        regionId: resolved.smallestRegionId,
        treeVersion: resolved.regionTreeVersion,
      );
    } else {
      await _regionCatalog.clearContactAssignment(contactId);
    }
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

  void _validateCorrectionSubmission(ContactCorrectionSubmission submission) {
    if (submission.contactId.trim().isEmpty ||
        submission.appUserId.trim().isEmpty ||
        submission.workspaceId.trim().isEmpty ||
        submission.projectId.trim().isEmpty) {
      throw const ContactValidationException('contact_context_required');
    }
    if (submission.deviceId.trim().isEmpty) {
      throw const ContactValidationException('contact_device_required');
    }
    if (submission.baseRevision < 1) {
      throw const ContactValidationException('contact_revision_invalid');
    }
    if (submission.reason.trim().isEmpty) {
      throw const ContactValidationException('contact_reason_required');
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

  void _validateVoidSubmission(ContactVoidSubmission submission) {
    if (submission.contactId.trim().isEmpty ||
        submission.appUserId.trim().isEmpty ||
        submission.workspaceId.trim().isEmpty ||
        submission.projectId.trim().isEmpty) {
      throw const ContactValidationException('contact_context_required');
    }
    if (submission.deviceId.trim().isEmpty) {
      throw const ContactValidationException('contact_device_required');
    }
    if (submission.baseRevision < 1) {
      throw const ContactValidationException('contact_revision_invalid');
    }
    if (submission.reason.trim().isEmpty) {
      throw const ContactValidationException('contact_reason_required');
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

    return _contactRecordFromRow(row);
  }

  Future<ContactRecord?> contactByIdForOwner({
    required String contactId,
    required String appUserId,
  }) async {
    final query = _database.select(_database.dbContactRecords)
      ..where(
        (row) =>
            row.contactId.equals(contactId) & row.appUserId.equals(appUserId),
      );
    final row = await query.getSingleOrNull();
    return row == null ? null : _contactRecordFromRow(row);
  }

  /// 列出当前项目的已提交接触，包括已作废历史。
  Future<List<ContactRecord>> listContactRecords({
    required String appUserId,
    required String workspaceId,
    required String projectId,
  }) async {
    final query = _database.select(_database.dbContactRecords)
      ..where(
        (row) =>
            row.appUserId.equals(appUserId) &
            row.workspaceId.equals(workspaceId) &
            row.projectId.equals(projectId),
      )
      ..orderBy([
        (row) => OrderingTerm.desc(row.occurredAtUtc),
        (row) => OrderingTerm.asc(row.contactId),
      ]);
    return [
      for (final row in await query.get()) await _contactRecordFromRow(row),
    ];
  }

  /// 返回一条本人接触的全部 revision，最新一条排在前面。
  Future<List<ContactRevision>> listContactRevisions({
    required String contactId,
    required String appUserId,
  }) async {
    final contact = await contactByIdForOwner(
      contactId: contactId,
      appUserId: appUserId,
    );
    if (contact == null) {
      return const [];
    }
    final query = _database.select(_database.dbContactRevisions)
      ..where((row) => row.contactId.equals(contactId))
      ..orderBy([(row) => OrderingTerm.desc(row.revisionNumber)]);
    return [
      for (final row in await query.get())
        ContactRevision(
          revisionId: row.revisionId,
          contactId: row.contactId,
          revisionNumber: row.revisionNumber,
          kind: ContactRevisionKind.fromStorage(row.revisionKind),
          revisedByAppUserId: row.revisedByAppUserId,
          revisedAtUtc: row.revisedAtUtc.toUtc(),
          reason: row.reason,
          occurredAtUtc: row.occurredAtUtc.toUtc(),
          occurredTimeZone: row.occurredTimeZone,
          channel: ContactChannel.fromStorage(row.channel),
          channelDetail: row.channelDetail,
          location: _locationFromColumns(
            kind: row.locationKind,
            placeName: row.placeName,
            smallestRegionId: row.smallestRegionId,
            regionTreeVersion: row.regionTreeVersion,
            latitude: row.latitude,
            longitude: row.longitude,
            accuracyMeters: row.locationAccuracyMeters,
          ),
          reachCount: row.reachCount,
          interestLevel: row.interestLevel,
          answers: await _answersForRevision(row.contactId, row.revisionNumber),
        ),
    ];
  }

  Future<ContactRecord> _contactRecordFromRow(DbContactRecord row) async {
    return ContactRecord(
      contactId: row.contactId,
      appUserId: row.appUserId,
      workspaceId: row.workspaceId,
      projectId: row.projectId,
      questionnaireVersionId: row.questionnaireVersionId,
      revisionNumber: row.currentRevision,
      occurredAtUtc: row.occurredAtUtc.toUtc(),
      occurredTimeZone: row.occurredTimeZone,
      firstSubmittedAtUtc: row.firstSubmittedAtUtc.toUtc(),
      channel: ContactChannel.fromStorage(row.channel),
      channelDetail: row.channelDetail,
      location: _locationFromColumns(
        kind: row.locationKind,
        placeName: row.placeName,
        smallestRegionId: row.smallestRegionId,
        regionTreeVersion: row.regionTreeVersion,
        latitude: row.latitude,
        longitude: row.longitude,
        accuracyMeters: row.locationAccuracyMeters,
      ),
      reachCount: row.reachCount,
      interestLevel: row.interestLevel,
      lifecycleStatus: ContactLifecycleStatus.fromStorage(row.lifecycleStatus),
      syncState: LocalSyncState.pending,
      answers: await _answersForRevision(row.contactId, row.currentRevision),
    );
  }

  ContactLocation _locationFromColumns({
    required String kind,
    required String? placeName,
    required String? smallestRegionId,
    required String? regionTreeVersion,
    required double? latitude,
    required double? longitude,
    required double? accuracyMeters,
  }) => switch (kind) {
    'resolved' => ResolvedContactLocation(
      placeName: placeName!,
      smallestRegionId: smallestRegionId!,
      regionTreeVersion: regionTreeVersion!,
    ),
    'not_applicable' => const NotApplicableContactLocation(),
    'pending_resolution' => PendingContactLocation(
      latitude: latitude!,
      longitude: longitude!,
      accuracyMeters: accuracyMeters,
    ),
    final unsupported => throw StateError(
      'unsupported_contact_location_kind:$unsupported',
    ),
  };

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
}
