import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/device/device_time_zone.dart';
import 'package:tongxingzhe_app/app_session/session_context_gateway.dart';
import 'package:tongxingzhe_app/features/contact_entry/contact_entry_view_model.dart';
import 'package:tongxingzhe_app/features/contact_journal/contact_models.dart';
import 'package:tongxingzhe_app/foundation/runtime_values.dart';
import 'package:tongxingzhe_app/regions/contact_region_resolver.dart';
import 'package:tongxingzhe_app/questionnaires/questionnaire_contract.dart';
import 'package:tongxingzhe_app/services/location_service.dart';

void main() {
  test('新接触使用当前 UTC 时刻和设备 IANA 时区', () async {
    final viewModel = ContactEntryViewModel(
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      timeZoneProvider: const _FakeTimeZoneProvider('America/Chicago'),
      context: _context,
      deviceId: 'device-1',
      store: _FakeEntryStore(),
      locationCapture: const _FakeLocationCapture([]),
    );

    await viewModel.initialize();

    expect(viewModel.state.occurredAtUtc, DateTime.utc(2030, 1, 2, 3, 4));
    expect(viewModel.state.occurredTimeZone, 'America/Chicago');
  });

  test('补录时间按设备当地时间转换为 UTC 并保留 IANA 时区', () async {
    final viewModel = ContactEntryViewModel(
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      timeZoneProvider: const _FakeTimeZoneProvider('America/Chicago'),
      context: _context,
      deviceId: 'device-1',
      store: _FakeEntryStore(),
      locationCapture: const _FakeLocationCapture([]),
    );
    await viewModel.initialize();
    final selectedLocalTime = DateTime(2029, 12, 20, 18, 30);

    viewModel.setOccurredAtLocal(selectedLocalTime);

    expect(viewModel.state.occurredAtUtc, selectedLocalTime.toUtc());
    expect(viewModel.state.occurredTimeZone, 'America/Chicago');
  });

  test('保存失败后保留未保存状态，并可显式重试恢复', () async {
    final store = _FakeEntryStore(saveFailuresRemaining: 1);
    final viewModel = _viewModel(store: store);
    await viewModel.initialize();

    viewModel.setChannel(ContactChannel.videoCall);
    await viewModel.flushDraft();

    expect(viewModel.state.saveState, ContactDraftSaveState.failed);
    expect(viewModel.state.hasUnsavedChanges, isTrue);

    await viewModel.retrySave();

    expect(viewModel.state.saveState, ContactDraftSaveState.saved);
    expect(viewModel.state.hasUnsavedChanges, isFalse);
    expect(viewModel.state.draft, isNotNull);
  });

  test('提交失败不会破坏已保存草稿，第二次可恢复', () async {
    final store = _FakeEntryStore(submitFailuresRemaining: 1);
    final viewModel = _viewModel(store: store);
    await viewModel.initialize();
    viewModel
      ..setChannel(ContactChannel.videoCall)
      ..setReachCountText('2')
      ..setInterestLevel(3);
    await viewModel.flushDraft();

    expect(viewModel.state.canSubmit, isTrue);
    expect(await viewModel.submit(), isFalse);
    expect(viewModel.state.canSubmit, isTrue);
    expect(viewModel.state.submissionFailure, 'contact_submission_failed');

    expect(await viewModel.submit(), isTrue);
    expect(store.submitCalls, 2);
  });

  test('定位失败后可重试，并把坐标状态留在 ViewModel', () async {
    final location = _FakeLocationCapture([
      const LocationSnapshot(error: 'location_permission_denied'),
      const LocationSnapshot(latitude: 41.79, longitude: -87.6),
    ]);
    final viewModel = _viewModel(
      store: _FakeEntryStore(),
      locationCapture: location,
    );
    await viewModel.initialize();
    viewModel.setChannel(ContactChannel.faceToFace);

    expect(await viewModel.captureLocation(), 'location_permission_denied');
    expect(viewModel.state.location, isNull);
    expect(await viewModel.captureLocation(), isNull);
    expect(viewModel.state.location, isA<PendingContactLocation>());
  });

  test('取得坐标后采用规范区域解析结果', () async {
    final resolver = _FakeRegionResolver(
      result: const ResolvedContactLocation(
        placeName: '芝加哥大学',
        smallestRegionId: 'institution-uchicago',
        regionTreeVersion: 'test-regions-v1',
      ),
    );
    final viewModel = _viewModel(
      store: _FakeEntryStore(),
      locationCapture: _FakeLocationCapture([
        const LocationSnapshot(
          latitude: 41.7897,
          longitude: -87.5997,
          accuracyMeters: 8.5,
        ),
      ]),
      regionResolver: resolver,
    );
    await viewModel.initialize();
    viewModel.setChannel(ContactChannel.faceToFace);

    expect(await viewModel.captureLocation(), isNull);
    expect(viewModel.state.location, isA<ResolvedContactLocation>());
    expect(resolver.received, hasLength(1));
    expect(resolver.received.single.latitude, 41.7897);
  });

  test('规范区域解析异常时保留坐标待后续匹配', () async {
    final viewModel = _viewModel(
      store: _FakeEntryStore(),
      locationCapture: _FakeLocationCapture([
        const LocationSnapshot(latitude: 41.7897, longitude: -87.5997),
      ]),
      regionResolver: _FakeRegionResolver(error: StateError('offline')),
    );
    await viewModel.initialize();
    viewModel.setChannel(ContactChannel.faceToFace);

    expect(await viewModel.captureLocation(), isNull);
    expect(viewModel.state.location, isA<PendingContactLocation>());
  });

  test('必填问卷未回答时阻止提交，回答后与草稿一起保存', () async {
    final store = _FakeEntryStore();
    final viewModel = _viewModel(
      store: store,
      questionnaireVersion: _questionnaire,
    );
    await viewModel.initialize();
    viewModel
      ..setChannel(ContactChannel.videoCall)
      ..setReachCountText('2')
      ..setInterestLevel(3);
    await viewModel.flushDraft();

    expect(viewModel.state.completedQuestionCount, 0);
    expect(viewModel.state.questionnaireEvaluation.isValid, isFalse);
    expect(viewModel.state.canSubmit, isFalse);

    viewModel.setQuestionnaireValue(_questionnaire.questions.first, true);
    await viewModel.flushDraft();

    expect(viewModel.state.completedQuestionCount, 1);
    expect(viewModel.state.questionnaireEvaluation.isValid, isTrue);
    expect(store.savedDraft!.answers, [
      const BooleanQuestionnaireAnswer(questionId: 'consent', value: true),
    ]);
    expect(viewModel.state.canSubmit, isTrue);
  });
}

ContactEntryViewModel _viewModel({
  required ContactEntryStore store,
  ContactLocationCapture locationCapture = const _FakeLocationCapture([]),
  ContactRegionResolver regionResolver = const DeferredContactRegionResolver(),
  QuestionnaireVersion? questionnaireVersion,
}) {
  return ContactEntryViewModel(
    clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
    timeZoneProvider: const _FakeTimeZoneProvider('America/Chicago'),
    context: _context,
    deviceId: 'device-1',
    store: store,
    locationCapture: locationCapture,
    regionResolver: regionResolver,
    questionnaireVersion: questionnaireVersion,
    saveDelay: const Duration(days: 1),
  );
}

final _questionnaire = QuestionnaireVersion(
  id: 'questionnaire-1',
  projectId: 'project-1',
  versionNumber: 1,
  questions: [
    QuestionnaireQuestion(
      id: 'consent',
      position: 1,
      prompt: '是否同意后续联系？',
      type: QuestionnaireQuestionType.boolean,
      required: true,
      allowUnknown: false,
      allowRefused: true,
      allowNotApplicable: false,
    ),
  ],
);

const _context = TrustedSessionContext(
  appUserId: 'user-1',
  workspace: WorkspaceContext(
    id: 'workspace-1',
    kind: WorkspaceKind.personal,
    name: '个人空间',
  ),
  project: ProjectContext(id: 'project-1', name: '项目'),
  questionnaireVersion: QuestionnaireVersionContext(
    id: 'questionnaire-1',
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

final class _FakeTimeZoneProvider implements DeviceTimeZoneProvider {
  const _FakeTimeZoneProvider(this.value);

  final String value;

  @override
  Future<String> currentIanaTimeZone() async => value;
}

final class _FakeLocationCapture implements ContactLocationCapture {
  const _FakeLocationCapture(this.results);

  final List<LocationSnapshot> results;

  @override
  Future<LocationSnapshot> captureCurrentPosition() async =>
      results.removeAt(0);
}

final class _FakeRegionResolver implements ContactRegionResolver {
  _FakeRegionResolver({this.result, this.error});

  final ContactLocation? result;
  final Object? error;
  final List<PendingContactLocation> received = [];

  @override
  Future<ContactLocation> resolve(PendingContactLocation location) async {
    received.add(location);
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return result ?? location;
  }

  @override
  Future<void> close() async {}
}

final class _FakeEntryStore implements ContactEntryStore {
  _FakeEntryStore({
    this.saveFailuresRemaining = 0,
    this.submitFailuresRemaining = 0,
  });

  int saveFailuresRemaining;
  int submitFailuresRemaining;
  int submitCalls = 0;
  ContactDraft? savedDraft;

  @override
  Future<ContactDraft?> saveDraft(ContactDraftInput input) async {
    if (saveFailuresRemaining > 0) {
      saveFailuresRemaining--;
      throw StateError('synthetic save failure');
    }
    final previous = savedDraft;
    final savedAt = DateTime.utc(2030, 1, 2, 4);
    return savedDraft = ContactDraft(
      draftId: input.draftId ?? 'draft-1',
      appUserId: input.appUserId,
      workspaceId: input.workspaceId,
      projectId: input.projectId,
      questionnaireVersionId: input.questionnaireVersionId,
      createdAtUtc: previous?.createdAtUtc ?? savedAt,
      updatedAtUtc: savedAt,
      occurredAtUtc: input.occurredAtUtc,
      occurredTimeZone: input.occurredTimeZone,
      channel: input.channel,
      channelDetail: input.channelDetail,
      location: input.location,
      reachCount: input.reachCount,
      interestLevel: input.interestLevel,
      answers: input.answers,
      syncMode: input.syncMode,
      localRevision: (previous?.localRevision ?? 0) + 1,
      serverRevision: previous?.serverRevision ?? 0,
      conflictOfDraftId: previous?.conflictOfDraftId,
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
