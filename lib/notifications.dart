import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings =
        InitializationSettings(android: androidInit);
    await _local.initialize(initSettings);

    final platform = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (platform != null) {
      await platform.requestNotificationsPermission();
    }
  }

  static Future<void> show(String title, String body) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'scanner_channel', 'Scanner Alerts',
      channelDescription: 'Alerts for high arbitrage opportunities',
      importance: Importance.max,
      priority: Priority.high,
    );
    const NotificationDetails details = NotificationDetails(android: androidDetails);
    
    await _local.show(DateTime.now().millisecondsSinceEpoch.remainder(100000), title, body, details);
  }
}