import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;

/// Called by the OS for background FCM messages (top-level function required).
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // Background messages are auto-displayed by the FCM SDK on Android 8+.
  // No additional action needed here.
  debugPrint('[FCM] background message: ${message.messageId}');
}

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static const _channelId      = 'jarvis_reminders';
  static const _channelName    = 'תזכורות ג׳רביס';
  static const _alertChannelId = 'jarvis_alerts';
  static const _alertChannelName = 'התראות ג׳רביס';

  static Future<void> init() async {
    if (kIsWeb) return; // flutter_local_notifications has no web support.
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

    // Create high-priority alert channel for system events
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _alertChannelId,
          _alertChannelName,
          importance: Importance.max,
        ));
  }

  /// Initialize Firebase Cloud Messaging for push notifications.
  /// Call this after [init] with the server URL and API key for token registration.
  static Future<void> initPush({
    required String serverUrl,
    String apiKey = '',
  }) async {
    if (kIsWeb) return;
    try {
      await Firebase.initializeApp();

      // Register background message handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // Request notification permission (iOS + Android 13+)
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      debugPrint('[FCM] permission: ${settings.authorizationStatus}');

      // Get token and register with the server
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _registerToken(token, serverUrl: serverUrl, apiKey: apiKey);
      }

      // Re-register on token refresh
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        _registerToken(newToken, serverUrl: serverUrl, apiKey: apiKey);
      });

      // Handle foreground messages: show as local notification
      FirebaseMessaging.onMessage.listen((message) {
        final n = message.notification;
        if (n != null) {
          showNow(
            message.hashCode,
            n.body ?? '',
            title: n.title ?? 'ג׳רביס 🤖',
            channelId: _alertChannelId,
            channelName: _alertChannelName,
          );
        }
      });

      debugPrint('[FCM] push notifications initialized');
    } catch (e) {
      debugPrint('[FCM] initPush error (non-fatal): $e');
    }
  }

  static Future<void> _registerToken(
    String token, {
    required String serverUrl,
    String apiKey = '',
  }) async {
    try {
      await http.post(
        Uri.parse('$serverUrl/push/register-token'),
        headers: {
          'Content-Type': 'application/json',
          if (apiKey.isNotEmpty) 'x-jarvis-key': apiKey,
        },
        body: jsonEncode({'token': token, 'platform': 'android'}),
      ).timeout(const Duration(seconds: 10));
      debugPrint('[FCM] token registered with server');
    } catch (e) {
      debugPrint('[FCM] token registration failed (will retry on next launch): $e');
    }
  }

  static Future<void> schedule(
      String id, String text, DateTime scheduledTime) async {
    if (kIsWeb) return;
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

  static Future<void> showNow(
    int id,
    String body, {
    String? title,
    String? channelId,
    String? channelName,
  }) async {
    if (kIsWeb) return;
    await _plugin.show(
      id,
      title ?? 'ג׳רביס 🔔',
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId ?? _channelId,
          channelName ?? _channelName,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }

  static Future<void> cancel(String id) async {
    if (kIsWeb) return;
    await _plugin.cancel(id.hashCode);
  }

  static Future<void> cancelAll() async {
    if (kIsWeb) return;
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
