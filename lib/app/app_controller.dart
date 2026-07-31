import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/material.dart';

import '../data/local_database.dart';
import '../foundation/runtime_values.dart';
import '../models/app_user.dart';
import '../models/conversation_record.dart';
import 'legacy_demo_access.dart';

class AppController extends ChangeNotifier {
  factory AppController({
    required LocalDatabase database,
    required AppClock clock,
    required IdGenerator idGenerator,
    LegacyDemoAccess? legacyDemoAccess,
  }) {
    return AppController._(database, clock, idGenerator, legacyDemoAccess);
  }

  AppController._(
    this._db,
    this._clock,
    this._idGenerator,
    this._legacyDemoAccess,
  );

  static const _maxFailedLogins = 4;
  static const _lockDuration = Duration(days: 30);
  final LocalDatabase _db;
  final AppClock _clock;
  final IdGenerator _idGenerator;
  final LegacyDemoAccess? _legacyDemoAccess;
  final List<ConversationRecord> _records = [];
  final List<AppUser> _users = [];

  String localeCode = 'zh';
  ThemeMode themeMode = ThemeMode.system;
  String cityName = 'Chicago, IL';
  String areaName = 'IIT';
  String teamName = 'Default Team';
  String recorderName = '';
  bool adminMode = false;
  AppUser? currentUser;

  List<AppUser> get users => List.unmodifiable(_users);

  bool get isLoggedIn => currentUser != null;
  bool get legacyDemoEnabled => _legacyDemoAccess != null;
  bool get canUseAdminMode => currentUser?.isCityAdmin == true;
  List<String> get availableAreas => areasForCity(cityName);

  List<ConversationRecord> get records {
    final sorted = List<ConversationRecord>.from(_records)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted;
  }

  /// 让旧 UI 也通过统一 Clock 取得当前时间；现代 Feature 会把时间放进其深模块。
  DateTime now() => _clock.now();

  /// legacy 记录临时使用的不透明 ID；正式接触 ID 将由 ContactJournal 创建。
  String nextLegacyRecordId() => 'legacy-${_idGenerator.next()}';

  List<ConversationRecord> get visibleRecords {
    final user = currentUser;
    if (user == null) {
      return const [];
    }
    return records.where((record) => _canCurrentUserSeeRecord(record)).toList();
  }

  List<ConversationRecord> get recordsNeedingReview {
    return visibleRecords
        .where((record) => record.needsLocationReview)
        .toList();
  }

  Future<void> load() async {
    await _loadUsers();
    if (legacyDemoEnabled) {
      await _ensureDefaultUsersExist();
    }
    await _loadSettings();
    await _loadRecords();
    if (legacyDemoEnabled) {
      await _ensureSeedData();
    }
  }

  @override
  void dispose() {
    _db.close();
    super.dispose();
  }

  Future<AuthResult> login(String username, String password) async {
    final legacyDemo = _legacyDemoAccess;
    if (legacyDemo == null) {
      return const AuthResult(
        success: false,
        messageKey: 'authUnavailableInProduction',
      );
    }
    final normalizedUsername = username.trim();
    final index = _users.indexWhere(
      (user) => user.username.toLowerCase() == normalizedUsername.toLowerCase(),
    );
    if (index == -1) {
      await _logSecurityEvent(null, 'login_unknown_user', {
        'username': normalizedUsername,
      });
      return const AuthResult(success: false, messageKey: 'authInvalid');
    }

    final now = _clock.now();
    var user = _users[index];
    if (!user.isActive) {
      return const AuthResult(success: false, messageKey: 'authInactive');
    }
    if (user.lockedUntil != null && user.lockedUntil!.isAfter(now)) {
      await _logSecurityEvent(user.userId, 'login_locked', {
        'lockedUntil': user.lockedUntil!.toIso8601String(),
      });
      return AuthResult(
        success: false,
        messageKey: 'authLocked',
        lockedUntil: user.lockedUntil,
      );
    }

    // Demo only: this simulates the app sending an MD5 password digest to a
    // cloud API, then the cloud comparing it with the stored digest.
    if (!legacyDemo.passwordMatches(user, password)) {
      final failedCount = user.failedLoginCount + 1;
      final lockedUntil = failedCount >= _maxFailedLogins
          ? now.add(_lockDuration)
          : null;
      user = user.copyWith(
        failedLoginCount: failedCount,
        lockedUntil: lockedUntil,
        lastFailedLoginAt: now,
      );
      _users[index] = user;
      await _upsertUser(user);
      await _logSecurityEvent(user.userId, 'login_failed', {
        'failedLoginCount': failedCount,
        'lockedUntil': lockedUntil?.toIso8601String(),
      });
      notifyListeners();
      return AuthResult(
        success: false,
        messageKey: lockedUntil == null ? 'authInvalid' : 'authLockedNow',
        lockedUntil: lockedUntil,
      );
    }

    user = user.copyWith(
      failedLoginCount: 0,
      clearLockedUntil: true,
      clearLastFailedLoginAt: true,
      lastSeenAt: now,
    );
    _users[index] = user;
    currentUser = user;
    cityName = user.primaryCity;
    areaName = _defaultAreaForCity(cityName);
    teamName = user.teamName;
    recorderName = user.displayName;
    adminMode = user.isCityAdmin;
    await _upsertUser(user);
    await _logSecurityEvent(user.userId, 'login_success', {});
    notifyListeners();
    await _saveSettings();
    return AuthResult(success: true, messageKey: 'authLoggedIn', user: user);
  }

  Future<AuthResult> loginDemoAccount(String username) async {
    final legacyDemo = _legacyDemoAccess;
    if (legacyDemo == null) {
      return const AuthResult(
        success: false,
        messageKey: 'authUnavailableInProduction',
      );
    }
    final normalizedUsername = username.trim();

    // Demo-only helper: these seeded accounts exist so the prototype can be
    // explored quickly. Resetting their local lock keeps accidental test taps
    // from making the demo unusable for a month.
    if (legacyDemo.demoUsernames.contains(normalizedUsername)) {
      final index = _users.indexWhere(
        (user) =>
            user.username.toLowerCase() == normalizedUsername.toLowerCase(),
      );
      if (index != -1) {
        final unlocked = _users[index].copyWith(
          failedLoginCount: 0,
          clearLockedUntil: true,
          clearLastFailedLoginAt: true,
        );
        _users[index] = unlocked;
        await _upsertUser(unlocked);
      }
    }

    return login(normalizedUsername, normalizedUsername);
  }

  Future<void> logout() async {
    currentUser = null;
    adminMode = false;
    notifyListeners();
    await _saveSettings();
  }

  Future<AuthResult> registerUser({
    required String username,
    required String displayName,
    required String email,
    required String phone,
    required String city,
    required String password,
  }) async {
    final legacyDemo = _legacyDemoAccess;
    if (legacyDemo == null) {
      return const AuthResult(
        success: false,
        messageKey: 'authUnavailableInProduction',
      );
    }
    final trimmedUsername = username.trim();
    if (trimmedUsername.isEmpty || password.isEmpty || email.trim().isEmpty) {
      return const AuthResult(success: false, messageKey: 'authMissingFields');
    }
    final exists = _users.any(
      (user) => user.username.toLowerCase() == trimmedUsername.toLowerCase(),
    );
    if (exists) {
      return const AuthResult(success: false, messageKey: 'authUserExists');
    }

    final now = _clock.now();
    final user = AppUser(
      userId: 'user-${_idGenerator.next()}',
      username: trimmedUsername,
      displayName: displayName.trim().isEmpty
          ? trimmedUsername
          : displayName.trim(),
      email: email.trim(),
      phone: phone.trim(),
      roleLevel: 10,
      cityNames: [city.trim().isEmpty ? 'Chicago, IL' : city.trim()],
      gender: 'unknown',
      occupation: '',
      contactJson: '{}',
      teamName: 'New Team',
      passwordMd5: legacyDemo.digestPassword(password),
      status: 'active',
      failedLoginCount: 0,
      mustChangePassword: false,
      lastSeenAt: now,
    );
    _users.add(user);
    currentUser = user;
    cityName = user.primaryCity;
    areaName = _defaultAreaForCity(cityName);
    teamName = user.teamName;
    recorderName = user.displayName;
    adminMode = false;
    await _upsertUser(user);
    await _logSecurityEvent(user.userId, 'register_user', {});
    notifyListeners();
    await _saveSettings();
    return AuthResult(success: true, messageKey: 'authRegistered', user: user);
  }

  Future<AuthResult> requestPasswordReset({
    required String displayName,
    required String email,
  }) async {
    final legacyDemo = _legacyDemoAccess;
    if (legacyDemo == null) {
      return const AuthResult(
        success: false,
        messageKey: 'authUnavailableInProduction',
      );
    }
    final index = _users.indexWhere((user) {
      return user.displayName.toLowerCase() ==
              displayName.trim().toLowerCase() &&
          user.email.toLowerCase() == email.trim().toLowerCase();
    });
    if (index == -1) {
      await _logSecurityEvent(null, 'password_reset_not_found', {
        'displayName': displayName.trim(),
        'email': email.trim(),
      });
      return const AuthResult(success: false, messageKey: 'authResetNotFound');
    }

    final temporaryPassword = legacyDemo.createTemporaryPassword();
    final updated = _users[index].copyWith(
      passwordMd5: legacyDemo.digestPassword(temporaryPassword),
      failedLoginCount: 0,
      clearLockedUntil: true,
      clearLastFailedLoginAt: true,
      mustChangePassword: true,
    );
    _users[index] = updated;
    await _upsertUser(updated);
    await _logSecurityEvent(updated.userId, 'password_reset', {});
    notifyListeners();
    return AuthResult(
      success: true,
      messageKey: 'authTempPasswordGenerated',
      temporaryPassword: temporaryPassword,
      user: updated,
    );
  }

  Future<AuthResult> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final legacyDemo = _legacyDemoAccess;
    if (legacyDemo == null) {
      return const AuthResult(
        success: false,
        messageKey: 'authUnavailableInProduction',
      );
    }
    final user = currentUser;
    if (user == null) {
      return const AuthResult(success: false, messageKey: 'authLoginRequired');
    }
    if (newPassword.trim().length < 4) {
      return const AuthResult(success: false, messageKey: 'authPasswordShort');
    }
    if (!legacyDemo.passwordMatches(user, currentPassword)) {
      await _logSecurityEvent(user.userId, 'change_password_failed', {});
      return const AuthResult(success: false, messageKey: 'authCurrentWrong');
    }
    final index = _users.indexWhere((item) => item.userId == user.userId);
    if (index == -1) {
      return const AuthResult(success: false, messageKey: 'authLoginRequired');
    }
    final updated = user.copyWith(
      passwordMd5: legacyDemo.digestPassword(newPassword),
      mustChangePassword: false,
      failedLoginCount: 0,
      clearLockedUntil: true,
      clearLastFailedLoginAt: true,
    );
    _users[index] = updated;
    currentUser = updated;
    await _upsertUser(updated);
    await _logSecurityEvent(user.userId, 'change_password_success', {});
    notifyListeners();
    return const AuthResult(success: true, messageKey: 'authPasswordChanged');
  }

  Future<void> setLocale(String value) async {
    localeCode = value;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setThemeMode(ThemeMode value) async {
    themeMode = value;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setCityName(String value) async {
    cityName = value.trim().isEmpty ? cityName : value.trim();
    if (!areasForCity(cityName).contains(areaName)) {
      areaName = _defaultAreaForCity(cityName);
    }
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setAreaName(String value) async {
    areaName = value.trim().isEmpty ? areaName : value.trim();
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setTeamName(String value) async {
    teamName = value.trim();
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setRecorderName(String value) async {
    recorderName = value.trim();
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setAdminMode(bool value) async {
    adminMode = canUseAdminMode && value;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> addRecord(ConversationRecord record) async {
    _records.add(record);
    notifyListeners();
    await _upsertRecord(record);
  }

  Future<void> updateRecord(ConversationRecord updated) async {
    final index = _records.indexWhere((record) => record.id == updated.id);
    if (index == -1) {
      return;
    }
    _records[index] = updated;
    notifyListeners();
    await _upsertRecord(updated);
  }

  Future<void> deleteRecord(String id) async {
    _records.removeWhere((record) => record.id == id);
    notifyListeners();
    await _deleteRecordFromDatabase(id);
  }

  Future<void> clearRecords() async {
    _records.clear();
    notifyListeners();
    await _db.transaction(() async {
      await _db.delete(_db.dbRecordContacts).go();
      await _db.delete(_db.dbConversationRecords).go();
    });
  }

  Future<void> addDemoData() async {
    final legacyDemo = _legacyDemoAccess;
    if (legacyDemo == null) {
      return;
    }
    final now = _clock.now();
    final records = legacyDemo.createSyntheticRecords(
      users: _users,
      now: now,
      seed: now.microsecondsSinceEpoch,
      idGenerator: _idGenerator,
    );
    _records.addAll(records);
    notifyListeners();
    await _insertRecords(records);
  }

  String buildAnonymousSummary() {
    final byHour = <String, int>{};
    final byIdentity = <String, int>{};
    final byRelationship = <String, int>{};
    final byInterest = <String, int>{};
    final byArea = <String, int>{};
    final byCity = <String, int>{};
    final byAttitude = <String, int>{};
    var highInterest = 0;
    var rejected = 0;
    var contactCount = 0;
    var reviewCount = 0;

    for (final record in visibleRecords) {
      final hour = record.createdAt.hour.toString().padLeft(2, '0');
      byHour[hour] = (byHour[hour] ?? 0) + 1;
      byIdentity[record.identity] = (byIdentity[record.identity] ?? 0) + 1;
      byRelationship[record.relationshipKey] =
          (byRelationship[record.relationshipKey] ?? 0) + 1;
      byInterest[record.interestKey] =
          (byInterest[record.interestKey] ?? 0) + 1;
      byArea[record.areaName] = (byArea[record.areaName] ?? 0) + 1;
      byCity[record.cityName] = (byCity[record.cityName] ?? 0) + 1;
      byAttitude[record.attitudeKey] =
          (byAttitude[record.attitudeKey] ?? 0) + 1;
      if (record.interestLevel >= 3) {
        highInterest++;
      }
      if (record.interestLevel == 0) {
        rejected++;
      }
      if (record.contacts.isNotEmpty) {
        contactCount++;
      }
      if (record.needsLocationReview) {
        reviewCount++;
      }
    }

    final payload = {
      'generatedAt': _clock.now().toIso8601String(),
      'total': visibleRecords.length,
      'highInterest': highInterest,
      'rejected': rejected,
      'contactCount': contactCount,
      'locationReviewQueue': reviewCount,
      'byHour': byHour,
      'byIdentity': byIdentity,
      'byRelationship': byRelationship,
      'byInterest': byInterest,
      'byArea': byArea,
      'byCity': byCity,
      'byAttitude': byAttitude,
    };

    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(payload);
  }

  int countToday() {
    final now = _clock.now();
    return visibleRecords.where((record) {
      return record.createdAt.year == now.year &&
          record.createdAt.month == now.month &&
          record.createdAt.day == now.day;
    }).length;
  }

  int countPositiveAttitudes() {
    return visibleRecords.where((record) => record.interestLevel >= 3).length;
  }

  int countRejected() {
    return visibleRecords.where((record) => record.interestLevel == 0).length;
  }

  double? contactRate() {
    if (visibleRecords.isEmpty) {
      return null;
    }
    final withContact = visibleRecords
        .where((record) => record.contacts.isNotEmpty)
        .length;
    return withContact / visibleRecords.length;
  }

  double? averageAttitude() {
    if (visibleRecords.isEmpty) {
      return null;
    }
    final total = visibleRecords.fold<int>(
      0,
      (sum, record) => sum + record.interestLevel,
    );
    return total / visibleRecords.length;
  }

  double? averageAccuracy() {
    final values = visibleRecords
        .map((record) => record.locationAccuracyMeters)
        .whereType<double>()
        .toList();
    if (values.isEmpty) {
      return null;
    }
    return values.reduce((a, b) => a + b) / values.length;
  }

  Future<void> _loadSettings() async {
    final rows = await _db.select(_db.dbAppSettings).get();
    final settings = {for (final row in rows) row.key: row.value};
    localeCode = settings['localeCode'] ?? localeCode;
    themeMode = _themeModeFromString(settings['themeMode']);
    cityName = settings['cityName'] ?? cityName;
    areaName = settings['areaName'] ?? areaName;
    if (!areasForCity(cityName).contains(areaName)) {
      areaName = _defaultAreaForCity(cityName);
    }
    teamName = settings['teamName'] ?? teamName;
    recorderName = settings['recorderName'] ?? recorderName;
    adminMode = settings['adminMode'] == 'true';
    final currentUserId = settings['currentUserId'];
    if (currentUserId != null) {
      currentUser = _findUserById(currentUserId);
    }
    if (!canUseAdminMode) {
      adminMode = false;
    }
  }

  Future<void> _loadUsers() async {
    final rows = await _db.select(_db.dbUsers).get();
    _users
      ..clear()
      ..addAll(rows.map(_userFromRow));
  }

  Future<void> _loadRecords() async {
    final recordRows = await _db.select(_db.dbConversationRecords).get();
    final contactRows = await _db.select(_db.dbRecordContacts).get();
    final contactsByRecord = <String, List<ConversationContact>>{};
    for (final contact in contactRows) {
      contactsByRecord
          .putIfAbsent(contact.recordId, () => [])
          .add(
            ConversationContact(channel: contact.channel, value: contact.value),
          );
    }

    _records
      ..clear()
      ..addAll(
        recordRows.map(
          (row) =>
              _recordFromRow(row, contactsByRecord[row.recordId] ?? const []),
        ),
      );
  }

  Future<void> _saveSettings() async {
    final settings = {
      'localeCode': localeCode,
      'themeMode': themeMode.name,
      'cityName': cityName,
      'areaName': areaName,
      'teamName': teamName,
      'recorderName': recorderName,
      'adminMode': adminMode.toString(),
      'currentUserId': currentUser?.userId ?? '',
    };
    for (final entry in settings.entries) {
      await _db
          .into(_db.dbAppSettings)
          .insertOnConflictUpdate(
            DbAppSettingsCompanion.insert(key: entry.key, value: entry.value),
          );
    }
  }

  Future<void> _ensureSeedData() async {
    final legacyDemo = _legacyDemoAccess;
    if (legacyDemo == null) {
      return;
    }
    if (_users.isEmpty) {
      _users.addAll(legacyDemo.createDefaultUsers());
      for (final user in _users) {
        await _upsertUser(user);
      }
    } else {
      await _ensureDefaultUsersExist();
    }

    if (currentUser != null) {
      currentUser = _findUserById(currentUser!.userId);
    }
    if (!canUseAdminMode) {
      adminMode = false;
    }

    final permissionReadyRecords = _records
        .where((record) => record.collectorUserId.isNotEmpty)
        .length;
    if (_records.isEmpty || permissionReadyRecords < 10) {
      final records = legacyDemo.createSyntheticRecords(
        users: _users,
        now: _clock.now(),
        seed: 31,
        idGenerator: _idGenerator,
      );
      _records.addAll(records);
      await _insertRecords(records);
    }
  }

  bool _canCurrentUserSeeRecord(ConversationRecord record) {
    final user = currentUser;
    if (user == null) {
      return false;
    }
    if (!user.canSeeCity(record.cityName)) {
      return false;
    }
    if (user.isCityAdmin) {
      return true;
    }
    return record.collectorUserId == user.userId;
  }

  Future<void> _ensureDefaultUsersExist() async {
    final legacyDemo = _legacyDemoAccess;
    if (legacyDemo == null) {
      return;
    }
    final existingUsernames = _users.map((user) => user.username).toSet();
    for (final user in legacyDemo.createDefaultUsers()) {
      if (!existingUsernames.contains(user.username)) {
        _users.add(user);
        await _upsertUser(user);
      }
    }
  }

  AppUser? _findUserById(String userId) {
    for (final user in _users) {
      if (user.userId == userId) {
        return user;
      }
    }
    return null;
  }

  Future<void> _upsertUser(AppUser user) async {
    await _db.into(_db.dbUsers).insertOnConflictUpdate(_userToCompanion(user));
  }

  Future<void> _upsertRecord(ConversationRecord record) async {
    await _db.transaction(() async {
      await _db
          .into(_db.dbConversationRecords)
          .insertOnConflictUpdate(_recordToCompanion(record));
      await (_db.delete(
        _db.dbRecordContacts,
      )..where((table) => table.recordId.equals(record.id))).go();
      await _insertContacts(record);
    });
  }

  Future<void> _insertRecords(List<ConversationRecord> records) async {
    await _db.transaction(() async {
      for (final record in records) {
        await _db
            .into(_db.dbConversationRecords)
            .insertOnConflictUpdate(_recordToCompanion(record));
        await (_db.delete(
          _db.dbRecordContacts,
        )..where((table) => table.recordId.equals(record.id))).go();
        await _insertContacts(record);
      }
    });
  }

  Future<void> _insertContacts(ConversationRecord record) async {
    for (var i = 0; i < record.contacts.length; i++) {
      final contact = record.contacts[i];
      await _db
          .into(_db.dbRecordContacts)
          .insertOnConflictUpdate(
            DbRecordContactsCompanion.insert(
              contactId: '${record.id}-$i',
              recordId: record.id,
              channel: contact.channel,
              value: contact.value,
              createdAt: record.createdAt,
            ),
          );
    }
  }

  Future<void> _deleteRecordFromDatabase(String id) async {
    await _db.transaction(() async {
      await (_db.delete(
        _db.dbRecordContacts,
      )..where((table) => table.recordId.equals(id))).go();
      await (_db.delete(
        _db.dbConversationRecords,
      )..where((table) => table.recordId.equals(id))).go();
    });
  }

  Future<void> _logSecurityEvent(
    String? userId,
    String eventType,
    Map<String, Object?> detail,
  ) async {
    final now = _clock.now();
    await _db
        .into(_db.dbSecurityEvents)
        .insert(
          DbSecurityEventsCompanion.insert(
            eventId: 'event-${_idGenerator.next()}',
            userId: Value(userId),
            eventType: eventType,
            eventDetailJson: jsonEncode(detail),
            createdAt: now,
          ),
        );
  }

  AppUser _userFromRow(DbUser row) {
    return AppUser(
      userId: row.userId,
      username: row.username,
      displayName: row.displayName,
      email: row.email,
      phone: row.phone,
      birthday: row.birthday,
      gender: row.gender,
      occupation: row.occupation,
      contactJson: row.contactJson,
      roleLevel: row.roleLevel,
      cityNames: (jsonDecode(row.cityNamesJson) as List<dynamic>)
          .map((city) => city.toString())
          .toList(),
      teamName: row.teamName,
      passwordMd5: row.passwordMd5,
      status: row.status,
      failedLoginCount: row.failedLoginCount,
      mustChangePassword: row.mustChangePassword,
      lockedUntil: row.lockedUntil,
      lastSeenAt: row.lastSeenAt,
      lastFailedLoginAt: row.lastFailedLoginAt,
    );
  }

  DbUsersCompanion _userToCompanion(AppUser user) {
    return DbUsersCompanion.insert(
      userId: user.userId,
      username: user.username,
      displayName: user.displayName,
      email: user.email,
      phone: user.phone,
      birthday: Value(user.birthday),
      gender: Value(user.gender),
      occupation: Value(user.occupation),
      contactJson: Value(user.contactJson),
      roleLevel: user.roleLevel,
      cityNamesJson: jsonEncode(user.cityNames),
      teamName: user.teamName,
      passwordMd5: user.passwordMd5,
      status: user.status,
      failedLoginCount: Value(user.failedLoginCount),
      mustChangePassword: Value(user.mustChangePassword),
      lockedUntil: Value(user.lockedUntil),
      lastSeenAt: Value(user.lastSeenAt),
      lastFailedLoginAt: Value(user.lastFailedLoginAt),
    );
  }

  ConversationRecord _recordFromRow(
    DbConversationRecord row,
    List<ConversationContact> contacts,
  ) {
    // Database rows are generated Drift objects. Convert them into our app
    // model at the boundary so screens do not depend on SQL-specific classes.
    return ConversationRecord(
      id: row.recordId,
      createdAt: row.createdAt,
      collectorUserId: row.collectorUserId,
      cityName: row.cityName,
      areaName: row.areaName,
      teamName: row.teamName,
      recorderName: row.recorderName,
      personName: row.personName,
      englishName: row.englishName,
      averageHeartRate: row.averageHeartRate,
      latitude: row.latitude,
      longitude: row.longitude,
      locationAccuracyMeters: row.locationAccuracyMeters,
      locationError: row.locationError,
      manualPlaceName: row.manualPlaceName,
      gender: row.gender,
      identity: row.identity,
      ageRange: row.ageRange,
      relationshipLevel: row.relationshipLevel,
      interestLevel: row.interestLevel,
      contacts: contacts,
      attitudeLevel: row.attitudeLevel,
      notes: row.notes,
      isLocationVerified: row.isLocationVerified,
      correctedLatitude: row.correctedLatitude,
      correctedLongitude: row.correctedLongitude,
      correctedPlaceName: row.correctedPlaceName,
      correctedAt: row.correctedAt,
    );
  }

  DbConversationRecordsCompanion _recordToCompanion(ConversationRecord record) {
    // This is the inverse mapping used when saving. If a field is not present
    // here and not present in DbConversationRecords, it cannot enter SQLite.
    return DbConversationRecordsCompanion.insert(
      recordId: record.id,
      createdAt: record.createdAt,
      collectorUserId: record.collectorUserId,
      cityName: record.cityName,
      areaName: Value(record.areaName),
      teamName: record.teamName,
      recorderName: record.recorderName,
      personName: record.personName,
      englishName: record.englishName,
      averageHeartRate: Value(record.averageHeartRate),
      latitude: Value(record.latitude),
      longitude: Value(record.longitude),
      locationAccuracyMeters: Value(record.locationAccuracyMeters),
      locationError: Value(record.locationError),
      manualPlaceName: record.manualPlaceName,
      gender: record.gender,
      identity: record.identity,
      ageRange: record.ageRange,
      relationshipLevel: Value(record.relationshipLevel),
      interestLevel: Value(record.interestLevel),
      attitudeLevel: record.attitudeLevel,
      notes: record.notes,
      isLocationVerified: Value(record.isLocationVerified),
      correctedLatitude: Value(record.correctedLatitude),
      correctedLongitude: Value(record.correctedLongitude),
      correctedPlaceName: Value(record.correctedPlaceName),
      correctedAt: Value(record.correctedAt),
    );
  }

  static List<String> areasForCity(String cityName) {
    if (cityName == 'Chicago, IL') {
      return const [
        'Union',
        'IIT',
        'UC',
        'UIC',
        '88 Supermarket',
        'Costco',
        'North Suburbs',
        'Chinatown',
      ];
    }
    if (cityName == 'New York, NY') {
      return const ['Campus', 'Downtown', 'Queens', 'Brooklyn'];
    }
    if (cityName == 'Los Angeles, CA') {
      return const ['Downtown', 'Campus', 'Market', 'Suburbs'];
    }
    return const ['General Area'];
  }

  String _defaultAreaForCity(String cityName) {
    return areasForCity(cityName).first;
  }

  ThemeMode _themeModeFromString(String? value) {
    return ThemeMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => ThemeMode.system,
    );
  }
}
