import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'android_download_service.dart';

/// App version metadata retrieved from server
class AppVersionInfo {
  final String version;
  final int versionCode;
  final int minSupportedVersionCode;
  final String title;
  final String releaseNotes;
  final String apkUrl;
  final String windowsUrl;
  final bool forceUpdate;
  final String pubDate;

  const AppVersionInfo({
    required this.version,
    required this.versionCode,
    required this.minSupportedVersionCode,
    required this.title,
    required this.releaseNotes,
    required this.apkUrl,
    required this.windowsUrl,
    required this.forceUpdate,
    required this.pubDate,
  });

  factory AppVersionInfo.fromJson(Map<String, dynamic> json, {String? serverUrl}) {
    String normalizeUrl(String? raw) {
      if (raw == null || raw.isEmpty) return '';
      if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
      if (serverUrl != null && serverUrl.isNotEmpty) {
        final base = serverUrl.endsWith('/') ? serverUrl.substring(0, serverUrl.length - 1) : serverUrl;
        final path = raw.startsWith('/') ? raw : '/$raw';
        return '$base$path';
      }
      return raw;
    }

    return AppVersionInfo(
      version: json['version'] as String? ?? '1.0.0',
      versionCode: json['version_code'] as int? ?? 1,
      minSupportedVersionCode: json['min_supported_version_code'] as int? ?? 1,
      title: json['title'] as String? ?? '发现新版本',
      releaseNotes: json['release_notes'] as String? ?? '修复已知问题并优化体验',
      apkUrl: normalizeUrl(json['apk_url'] as String?),
      windowsUrl: normalizeUrl(json['windows_url'] as String?),
      forceUpdate: json['force_update'] as bool? ?? false,
      pubDate: json['pub_date'] as String? ?? '',
    );
  }
}

/// Result of checking for updates
class UpdateCheckResult {
  final bool hasUpdate;
  final String currentVersion;
  final int currentBuildNumber;
  final AppVersionInfo? latestInfo;
  final String? errorMessage;

  const UpdateCheckResult({
    required this.hasUpdate,
    required this.currentVersion,
    required this.currentBuildNumber,
    this.latestInfo,
    this.errorMessage,
  });
}

class UpdateService {
  /// Compare local version and server latest version. Returns true if server version is newer.
  static bool isNewerVersion({
    required String currentVersion,
    required int currentBuildNumber,
    required String latestVersion,
    required int latestBuildNumber,
  }) {
    // 1. Primary check: buildNumber / versionCode
    if (latestBuildNumber > currentBuildNumber) {
      return true;
    }
    if (latestBuildNumber < currentBuildNumber) {
      return false;
    }

    // 2. Secondary check: semantic version parts (e.g. 1.0.1 vs 1.0.0)
    try {
      final currentParts = currentVersion.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final latestParts = latestVersion.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      final maxLen = currentParts.length > latestParts.length ? currentParts.length : latestParts.length;
      for (int i = 0; i < maxLen; i++) {
        final c = i < currentParts.length ? currentParts[i] : 0;
        final l = i < latestParts.length ? latestParts[i] : 0;
        if (l > c) return true;
        if (l < c) return false;
      }
    } catch (_) {}

    return false;
  }

  /// Get current running application version info
  static Future<Map<String, dynamic>> getCurrentAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final buildNum = int.tryParse(packageInfo.buildNumber) ?? 1;
      return {
        'version': packageInfo.version.isNotEmpty ? packageInfo.version : '1.0.0',
        'buildNumber': buildNum,
      };
    } catch (e) {
      debugPrint('[UpdateService] 获取本地版本号失败，使用默认配置: $e');
      return {
        'version': '1.0.0',
        'buildNumber': 1,
      };
    }
  }

  /// Check server for latest version
  static Future<UpdateCheckResult> checkUpdate({
    required String serverUrl,
  }) async {
    try {
      final localInfo = await getCurrentAppVersion();
      final currentVer = localInfo['version'] as String;
      final currentBuild = localInfo['buildNumber'] as int;

      final cleanServerUrl = serverUrl.trim();
      if (cleanServerUrl.isEmpty) {
        return UpdateCheckResult(
          hasUpdate: false,
          currentVersion: currentVer,
          currentBuildNumber: currentBuild,
          errorMessage: '服务器地址未配置',
        );
      }

      final uri = Uri.parse('$cleanServerUrl/api/version/latest');
      final response = await http.get(uri).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
        final latest = AppVersionInfo.fromJson(data, serverUrl: cleanServerUrl);

        final hasNew = isNewerVersion(
          currentVersion: currentVer,
          currentBuildNumber: currentBuild,
          latestVersion: latest.version,
          latestBuildNumber: latest.versionCode,
        );

        if (hasNew) {
          currentAvailableUpdate = latest;
          currentAppVersion = currentVer;
        }

        return UpdateCheckResult(
          hasUpdate: hasNew,
          currentVersion: currentVer,
          currentBuildNumber: currentBuild,
          latestInfo: latest,
        );
      } else {
        return UpdateCheckResult(
          hasUpdate: false,
          currentVersion: currentVer,
          currentBuildNumber: currentBuild,
          errorMessage: '服务器响应异常 (HTTP ${response.statusCode})',
        );
      }
    } catch (e) {
      debugPrint('[UpdateService] 检查更新异常: $e');
      final localInfo = await getCurrentAppVersion();
      return UpdateCheckResult(
        hasUpdate: false,
        currentVersion: localInfo['version'] as String? ?? '1.0.0',
        currentBuildNumber: localInfo['buildNumber'] as int? ?? 1,
        errorMessage: '无法连接到更新服务器',
      );
    }
  }

  // -------------------------------------------------------------
  // Global Download State Management for Android Background Downloading
  // -------------------------------------------------------------
  static AppVersionInfo? currentAvailableUpdate;
  static String? currentAppVersion;
  static AppVersionInfo? _currentVersionInfo;
  static AppVersionInfo? get currentVersionInfo => _currentVersionInfo ?? currentAvailableUpdate;
  static bool get isCurrentDownloadMandatory => currentVersionInfo?.forceUpdate ?? false;

  static bool _isOtaDownloading = false;
  static int _currentOtaProgress = 0;
  static bool _isOtaInstalling = false;
  static String? _currentOtaError;
  static String? _currentDownloadingUrl;

  static final ValueNotifier<int> otaProgressNotifier = ValueNotifier<int>(0);
  static final ValueNotifier<bool> isOtaInstallingNotifier = ValueNotifier<bool>(false);
  static final ValueNotifier<String?> otaErrorNotifier = ValueNotifier<String?>(null);
  static final ValueNotifier<bool> isOtaDownloadingNotifier = ValueNotifier<bool>(false);

  static bool get isOtaDownloading => _isOtaDownloading;
  static int get currentOtaProgress => _currentOtaProgress;
  static bool get isOtaInstalling => _isOtaInstalling;
  static String? get currentOtaError => _currentOtaError;
  static String? get currentDownloadingUrl => _currentDownloadingUrl;

  /// Starts or re-connects to an Android background download stream.
  /// Powered by Android OS System DownloadManager which guarantees downloading
  /// continues uninterrupted when switching apps or locking the screen.
  static Future<void> startAndroidOtaUpdate({
    required String apkUrl,
    AppVersionInfo? versionInfo,
    Function(int progress)? onProgress,
    Function(String error)? onError,
    VoidCallback? onInstalling,
  }) async {
    if (versionInfo != null) {
      _currentVersionInfo = versionInfo;
    }
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      onError?.call('在线更新仅支持 Android 原生平台');
      return;
    }

    // If already downloading the same URL, connect to existing progress
    if (_isOtaDownloading && _currentDownloadingUrl == apkUrl) {
      debugPrint('[UpdateService] 发现正在进行的后台下载任务，关联监听: $apkUrl (进度: $_currentOtaProgress%)');
      onProgress?.call(_currentOtaProgress);
      if (_isOtaInstalling) onInstalling?.call();
      if (_currentOtaError != null) onError?.call(_currentOtaError!);
      return;
    }

    // Cancel previous download if URL changed
    await cancelAndroidOtaUpdate();

    _isOtaDownloading = true;
    _currentDownloadingUrl = apkUrl;
    _currentOtaProgress = 0;
    _isOtaInstalling = false;
    _currentOtaError = null;

    isOtaDownloadingNotifier.value = true;
    otaProgressNotifier.value = 0;
    isOtaInstallingNotifier.value = false;
    otaErrorNotifier.value = null;

    debugPrint('[UpdateService] 发起 Android DownloadManager 系统级后台下载: $apkUrl');

    await AndroidDownloadService.startDownload(
      url: apkUrl,
      fileName: 'WordN_Latest.apk',
      onProgress: (prog) {
        debugPrint('[UpdateService] DownloadManager 进度: status=${prog.status}, progress=${prog.progress}%');
        if (prog.status == AndroidDownloadStatus.downloading ||
            prog.status == AndroidDownloadStatus.pending ||
            prog.status == AndroidDownloadStatus.paused) {
          _currentOtaProgress = prog.progress;
          otaProgressNotifier.value = prog.progress;
          onProgress?.call(prog.progress);
        }
      },
      onComplete: () {
        debugPrint('[UpdateService] DownloadManager 下载完成，准备安装');
        _isOtaDownloading = false;
        _isOtaInstalling = true;
        _currentOtaProgress = 100;
        otaProgressNotifier.value = 100;
        isOtaDownloadingNotifier.value = false;
        isOtaInstallingNotifier.value = true;
        onInstalling?.call();
      },
      onError: (err) {
        debugPrint('[UpdateService] DownloadManager 下载失败: $err');
        _handleOtaError(err, onError);
      },
    );
  }

  static void _handleOtaError(String message, Function(String error)? callback) {
    _isOtaDownloading = false;
    _currentOtaError = message;
    isOtaDownloadingNotifier.value = false;
    otaErrorNotifier.value = message;
    callback?.call(message);
  }

  /// Cancels ongoing Android OTA background download
  static Future<void> cancelAndroidOtaUpdate() async {
    await AndroidDownloadService.cancelDownload();
    _isOtaDownloading = false;
    _currentDownloadingUrl = null;
    _currentOtaProgress = 0;
    _isOtaInstalling = false;
    _currentOtaError = null;

    isOtaDownloadingNotifier.value = false;
    otaProgressNotifier.value = 0;
    isOtaInstallingNotifier.value = false;
    otaErrorNotifier.value = null;
  }
}
