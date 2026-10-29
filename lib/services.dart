import 'dart:convert';
import 'dart:io';
import 'package:http_parser/http_parser.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:http/http.dart' as http;
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as tz;

const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000/api',
);

class GlowlyApi {
  GlowlyApi({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$apiBaseUrl$path').replace(queryParameters: query);

  Future<List<Map<String, dynamic>>> searchProducts({
    required String query,
    String skinType = 'All',
    String category = 'All',
    String sort = 'relevance',
    double? maxPrice,
  }) async {
    final params = <String, String>{
      'q': query.isEmpty ? 'skincare' : query,
      'skin_type': skinType,
      'category': category,
      'sort': sort,
      if (maxPrice != null) 'max_price': '$maxPrice',
    };
    final response = await _client.get(_uri('/products', params));
    final body = _decode(response);
    return (body['items'] as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> analyzeSkin(File image, String goals) async {
    final request = http.MultipartRequest('POST', _uri('/analyze-skin'))
      ..fields['goals'] = goals
      ..files.add(await http.MultipartFile.fromPath('image', image.path));
    final streamed = await request.send().timeout(const Duration(seconds: 100));
    final response = await http.Response.fromStream(streamed);
    return _decode(response);
  }

  Future<void> saveReview(Map<String, dynamic> review) async {
    final response = await _client.post(
      _uri('/reviews'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(review),
    );
    _decode(response);
  }

  Future<void> deleteReview(String reviewId, String userId) async {
    final response = await _client.delete(
      _uri('/reviews/$reviewId', {'user_id': userId}),
    );
    _decode(response);
  }

  Future<List<Map<String, dynamic>>> reviews(String userId) async {
    final response = await _client.get(_uri('/reviews/$userId'));
    return (_decode(response) as List<dynamic>).cast<Map<String, dynamic>>();
  }

  dynamic _decode(http.Response response) {
    final dynamic body = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = body is Map ? body['detail'] : null;
      throw Exception(
        detail?.toString() ?? 'Request failed (${response.statusCode})',
      );
    }
    return body;
  }
}

class RoutineReminderService {
  RoutineReminderService._();
  static final RoutineReminderService instance = RoutineReminderService._();
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> initialize() async {
    if (_ready) return;
    timezone_data.initializeTimeZones();
    try {
      final local = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(local.identifier));
    } catch (_) {
      // Keep timezone's UTC fallback if the platform does not expose a zone.
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _ready = true;
  }

  Future<void> requestPermission() async {
    await initialize();
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  Future<void> schedule(int id, String label, String time) async {
    await initialize();
    await requestPermission();
    final parts = time.split(':');
    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
    if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
    await _plugin.zonedSchedule(
      id: id,
      title: 'Glowly routine time',
      body: 'Time for $label. A little consistency goes a long way.',
      scheduledDate: next,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'glowly_routines',
          'Routine reminders',
          channelDescription: 'Daily reminders for your skincare routine.',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> cancel(int id) async {
    await initialize();
    await _plugin.cancel(id: id);
  }
}
