import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordn/controllers/quiz_controller.dart';
import 'package:wordn/models/fsrs/fsrs_models.dart';
import 'package:wordn/services/fsrs_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });


  test('FsrsRepository supports multi-user storage and user switching', () async {
    // 1. Save cards for user_a
    final cardA = FsrsCard(word: 'influence', reps: 3, stability: 4.5);
    await FsrsRepository.saveCards({'influence': cardA}, 'user_a');
    await FsrsRepository.setCurrentUser('user_a');

    // 2. Save cards for user_b
    final cardB = FsrsCard(word: 'abandon', reps: 1, stability: 0.4);
    await FsrsRepository.saveCards({'abandon': cardB}, 'user_b');

    // 3. Verify user_a cards
    final loadedA = await FsrsRepository.loadCards('user_a');
    expect(loadedA.containsKey('influence'), isTrue);
    expect(loadedA.containsKey('abandon'), isFalse);
    expect(loadedA['influence']!.reps, 3);

    // 4. Verify user_b cards
    final loadedB = await FsrsRepository.loadCards('user_b');
    expect(loadedB.containsKey('abandon'), isTrue);
    expect(loadedB.containsKey('influence'), isFalse);
    expect(loadedB['abandon']!.reps, 1);

    // 5. Verify current user
    expect(await FsrsRepository.getCurrentUser(), 'user_a');
    await FsrsRepository.setCurrentUser('user_b');
    expect(await FsrsRepository.getCurrentUser(), 'user_b');
  });

  test('QuizController login, logout, and multi-user isolation', () async {
    final controller = QuizController();
    await controller.init();

    expect(controller.isLoggedIn, isFalse);

    // Login user_alex
    await controller.login('Alex');
    expect(controller.currentUsername, 'alex');
    expect(controller.isLoggedIn, isTrue);

    // Submit an answer to generate a card for alex
    if (controller.currentWord != null) {
      controller.submitAnswer('释义测试');
      expect(controller.totalTrackedCardsCount, 1);
    }

    // Switch to another user
    await controller.login('Bob');
    expect(controller.currentUsername, 'bob');
    expect(controller.totalTrackedCardsCount, 0); // Fresh user has 0 cards

    // Switch back to alex
    await controller.login('alex');
    expect(controller.currentUsername, 'alex');
    expect(controller.totalTrackedCardsCount, 1); // Alex's cards restored

    // Logout
    await controller.logout();
    expect(controller.isLoggedIn, isFalse);
    expect(controller.currentUsername, isNull);
  });

  test('Persistent auto-login on application startup across restarts', () async {
    // 1. Simulate a previous user login and cards saved locally
    await FsrsRepository.setCurrentUser('sarah');
    await FsrsRepository.saveCards({
      'abandon': FsrsCard(word: 'abandon', reps: 5, stability: 12.0),
    }, 'sarah');

    // 2. Launch new QuizController (simulating fresh app startup)
    final freshController = QuizController();
    await freshController.init();

    // 3. Verify auto-login succeeded without prompting
    expect(freshController.isLoggedIn, isTrue);
    expect(freshController.currentUsername, 'sarah');
    expect(freshController.totalTrackedCardsCount, 1);
    expect(freshController.allCards.first.word, 'abandon');
    expect(freshController.allCards.first.stability, 12.0);

    // 4. Verify history contains logged in users
    final history = await FsrsRepository.getUserHistory();
    expect(history.contains('sarah'), isTrue);
  });
}


