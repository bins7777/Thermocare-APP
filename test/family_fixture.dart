import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:thermocare/controller.dart';
import 'package:thermocare/data/device_api.dart';
import 'package:thermocare/models.dart';

// Synthetic hardware and history live only in the test suite.
const fixtureFamily = [
  FamilyMember(id: 'mom', name: 'Mom', avatar: 10),
  FamilyMember(id: 'dad', name: 'Dad', avatar: 9),
  FamilyMember(id: 'child', name: 'Child', avatar: 7),
];

DeviceApi familyFixtureApi() {
  var sequence = 0;
  return DeviceApi(
    client: MockClient((request) async {
      if (request.url.path == '/api/history') return http.Response('[]', 200);
      return http.Response(
        jsonEncode({
          'device_id': 'fixture-device',
          'boot_id': '1',
          'sequence': ++sequence,
          'sensor_ok': true,
          'object_c': 36.6,
          'ambient_c': 25.2,
          'age_ms': 0,
          'epoch': DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
        }),
        200,
      );
    }),
  );
}

Future<void> initializeFamilyFixture(MonitorController c) async {
  final now = DateTime.now();
  for (final m in fixtureFamily) {
    await c.store.saveMember(m);
  }
  await c.store.setSetting('selectedMember', 'mom');
  await c.store.saveReadings(
    List.generate(
      24,
      (i) => Reading(
        id: 'fixture-history/$i',
        celsius: 36.4 + math.sin(i * .65) * .22 + i * .008,
        ambient: 25.2,
        at: now.subtract(Duration(minutes: (24 - i) * 5)),
        deviceId: 'fixture-device',
        memberId: fixtureFamily[i % 3].id,
        memberName: fixtureFamily[i % 3].name,
      ),
    ),
  );
  await c.initialize();
  await c.connect('192.168.4.1');
}
