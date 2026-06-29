import 'dart:convert';

/// One contact row in the form.
///
/// In the future Snowflake schema this maps cleanly to a child table
/// (`record_contacts`). Keeping it as a Dart value object also makes the
/// dynamic "Add contact" UI much easier to reason about.
class ConversationContact {
  const ConversationContact({required this.channel, required this.value});

  final String channel;
  final String value;

  bool get isEmpty => value.trim().isEmpty || channel == 'none';

  Map<String, Object?> toJson() {
    return {'channel': channel, 'value': value};
  }

  factory ConversationContact.fromJson(Map<String, Object?> json) {
    return ConversationContact(
      channel: json['channel'] as String? ?? 'other',
      value: json['value'] as String? ?? '',
    );
  }
}

/// A single field conversation record.
///
/// This model is intentionally explicit instead of storing one large Map. That
/// gives beginners a useful rule of thumb: fields you filter, chart, or join on
/// should usually be first-class columns; flexible fields can be JSON/VARIANT.
/// The old prayer free-text field is intentionally absent, so the UI cannot
/// accidentally pass it into SQLite or future cloud sync.
class ConversationRecord {
  const ConversationRecord({
    required this.id,
    required this.createdAt,
    required this.collectorUserId,
    required this.cityName,
    required this.areaName,
    required this.teamName,
    required this.recorderName,
    required this.personName,
    required this.englishName,
    required this.gender,
    required this.identity,
    required this.ageRange,
    required this.relationshipLevel,
    required this.interestLevel,
    required this.contacts,
    required this.attitudeLevel,
    required this.manualPlaceName,
    required this.notes,
    required this.isLocationVerified,
    this.averageHeartRate,
    this.latitude,
    this.longitude,
    this.locationAccuracyMeters,
    this.locationError,
    this.correctedLatitude,
    this.correctedLongitude,
    this.correctedPlaceName,
    this.correctedAt,
  });

  final String id;
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
  final List<ConversationContact> contacts;
  final int attitudeLevel;
  // Keep optional narrative text in one place. Analytics should aggregate
  // structured fields like area, identity, and interest instead of this text.
  final String notes;
  final bool isLocationVerified;
  final double? correctedLatitude;
  final double? correctedLongitude;
  final String? correctedPlaceName;
  final DateTime? correctedAt;

  bool get hasCoordinates => latitude != null && longitude != null;

  String get attitudeKey {
    return switch (_clampAttitude(attitudeLevel)) {
      -2 => 'very_negative',
      -1 => 'negative',
      1 => 'positive',
      2 => 'very_positive',
      _ => 'neutral',
    };
  }

  String get relationshipKey {
    return switch (_clampRelationship(relationshipLevel)) {
      2 => 'familiar_contact',
      3 => 'very_interested',
      4 => 'companion',
      _ => 'new_contact',
    };
  }

  String get interestKey {
    return switch (_clampInterest(interestLevel)) {
      0 => 'rejected',
      1 => 'low',
      3 => 'interested',
      4 => 'high',
      _ => 'neutral',
    };
  }

  String get displayPersonName {
    final local = personName.trim();
    if (local.isNotEmpty) {
      return local;
    }
    return englishName.trim();
  }

  bool get needsLocationReview {
    if (isLocationVerified) {
      return false;
    }
    if (!hasCoordinates) {
      return true;
    }
    return (locationAccuracyMeters ?? 999) > 80;
  }

  double? get displayLatitude => correctedLatitude ?? latitude;
  double? get displayLongitude => correctedLongitude ?? longitude;

  String get displayPlaceName {
    final corrected = correctedPlaceName?.trim();
    if (corrected != null && corrected.isNotEmpty) {
      return corrected;
    }
    return manualPlaceName.trim();
  }

  ConversationRecord copyWith({
    String? id,
    DateTime? createdAt,
    String? collectorUserId,
    String? cityName,
    String? areaName,
    String? teamName,
    String? recorderName,
    String? personName,
    String? englishName,
    double? averageHeartRate,
    double? latitude,
    double? longitude,
    double? locationAccuracyMeters,
    String? locationError,
    String? manualPlaceName,
    String? gender,
    String? identity,
    String? ageRange,
    int? relationshipLevel,
    int? interestLevel,
    List<ConversationContact>? contacts,
    int? attitudeLevel,
    String? notes,
    bool? isLocationVerified,
    double? correctedLatitude,
    double? correctedLongitude,
    String? correctedPlaceName,
    DateTime? correctedAt,
    bool clearCorrectedLatitude = false,
    bool clearCorrectedLongitude = false,
    bool clearCorrectedPlaceName = false,
  }) {
    return ConversationRecord(
      id: id ?? this.id,
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
      relationshipLevel: _clampRelationship(
        relationshipLevel ?? this.relationshipLevel,
      ),
      interestLevel: _clampInterest(interestLevel ?? this.interestLevel),
      contacts: contacts ?? this.contacts,
      attitudeLevel: _clampAttitude(attitudeLevel ?? this.attitudeLevel),
      notes: notes ?? this.notes,
      isLocationVerified: isLocationVerified ?? this.isLocationVerified,
      correctedLatitude: clearCorrectedLatitude
          ? null
          : correctedLatitude ?? this.correctedLatitude,
      correctedLongitude: clearCorrectedLongitude
          ? null
          : correctedLongitude ?? this.correctedLongitude,
      correctedPlaceName: clearCorrectedPlaceName
          ? null
          : correctedPlaceName ?? this.correctedPlaceName,
      correctedAt: correctedAt ?? this.correctedAt,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'schemaVersion': 3,
      'id': id,
      'createdAt': createdAt.toIso8601String(),
      'collectorUserId': collectorUserId,
      'cityName': cityName,
      'areaName': areaName,
      'teamName': teamName,
      'recorderName': recorderName,
      'personName': personName,
      'englishName': englishName,
      'averageHeartRate': averageHeartRate,
      'latitude': latitude,
      'longitude': longitude,
      'locationAccuracyMeters': locationAccuracyMeters,
      'locationError': locationError,
      'manualPlaceName': manualPlaceName,
      'gender': gender,
      'identity': identity,
      'ageRange': ageRange,
      'relationshipLevel': relationshipLevel,
      'interestLevel': interestLevel,
      'contacts': contacts.map((contact) => contact.toJson()).toList(),
      'attitudeLevel': attitudeLevel,
      'notes': notes,
      'isLocationVerified': isLocationVerified,
      'correctedLatitude': correctedLatitude,
      'correctedLongitude': correctedLongitude,
      'correctedPlaceName': correctedPlaceName,
      'correctedAt': correctedAt?.toIso8601String(),
    };
  }

  factory ConversationRecord.fromJson(Map<String, Object?> json) {
    return ConversationRecord(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      collectorUserId: json['collectorUserId'] as String? ?? '',
      cityName: json['cityName'] as String? ?? '',
      areaName: json['areaName'] as String? ?? 'unassigned',
      teamName: json['teamName'] as String? ?? '',
      recorderName: json['recorderName'] as String? ?? '',
      personName: json['personName'] as String? ?? '',
      englishName: json['englishName'] as String? ?? '',
      averageHeartRate: _toDouble(json['averageHeartRate']),
      latitude: _toDouble(json['latitude']),
      longitude: _toDouble(json['longitude']),
      locationAccuracyMeters: _toDouble(json['locationAccuracyMeters']),
      locationError: json['locationError'] as String?,
      manualPlaceName: json['manualPlaceName'] as String? ?? '',
      gender: json['gender'] as String? ?? 'unknown',
      identity: json['identity'] as String? ?? 'other',
      ageRange: json['ageRange'] as String? ?? 'unknown',
      relationshipLevel: _readRelationship(json),
      interestLevel: _readInterest(json),
      contacts: _readContacts(json),
      attitudeLevel: _readAttitude(json),
      notes: json['notes'] as String? ?? '',
      isLocationVerified: json['isLocationVerified'] as bool? ?? false,
      correctedLatitude: _toDouble(json['correctedLatitude']),
      correctedLongitude: _toDouble(json['correctedLongitude']),
      correctedPlaceName: json['correctedPlaceName'] as String?,
      correctedAt: _toDate(json['correctedAt']),
    );
  }

  static List<ConversationRecord> decodeList(String raw) {
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map(
          (item) => ConversationRecord.fromJson(item as Map<String, Object?>),
        )
        .toList();
  }

  static String encodeList(List<ConversationRecord> records) {
    return jsonEncode(records.map((record) => record.toJson()).toList());
  }

  static List<ConversationContact> _readContacts(Map<String, Object?> json) {
    final rawContacts = json['contacts'];
    if (rawContacts is List) {
      return rawContacts
          .whereType<Map<String, Object?>>()
          .map(ConversationContact.fromJson)
          .where((contact) => !contact.isEmpty)
          .toList();
    }

    // Backward compatibility for records created by the first prototype.
    final oldChannel = json['contactChannel'] as String? ?? 'none';
    final oldValue = json['contactValue'] as String? ?? '';
    final oldContact = ConversationContact(
      channel: oldChannel,
      value: oldValue,
    );
    return oldContact.isEmpty ? const [] : [oldContact];
  }

  static int _readAttitude(Map<String, Object?> json) {
    final value = json['attitudeLevel'];
    if (value is num) {
      return _clampAttitude(value.toInt());
    }

    // Old "follow-up needed" records were usually warmer conversations, so
    // migrate true to +1 instead of losing the hint entirely.
    final oldFollowUp = json['followUpNeeded'] as bool? ?? false;
    return oldFollowUp ? 1 : 0;
  }

  static int _readRelationship(Map<String, Object?> json) {
    final value = json['relationshipLevel'];
    if (value is num) {
      return _clampRelationship(value.toInt());
    }
    return 1;
  }

  static int _readInterest(Map<String, Object?> json) {
    final value = json['interestLevel'];
    if (value is num) {
      return _clampInterest(value.toInt());
    }

    // When migrating old attitude records, map -2..2 into the new 0..4 scale.
    final oldAttitude = json['attitudeLevel'];
    if (oldAttitude is num) {
      return _clampInterest(oldAttitude.toInt() + 2);
    }
    return 2;
  }

  static int _clampInterest(int value) {
    if (value < 0) {
      return 0;
    }
    if (value > 4) {
      return 4;
    }
    return value;
  }

  static int _clampRelationship(int value) {
    if (value < 1) {
      return 1;
    }
    if (value > 4) {
      return 4;
    }
    return value;
  }

  static int _clampAttitude(int value) {
    if (value < -2) {
      return -2;
    }
    if (value > 2) {
      return 2;
    }
    return value;
  }

  static double? _toDouble(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value.toString());
  }

  static DateTime? _toDate(Object? value) {
    if (value == null) {
      return null;
    }
    return DateTime.tryParse(value.toString());
  }
}
