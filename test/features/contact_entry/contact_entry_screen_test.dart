import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/app/app_controller.dart';
import 'package:tongxingzhe_app/app_session/session_context_gateway.dart';
import 'package:tongxingzhe_app/data/local_database.dart';
import 'package:tongxingzhe_app/device/device_time_zone.dart';
import 'package:tongxingzhe_app/features/contact_entry/contact_entry_screen.dart';
import 'package:tongxingzhe_app/features/contact_entry/contact_entry_view_model.dart';
import 'package:tongxingzhe_app/features/contact_journal/contact_journal.dart';
import 'package:tongxingzhe_app/features/contact_journal/contact_models.dart';
import 'package:tongxingzhe_app/foundation/runtime_values.dart';
import 'package:tongxingzhe_app/questionnaires/questionnaire_contract.dart';
import 'package:tongxingzhe_app/questionnaires/questionnaire_draft_upgrade.dart';
import 'package:tongxingzhe_app/services/location_service.dart';

void main() {
  testWidgets('草稿保存失败会显示重试入口，重试后恢复已保存', (tester) async {
    final store = _FakeEntryStore(saveFailuresRemaining: 1);
    await _pumpEntry(tester, store: store);

    await tester.tap(find.text('视频通话'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.textContaining('N/A（非线下接触）'), findsOneWidget);
    expect(find.text('草稿保存失败，请重试'), findsOneWidget);
    expect(find.byKey(const ValueKey('retry-draft-save')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('retry-draft-save')));
    await tester.pumpAndSettle();

    expect(find.text('已保存'), findsOneWidget);
    expect(store.saveCalls, 2);
  });

  testWidgets('定位权限失败后可在同一表单重试并恢复', (tester) async {
    final capture = _QueuedLocationCapture([
      const LocationSnapshot(error: 'location_permission_denied'),
      const LocationSnapshot(
        latitude: 41.79,
        longitude: -87.6,
        accuracyMeters: 13.75,
      ),
    ]);
    await _pumpEntry(
      tester,
      store: _FakeEntryStore(),
      locationCapture: capture,
    );
    await tester.tap(find.text('面对面'));
    await tester.pumpAndSettle();
    final locationButton = find.widgetWithText(OutlinedButton, '获取当前坐标');
    await tester.ensureVisible(locationButton);
    await tester.pumpAndSettle();

    await tester.tap(locationButton);
    await tester.pumpAndSettle();
    expect(find.text('定位权限被拒绝'), findsOneWidget);

    await tester.tap(locationButton);
    await tester.pumpAndSettle();
    expect(find.textContaining('待匹配规范区域'), findsOneWidget);
    expect(find.textContaining('41.790000'), findsNothing);
    expect(find.textContaining('-87.600000'), findsNothing);
    expect(find.textContaining('13.8'), findsNothing);
  });

  testWidgets('重新打开待解析草稿时不显示精确坐标或精度', (tester) async {
    await _pumpEntry(
      tester,
      store: _FakeEntryStore(),
      initialDraft: _pendingLocationDraft,
    );

    expect(find.textContaining('待匹配规范区域'), findsOneWidget);
    expect(find.textContaining('32.123456'), findsNothing);
    expect(find.textContaining('-96.654321'), findsNothing);
    expect(find.textContaining('6.4'), findsNothing);
  });

  testWidgets('提交失败保留可提交草稿，第二次提交可成功', (tester) async {
    final store = _FakeEntryStore(submitFailuresRemaining: 1);
    await _pumpEntry(tester, store: store, initialDraft: _completeDraft);
    await tester.scrollUntilVisible(
      find.text('正式提交'),
      120,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.tap(find.text('正式提交'));
    await tester.pumpAndSettle();
    expect(find.textContaining('草稿仍已保存'), findsOneWidget);

    await tester.tap(find.text('正式提交'));
    await tester.pumpAndSettle();
    expect(store.submitCalls, 2);
  });

  testWidgets('旧草稿显示创建时问卷版本并说明不会被新发布改写', (tester) async {
    final currentContext = TrustedSessionContext(
      appUserId: _context.appUserId,
      workspace: _context.workspace,
      project: _context.project,
      questionnaireVersion: const QuestionnaireVersionContext(
        id: 'questionnaire-2',
        versionNumber: 2,
      ),
      capabilities: _context.capabilities,
    );
    final oldVersion = QuestionnaireVersion(
      id: 'questionnaire-1',
      projectId: 'project-1',
      versionNumber: 1,
      questions: const [],
    );

    await _pumpEntry(
      tester,
      store: _FakeEntryStore(),
      initialDraft: _completeDraft,
      questionnaireVersion: oldVersion,
      context: currentContext,
    );

    expect(find.byKey(const ValueKey('old-questionnaire-version')), findsOne);
    expect(find.text('使用旧问卷版本'), findsOne);
    expect(find.text('问卷版本 1'), findsOne);
    expect(find.text('问卷版本 2'), findsNothing);
  });

  testWidgets('旧草稿升级预览分类答案并在确认后新建草稿', (tester) async {
    final fixture =
        jsonDecode(
              File(
                'fixtures/questionnaire/questionnaire-draft-upgrade-contract-v1.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final sourceVersion = QuestionnaireContract.parseVersion(fixture['source']);
    final targetVersion = QuestionnaireContract.parseVersion(fixture['target']);
    final sourceAnswers = [
      for (final value in fixture['source_answers']! as List<Object?>)
        QuestionnaireContract.parseAnswer(value),
    ];
    final compatibilities = [
      for (final value in fixture['audited_compatibilities']! as List<Object?>)
        if (value case final Map<String, Object?> item)
          AuditedQuestionnaireAnswerCompatibility(
            decisionId: item['decision_id']! as String,
            sourceQuestionId: item['source_question_id']! as String,
            targetQuestionId: item['target_question_id']! as String,
          ),
    ];
    final context = TrustedSessionContext(
      appUserId: 'user-1',
      workspace: _context.workspace,
      project: ProjectContext(id: sourceVersion.projectId, name: '推广项目'),
      questionnaireVersion: QuestionnaireVersionContext(
        id: targetVersion.id,
        versionNumber: targetVersion.versionNumber,
      ),
      capabilities: const {'record_contact'},
    );
    final sourceDraft = ContactDraft(
      draftId: 'upgrade-source',
      appUserId: context.appUserId,
      workspaceId: context.workspace.id,
      projectId: context.project.id,
      questionnaireVersionId: sourceVersion.id,
      createdAtUtc: DateTime.utc(2030, 1, 2, 3),
      updatedAtUtc: DateTime.utc(2030, 1, 2, 4),
      occurredAtUtc: DateTime.utc(2030, 1, 2, 3),
      occurredTimeZone: 'America/Chicago',
      channel: ContactChannel.videoCall,
      channelDetail: null,
      location: const NotApplicableContactLocation(),
      reachCount: 2,
      interestLevel: 3,
      answers: sourceAnswers,
      syncMode: ContactDraftSyncMode.accountPrivate,
      localRevision: 1,
      serverRevision: 1,
      conflictOfDraftId: null,
    );
    var upgradeCalls = 0;
    List<QuestionnaireAnswer>? receivedCopiedAnswers;

    await _pumpEntry(
      tester,
      store: _FakeEntryStore(),
      initialDraft: sourceDraft,
      questionnaireVersion: sourceVersion,
      currentQuestionnaireVersion: targetVersion,
      auditedUpgradeCompatibilities: compatibilities,
      context: context,
      upgradeDraft:
          ({
            required sourceDraftId,
            required appUserId,
            required deviceId,
            required targetVersion,
            required copiedAnswers,
          }) async {
            upgradeCalls++;
            receivedCopiedAnswers = copiedAnswers;
            return ContactDraft(
              draftId: 'upgrade-target',
              appUserId: appUserId,
              workspaceId: sourceDraft.workspaceId,
              projectId: sourceDraft.projectId,
              questionnaireVersionId: targetVersion.id,
              createdAtUtc: DateTime.utc(2030, 1, 2, 5),
              updatedAtUtc: DateTime.utc(2030, 1, 2, 5),
              occurredAtUtc: sourceDraft.occurredAtUtc,
              occurredTimeZone: sourceDraft.occurredTimeZone,
              channel: sourceDraft.channel,
              channelDetail: sourceDraft.channelDetail,
              location: sourceDraft.location,
              reachCount: sourceDraft.reachCount,
              interestLevel: sourceDraft.interestLevel,
              answers: copiedAnswers,
              syncMode: ContactDraftSyncMode.accountPrivate,
              localRevision: 1,
              serverRevision: 0,
              conflictOfDraftId: null,
              upgradedFromDraftId: sourceDraftId,
            );
          },
    );

    await tester.tap(
      find.byKey(const ValueKey('preview-questionnaire-upgrade')),
    );
    await tester.pumpAndSettle();

    expect(find.text('升级到当前问卷'), findsOneWidget);
    expect(find.text('经审计可保留的答案'), findsOneWidget);
    expect(find.text('需要重新确认的新问卷问题'), findsOneWidget);
    expect(find.text('不能复制的旧答案'), findsOneWidget);
    expect(upgradeCalls, 0);

    await tester.tap(
      find.byKey(const ValueKey('confirm-questionnaire-upgrade')),
    );
    await tester.pumpAndSettle();

    expect(upgradeCalls, 1);
    expect(receivedCopiedAnswers!.map((answer) => answer.questionId), [
      'consent_v2',
      'age',
    ]);
    expect(find.text('新草稿已创建'), findsOneWidget);
    expect(sourceDraft.questionnaireVersionId, sourceVersion.id);
    expect(sourceDraft.answers, sourceAnswers);
  });

  testWidgets('隐藏已答问题前先确认，确认后可撤销', (tester) async {
    final fixture =
        jsonDecode(
              File(
                'fixtures/questionnaire/questionnaire-visibility-contract-v1.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final version = QuestionnaireContract.parseVersion(
      fixture['questionnaire'],
    );
    final transitionCase = fixture['transition_case']! as Map<String, Object?>;
    final answers =
        (transitionCase['answers']! as List<Object?>)
            .map(QuestionnaireContract.parseAnswer)
            .toList()
          ..addAll(const [
            ShortTextQuestionnaireAnswer(questionId: 'note', value: '原说明'),
            ShortTextQuestionnaireAnswer(
              questionId: 'note_filled',
              value: '原补充',
            ),
          ]);
    final context = TrustedSessionContext(
      appUserId: 'user-1',
      workspace: _context.workspace,
      project: ProjectContext(id: version.projectId, name: '推广项目'),
      questionnaireVersion: QuestionnaireVersionContext(
        id: version.id,
        versionNumber: version.versionNumber,
      ),
      capabilities: const {'record_contact'},
    );
    final draft = ContactDraft(
      draftId: 'draft-visibility',
      appUserId: context.appUserId,
      workspaceId: context.workspace.id,
      projectId: context.project.id,
      questionnaireVersionId: version.id,
      createdAtUtc: DateTime.utc(2030, 1, 2, 3),
      updatedAtUtc: DateTime.utc(2030, 1, 2, 4),
      occurredAtUtc: DateTime.utc(2030, 1, 2, 3),
      occurredTimeZone: 'America/Chicago',
      channel: ContactChannel.videoCall,
      channelDetail: null,
      location: const NotApplicableContactLocation(),
      reachCount: 2,
      interestLevel: 3,
      answers: answers,
      syncMode: ContactDraftSyncMode.accountPrivate,
      localRevision: 1,
      serverRevision: 1,
      conflictOfDraftId: null,
    );
    await _pumpEntry(
      tester,
      store: _FakeEntryStore(),
      initialDraft: draft,
      questionnaireVersion: version,
      context: context,
    );
    final courses = find.byKey(const ValueKey('question-topics-courses'));
    await tester.ensureVisible(courses);
    await tester.pumpAndSettle();

    await tester.tap(courses);
    await tester.pumpAndSettle();

    expect(find.text('这些答案将被清除'), findsOneWidget);
    expect(find.text('• 未选课程说明'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('question-no_courses')), findsOneWidget);

    await tester.tap(courses);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-questionnaire-clear')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('question-no_courses')), findsNothing);
    expect(find.text('不再适用的问题答案已清除'), findsOneWidget);
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('question-no_courses')), findsOneWidget);

    final note = find.byKey(const ValueKey('question-value-note'));
    await tester.ensureVisible(note);
    await tester.pumpAndSettle();
    await tester.enterText(note, '');
    await tester.pumpAndSettle();
    expect(find.text('• 已填写说明后的补充'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();

    final restoredNote = tester.widget<TextField>(note);
    expect(restoredNote.controller!.text, '原说明');
  });
}

Future<void> _pumpEntry(
  WidgetTester tester, {
  required ContactEntryStore store,
  ContactLocationCapture locationCapture = const _QueuedLocationCapture([]),
  ContactDraft? initialDraft,
  QuestionnaireVersion? questionnaireVersion,
  QuestionnaireVersion? currentQuestionnaireVersion,
  List<AuditedQuestionnaireAnswerCompatibility> auditedUpgradeCompatibilities =
      const [],
  ContactDraftUpgradeAction? upgradeDraft,
  TrustedSessionContext context = _context,
}) async {
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final database = LocalDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  final controller = AppController(
    database: database,
    clock: const _FixedClock(),
    idGenerator: _SequenceIdGenerator(),
  );
  final journal = ContactJournal(
    database: database,
    clock: const _FixedClock(),
    idGenerator: _SequenceIdGenerator(),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: ContactEntryScreen(
        controller: controller,
        clock: const _FixedClock(),
        context: context,
        contactJournal: journal,
        deviceId: 'device-1',
        locationCapture: locationCapture,
        timeZoneProvider: const _FakeTimeZoneProvider(),
        initialDraft: initialDraft,
        entryStore: store,
        questionnaireVersion: questionnaireVersion,
        currentQuestionnaireVersion: currentQuestionnaireVersion,
        auditedUpgradeCompatibilities: auditedUpgradeCompatibilities,
        upgradeDraft: upgradeDraft,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _context = TrustedSessionContext(
  appUserId: 'user-1',
  workspace: WorkspaceContext(
    id: 'workspace-1',
    kind: WorkspaceKind.personal,
    name: '个人空间',
  ),
  project: ProjectContext(id: 'project-1', name: '推广项目'),
  questionnaireVersion: QuestionnaireVersionContext(
    id: 'questionnaire-1',
    versionNumber: 1,
  ),
  capabilities: {'record_contact'},
);

final _completeDraft = ContactDraft(
  draftId: 'draft-complete',
  appUserId: 'user-1',
  workspaceId: 'workspace-1',
  projectId: 'project-1',
  questionnaireVersionId: 'questionnaire-1',
  createdAtUtc: DateTime.utc(2030, 1, 2, 3),
  updatedAtUtc: DateTime.utc(2030, 1, 2, 4),
  occurredAtUtc: DateTime.utc(2030, 1, 2, 3),
  occurredTimeZone: 'America/Chicago',
  channel: ContactChannel.videoCall,
  channelDetail: null,
  location: const NotApplicableContactLocation(),
  reachCount: 2,
  interestLevel: 3,
  answers: const [],
  syncMode: ContactDraftSyncMode.accountPrivate,
  localRevision: 1,
  serverRevision: 1,
  conflictOfDraftId: null,
);

final _pendingLocationDraft = ContactDraft(
  draftId: 'draft-pending-location',
  appUserId: 'user-1',
  workspaceId: 'workspace-1',
  projectId: 'project-1',
  questionnaireVersionId: 'questionnaire-1',
  createdAtUtc: DateTime.utc(2030, 1, 2, 3),
  updatedAtUtc: DateTime.utc(2030, 1, 2, 4),
  occurredAtUtc: DateTime.utc(2030, 1, 2, 3),
  occurredTimeZone: 'America/Chicago',
  channel: ContactChannel.faceToFace,
  channelDetail: null,
  location: const PendingContactLocation(
    latitude: 32.123456,
    longitude: -96.654321,
    accuracyMeters: 6.4,
  ),
  reachCount: 2,
  interestLevel: 3,
  answers: const [],
  syncMode: ContactDraftSyncMode.accountPrivate,
  localRevision: 1,
  serverRevision: 1,
  conflictOfDraftId: null,
);

final class _FakeEntryStore implements ContactEntryStore {
  _FakeEntryStore({
    this.saveFailuresRemaining = 0,
    this.submitFailuresRemaining = 0,
  });

  int saveFailuresRemaining;
  int submitFailuresRemaining;
  int saveCalls = 0;
  int submitCalls = 0;
  ContactDraft? savedDraft;

  @override
  Future<ContactDraft?> saveDraft(ContactDraftInput input) async {
    saveCalls++;
    if (saveFailuresRemaining > 0) {
      saveFailuresRemaining--;
      throw StateError('synthetic save failure');
    }
    return savedDraft = ContactDraft(
      draftId: input.draftId ?? 'draft-1',
      appUserId: input.appUserId,
      workspaceId: input.workspaceId,
      projectId: input.projectId,
      questionnaireVersionId: input.questionnaireVersionId,
      createdAtUtc: DateTime.utc(2030, 1, 2, 3),
      updatedAtUtc: DateTime.utc(2030, 1, 2, 4),
      occurredAtUtc: input.occurredAtUtc,
      occurredTimeZone: input.occurredTimeZone,
      channel: input.channel,
      channelDetail: input.channelDetail,
      location: input.location,
      reachCount: input.reachCount,
      interestLevel: input.interestLevel,
      answers: input.answers,
      syncMode: input.syncMode,
      localRevision: 1,
      serverRevision: 0,
      conflictOfDraftId: null,
    );
  }

  @override
  Future<ContactSubmissionReceipt> submitDraft({
    required String draftId,
    required String appUserId,
    required String deviceId,
  }) async {
    submitCalls++;
    if (submitFailuresRemaining > 0) {
      submitFailuresRemaining--;
      throw StateError('synthetic submit failure');
    }
    return const ContactSubmissionReceipt(
      contactId: 'contact-1',
      revisionNumber: 1,
      syncState: LocalSyncState.pending,
    );
  }
}

final class _QueuedLocationCapture implements ContactLocationCapture {
  const _QueuedLocationCapture(this.results);

  final List<LocationSnapshot> results;

  @override
  Future<LocationSnapshot> captureCurrentPosition() async =>
      results.removeAt(0);
}

final class _FakeTimeZoneProvider implements DeviceTimeZoneProvider {
  const _FakeTimeZoneProvider();

  @override
  Future<String> currentIanaTimeZone() async => 'America/Chicago';
}

final class _FixedClock implements AppClock {
  const _FixedClock();

  @override
  DateTime now() => DateTime.utc(2030, 1, 2, 3, 4);
}

final class _SequenceIdGenerator implements IdGenerator {
  var nextValue = 0;

  @override
  String next() => 'test-${nextValue++}';
}
