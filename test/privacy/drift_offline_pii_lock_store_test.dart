import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/app_session/session_context_gateway.dart';
import 'package:tongxingzhe_app/data/local_database.dart';
import 'package:tongxingzhe_app/foundation/runtime_values.dart';
import 'package:tongxingzhe_app/privacy/drift_offline_pii_lock_store.dart';
import 'package:tongxingzhe_app/privacy/offline_pii_vault.dart';
import 'package:tongxingzhe_app/targets/promotion_target.dart';

void main() {
  test(
    'PII-free lock survives repository reconstruction until explicitly cleared',
    () async {
      final database = LocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final first = DriftOfflinePiiLockStore(database);
      final lock = OfflinePiiLock(
        reason: OfflinePiiLockReason.unauthorized,
        lockedAtUtc: _lockedAt,
      );

      await first.write('opaque-scope-hash', lock);
      final restored = await DriftOfflinePiiLockStore(
        database,
      ).read('opaque-scope-hash');
      await first.clear('opaque-scope-hash');

      expect(restored?.reason, OfflinePiiLockReason.unauthorized);
      expect(restored?.lockedAtUtc, _lockedAt);
      expect(await first.read('opaque-scope-hash'), isNull);
    },
  );

  test('vault 的 Drift 锁不包含身份 subject 或对象 PII', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final vault = OfflinePiiVault(
      secureStore: _MemorySecureValueStore(),
      lockStore: DriftOfflinePiiLockStore(database),
      clock: const _FixedClock(),
      installationId: 'installation-1',
    );
    await vault.replace(
      externalSubject: 'external-subject-sensitive',
      context: _context,
      assignedTargets: [_target],
      authorizedAtUtc: _lockedAt,
    );

    await vault.revoke(
      'external-subject-sensitive',
      OfflinePiiLockReason.unauthorized,
    );
    final rows = await database.select(database.dbAppSettings).get();
    final driftText = rows.map((row) => '${row.key}\n${row.value}').join('\n');

    expect(rows, hasLength(1));
    expect(driftText, isNot(contains('external-subject-sensitive')));
    expect(driftText, isNot(contains('王小明')));
    expect(driftText, isNot(contains('+1 555 0100')));
    expect(driftText, isNot(contains('assigned@example.test')));
    expect(driftText, contains('unauthorized'));
  });
}

final _lockedAt = DateTime.utc(2026, 8, 6, 12);

const _context = TrustedSessionContext(
  appUserId: '11111111-1111-4111-8111-111111111111',
  workspace: WorkspaceContext(
    id: '22222222-2222-4222-8222-222222222222',
    kind: WorkspaceKind.personal,
    name: '个人空间',
  ),
  project: ProjectContext(
    id: '33333333-3333-4333-8333-333333333333',
    name: '校园推广',
  ),
  questionnaireVersion: QuestionnaireVersionContext(
    id: '44444444-4444-4444-8444-444444444444',
    versionNumber: 1,
  ),
  capabilities: {'view_assigned_target_pii'},
);

final _target = PromotionTargetProfile(
  id: 'target-1',
  type: PromotionTargetType.person,
  displayName: '王小明',
  phone: '+1 555 0100',
  email: 'assigned@example.test',
  createdAtUtc: DateTime.utc(2026, 8, 1),
);

final class _FixedClock implements AppClock {
  const _FixedClock();

  @override
  DateTime now() => DateTime.utc(2026, 8, 6, 13);
}

final class _MemorySecureValueStore implements SecureValueStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
