import 'dart:math';

enum CardState {
  newCard,
  learning,
  review,
  relearning,
}

enum Rating {
  again(1), // 答错/遗忘
  hard(2),  // 困难 (如看了提示后答对)
  good(3),  // 正常正确
  easy(4);  // 容易/连续答对

  final int value;
  const Rating(this.value);
}

enum MemoryCategory {
  critical,     // 🔴 顽固高危词 (失误多次或留存率低)
  consolidating,// 🟡 巩固进行中 (正在经历正常间隔复习)
  mastered,     // 🟢 趋于掌握 (记忆稳定性高或已毕业)
}

class FsrsCard {
  final String word;
  CardState state;
  double stability;  // S (天)
  double difficulty; // D (1 - 10)
  int reps;          // 总复习次数
  int lapses;        // 遗忘/失误次数
  int consecutiveCorrect; // 连续正确次数
  DateTime? lastReview;
  DateTime? due;
  int dueStep;       // 会话内短步长到期题号 (-1 表示无会话内步长限制)

  FsrsCard({
    required this.word,
    this.state = CardState.newCard,
    this.stability = 0.4,
    this.difficulty = 5.0,
    this.reps = 0,
    this.lapses = 0,
    this.consecutiveCorrect = 0,
    this.lastReview,
    this.due,
    this.dueStep = -1,
  });

  /// FSRS 4.5/5 Power Forgetting Curve: R(t, S) = (1 + factor * t / S)^decay
  /// Here factor = 19/81 (~0.2346), decay = -0.5, ensuring R(S, S) = 0.90 (90%)
  double getRetrievability([DateTime? now]) {
    final current = now ?? DateTime.now();
    if (lastReview == null) return 0.0;

    final elapsedDays = current.difference(lastReview!).inSeconds / 86400.0;
    if (elapsedDays <= 0) return 1.0;
    if (stability <= 0.01) return 0.0;

    const factor = 19.0 / 81.0;
    const decay = -0.5;

    final r = pow(1.0 + factor * (elapsedDays / stability), decay).toDouble();
    return r.clamp(0.0, 1.0);
  }

  /// Whether this card has graduated to long-term memory (S >= 25 days or consecutiveCorrect >= 4)
  bool get isGraduated => stability >= 25.0 || consecutiveCorrect >= 4;

  /// Categorize card health for the wrong words dashboard
  MemoryCategory get category {
    if (isGraduated) {
      return MemoryCategory.mastered;
    }
    if (lapses >= 2 || getRetrievability() < 0.70) {
      return MemoryCategory.critical;
    }
    return MemoryCategory.consolidating;
  }

  /// Checks if card is due for review right now
  bool isDue(DateTime now, int currentSessionStep) {
    if (isGraduated) return false;

    // Check intrasession step first
    if (dueStep > 0 && currentSessionStep >= dueStep) {
      return true;
    }

    // Check time-based due date or retrievability threshold (R <= 0.90)
    if (due != null && now.isAfter(due!)) {
      return true;
    }

    return getRetrievability(now) <= 0.90;
  }

  Map<String, dynamic> toJson() => {
    'word': word,
    'state': state.index,
    'stability': stability,
    'difficulty': difficulty,
    'reps': reps,
    'lapses': lapses,
    'consecutiveCorrect': consecutiveCorrect,
    'lastReview': lastReview?.toIso8601String(),
    'due': due?.toIso8601String(),
    'dueStep': dueStep,
  };

  factory FsrsCard.fromJson(Map<String, dynamic> json) {
    return FsrsCard(
      word: json['word'] as String,
      state: CardState.values[json['state'] as int? ?? 0],
      stability: (json['stability'] as num?)?.toDouble() ?? 0.4,
      difficulty: (json['difficulty'] as num?)?.toDouble() ?? 5.0,
      reps: json['reps'] as int? ?? 0,
      lapses: json['lapses'] as int? ?? 0,
      consecutiveCorrect: json['consecutiveCorrect'] as int? ?? 0,
      lastReview: json['lastReview'] != null
          ? DateTime.tryParse(json['lastReview'] as String)
          : null,
      due: json['due'] != null ? DateTime.tryParse(json['due'] as String) : null,
      dueStep: json['dueStep'] as int? ?? -1,
    );
  }
}

