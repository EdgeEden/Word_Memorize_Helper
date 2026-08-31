import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum AndroidDownloadStatus {
  idle,
  pending,
  downloading,
  paused,
  successful,
  failed,
  unknown,
}

class AndroidDownloadProgress {
  final AndroidDownloadStatus status;
  final int progress;
  final int bytesDownloaded;
  final int bytesTotal;
  final int? reason;

  const AndroidDownloadProgress({
    required this.status,
    required this.progress,
    required this.bytesDownloaded,
    required this.bytesTotal,
    this.reason,
  });

  factory AndroidDownloadProgress.fromMap(Map<dynamic, dynamic> map) {
    final statusStr = map['status'] as String? ?? 'unknown';
    AndroidDownloadStatus status;
    switch (statusStr) {
      case 'downloading':
        status = AndroidDownloadStatus.downloading;
        break;
      case 'successful':
        status = AndroidDownloadStatus.successful;
        break;
      case 'failed':
        status = AndroidDownloadStatus.failed;
        break;
      case 'paused':
        status = AndroidDownloadStatus.paused;
        break;
      case 'pending':
        status = AndroidDownloadStatus.pending;
        break;
      case 'idle':
        status = AndroidDownloadStatus.idle;
        break;
      default:
        status = AndroidDownloadStatus.unknown;
    }

    final progress = (map['progress'] as num?)?.toInt() ?? 0;
    final bytesDownloaded = (map['bytesDownloaded'] as num?)?.toInt() ?? 0;
    final bytesTotal = (map['bytesTotal'] as num?)?.toInt() ?? 0;
    final reason = (map['reason'] as num?)?.toInt();

    return AndroidDownloadProgress(
      status: status,
      progress: progress.clamp(0, 100),
      bytesDownloaded: bytesDownloaded,
      bytesTotal: bytesTotal,
      reason: reason,
    );
  }
}

class AndroidDownloadService {
  static const MethodChannel _methodChannel =
      MethodChannel('com.example.wordn/download_manager');
  static const EventChannel _eventChannel =
      EventChannel('com.example.wordn/download_progress');

  static int? _currentDownloadId;
  static StreamSubscription<dynamic>? _progressSubscription;

  static int? get currentDownloadId => _currentDownloadId;

  /// Starts downloading an APK via Android OS System DownloadManager
  static Future<int?> startDownload({
    required String url,
    String fileName = 'WordN_Latest.apk',
    Function(AndroidDownloadProgress progress)? onProgress,
    VoidCallback? onComplete,
    Function(String error)? onError,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      onError?.call('仅支持 Android 原生平台');
      return null;
    }

    try {
      final downloadId = await _methodChannel.invokeMethod<int>(
        'startDownload',
        {
          'url': url,
          'fileName': fileName,
        },
      );

      _currentDownloadId = downloadId;

      _progressSubscription?.cancel();
      _progressSubscription = _eventChannel.receiveBroadcastStream().listen(
        (data) {
          if (data is Map) {
            final progress = AndroidDownloadProgress.fromMap(data);
            onProgress?.call(progress);

            if (progress.status == AndroidDownloadStatus.successful) {
              onComplete?.call();
            } else if (progress.status == AndroidDownloadStatus.failed) {
              onError?.call('下载失败 (错误代码: ${progress.reason})');
            }
          }
        },
        onError: (err) {
          onError?.call('下载进度监听异常: $err');
        },
      );

      return downloadId;
    } catch (e) {
      debugPrint('[AndroidDownloadService] startDownload 异常: $e');
      onError?.call('启动系统下载器失败: $e');
      return null;
    }
  }

  /// Queries current download progress from DownloadManager
  static Future<AndroidDownloadProgress?> getProgress([int? downloadId]) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    final id = downloadId ?? _currentDownloadId;
    if (id == null) return null;

    try {
      final res = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>(
        'getDownloadProgress',
        {'downloadId': id},
      );
      if (res != null) {
        return AndroidDownloadProgress.fromMap(res);
      }
    } catch (e) {
      debugPrint('[AndroidDownloadService] getProgress 异常: $e');
    }
    return null;
  }

  /// Cancels the ongoing download in DownloadManager
  static Future<bool> cancelDownload([int? downloadId]) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    final id = downloadId ?? _currentDownloadId;
    if (id == null) return false;

    _progressSubscription?.cancel();
    _progressSubscription = null;
    _currentDownloadId = null;

    try {
      final res = await _methodChannel.invokeMethod<bool>(
        'cancelDownload',
        {'downloadId': id},
      );
      return res ?? false;
    } catch (e) {
      debugPrint('[AndroidDownloadService] cancelDownload 异常: $e');
      return false;
    }
  }

  /// Triggers installation of downloaded APK
  static Future<bool> installApk([int? downloadId]) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    final id = downloadId ?? _currentDownloadId;
    if (id == null) return false;

    try {
      final res = await _methodChannel.invokeMethod<bool>(
        'installApk',
        {'downloadId': id},
      );
      return res ?? false;
    } catch (e) {
      debugPrint('[AndroidDownloadService] installApk 异常: $e');
      return false;
    }
  }
}

