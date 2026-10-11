import 'models.dart';

/// A repeatability aid, not a clinical accuracy or fever assessment.
class MeasurementWindow {
  final List<(Reading, DateTime)> _samples = [];
  void reset() => _samples.clear();
  void add(Reading reading, DateTime receivedAt) {
    if (_samples.isNotEmpty &&
        (_samples.last.$1.deviceId != reading.deviceId ||
            receivedAt.difference(_samples.last.$2).inSeconds > 4)) {
      reset();
    }
    if (_samples.any((s) => s.$1.id == reading.id)) return;
    _samples.add((reading, receivedAt));
    if (_samples.length > 3) _samples.removeAt(0);
  }

  MeasurementQuality? evaluate(DateTime now, {required bool prepared}) {
    if (_samples.length != 3 ||
        now.difference(_samples.last.$2).inSeconds >= 8 ||
        now.isBefore(_samples.last.$2)) {
      return null;
    }
    final seconds = _samples.last.$2.difference(_samples.first.$2).inSeconds;
    if (seconds < 3 || seconds > 8) return null;
    double spread(double Function(Reading) value) {
      final values = _samples.map((s) => value(s.$1)).toList()..sort();
      return values.last - values.first;
    }

    final surface = spread((r) => r.celsius);
    final ambient = spread((r) => r.ambient);
    if (!surface.isFinite ||
        !ambient.isFinite ||
        surface > .300001 ||
        ambient > 1.000001) {
      return null;
    }
    return MeasurementQuality(
      sampleCount: 3,
      surfaceRange: surface,
      ambientRange: ambient,
      windowSeconds: seconds,
      prepared: prepared,
    );
  }

  int get count => _samples.length;
  bool matches(Reading? reading) =>
      _samples.isNotEmpty && _samples.last.$1.id == reading?.id;
}

class PersonalTrend {
  PersonalTrend(
    Iterable<Reading> records,
    String memberId,
    DateTime now,
    int days,
  ) : readings =
          records
              .where(
                (r) =>
                    r.memberId == memberId &&
                    !r.at.isBefore(
                      careDay(now).subtract(Duration(days: days - 1)),
                    ) &&
                    !r.at.isAfter(now),
              )
              .toList()
            ..sort((a, b) => a.at.compareTo(b.at));
  final List<Reading> readings;
  double? get average => readings.isEmpty
      ? null
      : readings.fold<double>(0, (sum, r) => sum + r.celsius) / readings.length;
  double? get change => readings.length < 2
      ? null
      : readings.last.celsius - readings.first.celsius;
  List<Reading> get dailyAverages {
    final groups = <DateTime, List<Reading>>{};
    for (final r in readings) {
      groups.putIfAbsent(careDay(r.at), () => []).add(r);
    }
    return groups.entries
        .map(
          (g) => Reading(
            id: 'day/${g.key.toIso8601String()}',
            celsius:
                g.value.fold<double>(0, (sum, r) => sum + r.celsius) /
                g.value.length,
            ambient: 0,
            at: g.key,
            deviceId: 'daily-average',
          ),
        )
        .toList();
  }
}

/// Freezes the person and sample at capture, before the user types a note.
class CheckInDraft {
  const CheckInDraft(this.reading, this.member);
  final Reading reading;
  final FamilyMember member;
}

class CareReminder {
  const CareReminder({
    required this.id,
    required this.memberId,
    required this.hour,
    required this.minute,
    required this.weekdays,
    this.enabled = true,
  });
  final String id;
  final String memberId;
  final int hour;
  final int minute;
  final List<int> weekdays;
  final bool enabled;
  CareReminder withEnabled(bool value) => CareReminder(
    id: id,
    memberId: memberId,
    hour: hour,
    minute: minute,
    weekdays: weekdays,
    enabled: value,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'memberId': memberId,
    'hour': hour,
    'minute': minute,
    'weekdays': weekdays,
    'enabled': enabled,
  };
  factory CareReminder.fromJson(Map<String, dynamic> json) => CareReminder(
    id: json['id'] as String,
    memberId: json['memberId'] as String,
    hour: json['hour'] as int,
    minute: json['minute'] as int,
    weekdays: (json['weekdays'] as List).cast<int>(),
    enabled: json['enabled'] == true,
  );
  bool dueAt(DateTime local) =>
      enabled &&
      weekdays.contains(local.weekday) &&
      local.hour == hour &&
      local.minute == minute;
}

DateTime careDay(DateTime time) {
  final local = time.toLocal();
  return DateTime(local.year, local.month, local.day);
}

List<Reading> checkInsOn(
  Iterable<Reading> readings,
  DateTime day, {
  String? memberId,
}) =>
    readings
        .where(
          (r) =>
              r.memberId != null &&
              (memberId == null || r.memberId == memberId) &&
              careDay(r.at) == careDay(day),
        )
        .toList()
      ..sort((a, b) => b.at.compareTo(a.at));
