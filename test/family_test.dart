import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:thermocare/controller.dart';
import 'package:thermocare/data/device_api.dart';
import 'package:thermocare/data/family_cloud.dart';
import 'package:thermocare/data/store.dart';
import 'package:thermocare/models.dart';
import 'package:thermocare/care_models.dart';
import 'capture_fixture.dart';

const mom = FamilyMember(id: 'mom', name: 'Mom');
const dad = FamilyMember(id: 'dad', name: 'Dad', avatar: 1);
Reading raw([String id = 'uno/1/1']) => Reading(
  id: id,
  celsius: 36.5,
  ambient: 25,
  at: DateTime.utc(2026, 10, 9),
  deviceId: 'uno',
);

class FakeCloud implements FamilyCloudGateway {
  bool offline = false;
  final writes = <String, Map<String, Object?>?>{};
  final memberStream =
      StreamController<CloudSnapshot<FamilyMember>>.broadcast();
  final readingStream = StreamController<CloudSnapshot<Reading>>.broadcast();
  final reminderStream =
      StreamController<CloudSnapshot<CareReminder>>.broadcast();
  @override
  Stream<CloudSnapshot<FamilyMember>> watchMembers() => memberStream.stream;
  @override
  Stream<CloudSnapshot<Reading>> watchReadings() => readingStream.stream;
  @override
  Stream<CloudSnapshot<CareReminder>> watchReminders() => reminderStream.stream;
  @override
  Future<void> write(PendingWrite write) async {
    if (offline) throw StateError('Offline');
    writes[write.path] = write.data;
  }

  Future<void> close() async {
    await memberStream.close();
    await readingStream.close();
    await reminderStream.close();
  }
}

void main() {
  test(
    'cloud snapshots restore family profiles and readings into the active account',
    () async {
      final db = await databaseFactoryMemory.openDatabase('incoming');
      final gateway = FakeCloud();
      final c = MonitorController(
        AppStore(db, ownerId: 'a'),
        DeviceApi(),
        cloudGateway: gateway,
      );
      await c.initialize();
      gateway.memberStream.add(const CloudSnapshot([mom]));
      gateway.readingStream.add(CloudSnapshot([raw().forMember(mom)]));
      for (
        var i = 0;
        i < 100 && (c.members.isEmpty || c.records.isEmpty);
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(c.members.single.name, 'Mom');
      expect(c.records.single.memberId, 'mom');
      expect(
        await c.store.pendingWrites(),
        isEmpty,
        reason: 'Downloads must not upload again',
      );
      expect(await AppStore(db, ownerId: 'b').loadReadings(), isEmpty);
      c.dispose();
      await gateway.close();
      await db.close();
    },
  );
  test(
    'assigned readings survive automatic history and cannot change person',
    () async {
      final db = await databaseFactoryMemory.openDatabase('attribution');
      final store = AppStore(db, ownerId: 'a');
      await store.saveMember(mom);
      await store.saveReadings([raw()]);
      expect(
        (await store.pendingWrites()).length,
        1,
        reason: 'Raw samples never upload',
      );
      await store.saveReadings([raw().forMember(mom)]);
      await store.saveReadings([raw()]);
      expect((await store.loadReadings()).single.memberId, mom.id);
      final queued = await store.pendingWrites();
      await store.saveReadings([raw().forMember(mom)]);
      expect((await store.pendingWrites()).last.revision, queued.last.revision);
      await expectLater(
        store.saveReadings([raw().forMember(dad)]),
        throwsFormatException,
      );
      expect((await store.loadReadings()).single.memberId, mom.id);
      await db.close();
    },
  );

  test(
    'one family account is isolated from other accounts and signed-out mode',
    () async {
      final db = await databaseFactoryMemory.openDatabase('accounts');
      final a = AppStore(db, ownerId: 'a');
      final b = AppStore(db, ownerId: 'b');
      final local = AppStore(db);
      await a.saveMember(mom);
      await a.saveReadings([raw().forMember(mom)]);
      await a.setSetting('selectedMember', mom.id);
      for (final other in [b, local]) {
        expect(await other.loadMembers(), isEmpty);
        expect(await other.loadReadings(), isEmpty);
        expect(await other.pendingWrites(), isEmpty);
        expect(await other.setting('selectedMember'), isNull);
      }
      expect(
        (await AppStore(db, ownerId: 'a').loadMembers()).single.name,
        'Mom',
      );
      await db.close();
    },
  );

  test('an older upload cannot acknowledge a newer edit', () async {
    final db = await databaseFactoryMemory.openDatabase('revision');
    final store = AppStore(db, ownerId: 'a');
    await store.saveMember(mom);
    final old = (await store.pendingWrites()).single;
    await store.saveMember(mom.copyWith(name: 'Mama'));
    await store.acknowledge(old);
    expect((await store.pendingWrites()).single.data!['name'], 'Mama');
    await store.mergeCloudMembers([mom], authoritative: true);
    expect((await store.loadMembers()).single.name, 'Mama');
    await db.close();
  });

  test(
    'offline saves persist across reopening and upload members before readings',
    () async {
      final db = await databaseFactoryMemory.openDatabase('offline');
      final store = AppStore(db, ownerId: 'a');
      await store.saveMember(mom);
      await store.saveReadings([raw().forMember(mom)]);
      final gateway = FakeCloud()..offline = true;
      final sync = FamilyCloudSync(store, gateway);
      await sync.flush();
      expect(sync.error, isNotNull);
      expect(await store.pendingWrites(), hasLength(2));
      sync.dispose();
      gateway.offline = false;
      final restored = AppStore(db, ownerId: 'a');
      final resumed = FamilyCloudSync(restored, gateway);
      await resumed.flush();
      expect(gateway.writes.keys.first, 'members/mom');
      expect(gateway.writes.keys.last, startsWith('readings/'));
      expect(await restored.pendingWrites(), isEmpty);
      expect(resumed.lastSynced, isNotNull);
      resumed.dispose();
      await gateway.close();
      await db.close();
    },
  );

  test(
    'remote deletion merges without erasing local pending changes or raw samples',
    () async {
      final db = await databaseFactoryMemory.openDatabase('merge');
      final store = AppStore(db, ownerId: 'a');
      await store.saveMember(mom);
      await store.saveReadings([raw().forMember(mom), raw('uno/1/2')]);
      await store.mergeCloudReadings([], authoritative: true);
      expect(await store.loadReadings(), hasLength(2));
      for (final write in await store.pendingWrites()) {
        await store.acknowledge(write);
      }
      await store.mergeCloudReadings([], authoritative: false);
      expect(
        await store.loadReadings(),
        hasLength(2),
        reason: 'Offline snapshots cannot delete',
      );
      await store.mergeCloudReadings([], authoritative: true);
      expect((await store.loadReadings()).single.memberId, isNull);
      await store.mergeCloudReadings([
        raw().forMember(mom),
      ], authoritative: true);
      await store.clearReadings();
      await store.mergeCloudReadings([
        raw().forMember(mom),
      ], authoritative: true);
      expect(
        await store.loadReadings(),
        isEmpty,
        reason: 'Pending deletion cannot be resurrected',
      );
      expect((await store.pendingWrites()).single.data, isNull);
      await db.close();
    },
  );

  test(
    'profiles select, archive, restore and preserve their saved attribution',
    () async {
      final db = await databaseFactoryMemory.openDatabase('profiles');
      final store = AppStore(db, ownerId: 'a');
      final c = MonitorController(store, DeviceApi());
      await c.initialize();
      c.active = true;
      c.latest = raw();
      c.lastContact = DateTime.now();
      await expectLater(c.saveCurrent(), throwsFormatException);
      await c.saveMember(name: '  Lily  ', avatar: 8);
      final lily = c.selectedMember!;
      expect(lily.name, 'Lily');
      seedStableCapture(c);
      await c.saveCurrent(prepared: true);
      await c.saveMember(
        existing: lily,
        name: 'Lil',
        avatar: 8,
        archived: true,
      );
      expect(c.selectedMember, isNull);
      expect(c.memberName(c.records.single), 'Lil');
      expect(
        c.records.single.memberName,
        'Lily',
        reason: 'Keep name at measurement time',
      );
      await c.saveMember(
        existing: lily,
        name: 'Lil',
        avatar: 8,
        archived: false,
      );
      expect(c.selectedMember?.id, lily.id);
      final queued = (await store.pendingWrites()).length;
      seedStableCapture(c);
      await c.saveCurrent(prepared: true);
      expect((await store.pendingWrites()).length, queued);
      expect(c.members.single.name, 'Lil');
      c.dispose();
      final restored = MonitorController(
        AppStore(db, ownerId: 'a'),
        DeviceApi(),
      );
      await restored.initialize();
      expect(restored.selectedMember?.id, lily.id);
      expect(restored.selectedMember?.avatar, 8);
      restored.dispose();
      await db.close();
    },
  );

  test('CSV exports family attribution and escapes names safely', () {
    final csv = readingsCsv([
      raw().forMember(const FamilyMember(id: 'a', name: 'Lily, "Lil"')),
      raw('uno/1/2'),
    ]);
    expect(csv, contains('member_id,member_name'));
    expect(csv, contains('"Lily, ""Lil"""'));
    expect(csv, contains('"Unassigned"'));
    expect(readingsCsv([]).split('\r\n'), hasLength(2));
  });
}
