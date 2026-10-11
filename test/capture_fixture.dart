import 'package:thermocare/controller.dart';
import 'package:thermocare/models.dart';

/// Supplies a stable live window in tests concerned with saving rather than acquisition.
void seedStableCapture(MonitorController c) {
  final latest = c.latest!;
  final now = DateTime.now();
  c.measurements.reset();
  for (var i = 0; i < 3; i++) {
    c.measurements.add(
      i == 2
          ? latest
          : Reading(
              id: '${latest.id}/fixture/$i',
              celsius: latest.celsius,
              ambient: latest.ambient,
              at: latest.at,
              deviceId: latest.deviceId,
            ),
      now.subtract(Duration(seconds: 4 - i * 2)),
    );
  }
}
