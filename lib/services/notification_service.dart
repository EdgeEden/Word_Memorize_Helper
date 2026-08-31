import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notification service for managing system notifications and download progress
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _isInitialized = false;

  static const int updateNotificationId = 1001;
  static const String updateChannelId = 'wordn_app_update_channel';
  static const String updateChannelName = 'WordN 应用更新';
  static const String updateChannelDescription = '显示 WordN 考研词汇助手安装包下载与升级进度';

  static DateTime _lastNotifyTime = DateTime.fromMillisecondsSinceEpoch(0);
  static int _lastReportedProgress = -1;

  /// Initializes local notifications
  static Future<void> initialize() async {
    if (_isInitialized) return;
    if (kIsWeb) return;

    try {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidSettings);

      await _plugin.initialize(settings: initSettings);

      // Request permission on Android 13+
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _plugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      }

      _isInitialized = true;
      debugPrint('[NotificationService] 初始化完成');
    } catch (e) {
      debugPrint('[NotificationService] 初始化异常: $e');
    }
  }

  /// Displays or updates download progress in the Android notification bar
  static Future<void> showDownloadProgress({
    required int progress,
    String title = '正在下载 WordN 新版本',
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    final now = DateTime.now();
    // Throttle notification updates (at most once every 600ms unless reaching 0% or 100%)
    if (progress != 0 &&
        progress != 100 &&
        progress == _lastReportedProgress &&
        now.difference(_lastNotifyTime).inMilliseconds < 600) {
      return;
    }

    _lastNotifyTime = now;
    _lastReportedProgress = progress;

    try {
      final androidDetails = AndroidNotificationDetails(
        updateChannelId,
        updateChannelName,
        channelDescription: updateChannelDescription,
        importance: Importance.low,
        priority: Priority.low,
        showProgress: true,
        maxProgress: 100,
        progress: progress,
        ongoing: true,
        autoCancel: false,
        onlyAlertOnce: true,
        icon: '@mipmap/ic_launcher',
      );

      final details = NotificationDetails(android: androidDetails);

      await _plugin.show(
        id: updateNotificationId,
        title: title,
        body: '下载进度: $progress%',
        notificationDetails: details,
      );
    } catch (e) {
      debugPrint('[NotificationService] 更新下载进度通知异常: $e');
    }
  }

  /// Displays download completed notification
  static Future<void> showDownloadCompleted({
    String title = 'WordN 新版本下载完成',
    String message = '安装包已就绪，正在调起系统安装程序...',
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    try {
      final androidDetails = AndroidNotificationDetails(
        updateChannelId,
        updateChannelName,
        channelDescription: updateChannelDescription,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        showProgress: false,
        ongoing: false,
        autoCancel: true,
        icon: '@mipmap/ic_launcher',
      );

      final details = NotificationDetails(android: androidDetails);

      await _plugin.show(
        id: updateNotificationId,
        title: title,
        body: message,
        notificationDetails: details,
      );
    } catch (e) {
      debugPrint('[NotificationService] 显示完成通知异常: $e');
    }
  }

  /// Displays download failed notification
  static Future<void> showDownloadError({
    String title = 'WordN 更新下载失败',
    required String error,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    try {
      final androidDetails = AndroidNotificationDetails(
        updateChannelId,
        updateChannelName,
        channelDescription: updateChannelDescription,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        showProgress: false,
        ongoing: false,
        autoCancel: true,
        icon: '@mipmap/ic_launcher',
      );

      final details = NotificationDetails(android: androidDetails);

      await _plugin.show(
        id: updateNotificationId,
        title: title,
        body: error,
        notificationDetails: details,
      );
    } catch (e) {
      debugPrint('[NotificationService] 显示错误通知异常: $e');
    }
  }

  /// Cancels update download notification
  static Future<void> cancelUpdateNotification() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    try {
      await _plugin.cancel(id: updateNotificationId);
    } catch (e) {
      debugPrint('[NotificationService] 取消通知异常: $e');
    }
  }
}
