import '../models/app_user.dart';
import '../models/conversation_record.dart';
import '../foundation/runtime_values.dart';

/// legacy demo 身份与种子资料的唯一 seam。
///
/// 正式 composition root 不提供此 Adapter，因此 AppController 无法验证本地
/// 演示密码、生成默认账号或写入 synthetic records。这个接口不会演变为正式
/// `IdentitySession`；它只负责在现代认证完成前隔离可删除的旧原型。
abstract interface class LegacyDemoAccess {
  Set<String> get demoUsernames;

  List<AppUser> createDefaultUsers();

  List<ConversationRecord> createSyntheticRecords({
    required List<AppUser> users,
    required DateTime now,
    required int seed,
    required IdGenerator idGenerator,
  });

  bool passwordMatches(AppUser user, String clearTextPassword);

  String digestPassword(String clearTextPassword);

  String createTemporaryPassword();
}
