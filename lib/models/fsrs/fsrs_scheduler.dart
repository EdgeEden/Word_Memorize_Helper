import 'dart:math';
import 'fsrs_models.dart';

class FsrsScheduler {
  // Standard FSRS-4.5 / 5 default parameter weights
  static const List<double> defaultWeights = [
    0.40255, 1.18385, 3.173, 15.69105, // w0-w3: Initial stability for ratings 1, 2, 3, 4
    7.1949, 0.5345,                     // w4-w5: Initial difficulty
    1.4604, 0.0046,                     // w6-w7: Difficulty update and mean reversion
    1.5457, 0.1192, 1.0192,             // w8-w10: Stability update on recall
    1.9395, 0.11, 0.296, 2.2698,        // w11-w14: Stability update on forget (Again)
    0.2315, 2.9898,                     // w15-w16: Hard penalty & Easy bonus
  ];

  static const double factor = 19.0 / 81.0;
  static const double decay = -0.5;
  static const double defaultDesiredRetention = 0.90; // 90% target retention

  final List<double> w;
  final double desiredRetention;
  final Random _random = Random();

  FsrsScheduler({
    List<double>? weights,
    this.desiredRetention = defaultDesiredRetention,
  }) : w = weights ?? defaultWeights;

  /// Initial stability S_0(G) = w[G-1]
  double initStability(Rating rating) {
    return max(0.1, w[rating.value - 1]);
  }

  /// Initial difficulty D_0(G) = w4 - exp(w5 * (G - 1)) + 1
  double initDifficulty(Rating rating) {
    final d0 = w[4] - exp(w[5] * (rating.value - 1)) + 1.0;
    return d0.clamp(1.0, 10.0);
  }

  /// Next difficulty D'(D, G) with mean reversion towards D_0(3)
  double nextDifficulty(double currentD, Rating rating) {
    final deltaD = -w[6] * (rating.value - 3);
    final rawD = currentD + deltaD;
    final d0Good = initDifficulty(Rating.good);
    final nextD = w[7] * d0Good + (1.0 - w[7]) * rawD;
    return nextD.clamp(1.0, 10.0);
  }

  /// Stability update on successful recall (G >= 2)
  double nextRecallStability(double s, double d, double r, Rating rating) {
    double hardPenalty = 1.0;
    double easyBonus = 1.0;

    if (rating == Rating.hard) {
      hardPenalty = w[15];
    } else if (rating == Rating.easy) {
      easyBonus = w[16];
    }

    final sMultiplier = 1.0 +
        exp(w[8]) *
            (11.0 - d) *
            pow(s, -w[9]) *
            (exp((1.0 - r) * w[10]) - 1.0) *
            hardPenalty *
            easyBonus;

    return max(0.1, s * sMultiplier);
  }

  /// Stability update on lapse/forget (G == 1)
  double nextForgetStability(double s, double d, double r) {
    final newS = w[11] *
        pow(d, -w[12]) *
        (pow(s + 1.0, w[13]) - 1.0) *
        exp((1.0 - r) * w[14]);
    return max(0.1, min(s, newS));
  }

  /// Calculate next interval in days for target retention
  double calculateInterval(double stability) {
    final interval = (stability / factor) * (pow(desiredRetention, 1.0 / decay) - 1.0);
    return max(1.0, interval);
  }

  /// Updates card state based on quiz rating, timestamp and session step
  FsrsCard reviewCard({
    required FsrsCard card,
    required Rating rating,
    required DateTime now,
    required int currentSessionStep,
  }) {
    card.reps++;

    if (card.state == CardState.newCard) {
      // First review
      card.stability = initStability(rating);
      card.difficulty = initDifficulty(rating);

      if (rating == Rating.again) {
        card.lapses++;
        card.consecutiveCorrect = 0;
        card.state = CardState.learning;
        // Schedule for intrasession review in 3-4 steps
        card.dueStep = currentSessionStep + 3 + _random.nextInt(2);
        card.due = now.add(const Duration(minutes: 5));
      } else {
        card.consecutiveCorrect = 1;
        card.state = CardState.review;
        card.dueStep = -1;
        final intervalDays = calculateInterval(card.stability);
        card.due = now.add(Duration(minutes: (intervalDays * 1440).round()));
      }
    } else {
      // Subsequent review: calculate current retrievability before updating lastReview
      final r = card.getRetrievability(now);
      card.difficulty = nextDifficulty(card.difficulty, rating);


      if (rating == Rating.again) {
        card.lapses++;
        card.consecutiveCorrect = 0;
        card.stability = nextForgetStability(card.stability, card.difficulty, r);
        card.state = CardState.relearning;
        // Immediate short step review in 3-4 steps
        card.dueStep = currentSessionStep + 3 + _random.nextInt(2);
        card.due = now.add(const Duration(minutes: 5));
      } else {
        card.consecutiveCorrect++;
        card.stability = nextRecallStability(card.stability, card.difficulty, r, rating);

        if (card.state == CardState.learning || card.state == CardState.relearning) {
          if (card.consecutiveCorrect < 2) {
            // Need one more confirmation step in current session (8-12 steps later)
            card.dueStep = currentSessionStep + 8 + _random.nextInt(5);
            card.due = now.add(const Duration(minutes: 15));
          } else {
            // Graduated from relearning/learning to standard review
            card.state = CardState.review;
            card.dueStep = -1;
            final intervalDays = calculateInterval(card.stability);
            card.due = now.add(Duration(minutes: (intervalDays * 1440).round()));
          }
        } else {
          // Standard review state
          card.dueStep = -1;
          final intervalDays = calculateInterval(card.stability);
          card.due = now.add(Duration(minutes: (intervalDays * 1440).round()));
        }
      }
    }

    card.lastReview = now;
    return card;
  }
}

