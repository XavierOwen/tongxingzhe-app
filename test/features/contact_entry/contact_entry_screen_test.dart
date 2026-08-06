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
import 'package:tongxingzhe_app/services/location_service.dart';

void main() {
  testWidgets('草稿保存失败会显示重试入口，重试后恢复已保存', (tester) async {
    final store = _FakeEntryStore(saveFailuresRemaining: 1);
    await _pumpEntry(tester, store: store);

    await tester.tap(find.text('视频通话'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

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
      const LocationSnapshot(latitude: 41.79, longitude: -87.6),
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
    expect(find.textContaining('41.790000, -87.600000'), findsOneWidget);
    expect(find.textContaining('待匹配规范区域'), findsOneWidget);
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
}

Future<void> _pumpEntry(
  WidgetTester tester, {
  required ContactEntryStore store,
  ContactLocationCapture locationCapture = const _QueuedLocationCapture([]),
  ContactDraft? initialDraft,
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
        context: _context,
        contactJournal: journal,
        deviceId: 'device-1',
        locationCapture: locationCapture,
        timeZoneProvider: const _FakeTimeZoneProvider(),
        initialDraft: initialDraft,
        entryStore: store,
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
