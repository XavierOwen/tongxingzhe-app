import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app_session/session_context_gateway.dart';
import '../../device/device_time_zone.dart';
import '../../foundation/runtime_values.dart';
import '../../services/location_service.dart';
import '../contact_journal/contact_journal.dart';
import '../contact_journal/contact_models.dart';

/// 接触录入的自动保存状态。Widget 只负责把状态翻译成图标和文字。
enum ContactDraftSaveState { untouched, waiting, saving, saved, failed }

/// 接触录入模块需要的最小持久化接口。
///
/// 这个测试接缝让失败、重试和并发编辑可以用确定性的 fake 验证，而不让
/// ViewModel 或 Widget 知道 Drift 表的结构。
abstract interface class ContactEntryStore {
  Future<ContactDraft?> saveDraft(ContactDraftInput input);

  Future<ContactSubmissionReceipt> submitDraft({
    required String draftId,
    required String appUserId,
    required String deviceId,
  });
}

/// 把正式 [ContactJournal] 收窄为接触录入需要的两个操作。
final class ContactJournalEntryStore implements ContactEntryStore {
  const ContactJournalEntryStore(this._journal);

  final ContactJournal _journal;

  @override
  Future<ContactDraft?> saveDraft(ContactDraftInput input) =>
      _journal.saveDraft(input);

  @override
  Future<ContactSubmissionReceipt> submitDraft({
    required String draftId,
    required String appUserId,
    required String deviceId,
  }) => _journal.submitDraft(
    draftId: draftId,
    appUserId: appUserId,
    deviceId: deviceId,
  );
}

/// Widget 可观察的完整表单快照。
final class ContactEntryViewState {
  const ContactEntryViewState({
    this.occurredAtUtc,
    this.occurredTimeZone,
    this.initializationFailure,
    this.draft,
    this.channel,
    this.channelDetail = '',
    this.location,
    this.reachCount,
    this.interestLevel,
    this.syncMode = ContactDraftSyncMode.accountPrivate,
    this.saveState = ContactDraftSaveState.untouched,
    this.hasUnsavedChanges = false,
    this.isSubmitting = false,
    this.isCapturingLocation = false,
    this.submissionFailure,
  });

  final DateTime? occurredAtUtc;
  final String? occurredTimeZone;
  final String? initializationFailure;
  final ContactDraft? draft;
  final ContactChannel? channel;
  final String channelDetail;
  final ContactLocation? location;
  final int? reachCount;
  final int? interestLevel;
  final ContactDraftSyncMode syncMode;
  final ContactDraftSaveState saveState;
  final bool hasUnsavedChanges;
  final bool isSubmitting;
  final bool isCapturingLocation;
  final String? submissionFailure;

  bool get isReady =>
      occurredAtUtc != null &&
      occurredTimeZone != null &&
      initializationFailure == null;

  bool get isConflictCopy => draft?.isConflictCopy ?? false;

  int get requiredCoreFactCount => 5;

  int get completedCoreFactCount {
    var completed = 0;
    if (occurredAtUtc != null && occurredTimeZone?.trim().isNotEmpty == true) {
      completed++;
    }
    if (channel != null &&
        (channel != ContactChannel.otherDirect ||
            channelDetail.trim().isNotEmpty)) {
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

  bool get canSubmit =>
      !isSubmitting &&
      !isConflictCopy &&
      draft != null &&
      saveState == ContactDraftSaveState.saved &&
      completedCoreFactCount == requiredCoreFactCount;
}

/// 管理时间、定位、草稿自动保存和正式提交的接触录入深模块。
///
/// Widget 只收集系统日期/时间选择器的结果并渲染 [state]。所有会改变领域状态
/// 或访问服务的操作都在这里串行化，因此相同规则可被单元测试和其他 UI 复用。
final class ContactEntryViewModel extends ChangeNotifier {
  ContactEntryViewModel({
    required AppClock clock,
    required DeviceTimeZoneProvider timeZoneProvider,
    required TrustedSessionContext context,
    required String deviceId,
    required ContactEntryStore store,
    required ContactLocationCapture locationCapture,
    Duration saveDelay = const Duration(milliseconds: 350),
  }) : this._(
         clock,
         timeZoneProvider,
         context,
         deviceId,
         store,
         locationCapture,
         saveDelay,
       );

  ContactEntryViewModel._(
    this._clock,
    this._timeZoneProvider,
    this._context,
    this._deviceId,
    this._store,
    this._locationCapture,
    this._saveDelay,
  );

  final AppClock _clock;
  final DeviceTimeZoneProvider _timeZoneProvider;
  final TrustedSessionContext _context;
  final String _deviceId;
  final ContactEntryStore _store;
  final ContactLocationCapture _locationCapture;
  final Duration _saveDelay;

  Timer? _saveTimer;
  Future<void>? _activeSave;
  ContactDraft? _draft;
  DateTime? _occurredAtUtc;
  String? _occurredTimeZone;
  String? _initializationFailure;
  ContactChannel? _channel;
  String _channelDetail = '';
  ContactLocation? _location;
  int? _reachCount;
  int? _interestLevel;
  ContactDraftSyncMode _syncMode = ContactDraftSyncMode.accountPrivate;
  ContactDraftSaveState _saveState = ContactDraftSaveState.untouched;
  String? _submissionFailure;
  var _isSubmitting = false;
  var _isCapturingLocation = false;
  var _editRevision = 0;
  var _savedRevision = 0;
  var _initialized = false;
  var _disposed = false;

  ContactEntryViewState get state => ContactEntryViewState(
    occurredAtUtc: _occurredAtUtc,
    occurredTimeZone: _occurredTimeZone,
    initializationFailure: _initializationFailure,
    draft: _draft,
    channel: _channel,
    channelDetail: _channelDetail,
    location: _location,
    reachCount: _reachCount,
    interestLevel: _interestLevel,
    syncMode: _syncMode,
    saveState: _saveState,
    hasUnsavedChanges: _hasUnsavedChanges,
    isSubmitting: _isSubmitting,
    isCapturingLocation: _isCapturingLocation,
    submissionFailure: _submissionFailure,
  );

  bool get _hasUnsavedChanges => _editRevision > _savedRevision;

  Future<void> initialize({ContactDraft? draft}) async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    _draft = draft;
    _channel = draft?.channel;
    _channelDetail = draft?.channelDetail ?? '';
    _location = draft?.location;
    _reachCount = draft?.reachCount;
    _interestLevel = draft?.interestLevel;
    _syncMode = draft?.syncMode ?? ContactDraftSyncMode.accountPrivate;
    if (draft != null) {
      _saveState = ContactDraftSaveState.saved;
    }
    if (draft?.occurredAtUtc != null && draft?.occurredTimeZone != null) {
      _occurredAtUtc = draft!.occurredAtUtc!.toUtc();
      _occurredTimeZone = draft.occurredTimeZone;
      _notify();
      return;
    }
    try {
      _occurredTimeZone = await _timeZoneProvider.currentIanaTimeZone();
      _occurredAtUtc = _clock.now().toUtc();
    } on DeviceTimeZoneException catch (error) {
      _initializationFailure = error.code;
    } catch (_) {
      _initializationFailure = 'device_time_zone_unavailable';
    }
    _notify();
  }

  void setOccurredAtLocal(DateTime localTime) {
    _requireReady();
    _occurredAtUtc = localTime.toUtc();
    _markEdited();
  }

  void setChannel(ContactChannel channel) {
    if (_channel == channel) {
      return;
    }
    _channel = channel;
    if (channel != ContactChannel.otherDirect) {
      _channelDetail = '';
    }
    if (_usesAutomaticNotApplicableLocation(channel)) {
      _location = const NotApplicableContactLocation();
    } else if (_location is NotApplicableContactLocation) {
      _location = null;
    }
    _markEdited();
  }

  void setChannelDetail(String value) {
    if (_channelDetail == value) {
      return;
    }
    _channelDetail = value;
    _markEdited();
  }

  void setReachCountText(String value) {
    final parsed = int.tryParse(value.trim());
    final next = parsed != null && parsed > 0 ? parsed : null;
    if (_reachCount == next) {
      return;
    }
    _reachCount = next;
    _markEdited();
  }

  void setInterestLevel(int value) {
    if (_interestLevel == value) {
      return;
    }
    _interestLevel = value;
    _markEdited();
  }

  void setSyncMode(ContactDraftSyncMode mode) {
    if (_syncMode == mode || (_draft?.isConflictCopy ?? false)) {
      return;
    }
    _syncMode = mode;
    _markEdited();
  }

  /// 成功时返回 `null`；失败时返回可本地化的稳定错误码。
  Future<String?> captureLocation() async {
    if (_isCapturingLocation) {
      return null;
    }
    _isCapturingLocation = true;
    _notify();
    final snapshot = await _locationCapture.captureCurrentPosition();
    if (_disposed) {
      return snapshot.error;
    }
    _isCapturingLocation = false;
    if (!snapshot.hasPosition) {
      _notify();
      return snapshot.error ?? 'location_unavailable';
    }
    _location = PendingContactLocation(
      latitude: snapshot.latitude!,
      longitude: snapshot.longitude!,
      accuracyMeters: snapshot.accuracyMeters,
    );
    _markEdited();
    return null;
  }

  void _markEdited() {
    _editRevision++;
    _saveState = ContactDraftSaveState.waiting;
    _submissionFailure = null;
    _notify();
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, () => unawaited(flushDraft()));
  }

  Future<void> retrySave() => flushDraft();

  /// 立即保存所有已排队编辑；编辑发生在 I/O 期间时继续保存下一版。
  Future<void> flushDraft() {
    _saveTimer?.cancel();
    final active = _activeSave;
    if (active != null) {
      return active;
    }
    if (!_hasUnsavedChanges || _disposed) {
      return Future.value();
    }
    late final Future<void> operation;
    operation = _drainPendingSaves().whenComplete(() {
      if (identical(_activeSave, operation)) {
        _activeSave = null;
      }
    });
    _activeSave = operation;
    return operation;
  }

  Future<void> _drainPendingSaves() async {
    while (!_disposed && _hasUnsavedChanges) {
      final savingRevision = _editRevision;
      _saveState = ContactDraftSaveState.saving;
      _notify();
      try {
        final saved = await _store.saveDraft(_draftInput());
        if (_disposed) {
          return;
        }
        _draft = saved ?? _draft;
        _savedRevision = savingRevision;
        _saveState = _hasUnsavedChanges
            ? ContactDraftSaveState.waiting
            : ContactDraftSaveState.saved;
        _notify();
      } catch (_) {
        if (!_disposed) {
          _saveState = ContactDraftSaveState.failed;
          _notify();
        }
        return;
      }
    }
  }

  ContactDraftInput _draftInput() => ContactDraftInput(
    draftId: _draft?.draftId,
    deviceId: _deviceId,
    appUserId: _context.appUserId,
    workspaceId: _context.workspace.id,
    projectId: _context.project.id,
    questionnaireVersionId: _context.questionnaireVersion.id,
    occurredAtUtc: _occurredAtUtc,
    occurredTimeZone: _occurredTimeZone,
    channel: _channel,
    channelDetail: _channel == ContactChannel.otherDirect
        ? _channelDetail.trim()
        : null,
    location: _location,
    reachCount: _reachCount,
    interestLevel: _interestLevel,
    syncMode: _syncMode,
  );

  /// 保存后判断是否可离开。`false` 表示仍有失败或并发产生的未保存编辑。
  Future<bool> canLeaveAfterSave() async {
    await flushDraft();
    return !_hasUnsavedChanges;
  }

  /// 成功提交返回 `true`。失败时保留草稿和可重试状态。
  Future<bool> submit() async {
    final snapshot = state;
    if (!snapshot.canSubmit) {
      return false;
    }
    _isSubmitting = true;
    _submissionFailure = null;
    _notify();
    try {
      await _store.submitDraft(
        draftId: _draft!.draftId,
        appUserId: _context.appUserId,
        deviceId: _deviceId,
      );
      return true;
    } catch (_) {
      if (!_disposed) {
        _isSubmitting = false;
        _submissionFailure = 'contact_submission_failed';
        _notify();
      }
      return false;
    }
  }

  void _requireReady() {
    if (!state.isReady) {
      throw StateError('contact_entry_not_ready');
    }
  }

  bool _usesAutomaticNotApplicableLocation(ContactChannel channel) =>
      channel == ContactChannel.voiceCall ||
      channel == ContactChannel.videoCall ||
      channel == ContactChannel.instantText ||
      channel == ContactChannel.asynchronousMessage ||
      channel == ContactChannel.otherDirect ||
      channel == ContactChannel.mixed;

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _saveTimer?.cancel();
    super.dispose();
  }
}
