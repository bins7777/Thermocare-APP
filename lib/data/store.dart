import 'package:sembast/sembast.dart';
import 'dart:convert';
import '../models.dart';
import '../care_models.dart';

class AppStore {
  AppStore(this.database, {this.ownerId});
  final Database database;
  final String? ownerId;
  String _scope(String name) =>
      ownerId == null ? name : 'account/$ownerId/$name';
  late final _readings = stringMapStoreFactory.store(_scope('readings'));
  late final _members = stringMapStoreFactory.store(_scope('members'));
  late final _reminders = stringMapStoreFactory.store(_scope('reminders'));
  late final _outbox = stringMapStoreFactory.store(_scope('outbox'));
  late final _settings = StoreRef<String, Object?>(_scope('settings'));

  static String readingDocumentId(String id) =>
      base64Url.encode(utf8.encode(id)).replaceAll('=', '');

  Future<void> _queue(
    DatabaseClient txn,
    String path,
    Map<String, Object?>? data,
  ) async {
    if (ownerId == null) return;
    await _outbox.record(path).put(txn, {
      'path': path,
      'data': data,
      'revision': newFamilyId(),
    });
  }

  Future<List<Reading>> loadReadings() async => (await _readings.find(
    database,
    finder: Finder(sortOrders: [SortOrder('at', false)]),
  )).map((r) => Reading.fromJson(r.value)).toList();

  Future<void> saveReadings(
    Iterable<Reading> readings,
  ) => database.transaction((txn) async {
    for (final r in readings) {
      final existing = await _readings.record(r.id).get(txn);
      if (existing?['memberId'] != null) {
        if (r.memberId == null) continue;
        if (existing!['memberId'] != r.memberId) {
          throw const FormatException(
            'This sample is already saved for someone else. Get a fresh reading first.',
          );
        }
        // A second save keeps the original measurement and attribution.
        continue;
      }
      final data = r.toJson();
      // Incoming automatic samples must not erase a locally written note.
      if (r.note.isEmpty && existing?['note'] != null) {
        data['note'] = existing!['note'];
      }
      await _readings.record(r.id).put(txn, data);
      if (r.memberId != null) {
        await _queue(txn, 'readings/${readingDocumentId(r.id)}', data);
      }
    }
  });
  Future<void> updateNote(String id, String note) => database.transaction((
    txn,
  ) async {
    if (note.length > 500) {
      throw const FormatException('Keep your note within 500 characters.');
    }
    final existing = await _readings.record(id).get(txn);
    if (existing == null) throw StateError('This reading is no longer saved.');
    final reading = Reading.fromJson(existing).withNote(note.trim());
    await _readings.record(id).put(txn, reading.toJson());
    if (reading.memberId != null) {
      await _queue(txn, 'readings/${readingDocumentId(id)}', reading.toJson());
    }
  });
  Future<void> clearReadings() async {
    await database.transaction((txn) async {
      for (final record in await _readings.find(txn)) {
        if (record.value['memberId'] != null) {
          await _queue(txn, 'readings/${readingDocumentId(record.key)}', null);
        }
      }
      await _readings.delete(txn);
    });
  }

  Future<List<FamilyMember>> loadMembers() async =>
      (await _members.find(
          database,
        )).map((r) => FamilyMember.fromJson(r.value)).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  Future<void> saveMember(FamilyMember member) =>
      database.transaction((txn) async {
        await _members.record(member.id).put(txn, member.toJson());
        await _queue(txn, 'members/${member.id}', member.toJson());
      });

  Future<List<PendingWrite>> pendingWrites() async =>
      (await _outbox.find(
          database,
        )).map((r) => PendingWrite.fromJson(r.value)).toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  Future<List<CareReminder>> loadReminders() async =>
      (await _reminders.find(
          database,
        )).map((r) => CareReminder.fromJson(r.value)).toList()
        ..sort((a, b) => a.id.compareTo(b.id));

  Future<void> saveReminder(CareReminder reminder) =>
      database.transaction((txn) async {
        await _reminders.record(reminder.id).put(txn, reminder.toJson());
        await _queue(txn, 'reminders/${reminder.id}', reminder.toJson());
      });

  Future<void> deleteReminder(String id) => database.transaction((txn) async {
    await _reminders.record(id).delete(txn);
    await _queue(txn, 'reminders/$id', null);
  });

  /// One-time migration preserves reminders created by previous app versions.
  Future<void> migrateReminders() => database.transaction((txn) async {
    if (await _settings.record('remindersMigrated').get(txn) == true) return;
    final legacy =
        (await _settings.record('careReminders').get(txn) as List?) ?? [];
    for (final item in legacy) {
      final reminder = CareReminder.fromJson(
        Map<String, dynamic>.from(item as Map),
      );
      await _reminders.record(reminder.id).put(txn, reminder.toJson());
      await _queue(txn, 'reminders/${reminder.id}', reminder.toJson());
    }
    await _settings.record('careReminders').delete(txn);
    await _settings.record('remindersMigrated').put(txn, true);
  });

  Future<void> mergeCloudReminders(
    List<CareReminder> reminders, {
    required bool authoritative,
  }) => database.transaction((txn) async {
    final ids = reminders.map((r) => r.id).toSet();
    for (final r in reminders) {
      if (await _outbox.record('reminders/${r.id}').exists(txn)) continue;
      await _reminders.record(r.id).put(txn, r.toJson());
    }
    if (authoritative) {
      for (final local in await _reminders.find(txn)) {
        if (!ids.contains(local.key) &&
            !await _outbox.record('reminders/${local.key}').exists(txn)) {
          await _reminders.record(local.key).delete(txn);
        }
      }
    }
  });

  Future<void> acknowledge(PendingWrite write) =>
      database.transaction((txn) async {
        if ((await _outbox.record(write.path).get(txn))?['revision'] ==
            write.revision) {
          await _outbox.record(write.path).delete(txn);
        }
      });

  Future<void> mergeCloudMembers(
    List<FamilyMember> members, {
    required bool authoritative,
  }) => database.transaction((txn) async {
    final ids = members.map((m) => m.id).toSet();
    for (final m in members) {
      if (await _outbox.record('members/${m.id}').exists(txn)) continue;
      await _members.record(m.id).put(txn, m.toJson());
    }
    if (authoritative) {
      for (final local in await _members.find(txn)) {
        if (!ids.contains(local.key) &&
            !await _outbox.record('members/${local.key}').exists(txn)) {
          await _members.record(local.key).delete(txn);
        }
      }
    }
  });

  Future<void> mergeCloudReadings(
    List<Reading> readings, {
    required bool authoritative,
  }) => database.transaction((txn) async {
    final ids = readings.map((r) => r.id).toSet();
    for (final r in readings.where((r) => r.memberId != null)) {
      if (await _outbox
          .record('readings/${readingDocumentId(r.id)}')
          .exists(txn)) {
        continue;
      }
      await _readings.record(r.id).put(txn, r.toJson());
    }
    if (authoritative) {
      for (final local in await _readings.find(txn)) {
        if (local.value['memberId'] != null &&
            !ids.contains(local.key) &&
            !await _outbox
                .record('readings/${readingDocumentId(local.key)}')
                .exists(txn)) {
          await _readings.record(local.key).delete(txn);
        }
      }
    }
  });

  Future<Object?> setting(String key) => _settings.record(key).get(database);
  Future<void> setSetting(String key, Object? value) async {
    await _settings.record(key).put(database, value);
  }
}

class PendingWrite {
  const PendingWrite({required this.path, required this.revision, this.data});
  final String path;
  final String revision;
  final Map<String, Object?>? data;
  factory PendingWrite.fromJson(Map<String, dynamic> json) => PendingWrite(
    path: json['path'] as String,
    revision: json['revision'] as String,
    data: json['data'] == null
        ? null
        : Map<String, Object?>.from(json['data'] as Map),
  );
}
