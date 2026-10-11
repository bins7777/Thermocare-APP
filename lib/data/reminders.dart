import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as zones;
import 'package:timezone/timezone.dart' as tz;
import '../care_models.dart';
import '../models.dart';

abstract class ReminderGateway {
  bool get backgroundSupported;
  Future<bool> requestPermission();
  Future<void> replace(
    Object owner,
    List<CareReminder> reminders,
    List<FamilyMember> members,
  );
}

/// Also used by tests. Foreground reminders are handled by the controller.
class ForegroundReminders implements ReminderGateway {
  @override
  bool get backgroundSupported => false;
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> replace(
    Object owner,
    List<CareReminder> reminders,
    List<FamilyMember> members,
  ) async {}
}

class PhoneReminders implements ReminderGateway {
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _ready;
  Future<void> _queue = Future.value();
  Object? _owner;
  @override
  bool get backgroundSupported =>
      !kIsWeb &&
      [
        TargetPlatform.android,
        TargetPlatform.iOS,
      ].contains(defaultTargetPlatform);

  Future<void> _initialize() => _ready ??=
      (() async {
        if (!backgroundSupported) return;
        zones.initializeTimeZones();
        final zone = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(zone.identifier));
        await _plugin.initialize(
          settings: const InitializationSettings(
            android: AndroidInitializationSettings('ic_care_notification'),
            iOS: DarwinInitializationSettings(
              requestAlertPermission: false,
              requestBadgePermission: false,
              requestSoundPermission: false,
            ),
          ),
        );
      })().catchError((Object error, StackTrace stack) {
        _ready = null;
        Error.throwWithStackTrace(error, stack);
      });

  @override
  Future<bool> requestPermission() async {
    if (!backgroundSupported) return true;
    await _initialize();
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          false;
    }
    return await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, sound: true, badge: false) ??
        false;
  }

  @override
  Future<void> replace(
    Object owner,
    List<CareReminder> reminders,
    List<FamilyMember> members,
  ) {
    _owner = owner;
    final work = _queue.catchError((Object _) {}).then((_) async {
      if (!backgroundSupported || !identical(_owner, owner)) return;
      await _initialize();
      await _plugin.cancelAll();
      if (!identical(_owner, owner)) return;
      var id = 1;
      for (final r in reminders.where((r) => r.enabled)) {
        if (!members.any((m) => m.id == r.memberId && !m.archived)) continue;
        // One weekly request per selected day; at most 8 x 7 = 56 on iOS.
        for (final weekday in r.weekdays) {
          if (!identical(_owner, owner)) return;
          await _plugin.zonedSchedule(
            id: id++,
            title: 'A little moment of care',
            body:
                'Your planned temperature check-in is ready whenever you are.',
            scheduledDate: nextReminderTime(
              tz.TZDateTime.now(tz.local),
              weekday,
              r.hour,
              r.minute,
            ),
            notificationDetails: const NotificationDetails(
              android: AndroidNotificationDetails(
                'care_check_ins',
                'Care reminders',
                channelDescription: 'Your optional family check-in reminders',
                importance: Importance.defaultImportance,
                priority: Priority.defaultPriority,
              ),
              iOS: DarwinNotificationDetails(),
            ),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
            payload: r.memberId,
          );
        }
      }
    });
    _queue = work;
    return work;
  }
}

tz.TZDateTime nextReminderTime(
  tz.TZDateTime now,
  int weekday,
  int hour,
  int minute,
) {
  var day = tz.TZDateTime(
    now.location,
    now.year,
    now.month,
    now.day,
    hour,
    minute,
  );
  for (var i = 0; i < 8; i++) {
    if (day.weekday == weekday && day.isAfter(now)) return day;
    // Calendar construction preserves wall-clock time across DST changes.
    day = tz.TZDateTime(
      now.location,
      day.year,
      day.month,
      day.day + 1,
      hour,
      minute,
    );
  }
  return day;
}
