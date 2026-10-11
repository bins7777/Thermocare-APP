import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:thermocare/controller.dart';
import 'package:thermocare/data/device_api.dart';
import 'package:thermocare/data/store.dart';
import 'package:thermocare/models.dart';
import 'capture_fixture.dart';

Map<String, dynamic> sample({
  int seq = 1,
  int age = 100,
  int? epoch = 1791504000,
}) => {
  'device_id': 'uno-1234',
  'boot_id': '42',
  'sequence': seq,
  'sensor_ok': true,
  'object_c': 36.6,
  'ambient_c': 25.1,
  'epoch': epoch,
  'age_ms': age,
};

void main() {
  test(
    'switching from a pending home request to the offline Arduino waits and actually connects',
    () async {
      final db = await databaseFactoryMemory.openDatabase('switch-to-ap');
      final homeRequest = Completer<http.Response>();
      final homeStarted = Completer<void>();
      var apRequests = 0;
      final c = MonitorController(
        AppStore(db),
        DeviceApi(
          client: MockClient((request) async {
            if (request.url.host == '192.168.1.42') {
              if (!homeStarted.isCompleted) homeStarted.complete();
              return homeRequest.future;
            }
            expect(request.url.host, '192.168.4.1');
            if (request.url.path == '/api/history') {
              return http.Response('[]', 200);
            }
            apRequests++;
            return http.Response(jsonEncode(sample(seq: 2, epoch: null)), 200);
          }),
        ),
      );
      await c.initialize();
      final home = c.connect('192.168.1.42');
      await homeStarted.future;
      final direct = c.connect('192.168.4.1');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(apRequests, 0);
      homeRequest.complete(http.Response(jsonEncode(sample()), 200));
      await Future.wait([home, direct]);
      expect(apRequests, 1);
      expect(c.fresh, isTrue);
      expect(c.latest!.id, endsWith('/2'));
      expect(c.latest!.estimatedTime, isTrue);
      expect(c.error, isNull);
      expect(c.records.single.id, c.latest!.id);
      expect(await c.store.setting('address'), 'http://192.168.4.1');
      c.dispose();
      await db.close();
    },
  );

  test(
    'disconnect cancels an explicit reconnect waiting for an old request',
    () async {
      final db = await databaseFactoryMemory.openDatabase(
        'cancel-waiting-connect',
      );
      final pending = Completer<http.Response>();
      final started = Completer<void>();
      var requests = 0;
      final c = MonitorController(
        AppStore(db),
        DeviceApi(
          client: MockClient((_) async {
            requests++;
            if (!started.isCompleted) started.complete();
            return pending.future;
          }),
        ),
      );
      await c.initialize();
      final first = c.connect('192.168.1.42');
      await started.future;
      final next = c.connect('192.168.4.1');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      c.disconnect();
      pending.complete(http.Response(jsonEncode(sample()), 200));
      await Future.wait([first, next]);
      expect(requests, 1);
      expect(c.active, isFalse);
      expect(c.latest, isNull);
      expect(c.records, isEmpty);
      c.dispose();
      await db.close();
    },
  );

  test(
    'first launch starts empty and never invents readings or family profiles',
    () async {
      final db = await databaseFactoryMemory.openDatabase(
        'first-product-launch',
      );
      final c = MonitorController(AppStore(db), DeviceApi());
      await c.initialize();
      await c.poll();
      expect(c.active, isFalse);
      expect(c.latest, isNull);
      expect(c.records, isEmpty);
      expect(c.members, isEmpty);
      expect(c.reminders, isEmpty);
      expect(await c.store.pendingWrites(), isEmpty);
      c.dispose();
      await db.close();
    },
  );

  test(
    'opening the app restores the address without acquiring idle readings',
    () async {
      final db = await databaseFactoryMemory.openDatabase('restore-connection');
      final store = AppStore(db);
      await store.setSetting('address', 'http://192.168.4.1');
      var requests = 0;
      final c = MonitorController(
        store,
        DeviceApi(
          client: MockClient((request) async {
            requests++;
            return http.Response(
              jsonEncode(request.url.path == '/api/history' ? [] : sample()),
              200,
            );
          }),
        ),
      );
      await c.initialize();
      c.resume();
      expect(requests, 0);
      expect(c.active, isTrue);
      expect(c.latest, isNull);
      expect(c.address, 'http://192.168.4.1');
      expect(c.records, isEmpty);
      await c.poll();
      expect(c.fresh, isTrue);
      expect(c.records.single.memberId, isNull);
      expect(c.members, isEmpty);
      c.dispose();
      await db.close();
    },
  );
  test(
    'each live poll enters History without waiting for the minute buffer',
    () async {
      final db = await databaseFactoryMemory.openDatabase('live-history');
      var sequence = 1;
      var historyRequests = 0;
      final c = MonitorController(
        AppStore(db, ownerId: 'family-a'),
        DeviceApi(
          client: MockClient((request) async {
            if (request.url.path == '/api/history') {
              historyRequests++;
              return http.Response(jsonEncode([sample(seq: 0)]), 200);
            }
            return http.Response(
              jsonEncode(sample(seq: sequence, epoch: 1791504000 + sequence)),
              200,
            );
          }),
        ),
      );
      await c.initialize();
      await c.connect('device.local');
      c.pause();
      expect(c.records, hasLength(2));
      expect(c.records.first.id, endsWith('/1'));
      sequence = 2;
      await c.poll();
      expect(c.records, hasLength(3));
      expect(c.records.first.id, endsWith('/2'));
      expect(c.records.first.memberId, isNull);
      expect(
        historyRequests,
        1,
        reason: 'Live History must update between buffer imports',
      );
      expect(
        await c.store.pendingWrites(),
        isEmpty,
        reason: 'Automatic samples never upload as family measurements',
      );
      await c.saveMember(name: 'Mom', avatar: 10);
      seedStableCapture(c);
      await c.saveCurrent(prepared: true);
      final memberId = c.selectedMember!.id;
      expect(c.records, hasLength(3));
      expect(c.records.first.memberId, memberId);
      await c.poll();
      expect(
        c.records,
        hasLength(3),
        reason: 'Repeated sensor sequence must not duplicate history',
      );
      expect(
        c.records.first.memberId,
        memberId,
        reason: 'Polling must not erase who a reading was saved for',
      );
      sequence = 3;
      await c.poll();
      expect(c.records, hasLength(4));
      expect(
        c.records.first.memberId,
        isNull,
        reason: 'New samples must not guess the person',
      );
      c.dispose();
      expect(
        await AppStore(db, ownerId: 'family-a').loadReadings(),
        hasLength(4),
      );
      await db.close();
    },
  );

  test(
    'live history still advances when the Arduino buffer request fails',
    () async {
      final db = await databaseFactoryMemory.openDatabase('history-failure');
      var sequence = 1;
      final c = MonitorController(
        AppStore(db),
        DeviceApi(
          client: MockClient((request) async {
            return request.url.path == '/api/history'
                ? http.Response('unavailable', 503)
                : http.Response(
                    jsonEncode(
                      sample(seq: sequence, epoch: 1791504000 + sequence),
                    ),
                    200,
                  );
          }),
        ),
      );
      await c.initialize();
      await c.connect('device.local');
      c.pause();
      expect(c.fresh, isTrue);
      expect(c.records, hasLength(1));
      expect(c.syncWarning, isNotNull);
      sequence++;
      await c.poll();
      expect(c.records, hasLength(2));
      expect(c.error, isNull);
      c.dispose();
      await db.close();
    },
  );
  test('parses RTC UTC time and estimates missing clock using sample age', () {
    expect(Reading.fromApi(sample()).at.isUtc, isTrue);
    final received = DateTime.utc(2026, 10, 9, 10);
    final r = Reading.fromApi(
      sample(age: 60000, epoch: null),
      receivedAt: received,
    );
    expect(r.at, received.subtract(const Duration(minutes: 1)));
    expect(r.estimatedTime, isTrue);
  });

  test('rejects sensor failure, non-finite values and malformed identity', () {
    for (final invalid in [
      {...sample(), 'sensor_ok': false},
      {...sample(), 'object_c': double.nan},
      {...sample(), 'object_c': 1000},
      {...sample(), 'ambient_c': '25'},
      {...sample(), 'sequence': null},
      {...sample(), 'age_ms': -1},
    ]) {
      expect(() => Reading.fromApi(invalid), throwsFormatException);
    }
  });

  test(
    'normalizes device host and rejects paths, credentials and bad ports',
    () {
      expect(deviceUri('192.168.1.42').toString(), 'http://192.168.1.42');
      expect(deviceUri('http://thermo.local:8080/').port, 8080);
      for (final invalid in [
        '',
        'ftp://device',
        'http://name:password@device',
        'http://device/path',
        'http://device?key=1',
        'bad host',
        'device:99999',
      ]) {
        expect(
          () => deviceUri(invalid),
          throwsFormatException,
          reason: invalid,
        );
      }
    },
  );

  test('unit conversion and CSV retain canonical Celsius', () {
    expect(TemperatureUnit.fahrenheit.format(37), '98.6');
    final r = Reading.fromApi(sample());
    final csv = readingsCsv([r]);
    expect(csv, contains('36.60,25.10'));
    expect(csv.split('\r\n').length, 3);
  });

  test('deduplicates records and restores settings', () async {
    final db = await databaseFactoryMemory.openDatabase('persistence');
    final store = AppStore(db);
    final r = Reading.fromApi(sample());
    await store.saveReadings([r, r]);
    await store.setSetting('threshold', 38.5);
    final restored = AppStore(db);
    expect((await restored.loadReadings()).single.id, r.id);
    expect(await restored.setting('threshold'), 38.5);
    await db.close();
  });

  test(
    'HTTP client handles stale data, sensor errors and invalid JSON',
    () async {
      for (final response in [
        http.Response(jsonEncode(sample(age: 6000)), 200),
        http.Response('{}', 503),
        http.Response('not json', 200),
      ]) {
        final api = DeviceApi(client: MockClient((_) async => response));
        await expectLater(
          api.latest(Uri.parse('http://device')),
          throwsFormatException,
        );
        api.dispose();
      }
    },
  );

  test('disconnect discards delayed live network results', () async {
    final db = await databaseFactoryMemory.openDatabase('generation');
    final pending = Completer<http.Response>();
    final c = MonitorController(
      AppStore(db),
      DeviceApi(client: MockClient((_) => pending.future)),
    );
    await c.initialize();
    final connecting = c.connect('192.168.1.42');
    await Future<void>.delayed(Duration.zero);
    c.disconnect();
    pending.complete(http.Response(jsonEncode(sample()), 200));
    await connecting;
    expect(c.active, isFalse);
    expect(c.latest, isNull);
    await expectLater(c.saveCurrent(), throwsStateError);
    expect(await c.store.loadReadings(), isEmpty);
    c.dispose();
    await db.close();
  });

  test(
    'failed refresh marks last reading unavailable and prevents saving it',
    () async {
      final db = await databaseFactoryMemory.openDatabase('disconnect');
      var fail = false;
      final api = DeviceApi(
        client: MockClient((request) async {
          if (fail) {
            throw http.ClientException('offline');
          }
          return http.Response(
            jsonEncode(
              request.url.path == '/api/history' ? [sample()] : sample(),
            ),
            200,
          );
        }),
      );
      final c = MonitorController(AppStore(db), api);
      await c.initialize();
      await c.connect('device.local');
      expect(c.fresh, isTrue);
      expect(c.records, hasLength(1));
      fail = true;
      await c.poll();
      expect(c.fresh, isFalse);
      expect(c.error, isNotNull);
      await expectLater(c.saveCurrent(), throwsStateError);
      c.dispose();
      await db.close();
    },
  );
}
