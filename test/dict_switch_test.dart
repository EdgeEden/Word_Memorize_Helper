import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordn/controllers/quiz_controller.dart';
import 'package:wordn/models/fsrs/fsrs_models.dart';
import 'package:wordn/services/dict_service.dart';
import 'package:wordn/services/fsrs_repository.dart';

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

  group('Dictionary Assets & Parsing Tests', () {
    test('gyq.csv asset file exists and parses properly', () {
      final file = File('assets/dict/gyq.csv');
      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();
      final words = DictService.parseCsv(content);

      expect(words.length, greaterThanOrEqualTo(1850));

      final first = words.first;
      expect(first.word, equals('reproduce'));
      expect(first.definition, contains('复制'));
      expect(first.exampleEn, equals('The turtles return to the coast to reproduce.'));
      expect(first.exampleCn, equals('海龟回到岸上繁殖。'));
    });

    test('DictService registry and fallback handling', () {
      expect(DictService.builtInDicts.length, equals(2));

      final gyqInfo = DictService.getDictInfo('gyq');
      expect(gyqInfo.id, equals('gyq'));
      expect(gyqInfo.name, equals('gyq'));
      expect(gyqInfo.assetPath, equals('assets/dict/gyq.csv'));

      final kaoyanInfo = DictService.getDictInfo('kaoyan4533');
      expect(kaoyanInfo.id, equals('kaoyan4533'));
      expect(kaoyanInfo.name, equals('考研 4533'));

      // Unknown id falls back to kaoyan4533
      final unknownInfo = DictService.getDictInfo('unknown_dict_id');
      expect(unknownInfo.id, equals('kaoyan4533'));
    });
  });

  group('FsrsRepository Multi-Dictionary Isolation Tests', () {
    test('Cards are isolated per dictionary for the same user', () async {
      final cardA = FsrsCard(word: 'influence', reps: 3, stability: 4.5);
      final cardB = FsrsCard(word: 'reproduce', reps: 1, stability: 0.4);

      // Save cardA in kaoyan4533, cardB in gyq
      await FsrsRepository.saveCards({'influence': cardA}, 'user_alice', 'kaoyan4533');
      await FsrsRepository.saveCards({'reproduce': cardB}, 'user_alice', 'gyq');

      // Load kaoyan4533
      final loadedKaoyan = await FsrsRepository.loadCards('user_alice', 'kaoyan4533');
      expect(loadedKaoyan.containsKey('influence'), isTrue);
      expect(loadedKaoyan.containsKey('reproduce'), isFalse);

      // Load gyq
      final loadedGyq = await FsrsRepository.loadCards('user_alice', 'gyq');
      expect(loadedGyq.containsKey('reproduce'), isTrue);
      expect(loadedGyq.containsKey('influence'), isFalse);
    });

    test('cleanLegacyAndInvalidCards removes unlabelled and corrupted keys, keeps valid stores', () async {
      final prefs = await SharedPreferences.getInstance();
      // 1. Write legacy unlabelled key format
      await prefs.setString('wordn_fsrs_cards_v1', '{"legacyword":{"word":"legacyword","state":1}}');
      await prefs.setString('wordn_cards_user_legacy', '{"legacyword":{"word":"legacyword","state":1}}');
      // 2. Write valid isolated key
      await FsrsRepository.saveCards({
        'paragraph': FsrsCard(word: 'paragraph', reps: 2, stability: 1.5),
      }, 'user_valid', 'kaoyan4533');

      // 3. Run cleaner
      await FsrsRepository.cleanLegacyAndInvalidCards();

      // Legacy unlabelled keys must be completely removed
      expect(prefs.containsKey('wordn_fsrs_cards_v1'), isFalse);
      expect(prefs.containsKey('wordn_cards_user_legacy'), isFalse);

      // Valid isolated store must be preserved
      final loaded = await FsrsRepository.loadCards('user_valid', 'kaoyan4533');
      expect(loaded.containsKey('paragraph'), isTrue);
      expect(loaded['paragraph']!.reps, equals(2));
    });

    test('Current dictionary ID persistence', () async {
      expect(await FsrsRepository.getCurrentDictId(), equals('kaoyan4533'));

      await FsrsRepository.setCurrentDictId('gyq');
      expect(await FsrsRepository.getCurrentDictId(), equals('gyq'));
    });
  });

  group('QuizController Multi-Dictionary Switching Tests', () {
    test('QuizController switches dictionary and isolates wrong cards', () async {
      final controller = QuizController();
      await controller.init();

      expect(controller.currentDictId, equals('kaoyan4533'));
      expect(controller.currentDict.name, equals('考研 4533'));

      // 1. Submit an answer in kaoyan4533
      if (controller.currentWord != null) {
        await controller.submitAnswer('错误答案1');
        expect(controller.totalTrackedCardsCount, equals(1));
      }

      // 2. Switch to gyq
      await controller.switchDict('gyq');
      expect(controller.currentDictId, equals('gyq'));
      expect(controller.currentDict.name, equals('gyq'));
      expect(controller.totalTrackedCardsCount, equals(0)); // gyq has 0 cards

      // 3. Submit an answer in gyq
      if (controller.currentWord != null) {
        await controller.submitAnswer('错误答案2');
        expect(controller.totalTrackedCardsCount, equals(1));
      }

      // 4. Switch back to kaoyan4533
      await controller.switchDict('kaoyan4533');
      expect(controller.currentDictId, equals('kaoyan4533'));
      expect(controller.totalTrackedCardsCount, equals(1));

      // 5. Switch back to gyq
      await controller.switchDict('gyq');
      expect(controller.currentDictId, equals('gyq'));
      expect(controller.totalTrackedCardsCount, equals(1));
    });

    test('Stray cards not in active dictionary are excluded from dueReviewCount and sanitized', () async {
      // Simulate storage having cards that do not belong to gyq
      final now = DateTime.now();
      final pastDue = now.subtract(const Duration(days: 1));
      final strayCard = FsrsCard(
        word: 'non_existent_fake_word',
        due: pastDue,
        state: CardState.learning,
        reps: 1,
        stability: 0.1,
      );

      await FsrsRepository.setCurrentDictId('gyq');
      await FsrsRepository.saveCards({'non_existent_fake_word': strayCard}, null, 'gyq');

      final controller = QuizController();
      await controller.init();

      expect(controller.currentDictId, equals('gyq'));
      // Stray card must not count in dueReviewCount or allCards
      expect(controller.dueReviewCount, equals(0));
      expect(controller.totalTrackedCardsCount, equals(0));
      expect(controller.allCards.isEmpty, isTrue);
    });

    test('clearWrongBookData clears current dict or all dicts correctly', () async {
      // 1. Prepare cards in both kaoyan4533 and gyq
      await FsrsRepository.saveCards({
        'paragraph': FsrsCard(word: 'paragraph', reps: 3, stability: 2.0),
      }, 'tester', 'kaoyan4533');

      await FsrsRepository.saveCards({
        'reproduce': FsrsCard(word: 'reproduce', reps: 2, stability: 1.0),
      }, 'tester', 'gyq');

      await FsrsRepository.setCurrentUser('tester');
      await FsrsRepository.setCurrentDictId('gyq');

      final controller = QuizController();
      await controller.init();

      expect(controller.currentDictId, equals('gyq'));
      expect(controller.totalTrackedCardsCount, equals(1));

      // 2. Clear ONLY current dict (gyq)
      final successSingle = await controller.clearWrongBookData(clearAll: false);
      expect(successSingle, isTrue);
      expect(controller.totalTrackedCardsCount, equals(0));

      final gyqCards = await FsrsRepository.loadCards('tester', 'gyq');
      expect(gyqCards.isEmpty, isTrue);

      // Verify kaoyan4533 is still intact
      final kaoyanCards = await FsrsRepository.loadCards('tester', 'kaoyan4533');
      expect(kaoyanCards.containsKey('paragraph'), isTrue);

      // 3. Switch to kaoyan4533 and clear ALL dicts
      await controller.switchDict('kaoyan4533');
      expect(controller.totalTrackedCardsCount, equals(1));

      final successAll = await controller.clearWrongBookData(clearAll: true);
      expect(successAll, isTrue);
      expect(controller.totalTrackedCardsCount, equals(0));

      final kaoyanCardsAfter = await FsrsRepository.loadCards('tester', 'kaoyan4533');
      expect(kaoyanCardsAfter.isEmpty, isTrue);
    });
  });
}
