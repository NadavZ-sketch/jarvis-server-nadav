import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static const _channelId   = 'jarvis_reminders';
  static const _channelName = 'תזכורות ג׳רביס';

  static Future<void> init() async {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Jerusalem'));

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: android),
    );

    // Request permission on Android 13+
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static Future<void> schedule(
      String id, String text, DateTime scheduledTime) async {
    final tzTime = tz.TZDateTime.from(scheduledTime, tz.local);
    if (tzTime.isBefore(tz.TZDateTime.now(tz.local))) return;

    await _plugin.zonedSchedule(
      id.hashCode,
      'ג׳רביס 🔔',
      text,
      tzTime,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  static Future<void> cancel(String id) async {
    await _plugin.cancel(id.hashCode);
  }

  static Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  /// Re-schedule all reminders (call after app launch with fresh fetch)
  static Future<void> rescheduleAll(
      List<Map<String, dynamic>> reminders) async {
    await cancelAll();
    for (final r in reminders) {
      final id  = r['id']?.toString();
      final text = r['text']?.toString() ?? '';
      final iso  = r['scheduled_time']?.toString();
      if (id == null || iso == null) continue;
      try {
        final dt = DateTime.parse(iso).toLocal();
        await schedule(id, text, dt);
      } catch (_) {}
    }
  }
}
