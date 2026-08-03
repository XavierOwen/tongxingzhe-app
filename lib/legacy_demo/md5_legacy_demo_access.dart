import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../app/legacy_demo_access.dart';
import '../foundation/runtime_values.dart';
import '../models/app_user.dart';
import '../models/conversation_record.dart';

/// 仅供 `main_demo.dart` 和测试使用的 legacy Adapter。
///
/// MD5 在这里是为了读取早期 Demo schema，不是安全密码方案。正式入口没有
/// 导入本文件；切换 Supabase Auth 后可整体删除此目录。
final class Md5LegacyDemoAccess implements LegacyDemoAccess {
  Md5LegacyDemoAccess({Random? random}) : _random = random ?? Random.secure();

  final Random _random;

  @override
  Set<String> get demoUsernames => const {
    'admin1',
    'admin2',
    'admin3',
    'user1',
    'user2',
  };

  @override
  bool passwordMatches(AppUser user, String clearTextPassword) {
    return digestPassword(clearTextPassword) == user.passwordMd5;
  }

  @override
  String digestPassword(String clearTextPassword) {
    return md5.convert(utf8.encode(clearTextPassword)).toString();
  }

  @override
  String createTemporaryPassword() {
    return 'temp${100000 + _random.nextInt(900000)}';
  }

  @override
  List<AppUser> createDefaultUsers() {
    return [
      _fakeUser(
        username: 'admin1',
        displayName: 'Admin One',
        email: 'admin1@example.com',
        gender: 'male',
        occupation: 'Director',
        birthday: DateTime(1986, 4, 12),
        roleLevel: 90,
        cityNames: const ['Chicago, IL', 'New York, NY', 'Los Angeles, CA'],
        teamName: 'Org Admins',
      ),
      _fakeUser(
        username: 'admin2',
        displayName: 'Admin Two',
        email: 'admin2@example.com',
        gender: 'female',
        occupation: 'Chicago city lead',
        birthday: DateTime(1990, 9, 3),
        roleLevel: 80,
        cityNames: const ['Chicago, IL'],
        teamName: 'Chicago Admins',
      ),
      _fakeUser(
        username: 'admin3',
        displayName: 'Admin Three',
        email: 'admin3@example.com',
        gender: 'male',
        occupation: 'New York city lead',
        birthday: DateTime(1988, 1, 20),
        roleLevel: 80,
        cityNames: const ['New York, NY'],
        teamName: 'New York Admins',
      ),
      _fakeUser(
        username: 'user1',
        displayName: 'User One',
        email: 'user1@example.com',
        gender: 'female',
        occupation: 'Student',
        birthday: DateTime(2001, 6, 18),
        roleLevel: 10,
        cityNames: const ['Chicago, IL'],
        teamName: 'Chicago Team A',
      ),
      _fakeUser(
        username: 'user2',
        displayName: 'User Two',
        email: 'user2@example.com',
        gender: 'male',
        occupation: 'Engineer',
        birthday: DateTime(1997, 11, 8),
        roleLevel: 10,
        cityNames: const ['New York, NY'],
        teamName: 'New York Team A',
      ),
    ];
  }

  @override
  List<ConversationRecord> createSyntheticRecords({
    required List<AppUser> users,
    required DateTime now,
    required int seed,
    required IdGenerator idGenerator,
  }) {
    final random = Random(seed);
    final identities = [
      'student',
      'young_worker',
      'undocumented',
      'longtime_immigrant',
      'newcomer',
      'visitor',
    ];
    final places = [
      'Central Station entrance',
      'Campus gate',
      'Grocery plaza',
      'Factory bus stop',
      'Weekend market',
      'Library corner',
    ];
    final citySamples = [
      ('Chicago, IL', 'Union', 41.8781, -87.6298, 'user1'),
      ('Chicago, IL', 'IIT', 41.8349, -87.6270, 'user1'),
      ('Chicago, IL', 'UIC', 41.8719, -87.6493, 'user1'),
      ('Chicago, IL', 'Chinatown', 41.8526, -87.6321, 'admin2'),
      ('New York, NY', 'Campus', 40.7128, -74.0060, 'user2'),
      ('Los Angeles, CA', 'Downtown', 34.0522, -118.2437, 'admin1'),
    ];
    final records = <ConversationRecord>[];

    for (var i = 0; i < 30; i++) {
      final hourOffset = i % 9;
      final city = citySamples[i % citySamples.length];
      final collector = users.firstWhere(
        (user) => user.username == city.$5,
        orElse: () => users.first,
      );
      records.add(
        ConversationRecord(
          id: 'demo-${idGenerator.next()}',
          createdAt: DateTime(
            now.year,
            now.month,
            now.day - (i ~/ 8),
            8 + hourOffset,
            (i * 11) % 60,
          ),
          collectorUserId: collector.userId,
          cityName: city.$1,
          areaName: city.$2,
          teamName: collector.teamName,
          recorderName: collector.displayName,
          personName: i % 3 == 0 ? 'Demo Person $i' : '',
          englishName: i % 3 == 1 ? 'Demo English $i' : '',
          averageHeartRate: i % 4 == 0
              ? 72 + random.nextInt(18).toDouble()
              : null,
          latitude: city.$3 + random.nextDouble() / 100,
          longitude: city.$4 - random.nextDouble() / 100,
          locationAccuracyMeters: 15 + random.nextInt(120).toDouble(),
          manualPlaceName: places[i % places.length],
          gender: i.isEven ? 'female' : 'male',
          identity: identities[i % identities.length],
          ageRange: i % 3 == 0 ? '18_25' : '26_40',
          relationshipLevel: (i % 4) + 1,
          interestLevel: i % 5,
          contacts: i % 4 == 0
              ? [
                  ConversationContact(
                    channel: 'wechat',
                    value: 'demo-contact-$i',
                  ),
                ]
              : const [],
          attitudeLevel: (i % 5) - 2,
          notes: 'Synthetic demo record',
          isLocationVerified: i % 6 != 0,
        ),
      );
    }

    return records;
  }

  AppUser _fakeUser({
    required String username,
    required String displayName,
    required String email,
    required String gender,
    required String occupation,
    required DateTime birthday,
    required int roleLevel,
    required List<String> cityNames,
    required String teamName,
  }) {
    return AppUser(
      userId: 'seed-$username',
      username: username,
      displayName: displayName,
      email: email,
      phone: '555-010-${username.substring(username.length - 1)}',
      birthday: birthday,
      gender: gender,
      occupation: occupation,
      contactJson: jsonEncode({'email': email, 'phone': '555-0100'}),
      roleLevel: roleLevel,
      cityNames: cityNames,
      teamName: teamName,
      passwordMd5: digestPassword(username),
      status: 'active',
      failedLoginCount: 0,
      mustChangePassword: false,
    );
  }
}
