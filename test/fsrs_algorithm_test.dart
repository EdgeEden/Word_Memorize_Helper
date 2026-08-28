import 'package:flutter_test/flutter_test.dart';
import 'package:wordn/models/fsrs/fsrs_models.dart';
import 'package:wordn/models/fsrs/fsrs_scheduler.dart';

void main() {
  group('FSRS 4.5/5 Algorithm & Model Tests', () {
    final scheduler = FsrsScheduler();

    test('Initial stability and difficulty by rating', () {
      final sAgain = scheduler.initStability(Rating.again);
      final sGood = scheduler.initStability(Rating.good);
      final sEasy = scheduler.initStability(Rating.easy);

      expect(sAgain, lessThan(sGood));
      expect(sGood, lessThan(sEasy));

      final dAgain = scheduler.initDifficulty(Rating.again);
      final dGood = scheduler.initDifficulty(Rating.good);
      final dEasy = scheduler.initDifficulty(Rating.easy);

      // Missed words have higher difficulty than easily recalled words
      expect(dAgain, greaterThan(dGood));
      expect(dGood, greaterThan(dEasy));
    });

    test('Retrievability power forgetting curve R(t, S)', () {
      final card = FsrsCard(
        word: 'influence',
        stability: 10.0, // 10 days stability
        difficulty: 5.0,
        lastReview: DateTime.now(),
      );

      // At t = 0 days, R should be 1.0
      expect(card.getRetrievability(DateTime.now()), closeTo(1.0, 0.01));

      // At t = S = 10 days, R should be exactly target retention 0.90
      final tenDaysLater = DateTime.now().add(const Duration(days: 10));
      expect(card.getRetrievability(tenDaysLater), closeTo(0.90, 0.02));

      // At t = 30 days, R should be significantly lower (~0.76)
      final thirtyDaysLater = DateTime.now().add(const Duration(days: 30));
      expect(card.getRetrievability(thirtyDaysLater), lessThan(0.85));
      expect(card.getRetrievability(thirtyDaysLater), greaterThan(0.50));
    });

    test('Sequential successful reviews increase stability exponentially', () {
      var card = FsrsCard(word: 'intellectual');
      var now = DateTime.now();

      // Review 1 (Good)
      card = scheduler.reviewCard(
        card: card,
        rating: Rating.good,
        now: now,
        currentSessionStep: 1,
      );
      final s1 = card.stability;
      expect(s1, greaterThan(0.5));
      expect(card.consecutiveCorrect, equals(1));

      // Review 2 (Good, after 3 days)
      now = now.add(const Duration(days: 3));
      card = scheduler.reviewCard(
        card: card,
        rating: Rating.good,
        now: now,
        currentSessionStep: 50,
      );
      final s2 = card.stability;
      expect(s2, greaterThan(s1));
      expect(card.consecutiveCorrect, equals(2));

      // Review 3 (Good, after 10 days)
      now = now.add(const Duration(days: 10));
      card = scheduler.reviewCard(
        card: card,
        rating: Rating.good,
        now: now,
        currentSessionStep: 120,
      );
      final s3 = card.stability;
      expect(s3, greaterThan(s2 * 1.5));
      expect(card.consecutiveCorrect, equals(3));
    });

    test('Lapse (Rating.again) resets streak, increases lapse count, and schedules short step', () {
      var card = FsrsCard(
        word: 'economic',
        state: CardState.review,
        stability: 15.0,
        difficulty: 4.0,
        reps: 4,
        consecutiveCorrect: 3,
        lastReview: DateTime.now().subtract(const Duration(days: 15)),
      );


      final now = DateTime.now();
      card = scheduler.reviewCard(
        card: card,
        rating: Rating.again,
        now: now,
        currentSessionStep: 20,
      );

      expect(card.lapses, equals(1));
      expect(card.consecutiveCorrect, equals(0));
      expect(card.state, equals(CardState.relearning));
      // Intrasession step should be scheduled 3-4 steps later (e.g. 23 or 24)
      expect(card.dueStep, greaterThanOrEqualTo(23));
      expect(card.dueStep, lessThanOrEqualTo(25));
    });

    test('FsrsCard JSON serialization and deserialization', () {
      final original = FsrsCard(
        word: 'century',
        state: CardState.review,
        stability: 8.5,
        difficulty: 4.2,
        reps: 5,
        lapses: 1,
        consecutiveCorrect: 3,
        lastReview: DateTime(2026, 8, 28, 12, 0),
        due: DateTime(2026, 9, 5, 12, 0),
        dueStep: -1,
      );

      final json = original.toJson();
      final restored = FsrsCard.fromJson(json);

      expect(restored.word, equals('century'));
      expect(restored.state, equals(CardState.review));
      expect(restored.stability, closeTo(8.5, 0.001));
      expect(restored.difficulty, closeTo(4.2, 0.001));
      expect(restored.reps, equals(5));
      expect(restored.lapses, equals(1));
      expect(restored.consecutiveCorrect, equals(3));
      expect(restored.lastReview, equals(DateTime(2026, 8, 28, 12, 0)));
      expect(restored.due, equals(DateTime(2026, 9, 5, 12, 0)));
      expect(restored.dueStep, equals(-1));
    });
  });
}
