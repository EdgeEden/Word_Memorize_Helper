import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

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

  /// Execute OTA update on Android
  static StreamSubscription<OtaEvent>? startAndroidOtaUpdate({
    required String apkUrl,
    required Function(int progress) onProgress,
    required Function(String error) onError,
    required VoidCallback onInstalling,
  }) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      onError('OTA 在线更新仅支持 Android 原生平台');
      return null;
    }

    try {
      debugPrint('[UpdateService] 开始 Android OTA 升级流程，目标地址: $apkUrl');
      final stream = OtaUpdate().execute(
        apkUrl,
        androidProviderAuthority: 'com.example.wordn.ota_update_provider',
        destinationFilename: 'WordN_Latest.apk',
      );

      return stream.listen(
        (OtaEvent event) {
          debugPrint('[UpdateService] OTA 状态更新: status=${event.status}, value=${event.value}');
          switch (event.status) {
            case OtaStatus.DOWNLOADING:
              final p = int.tryParse(event.value ?? '0') ?? 0;
              onProgress(p.clamp(0, 100));
              break;
            case OtaStatus.INSTALLING:
            case OtaStatus.INSTALLATION_DONE:
              onInstalling();
              break;

            case OtaStatus.ALREADY_RUNNING_ERROR:
              onError('更新下载已在后台进行中，请稍候');
              break;
            case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
              onError('未授予应用安装权限，请在系统设置中允许 WordN 安装未知应用');
              break;
            case OtaStatus.INTERNAL_ERROR:
              onError('更新组件内部异常，请检查存储权限或网络');
              break;
            case OtaStatus.DOWNLOAD_ERROR:
              onError('安装包下载失败，请检查网络连接或服务器地址');
              break;
            case OtaStatus.CHECKSUM_ERROR:
              onError('安装包校验失败，文件可能已损坏');
              break;
            case OtaStatus.INSTALLATION_ERROR:
              onError('安装过程异常，请确认系统已允许安装未知应用');
              break;
            case OtaStatus.CANCELED:
              onError('更新已取消');
              break;


          }
        },
        onError: (err) {
          debugPrint('[UpdateService] OTA Stream 异常: $err');
          onError('更新下载失败: $err');
        },
      );
    } catch (e) {
      debugPrint('[UpdateService] 发起 OTA 异常: $e');
      onError('发起 OTA 更新失败: $e');
      return null;
    }
  }
}
