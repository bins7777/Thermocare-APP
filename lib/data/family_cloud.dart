import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models.dart';
import '../care_models.dart';
import 'store.dart';

class CloudSnapshot<T> {
  const CloudSnapshot(this.items, {this.authoritative = true});
  final List<T> items;
  final bool authoritative;
}

abstract interface class FamilyCloudGateway {
  Stream<CloudSnapshot<FamilyMember>> watchMembers();
  Stream<CloudSnapshot<Reading>> watchReadings();
  Stream<CloudSnapshot<CareReminder>> watchReminders();
  Future<void> write(PendingWrite write);
}

class FirestoreFamilyGateway implements FamilyCloudGateway {
  FirestoreFamilyGateway(FirebaseFirestore firestore, String uid)
    : family = firestore.collection('families').doc(uid);
  final DocumentReference<Map<String, dynamic>> family;

  @override
  Stream<CloudSnapshot<FamilyMember>> watchMembers() => family
      .collection('members')
      .snapshots(includeMetadataChanges: true)
      .map(
        (snapshot) => CloudSnapshot(
          snapshot.docs
              .map((doc) => FamilyMember.fromJson(doc.data()))
              .toList(),
          authoritative: !snapshot.metadata.isFromCache,
        ),
      );

  @override
  Stream<CloudSnapshot<Reading>> watchReadings() => family
      .collection('readings')
      .snapshots(includeMetadataChanges: true)
      .map(
        (snapshot) => CloudSnapshot(
          snapshot.docs.map((doc) => Reading.fromJson(doc.data())).toList(),
          authoritative: !snapshot.metadata.isFromCache,
        ),
      );

  @override
  Stream<CloudSnapshot<CareReminder>> watchReminders() => family
      .collection('reminders')
      .snapshots(includeMetadataChanges: true)
      .map(
        (snapshot) => CloudSnapshot(
          snapshot.docs
              .map((doc) => CareReminder.fromJson(doc.data()))
              .toList(),
          authoritative: !snapshot.metadata.isFromCache,
        ),
      );

  @override
  Future<void> write(PendingWrite write) => write.data == null
      ? family
            .collection(write.path.split('/').first)
            .doc(write.path.split('/').last)
            .delete()
      : family
            .collection(write.path.split('/').first)
            .doc(write.path.split('/').last)
            .set(write.data!);
}

/// Durable local outbox: saving never waits for an internet connection.
class FamilyCloudSync extends ChangeNotifier {
  FamilyCloudSync(this.store, this.gateway);
  final AppStore store;
  final FamilyCloudGateway gateway;
  bool syncing = false;
  int pending = 0;
  String? error;
  DateTime? lastSynced;
  bool _disposed = false;
  Timer? _retry;
  StreamSubscription? _members;
  StreamSubscription? _readings;
  StreamSubscription? _reminders;
  Future<void> Function()? _onData;

  void start(Future<void> Function() onData) {
    _onData = onData;
    _members = gateway.watchMembers().listen((snapshot) async {
      try {
        await store.mergeCloudMembers(
          snapshot.items,
          authoritative: snapshot.authoritative,
        );
        if (!_disposed) await _onData?.call();
      } catch (e) {
        _fail(e);
      }
    }, onError: _fail);
    _readings = gateway.watchReadings().listen((snapshot) async {
      try {
        await store.mergeCloudReadings(
          snapshot.items,
          authoritative: snapshot.authoritative,
        );
        if (!_disposed) await _onData?.call();
      } catch (e) {
        _fail(e);
      }
    }, onError: _fail);
    _reminders = gateway.watchReminders().listen((snapshot) async {
      try {
        await store.mergeCloudReminders(
          snapshot.items,
          authoritative: snapshot.authoritative,
        );
        if (!_disposed) await _onData?.call();
      } catch (e) {
        _fail(e);
      }
    }, onError: _fail);
    unawaited(flush());
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _fail(Object exception) {
    if (_disposed) return;
    error =
        exception is FirebaseException && exception.code == 'permission-denied'
        ? 'This change could not sync to your family account. Sign in again and retry. Your saved copy is still on this phone.'
        : 'Saved on this phone. Waiting to connect to your family account.';
    _notify();
  }

  Future<void> flush() async {
    if (_disposed || syncing) return;
    syncing = true;
    error = null;
    _retry?.cancel();
    _notify();
    try {
      var writes = await store.pendingWrites();
      pending = writes.length;
      _notify();
      while (writes.isNotEmpty && !_disposed) {
        for (final write in writes) {
          if (_disposed) return;
          await gateway.write(write).timeout(const Duration(seconds: 6));
          if (_disposed) return;
          await store.acknowledge(write);
          lastSynced = DateTime.now();
        }
        writes = await store.pendingWrites();
        pending = writes.length;
        _notify();
      }
    } catch (e) {
      _fail(e);
      if (!_disposed) {
        _retry = Timer(const Duration(seconds: 12), () => unawaited(flush()));
      }
    } finally {
      syncing = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    unawaited(_members?.cancel());
    unawaited(_readings?.cancel());
    unawaited(_reminders?.cancel());
    super.dispose();
  }
}
