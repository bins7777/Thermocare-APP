import 'dart:math' as math;

// IDs are stored in Firebase. Append choices to preserve existing profiles.
const familyAvatarLabels = [
  'Heart',
  'Star',
  'Paw',
  'Flower',
  'Moon',
  'Sun',
  'Baby',
  'Boy',
  'Girl',
  'Man',
  'Woman',
  'Grandpa',
  'Grandma',
  'Person',
];

String newFamilyId() => List.generate(
  16,
  (_) => math.Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();

class FamilyMember {
  const FamilyMember({
    required this.id,
    required this.name,
    this.avatar = 0,
    this.archived = false,
  });
  final String id;
  final String name;
  final int avatar;
  final bool archived;

  factory FamilyMember.fromJson(Map<String, dynamic> json) => FamilyMember(
    id: json['id'] as String,
    name: json['name'] as String,
    avatar: json['avatar'] as int? ?? 0,
    archived: json['archived'] == true,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'avatar': avatar,
    'archived': archived,
  };
  FamilyMember copyWith({String? name, int? avatar, bool? archived}) =>
      FamilyMember(
        id: id,
        name: name ?? this.name,
        avatar: avatar ?? this.avatar,
        archived: archived ?? this.archived,
      );
}

enum TemperatureUnit { celsius, fahrenheit }

extension UnitFormat on TemperatureUnit {
  String get symbol => this == TemperatureUnit.celsius ? '°C' : '°F';
  double convert(double celsius) =>
      this == TemperatureUnit.celsius ? celsius : celsius * 9 / 5 + 32;
  String format(double celsius) => convert(celsius).toStringAsFixed(1);
}

/// Capture context is stored with the original sample and cannot be edited.
class MeasurementQuality {
  const MeasurementQuality({
    required this.sampleCount,
    required this.surfaceRange,
    required this.ambientRange,
    required this.windowSeconds,
    required this.prepared,
  });
  final int sampleCount;
  final double surfaceRange;
  final double ambientRange;
  final int windowSeconds;
  final bool prepared;
  Map<String, Object?> toJson() => {
    'sampleCount': sampleCount,
    'surfaceRange': surfaceRange,
    'ambientRange': ambientRange,
    'windowSeconds': windowSeconds,
    'prepared': prepared,
    'method': 'stable-v1',
  };
  factory MeasurementQuality.fromJson(Map<String, dynamic> json) =>
      MeasurementQuality(
        sampleCount: json['sampleCount'] as int,
        surfaceRange: (json['surfaceRange'] as num).toDouble(),
        ambientRange: (json['ambientRange'] as num).toDouble(),
        windowSeconds: json['windowSeconds'] as int,
        prepared: json['prepared'] == true,
      );
}

class Reading {
  const Reading({
    required this.id,
    required this.celsius,
    required this.ambient,
    required this.at,
    required this.deviceId,
    this.estimatedTime = false,
    this.memberId,
    this.memberName,
    this.note = '',
    this.quality,
  });
  final String id;
  final double celsius;
  final double ambient;
  final DateTime at;
  final String deviceId;
  final bool estimatedTime;
  final String? memberId;
  final String? memberName;
  final String note;
  final MeasurementQuality? quality;

  Reading forMember(FamilyMember member) => Reading(
    id: id,
    celsius: celsius,
    ambient: ambient,
    at: at,
    deviceId: deviceId,
    estimatedTime: estimatedTime,
    memberId: member.id,
    memberName: member.name,
    note: note,
    quality: quality,
  );

  Reading withNote(String value) => Reading(
    id: id,
    celsius: celsius,
    ambient: ambient,
    at: at,
    deviceId: deviceId,
    estimatedTime: estimatedTime,
    memberId: memberId,
    memberName: memberName,
    note: value,
    quality: quality,
  );

  Reading withQuality(MeasurementQuality value) => Reading(
    id: id,
    celsius: celsius,
    ambient: ambient,
    at: at,
    deviceId: deviceId,
    estimatedTime: estimatedTime,
    memberId: memberId,
    memberName: memberName,
    note: note,
    quality: value,
  );

  factory Reading.fromApi(Map<String, dynamic> json, {DateTime? receivedAt}) {
    final object = json['object_c'];
    final ambient = json['ambient_c'];
    if (json['sensor_ok'] != true ||
        object is! num ||
        ambient is! num ||
        !object.isFinite ||
        !ambient.isFinite ||
        object < -70 ||
        object > 380 ||
        ambient < -40 ||
        ambient > 125) {
      throw const FormatException('Sensor reading is unavailable or invalid.');
    }
    final device = json['device_id'];
    final boot = json['boot_id'];
    final seq = json['sequence'];
    final age = json['age_ms'];
    final epoch = json['epoch'];
    if (device is! String ||
        device.isEmpty ||
        boot is! String ||
        boot.isEmpty ||
        seq is! int ||
        seq < 0 ||
        age is! num ||
        !age.isFinite ||
        age < 0) {
      throw const FormatException(
        'This thermometer could not be read. Check its setup and try again.',
      );
    }
    final hasClock = epoch is int && epoch >= 1704067200 && epoch <= 4102444800;
    return Reading(
      id: '$device/$boot/$seq',
      celsius: object.toDouble(),
      ambient: ambient.toDouble(),
      at: hasClock
          ? DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true)
          : (receivedAt ?? DateTime.now()).toUtc().subtract(
              Duration(milliseconds: age.round()),
            ),
      deviceId: device,
      estimatedTime: !hasClock,
    );
  }

  factory Reading.fromJson(Map<String, dynamic> json) => Reading(
    id: json['id'] as String,
    celsius: (json['celsius'] as num).toDouble(),
    ambient: (json['ambient'] as num).toDouble(),
    at: DateTime.parse(json['at'] as String),
    deviceId: json['deviceId'] as String,
    estimatedTime: json['estimatedTime'] == true,
    memberId: json['memberId'] as String?,
    memberName: json['memberName'] as String?,
    note: json['note'] as String? ?? '',
    quality: json['quality'] == null
        ? null
        : MeasurementQuality.fromJson(
            Map<String, dynamic>.from(json['quality'] as Map),
          ),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'celsius': celsius,
    'ambient': ambient,
    'at': at.toUtc().toIso8601String(),
    'deviceId': deviceId,
    'estimatedTime': estimatedTime,
    'memberId': memberId,
    'memberName': memberName,
    if (note.isNotEmpty) 'note': note,
    if (quality != null) 'quality': quality!.toJson(),
  };
}

Uri deviceUri(String input) {
  final value = input.trim();
  final uri = Uri.tryParse(value.contains('://') ? value : 'http://$value');
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      uri.hasQuery ||
      uri.hasFragment ||
      RegExp(r'\s').hasMatch(value)) {
    throw const FormatException(
      'Enter an IP address or hostname, for example 192.168.1.42.',
    );
  }
  try {
    if (uri.port < 1 || uri.port > 65535) {
      throw const FormatException('Invalid port.');
    }
  } on FormatException {
    throw const FormatException('Enter a valid port between 1 and 65535.');
  }
  return uri.replace(path: '');
}

String readingsCsv(List<Reading> readings) {
  String cell(String value) => '"${value.replaceAll('"', '""')}"';
  final lines = <String>[
    'timestamp_utc,surface_c,ambient_c,device_id,time_source,member_id,member_name,note',
  ];
  for (final r in readings) {
    lines.add(
      '${cell(r.at.toUtc().toIso8601String())},${r.celsius.toStringAsFixed(2)},'
      '${r.ambient.toStringAsFixed(2)},${cell(r.deviceId)},${r.estimatedTime ? 'phone_estimate' : 'rtc'},${cell(r.memberId ?? '')},${cell(r.memberName ?? 'Unassigned')},${cell(r.note)}',
    );
  }
  return '${lines.join('\r\n')}\r\n';
}
