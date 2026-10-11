import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thermocare/care_models.dart';
import 'package:thermocare/data/reminders.dart';
import 'package:thermocare/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const notifications = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  const timezone = MethodChannel('flutter_timezone');
  const mom = FamilyMember(id: 'mom', name: 'Mom');
  const reminder = CareReminder(
    id: 'r',
    memberId: 'mom',
    hour: 19,
    minute: 15,
    weekdays: [1, 3, 5],
  );
  final calls = <MethodCall>[];
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(timezone, (_) async => 'Asia/Manila');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifications, (call) async {
          calls.add(call);
          return [
                'initialize',
                'requestNotificationsPermission',
              ].contains(call.method)
              ? true
              : null;
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(timezone, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifications, null);
  });
  test(
    'Android schedules local weekly reminders, replaces schedules and requests permission only explicitly',
    () async {
      final service = PhoneReminders();
      final owner = Object();
      await service.replace(owner, [reminder], [mom]);
      expect(
        calls.where((c) => c.method == 'requestNotificationsPermission'),
        isEmpty,
      );
      final schedules = calls
          .where((c) => c.method == 'zonedSchedule')
          .toList();
      expect(schedules.length, 3);
      expect(
        schedules.map((c) => (c.arguments as Map)['id']).toSet().length,
        3,
      );
      for (final call in schedules) {
        final data = call.arguments as Map;
        expect(data['timeZoneName'], 'Asia/Manila');
        expect(data['scheduledDateTime'], contains('19:15:00'));
        expect(
          data['matchDateTimeComponents'],
          DateTimeComponents.dayOfWeekAndTime.index,
        );
        expect(
          (data['platformSpecifics'] as Map)['scheduleMode'],
          AndroidScheduleMode.inexactAllowWhileIdle.name,
        );
        expect(data['payload'], 'mom');
      }
      expect(await service.requestPermission(), isTrue);
      expect(
        calls.where((c) => c.method == 'requestNotificationsPermission').length,
        1,
      );
      calls.clear();
      await service.replace(owner, [reminder.withEnabled(false)], [mom]);
      expect(calls.map((c) => c.method), ['cancelAll']);
      calls.clear();
      await service.replace(owner, [reminder], [mom.copyWith(archived: true)]);
      expect(calls.map((c) => c.method), ['cancelAll']);
    },
  );
  test(
    'a new account prevents an older queued schedule from being restored',
    () async {
      final gate = Completer<String>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(timezone, (_) => gate.future);
      final service = PhoneReminders();
      final old = service.replace(Object(), [reminder], [mom]);
      await Future<void>.delayed(Duration.zero);
      final current = service.replace(Object(), [], []);
      gate.complete('Asia/Manila');
      await Future.wait([old, current]);
      expect(calls.where((c) => c.method == 'zonedSchedule'), isEmpty);
      expect(calls.last.method, 'cancelAll');
    },
  );
}
