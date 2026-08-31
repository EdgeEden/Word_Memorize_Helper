import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordn/services/update_service.dart';
import 'package:wordn/widgets/update_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'WordN',
      packageName: 'com.example.wordn',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  tearDown(() {
    UpdateService.cancelAndroidOtaUpdate();
  });

  group('Update Protection & Mandatory Update Intercept Tests', () {
    const mockMandatoryInfo = AppVersionInfo(
      version: '2.0.0',
      versionCode: 200,
      minSupportedVersionCode: 200,
      title: '重大版本更新',
      releaseNotes: '核心算法升级，必须更新后使用',
      apkUrl: 'http://example.com/app.apk',
      windowsUrl: '',
      forceUpdate: true,
      pubDate: '2026-08-31',
    );

    const mockOptionalInfo = AppVersionInfo(
      version: '1.1.0',
      versionCode: 110,
      minSupportedVersionCode: 100,
      title: '常规体验优化',
      releaseNotes: '优化下载体验',
      apkUrl: 'http://example.com/app.apk',
      windowsUrl: '',
      forceUpdate: false,
      pubDate: '2026-08-31',
    );

    testWidgets('Mandatory update: clicking "后台下载" shows intercept alert and blocks navigation', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    OtaDownloadDialog.show(
                      context,
                      apkUrl: mockMandatoryInfo.apkUrl,
                      title: mockMandatoryInfo.title,
                      versionInfo: mockMandatoryInfo,
                    );
                  },
                  child: const Text('Open Dialog'),
                );
              },
            ),
          ),
        ),
      );

      // Open OtaDownloadDialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('正在下载新版本安装包'), findsOneWidget);
      expect(find.text('后台下载'), findsOneWidget);

      // Click "后台下载"
      await tester.tap(find.text('后台下载'));
      await tester.pumpAndSettle();

      // Intercept alert should be displayed
      expect(find.text('强制更新提示'), findsOneWidget);
      expect(find.textContaining('当前为重要强制更新版本'), findsOneWidget);

      // Click "确定" on intercept alert
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      // Should remain on OtaDownloadDialog (not back to Scaffold base)
      expect(find.text('正在下载新版本安装包'), findsOneWidget);
    });

    testWidgets('Mandatory update: clicking "取消下载" returns to UpdateDialog introduction modal', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    OtaDownloadDialog.show(
                      context,
                      apkUrl: mockMandatoryInfo.apkUrl,
                      title: mockMandatoryInfo.title,
                      versionInfo: mockMandatoryInfo,
                    );
                  },
                  child: const Text('Open Dialog'),
                );
              },
            ),
          ),
        ),
      );

      // Open OtaDownloadDialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('取消下载'), findsOneWidget);

      // Click "取消下载"
      await tester.tap(find.text('取消下载'));
      await tester.pumpAndSettle();

      // Should automatically open UpdateDialog with version details
      expect(find.text('重大版本更新'), findsOneWidget);
      expect(find.text('立即更新'), findsOneWidget);
      // Mandatory update does NOT have "稍后再说" button
      expect(find.text('稍后再说'), findsNothing);
    });

    testWidgets('Optional update: clicking "后台下载" dismisses dialog and shows SnackBar', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    OtaDownloadDialog.show(
                      context,
                      apkUrl: mockOptionalInfo.apkUrl,
                      title: mockOptionalInfo.title,
                      versionInfo: mockOptionalInfo,
                    );
                  },
                  child: const Text('Open Dialog'),
                );
              },
            ),
          ),
        ),
      );

      // Open OtaDownloadDialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('后台下载'), findsOneWidget);

      // Click "后台下载"
      await tester.tap(find.text('后台下载'));
      await tester.pumpAndSettle();

      // Dialog is dismissed and SnackBar is shown
      expect(find.text('正在下载新版本安装包'), findsNothing);
      expect(find.text('已转入后台继续下载，下载完成后将自动提示安装'), findsOneWidget);
    });
  });
}

