import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/app_session/session_context_gateway.dart';
import 'package:tongxingzhe_app/data/local_database.dart';
import 'package:tongxingzhe_app/device/device_time_zone.dart';
import 'package:tongxingzhe_app/features/contact_journal/contact_journal.dart';
import 'package:tongxingzhe_app/features/contact_journal/contact_models.dart';
import 'package:tongxingzhe_app/features/contact_revision/contact_revision_screen.dart';
import 'package:tongxingzhe_app/foundation/runtime_values.dart';
import 'package:tongxingzhe_app/regions/contact_region_resolver.dart';
import 'package:tongxingzhe_app/services/location_service.dart';
import 'package:tongxingzhe_app/targets/promotion_target.dart';

void main() {
  testWidgets('待解析地点只显示状态，不显示精确坐标或精度', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final clock = _FixedClock(DateTime.utc(2030, 1, 10, 18));
    final journal = ContactJournal(
      database: database,
      clock: clock,
      idGenerator: _SequenceIdGenerator([
        'contact-private-location',
        'revision-private-location',
        'command-private-location',
      ]),
    );
    await journal.submitAnonymousContact(
      AnonymousContactSubmission(
        appUserId: _context.appUserId,
        workspaceId: _context.workspace.id,
        projectId: _context.project.id,
        questionnaireVersionId: _context.questionnaireVersion.id,
        deviceId: 'device-1',
        occurredAtUtc: DateTime.utc(2030, 1, 9, 17),
        occurredTimeZone: 'America/Chicago',
        channel: ContactChannel.faceToFace,
        location: const PendingContactLocation(
          latitude: 12.345678,
          longitude: -98.765432,
          accuracyMeters: 7.25,
        ),
        reachCount: 1,
        interestLevel: 2,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ContactRevisionScreen(
          localeCode: 'zh',
          context: _context,
          contactId: 'contact-private-location',
          contactJournal: journal,
          deviceId: 'device-1',
          locationCapture: const _NoLocationCapture(),
          timeZoneProvider: const _TimeZoneProvider(),
          regionResolver: const _NoopRegionResolver(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    _expectLocationCoordinatesHidden(tester);
    expect(find.textContaining('待匹配规范区域'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('correct-contact')));
    await tester.pumpAndSettle();

    _expectLocationCoordinatesHidden(tester);
    expect(find.textContaining('待匹配规范区域'), findsWidgets);
  });

  testWidgets('本人可查看历史、带原因更正并带原因作废', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = LocalDatabase(NativeDatabase.memory());
    final clock = _FixedClock(DateTime.utc(2030, 1, 10, 18));
    final journal = ContactJournal(
      database: database,
      clock: clock,
      idGenerator: _SequenceIdGenerator([
        'contact-1',
        'revision-1',
        'command-1',
        'revision-2',
        'command-2',
        'revision-3',
        'command-3',
      ]),
    );
    await journal.submitAnonymousContact(
      AnonymousContactSubmission(
        appUserId: _context.appUserId,
        workspaceId: _context.workspace.id,
        projectId: _context.project.id,
        questionnaireVersionId: _context.questionnaireVersion.id,
        deviceId: 'device-1',
        occurredAtUtc: DateTime.utc(2030, 1, 9, 17),
        occurredTimeZone: 'America/Chicago',
        channel: ContactChannel.videoCall,
        location: const NotApplicableContactLocation(),
        reachCount: 1,
        interestLevel: 2,
        targetLinks: const [
          ContactTargetLink(
            targetId: 'target-person',
            targetType: PromotionTargetType.person,
            responseLevel: 3,
            followUpConsent: ContactFollowUpConsent.yes,
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ContactRevisionScreen(
          localeCode: 'zh',
          context: _context,
          contactId: 'contact-1',
          contactJournal: journal,
          deviceId: 'device-1',
          locationCapture: const _NoLocationCapture(),
          timeZoneProvider: const _TimeZoneProvider(),
          regionResolver: const _NoopRegionResolver(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('contact-revision-1')), findsOneWidget);
    expect(find.text('初次提交'), findsOneWidget);
    expect(find.textContaining('N/A（非线下接触）'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('correct-contact')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('contact-correction-reason')),
      '修正触达人数',
    );
    await tester.enterText(
      find.byKey(const ValueKey('contact-correction-reach')),
      '3',
    );
    await tester.tap(
      find.byKey(const ValueKey('remove-contact-target-link-target-person')),
    );
    await tester.tap(find.byKey(const ValueKey('confirm-contact-correction')));
    await tester.pumpAndSettle();

    expect(find.textContaining('更正已保存'), findsOneWidget);
    expect(find.byKey(const ValueKey('contact-revision-2')), findsOneWidget);
    expect(find.textContaining('修正触达人数'), findsOneWidget);
    expect(find.textContaining('触达人数：3'), findsWidgets);
    final corrected = await journal.contactById('contact-1');
    expect(corrected!.targetLinks, isEmpty);
    final correctedHistory = await journal.listContactRevisions(
      contactId: 'contact-1',
      appUserId: _context.appUserId,
    );
    expect(correctedHistory.last.targetLinks, hasLength(1));

    await tester.tap(find.byKey(const ValueKey('void-contact')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('contact-void-reason')),
      '重复录入',
    );
    await tester.tap(find.byKey(const ValueKey('confirm-void-contact')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('contact-revision-3')), findsOneWidget);
    expect(find.textContaining('重复录入'), findsOneWidget);
    expect(find.byKey(const ValueKey('correct-contact')), findsNothing);

    final summary = await journal.summarizePersonalContacts(
      appUserId: _context.appUserId,
      workspaceId: _context.workspace.id,
      projectId: _context.project.id,
      fromUtc: DateTime.utc(2030, 1),
      untilUtc: DateTime.utc(2030, 2),
    );
    expect(summary.contactSessionCount, 0);
  });

  testWidgets('跨设备冲突显示差异并可手动组合为追加 revision', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final clock = _FixedClock(DateTime.utc(2030, 1, 10, 18));
    final journal = ContactJournal(
      database: database,
      clock: clock,
      idGenerator: _SequenceIdGenerator([
        'contact-1',
        'revision-1',
        'command-1',
        'revision-server-2',
        'command-conflict',
        'revision-resolution-3',
        'command-resolution',
      ]),
    );
    await journal.submitAnonymousContact(
      AnonymousContactSubmission(
        appUserId: _context.appUserId,
        workspaceId: _context.workspace.id,
        projectId: _context.project.id,
        questionnaireVersionId: _context.questionnaireVersion.id,
        deviceId: 'device-1',
        occurredAtUtc: DateTime.utc(2030, 1, 9, 17),
        occurredTimeZone: 'America/Chicago',
        channel: ContactChannel.faceToFace,
        location: const PendingContactLocation(
          latitude: 23.456789,
          longitude: -87.654321,
          accuracyMeters: 8.75,
        ),
        reachCount: 1,
        interestLevel: 2,
        targetLinks: const [
          ContactTargetLink(
            targetId: 'target-current',
            targetType: PromotionTargetType.person,
            responseLevel: 2,
            followUpConsent: ContactFollowUpConsent.unknown,
          ),
        ],
      ),
    );
    await journal.correctContact(
      ContactCorrectionSubmission(
        contactId: 'contact-1',
        appUserId: _context.appUserId,
        workspaceId: _context.workspace.id,
        projectId: _context.project.id,
        deviceId: 'device-other',
        baseRevision: 1,
        reason: '另一台设备修正人数',
        occurredAtUtc: DateTime.utc(2030, 1, 9, 17),
        occurredTimeZone: 'America/Chicago',
        channel: ContactChannel.faceToFace,
        location: const PendingContactLocation(
          latitude: 23.456789,
          longitude: -87.654321,
          accuracyMeters: 8.75,
        ),
        reachCount: 4,
        interestLevel: 2,
        targetLinks: const [
          ContactTargetLink(
            targetId: 'target-current',
            targetType: PromotionTargetType.person,
            responseLevel: 4,
            followUpConsent: ContactFollowUpConsent.yes,
          ),
        ],
      ),
    );
    await (database.update(database.dbSyncOutbox)
          ..where((row) => row.commandId.equals('command-conflict')))
        .write(const DbSyncOutboxCompanion(status: Value('needs_resolution')));
    await database
        .into(database.dbContactRevisionConflicts)
        .insert(
          DbContactRevisionConflictsCompanion.insert(
            conflictId: 'conflict-1',
            commandId: 'command-conflict',
            contactId: 'contact-1',
            appUserId: _context.appUserId,
            workspaceId: _context.workspace.id,
            projectId: _context.project.id,
            baseRevision: 1,
            currentRevision: 2,
            conflictingFieldsJson: jsonEncode([
              'reachCount',
              'location',
              'answers',
              'targetLinks',
            ]),
            questionnaireVersionId: _context.questionnaireVersion.id,
            currentRevisionKind: 'corrected',
            currentRevisedAtUtc: clock.now(),
            currentReason: '另一台设备修正人数',
            currentSnapshotJson: jsonEncode(
              _snapshot(
                reachCount: 4,
                answerValue: true,
                targetId: 'target-current',
                location: _pendingLocation(
                  latitude: 23.456789,
                  longitude: -87.654321,
                  accuracyMeters: 8.75,
                ),
              ),
            ),
            proposedSnapshotJson: jsonEncode(
              _snapshot(
                reachCount: 3,
                answerValue: false,
                targetId: 'target-proposed',
                location: _pendingLocation(
                  latitude: 34.567891,
                  longitude: -76.543219,
                  accuracyMeters: 9.5,
                ),
              ),
            ),
            createdAtUtc: clock.now(),
          ),
        );
    await tester.pumpWidget(
      MaterialApp(
        home: ContactRevisionScreen(
          localeCode: 'zh',
          context: _context,
          contactId: 'contact-1',
          contactJournal: journal,
          deviceId: 'device-1',
          locationCapture: const _NoLocationCapture(),
          timeZoneProvider: const _TimeZoneProvider(),
          regionResolver: const _NoopRegionResolver(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('contact-conflict-conflict-1')), findsOne);
    expect(find.textContaining('触达人数'), findsWidgets);
    expect(find.textContaining('服务器：4'), findsOne);
    expect(find.textContaining('本机：3'), findsOne);
    expect(find.textContaining('待匹配规范区域'), findsWidgets);
    for (final privateValue in [
      '23.456789',
      '-87.654321',
      '8.75',
      '34.567891',
      '-76.543219',
      '9.5',
    ]) {
      expect(find.textContaining(privateValue), findsNothing);
    }
    expect(find.textContaining('follow_up: 是'), findsOne);
    expect(find.textContaining('follow_up: 否'), findsOne);
    expect(find.textContaining('关联推广对象'), findsWidgets);
    expect(
      find.byKey(const ValueKey('use-current-conflict-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('merge-conflict-conflict-1')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('merge-conflict-conflict-1')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('conflict-answer-source')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('conflict-target-link-source')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('contact-correction-reason')),
      '组合两边修改',
    );
    await tester.enterText(
      find.byKey(const ValueKey('contact-correction-reach')),
      '5',
    );
    await tester.tap(find.byKey(const ValueKey('use-proposed-answers')));
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('conflict-target-link-source')),
        matching: find.text('本机'),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('confirm-contact-correction')));
    await tester.pumpAndSettle();

    expect(find.textContaining('正在等待同步'), findsOneWidget);
    expect(find.byKey(const ValueKey('use-proposed-conflict-1')), findsNothing);
    expect(find.byKey(const ValueKey('correct-contact')), findsNothing);
    expect(find.byKey(const ValueKey('void-contact')), findsNothing);
    expect(find.textContaining('触达人数：5'), findsWidgets);
    expect(find.byKey(const ValueKey('contact-revision-3')), findsOneWidget);
    final resolved = await journal.contactByIdForOwner(
      contactId: 'contact-1',
      appUserId: _context.appUserId,
    );
    final resolvedAnswer =
        resolved!.answers.single as BooleanQuestionnaireAnswer;
    expect(resolvedAnswer.value, isFalse);
    expect(resolved.targetLinks.single.targetId, 'target-proposed');
    final resolution = await (database.select(
      database.dbSyncOutbox,
    )..where((row) => row.commandId.equals('command-resolution'))).getSingle();
    expect(resolution.commandType, 'contact.resolve.v1');
  });
}

void _expectLocationCoordinatesHidden(WidgetTester tester) {
  expect(find.textContaining('12.345678'), findsNothing);
  expect(find.textContaining('-98.765432'), findsNothing);
  expect(find.textContaining('7.25'), findsNothing);
}

Map<String, Object?> _snapshot({
  required int reachCount,
  bool? answerValue,
  String? targetId,
  Map<String, Object?>? location,
}) => {
  'occurredAtUtc': '2030-01-09T17:00:00.000Z',
  'occurredTimeZone': 'America/Chicago',
  'channel': location == null ? 'video_call' : 'face_to_face',
  'channelDetail': null,
  'location':
      location ??
      {
        'kind': 'not_applicable',
        'placeName': null,
        'smallestRegionId': null,
        'regionTreeVersion': null,
        'latitude': null,
        'longitude': null,
        'accuracyMeters': null,
      },
  'reachCount': reachCount,
  'interestLevel': 2,
  'answers': answerValue == null
      ? <Object?>[]
      : <Object?>[
          {
            'questionId': 'follow_up',
            'state': 'answered',
            'type': 'boolean',
            'value': answerValue,
          },
        ],
  'targetLinks': targetId == null
      ? <Object?>[]
      : <Object?>[
          {
            'targetId': targetId,
            'targetType': 'person',
            'responseLevel': 3,
            'followUpConsent': 'yes',
            'institutionRepresentativeConfirmed': false,
            'confirmStageZero': false,
          },
        ],
};

Map<String, Object?> _pendingLocation({
  required double latitude,
  required double longitude,
  required double accuracyMeters,
}) => {
  'kind': 'pending_resolution',
  'placeName': null,
  'smallestRegionId': null,
  'regionTreeVersion': null,
  'latitude': latitude,
  'longitude': longitude,
  'accuracyMeters': accuracyMeters,
};

const _context = TrustedSessionContext(
  appUserId: 'app-user-1',
  workspace: WorkspaceContext(
    id: 'workspace-1',
    kind: WorkspaceKind.personal,
    name: '个人空间',
  ),
  project: ProjectContext(id: 'project-1', name: '推广项目'),
  questionnaireVersion: QuestionnaireVersionContext(
    id: 'questionnaire-v1',
    versionNumber: 1,
  ),
  capabilities: {'record_contact'},
);

final class _FixedClock implements AppClock {
  const _FixedClock(this.value);

  final DateTime value;

  @override
  DateTime now() => value;
}

final class _SequenceIdGenerator implements IdGenerator {
  _SequenceIdGenerator(this.values);

  final List<String> values;
  var _index = 0;

  @override
  String next() => values[_index++];
}

final class _NoLocationCapture implements ContactLocationCapture {
  const _NoLocationCapture();

  @override
  Future<LocationSnapshot> captureCurrentPosition() async =>
      const LocationSnapshot(error: 'location_unavailable');
}

final class _TimeZoneProvider implements DeviceTimeZoneProvider {
  const _TimeZoneProvider();

  @override
  Future<String> currentIanaTimeZone() async => 'America/Chicago';
}

final class _NoopRegionResolver implements ContactRegionResolver {
  const _NoopRegionResolver();

  @override
  Future<void> close() async {}

  @override
  Future<ContactLocation> resolve(PendingContactLocation location) async =>
      location;
}
