import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:thermocare/controller.dart';
import 'package:thermocare/data/device_api.dart';
import 'package:thermocare/data/store.dart';
import 'package:thermocare/models.dart';
import 'package:thermocare/ui/app.dart';
import 'package:thermocare/ui/care_pages.dart';
import 'capture_fixture.dart';

Reading reading(
  String id,
  double temperature, {
  String? member,
  int minute = 0,
}) => Reading(
  id: id,
  celsius: temperature,
  ambient: 25,
  at: DateTime.now().add(Duration(minutes: minute)),
  deviceId: 'uno',
  memberId: member,
  memberName: member == 'mom' ? 'Mom' : member,
);

void main() {
  test(
    'idle connection and resume never poll; capture is the only automatic polling session',
    () async {
      final db = await databaseFactoryMemory.openDatabase('on-demand');
      var requests = 0;
      final c = MonitorController(
        AppStore(db),
        DeviceApi(
          client: MockClient((request) async {
            if (request.url.path == '/api/history') {
              return http.Response('[]', 200);
            }
            requests++;
            return http.Response(
              jsonEncode({
                'device_id': 'uno',
                'boot_id': '1',
                'sequence': requests,
                'sensor_ok': true,
                'object_c': 32,
                'ambient_c': 25,
                'age_ms': 0,
                'epoch': DateTime.now().millisecondsSinceEpoch ~/ 1000,
              }),
              200,
            );
          }),
        ),
      );
      await c.initialize();
      await c.connect('device.local');
      expect(requests, 1);
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      expect(requests, 1);
      c.pause();
      c.resume();
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      expect(requests, 1);
      await c.poll();
      expect(requests, 2);
      c.beginMeasurement();
      await Future<void>.delayed(const Duration(milliseconds: 2300));
      expect(requests, greaterThanOrEqualTo(4));
      c.endMeasurement();
      final stopped = requests;
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      expect(requests, stopped);
      expect(c.hasReading, isTrue);
      c.dispose();
      await db.close();
    },
  );

  testWidgets('an unattended guided sampling session stops after one minute', (
    tester,
  ) async {
    final db = await tester.runAsync(
      () => databaseFactoryMemory.openDatabase('sampling-timeout'),
    );
    final pending = Completer<http.Response>();
    final c = MonitorController(
      AppStore(db!),
      DeviceApi(client: MockClient((_) => pending.future)),
    );
    c.active = true;
    c.address = 'http://device.local';
    c.beginMeasurement();
    expect(c.measuring, isTrue);
    await tester.pump(const Duration(seconds: 61));
    expect(c.measuring, isFalse);
    expect(c.busy, isFalse);
    pending.complete(http.Response('{}', 200));
    await tester.pump();
    c.dispose();
    await tester.runAsync(db.close);
  });

  test(
    'alerts restore from the family database, follow the selected person and clear after a newer lower check-in',
    () async {
      final db = await databaseFactoryMemory.openDatabase('persisted-alert');
      final store = AppStore(db, ownerId: 'family');
      await store.saveMember(const FamilyMember(id: 'mom', name: 'Mom'));
      await store.saveMember(const FamilyMember(id: 'dad', name: 'Dad'));
      await store.setSetting('selectedMember', 'mom');
      await store.setSetting('threshold', 38.5);
      await store.saveReadings([
        reading('high', 38.5, member: 'mom'),
        reading('raw', 45, minute: 1),
        reading('dad', 37, member: 'dad'),
      ]);
      final c = MonitorController(store, DeviceApi());
      await c.initialize();
      expect(c.temperatureAlert!.id, 'high');
      await c.setUnit(TemperatureUnit.fahrenheit);
      expect(c.temperatureAlert!.id, 'high');
      await c.selectMember('dad');
      expect(c.temperatureAlert, isNull);
      await c.selectMember('mom');
      c.dispose();
      final restored = MonitorController(
        AppStore(db, ownerId: 'family'),
        DeviceApi(),
      );
      await restored.initialize();
      expect(restored.temperatureAlert!.id, 'high');
      expect(restored.threshold, 38.5);
      expect(restored.unit, TemperatureUnit.fahrenheit);
      await restored.store.saveReadings([
        reading('lower', 38.4, member: 'mom', minute: 2),
      ]);
      restored.dispose();
      final updated = MonitorController(
        AppStore(db, ownerId: 'family'),
        DeviceApi(),
      );
      await updated.initialize();
      expect(updated.temperatureAlert, isNull);
      expect(
        (await store.pendingWrites()).where(
          (w) => w.path.startsWith('readings/'),
        ),
        hasLength(3),
      );
      updated.dispose();
      final other = MonitorController(
        AppStore(db, ownerId: 'other-family'),
        DeviceApi(),
      );
      await other.initialize();
      expect(other.temperatureAlert, isNull);
      other.dispose();
      await db.close();
    },
  );

  testWidgets('high check-in warns once on save and remains visible on Home', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = await tester.runAsync(
      () => databaseFactoryMemory.openDatabase('alert-ui'),
    );
    final c = MonitorController(AppStore(db!), DeviceApi());
    await tester.runAsync(() async {
      await (FontLoader(
        'Nunito',
      )..addFont(rootBundle.load('assets/fonts/Nunito.ttf'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      await c.initialize();
      await c.saveMember(name: 'Mom', avatar: 10);
      c.active = true;
      c.latest = reading('captured-high', 38.5);
      c.lastContact = DateTime.now();
      c.pause();
    });
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: ThermoCareApp(controller: c),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    Future<void> tap(String label) async {
      final finder = find.text(label);
      await tester.ensureVisible(finder);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(finder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    await tap('Save reading');
    expect(find.byType(GuidedCheckIn), findsOneWidget);
    await tap('Let’s begin');
    for (final label in [
      'Rested indoors, away from direct heat or drafts',
      'Same exposed skin site as previous check-ins',
      'Sensor aimed and held at the validated device distance',
    ]) {
      await tap(label);
    }
    seedStableCapture(c);
    c.dismissReminder();
    await tester.pump();
    await tap('Capture reading');
    expect(c.measuring, isFalse);
    expect(find.text('High temperature alert'), findsOneWidget);
    final save = find.text('Save check-in');
    await tester.ensureVisible(save);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(() async {
      await tester.tap(save);
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(c.temperatureAlert!.memberId, c.selectedMember!.id);
    await tap('Understood');
    await tap('All done');
    expect(find.text('High temperature alert'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.ensureVisible(find.text('High temperature alert'));
    await tester.pump(const Duration(milliseconds: 900));
    await tester.runAsync(() async {
      await Directory('artifacts').create(recursive: true);
      final image =
          await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        'artifacts/high-temperature-alert.png',
      ).writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(db.close);
  });
}
