// Public constructor arguments intentionally differ from private field names.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../app_session/session_context_gateway.dart';
import '../foundation/runtime_values.dart';
import '../targets/promotion_target.dart';

const _offlineAuthorizationWindow = Duration(hours: 72);
const _clockRollbackTolerance = Duration(minutes: 5);

abstract interface class SecureValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

enum OfflinePiiLockReason {
  refreshing,
  unauthorized,
  signedOut,
  contextChanged,
  expired,
  clockRollback,
  installationChanged,
  corrupt,
  storageFailure,
}

final class OfflinePiiLock {
  const OfflinePiiLock({required this.reason, required this.lockedAtUtc});

  final OfflinePiiLockReason reason;
  final DateTime lockedAtUtc;
}

abstract interface class OfflinePiiLockStore {
  Future<OfflinePiiLock?> read(String scopeKey);

  Future<void> write(String scopeKey, OfflinePiiLock lock);

  Future<void> clear(String scopeKey);
}

final class OfflinePiiSnapshot {
  const OfflinePiiSnapshot({
    required this.context,
    required this.assignedTargets,
    required this.authorizedAtUtc,
    required this.expiresAtUtc,
  });

  final TrustedSessionContext context;
  final List<PromotionTargetProfile> assignedTargets;
  final DateTime authorizedAtUtc;
  final DateTime expiresAtUtc;
}

sealed class OfflinePiiReadResult {
  const OfflinePiiReadResult();
}

final class OfflinePiiAvailable extends OfflinePiiReadResult {
  const OfflinePiiAvailable(this.snapshot);

  final OfflinePiiSnapshot snapshot;
}

final class OfflinePiiEmpty extends OfflinePiiReadResult {
  const OfflinePiiEmpty();
}

final class OfflinePiiLocked extends OfflinePiiReadResult {
  const OfflinePiiLocked(this.reason);

  final OfflinePiiLockReason reason;
}

final class OfflinePiiUnavailable extends OfflinePiiReadResult {
  const OfflinePiiUnavailable();
}

sealed class OfflinePiiSaveResult {
  const OfflinePiiSaveResult();
}

final class OfflinePiiSaved extends OfflinePiiSaveResult {
  const OfflinePiiSaved();
}

final class OfflinePiiSaveFailed extends OfflinePiiSaveResult {
  const OfflinePiiSaveFailed();
}

final class OfflinePiiStaleRefreshIgnored extends OfflinePiiSaveResult {
  const OfflinePiiStaleRefreshIgnored();
}

enum OfflinePiiDeletionResult { deleted, pending, notLocked }

/// 受平台安全存储保护的最小离线跟进资料。
///
/// 普通本地数据库只保存不含 PII 的锁定状态。任何清除或高水位写入失败都会
/// 先锁定 scope，后续读取不能绕过该锁。
final class OfflinePiiVault {
  OfflinePiiVault({
    required SecureValueStore secureStore,
    required OfflinePiiLockStore lockStore,
    required AppClock clock,
    required String installationId,
  }) : _secureStore = secureStore,
       _lockStore = lockStore,
       _clock = clock,
       _installationId = installationId;

  final SecureValueStore _secureStore;
  final OfflinePiiLockStore _lockStore;
  final AppClock _clock;
  final String _installationId;
  final Map<String, Future<void>> _operationQueues = {};

  Future<OfflinePiiSaveResult> replace({
    required String externalSubject,
    required TrustedSessionContext context,
    required List<PromotionTargetProfile> assignedTargets,
    required DateTime authorizedAtUtc,
  }) {
    final scopeKey = _scopeKey(externalSubject);
    return _serialize(
      scopeKey,
      () => _replace(
        scopeKey: scopeKey,
        context: context,
        assignedTargets: assignedTargets,
        authorizedAtUtc: authorizedAtUtc.toUtc(),
      ),
    );
  }

  Future<OfflinePiiSaveResult> _replace({
    required String scopeKey,
    required TrustedSessionContext context,
    required List<PromotionTargetProfile> assignedTargets,
    required DateTime authorizedAtUtc,
  }) async {
    final now = _clock.now().toUtc();
    try {
      final existingValue = await _secureStore.read(_secureKey(scopeKey));
      if (existingValue != null) {
        try {
          final existing = _decodeEnvelope(jsonDecode(existingValue));
          if (existing.authorizedAtUtc.isAfter(authorizedAtUtc)) {
            return const OfflinePiiStaleRefreshIgnored();
          }
        } on Object {
          // 一次新的在线验权可以替换损坏的旧密文，但在完成前仍保持锁定。
        }
      }
      await _lockStore.write(
        scopeKey,
        OfflinePiiLock(
          reason: OfflinePiiLockReason.refreshing,
          lockedAtUtc: now,
        ),
      );
      await _secureStore.write(
        _secureKey(scopeKey),
        jsonEncode(
          _encodeEnvelope(
            installationId: _installationId,
            context: context,
            targets: assignedTargets,
            authorizedAtUtc: authorizedAtUtc,
            lastObservedAtUtc: now,
          ),
        ),
      );
      await _lockStore.clear(scopeKey);
      return const OfflinePiiSaved();
    } on Object {
      try {
        await _lockAndDelete(scopeKey, OfflinePiiLockReason.storageFailure);
      } on Object {
        // 两种存储同时不可用时，调用方只得到失败，不能把旧快照当成已刷新。
      }
      return const OfflinePiiSaveFailed();
    }
  }

  Future<T> _serialize<T>(String scopeKey, Future<T> Function() operation) {
    final result = Completer<T>();
    final previous = _operationQueues[scopeKey] ?? Future<void>.value();
    late final Future<void> current;
    current = previous
        .then((_) async {
          try {
            result.complete(await operation());
          } on Object catch (error, stackTrace) {
            result.completeError(error, stackTrace);
          }
        })
        .whenComplete(() {
          if (identical(_operationQueues[scopeKey], current)) {
            _operationQueues.remove(scopeKey);
          }
        });
    _operationQueues[scopeKey] = current;
    return result.future;
  }

  Future<OfflinePiiReadResult> read(String externalSubject) {
    final scopeKey = _scopeKey(externalSubject);
    return _serialize(scopeKey, () => _read(scopeKey));
  }

  Future<OfflinePiiReadResult> _read(String scopeKey) async {
    try {
      final lock = await _lockStore.read(scopeKey);
      if (lock != null) return OfflinePiiLocked(lock.reason);
      late final String? encoded;
      try {
        encoded = await _secureStore.read(_secureKey(scopeKey));
      } on Object {
        return _lockAndDelete(scopeKey, OfflinePiiLockReason.storageFailure);
      }
      if (encoded == null) return const OfflinePiiEmpty();
      late final _Envelope envelope;
      try {
        envelope = _decodeEnvelope(jsonDecode(encoded));
      } on Object {
        return _lockAndDelete(scopeKey, OfflinePiiLockReason.corrupt);
      }
      if (envelope.installationId != _installationId) {
        return _lockAndDelete(
          scopeKey,
          OfflinePiiLockReason.installationChanged,
        );
      }
      final now = _clock.now().toUtc();
      final toleratedNow = now.add(_clockRollbackTolerance);
      if (toleratedNow.isBefore(envelope.authorizedAtUtc) ||
          toleratedNow.isBefore(envelope.lastObservedAtUtc)) {
        return _lockAndDelete(scopeKey, OfflinePiiLockReason.clockRollback);
      }
      if (!now.isBefore(
        envelope.authorizedAtUtc.add(_offlineAuthorizationWindow),
      )) {
        return _lockAndDelete(scopeKey, OfflinePiiLockReason.expired);
      }
      try {
        await _secureStore.write(
          _secureKey(scopeKey),
          jsonEncode(envelope.encode(lastObservedAtUtc: now)),
        );
      } on Object {
        return _lockAndDelete(scopeKey, OfflinePiiLockReason.storageFailure);
      }
      return OfflinePiiAvailable(
        OfflinePiiSnapshot(
          context: envelope.context,
          assignedTargets: envelope.targets,
          authorizedAtUtc: envelope.authorizedAtUtc,
          expiresAtUtc: envelope.authorizedAtUtc.add(
            _offlineAuthorizationWindow,
          ),
        ),
      );
    } on Object {
      return const OfflinePiiUnavailable();
    }
  }

  Future<OfflinePiiDeletionResult> revoke(
    String externalSubject,
    OfflinePiiLockReason reason,
  ) {
    final scopeKey = _scopeKey(externalSubject);
    return _serialize(scopeKey, () => _revoke(scopeKey, reason));
  }

  Future<OfflinePiiDeletionResult> _revoke(
    String scopeKey,
    OfflinePiiLockReason reason,
  ) async {
    await _lockStore.write(
      scopeKey,
      OfflinePiiLock(reason: reason, lockedAtUtc: _clock.now().toUtc()),
    );
    return _deleteSecureValue(scopeKey);
  }

  Future<OfflinePiiDeletionResult> retryLockedDeletion(String externalSubject) {
    final scopeKey = _scopeKey(externalSubject);
    return _serialize(scopeKey, () => _retryLockedDeletion(scopeKey));
  }

  Future<OfflinePiiDeletionResult> _retryLockedDeletion(String scopeKey) async {
    if (await _lockStore.read(scopeKey) == null) {
      return OfflinePiiDeletionResult.notLocked;
    }
    return _deleteSecureValue(scopeKey);
  }

  Future<OfflinePiiLocked> _lockAndDelete(
    String scopeKey,
    OfflinePiiLockReason reason,
  ) async {
    await _lockStore.write(
      scopeKey,
      OfflinePiiLock(reason: reason, lockedAtUtc: _clock.now().toUtc()),
    );
    await _deleteSecureValue(scopeKey);
    return OfflinePiiLocked(reason);
  }

  Future<OfflinePiiDeletionResult> _deleteSecureValue(String scopeKey) async {
    try {
      await _secureStore.delete(_secureKey(scopeKey));
      return OfflinePiiDeletionResult.deleted;
    } on Object {
      // 锁已先持久化。删除失败时仍不可读取，后续联网或启动流程可以重试。
      return OfflinePiiDeletionResult.pending;
    }
  }

  String _scopeKey(String externalSubject) {
    final normalized = externalSubject.trim();
    if (normalized.isEmpty) throw ArgumentError.value(externalSubject);
    return sha256.convert(utf8.encode(normalized)).toString();
  }

  String _secureKey(String scopeKey) => 'tongxingzhe.offline-pii.v1.$scopeKey';
}

Map<String, Object?> _encodeEnvelope({
  required String installationId,
  required TrustedSessionContext context,
  required List<PromotionTargetProfile> targets,
  required DateTime authorizedAtUtc,
  required DateTime lastObservedAtUtc,
}) => {
  'version': 1,
  'installation_id': installationId,
  'authorized_at_utc': authorizedAtUtc.toIso8601String(),
  'last_observed_at_utc': lastObservedAtUtc.toIso8601String(),
  'context': _encodeContext(context),
  'assigned_targets': targets.map(_encodeTarget).toList(),
};

Map<String, Object?> _encodeContext(TrustedSessionContext context) => {
  'app_user_id': context.appUserId,
  'workspace': {
    'id': context.workspace.id,
    'kind': context.workspace.kind.name,
    'name': context.workspace.name,
  },
  'project': {'id': context.project.id, 'name': context.project.name},
  'questionnaire_version': {
    'id': context.questionnaireVersion.id,
    'version_number': context.questionnaireVersion.versionNumber,
  },
  'capabilities': context.capabilities.toList()..sort(),
};

Map<String, Object?> _encodeTarget(PromotionTargetProfile target) => {
  'id': target.id,
  'type': target.type.storageValue,
  'display_name': target.displayName,
  'phone': target.phone,
  'email': target.email,
  'created_at_utc': target.createdAtUtc.toUtc().toIso8601String(),
  'has_current_project_relationship': target.hasCurrentProjectRelationship,
  'project_relationship': target.projectRelationship == null
      ? null
      : _encodeRelationship(target.projectRelationship!),
};

Map<String, Object?> _encodeRelationship(
  PromotionTargetRelationship relationship,
) => {
  'target_id': relationship.targetId,
  'project_id': relationship.projectId,
  'stage': relationship.stage,
  'display_stage': relationship.displayStage,
  'lifecycle_status': relationship.lifecycleStatus.storageValue,
  'follow_up_note': relationship.followUpNote,
  'revision_number': relationship.revisionNumber,
  'updated_at_utc': relationship.updatedAtUtc.toUtc().toIso8601String(),
  'stage_aliases': relationship.stageAliases
      .map(
        (alias) => {
          'stage': alias.stage,
          'display_stage': alias.displayStage,
          'display_name': alias.displayName,
        },
      )
      .toList(),
  'history': relationship.history
      .map(
        (revision) => {
          'revision_number': revision.revisionNumber,
          'old_stage': revision.oldStage,
          'new_stage': revision.newStage,
          'old_lifecycle_status': revision.oldLifecycleStatus?.storageValue,
          'new_lifecycle_status': revision.newLifecycleStatus.storageValue,
          'follow_up_note': revision.followUpNote,
          'changed_fields': revision.changedFields,
          'reason_code': revision.reasonCode,
          'reason_detail': revision.reasonDetail,
          'changed_by_app_user_id': revision.changedByAppUserId,
          'changed_at_utc': revision.changedAtUtc.toUtc().toIso8601String(),
        },
      )
      .toList(),
};

final class _Envelope {
  const _Envelope({
    required this.installationId,
    required this.context,
    required this.targets,
    required this.authorizedAtUtc,
    required this.lastObservedAtUtc,
  });

  final String installationId;
  final TrustedSessionContext context;
  final List<PromotionTargetProfile> targets;
  final DateTime authorizedAtUtc;
  final DateTime lastObservedAtUtc;

  Map<String, Object?> encode({required DateTime lastObservedAtUtc}) =>
      _encodeEnvelope(
        installationId: installationId,
        context: context,
        targets: targets,
        authorizedAtUtc: authorizedAtUtc,
        lastObservedAtUtc: lastObservedAtUtc,
      );
}

_Envelope _decodeEnvelope(Object? value) {
  final root = _object(value);
  if (_integer(root['version']) != 1) throw const FormatException('version');
  final targets = _list(root['assigned_targets']).map(_decodeTarget).toList();
  if (targets.map((target) => target.id).toSet().length != targets.length) {
    throw const FormatException('duplicate target');
  }
  return _Envelope(
    installationId: _string(root['installation_id']),
    context: _decodeContext(root['context']),
    targets: targets,
    authorizedAtUtc: _date(root['authorized_at_utc']),
    lastObservedAtUtc: _date(root['last_observed_at_utc']),
  );
}

TrustedSessionContext _decodeContext(Object? value) {
  final root = _object(value);
  final workspace = _object(root['workspace']);
  final project = _object(root['project']);
  final questionnaire = _object(root['questionnaire_version']);
  return TrustedSessionContext(
    appUserId: _string(root['app_user_id']),
    workspace: WorkspaceContext(
      id: _string(workspace['id']),
      kind: switch (_string(workspace['kind'])) {
        'personal' => WorkspaceKind.personal,
        'organization' => WorkspaceKind.organization,
        _ => throw const FormatException('workspace kind'),
      },
      name: _string(workspace['name']),
    ),
    project: ProjectContext(
      id: _string(project['id']),
      name: _string(project['name']),
    ),
    questionnaireVersion: QuestionnaireVersionContext(
      id: _string(questionnaire['id']),
      versionNumber: _integer(questionnaire['version_number']),
    ),
    capabilities: Set.unmodifiable(_list(root['capabilities']).map(_string)),
  );
}

PromotionTargetProfile _decodeTarget(Object? value) {
  final root = _object(value);
  return PromotionTargetProfile(
    id: _string(root['id']),
    type: switch (_string(root['type'])) {
      'person' => PromotionTargetType.person,
      'institution' => PromotionTargetType.institution,
      _ => throw const FormatException('target type'),
    },
    displayName: _string(root['display_name']),
    phone: _nullableString(root['phone']),
    email: _nullableString(root['email']),
    createdAtUtc: _date(root['created_at_utc']),
    hasCurrentProjectRelationship: _boolean(
      root['has_current_project_relationship'],
    ),
    projectRelationship: root['project_relationship'] == null
        ? null
        : _decodeRelationship(root['project_relationship']),
  );
}

PromotionTargetRelationship _decodeRelationship(Object? value) {
  final root = _object(value);
  return PromotionTargetRelationship(
    targetId: _string(root['target_id']),
    projectId: _string(root['project_id']),
    stage: _boundedInteger(root['stage'], 0, 4),
    displayStage: _boundedInteger(root['display_stage'], 0, 8),
    lifecycleStatus: _lifecycle(root['lifecycle_status']),
    followUpNote: _nullableString(root['follow_up_note']),
    revisionNumber: _integer(root['revision_number']),
    updatedAtUtc: _date(root['updated_at_utc']),
    stageAliases: _list(root['stage_aliases']).map((value) {
      final alias = _object(value);
      return PromotionTargetStageAlias(
        stage: _boundedInteger(alias['stage'], 0, 4),
        displayStage: _boundedInteger(alias['display_stage'], 0, 8),
        displayName: _nullableString(alias['display_name']),
      );
    }).toList(),
    history: _list(root['history']).map(_decodeRelationshipRevision).toList(),
  );
}

PromotionTargetRelationshipRevision _decodeRelationshipRevision(Object? value) {
  final root = _object(value);
  return PromotionTargetRelationshipRevision(
    revisionNumber: _integer(root['revision_number']),
    oldStage: root['old_stage'] == null
        ? null
        : _boundedInteger(root['old_stage'], 0, 4),
    newStage: _boundedInteger(root['new_stage'], 0, 4),
    oldLifecycleStatus: root['old_lifecycle_status'] == null
        ? null
        : _lifecycle(root['old_lifecycle_status']),
    newLifecycleStatus: _lifecycle(root['new_lifecycle_status']),
    followUpNote: _nullableString(root['follow_up_note']),
    changedFields: _list(root['changed_fields']).map(_string).toList(),
    reasonCode: _string(root['reason_code']),
    reasonDetail: _nullableString(root['reason_detail']),
    changedByAppUserId: _string(root['changed_by_app_user_id']),
    changedAtUtc: _date(root['changed_at_utc']),
  );
}

PromotionTargetRelationshipLifecycle _lifecycle(Object? value) =>
    switch (_string(value)) {
      'active' => PromotionTargetRelationshipLifecycle.active,
      'paused' => PromotionTargetRelationshipLifecycle.paused,
      'ended' => PromotionTargetRelationshipLifecycle.ended,
      _ => throw const FormatException('relationship lifecycle'),
    };

Map<String, Object?> _object(Object? value) =>
    value is Map<String, Object?> ? value : throw const FormatException();

List<Object?> _list(Object? value) =>
    value is List<Object?> ? value : throw const FormatException();

String _string(Object? value) =>
    value is String && value.isNotEmpty ? value : throw const FormatException();

String? _nullableString(Object? value) => value == null ? null : _string(value);

int _integer(Object? value) =>
    value is int && value >= 1 ? value : throw const FormatException();

int _boundedInteger(Object? value, int minimum, int maximum) =>
    value is int && value >= minimum && value <= maximum
    ? value
    : throw const FormatException();

bool _boolean(Object? value) =>
    value is bool ? value : throw const FormatException();

DateTime _date(Object? value) => DateTime.parse(_string(value)).toUtc();
