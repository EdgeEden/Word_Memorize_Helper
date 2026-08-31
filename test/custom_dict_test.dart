import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordn/controllers/quiz_controller.dart';
import 'package:wordn/services/dict_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Custom Dictionary CSV Parsing & Validation Tests', () {
    test('Correctly parses 2-column CSV: [word, definition]', () {
      const csv = '''
abandon,放弃；抛弃
ability,能力；才能
''';
      final words = DictService.parseCsv(csv);
      expect(words.length, equals(2));
      expect(words[0].word, equals('abandon'));
      expect(words[0].phonetic, equals(''));
      expect(words[0].definition, equals('放弃；抛弃'));
      expect(words[1].word, equals('ability'));
      expect(words[1].definition, equals('能力；才能'));
    });

    test('Correctly parses 3-column CSV: [word, phonetic, definition]', () {
      const csv = '''
word,phonetic,definition
apple,/ˈæpl/,苹果
banana,/bəˈnænə/,香蕉
''';
      final words = DictService.parseCsv(csv);
      expect(words.length, equals(2)); // Header 'word' skipped
      expect(words[0].word, equals('apple'));
      expect(words[0].phonetic, equals('/ˈæpl/'));
      expect(words[0].definition, equals('苹果'));
    });

    test('Correctly parses 5-column CSV with examples', () {
      const csv = '''
单词,音标,释义,英文例句,中文例句
resilient,/rɪˈzɪliənt/,有弹性的；适应力强的,She is very resilient.,她非常有适应力。
''';
      final words = DictService.parseCsv(csv);
      expect(words.length, equals(1)); // Header '单词' skipped
      expect(words[0].word, equals('resilient'));
      expect(words[0].phonetic, equals('/rɪˈzɪliənt/'));
      expect(words[0].definition, equals('有弹性的；适应力强的'));
      expect(words[0].exampleEn, equals('She is very resilient.'));
      expect(words[0].exampleCn, equals('她非常有适应力。'));
    });

    test('validateAndParseCsv returns failure on empty or invalid CSV', () {
      final res1 = DictService.validateAndParseCsv('');
      expect(res1.isValid, isFalse);

      final res2 = DictService.validateAndParseCsv('   \n\n  ');
      expect(res2.isValid, isFalse);
    });

    test('validateAndParseCsv returns valid count and samples on success', () {
      const csv = '''
cat,猫
dog,狗
elephant,大象
''';
      final res = DictService.validateAndParseCsv(csv);
      expect(res.isValid, isTrue);
      expect(res.wordCount, equals(3));
      expect(res.sampleWords.length, equals(3));
      expect(res.sampleWords.first.word, equals('cat'));
    });
  });

  group('Custom Dictionary Lifecycle & QuizController Integration Tests', () {
    late Directory tempDir;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tempDir = Directory.systemTemp.createTempSync('wordn_test_dicts_');

      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        return tempDir.path;
      });
    });

    tearDown(() {
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);

      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('QuizController imports custom dictionary and switches to it', () async {
      final controller = QuizController();
      await controller.init();

      expect(controller.currentDictId, equals('kaoyan4533'));
      expect(controller.availableDicts.length, equals(2)); // builtIn: kaoyan4533, gyq

      const sampleCsv = '''
novel,小说；新奇的
fiction,虚构；小说
narrative,记叙文；故事
''';

      // Import custom dict
      final customDict = await controller.importCustomDict(
        name: '文学核心词',
        description: '文学类高频词表',
        csvContent: sampleCsv,
        switchImmediately: true,
      );

      expect(customDict.isCustom, isTrue);
      expect(customDict.name, equals('文学核心词'));
      expect(customDict.estimatedCount, equals(3));

      // Controller must have switched to new dict
      expect(controller.currentDictId, equals(customDict.id));
      expect(controller.currentDict.name, equals('文学核心词'));
      expect(controller.totalWordsCount, equals(3));
      expect(controller.availableDicts.length, equals(3));

      // Submit an answer in custom dict to create wrong card
      if (controller.currentWord != null) {
        await controller.submitAnswer('错误答案');
        expect(controller.totalTrackedCardsCount, equals(1));
      }

      // Switch back to kaoyan4533
      await controller.switchDict('kaoyan4533');
      expect(controller.currentDictId, equals('kaoyan4533'));
      expect(controller.totalTrackedCardsCount, equals(0)); // kaoyan4533 is isolated

      // Delete custom dict
      await controller.deleteCustomDict(customDict.id);
      expect(controller.availableDicts.length, equals(2));
    });
  });
}
