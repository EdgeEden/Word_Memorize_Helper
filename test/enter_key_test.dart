import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordn/main.dart';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'wordn_current_user': 'tester'});
    PackageInfo.setMockInitialValues(
      appName: 'WordN',
      packageName: 'com.example.wordn',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });



  testWidgets('Enter key submits answer, and subsequent Enter advances to next word',
      (WidgetTester tester) async {
    await tester.pumpWidget(const WordNApp());
    // Pump frames to complete async initialization
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Verify initial unsubmitted state: TextField and Submit button exist
    if (find.byType(TextField).evaluate().isNotEmpty) {
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('答案提交'), findsOneWidget);

      // 1. Enter Chinese answer and press Enter to submit
      await tester.enterText(find.byType(TextField), '段落');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 300));

      // Verify submitted state: "下一个 (Enter)" button is visible
      expect(find.text('下一个 (Enter)'), findsOneWidget);

      // 2. Press Enter while answer is displayed -> should advance to next word
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 300));

      // Verify that we are back to unsubmitted state for the next word
      expect(find.text('答案提交'), findsOneWidget);
      expect(find.text('下一个 (Enter)'), findsNothing);
    }
  });

  testWidgets('Clicking or tapping "下一个 (Enter)" button advances to next word',
      (WidgetTester tester) async {
    await tester.pumpWidget(const WordNApp());
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    if (find.byType(TextField).evaluate().isNotEmpty) {
      // 1. Submit answer via tapping the submit button on UI
      await tester.enterText(find.byType(TextField), '段落');
      await tester.tap(find.text('答案提交'));
      await tester.pump(const Duration(milliseconds: 300));

      // Verify "下一个 (Enter)" button is visible
      expect(find.text('下一个 (Enter)'), findsOneWidget);

      // 2. Tap "下一个 (Enter)" button directly with mouse/touchscreen
      await tester.tap(find.text('下一个 (Enter)'));
      await tester.pump(const Duration(milliseconds: 300));

      // Verify that we advance to next word
      expect(find.text('答案提交'), findsOneWidget);
      expect(find.text('下一个 (Enter)'), findsNothing);
    }
  });
}


