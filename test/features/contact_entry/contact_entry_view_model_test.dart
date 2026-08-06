import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/device/device_time_zone.dart';
import 'package:tongxingzhe_app/app_session/session_context_gateway.dart';
import 'package:tongxingzhe_app/features/contact_entry/contact_entry_view_model.dart';
import 'package:tongxingzhe_app/features/contact_journal/contact_models.dart';
import 'package:tongxingzhe_app/foundation/runtime_values.dart';
import 'package:tongxingzhe_app/regions/contact_region_resolver.dart';
import 'package:tongxingzhe_app/questionnaires/questionnaire_contract.dart';
import 'package:tongxingzhe_app/services/location_service.dart';
import 'package:tongxingzhe_app/targets/promotion_target.dart';

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

  test('对象候选载入失败不阻止匿名接触提交', () async {
    final store = _FakeEntryStore();
    final viewModel = _viewModel(
      store: store,
      targetGateway: const _FakeTargetGateway(
        PromotionTargetRejected(PromotionTargetFailureCode.networkUnavailable),
      ),
    );
    await viewModel.initialize();
    await Future<void>.delayed(Duration.zero);
    viewModel
      ..setChannel(ContactChannel.videoCall)
      ..setReachCountText('2')
      ..setInterestLevel(3);
    await viewModel.flushDraft();

    expect(viewModel.state.targetLoadState, ContactTargetLoadState.failed);
    expect(viewModel.state.targetLinks, isEmpty);
    expect(viewModel.state.canSubmit, isTrue);
  });

  test('首次项目关联必须显式确认阶段 0', () async {
    final viewModel = _viewModel(store: _FakeEntryStore());
    await viewModel.initialize();
    final target = _target(hasCurrentProjectRelationship: false);

    expect(viewModel.linkTarget(target, confirmStageZero: false), isFalse);
    expect(viewModel.state.targetLinks, isEmpty);

    expect(viewModel.linkTarget(target, confirmStageZero: true), isTrue);
    expect(viewModel.state.targetLinks.single.confirmStageZero, isTrue);
  });

  test('机构反应只有在确认代表后才可记录，撤销确认会清空反应', () async {
    final viewModel = _viewModel(store: _FakeEntryStore());
    await viewModel.initialize();
    final institution = _target(
      type: PromotionTargetType.institution,
      hasCurrentProjectRelationship: true,
    );
    viewModel.linkTarget(institution, confirmStageZero: false);

    viewModel.setTargetResponse(institution.id, 4);
    expect(viewModel.state.targetLinks.single.responseLevel, isNull);

    viewModel.setInstitutionRepresentativeConfirmed(institution.id, true);
    viewModel.setTargetResponse(institution.id, 4);
    expect(viewModel.state.targetLinks.single.responseLevel, 4);

    viewModel.setInstitutionRepresentativeConfirmed(institution.id, false);
    expect(viewModel.state.targetLinks.single.responseLevel, isNull);
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

  test('首次保存草稿时补齐规则跳过原因', () async {
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
    final store = _FakeEntryStore();
    final viewModel = _viewModel(store: store, questionnaireVersion: version);
    await viewModel.initialize();

    viewModel.setChannel(ContactChannel.videoCall);
    await viewModel.flushDraft();

    final skippedIds =
        viewModel.state.questionnaireEvaluation.ruleSkippedQuestionIds;
    final savedAnswers = {
      for (final answer in store.savedDraft!.answers) answer.questionId: answer,
    };
    for (final questionId in skippedIds) {
      expect(
        savedAnswers[questionId]?.stateReason,
        questionnaireRuleSkippedReason,
      );
      expect(savedAnswers[questionId]?.value, isNull);
    }
  });

  test('旧问卷草稿自动保存时继续使用创建时版本', () async {
    final store = _FakeEntryStore();
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
    final viewModel = _viewModel(
      store: store,
      questionnaireVersion: _questionnaire,
      context: currentContext,
    );
    await viewModel.initialize(draft: _draftWithAnswers(const []));

    viewModel.setReachCountText('3');
    await viewModel.flushDraft();

    expect(store.savedDraft!.questionnaireVersionId, 'questionnaire-1');
  });

  test('前置答案隐藏已答问题时先确认清除，并可撤销整次变更', () async {
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
    final answers = (transitionCase['answers']! as List<Object?>)
        .map(QuestionnaireContract.parseAnswer)
        .toList();
    final topics = version.questions.singleWhere(
      (question) => question.id == 'topics',
    );
    final store = _FakeEntryStore();
    final viewModel = _viewModel(
      store: store,
      questionnaireVersion: version,
      questionnaireUndoDuration: const Duration(days: 1),
    );
    await viewModel.initialize(draft: _draftWithAnswers(answers));

    final requiresConfirmation = viewModel.setQuestionnaireValue(topics, const [
      'courses',
    ]);

    expect(requiresConfirmation, isTrue);
    expect(
      viewModel.state.pendingQuestionnaireAnswersToClear.map(
        (answer) => answer.questionId,
      ),
      ['event_detail', 'no_courses'],
    );
    expect(viewModel.state.answerFor('topics')!.value, ['events']);

    viewModel.confirmQuestionnaireClear();
    expect(viewModel.state.answerFor('topics')!.value, ['courses']);
    for (final questionId in ['event_detail', 'no_courses']) {
      final skipped = viewModel.state.answerFor(questionId)!;
      expect(skipped.state, QuestionnaireAnswerState.notApplicable);
      expect(skipped.stateReason, questionnaireRuleSkippedReason);
    }
    expect(viewModel.state.canUndoQuestionnaireClear, isTrue);
    await viewModel.flushDraft();
    expect(
      store.savedDraft!.answers
          .singleWhere((answer) => answer.questionId == 'event_detail')
          .stateReason,
      questionnaireRuleSkippedReason,
    );

    viewModel.undoQuestionnaireClear();
    expect(viewModel.state.answerFor('topics')!.value, ['events']);
    expect(viewModel.state.answerFor('event_detail')!.value, '原活动答案');
    expect(viewModel.state.answerFor('no_courses')!.value, '原课程答案');
  });
}

ContactEntryViewModel _viewModel({
  required ContactEntryStore store,
  ContactLocationCapture locationCapture = const _FakeLocationCapture([]),
  ContactRegionResolver regionResolver = const DeferredContactRegionResolver(),
  QuestionnaireVersion? questionnaireVersion,
  TrustedSessionContext context = _context,
  PromotionTargetGateway? targetGateway,
  Duration questionnaireUndoDuration = const Duration(seconds: 10),
}) {
  return ContactEntryViewModel(
    clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
    timeZoneProvider: const _FakeTimeZoneProvider('America/Chicago'),
    context: context,
    deviceId: 'device-1',
    store: store,
    locationCapture: locationCapture,
    regionResolver: regionResolver,
    questionnaireVersion: questionnaireVersion,
    targetGateway: targetGateway,
    questionnaireUndoDuration: questionnaireUndoDuration,
    saveDelay: const Duration(days: 1),
  );
}

ContactDraft _draftWithAnswers(List<QuestionnaireAnswer> answers) =>
    ContactDraft(
      draftId: 'draft-visibility',
      appUserId: 'user-1',
      workspaceId: 'workspace-1',
      projectId: 'project-1',
      questionnaireVersionId: 'questionnaire-1',
      createdAtUtc: DateTime.utc(2030, 1, 1),
      updatedAtUtc: DateTime.utc(2030, 1, 1),
      occurredAtUtc: DateTime.utc(2030, 1, 1),
      occurredTimeZone: 'America/Chicago',
      channel: ContactChannel.videoCall,
      channelDetail: null,
      location: const NotApplicableContactLocation(),
      reachCount: 1,
      interestLevel: 2,
      answers: answers,
      syncMode: ContactDraftSyncMode.accountPrivate,
      localRevision: 1,
      serverRevision: 0,
      conflictOfDraftId: null,
    );

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
      targetLinks: input.targetLinks,
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

PromotionTargetProfile _target({
  PromotionTargetType type = PromotionTargetType.person,
  required bool hasCurrentProjectRelationship,
}) => PromotionTargetProfile(
  id: type == PromotionTargetType.person ? 'target-person' : 'target-org',
  type: type,
  displayName: type == PromotionTargetType.person ? '测试对象' : '测试机构',
  phone: null,
  email: null,
  createdAtUtc: DateTime.utc(2030, 1, 1),
  hasCurrentProjectRelationship: hasCurrentProjectRelationship,
);

final class _FakeTargetGateway implements PromotionTargetGateway {
  const _FakeTargetGateway(this.result);

  final PromotionTargetResult<List<PromotionTargetProfile>> result;

  @override
  Future<PromotionTargetResult<List<PromotionTargetProfile>>>
  loadAssigned() async => result;

  @override
  Future<PromotionTargetResult<PromotionTargetProfile>> create({
    required PromotionTargetType type,
    required String displayName,
    required String? phone,
    required String? email,
    required String requestId,
  }) async =>
      const PromotionTargetRejected(PromotionTargetFailureCode.serverRejected);

  @override
  Future<PromotionTargetResult<PromotionTargetRelationship>>
  updateRelationship({
    required String targetId,
    required int expectedRevision,
    required int stage,
    required PromotionTargetRelationshipLifecycle lifecycleStatus,
    required String? followUpNote,
    required PromotionTargetRelationshipReason reason,
    required String? reasonDetail,
    required String mutationId,
    required String? resolvedConflictId,
  }) async =>
      const PromotionTargetRejected(PromotionTargetFailureCode.serverRejected);

  @override
  Future<PromotionTargetResult<List<PromotionTargetStageAlias>>>
  configureStageAliases({
    required List<PromotionTargetStageAlias> aliases,
  }) async =>
      const PromotionTargetRejected(PromotionTargetFailureCode.serverRejected);

  @override
  Future<PromotionTargetResult<List<TargetInstitutionRelationship>>>
  loadInstitutionRelationships() async =>
      const PromotionTargetRejected(PromotionTargetFailureCode.serverRejected);

  @override
  Future<PromotionTargetResult<TargetInstitutionRelationship>>
  createInstitutionRelationship({
    required String personTargetId,
    required String institutionTargetId,
    required TargetInstitutionRelationshipKind kind,
    required String? roleDescription,
    required String mutationId,
  }) async =>
      const PromotionTargetRejected(PromotionTargetFailureCode.serverRejected);

  @override
  Future<PromotionTargetResult<TargetInstitutionRelationship>>
  endInstitutionRelationship({
    required String relationshipId,
    required int expectedRevision,
    required String mutationId,
  }) async =>
      const PromotionTargetRejected(PromotionTargetFailureCode.serverRejected);

  @override
  Future<void> close() async {}
}
