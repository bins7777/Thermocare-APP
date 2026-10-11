import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:thermocare/controller.dart';
import 'package:thermocare/data/device_api.dart';
import 'package:thermocare/data/store.dart';
import 'package:thermocare/ui/app.dart';

void main() {
  testWidgets(
    'direct Wi-Fi button replaces the home address and reads locally without a cloud service',
    (tester) async {
      final setup = await tester.runAsync(() async {
        final db = await databaseFactoryMemory.openDatabase('direct-wifi-ui');
        final store = AppStore(db);
        await store.setSetting('address', 'http://192.168.1.42');
        final hosts = <String>[];
        final c = MonitorController(
          store,
          DeviceApi(
            client: MockClient((request) async {
              hosts.add(request.url.host);
              expect(request.url.host, '192.168.4.1');
              return http.Response(
                jsonEncode(
                  request.url.path == '/api/history'
                      ? []
                      : {
                          'device_id': 'uno',
                          'boot_id': '1',
                          'sequence': 1,
                          'sensor_ok': true,
                          'object_c': 32.5,
                          'ambient_c': 25,
                          'age_ms': 100,
                          'epoch': null,
                        },
                ),
                200,
              );
            }),
          ),
        );
        await c.initialize();
        return (db, c, hosts);
      });
      final (db, c, hosts) = setup!;
      await tester.pumpWidget(ThermoCareApp(controller: c));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      await tester.tap(find.text('My device').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      final direct = find.text('Connect on ThermoCare Wi-Fi');
      await tester.ensureVisible(direct);
      await tester.pump(const Duration(milliseconds: 900));
      await tester.runAsync(() async {
        await tester.tap(direct);
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      expect(c.address, 'http://192.168.4.1');
      expect(c.latest!.celsius, 32.5);
      expect(c.records.single.celsius, 32.5);
      expect(hosts, ['192.168.4.1', '192.168.4.1']);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '192.168.4.1',
      );
      expect(find.text('Connected over Wi-Fi'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(db.close);
    },
  );
}
