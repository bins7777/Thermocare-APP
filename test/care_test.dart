import 'family_fixture.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:thermocare/controller.dart';
import 'package:thermocare/care_models.dart';
import 'package:thermocare/models.dart';
import 'package:thermocare/data/device_api.dart';
import 'package:thermocare/data/reminders.dart';
import 'package:thermocare/data/store.dart';
import 'package:timezone/data/latest.dart' as zones;
import 'package:timezone/timezone.dart' as tz;
import 'capture_fixture.dart';

class ReminderFake extends ForegroundReminders {
  bool allowed = true;
  bool fail = false;
  int permissions = 0;
  List<CareReminder> scheduled = [];
  @override
  Future<bool> requestPermission() async {
    permissions++;
    return allowed;
  }

  @override
  Future<void> replace(
    Object owner,
    List<CareReminder> reminders,
    List<FamilyMember> members,
  ) async {
    if (fail) throw StateError('Scheduling failed');
    scheduled = reminders
        .where(
          (r) =>
              r.enabled &&
              members.any((m) => m.id == r.memberId && !m.archived),
        )
        .toList();
  }
}

void main() {
  test(
    'check-in freezes the captured person and sample while live values change',
    () async {
      final db = await databaseFactoryMemory.openDatabase('capture');
      final c = MonitorController(AppStore(db), familyFixtureApi());
      await initializeFamilyFixture(c);
      c.pause();
      seedStableCapture(c);
      final draft = c.captureCheckIn(prepared: true);
      await c.poll();
      await c.selectMember('dad');
      await c.saveCheckIn(draft, note: ' After a nap ');
      final saved = c.records.firstWhere((r) => r.id == draft.reading.id);
      expect(saved.memberId, 'mom');
      expect(saved.celsius, draft.reading.celsius);
      expect(saved.note, 'After a nap');
      expect(c.latest!.id, isNot(saved.id));
      await c.updateNote(saved, 'Feeling cozy');
      expect(
        c.records.firstWhere((r) => r.id == saved.id).note,
        'Feeling cozy',
      );
      expect(
        (await c.store.loadReadings()).firstWhere((r) => r.id == saved.id).note,
        'Feeling cozy',
      );
      await c.saveMember(
        existing: fixtureFamily.first,
        name: 'Mom',
        avatar: 10,
        archived: true,
      );
      await expectLater(c.saveCheckIn(draft), throwsFormatException);
      c.dispose();
      await db.close();
    },
  );

  test(
    'notes persist, queue for cloud, survive samples, and keep measurements immutable',
    () async {
      final db = await databaseFactoryMemory.openDatabase('notes');
      final store = AppStore(db, ownerId: 'a');
      const mom = FamilyMember(id: 'mom', name: 'Mom');
      final raw = Reading(
        id: 'uno/1/1',
        celsius: 31.5,
        ambient: 25,
        at: DateTime.utc(2026, 10, 9),
        deviceId: 'uno',
      );
      await store.saveMember(mom);
      await store.saveReadings([raw]);
      await store.updateNote(raw.id, 'After resting');
      await store.saveReadings([raw]);
      expect((await store.loadReadings()).single.note, 'After resting');
      expect(
        (await store.pendingWrites()).where(
          (w) => w.path.startsWith('readings'),
        ),
        isEmpty,
      );
      await store.saveReadings([raw.forMember(mom)]);
      await store.updateNote(raw.id, 'Rested, then checked');
      final saved = (await store.loadReadings()).single;
      expect(saved.note, 'Rested, then checked');
      expect(saved.celsius, 31.5);
      final queued = (await store.pendingWrites()).firstWhere(
        (w) => w.path.startsWith('readings'),
      );
      expect(queued.data!['note'], saved.note);
      await store.mergeCloudReadings([
        saved.withNote('Old server note'),
      ], authoritative: true);
      expect((await store.loadReadings()).single.note, saved.note);
      await store.acknowledge(queued);
      await store.mergeCloudReadings([
        saved.withNote('From another phone'),
      ], authoritative: true);
      expect((await store.loadReadings()).single.note, 'From another phone');
      await expectLater(
        store.updateNote(raw.id, 'x' * 501),
        throwsFormatException,
      );
      expect(
        readingsCsv([saved.withNote('Cozy, "rested"\nwell')]),
        contains('"Cozy, ""rested""\nwell"'),
      );
      await store.updateNote(raw.id, '');
      expect(
        (await store.loadReadings()).single.toJson().containsKey('note'),
        isFalse,
      );
      await db.close();
    },
  );

  test(
    'calendar groups local days and family members, excluding automatic samples',
    () {
      final day = DateTime(2026, 1, 1);
      Reading sample(String id, DateTime at, String? member) => Reading(
        id: id,
        celsius: 32,
        ambient: 25,
        at: at.toUtc(),
        deviceId: 'uno',
        memberId: member,
      );
      final records = [
        sample('a', day, 'mom'),
        sample('b', day.add(const Duration(hours: 23)), 'dad'),
        sample('c', day.add(const Duration(days: 1)), 'mom'),
        sample('raw', day, null),
      ];
      expect(checkInsOn(records, day).map((r) => r.id), ['b', 'a']);
      expect(checkInsOn(records, day, memberId: 'mom').single.id, 'a');
      expect(checkInsOn(records, DateTime(2025, 12, 31)), isEmpty);
    },
  );

  test(
    'reminders persist per account, fire once per day, and pause for archived people',
    () async {
      final db = await databaseFactoryMemory.openDatabase('reminders');
      final gateway = ReminderFake();
      final store = AppStore(db, ownerId: 'a');
      const mom = FamilyMember(id: 'mom', name: 'Mom');
      await store.saveMember(mom);
      final c = MonitorController(
        store,
        DeviceApi(),
        remindersGateway: gateway,
      );
      await c.initialize();
      c.pause();
      expect(gateway.permissions, 0);
      const r = CareReminder(
        id: 'r',
        memberId: 'mom',
        hour: 9,
        minute: 15,
        weekdays: [1, 3],
      );
      await c.saveReminder(r);
      expect(gateway.scheduled.single.id, 'r');
      c.checkReminders(now: DateTime(2026, 10, 12, 9, 15)); // Monday.
      expect(c.dueMemberId, 'mom');
      c.dismissReminder();
      c.checkReminders(now: DateTime(2026, 10, 12, 9, 15, 30));
      expect(c.dueMemberId, isNull);
      c.dispose();
      final restored = MonitorController(
        store,
        DeviceApi(),
        remindersGateway: gateway,
      );
      await restored.initialize();
      restored.pause();
      expect(restored.reminders.single.weekdays, [1, 3]);
      restored.checkReminders(now: DateTime(2026, 10, 12, 9, 15));
      expect(restored.dueMemberId, isNull);
      restored.checkReminders(now: DateTime(2026, 10, 14, 9, 15));
      expect(restored.dueMemberId, 'mom');
      await restored.saveMember(
        existing: mom,
        name: 'Mom',
        avatar: 0,
        archived: true,
      );
      expect(gateway.scheduled, isEmpty);
      restored.dismissReminder();
      restored.checkReminders(now: DateTime(2026, 10, 19, 9, 15));
      expect(restored.dueMemberId, isNull);
      final other = MonitorController(
        AppStore(db, ownerId: 'b'),
        DeviceApi(),
        remindersGateway: gateway,
      );
      await other.initialize();
      other.pause();
      expect(other.reminders, isEmpty);
      expect(gateway.scheduled, isEmpty);
      restored.dispose();
      other.dispose();
      await db.close();
    },
  );

  test(
    'permission denial, schedule failure, edits, deletion and account isolation',
    () async {
      final db = await databaseFactoryMemory.openDatabase(
        'reminder-permissions',
      );
      final gateway = ReminderFake()..allowed = false;
      final c = MonitorController(
        AppStore(db),
        DeviceApi(),
        remindersGateway: gateway,
      );
      await c.initialize();
      c.pause();
      await c.saveMember(name: 'Mom', avatar: 10);
      final r = CareReminder(
        id: 'r',
        memberId: c.members.single.id,
        hour: 21,
        minute: 30,
        weekdays: [1, 2, 3, 4, 5, 6, 7],
      );
      await c.saveReminder(r);
      expect(
        c.reminders.single.id,
        'r',
        reason: 'Notification permission must not block saving shared data',
      );
      expect(c.reminderWarning, isNotNull);
      gateway
        ..allowed = true
        ..fail = true;
      await c.saveReminder(r);
      expect(c.reminderWarning, isNotNull);
      gateway.fail = false;
      await c.saveReminder(r.withEnabled(false));
      expect(c.reminderWarning, isNull);
      expect(gateway.scheduled, isEmpty);
      expect(await AppStore(db, ownerId: 'other').loadReminders(), isEmpty);
      await c.deleteReminder('r');
      expect(c.reminders, isEmpty);
      final a = CareReminder(
        id: 'a',
        memberId: r.memberId,
        hour: 8,
        minute: 0,
        weekdays: [1],
        enabled: false,
      );
      final b = CareReminder(
        id: 'b',
        memberId: r.memberId,
        hour: 20,
        minute: 0,
        weekdays: [2],
        enabled: false,
      );
      await Future.wait([c.saveReminder(a), c.saveReminder(b)]);
      expect(c.reminders.map((r) => r.id).toSet(), {'a', 'b'});
      await Future.wait([
        c.deleteReminder('a'),
        c.saveReminder(b.withEnabled(true)),
      ]);
      expect(c.reminders.single.id, 'b');
      expect(c.reminders.single.enabled, isTrue);
      c.dispose();
      await db.close();
    },
  );

  test('weekly notifications preserve local time across DST and midnight', () {
    zones.initializeTimeZones();
    final zone = tz.getLocation('America/New_York');
    final now = tz.TZDateTime(zone, 2026, 3, 7, 19);
    final next = nextReminderTime(now, DateTime.sunday, 9, 15);
    expect(next.day, 8);
    expect(next.hour, 9);
    expect(next.minute, 15);
    expect(next.timeZoneOffset, const Duration(hours: -4));
    final same = nextReminderTime(next, DateTime.sunday, 9, 15);
    expect(same.day, 15);
    final midnight = nextReminderTime(
      tz.TZDateTime(zone, 2026, 12, 31, 23, 59),
      DateTime.friday,
      0,
      0,
    );
    expect(midnight.year, 2027);
    expect(midnight.month, 1);
    expect(midnight.day, 1);
  });
}
