import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotificationsService {
  LocalNotificationsService._();

  static final LocalNotificationsService instance =
      LocalNotificationsService._();

  static const String directMessagePayloadPrefix = 'direct_message:';

  static const String _directMessagesChannelId = 'direct_messages';
  static const String _directMessagesChannelName = 'Direct Messages';
  static const String _directMessagesChannelDescription =
      'Incoming direct message alerts';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final StreamController<String> _tapPayloadController =
      StreamController<String>.broadcast();

  bool _initialized = false;
  String? _launchPayload;

  Stream<String> get tapPayloadStream => _tapPayloadController.stream;

  Future<void> initialize() async {
    if (_initialized) return;

    if (kIsWeb) {
      _initialized = true;
      return;
    }

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const initializationSettings = InitializationSettings(
      android: androidSettings,
    );

    await _plugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = (response.payload ?? '').trim();
        if (payload.isEmpty) return;
        _tapPayloadController.add(payload);
      },
    );

    final androidImplementation = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    await androidImplementation?.createNotificationChannel(
      const AndroidNotificationChannel(
        _directMessagesChannelId,
        _directMessagesChannelName,
        description: _directMessagesChannelDescription,
        importance: Importance.high,
      ),
    );

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    final payload = (launchDetails?.notificationResponse?.payload ?? '').trim();
    if (payload.isNotEmpty) {
      _launchPayload = payload;
    }

    _initialized = true;
  }

  Future<bool> ensureNotificationPermission({
    bool promptIfNeeded = true,
  }) async {
    if (kIsWeb) return false;

    await initialize();

    final androidImplementation = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (androidImplementation == null) {
      return true;
    }

    final currentlyEnabled =
        await androidImplementation.areNotificationsEnabled() ?? true;
    if (currentlyEnabled) return true;
    if (!promptIfNeeded) return false;

    final granted =
        await androidImplementation.requestNotificationsPermission() ?? false;
    return granted;
  }

  String? consumeLaunchPayload() {
    final payload = _launchPayload;
    _launchPayload = null;
    return payload;
  }

  bool isDirectMessagePayload(String payload) {
    return payload.startsWith(directMessagePayloadPrefix);
  }

  Future<void> showIncomingMessageNotification({
    required String chatId,
    required String senderName,
    required String messagePreview,
  }) async {
    if (kIsWeb) return;

    final permissionGranted = await ensureNotificationPermission(
      promptIfNeeded: false,
    );
    if (!permissionGranted) return;

    final normalizedName = senderName.trim();
    final title = normalizedName.isEmpty ? 'New message' : normalizedName;
    final body = messagePreview.trim().isEmpty
        ? 'Sent you a new message.'
        : messagePreview.trim();

    final androidDetails = AndroidNotificationDetails(
      _directMessagesChannelId,
      _directMessagesChannelName,
      channelDescription: _directMessagesChannelDescription,
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.message,
      visibility: NotificationVisibility.public,
      styleInformation: BigTextStyleInformation(body),
    );

    final details = NotificationDetails(android: androidDetails);

    await _plugin.show(
      _stableNotificationId(chatId),
      title,
      body,
      details,
      payload: '$directMessagePayloadPrefix$chatId',
    );
  }

  int _stableNotificationId(String value) {
    var hash = 0;
    for (final codeUnit in value.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x7fffffff;
    }
    return hash;
  }
}
