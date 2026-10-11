import 'family_fixture.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:thermocare/care_models.dart';
import 'package:thermocare/controller.dart';
import 'package:thermocare/data/device_api.dart';
import 'package:thermocare/data/family_cloud.dart';
import 'package:thermocare/data/store.dart';
import 'package:thermocare/models.dart';
import 'capture_fixture.dart';

Reading sample(
  String id,
  DateTime at, {
  double surface = 32,
  double ambient = 25,
  String? member,
}) => Reading(
  id: id,
  celsius: surface,
  ambient: ambient,
  at: at,
  deviceId: 'uno',
  memberId: member,
);

Future<void> eventually(bool Function() done, String stage) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(done(), isTrue, reason: stage);
}

class SharedDatabase {
  final members = <String, FamilyMember>{};
  final readings = <String, Reading>{};
  final reminders = <String, CareReminder>{};
  final changes = StreamController<void>.broadcast();
}

class ConnectedPhone implements FamilyCloudGateway {
  ConnectedPhone(this.server);
  final SharedDatabase server;
  bool offline = false;
  Stream<CloudSnapshot<T>> _watch<T>(Iterable<T> Function() values) =>
      Stream.multi((controller) {
        // Subscribe before the first snapshot so a write during startup cannot
        // fall into the gap between an async* yield and yield* subscription.
        final subscription = server.changes.stream.listen(
          (_) => controller.add(CloudSnapshot(values().toList())),
          onError: controller.addError,
          onDone: controller.close,
        );
        controller.add(CloudSnapshot(values().toList()));
        controller.onCancel = subscription.cancel;
      });
  @override
  Stream<CloudSnapshot<FamilyMember>> watchMembers() =>
      _watch(() => server.members.values);

  @override
  Stream<CloudSnapshot<Reading>> watchReadings() =>
      _watch(() => server.readings.values);

  @override
  Stream<CloudSnapshot<CareReminder>> watchReminders() =>
      _watch(() => server.reminders.values);

  @override
  Future<void> write(PendingWrite write) async {
    if (offline) throw StateError('Offline');
    final key = write.path.split('/').last;
    switch (write.path.split('/').first) {
      case 'members':
        if (write.data == null) {
          server.members.remove(key);
        } else {
          server.members[key] = FamilyMember.fromJson(write.data!);
        }
      case 'readings':
        if (write.data == null) {
          server.readings.remove(key);
        } else {
          server.readings[key] = Reading.fromJson(write.data!);
        }
      case 'reminders':
        if (write.data == null) {
          server.reminders.remove(key);
        } else {
          server.reminders[key] = CareReminder.fromJson(write.data!);
        }
    }
    server.changes.add(null);
  }
}

void main() {
  test(
    'capture cannot bypass preparation or reuse another person’s stability window',
    () async {
      final db = await databaseFactoryMemory.openDatabase('capture-gate');
      final c = MonitorController(AppStore(db), familyFixtureApi());
      await initializeFamilyFixture(c);
      c.pause();
      expect(() => c.captureCheckIn(prepared: true), throwsFormatException);
      seedStableCapture(c);
      expect(() => c.captureCheckIn(), throwsFormatException);
      final held = c.captureCheckIn(prepared: true);
      expect(held.reading.quality!.prepared, isTrue);
      await c.selectMember('dad');
      expect(() => c.captureCheckIn(prepared: true), throwsFormatException);
      await c.saveCheckIn(held);
      expect(
        c.records.firstWhere((r) => r.id == held.reading.id).memberId,
        'mom',
      );
      c.dispose();
      await db.close();
    },
  );

  test(
    'importing phone profiles queues their reminders for the family database',
    () async {
      final db = await databaseFactoryMemory.openDatabase('import-reminders');
      final store = AppStore(db, ownerId: 'family');
      final c = MonitorController(store, DeviceApi());
      await c.initialize();
      c.pause();
      const member = FamilyMember(id: 'mom', name: 'Mom');
      const reminder = CareReminder(
        id: 'evening',
        memberId: 'mom',
        hour: 19,
        minute: 0,
        weekdays: [1],
      );
      await c.importLocalFamily([member], [], reminders: [reminder]);
      expect(c.reminders.single.id, 'evening');
      expect((await store.pendingWrites()).map((w) => w.path), [
        'members/mom',
        'reminders/evening',
      ]);
      c.dispose();
      await db.close();
    },
  );
  test(
    'readiness requires three unique samples, elapsed time, stability and recency',
    () {
      final now = DateTime.utc(2026, 10, 10, 12);
      final window = MeasurementWindow();
      final first = sample('1', now);
      window.add(first, now.subtract(const Duration(seconds: 4)));
      window.add(first, now.subtract(const Duration(seconds: 2)));
      window.add(first, now);
      expect(window.evaluate(now, prepared: true), isNull);
      window.add(
        sample('2', now, surface: 32.1),
        now.subtract(const Duration(seconds: 2)),
      );
      window.add(sample('3', now, surface: 32.2), now);
      final quality = window.evaluate(now, prepared: true)!;
      expect(quality.sampleCount, 3);
      expect(quality.surfaceRange, closeTo(.2, .00001));
      expect(
        window.evaluate(now.add(const Duration(seconds: 8)), prepared: true),
        isNull,
      );
      window.add(
        sample('4', now, surface: 33),
        now.add(const Duration(seconds: 2)),
      );
      expect(
        window.evaluate(now.add(const Duration(seconds: 2)), prepared: true),
        isNull,
      );
      window.reset();
      for (var i = 0; i < 3; i++) {
        window.add(sample('$i', now), now);
      }
      expect(
        window.evaluate(now, prepared: true),
        isNull,
        reason: 'Rapid requests do not establish stability over time',
      );
      window.reset();
      for (var i = 0; i < 3; i++) {
        window.add(
          sample('$i', now, ambient: 25 + i.toDouble()),
          now.add(Duration(seconds: i * 2)),
        );
      }
      expect(
        window.evaluate(now.add(const Duration(seconds: 4)), prepared: true),
        isNull,
      );
      window.add(
        sample('after-gap', now),
        now.add(const Duration(seconds: 10)),
      );
      expect(window.count, 1, reason: 'A connection gap resets the window');
    },
  );

  test(
    'personal trends exclude other people, unassigned samples, future and old dates',
    () {
      final now = DateTime(2026, 10, 10, 12);
      final rows = [
        sample(
          'latest',
          now,
          surface: 34,
          member: 'mom',
        ).withNote('After rest'),
        sample('first', DateTime(2026, 10, 4), surface: 30, member: 'mom'),
        sample(
          'same-day',
          now.subtract(const Duration(hours: 1)),
          surface: 32,
          member: 'mom',
        ),
        sample(
          'old',
          DateTime(2026, 10, 3, 23, 59),
          surface: 99,
          member: 'mom',
        ),
        sample('future', now.add(const Duration(hours: 1)), member: 'mom'),
        sample('dad', now, surface: 99, member: 'dad'),
        sample('raw', now, surface: 99),
      ];
      final trend = PersonalTrend(rows, 'mom', now, 7);
      expect(trend.readings.map((r) => r.id), ['first', 'same-day', 'latest']);
      expect(trend.average, 32);
      expect(trend.change, 4);
      expect(trend.dailyAverages.map((r) => r.celsius), [30, 33]);
      expect(trend.readings.last.note, 'After rest');
      expect(PersonalTrend(rows, 'unknown', now, 30).average, isNull);
      expect(PersonalTrend([rows.first], 'mom', now, 7).change, isNull);
    },
  );

  test(
    'legacy reminders migrate once and pending edits/deletions survive cloud snapshots',
    () async {
      final db = await databaseFactoryMemory.openDatabase('legacy-reminders');
      final store = AppStore(db, ownerId: 'a');
      const original = CareReminder(
        id: 'old',
        memberId: 'mom',
        hour: 8,
        minute: 0,
        weekdays: [1],
      );
      await store.setSetting('careReminders', [original.toJson()]);
      await store.migrateReminders();
      final write = (await store.pendingWrites()).single;
      await store.migrateReminders();
      expect((await store.pendingWrites()).single.revision, write.revision);
      await store.mergeCloudReminders([], authoritative: true);
      expect((await store.loadReminders()).single.id, 'old');
      await store.acknowledge(write);
      await store.mergeCloudReminders([], authoritative: false);
      expect(await store.loadReminders(), hasLength(1));
      await store.deleteReminder('old');
      await store.mergeCloudReminders([original], authoritative: true);
      expect(await store.loadReminders(), isEmpty);
      expect((await store.pendingWrites()).single.data, isNull);
      expect(await AppStore(db, ownerId: 'b').loadReminders(), isEmpty);
      await db.close();
    },
  );

  test(
    'two phones receive reminder edits and deletions; offline writes recover after restart',
    () async {
      final server = SharedDatabase();
      final db1 = await databaseFactoryMemory.openDatabase('phone-one');
      final db2 = await databaseFactoryMemory.openDatabase('phone-two');
      final gateway1 = ConnectedPhone(server);
      final store1 = AppStore(db1, ownerId: 'family');
      var one = MonitorController(store1, DeviceApi(), cloudGateway: gateway1);
      final two = MonitorController(
        AppStore(db2, ownerId: 'family'),
        DeviceApi(),
        cloudGateway: ConnectedPhone(server),
      );
      await one.initialize();
      await two.initialize();
      one.pause();
      two.pause();
      await one.saveMember(name: 'Mom', avatar: 10);
      await eventually(() => two.members.isNotEmpty, 'member creation');
      final member = two.members.single;
      CareReminder reminder(int hour) => CareReminder(
        id: 'shared',
        memberId: member.id,
        hour: hour,
        minute: 15,
        weekdays: [1, 3],
      );
      await one.saveReminder(reminder(9));
      await eventually(() => two.reminders.isNotEmpty, 'reminder creation');
      await two.saveReminder(two.reminders.single.withEnabled(false));
      await eventually(
        () => one.reminders.single.enabled == false,
        'reminder edit',
      );
      gateway1.offline = true;
      await one.saveReminder(reminder(20));
      await one.cloud!.flush();
      expect(two.reminders.single.hour, 9);
      expect(await store1.pendingWrites(), isNotEmpty);
      one.dispose();
      one = MonitorController(
        store1,
        DeviceApi(),
        cloudGateway: ConnectedPhone(server),
      );
      await one.initialize();
      one.pause();
      await eventually(
        () => two.reminders.single.hour == 20,
        'offline recovery',
      );
      const quality = MeasurementQuality(
        sampleCount: 3,
        surfaceRange: .2,
        ambientRange: .1,
        windowSeconds: 4,
        prepared: true,
      );
      final reading = sample(
        'synced',
        DateTime.now(),
      ).forMember(member).withQuality(quality).withNote('After rest');
      await store1.saveReadings([reading]);
      await one.cloud!.flush();
      await eventually(() => two.records.isNotEmpty, 'reading sync');
      expect(two.records.single.quality!.prepared, isTrue);
      expect(
        PersonalTrend(
          two.records,
          member.id,
          DateTime.now(),
          7,
        ).readings.single.note,
        'After rest',
      );
      await two.deleteReminder('shared');
      await eventually(() => one.reminders.isEmpty, 'reminder deletion');
      one.dispose();
      two.dispose();
      await server.changes.close();
      await db1.close();
      await db2.close();
    },
  );
}
