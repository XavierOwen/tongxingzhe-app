import '../../questionnaires/questionnaire_contract.dart';
import '../../targets/promotion_target.dart';

export '../../questionnaires/questionnaire_contract.dart'
    show
        BooleanQuestionnaireAnswer,
        DateQuestionnaireAnswer,
        LongTextQuestionnaireAnswer,
        MultiChoiceQuestionnaireAnswer,
        NumberQuestionnaireAnswer,
        OrdinalChoiceQuestionnaireAnswer,
        QuestionnaireAnswer,
        QuestionnaireAnswerState,
        ShortTextQuestionnaireAnswer,
        SingleChoiceQuestionnaireAnswer;

/// 接触使用的全平台稳定渠道分类。
///
/// 这些枚举值是领域含义；数据库和同步协议使用 [storageValue]，避免把会变化的
/// 中文显示文字当作数据合同。
enum ContactChannel {
  faceToFace('face_to_face'),
  voiceCall('voice_call'),
  videoCall('video_call'),
  instantText('instant_text'),
  asynchronousMessage('asynchronous_message'),
  mixed('mixed'),
  otherDirect('other_direct');

  const ContactChannel(this.storageValue);

  final String storageValue;

  static ContactChannel fromStorage(String value) {
    return ContactChannel.values.singleWhere(
      (channel) => channel.storageValue == value,
    );
  }
}

/// 一次接触的地点事实。
///
/// 地点不是 nullable 字段：调用者必须明确提供已解析线下地点，或在后续切片中
/// 使用“待解析”和“不适用”的专用类型。
sealed class ContactLocation {
  const ContactLocation();
}

/// 已经确定具体地点和最小规范区域的线下地点。
final class ResolvedContactLocation extends ContactLocation {
  const ResolvedContactLocation({
    required this.placeName,
    required this.smallestRegionId,
    required this.regionTreeVersion,
  });

  final String placeName;
  final String smallestRegionId;
  final String regionTreeVersion;

  @override
  bool operator ==(Object other) {
    return other is ResolvedContactLocation &&
        other.placeName == placeName &&
        other.smallestRegionId == smallestRegionId &&
        other.regionTreeVersion == regionTreeVersion;
  }

  @override
  int get hashCode =>
      Object.hash(placeName, smallestRegionId, regionTreeVersion);
}

/// 纯非线下接触明确记录的“不适用”地点。
final class NotApplicableContactLocation extends ContactLocation {
  const NotApplicableContactLocation();

  @override
  bool operator ==(Object other) => other is NotApplicableContactLocation;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// 已有原始坐标、但尚未匹配规范区域树的暂时地点。
///
/// 该状态不能用于最终区域分析；后台解析成功后会追加修订，而不是把它当作
/// `N/A` 或静默丢弃坐标。
final class PendingContactLocation extends ContactLocation {
  const PendingContactLocation({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
  });

  final double latitude;
  final double longitude;
  final double? accuracyMeters;

  @override
  bool operator ==(Object other) {
    return other is PendingContactLocation &&
        other.latitude == latitude &&
        other.longitude == longitude &&
        other.accuracyMeters == accuracyMeters;
  }

  @override
  int get hashCode => Object.hash(latitude, longitude, accuracyMeters);
}

/// 本地接触事实相对于远端的同步状态。
enum LocalSyncState { pending }

/// 接触当前是否仍参与正常统计。
enum ContactLifecycleStatus {
  active('active'),
  voided('voided');

  const ContactLifecycleStatus(this.storageValue);

  final String storageValue;

  static ContactLifecycleStatus fromStorage(String value) {
    return ContactLifecycleStatus.values.singleWhere(
      (status) => status.storageValue == value,
    );
  }
}

/// 一条追加历史所表达的动作。
enum ContactRevisionKind {
  submitted('submitted'),
  corrected('corrected'),
  voided('voided');

  const ContactRevisionKind(this.storageValue);

  final String storageValue;

  static ContactRevisionKind fromStorage(String value) {
    return ContactRevisionKind.values.singleWhere(
      (kind) => kind.storageValue == value,
    );
  }
}

/// 提交输入违反稳定接触规则时抛出的可分类错误。
///
/// UI 应依据 [code] 选择本地化提示，不解析 [toString] 的说明文字。
final class ContactValidationException implements Exception {
  const ContactValidationException(this.code);

  final String code;

  @override
  String toString() => 'ContactValidationException($code)';
}

/// SQLite 事务未能完整提交时抛出的稳定错误。
///
/// [cause] 和 [stackTrace] 只供诊断；UI 依据 [code] 显示保存失败，不解析
/// SQLite 版本相关的错误文字，也不能把失败当成已保存。
final class ContactPersistenceException implements Exception {
  const ContactPersistenceException({
    required this.code,
    required this.cause,
    required this.stackTrace,
  });

  final String code;
  final Object cause;
  final StackTrace stackTrace;

  @override
  String toString() => 'ContactPersistenceException($code)';
}

/// 一份草稿的私有保存边界。
enum ContactDraftSyncMode {
  accountPrivate('account_private'),
  deviceOnly('device_only');

  const ContactDraftSyncMode(this.storageValue);

  final String storageValue;

  static ContactDraftSyncMode fromStorage(String value) {
    return ContactDraftSyncMode.values.singleWhere(
      (mode) => mode.storageValue == value,
    );
  }
}

/// 对一个明确推广对象作出的当次跟进决定。
///
/// 联系方式是否存在不能代替当事人的同意，因此“未知”“拒绝回答”和“不适用”
/// 都保留为独立事实。
enum ContactFollowUpConsent {
  yes('yes'),
  no('no'),
  unknown('unknown'),
  refused('refused'),
  notApplicable('not_applicable');

  const ContactFollowUpConsent(this.storageValue);

  final String storageValue;

  static ContactFollowUpConsent fromStorage(String value) =>
      ContactFollowUpConsent.values.singleWhere(
        (consent) => consent.storageValue == value,
      );
}

/// 一次接触修订中与一个明确推广对象相连的受控事实。
///
/// 这里只保存对象 ID、类型和当次事实，不保存姓名、电话或邮箱。对象反应与
/// 接触整体兴趣互不推导；[confirmStageZero] 只表达使用者明确确认首次进入项目。
final class ContactTargetLink {
  const ContactTargetLink({
    required this.targetId,
    required this.targetType,
    this.responseLevel,
    this.followUpConsent = ContactFollowUpConsent.unknown,
    this.institutionRepresentativeConfirmed = false,
    this.confirmStageZero = false,
  });

  final String targetId;
  final PromotionTargetType targetType;
  final int? responseLevel;
  final ContactFollowUpConsent followUpConsent;
  final bool institutionRepresentativeConfirmed;
  final bool confirmStageZero;

  @override
  bool operator ==(Object other) =>
      other is ContactTargetLink &&
      other.targetId == targetId &&
      other.targetType == targetType &&
      other.responseLevel == responseLevel &&
      other.followUpConsent == followUpConsent &&
      other.institutionRepresentativeConfirmed ==
          institutionRepresentativeConfirmed &&
      other.confirmStageZero == confirmStageZero;

  @override
  int get hashCode => Object.hash(
    targetId,
    targetType,
    responseLevel,
    followUpConsent,
    institutionRepresentativeConfirmed,
    confirmStageZero,
  );
}

/// 草稿保存时 UI 交给 [ContactJournal] 的当前表单内容。
///
/// 归属字段只是上下文，本身不算用户输入。其余 nullable 字段代表尚未填写；
/// [ContactJournal] 负责判断是否已经出现足以创建草稿的有意义内容。
final class ContactDraftInput {
  const ContactDraftInput({
    this.draftId,
    required this.deviceId,
    required this.appUserId,
    required this.workspaceId,
    required this.projectId,
    required this.questionnaireVersionId,
    this.occurredAtUtc,
    this.occurredTimeZone,
    this.channel,
    this.channelDetail,
    this.location,
    this.reachCount,
    this.interestLevel,
    this.answers = const [],
    this.targetLinks = const [],
    this.syncMode = ContactDraftSyncMode.accountPrivate,
    this.sourceAttemptId,
    this.upgradedFromDraftId,
  });

  final String? draftId;
  final String deviceId;
  final String appUserId;
  final String workspaceId;
  final String projectId;
  final String questionnaireVersionId;
  final DateTime? occurredAtUtc;
  final String? occurredTimeZone;
  final ContactChannel? channel;
  final String? channelDetail;
  final ContactLocation? location;
  final int? reachCount;
  final int? interestLevel;
  final List<QuestionnaireAnswer> answers;
  final List<ContactTargetLink> targetLinks;
  final ContactDraftSyncMode syncMode;
  final String? sourceAttemptId;
  final String? upgradedFromDraftId;
}

/// 已经落入 SQLite 的私有接触草稿。
final class ContactDraft {
  const ContactDraft({
    required this.draftId,
    required this.appUserId,
    required this.workspaceId,
    required this.projectId,
    required this.questionnaireVersionId,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.occurredAtUtc,
    required this.occurredTimeZone,
    required this.channel,
    required this.channelDetail,
    required this.location,
    required this.reachCount,
    required this.interestLevel,
    required this.answers,
    this.targetLinks = const [],
    required this.syncMode,
    required this.localRevision,
    required this.serverRevision,
    required this.conflictOfDraftId,
    this.sourceAttemptId,
    this.upgradedFromDraftId,
  });

  final String draftId;
  final String appUserId;
  final String workspaceId;
  final String projectId;
  final String questionnaireVersionId;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  final DateTime? occurredAtUtc;
  final String? occurredTimeZone;
  final ContactChannel? channel;
  final String? channelDetail;
  final ContactLocation? location;
  final int? reachCount;
  final int? interestLevel;
  final List<QuestionnaireAnswer> answers;
  final List<ContactTargetLink> targetLinks;
  final ContactDraftSyncMode syncMode;
  final int localRevision;
  final int serverRevision;
  final String? conflictOfDraftId;
  final String? sourceAttemptId;
  final String? upgradedFromDraftId;

  bool get isConflictCopy => conflictOfDraftId != null;

  /// 草稿列表使用的稳定核心事实总数。
  int get requiredCoreFactCount => 5;

  /// 已经达到正式提交最低语义要求的核心事实组数。
  int get completedCoreFactCount {
    var completed = 0;
    if (occurredAtUtc != null &&
        occurredTimeZone != null &&
        occurredTimeZone!.trim().isNotEmpty) {
      completed++;
    }
    if (channel != null &&
        (channel != ContactChannel.otherDirect ||
            (channelDetail?.trim().isNotEmpty ?? false))) {
      completed++;
    }
    if (location != null &&
        !(channel == ContactChannel.faceToFace &&
            location is NotApplicableContactLocation)) {
      completed++;
    }
    if (reachCount != null && reachCount! > 0) {
      completed++;
    }
    if (interestLevel != null && interestLevel! >= 0 && interestLevel! <= 4) {
      completed++;
    }
    return completed;
  }

  bool get hasCompleteCoreFacts =>
      completedCoreFactCount == requiredCoreFactCount;

  @override
  bool operator ==(Object other) {
    return other is ContactDraft &&
        other.draftId == draftId &&
        other.appUserId == appUserId &&
        other.workspaceId == workspaceId &&
        other.projectId == projectId &&
        other.questionnaireVersionId == questionnaireVersionId &&
        other.createdAtUtc == createdAtUtc &&
        other.updatedAtUtc == updatedAtUtc &&
        other.occurredAtUtc == occurredAtUtc &&
        other.occurredTimeZone == occurredTimeZone &&
        other.channel == channel &&
        other.channelDetail == channelDetail &&
        other.location == location &&
        other.reachCount == reachCount &&
        other.interestLevel == interestLevel &&
        _answerListsEqual(other.answers, answers) &&
        _targetLinkListsEqual(other.targetLinks, targetLinks) &&
        other.syncMode == syncMode &&
        other.localRevision == localRevision &&
        other.serverRevision == serverRevision &&
        other.conflictOfDraftId == conflictOfDraftId &&
        other.sourceAttemptId == sourceAttemptId &&
        other.upgradedFromDraftId == upgradedFromDraftId;
  }

  @override
  int get hashCode => Object.hashAll([
    draftId,
    appUserId,
    workspaceId,
    projectId,
    questionnaireVersionId,
    createdAtUtc,
    updatedAtUtc,
    occurredAtUtc,
    occurredTimeZone,
    channel,
    channelDetail,
    location,
    reachCount,
    interestLevel,
    Object.hashAll(answers),
    Object.hashAll(targetLinks),
    syncMode,
    localRevision,
    serverRevision,
    conflictOfDraftId,
    sourceAttemptId,
    upgradedFromDraftId,
  ]);
}

/// 一次未获回应的直接联络输入。
final class ContactAttemptSubmission {
  const ContactAttemptSubmission({
    required this.appUserId,
    required this.workspaceId,
    required this.projectId,
    required this.deviceId,
    required this.occurredAtUtc,
    required this.occurredTimeZone,
    required this.channel,
    this.channelDetail,
  });

  final String appUserId;
  final String workspaceId;
  final String projectId;
  final String deviceId;
  final DateTime occurredAtUtc;
  final String occurredTimeZone;
  final ContactChannel channel;
  final String? channelDetail;
}

/// 本地已保存、等待或已经完成同步的接触尝试。
final class ContactAttempt {
  const ContactAttempt({
    required this.attemptId,
    required this.appUserId,
    required this.workspaceId,
    required this.projectId,
    required this.occurredAtUtc,
    required this.occurredTimeZone,
    required this.firstSubmittedAtUtc,
    required this.channel,
    required this.channelDetail,
    required this.linkedContactId,
  });

  final String attemptId;
  final String appUserId;
  final String workspaceId;
  final String projectId;
  final DateTime occurredAtUtc;
  final String occurredTimeZone;
  final DateTime firstSubmittedAtUtc;
  final ContactChannel channel;
  final String? channelDetail;
  final String? linkedContactId;
}

/// 本地事务成功后的接触尝试回执。
final class ContactAttemptReceipt {
  const ContactAttemptReceipt({
    required this.attemptId,
    required this.syncState,
  });

  final String attemptId;
  final LocalSyncState syncState;
}

/// 草稿已进入隐藏放弃状态后的撤销回执。
final class ContactDraftAbandonmentReceipt {
  const ContactDraftAbandonmentReceipt({
    required this.draftId,
    required this.undoUntilUtc,
  });

  final String draftId;
  final DateTime undoUntilUtc;
}

bool _answerListsEqual(
  List<QuestionnaireAnswer> first,
  List<QuestionnaireAnswer> second,
) {
  if (first.length != second.length) {
    return false;
  }
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) {
      return false;
    }
  }
  return true;
}

bool _targetLinkListsEqual(
  List<ContactTargetLink> first,
  List<ContactTargetLink> second,
) {
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) return false;
  }
  return true;
}

/// UI 提交一条默认匿名接触时交给 [ContactJournal] 的完整输入。
///
/// `appUserId`、空间、项目和问卷版本来自当前上下文；它们用于确定本地归属，
/// 不能替代 Backend 对 token、membership 和 capability 的重新验证。
final class AnonymousContactSubmission {
  const AnonymousContactSubmission({
    required this.appUserId,
    required this.workspaceId,
    required this.projectId,
    required this.questionnaireVersionId,
    required this.deviceId,
    required this.occurredAtUtc,
    required this.occurredTimeZone,
    required this.channel,
    this.channelDetail,
    required this.location,
    required this.reachCount,
    required this.interestLevel,
    this.answers = const [],
    this.targetLinks = const [],
    this.sourceAttemptId,
  });

  final String appUserId;
  final String workspaceId;
  final String projectId;
  final String questionnaireVersionId;
  final String deviceId;
  final DateTime occurredAtUtc;
  final String occurredTimeZone;
  final ContactChannel channel;
  final String? channelDetail;
  final ContactLocation location;
  final int reachCount;
  final int interestLevel;
  final List<QuestionnaireAnswer> answers;
  final List<ContactTargetLink> targetLinks;
  final String? sourceAttemptId;
}

/// 本地事务成功后的最小回执。
///
/// 收到此结果表示接触事实与待同步命令都已经落入 SQLite；它不表示服务器已经
/// 接受命令。
final class ContactSubmissionReceipt {
  const ContactSubmissionReceipt({
    required this.contactId,
    required this.revisionNumber,
    required this.syncState,
  });

  final String contactId;
  final int revisionNumber;
  final LocalSyncState syncState;
}

/// 更正已提交接触时提供的完整新快照。
///
/// [baseRevision] 是使用者开始编辑时看到的版本。它防止本机把已经变化的
/// 当前投影静默覆盖；服务端会用同一值执行最终并发检查。
final class ContactCorrectionSubmission {
  const ContactCorrectionSubmission({
    required this.contactId,
    required this.appUserId,
    required this.workspaceId,
    required this.projectId,
    required this.deviceId,
    required this.baseRevision,
    required this.reason,
    required this.occurredAtUtc,
    required this.occurredTimeZone,
    required this.channel,
    this.channelDetail,
    required this.location,
    required this.reachCount,
    required this.interestLevel,
    this.answers = const [],
    this.targetLinks = const [],
  });

  final String contactId;
  final String appUserId;
  final String workspaceId;
  final String projectId;
  final String deviceId;
  final int baseRevision;
  final String reason;
  final DateTime occurredAtUtc;
  final String occurredTimeZone;
  final ContactChannel channel;
  final String? channelDetail;
  final ContactLocation location;
  final int reachCount;
  final int interestLevel;
  final List<QuestionnaireAnswer> answers;
  final List<ContactTargetLink> targetLinks;
}

/// 作废已提交接触所需的最小命令。
final class ContactVoidSubmission {
  const ContactVoidSubmission({
    required this.contactId,
    required this.appUserId,
    required this.workspaceId,
    required this.projectId,
    required this.deviceId,
    required this.baseRevision,
    required this.reason,
  });

  final String contactId;
  final String appUserId;
  final String workspaceId;
  final String projectId;
  final String deviceId;
  final int baseRevision;
  final String reason;
}

/// 本地更正或作废事务成功后的回执。
final class ContactRevisionReceipt {
  const ContactRevisionReceipt({
    required this.contactId,
    required this.revisionNumber,
    required this.kind,
    required this.syncState,
  });

  final String contactId;
  final int revisionNumber;
  final ContactRevisionKind kind;
  final LocalSyncState syncState;
}

/// 一条可审计的接触历史快照。
final class ContactRevision {
  const ContactRevision({
    required this.revisionId,
    required this.contactId,
    required this.revisionNumber,
    required this.kind,
    required this.revisedByAppUserId,
    required this.revisedAtUtc,
    required this.reason,
    required this.occurredAtUtc,
    required this.occurredTimeZone,
    required this.channel,
    required this.channelDetail,
    required this.location,
    required this.reachCount,
    required this.interestLevel,
    required this.answers,
    this.targetLinks = const [],
  });

  final String revisionId;
  final String contactId;
  final int revisionNumber;
  final ContactRevisionKind kind;
  final String revisedByAppUserId;
  final DateTime revisedAtUtc;
  final String? reason;
  final DateTime occurredAtUtc;
  final String occurredTimeZone;
  final ContactChannel channel;
  final String? channelDetail;
  final ContactLocation location;
  final int reachCount;
  final int interestLevel;
  final List<QuestionnaireAnswer> answers;
  final List<ContactTargetLink> targetLinks;
}

/// 跨设备冲突中一方提交的完整核心事实。
///
/// 身份、权限和同步状态不属于比较快照，不能由服务端冲突 payload 反向覆盖。
final class ContactConflictSnapshot {
  const ContactConflictSnapshot({
    required this.occurredAtUtc,
    required this.occurredTimeZone,
    required this.channel,
    required this.channelDetail,
    required this.location,
    required this.reachCount,
    required this.interestLevel,
    required this.answers,
    this.targetLinks = const [],
  });

  final DateTime occurredAtUtc;
  final String occurredTimeZone;
  final ContactChannel channel;
  final String? channelDetail;
  final ContactLocation location;
  final int reachCount;
  final int interestLevel;
  final List<QuestionnaireAnswer> answers;
  final List<ContactTargetLink> targetLinks;
}

enum ContactRevisionConflictStatus {
  pending('pending'),
  resolutionPending('resolution_pending'),
  resolved('resolved');

  const ContactRevisionConflictStatus(this.storageValue);

  final String storageValue;

  static ContactRevisionConflictStatus fromStorage(String value) =>
      ContactRevisionConflictStatus.values.singleWhere(
        (status) => status.storageValue == value,
      );
}

/// 一次同字段跨设备分叉。服务器版本与本机提议都持久保留。
final class ContactRevisionConflict {
  const ContactRevisionConflict({
    required this.conflictId,
    required this.commandId,
    required this.contactId,
    required this.appUserId,
    required this.workspaceId,
    required this.projectId,
    required this.baseRevision,
    required this.currentRevision,
    required this.conflictingFields,
    required this.questionnaireVersionId,
    required this.currentRevisionKind,
    required this.currentRevisedAtUtc,
    required this.currentReason,
    required this.currentSnapshot,
    required this.proposedSnapshot,
    required this.status,
  });

  final String conflictId;
  final String commandId;
  final String contactId;
  final String appUserId;
  final String workspaceId;
  final String projectId;
  final int baseRevision;
  final int currentRevision;
  final List<String> conflictingFields;
  final String questionnaireVersionId;
  final ContactRevisionKind currentRevisionKind;
  final DateTime currentRevisedAtUtc;
  final String currentReason;
  final ContactConflictSnapshot currentSnapshot;
  final ContactConflictSnapshot proposedSnapshot;
  final ContactRevisionConflictStatus status;
}

/// 使用者对一条持久冲突提交的明确选择或合并结果。
final class ContactConflictResolutionSubmission {
  const ContactConflictResolutionSubmission({
    required this.conflictId,
    required this.appUserId,
    required this.workspaceId,
    required this.projectId,
    required this.deviceId,
    required this.reason,
    required this.snapshot,
  });

  final String conflictId;
  final String appUserId;
  final String workspaceId;
  final String projectId;
  final String deviceId;
  final String reason;
  final ContactConflictSnapshot snapshot;
}

/// `ContactJournal` 向 UI 返回的当前有效接触视图。
final class ContactRecord {
  const ContactRecord({
    required this.contactId,
    required this.appUserId,
    required this.workspaceId,
    required this.projectId,
    required this.questionnaireVersionId,
    required this.revisionNumber,
    required this.occurredAtUtc,
    required this.occurredTimeZone,
    required this.firstSubmittedAtUtc,
    required this.channel,
    required this.channelDetail,
    required this.location,
    required this.reachCount,
    required this.interestLevel,
    required this.lifecycleStatus,
    required this.syncState,
    required this.answers,
    this.targetLinks = const [],
  });

  final String contactId;
  final String appUserId;
  final String workspaceId;
  final String projectId;
  final String questionnaireVersionId;
  final int revisionNumber;
  final DateTime occurredAtUtc;
  final String occurredTimeZone;
  final DateTime firstSubmittedAtUtc;
  final ContactChannel channel;
  final String? channelDetail;
  final ContactLocation location;
  final int reachCount;
  final int interestLevel;
  final ContactLifecycleStatus lifecycleStatus;
  final LocalSyncState syncState;
  final List<QuestionnaireAnswer> answers;
  final List<ContactTargetLink> targetLinks;
}

/// 一位推广者在一个项目、一个明确 UTC 期间内的个人接触汇总。
///
/// [contactSessionCount] 以接触记录为单位；[reachCount] 以参与互动的自然
/// 人次为单位；[interestDistribution] 的索引 `0–4` 对应五档单次兴趣；
/// [channelDistribution] 的索引与 [ContactChannel.values] 一致。
/// 这是个人自我分析，不应用匿名阈值，也不能解释成管理考核。
final class PersonalContactSummary {
  const PersonalContactSummary({
    required this.contactSessionCount,
    required this.reachCount,
    required this.interestDistribution,
    required this.pendingSyncCount,
    this.channelDistribution = const [0, 0, 0, 0, 0, 0, 0],
    this.latestOccurredAtUtc,
  });

  final int contactSessionCount;
  final int reachCount;
  final List<int> interestDistribution;
  final int pendingSyncCount;
  final List<int> channelDistribution;
  final DateTime? latestOccurredAtUtc;
}
