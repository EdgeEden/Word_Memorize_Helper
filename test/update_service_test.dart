import 'package:flutter_test/flutter_test.dart';
import 'package:wordn/services/update_service.dart';

void main() {
  group('UpdateService Version Comparison Tests', () {
    test('Correctly identifies newer version by build number / versionCode', () {
      expect(
        UpdateService.isNewerVersion(
          currentVersion: '1.0.0',
          currentBuildNumber: 1,
          latestVersion: '1.0.0',
          latestBuildNumber: 2,
        ),
        isTrue,
      );

      expect(
        UpdateService.isNewerVersion(
          currentVersion: '1.0.0',
          currentBuildNumber: 5,
          latestVersion: '1.0.0',
          latestBuildNumber: 3,
        ),
        isFalse,
      );
    });

    test('Correctly compares semantic version strings when build numbers are equal', () {
      expect(
        UpdateService.isNewerVersion(
          currentVersion: '1.0.0',
          currentBuildNumber: 1,
          latestVersion: '1.0.1',
          latestBuildNumber: 1,
        ),
        isTrue,
      );

      expect(
        UpdateService.isNewerVersion(
          currentVersion: '1.2.0',
          currentBuildNumber: 1,
          latestVersion: '1.1.9',
          latestBuildNumber: 1,
        ),
        isFalse,
      );

      expect(
        UpdateService.isNewerVersion(
          currentVersion: '1.0.0',
          currentBuildNumber: 1,
          latestVersion: '2.0.0',
          latestBuildNumber: 1,
        ),
        isTrue,
      );
    });

    test('Returns false when current version is equal to or newer than server version', () {
      expect(
        UpdateService.isNewerVersion(
          currentVersion: '1.0.1',
          currentBuildNumber: 2,
          latestVersion: '1.0.1',
          latestBuildNumber: 2,
        ),
        isFalse,
      );
    });
  });

  group('AppVersionInfo JSON Deserialization Tests', () {
    test('Parses JSON and normalizes relative URLs with serverUrl', () {
      final json = {
        'version': '1.0.2',
        'version_code': 3,
        'min_supported_version_code': 1,
        'title': 'WordN v1.0.2 升级',
        'release_notes': '1. 修复已知问题\n2. 优化性能',
        'apk_url': '/api/download/apk',
        'windows_url': '/api/download/windows',
        'force_update': true,
        'pub_date': '2026-08-30T12:00:00Z',
      };

      final info = AppVersionInfo.fromJson(json, serverUrl: 'http://192.168.1.100:25642');

      expect(info.version, '1.0.2');
      expect(info.versionCode, 3);
      expect(info.title, 'WordN v1.0.2 升级');
      expect(info.forceUpdate, isTrue);
      expect(info.apkUrl, 'http://192.168.1.100:25642/api/download/apk');
      expect(info.windowsUrl, 'http://192.168.1.100:25642/api/download/windows');
    });

    test('Keeps absolute URLs intact during JSON parsing', () {
      final json = {
        'version': '1.0.2',
        'version_code': 3,
        'apk_url': 'https://github.com/myuser/wordn/releases/download/v1.0.2/app.apk',
        'windows_url': 'https://github.com/myuser/wordn/releases/download/v1.0.2/win.zip',
      };

      final info = AppVersionInfo.fromJson(json, serverUrl: 'http://localhost:8000');

      expect(info.apkUrl, 'https://github.com/myuser/wordn/releases/download/v1.0.2/app.apk');
      expect(info.windowsUrl, 'https://github.com/myuser/wordn/releases/download/v1.0.2/win.zip');
    });
  });
}

