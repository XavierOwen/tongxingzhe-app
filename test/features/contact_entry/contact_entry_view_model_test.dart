import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/device/device_time_zone.dart';
import 'package:tongxingzhe_app/app_session/session_context_gateway.dart';
import 'package:tongxingzhe_app/features/contact_entry/contact_entry_view_model.dart';
import 'package:tongxingzhe_app/features/contact_journal/contact_models.dart';
import 'package:tongxingzhe_app/foundation/runtime_values.dart';
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
}

ContactEntryViewModel _viewModel({
  required ContactEntryStore store,
  ContactLocationCapture locationCapture = const _FakeLocationCapture([]),
}) {
  return ContactEntryViewModel(
    clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
    timeZoneProvider: const _FakeTimeZoneProvider('America/Chicago'),
    context: _context,
    deviceId: 'device-1',
    store: store,
    locationCapture: locationCapture,
    saveDelay: const Duration(days: 1),
  );
}

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
