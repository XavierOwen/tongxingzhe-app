class AppUser {
  const AppUser({
    required this.userId,
    required this.username,
    required this.displayName,
    required this.email,
    required this.phone,
    required this.gender,
    required this.occupation,
    required this.contactJson,
    required this.roleLevel,
    required this.cityNames,
    required this.teamName,
    required this.passwordMd5,
    required this.status,
    required this.failedLoginCount,
    required this.mustChangePassword,
    this.lockedUntil,
    this.birthday,
    this.lastSeenAt,
    this.lastFailedLoginAt,
  });

  final String userId;
  final String username;
  final String displayName;
  final String email;
  final String phone;
  final String gender;
  final String occupation;
  final String contactJson;
  final int roleLevel;
  final List<String> cityNames;
  final String teamName;
  final String passwordMd5;
  final String status;
  final int failedLoginCount;
  final bool mustChangePassword;
  final DateTime? lockedUntil;
  final DateTime? birthday;
  final DateTime? lastSeenAt;
  final DateTime? lastFailedLoginAt;

  bool get isOrgAdmin => roleLevel >= 90;
  bool get isCityAdmin => roleLevel >= 70;
  bool get isActive => status == 'active';
  int? get age {
    final value = birthday;
    if (value == null) {
      return null;
    }
    final now = DateTime.now();
    var years = now.year - value.year;
    final birthdayPassed =
        now.month > value.month ||
        (now.month == value.month && now.day >= value.day);
    if (!birthdayPassed) {
      years--;
    }
    return years < 0 ? null : years;
  }

  String get ageBand {
    final years = age;
    if (years == null) {
      return 'unknown';
    }
    if (years < 25) {
      return 'under_25';
    }
    if (years < 35) {
      return '25_34';
    }
    if (years < 45) {
      return '35_44';
    }
    if (years < 60) {
      return '45_59';
    }
    return '60_plus';
  }

  String get primaryCity => cityNames.isEmpty ? 'Chicago, IL' : cityNames.first;

  bool canSeeCity(String cityName) {
    return isOrgAdmin || cityNames.contains(cityName);
  }

  AppUser copyWith({
    String? userId,
    String? username,
    String? displayName,
    String? email,
    String? phone,
    String? gender,
    String? occupation,
    String? contactJson,
    int? roleLevel,
    List<String>? cityNames,
    String? teamName,
    String? passwordMd5,
    String? status,
    int? failedLoginCount,
    bool? mustChangePassword,
    DateTime? lockedUntil,
    DateTime? birthday,
    DateTime? lastSeenAt,
    DateTime? lastFailedLoginAt,
    bool clearLockedUntil = false,
    bool clearLastFailedLoginAt = false,
  }) {
    return AppUser(
      userId: userId ?? this.userId,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      gender: gender ?? this.gender,
      occupation: occupation ?? this.occupation,
      contactJson: contactJson ?? this.contactJson,
      roleLevel: roleLevel ?? this.roleLevel,
      cityNames: cityNames ?? this.cityNames,
      teamName: teamName ?? this.teamName,
      passwordMd5: passwordMd5 ?? this.passwordMd5,
      status: status ?? this.status,
      failedLoginCount: failedLoginCount ?? this.failedLoginCount,
      mustChangePassword: mustChangePassword ?? this.mustChangePassword,
      lockedUntil: clearLockedUntil ? null : lockedUntil ?? this.lockedUntil,
      birthday: birthday ?? this.birthday,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      lastFailedLoginAt: clearLastFailedLoginAt
          ? null
          : lastFailedLoginAt ?? this.lastFailedLoginAt,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'userId': userId,
      'username': username,
      'displayName': displayName,
      'email': email,
      'phone': phone,
      'gender': gender,
      'occupation': occupation,
      'contactJson': contactJson,
      'roleLevel': roleLevel,
      'cityNames': cityNames,
      'teamName': teamName,
      'passwordMd5': passwordMd5,
      'status': status,
      'failedLoginCount': failedLoginCount,
      'mustChangePassword': mustChangePassword,
      'lockedUntil': lockedUntil?.toIso8601String(),
      'birthday': birthday?.toIso8601String(),
      'lastSeenAt': lastSeenAt?.toIso8601String(),
      'lastFailedLoginAt': lastFailedLoginAt?.toIso8601String(),
    };
  }

  factory AppUser.fromJson(Map<String, Object?> json) {
    return AppUser(
      userId: json['userId'] as String,
      username: json['username'] as String,
      displayName: json['displayName'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      gender: json['gender'] as String? ?? 'unknown',
      occupation: json['occupation'] as String? ?? '',
      contactJson: json['contactJson'] as String? ?? '{}',
      roleLevel: (json['roleLevel'] as num?)?.toInt() ?? 10,
      cityNames:
          (json['cityNames'] as List<dynamic>?)
              ?.map((city) => city.toString())
              .toList() ??
          const [],
      teamName: json['teamName'] as String? ?? '',
      passwordMd5: json['passwordMd5'] as String? ?? '',
      status: json['status'] as String? ?? 'active',
      failedLoginCount: (json['failedLoginCount'] as num?)?.toInt() ?? 0,
      mustChangePassword: json['mustChangePassword'] as bool? ?? false,
      lockedUntil: _toDate(json['lockedUntil']),
      birthday: _toDate(json['birthday']),
      lastSeenAt: _toDate(json['lastSeenAt']),
      lastFailedLoginAt: _toDate(json['lastFailedLoginAt']),
    );
  }

  static DateTime? _toDate(Object? value) {
    if (value == null) {
      return null;
    }
    return DateTime.tryParse(value.toString());
  }
}

class AuthResult {
  const AuthResult({
    required this.success,
    required this.messageKey,
    this.user,
    this.temporaryPassword,
    this.lockedUntil,
  });

  final bool success;
  final String messageKey;
  final AppUser? user;
  final String? temporaryPassword;
  final DateTime? lockedUntil;
}
