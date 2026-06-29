// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_database.dart';

// ignore_for_file: type=lint
class $DbUsersTable extends DbUsers with TableInfo<$DbUsersTable, DbUser> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DbUsersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _emailMeta = const VerificationMeta('email');
  @override
  late final GeneratedColumn<String> email = GeneratedColumn<String>(
    'email',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _phoneMeta = const VerificationMeta('phone');
  @override
  late final GeneratedColumn<String> phone = GeneratedColumn<String>(
    'phone',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _birthdayMeta = const VerificationMeta(
    'birthday',
  );
  @override
  late final GeneratedColumn<DateTime> birthday = GeneratedColumn<DateTime>(
    'birthday',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _genderMeta = const VerificationMeta('gender');
  @override
  late final GeneratedColumn<String> gender = GeneratedColumn<String>(
    'gender',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('unknown'),
  );
  static const VerificationMeta _occupationMeta = const VerificationMeta(
    'occupation',
  );
  @override
  late final GeneratedColumn<String> occupation = GeneratedColumn<String>(
    'occupation',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _contactJsonMeta = const VerificationMeta(
    'contactJson',
  );
  @override
  late final GeneratedColumn<String> contactJson = GeneratedColumn<String>(
    'contact_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _roleLevelMeta = const VerificationMeta(
    'roleLevel',
  );
  @override
  late final GeneratedColumn<int> roleLevel = GeneratedColumn<int>(
    'role_level',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cityNamesJsonMeta = const VerificationMeta(
    'cityNamesJson',
  );
  @override
  late final GeneratedColumn<String> cityNamesJson = GeneratedColumn<String>(
    'city_names_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _teamNameMeta = const VerificationMeta(
    'teamName',
  );
  @override
  late final GeneratedColumn<String> teamName = GeneratedColumn<String>(
    'team_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _passwordMd5Meta = const VerificationMeta(
    'passwordMd5',
  );
  @override
  late final GeneratedColumn<String> passwordMd5 = GeneratedColumn<String>(
    'password_md5',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _failedLoginCountMeta = const VerificationMeta(
    'failedLoginCount',
  );
  @override
  late final GeneratedColumn<int> failedLoginCount = GeneratedColumn<int>(
    'failed_login_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _mustChangePasswordMeta =
      const VerificationMeta('mustChangePassword');
  @override
  late final GeneratedColumn<bool> mustChangePassword = GeneratedColumn<bool>(
    'must_change_password',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("must_change_password" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _lockedUntilMeta = const VerificationMeta(
    'lockedUntil',
  );
  @override
  late final GeneratedColumn<DateTime> lockedUntil = GeneratedColumn<DateTime>(
    'locked_until',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastSeenAtMeta = const VerificationMeta(
    'lastSeenAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSeenAt = GeneratedColumn<DateTime>(
    'last_seen_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastFailedLoginAtMeta = const VerificationMeta(
    'lastFailedLoginAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastFailedLoginAt =
      GeneratedColumn<DateTime>(
        'last_failed_login_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    userId,
    username,
    displayName,
    email,
    phone,
    birthday,
    gender,
    occupation,
    contactJson,
    roleLevel,
    cityNamesJson,
    teamName,
    passwordMd5,
    status,
    failedLoginCount,
    mustChangePassword,
    lockedUntil,
    lastSeenAt,
    lastFailedLoginAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'db_users';
  @override
  VerificationContext validateIntegrity(
    Insertable<DbUser> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    } else if (isInserting) {
      context.missing(_usernameMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('email')) {
      context.handle(
        _emailMeta,
        email.isAcceptableOrUnknown(data['email']!, _emailMeta),
      );
    } else if (isInserting) {
      context.missing(_emailMeta);
    }
    if (data.containsKey('phone')) {
      context.handle(
        _phoneMeta,
        phone.isAcceptableOrUnknown(data['phone']!, _phoneMeta),
      );
    } else if (isInserting) {
      context.missing(_phoneMeta);
    }
    if (data.containsKey('birthday')) {
      context.handle(
        _birthdayMeta,
        birthday.isAcceptableOrUnknown(data['birthday']!, _birthdayMeta),
      );
    }
    if (data.containsKey('gender')) {
      context.handle(
        _genderMeta,
        gender.isAcceptableOrUnknown(data['gender']!, _genderMeta),
      );
    }
    if (data.containsKey('occupation')) {
      context.handle(
        _occupationMeta,
        occupation.isAcceptableOrUnknown(data['occupation']!, _occupationMeta),
      );
    }
    if (data.containsKey('contact_json')) {
      context.handle(
        _contactJsonMeta,
        contactJson.isAcceptableOrUnknown(
          data['contact_json']!,
          _contactJsonMeta,
        ),
      );
    }
    if (data.containsKey('role_level')) {
      context.handle(
        _roleLevelMeta,
        roleLevel.isAcceptableOrUnknown(data['role_level']!, _roleLevelMeta),
      );
    } else if (isInserting) {
      context.missing(_roleLevelMeta);
    }
    if (data.containsKey('city_names_json')) {
      context.handle(
        _cityNamesJsonMeta,
        cityNamesJson.isAcceptableOrUnknown(
          data['city_names_json']!,
          _cityNamesJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_cityNamesJsonMeta);
    }
    if (data.containsKey('team_name')) {
      context.handle(
        _teamNameMeta,
        teamName.isAcceptableOrUnknown(data['team_name']!, _teamNameMeta),
      );
    } else if (isInserting) {
      context.missing(_teamNameMeta);
    }
    if (data.containsKey('password_md5')) {
      context.handle(
        _passwordMd5Meta,
        passwordMd5.isAcceptableOrUnknown(
          data['password_md5']!,
          _passwordMd5Meta,
        ),
      );
    } else if (isInserting) {
      context.missing(_passwordMd5Meta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('failed_login_count')) {
      context.handle(
        _failedLoginCountMeta,
        failedLoginCount.isAcceptableOrUnknown(
          data['failed_login_count']!,
          _failedLoginCountMeta,
        ),
      );
    }
    if (data.containsKey('must_change_password')) {
      context.handle(
        _mustChangePasswordMeta,
        mustChangePassword.isAcceptableOrUnknown(
          data['must_change_password']!,
          _mustChangePasswordMeta,
        ),
      );
    }
    if (data.containsKey('locked_until')) {
      context.handle(
        _lockedUntilMeta,
        lockedUntil.isAcceptableOrUnknown(
          data['locked_until']!,
          _lockedUntilMeta,
        ),
      );
    }
    if (data.containsKey('last_seen_at')) {
      context.handle(
        _lastSeenAtMeta,
        lastSeenAt.isAcceptableOrUnknown(
          data['last_seen_at']!,
          _lastSeenAtMeta,
        ),
      );
    }
    if (data.containsKey('last_failed_login_at')) {
      context.handle(
        _lastFailedLoginAtMeta,
        lastFailedLoginAt.isAcceptableOrUnknown(
          data['last_failed_login_at']!,
          _lastFailedLoginAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {userId};
  @override
  DbUser map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbUser(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      email: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}email'],
      )!,
      phone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phone'],
      )!,
      birthday: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}birthday'],
      ),
      gender: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gender'],
      )!,
      occupation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}occupation'],
      )!,
      contactJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}contact_json'],
      )!,
      roleLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}role_level'],
      )!,
      cityNamesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}city_names_json'],
      )!,
      teamName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}team_name'],
      )!,
      passwordMd5: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}password_md5'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      failedLoginCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}failed_login_count'],
      )!,
      mustChangePassword: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}must_change_password'],
      )!,
      lockedUntil: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}locked_until'],
      ),
      lastSeenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_seen_at'],
      ),
      lastFailedLoginAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_failed_login_at'],
      ),
    );
  }

  @override
  $DbUsersTable createAlias(String alias) {
    return $DbUsersTable(attachedDatabase, alias);
  }
}

class DbUser extends DataClass implements Insertable<DbUser> {
  final String userId;
  final String username;
  final String displayName;
  final String email;
  final String phone;
  final DateTime? birthday;
  final String gender;
  final String occupation;
  final String contactJson;
  final int roleLevel;
  final String cityNamesJson;
  final String teamName;
  final String passwordMd5;
  final String status;
  final int failedLoginCount;
  final bool mustChangePassword;
  final DateTime? lockedUntil;
  final DateTime? lastSeenAt;
  final DateTime? lastFailedLoginAt;
  const DbUser({
    required this.userId,
    required this.username,
    required this.displayName,
    required this.email,
    required this.phone,
    this.birthday,
    required this.gender,
    required this.occupation,
    required this.contactJson,
    required this.roleLevel,
    required this.cityNamesJson,
    required this.teamName,
    required this.passwordMd5,
    required this.status,
    required this.failedLoginCount,
    required this.mustChangePassword,
    this.lockedUntil,
    this.lastSeenAt,
    this.lastFailedLoginAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['username'] = Variable<String>(username);
    map['display_name'] = Variable<String>(displayName);
    map['email'] = Variable<String>(email);
    map['phone'] = Variable<String>(phone);
    if (!nullToAbsent || birthday != null) {
      map['birthday'] = Variable<DateTime>(birthday);
    }
    map['gender'] = Variable<String>(gender);
    map['occupation'] = Variable<String>(occupation);
    map['contact_json'] = Variable<String>(contactJson);
    map['role_level'] = Variable<int>(roleLevel);
    map['city_names_json'] = Variable<String>(cityNamesJson);
    map['team_name'] = Variable<String>(teamName);
    map['password_md5'] = Variable<String>(passwordMd5);
    map['status'] = Variable<String>(status);
    map['failed_login_count'] = Variable<int>(failedLoginCount);
    map['must_change_password'] = Variable<bool>(mustChangePassword);
    if (!nullToAbsent || lockedUntil != null) {
      map['locked_until'] = Variable<DateTime>(lockedUntil);
    }
    if (!nullToAbsent || lastSeenAt != null) {
      map['last_seen_at'] = Variable<DateTime>(lastSeenAt);
    }
    if (!nullToAbsent || lastFailedLoginAt != null) {
      map['last_failed_login_at'] = Variable<DateTime>(lastFailedLoginAt);
    }
    return map;
  }

  DbUsersCompanion toCompanion(bool nullToAbsent) {
    return DbUsersCompanion(
      userId: Value(userId),
      username: Value(username),
      displayName: Value(displayName),
      email: Value(email),
      phone: Value(phone),
      birthday: birthday == null && nullToAbsent
          ? const Value.absent()
          : Value(birthday),
      gender: Value(gender),
      occupation: Value(occupation),
      contactJson: Value(contactJson),
      roleLevel: Value(roleLevel),
      cityNamesJson: Value(cityNamesJson),
      teamName: Value(teamName),
      passwordMd5: Value(passwordMd5),
      status: Value(status),
      failedLoginCount: Value(failedLoginCount),
      mustChangePassword: Value(mustChangePassword),
      lockedUntil: lockedUntil == null && nullToAbsent
          ? const Value.absent()
          : Value(lockedUntil),
      lastSeenAt: lastSeenAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSeenAt),
      lastFailedLoginAt: lastFailedLoginAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastFailedLoginAt),
    );
  }

  factory DbUser.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbUser(
      userId: serializer.fromJson<String>(json['userId']),
      username: serializer.fromJson<String>(json['username']),
      displayName: serializer.fromJson<String>(json['displayName']),
      email: serializer.fromJson<String>(json['email']),
      phone: serializer.fromJson<String>(json['phone']),
      birthday: serializer.fromJson<DateTime?>(json['birthday']),
      gender: serializer.fromJson<String>(json['gender']),
      occupation: serializer.fromJson<String>(json['occupation']),
      contactJson: serializer.fromJson<String>(json['contactJson']),
      roleLevel: serializer.fromJson<int>(json['roleLevel']),
      cityNamesJson: serializer.fromJson<String>(json['cityNamesJson']),
      teamName: serializer.fromJson<String>(json['teamName']),
      passwordMd5: serializer.fromJson<String>(json['passwordMd5']),
      status: serializer.fromJson<String>(json['status']),
      failedLoginCount: serializer.fromJson<int>(json['failedLoginCount']),
      mustChangePassword: serializer.fromJson<bool>(json['mustChangePassword']),
      lockedUntil: serializer.fromJson<DateTime?>(json['lockedUntil']),
      lastSeenAt: serializer.fromJson<DateTime?>(json['lastSeenAt']),
      lastFailedLoginAt: serializer.fromJson<DateTime?>(
        json['lastFailedLoginAt'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'username': serializer.toJson<String>(username),
      'displayName': serializer.toJson<String>(displayName),
      'email': serializer.toJson<String>(email),
      'phone': serializer.toJson<String>(phone),
      'birthday': serializer.toJson<DateTime?>(birthday),
      'gender': serializer.toJson<String>(gender),
      'occupation': serializer.toJson<String>(occupation),
      'contactJson': serializer.toJson<String>(contactJson),
      'roleLevel': serializer.toJson<int>(roleLevel),
      'cityNamesJson': serializer.toJson<String>(cityNamesJson),
      'teamName': serializer.toJson<String>(teamName),
      'passwordMd5': serializer.toJson<String>(passwordMd5),
      'status': serializer.toJson<String>(status),
      'failedLoginCount': serializer.toJson<int>(failedLoginCount),
      'mustChangePassword': serializer.toJson<bool>(mustChangePassword),
      'lockedUntil': serializer.toJson<DateTime?>(lockedUntil),
      'lastSeenAt': serializer.toJson<DateTime?>(lastSeenAt),
      'lastFailedLoginAt': serializer.toJson<DateTime?>(lastFailedLoginAt),
    };
  }

  DbUser copyWith({
    String? userId,
    String? username,
    String? displayName,
    String? email,
    String? phone,
    Value<DateTime?> birthday = const Value.absent(),
    String? gender,
    String? occupation,
    String? contactJson,
    int? roleLevel,
    String? cityNamesJson,
    String? teamName,
    String? passwordMd5,
    String? status,
    int? failedLoginCount,
    bool? mustChangePassword,
    Value<DateTime?> lockedUntil = const Value.absent(),
    Value<DateTime?> lastSeenAt = const Value.absent(),
    Value<DateTime?> lastFailedLoginAt = const Value.absent(),
  }) => DbUser(
    userId: userId ?? this.userId,
    username: username ?? this.username,
    displayName: displayName ?? this.displayName,
    email: email ?? this.email,
    phone: phone ?? this.phone,
    birthday: birthday.present ? birthday.value : this.birthday,
    gender: gender ?? this.gender,
    occupation: occupation ?? this.occupation,
    contactJson: contactJson ?? this.contactJson,
    roleLevel: roleLevel ?? this.roleLevel,
    cityNamesJson: cityNamesJson ?? this.cityNamesJson,
    teamName: teamName ?? this.teamName,
    passwordMd5: passwordMd5 ?? this.passwordMd5,
    status: status ?? this.status,
    failedLoginCount: failedLoginCount ?? this.failedLoginCount,
    mustChangePassword: mustChangePassword ?? this.mustChangePassword,
    lockedUntil: lockedUntil.present ? lockedUntil.value : this.lockedUntil,
    lastSeenAt: lastSeenAt.present ? lastSeenAt.value : this.lastSeenAt,
    lastFailedLoginAt: lastFailedLoginAt.present
        ? lastFailedLoginAt.value
        : this.lastFailedLoginAt,
  );
  DbUser copyWithCompanion(DbUsersCompanion data) {
    return DbUser(
      userId: data.userId.present ? data.userId.value : this.userId,
      username: data.username.present ? data.username.value : this.username,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      email: data.email.present ? data.email.value : this.email,
      phone: data.phone.present ? data.phone.value : this.phone,
      birthday: data.birthday.present ? data.birthday.value : this.birthday,
      gender: data.gender.present ? data.gender.value : this.gender,
      occupation: data.occupation.present
          ? data.occupation.value
          : this.occupation,
      contactJson: data.contactJson.present
          ? data.contactJson.value
          : this.contactJson,
      roleLevel: data.roleLevel.present ? data.roleLevel.value : this.roleLevel,
      cityNamesJson: data.cityNamesJson.present
          ? data.cityNamesJson.value
          : this.cityNamesJson,
      teamName: data.teamName.present ? data.teamName.value : this.teamName,
      passwordMd5: data.passwordMd5.present
          ? data.passwordMd5.value
          : this.passwordMd5,
      status: data.status.present ? data.status.value : this.status,
      failedLoginCount: data.failedLoginCount.present
          ? data.failedLoginCount.value
          : this.failedLoginCount,
      mustChangePassword: data.mustChangePassword.present
          ? data.mustChangePassword.value
          : this.mustChangePassword,
      lockedUntil: data.lockedUntil.present
          ? data.lockedUntil.value
          : this.lockedUntil,
      lastSeenAt: data.lastSeenAt.present
          ? data.lastSeenAt.value
          : this.lastSeenAt,
      lastFailedLoginAt: data.lastFailedLoginAt.present
          ? data.lastFailedLoginAt.value
          : this.lastFailedLoginAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbUser(')
          ..write('userId: $userId, ')
          ..write('username: $username, ')
          ..write('displayName: $displayName, ')
          ..write('email: $email, ')
          ..write('phone: $phone, ')
          ..write('birthday: $birthday, ')
          ..write('gender: $gender, ')
          ..write('occupation: $occupation, ')
          ..write('contactJson: $contactJson, ')
          ..write('roleLevel: $roleLevel, ')
          ..write('cityNamesJson: $cityNamesJson, ')
          ..write('teamName: $teamName, ')
          ..write('passwordMd5: $passwordMd5, ')
          ..write('status: $status, ')
          ..write('failedLoginCount: $failedLoginCount, ')
          ..write('mustChangePassword: $mustChangePassword, ')
          ..write('lockedUntil: $lockedUntil, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('lastFailedLoginAt: $lastFailedLoginAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    userId,
    username,
    displayName,
    email,
    phone,
    birthday,
    gender,
    occupation,
    contactJson,
    roleLevel,
    cityNamesJson,
    teamName,
    passwordMd5,
    status,
    failedLoginCount,
    mustChangePassword,
    lockedUntil,
    lastSeenAt,
    lastFailedLoginAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbUser &&
          other.userId == this.userId &&
          other.username == this.username &&
          other.displayName == this.displayName &&
          other.email == this.email &&
          other.phone == this.phone &&
          other.birthday == this.birthday &&
          other.gender == this.gender &&
          other.occupation == this.occupation &&
          other.contactJson == this.contactJson &&
          other.roleLevel == this.roleLevel &&
          other.cityNamesJson == this.cityNamesJson &&
          other.teamName == this.teamName &&
          other.passwordMd5 == this.passwordMd5 &&
          other.status == this.status &&
          other.failedLoginCount == this.failedLoginCount &&
          other.mustChangePassword == this.mustChangePassword &&
          other.lockedUntil == this.lockedUntil &&
          other.lastSeenAt == this.lastSeenAt &&
          other.lastFailedLoginAt == this.lastFailedLoginAt);
}

class DbUsersCompanion extends UpdateCompanion<DbUser> {
  final Value<String> userId;
  final Value<String> username;
  final Value<String> displayName;
  final Value<String> email;
  final Value<String> phone;
  final Value<DateTime?> birthday;
  final Value<String> gender;
  final Value<String> occupation;
  final Value<String> contactJson;
  final Value<int> roleLevel;
  final Value<String> cityNamesJson;
  final Value<String> teamName;
  final Value<String> passwordMd5;
  final Value<String> status;
  final Value<int> failedLoginCount;
  final Value<bool> mustChangePassword;
  final Value<DateTime?> lockedUntil;
  final Value<DateTime?> lastSeenAt;
  final Value<DateTime?> lastFailedLoginAt;
  final Value<int> rowid;
  const DbUsersCompanion({
    this.userId = const Value.absent(),
    this.username = const Value.absent(),
    this.displayName = const Value.absent(),
    this.email = const Value.absent(),
    this.phone = const Value.absent(),
    this.birthday = const Value.absent(),
    this.gender = const Value.absent(),
    this.occupation = const Value.absent(),
    this.contactJson = const Value.absent(),
    this.roleLevel = const Value.absent(),
    this.cityNamesJson = const Value.absent(),
    this.teamName = const Value.absent(),
    this.passwordMd5 = const Value.absent(),
    this.status = const Value.absent(),
    this.failedLoginCount = const Value.absent(),
    this.mustChangePassword = const Value.absent(),
    this.lockedUntil = const Value.absent(),
    this.lastSeenAt = const Value.absent(),
    this.lastFailedLoginAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DbUsersCompanion.insert({
    required String userId,
    required String username,
    required String displayName,
    required String email,
    required String phone,
    this.birthday = const Value.absent(),
    this.gender = const Value.absent(),
    this.occupation = const Value.absent(),
    this.contactJson = const Value.absent(),
    required int roleLevel,
    required String cityNamesJson,
    required String teamName,
    required String passwordMd5,
    required String status,
    this.failedLoginCount = const Value.absent(),
    this.mustChangePassword = const Value.absent(),
    this.lockedUntil = const Value.absent(),
    this.lastSeenAt = const Value.absent(),
    this.lastFailedLoginAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       username = Value(username),
       displayName = Value(displayName),
       email = Value(email),
       phone = Value(phone),
       roleLevel = Value(roleLevel),
       cityNamesJson = Value(cityNamesJson),
       teamName = Value(teamName),
       passwordMd5 = Value(passwordMd5),
       status = Value(status);
  static Insertable<DbUser> custom({
    Expression<String>? userId,
    Expression<String>? username,
    Expression<String>? displayName,
    Expression<String>? email,
    Expression<String>? phone,
    Expression<DateTime>? birthday,
    Expression<String>? gender,
    Expression<String>? occupation,
    Expression<String>? contactJson,
    Expression<int>? roleLevel,
    Expression<String>? cityNamesJson,
    Expression<String>? teamName,
    Expression<String>? passwordMd5,
    Expression<String>? status,
    Expression<int>? failedLoginCount,
    Expression<bool>? mustChangePassword,
    Expression<DateTime>? lockedUntil,
    Expression<DateTime>? lastSeenAt,
    Expression<DateTime>? lastFailedLoginAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (username != null) 'username': username,
      if (displayName != null) 'display_name': displayName,
      if (email != null) 'email': email,
      if (phone != null) 'phone': phone,
      if (birthday != null) 'birthday': birthday,
      if (gender != null) 'gender': gender,
      if (occupation != null) 'occupation': occupation,
      if (contactJson != null) 'contact_json': contactJson,
      if (roleLevel != null) 'role_level': roleLevel,
      if (cityNamesJson != null) 'city_names_json': cityNamesJson,
      if (teamName != null) 'team_name': teamName,
      if (passwordMd5 != null) 'password_md5': passwordMd5,
      if (status != null) 'status': status,
      if (failedLoginCount != null) 'failed_login_count': failedLoginCount,
      if (mustChangePassword != null)
        'must_change_password': mustChangePassword,
      if (lockedUntil != null) 'locked_until': lockedUntil,
      if (lastSeenAt != null) 'last_seen_at': lastSeenAt,
      if (lastFailedLoginAt != null) 'last_failed_login_at': lastFailedLoginAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DbUsersCompanion copyWith({
    Value<String>? userId,
    Value<String>? username,
    Value<String>? displayName,
    Value<String>? email,
    Value<String>? phone,
    Value<DateTime?>? birthday,
    Value<String>? gender,
    Value<String>? occupation,
    Value<String>? contactJson,
    Value<int>? roleLevel,
    Value<String>? cityNamesJson,
    Value<String>? teamName,
    Value<String>? passwordMd5,
    Value<String>? status,
    Value<int>? failedLoginCount,
    Value<bool>? mustChangePassword,
    Value<DateTime?>? lockedUntil,
    Value<DateTime?>? lastSeenAt,
    Value<DateTime?>? lastFailedLoginAt,
    Value<int>? rowid,
  }) {
    return DbUsersCompanion(
      userId: userId ?? this.userId,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      birthday: birthday ?? this.birthday,
      gender: gender ?? this.gender,
      occupation: occupation ?? this.occupation,
      contactJson: contactJson ?? this.contactJson,
      roleLevel: roleLevel ?? this.roleLevel,
      cityNamesJson: cityNamesJson ?? this.cityNamesJson,
      teamName: teamName ?? this.teamName,
      passwordMd5: passwordMd5 ?? this.passwordMd5,
      status: status ?? this.status,
      failedLoginCount: failedLoginCount ?? this.failedLoginCount,
      mustChangePassword: mustChangePassword ?? this.mustChangePassword,
      lockedUntil: lockedUntil ?? this.lockedUntil,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      lastFailedLoginAt: lastFailedLoginAt ?? this.lastFailedLoginAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (email.present) {
      map['email'] = Variable<String>(email.value);
    }
    if (phone.present) {
      map['phone'] = Variable<String>(phone.value);
    }
    if (birthday.present) {
      map['birthday'] = Variable<DateTime>(birthday.value);
    }
    if (gender.present) {
      map['gender'] = Variable<String>(gender.value);
    }
    if (occupation.present) {
      map['occupation'] = Variable<String>(occupation.value);
    }
    if (contactJson.present) {
      map['contact_json'] = Variable<String>(contactJson.value);
    }
    if (roleLevel.present) {
      map['role_level'] = Variable<int>(roleLevel.value);
    }
    if (cityNamesJson.present) {
      map['city_names_json'] = Variable<String>(cityNamesJson.value);
    }
    if (teamName.present) {
      map['team_name'] = Variable<String>(teamName.value);
    }
    if (passwordMd5.present) {
      map['password_md5'] = Variable<String>(passwordMd5.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (failedLoginCount.present) {
      map['failed_login_count'] = Variable<int>(failedLoginCount.value);
    }
    if (mustChangePassword.present) {
      map['must_change_password'] = Variable<bool>(mustChangePassword.value);
    }
    if (lockedUntil.present) {
      map['locked_until'] = Variable<DateTime>(lockedUntil.value);
    }
    if (lastSeenAt.present) {
      map['last_seen_at'] = Variable<DateTime>(lastSeenAt.value);
    }
    if (lastFailedLoginAt.present) {
      map['last_failed_login_at'] = Variable<DateTime>(lastFailedLoginAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DbUsersCompanion(')
          ..write('userId: $userId, ')
          ..write('username: $username, ')
          ..write('displayName: $displayName, ')
          ..write('email: $email, ')
          ..write('phone: $phone, ')
          ..write('birthday: $birthday, ')
          ..write('gender: $gender, ')
          ..write('occupation: $occupation, ')
          ..write('contactJson: $contactJson, ')
          ..write('roleLevel: $roleLevel, ')
          ..write('cityNamesJson: $cityNamesJson, ')
          ..write('teamName: $teamName, ')
          ..write('passwordMd5: $passwordMd5, ')
          ..write('status: $status, ')
          ..write('failedLoginCount: $failedLoginCount, ')
          ..write('mustChangePassword: $mustChangePassword, ')
          ..write('lockedUntil: $lockedUntil, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('lastFailedLoginAt: $lastFailedLoginAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DbConversationRecordsTable extends DbConversationRecords
    with TableInfo<$DbConversationRecordsTable, DbConversationRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DbConversationRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _recordIdMeta = const VerificationMeta(
    'recordId',
  );
  @override
  late final GeneratedColumn<String> recordId = GeneratedColumn<String>(
    'record_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _collectorUserIdMeta = const VerificationMeta(
    'collectorUserId',
  );
  @override
  late final GeneratedColumn<String> collectorUserId = GeneratedColumn<String>(
    'collector_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cityNameMeta = const VerificationMeta(
    'cityName',
  );
  @override
  late final GeneratedColumn<String> cityName = GeneratedColumn<String>(
    'city_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _areaNameMeta = const VerificationMeta(
    'areaName',
  );
  @override
  late final GeneratedColumn<String> areaName = GeneratedColumn<String>(
    'area_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('unassigned'),
  );
  static const VerificationMeta _teamNameMeta = const VerificationMeta(
    'teamName',
  );
  @override
  late final GeneratedColumn<String> teamName = GeneratedColumn<String>(
    'team_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recorderNameMeta = const VerificationMeta(
    'recorderName',
  );
  @override
  late final GeneratedColumn<String> recorderName = GeneratedColumn<String>(
    'recorder_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _personNameMeta = const VerificationMeta(
    'personName',
  );
  @override
  late final GeneratedColumn<String> personName = GeneratedColumn<String>(
    'person_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _englishNameMeta = const VerificationMeta(
    'englishName',
  );
  @override
  late final GeneratedColumn<String> englishName = GeneratedColumn<String>(
    'english_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _averageHeartRateMeta = const VerificationMeta(
    'averageHeartRate',
  );
  @override
  late final GeneratedColumn<double> averageHeartRate = GeneratedColumn<double>(
    'average_heart_rate',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _latitudeMeta = const VerificationMeta(
    'latitude',
  );
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
    'latitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _longitudeMeta = const VerificationMeta(
    'longitude',
  );
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
    'longitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _locationAccuracyMetersMeta =
      const VerificationMeta('locationAccuracyMeters');
  @override
  late final GeneratedColumn<double> locationAccuracyMeters =
      GeneratedColumn<double>(
        'location_accuracy_meters',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _locationErrorMeta = const VerificationMeta(
    'locationError',
  );
  @override
  late final GeneratedColumn<String> locationError = GeneratedColumn<String>(
    'location_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _manualPlaceNameMeta = const VerificationMeta(
    'manualPlaceName',
  );
  @override
  late final GeneratedColumn<String> manualPlaceName = GeneratedColumn<String>(
    'manual_place_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _genderMeta = const VerificationMeta('gender');
  @override
  late final GeneratedColumn<String> gender = GeneratedColumn<String>(
    'gender',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _identityMeta = const VerificationMeta(
    'identity',
  );
  @override
  late final GeneratedColumn<String> identity = GeneratedColumn<String>(
    'identity',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ageRangeMeta = const VerificationMeta(
    'ageRange',
  );
  @override
  late final GeneratedColumn<String> ageRange = GeneratedColumn<String>(
    'age_range',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _relationshipLevelMeta = const VerificationMeta(
    'relationshipLevel',
  );
  @override
  late final GeneratedColumn<int> relationshipLevel = GeneratedColumn<int>(
    'relationship_level',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _interestLevelMeta = const VerificationMeta(
    'interestLevel',
  );
  @override
  late final GeneratedColumn<int> interestLevel = GeneratedColumn<int>(
    'interest_level',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(2),
  );
  static const VerificationMeta _attitudeLevelMeta = const VerificationMeta(
    'attitudeLevel',
  );
  @override
  late final GeneratedColumn<int> attitudeLevel = GeneratedColumn<int>(
    'attitude_level',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isLocationVerifiedMeta =
      const VerificationMeta('isLocationVerified');
  @override
  late final GeneratedColumn<bool> isLocationVerified = GeneratedColumn<bool>(
    'is_location_verified',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_location_verified" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _correctedLatitudeMeta = const VerificationMeta(
    'correctedLatitude',
  );
  @override
  late final GeneratedColumn<double> correctedLatitude =
      GeneratedColumn<double>(
        'corrected_latitude',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _correctedLongitudeMeta =
      const VerificationMeta('correctedLongitude');
  @override
  late final GeneratedColumn<double> correctedLongitude =
      GeneratedColumn<double>(
        'corrected_longitude',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _correctedPlaceNameMeta =
      const VerificationMeta('correctedPlaceName');
  @override
  late final GeneratedColumn<String> correctedPlaceName =
      GeneratedColumn<String>(
        'corrected_place_name',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _correctedAtMeta = const VerificationMeta(
    'correctedAt',
  );
  @override
  late final GeneratedColumn<DateTime> correctedAt = GeneratedColumn<DateTime>(
    'corrected_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    recordId,
    createdAt,
    collectorUserId,
    cityName,
    areaName,
    teamName,
    recorderName,
    personName,
    englishName,
    averageHeartRate,
    latitude,
    longitude,
    locationAccuracyMeters,
    locationError,
    manualPlaceName,
    gender,
    identity,
    ageRange,
    relationshipLevel,
    interestLevel,
    attitudeLevel,
    notes,
    isLocationVerified,
    correctedLatitude,
    correctedLongitude,
    correctedPlaceName,
    correctedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'db_conversation_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<DbConversationRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('record_id')) {
      context.handle(
        _recordIdMeta,
        recordId.isAcceptableOrUnknown(data['record_id']!, _recordIdMeta),
      );
    } else if (isInserting) {
      context.missing(_recordIdMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('collector_user_id')) {
      context.handle(
        _collectorUserIdMeta,
        collectorUserId.isAcceptableOrUnknown(
          data['collector_user_id']!,
          _collectorUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_collectorUserIdMeta);
    }
    if (data.containsKey('city_name')) {
      context.handle(
        _cityNameMeta,
        cityName.isAcceptableOrUnknown(data['city_name']!, _cityNameMeta),
      );
    } else if (isInserting) {
      context.missing(_cityNameMeta);
    }
    if (data.containsKey('area_name')) {
      context.handle(
        _areaNameMeta,
        areaName.isAcceptableOrUnknown(data['area_name']!, _areaNameMeta),
      );
    }
    if (data.containsKey('team_name')) {
      context.handle(
        _teamNameMeta,
        teamName.isAcceptableOrUnknown(data['team_name']!, _teamNameMeta),
      );
    } else if (isInserting) {
      context.missing(_teamNameMeta);
    }
    if (data.containsKey('recorder_name')) {
      context.handle(
        _recorderNameMeta,
        recorderName.isAcceptableOrUnknown(
          data['recorder_name']!,
          _recorderNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_recorderNameMeta);
    }
    if (data.containsKey('person_name')) {
      context.handle(
        _personNameMeta,
        personName.isAcceptableOrUnknown(data['person_name']!, _personNameMeta),
      );
    } else if (isInserting) {
      context.missing(_personNameMeta);
    }
    if (data.containsKey('english_name')) {
      context.handle(
        _englishNameMeta,
        englishName.isAcceptableOrUnknown(
          data['english_name']!,
          _englishNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_englishNameMeta);
    }
    if (data.containsKey('average_heart_rate')) {
      context.handle(
        _averageHeartRateMeta,
        averageHeartRate.isAcceptableOrUnknown(
          data['average_heart_rate']!,
          _averageHeartRateMeta,
        ),
      );
    }
    if (data.containsKey('latitude')) {
      context.handle(
        _latitudeMeta,
        latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta),
      );
    }
    if (data.containsKey('longitude')) {
      context.handle(
        _longitudeMeta,
        longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta),
      );
    }
    if (data.containsKey('location_accuracy_meters')) {
      context.handle(
        _locationAccuracyMetersMeta,
        locationAccuracyMeters.isAcceptableOrUnknown(
          data['location_accuracy_meters']!,
          _locationAccuracyMetersMeta,
        ),
      );
    }
    if (data.containsKey('location_error')) {
      context.handle(
        _locationErrorMeta,
        locationError.isAcceptableOrUnknown(
          data['location_error']!,
          _locationErrorMeta,
        ),
      );
    }
    if (data.containsKey('manual_place_name')) {
      context.handle(
        _manualPlaceNameMeta,
        manualPlaceName.isAcceptableOrUnknown(
          data['manual_place_name']!,
          _manualPlaceNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_manualPlaceNameMeta);
    }
    if (data.containsKey('gender')) {
      context.handle(
        _genderMeta,
        gender.isAcceptableOrUnknown(data['gender']!, _genderMeta),
      );
    } else if (isInserting) {
      context.missing(_genderMeta);
    }
    if (data.containsKey('identity')) {
      context.handle(
        _identityMeta,
        identity.isAcceptableOrUnknown(data['identity']!, _identityMeta),
      );
    } else if (isInserting) {
      context.missing(_identityMeta);
    }
    if (data.containsKey('age_range')) {
      context.handle(
        _ageRangeMeta,
        ageRange.isAcceptableOrUnknown(data['age_range']!, _ageRangeMeta),
      );
    } else if (isInserting) {
      context.missing(_ageRangeMeta);
    }
    if (data.containsKey('relationship_level')) {
      context.handle(
        _relationshipLevelMeta,
        relationshipLevel.isAcceptableOrUnknown(
          data['relationship_level']!,
          _relationshipLevelMeta,
        ),
      );
    }
    if (data.containsKey('interest_level')) {
      context.handle(
        _interestLevelMeta,
        interestLevel.isAcceptableOrUnknown(
          data['interest_level']!,
          _interestLevelMeta,
        ),
      );
    }
    if (data.containsKey('attitude_level')) {
      context.handle(
        _attitudeLevelMeta,
        attitudeLevel.isAcceptableOrUnknown(
          data['attitude_level']!,
          _attitudeLevelMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_attitudeLevelMeta);
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    } else if (isInserting) {
      context.missing(_notesMeta);
    }
    if (data.containsKey('is_location_verified')) {
      context.handle(
        _isLocationVerifiedMeta,
        isLocationVerified.isAcceptableOrUnknown(
          data['is_location_verified']!,
          _isLocationVerifiedMeta,
        ),
      );
    }
    if (data.containsKey('corrected_latitude')) {
      context.handle(
        _correctedLatitudeMeta,
        correctedLatitude.isAcceptableOrUnknown(
          data['corrected_latitude']!,
          _correctedLatitudeMeta,
        ),
      );
    }
    if (data.containsKey('corrected_longitude')) {
      context.handle(
        _correctedLongitudeMeta,
        correctedLongitude.isAcceptableOrUnknown(
          data['corrected_longitude']!,
          _correctedLongitudeMeta,
        ),
      );
    }
    if (data.containsKey('corrected_place_name')) {
      context.handle(
        _correctedPlaceNameMeta,
        correctedPlaceName.isAcceptableOrUnknown(
          data['corrected_place_name']!,
          _correctedPlaceNameMeta,
        ),
      );
    }
    if (data.containsKey('corrected_at')) {
      context.handle(
        _correctedAtMeta,
        correctedAt.isAcceptableOrUnknown(
          data['corrected_at']!,
          _correctedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {recordId};
  @override
  DbConversationRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbConversationRecord(
      recordId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}record_id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      collectorUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}collector_user_id'],
      )!,
      cityName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}city_name'],
      )!,
      areaName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}area_name'],
      )!,
      teamName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}team_name'],
      )!,
      recorderName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recorder_name'],
      )!,
      personName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}person_name'],
      )!,
      englishName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}english_name'],
      )!,
      averageHeartRate: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}average_heart_rate'],
      ),
      latitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitude'],
      ),
      longitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitude'],
      ),
      locationAccuracyMeters: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}location_accuracy_meters'],
      ),
      locationError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location_error'],
      ),
      manualPlaceName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}manual_place_name'],
      )!,
      gender: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gender'],
      )!,
      identity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}identity'],
      )!,
      ageRange: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}age_range'],
      )!,
      relationshipLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}relationship_level'],
      )!,
      interestLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}interest_level'],
      )!,
      attitudeLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attitude_level'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      )!,
      isLocationVerified: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_location_verified'],
      )!,
      correctedLatitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}corrected_latitude'],
      ),
      correctedLongitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}corrected_longitude'],
      ),
      correctedPlaceName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}corrected_place_name'],
      ),
      correctedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}corrected_at'],
      ),
    );
  }

  @override
  $DbConversationRecordsTable createAlias(String alias) {
    return $DbConversationRecordsTable(attachedDatabase, alias);
  }
}

class DbConversationRecord extends DataClass
    implements Insertable<DbConversationRecord> {
  final String recordId;
  final DateTime createdAt;
  final String collectorUserId;
  final String cityName;
  final String areaName;
  final String teamName;
  final String recorderName;
  final String personName;
  final String englishName;
  final double? averageHeartRate;
  final double? latitude;
  final double? longitude;
  final double? locationAccuracyMeters;
  final String? locationError;
  final String manualPlaceName;
  final String gender;
  final String identity;
  final String ageRange;
  final int relationshipLevel;
  final int interestLevel;
  final int attitudeLevel;
  final String notes;
  final bool isLocationVerified;
  final double? correctedLatitude;
  final double? correctedLongitude;
  final String? correctedPlaceName;
  final DateTime? correctedAt;
  const DbConversationRecord({
    required this.recordId,
    required this.createdAt,
    required this.collectorUserId,
    required this.cityName,
    required this.areaName,
    required this.teamName,
    required this.recorderName,
    required this.personName,
    required this.englishName,
    this.averageHeartRate,
    this.latitude,
    this.longitude,
    this.locationAccuracyMeters,
    this.locationError,
    required this.manualPlaceName,
    required this.gender,
    required this.identity,
    required this.ageRange,
    required this.relationshipLevel,
    required this.interestLevel,
    required this.attitudeLevel,
    required this.notes,
    required this.isLocationVerified,
    this.correctedLatitude,
    this.correctedLongitude,
    this.correctedPlaceName,
    this.correctedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['record_id'] = Variable<String>(recordId);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['collector_user_id'] = Variable<String>(collectorUserId);
    map['city_name'] = Variable<String>(cityName);
    map['area_name'] = Variable<String>(areaName);
    map['team_name'] = Variable<String>(teamName);
    map['recorder_name'] = Variable<String>(recorderName);
    map['person_name'] = Variable<String>(personName);
    map['english_name'] = Variable<String>(englishName);
    if (!nullToAbsent || averageHeartRate != null) {
      map['average_heart_rate'] = Variable<double>(averageHeartRate);
    }
    if (!nullToAbsent || latitude != null) {
      map['latitude'] = Variable<double>(latitude);
    }
    if (!nullToAbsent || longitude != null) {
      map['longitude'] = Variable<double>(longitude);
    }
    if (!nullToAbsent || locationAccuracyMeters != null) {
      map['location_accuracy_meters'] = Variable<double>(
        locationAccuracyMeters,
      );
    }
    if (!nullToAbsent || locationError != null) {
      map['location_error'] = Variable<String>(locationError);
    }
    map['manual_place_name'] = Variable<String>(manualPlaceName);
    map['gender'] = Variable<String>(gender);
    map['identity'] = Variable<String>(identity);
    map['age_range'] = Variable<String>(ageRange);
    map['relationship_level'] = Variable<int>(relationshipLevel);
    map['interest_level'] = Variable<int>(interestLevel);
    map['attitude_level'] = Variable<int>(attitudeLevel);
    map['notes'] = Variable<String>(notes);
    map['is_location_verified'] = Variable<bool>(isLocationVerified);
    if (!nullToAbsent || correctedLatitude != null) {
      map['corrected_latitude'] = Variable<double>(correctedLatitude);
    }
    if (!nullToAbsent || correctedLongitude != null) {
      map['corrected_longitude'] = Variable<double>(correctedLongitude);
    }
    if (!nullToAbsent || correctedPlaceName != null) {
      map['corrected_place_name'] = Variable<String>(correctedPlaceName);
    }
    if (!nullToAbsent || correctedAt != null) {
      map['corrected_at'] = Variable<DateTime>(correctedAt);
    }
    return map;
  }

  DbConversationRecordsCompanion toCompanion(bool nullToAbsent) {
    return DbConversationRecordsCompanion(
      recordId: Value(recordId),
      createdAt: Value(createdAt),
      collectorUserId: Value(collectorUserId),
      cityName: Value(cityName),
      areaName: Value(areaName),
      teamName: Value(teamName),
      recorderName: Value(recorderName),
      personName: Value(personName),
      englishName: Value(englishName),
      averageHeartRate: averageHeartRate == null && nullToAbsent
          ? const Value.absent()
          : Value(averageHeartRate),
      latitude: latitude == null && nullToAbsent
          ? const Value.absent()
          : Value(latitude),
      longitude: longitude == null && nullToAbsent
          ? const Value.absent()
          : Value(longitude),
      locationAccuracyMeters: locationAccuracyMeters == null && nullToAbsent
          ? const Value.absent()
          : Value(locationAccuracyMeters),
      locationError: locationError == null && nullToAbsent
          ? const Value.absent()
          : Value(locationError),
      manualPlaceName: Value(manualPlaceName),
      gender: Value(gender),
      identity: Value(identity),
      ageRange: Value(ageRange),
      relationshipLevel: Value(relationshipLevel),
      interestLevel: Value(interestLevel),
      attitudeLevel: Value(attitudeLevel),
      notes: Value(notes),
      isLocationVerified: Value(isLocationVerified),
      correctedLatitude: correctedLatitude == null && nullToAbsent
          ? const Value.absent()
          : Value(correctedLatitude),
      correctedLongitude: correctedLongitude == null && nullToAbsent
          ? const Value.absent()
          : Value(correctedLongitude),
      correctedPlaceName: correctedPlaceName == null && nullToAbsent
          ? const Value.absent()
          : Value(correctedPlaceName),
      correctedAt: correctedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(correctedAt),
    );
  }

  factory DbConversationRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbConversationRecord(
      recordId: serializer.fromJson<String>(json['recordId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      collectorUserId: serializer.fromJson<String>(json['collectorUserId']),
      cityName: serializer.fromJson<String>(json['cityName']),
      areaName: serializer.fromJson<String>(json['areaName']),
      teamName: serializer.fromJson<String>(json['teamName']),
      recorderName: serializer.fromJson<String>(json['recorderName']),
      personName: serializer.fromJson<String>(json['personName']),
      englishName: serializer.fromJson<String>(json['englishName']),
      averageHeartRate: serializer.fromJson<double?>(json['averageHeartRate']),
      latitude: serializer.fromJson<double?>(json['latitude']),
      longitude: serializer.fromJson<double?>(json['longitude']),
      locationAccuracyMeters: serializer.fromJson<double?>(
        json['locationAccuracyMeters'],
      ),
      locationError: serializer.fromJson<String?>(json['locationError']),
      manualPlaceName: serializer.fromJson<String>(json['manualPlaceName']),
      gender: serializer.fromJson<String>(json['gender']),
      identity: serializer.fromJson<String>(json['identity']),
      ageRange: serializer.fromJson<String>(json['ageRange']),
      relationshipLevel: serializer.fromJson<int>(json['relationshipLevel']),
      interestLevel: serializer.fromJson<int>(json['interestLevel']),
      attitudeLevel: serializer.fromJson<int>(json['attitudeLevel']),
      notes: serializer.fromJson<String>(json['notes']),
      isLocationVerified: serializer.fromJson<bool>(json['isLocationVerified']),
      correctedLatitude: serializer.fromJson<double?>(
        json['correctedLatitude'],
      ),
      correctedLongitude: serializer.fromJson<double?>(
        json['correctedLongitude'],
      ),
      correctedPlaceName: serializer.fromJson<String?>(
        json['correctedPlaceName'],
      ),
      correctedAt: serializer.fromJson<DateTime?>(json['correctedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'recordId': serializer.toJson<String>(recordId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'collectorUserId': serializer.toJson<String>(collectorUserId),
      'cityName': serializer.toJson<String>(cityName),
      'areaName': serializer.toJson<String>(areaName),
      'teamName': serializer.toJson<String>(teamName),
      'recorderName': serializer.toJson<String>(recorderName),
      'personName': serializer.toJson<String>(personName),
      'englishName': serializer.toJson<String>(englishName),
      'averageHeartRate': serializer.toJson<double?>(averageHeartRate),
      'latitude': serializer.toJson<double?>(latitude),
      'longitude': serializer.toJson<double?>(longitude),
      'locationAccuracyMeters': serializer.toJson<double?>(
        locationAccuracyMeters,
      ),
      'locationError': serializer.toJson<String?>(locationError),
      'manualPlaceName': serializer.toJson<String>(manualPlaceName),
      'gender': serializer.toJson<String>(gender),
      'identity': serializer.toJson<String>(identity),
      'ageRange': serializer.toJson<String>(ageRange),
      'relationshipLevel': serializer.toJson<int>(relationshipLevel),
      'interestLevel': serializer.toJson<int>(interestLevel),
      'attitudeLevel': serializer.toJson<int>(attitudeLevel),
      'notes': serializer.toJson<String>(notes),
      'isLocationVerified': serializer.toJson<bool>(isLocationVerified),
      'correctedLatitude': serializer.toJson<double?>(correctedLatitude),
      'correctedLongitude': serializer.toJson<double?>(correctedLongitude),
      'correctedPlaceName': serializer.toJson<String?>(correctedPlaceName),
      'correctedAt': serializer.toJson<DateTime?>(correctedAt),
    };
  }

  DbConversationRecord copyWith({
    String? recordId,
    DateTime? createdAt,
    String? collectorUserId,
    String? cityName,
    String? areaName,
    String? teamName,
    String? recorderName,
    String? personName,
    String? englishName,
    Value<double?> averageHeartRate = const Value.absent(),
    Value<double?> latitude = const Value.absent(),
    Value<double?> longitude = const Value.absent(),
    Value<double?> locationAccuracyMeters = const Value.absent(),
    Value<String?> locationError = const Value.absent(),
    String? manualPlaceName,
    String? gender,
    String? identity,
    String? ageRange,
    int? relationshipLevel,
    int? interestLevel,
    int? attitudeLevel,
    String? notes,
    bool? isLocationVerified,
    Value<double?> correctedLatitude = const Value.absent(),
    Value<double?> correctedLongitude = const Value.absent(),
    Value<String?> correctedPlaceName = const Value.absent(),
    Value<DateTime?> correctedAt = const Value.absent(),
  }) => DbConversationRecord(
    recordId: recordId ?? this.recordId,
    createdAt: createdAt ?? this.createdAt,
    collectorUserId: collectorUserId ?? this.collectorUserId,
    cityName: cityName ?? this.cityName,
    areaName: areaName ?? this.areaName,
    teamName: teamName ?? this.teamName,
    recorderName: recorderName ?? this.recorderName,
    personName: personName ?? this.personName,
    englishName: englishName ?? this.englishName,
    averageHeartRate: averageHeartRate.present
        ? averageHeartRate.value
        : this.averageHeartRate,
    latitude: latitude.present ? latitude.value : this.latitude,
    longitude: longitude.present ? longitude.value : this.longitude,
    locationAccuracyMeters: locationAccuracyMeters.present
        ? locationAccuracyMeters.value
        : this.locationAccuracyMeters,
    locationError: locationError.present
        ? locationError.value
        : this.locationError,
    manualPlaceName: manualPlaceName ?? this.manualPlaceName,
    gender: gender ?? this.gender,
    identity: identity ?? this.identity,
    ageRange: ageRange ?? this.ageRange,
    relationshipLevel: relationshipLevel ?? this.relationshipLevel,
    interestLevel: interestLevel ?? this.interestLevel,
    attitudeLevel: attitudeLevel ?? this.attitudeLevel,
    notes: notes ?? this.notes,
    isLocationVerified: isLocationVerified ?? this.isLocationVerified,
    correctedLatitude: correctedLatitude.present
        ? correctedLatitude.value
        : this.correctedLatitude,
    correctedLongitude: correctedLongitude.present
        ? correctedLongitude.value
        : this.correctedLongitude,
    correctedPlaceName: correctedPlaceName.present
        ? correctedPlaceName.value
        : this.correctedPlaceName,
    correctedAt: correctedAt.present ? correctedAt.value : this.correctedAt,
  );
  DbConversationRecord copyWithCompanion(DbConversationRecordsCompanion data) {
    return DbConversationRecord(
      recordId: data.recordId.present ? data.recordId.value : this.recordId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      collectorUserId: data.collectorUserId.present
          ? data.collectorUserId.value
          : this.collectorUserId,
      cityName: data.cityName.present ? data.cityName.value : this.cityName,
      areaName: data.areaName.present ? data.areaName.value : this.areaName,
      teamName: data.teamName.present ? data.teamName.value : this.teamName,
      recorderName: data.recorderName.present
          ? data.recorderName.value
          : this.recorderName,
      personName: data.personName.present
          ? data.personName.value
          : this.personName,
      englishName: data.englishName.present
          ? data.englishName.value
          : this.englishName,
      averageHeartRate: data.averageHeartRate.present
          ? data.averageHeartRate.value
          : this.averageHeartRate,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      locationAccuracyMeters: data.locationAccuracyMeters.present
          ? data.locationAccuracyMeters.value
          : this.locationAccuracyMeters,
      locationError: data.locationError.present
          ? data.locationError.value
          : this.locationError,
      manualPlaceName: data.manualPlaceName.present
          ? data.manualPlaceName.value
          : this.manualPlaceName,
      gender: data.gender.present ? data.gender.value : this.gender,
      identity: data.identity.present ? data.identity.value : this.identity,
      ageRange: data.ageRange.present ? data.ageRange.value : this.ageRange,
      relationshipLevel: data.relationshipLevel.present
          ? data.relationshipLevel.value
          : this.relationshipLevel,
      interestLevel: data.interestLevel.present
          ? data.interestLevel.value
          : this.interestLevel,
      attitudeLevel: data.attitudeLevel.present
          ? data.attitudeLevel.value
          : this.attitudeLevel,
      notes: data.notes.present ? data.notes.value : this.notes,
      isLocationVerified: data.isLocationVerified.present
          ? data.isLocationVerified.value
          : this.isLocationVerified,
      correctedLatitude: data.correctedLatitude.present
          ? data.correctedLatitude.value
          : this.correctedLatitude,
      correctedLongitude: data.correctedLongitude.present
          ? data.correctedLongitude.value
          : this.correctedLongitude,
      correctedPlaceName: data.correctedPlaceName.present
          ? data.correctedPlaceName.value
          : this.correctedPlaceName,
      correctedAt: data.correctedAt.present
          ? data.correctedAt.value
          : this.correctedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbConversationRecord(')
          ..write('recordId: $recordId, ')
          ..write('createdAt: $createdAt, ')
          ..write('collectorUserId: $collectorUserId, ')
          ..write('cityName: $cityName, ')
          ..write('areaName: $areaName, ')
          ..write('teamName: $teamName, ')
          ..write('recorderName: $recorderName, ')
          ..write('personName: $personName, ')
          ..write('englishName: $englishName, ')
          ..write('averageHeartRate: $averageHeartRate, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('locationAccuracyMeters: $locationAccuracyMeters, ')
          ..write('locationError: $locationError, ')
          ..write('manualPlaceName: $manualPlaceName, ')
          ..write('gender: $gender, ')
          ..write('identity: $identity, ')
          ..write('ageRange: $ageRange, ')
          ..write('relationshipLevel: $relationshipLevel, ')
          ..write('interestLevel: $interestLevel, ')
          ..write('attitudeLevel: $attitudeLevel, ')
          ..write('notes: $notes, ')
          ..write('isLocationVerified: $isLocationVerified, ')
          ..write('correctedLatitude: $correctedLatitude, ')
          ..write('correctedLongitude: $correctedLongitude, ')
          ..write('correctedPlaceName: $correctedPlaceName, ')
          ..write('correctedAt: $correctedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    recordId,
    createdAt,
    collectorUserId,
    cityName,
    areaName,
    teamName,
    recorderName,
    personName,
    englishName,
    averageHeartRate,
    latitude,
    longitude,
    locationAccuracyMeters,
    locationError,
    manualPlaceName,
    gender,
    identity,
    ageRange,
    relationshipLevel,
    interestLevel,
    attitudeLevel,
    notes,
    isLocationVerified,
    correctedLatitude,
    correctedLongitude,
    correctedPlaceName,
    correctedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbConversationRecord &&
          other.recordId == this.recordId &&
          other.createdAt == this.createdAt &&
          other.collectorUserId == this.collectorUserId &&
          other.cityName == this.cityName &&
          other.areaName == this.areaName &&
          other.teamName == this.teamName &&
          other.recorderName == this.recorderName &&
          other.personName == this.personName &&
          other.englishName == this.englishName &&
          other.averageHeartRate == this.averageHeartRate &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.locationAccuracyMeters == this.locationAccuracyMeters &&
          other.locationError == this.locationError &&
          other.manualPlaceName == this.manualPlaceName &&
          other.gender == this.gender &&
          other.identity == this.identity &&
          other.ageRange == this.ageRange &&
          other.relationshipLevel == this.relationshipLevel &&
          other.interestLevel == this.interestLevel &&
          other.attitudeLevel == this.attitudeLevel &&
          other.notes == this.notes &&
          other.isLocationVerified == this.isLocationVerified &&
          other.correctedLatitude == this.correctedLatitude &&
          other.correctedLongitude == this.correctedLongitude &&
          other.correctedPlaceName == this.correctedPlaceName &&
          other.correctedAt == this.correctedAt);
}

class DbConversationRecordsCompanion
    extends UpdateCompanion<DbConversationRecord> {
  final Value<String> recordId;
  final Value<DateTime> createdAt;
  final Value<String> collectorUserId;
  final Value<String> cityName;
  final Value<String> areaName;
  final Value<String> teamName;
  final Value<String> recorderName;
  final Value<String> personName;
  final Value<String> englishName;
  final Value<double?> averageHeartRate;
  final Value<double?> latitude;
  final Value<double?> longitude;
  final Value<double?> locationAccuracyMeters;
  final Value<String?> locationError;
  final Value<String> manualPlaceName;
  final Value<String> gender;
  final Value<String> identity;
  final Value<String> ageRange;
  final Value<int> relationshipLevel;
  final Value<int> interestLevel;
  final Value<int> attitudeLevel;
  final Value<String> notes;
  final Value<bool> isLocationVerified;
  final Value<double?> correctedLatitude;
  final Value<double?> correctedLongitude;
  final Value<String?> correctedPlaceName;
  final Value<DateTime?> correctedAt;
  final Value<int> rowid;
  const DbConversationRecordsCompanion({
    this.recordId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.collectorUserId = const Value.absent(),
    this.cityName = const Value.absent(),
    this.areaName = const Value.absent(),
    this.teamName = const Value.absent(),
    this.recorderName = const Value.absent(),
    this.personName = const Value.absent(),
    this.englishName = const Value.absent(),
    this.averageHeartRate = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.locationAccuracyMeters = const Value.absent(),
    this.locationError = const Value.absent(),
    this.manualPlaceName = const Value.absent(),
    this.gender = const Value.absent(),
    this.identity = const Value.absent(),
    this.ageRange = const Value.absent(),
    this.relationshipLevel = const Value.absent(),
    this.interestLevel = const Value.absent(),
    this.attitudeLevel = const Value.absent(),
    this.notes = const Value.absent(),
    this.isLocationVerified = const Value.absent(),
    this.correctedLatitude = const Value.absent(),
    this.correctedLongitude = const Value.absent(),
    this.correctedPlaceName = const Value.absent(),
    this.correctedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DbConversationRecordsCompanion.insert({
    required String recordId,
    required DateTime createdAt,
    required String collectorUserId,
    required String cityName,
    this.areaName = const Value.absent(),
    required String teamName,
    required String recorderName,
    required String personName,
    required String englishName,
    this.averageHeartRate = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.locationAccuracyMeters = const Value.absent(),
    this.locationError = const Value.absent(),
    required String manualPlaceName,
    required String gender,
    required String identity,
    required String ageRange,
    this.relationshipLevel = const Value.absent(),
    this.interestLevel = const Value.absent(),
    required int attitudeLevel,
    required String notes,
    this.isLocationVerified = const Value.absent(),
    this.correctedLatitude = const Value.absent(),
    this.correctedLongitude = const Value.absent(),
    this.correctedPlaceName = const Value.absent(),
    this.correctedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : recordId = Value(recordId),
       createdAt = Value(createdAt),
       collectorUserId = Value(collectorUserId),
       cityName = Value(cityName),
       teamName = Value(teamName),
       recorderName = Value(recorderName),
       personName = Value(personName),
       englishName = Value(englishName),
       manualPlaceName = Value(manualPlaceName),
       gender = Value(gender),
       identity = Value(identity),
       ageRange = Value(ageRange),
       attitudeLevel = Value(attitudeLevel),
       notes = Value(notes);
  static Insertable<DbConversationRecord> custom({
    Expression<String>? recordId,
    Expression<DateTime>? createdAt,
    Expression<String>? collectorUserId,
    Expression<String>? cityName,
    Expression<String>? areaName,
    Expression<String>? teamName,
    Expression<String>? recorderName,
    Expression<String>? personName,
    Expression<String>? englishName,
    Expression<double>? averageHeartRate,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<double>? locationAccuracyMeters,
    Expression<String>? locationError,
    Expression<String>? manualPlaceName,
    Expression<String>? gender,
    Expression<String>? identity,
    Expression<String>? ageRange,
    Expression<int>? relationshipLevel,
    Expression<int>? interestLevel,
    Expression<int>? attitudeLevel,
    Expression<String>? notes,
    Expression<bool>? isLocationVerified,
    Expression<double>? correctedLatitude,
    Expression<double>? correctedLongitude,
    Expression<String>? correctedPlaceName,
    Expression<DateTime>? correctedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (recordId != null) 'record_id': recordId,
      if (createdAt != null) 'created_at': createdAt,
      if (collectorUserId != null) 'collector_user_id': collectorUserId,
      if (cityName != null) 'city_name': cityName,
      if (areaName != null) 'area_name': areaName,
      if (teamName != null) 'team_name': teamName,
      if (recorderName != null) 'recorder_name': recorderName,
      if (personName != null) 'person_name': personName,
      if (englishName != null) 'english_name': englishName,
      if (averageHeartRate != null) 'average_heart_rate': averageHeartRate,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (locationAccuracyMeters != null)
        'location_accuracy_meters': locationAccuracyMeters,
      if (locationError != null) 'location_error': locationError,
      if (manualPlaceName != null) 'manual_place_name': manualPlaceName,
      if (gender != null) 'gender': gender,
      if (identity != null) 'identity': identity,
      if (ageRange != null) 'age_range': ageRange,
      if (relationshipLevel != null) 'relationship_level': relationshipLevel,
      if (interestLevel != null) 'interest_level': interestLevel,
      if (attitudeLevel != null) 'attitude_level': attitudeLevel,
      if (notes != null) 'notes': notes,
      if (isLocationVerified != null)
        'is_location_verified': isLocationVerified,
      if (correctedLatitude != null) 'corrected_latitude': correctedLatitude,
      if (correctedLongitude != null) 'corrected_longitude': correctedLongitude,
      if (correctedPlaceName != null)
        'corrected_place_name': correctedPlaceName,
      if (correctedAt != null) 'corrected_at': correctedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DbConversationRecordsCompanion copyWith({
    Value<String>? recordId,
    Value<DateTime>? createdAt,
    Value<String>? collectorUserId,
    Value<String>? cityName,
    Value<String>? areaName,
    Value<String>? teamName,
    Value<String>? recorderName,
    Value<String>? personName,
    Value<String>? englishName,
    Value<double?>? averageHeartRate,
    Value<double?>? latitude,
    Value<double?>? longitude,
    Value<double?>? locationAccuracyMeters,
    Value<String?>? locationError,
    Value<String>? manualPlaceName,
    Value<String>? gender,
    Value<String>? identity,
    Value<String>? ageRange,
    Value<int>? relationshipLevel,
    Value<int>? interestLevel,
    Value<int>? attitudeLevel,
    Value<String>? notes,
    Value<bool>? isLocationVerified,
    Value<double?>? correctedLatitude,
    Value<double?>? correctedLongitude,
    Value<String?>? correctedPlaceName,
    Value<DateTime?>? correctedAt,
    Value<int>? rowid,
  }) {
    return DbConversationRecordsCompanion(
      recordId: recordId ?? this.recordId,
      createdAt: createdAt ?? this.createdAt,
      collectorUserId: collectorUserId ?? this.collectorUserId,
      cityName: cityName ?? this.cityName,
      areaName: areaName ?? this.areaName,
      teamName: teamName ?? this.teamName,
      recorderName: recorderName ?? this.recorderName,
      personName: personName ?? this.personName,
      englishName: englishName ?? this.englishName,
      averageHeartRate: averageHeartRate ?? this.averageHeartRate,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      locationAccuracyMeters:
          locationAccuracyMeters ?? this.locationAccuracyMeters,
      locationError: locationError ?? this.locationError,
      manualPlaceName: manualPlaceName ?? this.manualPlaceName,
      gender: gender ?? this.gender,
      identity: identity ?? this.identity,
      ageRange: ageRange ?? this.ageRange,
      relationshipLevel: relationshipLevel ?? this.relationshipLevel,
      interestLevel: interestLevel ?? this.interestLevel,
      attitudeLevel: attitudeLevel ?? this.attitudeLevel,
      notes: notes ?? this.notes,
      isLocationVerified: isLocationVerified ?? this.isLocationVerified,
      correctedLatitude: correctedLatitude ?? this.correctedLatitude,
      correctedLongitude: correctedLongitude ?? this.correctedLongitude,
      correctedPlaceName: correctedPlaceName ?? this.correctedPlaceName,
      correctedAt: correctedAt ?? this.correctedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (recordId.present) {
      map['record_id'] = Variable<String>(recordId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (collectorUserId.present) {
      map['collector_user_id'] = Variable<String>(collectorUserId.value);
    }
    if (cityName.present) {
      map['city_name'] = Variable<String>(cityName.value);
    }
    if (areaName.present) {
      map['area_name'] = Variable<String>(areaName.value);
    }
    if (teamName.present) {
      map['team_name'] = Variable<String>(teamName.value);
    }
    if (recorderName.present) {
      map['recorder_name'] = Variable<String>(recorderName.value);
    }
    if (personName.present) {
      map['person_name'] = Variable<String>(personName.value);
    }
    if (englishName.present) {
      map['english_name'] = Variable<String>(englishName.value);
    }
    if (averageHeartRate.present) {
      map['average_heart_rate'] = Variable<double>(averageHeartRate.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (locationAccuracyMeters.present) {
      map['location_accuracy_meters'] = Variable<double>(
        locationAccuracyMeters.value,
      );
    }
    if (locationError.present) {
      map['location_error'] = Variable<String>(locationError.value);
    }
    if (manualPlaceName.present) {
      map['manual_place_name'] = Variable<String>(manualPlaceName.value);
    }
    if (gender.present) {
      map['gender'] = Variable<String>(gender.value);
    }
    if (identity.present) {
      map['identity'] = Variable<String>(identity.value);
    }
    if (ageRange.present) {
      map['age_range'] = Variable<String>(ageRange.value);
    }
    if (relationshipLevel.present) {
      map['relationship_level'] = Variable<int>(relationshipLevel.value);
    }
    if (interestLevel.present) {
      map['interest_level'] = Variable<int>(interestLevel.value);
    }
    if (attitudeLevel.present) {
      map['attitude_level'] = Variable<int>(attitudeLevel.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (isLocationVerified.present) {
      map['is_location_verified'] = Variable<bool>(isLocationVerified.value);
    }
    if (correctedLatitude.present) {
      map['corrected_latitude'] = Variable<double>(correctedLatitude.value);
    }
    if (correctedLongitude.present) {
      map['corrected_longitude'] = Variable<double>(correctedLongitude.value);
    }
    if (correctedPlaceName.present) {
      map['corrected_place_name'] = Variable<String>(correctedPlaceName.value);
    }
    if (correctedAt.present) {
      map['corrected_at'] = Variable<DateTime>(correctedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DbConversationRecordsCompanion(')
          ..write('recordId: $recordId, ')
          ..write('createdAt: $createdAt, ')
          ..write('collectorUserId: $collectorUserId, ')
          ..write('cityName: $cityName, ')
          ..write('areaName: $areaName, ')
          ..write('teamName: $teamName, ')
          ..write('recorderName: $recorderName, ')
          ..write('personName: $personName, ')
          ..write('englishName: $englishName, ')
          ..write('averageHeartRate: $averageHeartRate, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('locationAccuracyMeters: $locationAccuracyMeters, ')
          ..write('locationError: $locationError, ')
          ..write('manualPlaceName: $manualPlaceName, ')
          ..write('gender: $gender, ')
          ..write('identity: $identity, ')
          ..write('ageRange: $ageRange, ')
          ..write('relationshipLevel: $relationshipLevel, ')
          ..write('interestLevel: $interestLevel, ')
          ..write('attitudeLevel: $attitudeLevel, ')
          ..write('notes: $notes, ')
          ..write('isLocationVerified: $isLocationVerified, ')
          ..write('correctedLatitude: $correctedLatitude, ')
          ..write('correctedLongitude: $correctedLongitude, ')
          ..write('correctedPlaceName: $correctedPlaceName, ')
          ..write('correctedAt: $correctedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DbRecordContactsTable extends DbRecordContacts
    with TableInfo<$DbRecordContactsTable, DbRecordContact> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DbRecordContactsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _contactIdMeta = const VerificationMeta(
    'contactId',
  );
  @override
  late final GeneratedColumn<String> contactId = GeneratedColumn<String>(
    'contact_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recordIdMeta = const VerificationMeta(
    'recordId',
  );
  @override
  late final GeneratedColumn<String> recordId = GeneratedColumn<String>(
    'record_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _channelMeta = const VerificationMeta(
    'channel',
  );
  @override
  late final GeneratedColumn<String> channel = GeneratedColumn<String>(
    'channel',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    contactId,
    recordId,
    channel,
    value,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'db_record_contacts';
  @override
  VerificationContext validateIntegrity(
    Insertable<DbRecordContact> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('contact_id')) {
      context.handle(
        _contactIdMeta,
        contactId.isAcceptableOrUnknown(data['contact_id']!, _contactIdMeta),
      );
    } else if (isInserting) {
      context.missing(_contactIdMeta);
    }
    if (data.containsKey('record_id')) {
      context.handle(
        _recordIdMeta,
        recordId.isAcceptableOrUnknown(data['record_id']!, _recordIdMeta),
      );
    } else if (isInserting) {
      context.missing(_recordIdMeta);
    }
    if (data.containsKey('channel')) {
      context.handle(
        _channelMeta,
        channel.isAcceptableOrUnknown(data['channel']!, _channelMeta),
      );
    } else if (isInserting) {
      context.missing(_channelMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {contactId};
  @override
  DbRecordContact map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbRecordContact(
      contactId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}contact_id'],
      )!,
      recordId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}record_id'],
      )!,
      channel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}channel'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $DbRecordContactsTable createAlias(String alias) {
    return $DbRecordContactsTable(attachedDatabase, alias);
  }
}

class DbRecordContact extends DataClass implements Insertable<DbRecordContact> {
  final String contactId;
  final String recordId;
  final String channel;
  final String value;
  final DateTime createdAt;
  const DbRecordContact({
    required this.contactId,
    required this.recordId,
    required this.channel,
    required this.value,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['contact_id'] = Variable<String>(contactId);
    map['record_id'] = Variable<String>(recordId);
    map['channel'] = Variable<String>(channel);
    map['value'] = Variable<String>(value);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  DbRecordContactsCompanion toCompanion(bool nullToAbsent) {
    return DbRecordContactsCompanion(
      contactId: Value(contactId),
      recordId: Value(recordId),
      channel: Value(channel),
      value: Value(value),
      createdAt: Value(createdAt),
    );
  }

  factory DbRecordContact.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbRecordContact(
      contactId: serializer.fromJson<String>(json['contactId']),
      recordId: serializer.fromJson<String>(json['recordId']),
      channel: serializer.fromJson<String>(json['channel']),
      value: serializer.fromJson<String>(json['value']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'contactId': serializer.toJson<String>(contactId),
      'recordId': serializer.toJson<String>(recordId),
      'channel': serializer.toJson<String>(channel),
      'value': serializer.toJson<String>(value),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  DbRecordContact copyWith({
    String? contactId,
    String? recordId,
    String? channel,
    String? value,
    DateTime? createdAt,
  }) => DbRecordContact(
    contactId: contactId ?? this.contactId,
    recordId: recordId ?? this.recordId,
    channel: channel ?? this.channel,
    value: value ?? this.value,
    createdAt: createdAt ?? this.createdAt,
  );
  DbRecordContact copyWithCompanion(DbRecordContactsCompanion data) {
    return DbRecordContact(
      contactId: data.contactId.present ? data.contactId.value : this.contactId,
      recordId: data.recordId.present ? data.recordId.value : this.recordId,
      channel: data.channel.present ? data.channel.value : this.channel,
      value: data.value.present ? data.value.value : this.value,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbRecordContact(')
          ..write('contactId: $contactId, ')
          ..write('recordId: $recordId, ')
          ..write('channel: $channel, ')
          ..write('value: $value, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(contactId, recordId, channel, value, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbRecordContact &&
          other.contactId == this.contactId &&
          other.recordId == this.recordId &&
          other.channel == this.channel &&
          other.value == this.value &&
          other.createdAt == this.createdAt);
}

class DbRecordContactsCompanion extends UpdateCompanion<DbRecordContact> {
  final Value<String> contactId;
  final Value<String> recordId;
  final Value<String> channel;
  final Value<String> value;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const DbRecordContactsCompanion({
    this.contactId = const Value.absent(),
    this.recordId = const Value.absent(),
    this.channel = const Value.absent(),
    this.value = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DbRecordContactsCompanion.insert({
    required String contactId,
    required String recordId,
    required String channel,
    required String value,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : contactId = Value(contactId),
       recordId = Value(recordId),
       channel = Value(channel),
       value = Value(value),
       createdAt = Value(createdAt);
  static Insertable<DbRecordContact> custom({
    Expression<String>? contactId,
    Expression<String>? recordId,
    Expression<String>? channel,
    Expression<String>? value,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (contactId != null) 'contact_id': contactId,
      if (recordId != null) 'record_id': recordId,
      if (channel != null) 'channel': channel,
      if (value != null) 'value': value,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DbRecordContactsCompanion copyWith({
    Value<String>? contactId,
    Value<String>? recordId,
    Value<String>? channel,
    Value<String>? value,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return DbRecordContactsCompanion(
      contactId: contactId ?? this.contactId,
      recordId: recordId ?? this.recordId,
      channel: channel ?? this.channel,
      value: value ?? this.value,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (contactId.present) {
      map['contact_id'] = Variable<String>(contactId.value);
    }
    if (recordId.present) {
      map['record_id'] = Variable<String>(recordId.value);
    }
    if (channel.present) {
      map['channel'] = Variable<String>(channel.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DbRecordContactsCompanion(')
          ..write('contactId: $contactId, ')
          ..write('recordId: $recordId, ')
          ..write('channel: $channel, ')
          ..write('value: $value, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DbAppSettingsTable extends DbAppSettings
    with TableInfo<$DbAppSettingsTable, DbAppSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DbAppSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'db_app_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<DbAppSetting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  DbAppSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbAppSetting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $DbAppSettingsTable createAlias(String alias) {
    return $DbAppSettingsTable(attachedDatabase, alias);
  }
}

class DbAppSetting extends DataClass implements Insertable<DbAppSetting> {
  final String key;
  final String value;
  const DbAppSetting({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  DbAppSettingsCompanion toCompanion(bool nullToAbsent) {
    return DbAppSettingsCompanion(key: Value(key), value: Value(value));
  }

  factory DbAppSetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbAppSetting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  DbAppSetting copyWith({String? key, String? value}) =>
      DbAppSetting(key: key ?? this.key, value: value ?? this.value);
  DbAppSetting copyWithCompanion(DbAppSettingsCompanion data) {
    return DbAppSetting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbAppSetting(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbAppSetting &&
          other.key == this.key &&
          other.value == this.value);
}

class DbAppSettingsCompanion extends UpdateCompanion<DbAppSetting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const DbAppSettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DbAppSettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<DbAppSetting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DbAppSettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return DbAppSettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DbAppSettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DbSecurityEventsTable extends DbSecurityEvents
    with TableInfo<$DbSecurityEventsTable, DbSecurityEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DbSecurityEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _eventIdMeta = const VerificationMeta(
    'eventId',
  );
  @override
  late final GeneratedColumn<String> eventId = GeneratedColumn<String>(
    'event_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _eventTypeMeta = const VerificationMeta(
    'eventType',
  );
  @override
  late final GeneratedColumn<String> eventType = GeneratedColumn<String>(
    'event_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _eventDetailJsonMeta = const VerificationMeta(
    'eventDetailJson',
  );
  @override
  late final GeneratedColumn<String> eventDetailJson = GeneratedColumn<String>(
    'event_detail_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    eventId,
    userId,
    eventType,
    eventDetailJson,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'db_security_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<DbSecurityEvent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('event_id')) {
      context.handle(
        _eventIdMeta,
        eventId.isAcceptableOrUnknown(data['event_id']!, _eventIdMeta),
      );
    } else if (isInserting) {
      context.missing(_eventIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    }
    if (data.containsKey('event_type')) {
      context.handle(
        _eventTypeMeta,
        eventType.isAcceptableOrUnknown(data['event_type']!, _eventTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_eventTypeMeta);
    }
    if (data.containsKey('event_detail_json')) {
      context.handle(
        _eventDetailJsonMeta,
        eventDetailJson.isAcceptableOrUnknown(
          data['event_detail_json']!,
          _eventDetailJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_eventDetailJsonMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {eventId};
  @override
  DbSecurityEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbSecurityEvent(
      eventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      ),
      eventType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_type'],
      )!,
      eventDetailJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_detail_json'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $DbSecurityEventsTable createAlias(String alias) {
    return $DbSecurityEventsTable(attachedDatabase, alias);
  }
}

class DbSecurityEvent extends DataClass implements Insertable<DbSecurityEvent> {
  final String eventId;
  final String? userId;
  final String eventType;
  final String eventDetailJson;
  final DateTime createdAt;
  const DbSecurityEvent({
    required this.eventId,
    this.userId,
    required this.eventType,
    required this.eventDetailJson,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['event_id'] = Variable<String>(eventId);
    if (!nullToAbsent || userId != null) {
      map['user_id'] = Variable<String>(userId);
    }
    map['event_type'] = Variable<String>(eventType);
    map['event_detail_json'] = Variable<String>(eventDetailJson);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  DbSecurityEventsCompanion toCompanion(bool nullToAbsent) {
    return DbSecurityEventsCompanion(
      eventId: Value(eventId),
      userId: userId == null && nullToAbsent
          ? const Value.absent()
          : Value(userId),
      eventType: Value(eventType),
      eventDetailJson: Value(eventDetailJson),
      createdAt: Value(createdAt),
    );
  }

  factory DbSecurityEvent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbSecurityEvent(
      eventId: serializer.fromJson<String>(json['eventId']),
      userId: serializer.fromJson<String?>(json['userId']),
      eventType: serializer.fromJson<String>(json['eventType']),
      eventDetailJson: serializer.fromJson<String>(json['eventDetailJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'eventId': serializer.toJson<String>(eventId),
      'userId': serializer.toJson<String?>(userId),
      'eventType': serializer.toJson<String>(eventType),
      'eventDetailJson': serializer.toJson<String>(eventDetailJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  DbSecurityEvent copyWith({
    String? eventId,
    Value<String?> userId = const Value.absent(),
    String? eventType,
    String? eventDetailJson,
    DateTime? createdAt,
  }) => DbSecurityEvent(
    eventId: eventId ?? this.eventId,
    userId: userId.present ? userId.value : this.userId,
    eventType: eventType ?? this.eventType,
    eventDetailJson: eventDetailJson ?? this.eventDetailJson,
    createdAt: createdAt ?? this.createdAt,
  );
  DbSecurityEvent copyWithCompanion(DbSecurityEventsCompanion data) {
    return DbSecurityEvent(
      eventId: data.eventId.present ? data.eventId.value : this.eventId,
      userId: data.userId.present ? data.userId.value : this.userId,
      eventType: data.eventType.present ? data.eventType.value : this.eventType,
      eventDetailJson: data.eventDetailJson.present
          ? data.eventDetailJson.value
          : this.eventDetailJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbSecurityEvent(')
          ..write('eventId: $eventId, ')
          ..write('userId: $userId, ')
          ..write('eventType: $eventType, ')
          ..write('eventDetailJson: $eventDetailJson, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(eventId, userId, eventType, eventDetailJson, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbSecurityEvent &&
          other.eventId == this.eventId &&
          other.userId == this.userId &&
          other.eventType == this.eventType &&
          other.eventDetailJson == this.eventDetailJson &&
          other.createdAt == this.createdAt);
}

class DbSecurityEventsCompanion extends UpdateCompanion<DbSecurityEvent> {
  final Value<String> eventId;
  final Value<String?> userId;
  final Value<String> eventType;
  final Value<String> eventDetailJson;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const DbSecurityEventsCompanion({
    this.eventId = const Value.absent(),
    this.userId = const Value.absent(),
    this.eventType = const Value.absent(),
    this.eventDetailJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DbSecurityEventsCompanion.insert({
    required String eventId,
    this.userId = const Value.absent(),
    required String eventType,
    required String eventDetailJson,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : eventId = Value(eventId),
       eventType = Value(eventType),
       eventDetailJson = Value(eventDetailJson),
       createdAt = Value(createdAt);
  static Insertable<DbSecurityEvent> custom({
    Expression<String>? eventId,
    Expression<String>? userId,
    Expression<String>? eventType,
    Expression<String>? eventDetailJson,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (eventId != null) 'event_id': eventId,
      if (userId != null) 'user_id': userId,
      if (eventType != null) 'event_type': eventType,
      if (eventDetailJson != null) 'event_detail_json': eventDetailJson,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DbSecurityEventsCompanion copyWith({
    Value<String>? eventId,
    Value<String?>? userId,
    Value<String>? eventType,
    Value<String>? eventDetailJson,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return DbSecurityEventsCompanion(
      eventId: eventId ?? this.eventId,
      userId: userId ?? this.userId,
      eventType: eventType ?? this.eventType,
      eventDetailJson: eventDetailJson ?? this.eventDetailJson,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (eventId.present) {
      map['event_id'] = Variable<String>(eventId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (eventType.present) {
      map['event_type'] = Variable<String>(eventType.value);
    }
    if (eventDetailJson.present) {
      map['event_detail_json'] = Variable<String>(eventDetailJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DbSecurityEventsCompanion(')
          ..write('eventId: $eventId, ')
          ..write('userId: $userId, ')
          ..write('eventType: $eventType, ')
          ..write('eventDetailJson: $eventDetailJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$LocalDatabase extends GeneratedDatabase {
  _$LocalDatabase(QueryExecutor e) : super(e);
  $LocalDatabaseManager get managers => $LocalDatabaseManager(this);
  late final $DbUsersTable dbUsers = $DbUsersTable(this);
  late final $DbConversationRecordsTable dbConversationRecords =
      $DbConversationRecordsTable(this);
  late final $DbRecordContactsTable dbRecordContacts = $DbRecordContactsTable(
    this,
  );
  late final $DbAppSettingsTable dbAppSettings = $DbAppSettingsTable(this);
  late final $DbSecurityEventsTable dbSecurityEvents = $DbSecurityEventsTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    dbUsers,
    dbConversationRecords,
    dbRecordContacts,
    dbAppSettings,
    dbSecurityEvents,
  ];
}

typedef $$DbUsersTableCreateCompanionBuilder =
    DbUsersCompanion Function({
      required String userId,
      required String username,
      required String displayName,
      required String email,
      required String phone,
      Value<DateTime?> birthday,
      Value<String> gender,
      Value<String> occupation,
      Value<String> contactJson,
      required int roleLevel,
      required String cityNamesJson,
      required String teamName,
      required String passwordMd5,
      required String status,
      Value<int> failedLoginCount,
      Value<bool> mustChangePassword,
      Value<DateTime?> lockedUntil,
      Value<DateTime?> lastSeenAt,
      Value<DateTime?> lastFailedLoginAt,
      Value<int> rowid,
    });
typedef $$DbUsersTableUpdateCompanionBuilder =
    DbUsersCompanion Function({
      Value<String> userId,
      Value<String> username,
      Value<String> displayName,
      Value<String> email,
      Value<String> phone,
      Value<DateTime?> birthday,
      Value<String> gender,
      Value<String> occupation,
      Value<String> contactJson,
      Value<int> roleLevel,
      Value<String> cityNamesJson,
      Value<String> teamName,
      Value<String> passwordMd5,
      Value<String> status,
      Value<int> failedLoginCount,
      Value<bool> mustChangePassword,
      Value<DateTime?> lockedUntil,
      Value<DateTime?> lastSeenAt,
      Value<DateTime?> lastFailedLoginAt,
      Value<int> rowid,
    });

class $$DbUsersTableFilterComposer
    extends Composer<_$LocalDatabase, $DbUsersTable> {
  $$DbUsersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get birthday => $composableBuilder(
    column: $table.birthday,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get gender => $composableBuilder(
    column: $table.gender,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get occupation => $composableBuilder(
    column: $table.occupation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contactJson => $composableBuilder(
    column: $table.contactJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get roleLevel => $composableBuilder(
    column: $table.roleLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cityNamesJson => $composableBuilder(
    column: $table.cityNamesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get teamName => $composableBuilder(
    column: $table.teamName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get passwordMd5 => $composableBuilder(
    column: $table.passwordMd5,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get failedLoginCount => $composableBuilder(
    column: $table.failedLoginCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get mustChangePassword => $composableBuilder(
    column: $table.mustChangePassword,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lockedUntil => $composableBuilder(
    column: $table.lockedUntil,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastFailedLoginAt => $composableBuilder(
    column: $table.lastFailedLoginAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DbUsersTableOrderingComposer
    extends Composer<_$LocalDatabase, $DbUsersTable> {
  $$DbUsersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get birthday => $composableBuilder(
    column: $table.birthday,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get gender => $composableBuilder(
    column: $table.gender,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get occupation => $composableBuilder(
    column: $table.occupation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contactJson => $composableBuilder(
    column: $table.contactJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get roleLevel => $composableBuilder(
    column: $table.roleLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cityNamesJson => $composableBuilder(
    column: $table.cityNamesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get teamName => $composableBuilder(
    column: $table.teamName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get passwordMd5 => $composableBuilder(
    column: $table.passwordMd5,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get failedLoginCount => $composableBuilder(
    column: $table.failedLoginCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get mustChangePassword => $composableBuilder(
    column: $table.mustChangePassword,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lockedUntil => $composableBuilder(
    column: $table.lockedUntil,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastFailedLoginAt => $composableBuilder(
    column: $table.lastFailedLoginAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DbUsersTableAnnotationComposer
    extends Composer<_$LocalDatabase, $DbUsersTable> {
  $$DbUsersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get email =>
      $composableBuilder(column: $table.email, builder: (column) => column);

  GeneratedColumn<String> get phone =>
      $composableBuilder(column: $table.phone, builder: (column) => column);

  GeneratedColumn<DateTime> get birthday =>
      $composableBuilder(column: $table.birthday, builder: (column) => column);

  GeneratedColumn<String> get gender =>
      $composableBuilder(column: $table.gender, builder: (column) => column);

  GeneratedColumn<String> get occupation => $composableBuilder(
    column: $table.occupation,
    builder: (column) => column,
  );

  GeneratedColumn<String> get contactJson => $composableBuilder(
    column: $table.contactJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get roleLevel =>
      $composableBuilder(column: $table.roleLevel, builder: (column) => column);

  GeneratedColumn<String> get cityNamesJson => $composableBuilder(
    column: $table.cityNamesJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get teamName =>
      $composableBuilder(column: $table.teamName, builder: (column) => column);

  GeneratedColumn<String> get passwordMd5 => $composableBuilder(
    column: $table.passwordMd5,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get failedLoginCount => $composableBuilder(
    column: $table.failedLoginCount,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get mustChangePassword => $composableBuilder(
    column: $table.mustChangePassword,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lockedUntil => $composableBuilder(
    column: $table.lockedUntil,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastFailedLoginAt => $composableBuilder(
    column: $table.lastFailedLoginAt,
    builder: (column) => column,
  );
}

class $$DbUsersTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $DbUsersTable,
          DbUser,
          $$DbUsersTableFilterComposer,
          $$DbUsersTableOrderingComposer,
          $$DbUsersTableAnnotationComposer,
          $$DbUsersTableCreateCompanionBuilder,
          $$DbUsersTableUpdateCompanionBuilder,
          (DbUser, BaseReferences<_$LocalDatabase, $DbUsersTable, DbUser>),
          DbUser,
          PrefetchHooks Function()
        > {
  $$DbUsersTableTableManager(_$LocalDatabase db, $DbUsersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DbUsersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DbUsersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DbUsersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<String> username = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<String> email = const Value.absent(),
                Value<String> phone = const Value.absent(),
                Value<DateTime?> birthday = const Value.absent(),
                Value<String> gender = const Value.absent(),
                Value<String> occupation = const Value.absent(),
                Value<String> contactJson = const Value.absent(),
                Value<int> roleLevel = const Value.absent(),
                Value<String> cityNamesJson = const Value.absent(),
                Value<String> teamName = const Value.absent(),
                Value<String> passwordMd5 = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> failedLoginCount = const Value.absent(),
                Value<bool> mustChangePassword = const Value.absent(),
                Value<DateTime?> lockedUntil = const Value.absent(),
                Value<DateTime?> lastSeenAt = const Value.absent(),
                Value<DateTime?> lastFailedLoginAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DbUsersCompanion(
                userId: userId,
                username: username,
                displayName: displayName,
                email: email,
                phone: phone,
                birthday: birthday,
                gender: gender,
                occupation: occupation,
                contactJson: contactJson,
                roleLevel: roleLevel,
                cityNamesJson: cityNamesJson,
                teamName: teamName,
                passwordMd5: passwordMd5,
                status: status,
                failedLoginCount: failedLoginCount,
                mustChangePassword: mustChangePassword,
                lockedUntil: lockedUntil,
                lastSeenAt: lastSeenAt,
                lastFailedLoginAt: lastFailedLoginAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required String username,
                required String displayName,
                required String email,
                required String phone,
                Value<DateTime?> birthday = const Value.absent(),
                Value<String> gender = const Value.absent(),
                Value<String> occupation = const Value.absent(),
                Value<String> contactJson = const Value.absent(),
                required int roleLevel,
                required String cityNamesJson,
                required String teamName,
                required String passwordMd5,
                required String status,
                Value<int> failedLoginCount = const Value.absent(),
                Value<bool> mustChangePassword = const Value.absent(),
                Value<DateTime?> lockedUntil = const Value.absent(),
                Value<DateTime?> lastSeenAt = const Value.absent(),
                Value<DateTime?> lastFailedLoginAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DbUsersCompanion.insert(
                userId: userId,
                username: username,
                displayName: displayName,
                email: email,
                phone: phone,
                birthday: birthday,
                gender: gender,
                occupation: occupation,
                contactJson: contactJson,
                roleLevel: roleLevel,
                cityNamesJson: cityNamesJson,
                teamName: teamName,
                passwordMd5: passwordMd5,
                status: status,
                failedLoginCount: failedLoginCount,
                mustChangePassword: mustChangePassword,
                lockedUntil: lockedUntil,
                lastSeenAt: lastSeenAt,
                lastFailedLoginAt: lastFailedLoginAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DbUsersTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $DbUsersTable,
      DbUser,
      $$DbUsersTableFilterComposer,
      $$DbUsersTableOrderingComposer,
      $$DbUsersTableAnnotationComposer,
      $$DbUsersTableCreateCompanionBuilder,
      $$DbUsersTableUpdateCompanionBuilder,
      (DbUser, BaseReferences<_$LocalDatabase, $DbUsersTable, DbUser>),
      DbUser,
      PrefetchHooks Function()
    >;
typedef $$DbConversationRecordsTableCreateCompanionBuilder =
    DbConversationRecordsCompanion Function({
      required String recordId,
      required DateTime createdAt,
      required String collectorUserId,
      required String cityName,
      Value<String> areaName,
      required String teamName,
      required String recorderName,
      required String personName,
      required String englishName,
      Value<double?> averageHeartRate,
      Value<double?> latitude,
      Value<double?> longitude,
      Value<double?> locationAccuracyMeters,
      Value<String?> locationError,
      required String manualPlaceName,
      required String gender,
      required String identity,
      required String ageRange,
      Value<int> relationshipLevel,
      Value<int> interestLevel,
      required int attitudeLevel,
      required String notes,
      Value<bool> isLocationVerified,
      Value<double?> correctedLatitude,
      Value<double?> correctedLongitude,
      Value<String?> correctedPlaceName,
      Value<DateTime?> correctedAt,
      Value<int> rowid,
    });
typedef $$DbConversationRecordsTableUpdateCompanionBuilder =
    DbConversationRecordsCompanion Function({
      Value<String> recordId,
      Value<DateTime> createdAt,
      Value<String> collectorUserId,
      Value<String> cityName,
      Value<String> areaName,
      Value<String> teamName,
      Value<String> recorderName,
      Value<String> personName,
      Value<String> englishName,
      Value<double?> averageHeartRate,
      Value<double?> latitude,
      Value<double?> longitude,
      Value<double?> locationAccuracyMeters,
      Value<String?> locationError,
      Value<String> manualPlaceName,
      Value<String> gender,
      Value<String> identity,
      Value<String> ageRange,
      Value<int> relationshipLevel,
      Value<int> interestLevel,
      Value<int> attitudeLevel,
      Value<String> notes,
      Value<bool> isLocationVerified,
      Value<double?> correctedLatitude,
      Value<double?> correctedLongitude,
      Value<String?> correctedPlaceName,
      Value<DateTime?> correctedAt,
      Value<int> rowid,
    });

class $$DbConversationRecordsTableFilterComposer
    extends Composer<_$LocalDatabase, $DbConversationRecordsTable> {
  $$DbConversationRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get recordId => $composableBuilder(
    column: $table.recordId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get collectorUserId => $composableBuilder(
    column: $table.collectorUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cityName => $composableBuilder(
    column: $table.cityName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get areaName => $composableBuilder(
    column: $table.areaName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get teamName => $composableBuilder(
    column: $table.teamName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recorderName => $composableBuilder(
    column: $table.recorderName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get personName => $composableBuilder(
    column: $table.personName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get englishName => $composableBuilder(
    column: $table.englishName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get averageHeartRate => $composableBuilder(
    column: $table.averageHeartRate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get locationAccuracyMeters => $composableBuilder(
    column: $table.locationAccuracyMeters,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get locationError => $composableBuilder(
    column: $table.locationError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get manualPlaceName => $composableBuilder(
    column: $table.manualPlaceName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get gender => $composableBuilder(
    column: $table.gender,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get identity => $composableBuilder(
    column: $table.identity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ageRange => $composableBuilder(
    column: $table.ageRange,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get relationshipLevel => $composableBuilder(
    column: $table.relationshipLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get interestLevel => $composableBuilder(
    column: $table.interestLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attitudeLevel => $composableBuilder(
    column: $table.attitudeLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isLocationVerified => $composableBuilder(
    column: $table.isLocationVerified,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get correctedLatitude => $composableBuilder(
    column: $table.correctedLatitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get correctedLongitude => $composableBuilder(
    column: $table.correctedLongitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get correctedPlaceName => $composableBuilder(
    column: $table.correctedPlaceName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get correctedAt => $composableBuilder(
    column: $table.correctedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DbConversationRecordsTableOrderingComposer
    extends Composer<_$LocalDatabase, $DbConversationRecordsTable> {
  $$DbConversationRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get recordId => $composableBuilder(
    column: $table.recordId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get collectorUserId => $composableBuilder(
    column: $table.collectorUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cityName => $composableBuilder(
    column: $table.cityName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get areaName => $composableBuilder(
    column: $table.areaName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get teamName => $composableBuilder(
    column: $table.teamName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recorderName => $composableBuilder(
    column: $table.recorderName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get personName => $composableBuilder(
    column: $table.personName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get englishName => $composableBuilder(
    column: $table.englishName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get averageHeartRate => $composableBuilder(
    column: $table.averageHeartRate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get locationAccuracyMeters => $composableBuilder(
    column: $table.locationAccuracyMeters,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get locationError => $composableBuilder(
    column: $table.locationError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get manualPlaceName => $composableBuilder(
    column: $table.manualPlaceName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get gender => $composableBuilder(
    column: $table.gender,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get identity => $composableBuilder(
    column: $table.identity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ageRange => $composableBuilder(
    column: $table.ageRange,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get relationshipLevel => $composableBuilder(
    column: $table.relationshipLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get interestLevel => $composableBuilder(
    column: $table.interestLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attitudeLevel => $composableBuilder(
    column: $table.attitudeLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isLocationVerified => $composableBuilder(
    column: $table.isLocationVerified,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get correctedLatitude => $composableBuilder(
    column: $table.correctedLatitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get correctedLongitude => $composableBuilder(
    column: $table.correctedLongitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get correctedPlaceName => $composableBuilder(
    column: $table.correctedPlaceName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get correctedAt => $composableBuilder(
    column: $table.correctedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DbConversationRecordsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $DbConversationRecordsTable> {
  $$DbConversationRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get recordId =>
      $composableBuilder(column: $table.recordId, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get collectorUserId => $composableBuilder(
    column: $table.collectorUserId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cityName =>
      $composableBuilder(column: $table.cityName, builder: (column) => column);

  GeneratedColumn<String> get areaName =>
      $composableBuilder(column: $table.areaName, builder: (column) => column);

  GeneratedColumn<String> get teamName =>
      $composableBuilder(column: $table.teamName, builder: (column) => column);

  GeneratedColumn<String> get recorderName => $composableBuilder(
    column: $table.recorderName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get personName => $composableBuilder(
    column: $table.personName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get englishName => $composableBuilder(
    column: $table.englishName,
    builder: (column) => column,
  );

  GeneratedColumn<double> get averageHeartRate => $composableBuilder(
    column: $table.averageHeartRate,
    builder: (column) => column,
  );

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<double> get locationAccuracyMeters => $composableBuilder(
    column: $table.locationAccuracyMeters,
    builder: (column) => column,
  );

  GeneratedColumn<String> get locationError => $composableBuilder(
    column: $table.locationError,
    builder: (column) => column,
  );

  GeneratedColumn<String> get manualPlaceName => $composableBuilder(
    column: $table.manualPlaceName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get gender =>
      $composableBuilder(column: $table.gender, builder: (column) => column);

  GeneratedColumn<String> get identity =>
      $composableBuilder(column: $table.identity, builder: (column) => column);

  GeneratedColumn<String> get ageRange =>
      $composableBuilder(column: $table.ageRange, builder: (column) => column);

  GeneratedColumn<int> get relationshipLevel => $composableBuilder(
    column: $table.relationshipLevel,
    builder: (column) => column,
  );

  GeneratedColumn<int> get interestLevel => $composableBuilder(
    column: $table.interestLevel,
    builder: (column) => column,
  );

  GeneratedColumn<int> get attitudeLevel => $composableBuilder(
    column: $table.attitudeLevel,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<bool> get isLocationVerified => $composableBuilder(
    column: $table.isLocationVerified,
    builder: (column) => column,
  );

  GeneratedColumn<double> get correctedLatitude => $composableBuilder(
    column: $table.correctedLatitude,
    builder: (column) => column,
  );

  GeneratedColumn<double> get correctedLongitude => $composableBuilder(
    column: $table.correctedLongitude,
    builder: (column) => column,
  );

  GeneratedColumn<String> get correctedPlaceName => $composableBuilder(
    column: $table.correctedPlaceName,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get correctedAt => $composableBuilder(
    column: $table.correctedAt,
    builder: (column) => column,
  );
}

class $$DbConversationRecordsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $DbConversationRecordsTable,
          DbConversationRecord,
          $$DbConversationRecordsTableFilterComposer,
          $$DbConversationRecordsTableOrderingComposer,
          $$DbConversationRecordsTableAnnotationComposer,
          $$DbConversationRecordsTableCreateCompanionBuilder,
          $$DbConversationRecordsTableUpdateCompanionBuilder,
          (
            DbConversationRecord,
            BaseReferences<
              _$LocalDatabase,
              $DbConversationRecordsTable,
              DbConversationRecord
            >,
          ),
          DbConversationRecord,
          PrefetchHooks Function()
        > {
  $$DbConversationRecordsTableTableManager(
    _$LocalDatabase db,
    $DbConversationRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DbConversationRecordsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$DbConversationRecordsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$DbConversationRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> recordId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<String> collectorUserId = const Value.absent(),
                Value<String> cityName = const Value.absent(),
                Value<String> areaName = const Value.absent(),
                Value<String> teamName = const Value.absent(),
                Value<String> recorderName = const Value.absent(),
                Value<String> personName = const Value.absent(),
                Value<String> englishName = const Value.absent(),
                Value<double?> averageHeartRate = const Value.absent(),
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                Value<double?> locationAccuracyMeters = const Value.absent(),
                Value<String?> locationError = const Value.absent(),
                Value<String> manualPlaceName = const Value.absent(),
                Value<String> gender = const Value.absent(),
                Value<String> identity = const Value.absent(),
                Value<String> ageRange = const Value.absent(),
                Value<int> relationshipLevel = const Value.absent(),
                Value<int> interestLevel = const Value.absent(),
                Value<int> attitudeLevel = const Value.absent(),
                Value<String> notes = const Value.absent(),
                Value<bool> isLocationVerified = const Value.absent(),
                Value<double?> correctedLatitude = const Value.absent(),
                Value<double?> correctedLongitude = const Value.absent(),
                Value<String?> correctedPlaceName = const Value.absent(),
                Value<DateTime?> correctedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DbConversationRecordsCompanion(
                recordId: recordId,
                createdAt: createdAt,
                collectorUserId: collectorUserId,
                cityName: cityName,
                areaName: areaName,
                teamName: teamName,
                recorderName: recorderName,
                personName: personName,
                englishName: englishName,
                averageHeartRate: averageHeartRate,
                latitude: latitude,
                longitude: longitude,
                locationAccuracyMeters: locationAccuracyMeters,
                locationError: locationError,
                manualPlaceName: manualPlaceName,
                gender: gender,
                identity: identity,
                ageRange: ageRange,
                relationshipLevel: relationshipLevel,
                interestLevel: interestLevel,
                attitudeLevel: attitudeLevel,
                notes: notes,
                isLocationVerified: isLocationVerified,
                correctedLatitude: correctedLatitude,
                correctedLongitude: correctedLongitude,
                correctedPlaceName: correctedPlaceName,
                correctedAt: correctedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String recordId,
                required DateTime createdAt,
                required String collectorUserId,
                required String cityName,
                Value<String> areaName = const Value.absent(),
                required String teamName,
                required String recorderName,
                required String personName,
                required String englishName,
                Value<double?> averageHeartRate = const Value.absent(),
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                Value<double?> locationAccuracyMeters = const Value.absent(),
                Value<String?> locationError = const Value.absent(),
                required String manualPlaceName,
                required String gender,
                required String identity,
                required String ageRange,
                Value<int> relationshipLevel = const Value.absent(),
                Value<int> interestLevel = const Value.absent(),
                required int attitudeLevel,
                required String notes,
                Value<bool> isLocationVerified = const Value.absent(),
                Value<double?> correctedLatitude = const Value.absent(),
                Value<double?> correctedLongitude = const Value.absent(),
                Value<String?> correctedPlaceName = const Value.absent(),
                Value<DateTime?> correctedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DbConversationRecordsCompanion.insert(
                recordId: recordId,
                createdAt: createdAt,
                collectorUserId: collectorUserId,
                cityName: cityName,
                areaName: areaName,
                teamName: teamName,
                recorderName: recorderName,
                personName: personName,
                englishName: englishName,
                averageHeartRate: averageHeartRate,
                latitude: latitude,
                longitude: longitude,
                locationAccuracyMeters: locationAccuracyMeters,
                locationError: locationError,
                manualPlaceName: manualPlaceName,
                gender: gender,
                identity: identity,
                ageRange: ageRange,
                relationshipLevel: relationshipLevel,
                interestLevel: interestLevel,
                attitudeLevel: attitudeLevel,
                notes: notes,
                isLocationVerified: isLocationVerified,
                correctedLatitude: correctedLatitude,
                correctedLongitude: correctedLongitude,
                correctedPlaceName: correctedPlaceName,
                correctedAt: correctedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DbConversationRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $DbConversationRecordsTable,
      DbConversationRecord,
      $$DbConversationRecordsTableFilterComposer,
      $$DbConversationRecordsTableOrderingComposer,
      $$DbConversationRecordsTableAnnotationComposer,
      $$DbConversationRecordsTableCreateCompanionBuilder,
      $$DbConversationRecordsTableUpdateCompanionBuilder,
      (
        DbConversationRecord,
        BaseReferences<
          _$LocalDatabase,
          $DbConversationRecordsTable,
          DbConversationRecord
        >,
      ),
      DbConversationRecord,
      PrefetchHooks Function()
    >;
typedef $$DbRecordContactsTableCreateCompanionBuilder =
    DbRecordContactsCompanion Function({
      required String contactId,
      required String recordId,
      required String channel,
      required String value,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$DbRecordContactsTableUpdateCompanionBuilder =
    DbRecordContactsCompanion Function({
      Value<String> contactId,
      Value<String> recordId,
      Value<String> channel,
      Value<String> value,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$DbRecordContactsTableFilterComposer
    extends Composer<_$LocalDatabase, $DbRecordContactsTable> {
  $$DbRecordContactsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get contactId => $composableBuilder(
    column: $table.contactId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recordId => $composableBuilder(
    column: $table.recordId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get channel => $composableBuilder(
    column: $table.channel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DbRecordContactsTableOrderingComposer
    extends Composer<_$LocalDatabase, $DbRecordContactsTable> {
  $$DbRecordContactsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get contactId => $composableBuilder(
    column: $table.contactId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recordId => $composableBuilder(
    column: $table.recordId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get channel => $composableBuilder(
    column: $table.channel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DbRecordContactsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $DbRecordContactsTable> {
  $$DbRecordContactsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get contactId =>
      $composableBuilder(column: $table.contactId, builder: (column) => column);

  GeneratedColumn<String> get recordId =>
      $composableBuilder(column: $table.recordId, builder: (column) => column);

  GeneratedColumn<String> get channel =>
      $composableBuilder(column: $table.channel, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$DbRecordContactsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $DbRecordContactsTable,
          DbRecordContact,
          $$DbRecordContactsTableFilterComposer,
          $$DbRecordContactsTableOrderingComposer,
          $$DbRecordContactsTableAnnotationComposer,
          $$DbRecordContactsTableCreateCompanionBuilder,
          $$DbRecordContactsTableUpdateCompanionBuilder,
          (
            DbRecordContact,
            BaseReferences<
              _$LocalDatabase,
              $DbRecordContactsTable,
              DbRecordContact
            >,
          ),
          DbRecordContact,
          PrefetchHooks Function()
        > {
  $$DbRecordContactsTableTableManager(
    _$LocalDatabase db,
    $DbRecordContactsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DbRecordContactsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DbRecordContactsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DbRecordContactsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> contactId = const Value.absent(),
                Value<String> recordId = const Value.absent(),
                Value<String> channel = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DbRecordContactsCompanion(
                contactId: contactId,
                recordId: recordId,
                channel: channel,
                value: value,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String contactId,
                required String recordId,
                required String channel,
                required String value,
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => DbRecordContactsCompanion.insert(
                contactId: contactId,
                recordId: recordId,
                channel: channel,
                value: value,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DbRecordContactsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $DbRecordContactsTable,
      DbRecordContact,
      $$DbRecordContactsTableFilterComposer,
      $$DbRecordContactsTableOrderingComposer,
      $$DbRecordContactsTableAnnotationComposer,
      $$DbRecordContactsTableCreateCompanionBuilder,
      $$DbRecordContactsTableUpdateCompanionBuilder,
      (
        DbRecordContact,
        BaseReferences<
          _$LocalDatabase,
          $DbRecordContactsTable,
          DbRecordContact
        >,
      ),
      DbRecordContact,
      PrefetchHooks Function()
    >;
typedef $$DbAppSettingsTableCreateCompanionBuilder =
    DbAppSettingsCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$DbAppSettingsTableUpdateCompanionBuilder =
    DbAppSettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$DbAppSettingsTableFilterComposer
    extends Composer<_$LocalDatabase, $DbAppSettingsTable> {
  $$DbAppSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DbAppSettingsTableOrderingComposer
    extends Composer<_$LocalDatabase, $DbAppSettingsTable> {
  $$DbAppSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DbAppSettingsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $DbAppSettingsTable> {
  $$DbAppSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$DbAppSettingsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $DbAppSettingsTable,
          DbAppSetting,
          $$DbAppSettingsTableFilterComposer,
          $$DbAppSettingsTableOrderingComposer,
          $$DbAppSettingsTableAnnotationComposer,
          $$DbAppSettingsTableCreateCompanionBuilder,
          $$DbAppSettingsTableUpdateCompanionBuilder,
          (
            DbAppSetting,
            BaseReferences<_$LocalDatabase, $DbAppSettingsTable, DbAppSetting>,
          ),
          DbAppSetting,
          PrefetchHooks Function()
        > {
  $$DbAppSettingsTableTableManager(
    _$LocalDatabase db,
    $DbAppSettingsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DbAppSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DbAppSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DbAppSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) =>
                  DbAppSettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => DbAppSettingsCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DbAppSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $DbAppSettingsTable,
      DbAppSetting,
      $$DbAppSettingsTableFilterComposer,
      $$DbAppSettingsTableOrderingComposer,
      $$DbAppSettingsTableAnnotationComposer,
      $$DbAppSettingsTableCreateCompanionBuilder,
      $$DbAppSettingsTableUpdateCompanionBuilder,
      (
        DbAppSetting,
        BaseReferences<_$LocalDatabase, $DbAppSettingsTable, DbAppSetting>,
      ),
      DbAppSetting,
      PrefetchHooks Function()
    >;
typedef $$DbSecurityEventsTableCreateCompanionBuilder =
    DbSecurityEventsCompanion Function({
      required String eventId,
      Value<String?> userId,
      required String eventType,
      required String eventDetailJson,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$DbSecurityEventsTableUpdateCompanionBuilder =
    DbSecurityEventsCompanion Function({
      Value<String> eventId,
      Value<String?> userId,
      Value<String> eventType,
      Value<String> eventDetailJson,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$DbSecurityEventsTableFilterComposer
    extends Composer<_$LocalDatabase, $DbSecurityEventsTable> {
  $$DbSecurityEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventType => $composableBuilder(
    column: $table.eventType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventDetailJson => $composableBuilder(
    column: $table.eventDetailJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DbSecurityEventsTableOrderingComposer
    extends Composer<_$LocalDatabase, $DbSecurityEventsTable> {
  $$DbSecurityEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventType => $composableBuilder(
    column: $table.eventType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventDetailJson => $composableBuilder(
    column: $table.eventDetailJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DbSecurityEventsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $DbSecurityEventsTable> {
  $$DbSecurityEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get eventId =>
      $composableBuilder(column: $table.eventId, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get eventType =>
      $composableBuilder(column: $table.eventType, builder: (column) => column);

  GeneratedColumn<String> get eventDetailJson => $composableBuilder(
    column: $table.eventDetailJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$DbSecurityEventsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $DbSecurityEventsTable,
          DbSecurityEvent,
          $$DbSecurityEventsTableFilterComposer,
          $$DbSecurityEventsTableOrderingComposer,
          $$DbSecurityEventsTableAnnotationComposer,
          $$DbSecurityEventsTableCreateCompanionBuilder,
          $$DbSecurityEventsTableUpdateCompanionBuilder,
          (
            DbSecurityEvent,
            BaseReferences<
              _$LocalDatabase,
              $DbSecurityEventsTable,
              DbSecurityEvent
            >,
          ),
          DbSecurityEvent,
          PrefetchHooks Function()
        > {
  $$DbSecurityEventsTableTableManager(
    _$LocalDatabase db,
    $DbSecurityEventsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DbSecurityEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DbSecurityEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DbSecurityEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> eventId = const Value.absent(),
                Value<String?> userId = const Value.absent(),
                Value<String> eventType = const Value.absent(),
                Value<String> eventDetailJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DbSecurityEventsCompanion(
                eventId: eventId,
                userId: userId,
                eventType: eventType,
                eventDetailJson: eventDetailJson,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String eventId,
                Value<String?> userId = const Value.absent(),
                required String eventType,
                required String eventDetailJson,
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => DbSecurityEventsCompanion.insert(
                eventId: eventId,
                userId: userId,
                eventType: eventType,
                eventDetailJson: eventDetailJson,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DbSecurityEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $DbSecurityEventsTable,
      DbSecurityEvent,
      $$DbSecurityEventsTableFilterComposer,
      $$DbSecurityEventsTableOrderingComposer,
      $$DbSecurityEventsTableAnnotationComposer,
      $$DbSecurityEventsTableCreateCompanionBuilder,
      $$DbSecurityEventsTableUpdateCompanionBuilder,
      (
        DbSecurityEvent,
        BaseReferences<
          _$LocalDatabase,
          $DbSecurityEventsTable,
          DbSecurityEvent
        >,
      ),
      DbSecurityEvent,
      PrefetchHooks Function()
    >;

class $LocalDatabaseManager {
  final _$LocalDatabase _db;
  $LocalDatabaseManager(this._db);
  $$DbUsersTableTableManager get dbUsers =>
      $$DbUsersTableTableManager(_db, _db.dbUsers);
  $$DbConversationRecordsTableTableManager get dbConversationRecords =>
      $$DbConversationRecordsTableTableManager(_db, _db.dbConversationRecords);
  $$DbRecordContactsTableTableManager get dbRecordContacts =>
      $$DbRecordContactsTableTableManager(_db, _db.dbRecordContacts);
  $$DbAppSettingsTableTableManager get dbAppSettings =>
      $$DbAppSettingsTableTableManager(_db, _db.dbAppSettings);
  $$DbSecurityEventsTableTableManager get dbSecurityEvents =>
      $$DbSecurityEventsTableTableManager(_db, _db.dbSecurityEvents);
}
