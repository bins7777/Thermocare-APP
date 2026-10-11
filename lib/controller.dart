import 'dart:async';
import 'package:flutter/foundation.dart';
import 'data/device_api.dart';
import 'data/store.dart';
import 'data/family_cloud.dart';
import 'models.dart';
import 'care_models.dart';
import 'data/reminders.dart';

class MonitorController extends ChangeNotifier {
  MonitorController(
    this.store,
    this.api, {
    FamilyCloudGateway? cloudGateway,
    this.accountEmail,
    ReminderGateway? remindersGateway,
  }) {
    reminderGateway = remindersGateway ?? ForegroundReminders();
    if (cloudGateway != null) {
      cloud = FamilyCloudSync(store, cloudGateway)..addListener(_notify);
    }
  }
  final AppStore store;
  final DeviceApi api;
  final String? accountEmail;
  late final ReminderGateway reminderGateway;
  final Object _reminderOwner = Object();
  Future<void>? _reminderWrites;
  List<CareReminder> _reminders = [];
  final Map<String, String> _reminded = {};
  Timer? _careTimer;
  String? reminderWarning;
  bool _notificationDenied = false;
  String? dueMemberId;
  List<CareReminder> get reminders => List.unmodifiable(_reminders);

  Future<void> _scheduleReminders() async {
    if (_disposed) return;
    try {
      await reminderGateway.replace(
        _reminderOwner,
        _notificationDenied ? [] : _reminders.take(8).toList(),
        _members,
      );
      reminderWarning = _notificationDenied && _reminders.any((r) => r.enabled)
          ? 'Your reminder is saved. Notifications are off on this phone; enable them here to receive nudges.'
          : null;
    } catch (_) {
      reminderWarning =
          'Phone notifications could not be scheduled. Open Reminders to try again.';
    }
    _notify();
  }

  Future<void> _editReminders(Future<void> Function() edit) {
    final work = (_reminderWrites ?? Future<void>.value())
        .catchError((Object _) {})
        .then((_) {
          if (_disposed) {
            throw const FormatException(
              'The family changed. Please open Reminders again.',
            );
          }
          return edit();
        });
    _reminderWrites = work;
    return work;
  }

  Future<void> saveReminder(CareReminder reminder) =>
      _editReminders(() => _saveReminder(reminder));

  Future<void> _saveReminder(CareReminder reminder) async {
    if (!activeMembers.any((m) => m.id == reminder.memberId) ||
        !RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(reminder.id) ||
        reminder.hour < 0 ||
        reminder.hour > 23 ||
        reminder.minute < 0 ||
        reminder.minute > 59 ||
        reminder.weekdays.isEmpty ||
        reminder.weekdays.any((d) => d < 1 || d > 7) ||
        reminder.weekdays.toSet().length != reminder.weekdays.length) {
      throw const FormatException(
        'Choose a person, a time, and at least one day.',
      );
    }
    final list = _reminders;
    if (!list.any((r) => r.id == reminder.id) && list.length >= 8) {
      throw const FormatException('You can keep up to 8 family reminders.');
    }
    if (reminder.enabled) {
      try {
        _notificationDenied = !await reminderGateway.requestPermission();
      } catch (_) {
        _notificationDenied = true;
      }
    }
    if (_disposed) {
      throw const FormatException(
        'The family changed. Please open Reminders again.',
      );
    }
    final current = _reminders;
    if (!current.any((r) => r.id == reminder.id) && current.length >= 8) {
      throw const FormatException('You can keep up to 8 family reminders.');
    }
    await store.saveReminder(reminder);
    _reminders = await store.loadReminders();
    await _scheduleReminders();
    unawaited(cloud?.flush());
    checkReminders();
    _notify();
  }

  Future<void> deleteReminder(String id) =>
      _editReminders(() => _deleteReminder(id));

  Future<void> _deleteReminder(String id) async {
    await store.deleteReminder(id);
    _reminders = await store.loadReminders();
    if (!_reminders.any((r) => r.enabled && r.memberId == dueMemberId)) {
      dueMemberId = null;
    }
    await _scheduleReminders();
    unawaited(cloud?.flush());
    _notify();
  }

  void dismissReminder() {
    dueMemberId = null;
    _notify();
  }

  Future<void> enableReminderNotifications() async {
    try {
      _notificationDenied = !await reminderGateway.requestPermission();
    } catch (_) {
      _notificationDenied = true;
    }
    await _scheduleReminders();
  }

  void checkReminders({DateTime? now}) {
    if (_disposed) return;
    final local = (now ?? DateTime.now()).toLocal();
    final day = '${local.year}-${local.month}-${local.day}';
    for (final r in reminders) {
      final key = 'real/${r.id}';
      if (r.dueAt(local) &&
          _reminded[key] != day &&
          activeMembers.any((m) => m.id == r.memberId)) {
        _reminded[key] = day;
        dueMemberId = r.memberId;
        unawaited(
          store
              .setSetting('remindedDays', Map<String, String>.from(_reminded))
              .catchError((Object _) {}),
        );
        _notify();
      }
    }
  }

  void _startCareTimer() {
    _careTimer?.cancel();
    checkReminders();
    _careTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => checkReminders(),
    );
  }

  FamilyCloudSync? cloud;
  List<FamilyMember> _members = [];
  String? _selectedMemberId;
  List<FamilyMember> get members => List.unmodifiable(_members);
  List<FamilyMember> get activeMembers =>
      members.where((m) => !m.archived).toList();
  FamilyMember? get selectedMember {
    final id = _selectedMemberId;
    for (final member in activeMembers) {
      if (member.id == id) return member;
    }
    return null;
  }

  String memberName(Reading reading) {
    for (final member in members) {
      if (member.id == reading.memberId) return member.name;
    }
    return reading.memberName ?? 'Unassigned';
  }

  Future<void> selectMember(String id) async {
    if (!activeMembers.any((m) => m.id == id)) return;
    measurements.reset();
    _selectedMemberId = id;
    await store.setSetting('selectedMember', id);
    _notify();
  }

  Future<void> saveMember({
    FamilyMember? existing,
    required String name,
    required int avatar,
    bool? archived,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 40) {
      throw const FormatException('Use a name from 1 to 40 characters.');
    }
    if (avatar < 0 || avatar >= familyAvatarLabels.length) {
      throw const FormatException('Choose an icon from the family list.');
    }
    final member = FamilyMember(
      id: existing?.id ?? newFamilyId(),
      name: trimmed,
      avatar: avatar,
      archived: archived ?? existing?.archived ?? false,
    );
    await store.saveMember(member);
    await _reloadFamily();
    if (selectedMember == null && !member.archived) {
      await selectMember(member.id);
    }
    unawaited(cloud?.flush());
    _notify();
  }

  Future<void> _reloadFamily() async {
    final previous = _members.map((m) => m.toJson().toString()).join();
    final previousReminders = _reminders
        .map((r) => r.toJson().toString())
        .join();
    _members = await store.loadMembers();
    _records = await store.loadReadings();
    _reminders = await store.loadReminders();
    if (previous != _members.map((m) => m.toJson().toString()).join() ||
        previousReminders !=
            _reminders.map((r) => r.toJson().toString()).join()) {
      await _scheduleReminders();
    }
    if (dueMemberId != null &&
        (!activeMembers.any((m) => m.id == dueMemberId) ||
            !_reminders.any((r) => r.enabled && r.memberId == dueMemberId))) {
      dueMemberId = null;
    }
    _notify();
  }

  Future<void> importLocalFamily(
    List<FamilyMember> members,
    List<Reading> readings, {
    List<CareReminder> reminders = const [],
  }) async {
    if (store.ownerId == null) {
      throw StateError('Sign in to import profiles.');
    }
    final ids = members.map((m) => m.id).toSet();
    final importedReminders = reminders
        .where((r) => ids.contains(r.memberId))
        .toList();
    final reminderIds = (await store.loadReminders()).map((r) => r.id).toSet()
      ..addAll(importedReminders.map((r) => r.id));
    if (reminderIds.length > 8) {
      throw const FormatException(
        'Keep up to 8 family reminders before importing.',
      );
    }
    for (final member in members) {
      await store.saveMember(member);
    }
    await store.saveReadings(readings.where((r) => ids.contains(r.memberId)));
    for (final reminder in importedReminders) {
      await store.saveReminder(reminder);
    }
    await _reloadFamily();
    unawaited(cloud?.flush());
  }

  List<Reading> _records = [];
  final List<Reading> session = [];
  final measurements = MeasurementWindow();
  bool get measurementReady =>
      fresh &&
      measurements.matches(latest) &&
      measurements.evaluate(DateTime.now(), prepared: false) != null;
  void beginMeasurement() {
    measurements.reset();
    _measuring = true;
    if (active && _foreground) {
      _startTimer();
      unawaited(poll());
    }
    _notify();
  }

  void endMeasurement({bool notify = true}) {
    _measuring = false;
    _timer?.cancel();
    _measurementTimeout?.cancel();
    ++_generation;
    busy = false;
    if (notify) _notify();
  }

  bool _measuring = false;
  bool _foreground = true;
  Timer? _measurementTimeout;
  bool get measuring => _measuring;

  Reading? get selectedMemberCheckIn {
    final id = selectedMember?.id;
    if (id == null) return null;
    for (final reading in _records) {
      if (reading.memberId == id) return reading;
    }
    return null;
  }

  /// Alerts use saved, person-attributed records, never an idle sensor sample.
  Reading? get temperatureAlert {
    final reading = selectedMemberCheckIn;
    return reading != null && reading.celsius >= threshold ? reading : null;
  }

  Reading? latest;
  DateTime? lastContact;
  DateTime? lastHistorySync;
  TemperatureUnit unit = TemperatureUnit.celsius;
  String address = '';
  String? error;
  String? syncWarning;
  double threshold = 38;
  bool active = false;
  bool busy = false;
  bool _disposed = false;
  bool _inflight = false;
  Completer<void>? _inflightDone;
  int _generation = 0;
  Timer? _timer;
  List<Reading> get records => List.unmodifiable(_records);
  bool get fresh =>
      active &&
      latest != null &&
      lastContact != null &&
      DateTime.now().difference(lastContact!) < const Duration(seconds: 8) &&
      error == null;
  bool get hasReading => active && latest != null;
  bool get aboveThreshold => hasReading && latest!.celsius >= threshold;

  Future<void> initialize() async {
    _records = await store.loadReadings();
    _members = await store.loadMembers();
    _selectedMemberId = await store.setting('selectedMember') as String?;
    address = await store.setting('address') as String? ?? '';
    active = address.isNotEmpty;
    unit = await store.setting('fahrenheit') == true
        ? TemperatureUnit.fahrenheit
        : TemperatureUnit.celsius;
    threshold = (await store.setting('threshold') as num?)?.toDouble() ?? 38;
    await store.migrateReminders();
    _reminders = await store.loadReminders();
    _reminded.addAll(
      Map<String, String>.from(
        (await store.setting('remindedDays') as Map?) ?? {},
      ),
    );
    if (_disposed) return;
    await _scheduleReminders();
    _startCareTimer();
    cloud?.start(_reloadFamily);
    _notify();
  }

  void _startTimer() {
    _timer?.cancel();
    _measurementTimeout?.cancel();
    _measurementTimeout = Timer(const Duration(minutes: 1), endMeasurement);
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_measuring || !_foreground) {
        endMeasurement();
        return;
      }
      unawaited(poll());
    });
  }

  Future<void> connect(String input) async {
    final normalized = deviceUri(input).toString();
    disconnect();
    final generation = _generation;
    address = normalized;
    await store.setSetting('address', address);
    if (_disposed || generation != _generation) return;
    active = true;
    await poll(forceHistory: true);
  }

  void disconnect() {
    ++_generation;
    _timer?.cancel();
    _measurementTimeout?.cancel();
    _measuring = false;
    active = false;
    busy = false;
    error = null;
    syncWarning = null;
    latest = null;
    lastContact = null;
    lastHistorySync = null;
    session.clear();
    measurements.reset();
    _notify();
  }

  void pause() {
    _foreground = false;
    measurements.reset();
    _timer?.cancel();
    _measurementTimeout?.cancel();
    _careTimer?.cancel();
    ++_generation;
    busy = false;
  }

  void resume() {
    _foreground = true;
    _startCareTimer();
    if (active && _measuring) {
      beginMeasurement();
    }
  }

  Future<void> poll({bool forceHistory = false}) async {
    if (!active || _disposed) {
      return;
    }
    final generation = _generation;
    // Explicit requests must survive a previous connection finishing. Periodic
    // capture ticks may skip; a user-requested reconnect must actually run.
    while (_inflight) {
      if (!forceHistory) return;
      await _inflightDone!.future;
      if (!active || _disposed || generation != _generation) return;
    }
    final completed = Completer<void>();
    _inflightDone = completed;
    _inflight = true;
    busy = true;
    _notify();
    try {
      final base = deviceUri(address);
      final value = await api.latest(base);
      if (generation != _generation || _disposed) {
        return;
      }
      latest = value;
      lastContact = DateTime.now();
      measurements.add(value, lastContact!);
      error = null;
      if (session.isEmpty || session.last.id != value.id) {
        session.add(value);
      }
      if (session.length > 60) {
        session.removeAt(0);
      }
      // Live samples belong in History too, independently of the Arduino's
      // slower one-minute buffer. Family attribution still requires Save.
      try {
        await store.saveReadings([value]);
        _records = await store.loadReadings();
      } catch (_) {
        syncWarning =
            'Live readings are working, but this phone could not save the latest sample. It will retry.';
      }
      if (generation != _generation || _disposed) return;
      _notify();
      if (forceHistory ||
          lastHistorySync == null ||
          DateTime.now().difference(lastHistorySync!) >
              const Duration(seconds: 30)) {
        try {
          final history = await api.history(base);
          if (generation != _generation || _disposed) {
            return;
          }
          await store.saveReadings(history);
          _records = await store.loadReadings();
          lastHistorySync = DateTime.now();
          syncWarning = null;
        } catch (_) {
          if (generation != _generation || _disposed) {
            return;
          }
          syncWarning =
              'Live readings are working. History sync failed; it will retry.';
        }
      }
    } catch (e) {
      if (generation != _generation || _disposed) {
        return;
      }
      error = e is FormatException
          ? e.message
          : 'Cannot reach $address. Check its power and Wi-Fi. On ThermoCare Wi-Fi, use 192.168.4.1; internet is not required.';
      measurements.reset();
    } finally {
      _inflight = false;
      _inflightDone = null;
      completed.complete();
      if (generation == _generation) {
        busy = false;
        _notify();
      }
    }
  }

  CheckInDraft captureCheckIn({FamilyMember? member, bool prepared = false}) {
    if (!fresh) {
      throw StateError('Wait for a fresh reading before saving.');
    }
    final person = member ?? selectedMember;
    if (person == null || !activeMembers.any((m) => m.id == person.id)) {
      throw const FormatException('Choose a family member before saving.');
    }
    final quality = measurements.evaluate(DateTime.now(), prepared: prepared);
    if (!prepared || quality == null || !measurements.matches(latest)) {
      throw const FormatException(
        'Complete the preparation checklist and hold still for three stable readings.',
      );
    }
    return CheckInDraft(latest!.withQuality(quality), person);
  }

  Future<void> saveCurrent({String note = '', bool prepared = false}) async {
    await saveCheckIn(captureCheckIn(prepared: prepared), note: note);
  }

  Future<void> saveCheckIn(CheckInDraft draft, {String note = ''}) async {
    if (note.length > 500) {
      throw const FormatException('Keep your note within 500 characters.');
    }
    if (draft.reading.quality?.prepared != true) {
      throw const FormatException(
        'Start a guided check-in to capture preparation and stable readings.',
      );
    }
    if (!activeMembers.any((m) => m.id == draft.member.id)) {
      throw const FormatException(
        'The family or device changed. Please start a new check-in.',
      );
    }
    final member = draft.member;
    final reading = draft.reading.forMember(member).withNote(note.trim());
    await store.saveReadings([reading]);
    _records = await store.loadReadings();
    unawaited(cloud?.flush());
    _notify();
  }

  Future<void> updateNote(Reading reading, String note) async {
    if (note.length > 500) {
      throw const FormatException('Keep your note within 500 characters.');
    }
    await store.updateNote(reading.id, note);
    _records = await store.loadReadings();
    unawaited(cloud?.flush());
    _notify();
  }

  Future<void> setUnit(TemperatureUnit value) async {
    await store.setSetting('fahrenheit', value == TemperatureUnit.fahrenheit);
    unit = value;
    _notify();
  }

  Future<void> setThreshold(double celsius) async {
    if (!celsius.isFinite || celsius < 30 || celsius > 45) {
      throw const FormatException('Use a threshold between 30 and 45°C.');
    }
    await store.setSetting('threshold', celsius);
    threshold = celsius;
    _notify();
  }

  Future<void> syncClock() async {
    if (!fresh) {
      throw StateError('Connect your thermometer first.');
    }
    await api.syncClock(deviceUri(address));
    await poll(forceHistory: true);
  }

  Future<void> clearRecords() async {
    await store.clearReadings();
    _records.clear();
    unawaited(cloud?.flush());
    _notify();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _measurementTimeout?.cancel();
    _careTimer?.cancel();
    api.dispose();
    cloud?.removeListener(_notify);
    cloud?.dispose();
    super.dispose();
  }
}
