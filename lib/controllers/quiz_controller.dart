import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/fsrs/fsrs_models.dart';
import '../models/fsrs/fsrs_scheduler.dart';
import '../models/word_item.dart';
import '../services/api_service.dart';
import '../services/dict_service.dart';
import '../services/fsrs_repository.dart';

enum SyncStatus {
  synced,  // 🟢 云端已同步
  syncing, // 🟡 正在同步
  offline, // ⚪ 离线运行
  failed,  // 🔴 同步出错
}

class QuizController extends ChangeNotifier {
  List<WordItem> _allWords = [];
  final Map<String, WordItem> _wordLookup = {};
  Map<String, FsrsCard> _fsrsCards = {};

  final FsrsScheduler _fsrsScheduler = FsrsScheduler();
  int _sessionStepCounter = 0;

  WordItem? _currentWord;
  bool _isCurrentWordReview = false;
  bool _isLoading = true;
  String? _errorMessage;

  bool _isSubmitted = false;
  bool? _isCorrect;
  bool _showHint = false;
  String _lastUserInput = '';

  int _totalAnswered = 0;
  int _correctCount = 0;
  int _streak = 0;
  int _maxStreak = 0;
  bool _isWrongReviewMode = false;

  // Account and Cloud Sync State
  String? _currentUsername;
  String _serverUrl = ApiService.getDefaultServerUrl();
  SyncStatus _syncStatus = SyncStatus.synced;

  final Random _random = Random();

  // Getters
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  WordItem? get currentWord => _currentWord;
  bool get isCurrentWordReview => _isCurrentWordReview;
  bool get isSubmitted => _isSubmitted;
  bool? get isCorrect => _isCorrect;
  bool get showHint => _showHint;
  String get lastUserInput => _lastUserInput;
  int get sessionStepCounter => _sessionStepCounter;

  int get totalWordsCount => _allWords.length;
  int get totalAnswered => _totalAnswered;
  int get correctCount => _correctCount;
  int get streak => _streak;
  int get maxStreak => _maxStreak;
  bool get isWrongReviewMode => _isWrongReviewMode;

  double get accuracy => _totalAnswered == 0 ? 0.0 : (_correctCount / _totalAnswered) * 100;

  // User & Sync Getters
  String? get currentUsername => _currentUsername;
  bool get isLoggedIn => _currentUsername != null && _currentUsername!.isNotEmpty;
  SyncStatus get syncStatus => _syncStatus;
  String get serverUrl => _serverUrl;

  // FSRS Metrics
  List<FsrsCard> get allCards => _fsrsCards.values.toList();

  FsrsCard? get currentCard =>
      _currentWord == null ? null : _fsrsCards[_currentWord!.word.toLowerCase()];

  /// Number of cards due for review right now
  int get dueReviewCount {
    final now = DateTime.now();
    return _fsrsCards.values.where((card) => card.isDue(now, _sessionStepCounter)).length;
  }

  /// 🔴 顽固高危词数量
  int get criticalCount =>
      _fsrsCards.values.where((c) => c.category == MemoryCategory.critical).length;

  /// 🟡 巩固进行中数量
  int get consolidatingCount =>
      _fsrsCards.values.where((c) => c.category == MemoryCategory.consolidating).length;

  /// 🟢 趋于掌握/已毕业数量
  int get masteredCount =>
      _fsrsCards.values.where((c) => c.category == MemoryCategory.mastered).length;

  /// Total tracked cards in FSRS
  int get totalTrackedCardsCount => _fsrsCards.length;

  WordItem? getWordItem(String word) => _wordLookup[word.toLowerCase()];

  /// Initialize and load vocabulary, user session & saved FSRS cards
  Future<void> init() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _allWords = await DictService.loadFromAsset();
      for (final w in _allWords) {
        _wordLookup[w.word.toLowerCase()] = w;
      }

      _currentUsername = await FsrsRepository.getCurrentUser();
      _serverUrl = await FsrsRepository.getServerUrl();

      // Load persisted FSRS memory cards for current user
      _fsrsCards = await FsrsRepository.loadCards(_currentUsername);

      if (_allWords.isEmpty) {
        _errorMessage = '词库为空或加载失败';
      } else {
        _pickNextWord();
      }

      // If user is logged in, perform background cloud sync
      if (isLoggedIn) {
        _pullAndMergeCloudCards();
      }
    } catch (e) {
      _errorMessage = '加载词库发生错误: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Login or register a user and sync their cloud cards
  Future<bool> login(String username) async {
    final cleanUsername = username.trim().toLowerCase();
    if (cleanUsername.isEmpty) return false;

    _currentUsername = cleanUsername;
    await FsrsRepository.setCurrentUser(cleanUsername);

    _syncStatus = SyncStatus.syncing;
    notifyListeners();

    // 1. Load any existing local cards for this user
    final localCards = await FsrsRepository.loadCards(cleanUsername);
    _fsrsCards = Map.from(localCards);

    // 2. Contact Python backend
    final result = await ApiService.loginOrRegister(cleanUsername, serverUrl: _serverUrl);
    if (result != null) {
      final Map<String, FsrsCard> remoteCards = result['cards'] as Map<String, FsrsCard>? ?? {};
      _mergeCards(remoteCards);
      await FsrsRepository.saveCards(_fsrsCards, cleanUsername);
      _syncStatus = SyncStatus.synced;
    } else {
      _syncStatus = SyncStatus.offline;
    }

    _pickNextWord();
    notifyListeners();
    return true;
  }

  /// Logout current user
  Future<void> logout() async {
    _currentUsername = null;
    await FsrsRepository.setCurrentUser(null);
    _fsrsCards = {};
    _syncStatus = SyncStatus.offline;
    _pickNextWord();
    notifyListeners();
  }

  /// Trigger manual two-way sync
  Future<void> syncNow() async {
    if (!isLoggedIn) return;

    _syncStatus = SyncStatus.syncing;
    notifyListeners();

    final remoteCards = await ApiService.fetchCards(_currentUsername!, serverUrl: _serverUrl);
    if (remoteCards != null) {
      _mergeCards(remoteCards);
      await FsrsRepository.saveCards(_fsrsCards, _currentUsername);
      final pushSuccess = await ApiService.syncCards(_currentUsername!, _fsrsCards, serverUrl: _serverUrl);
      _syncStatus = pushSuccess ? SyncStatus.synced : SyncStatus.failed;
    } else {
      _syncStatus = SyncStatus.offline;
    }

    notifyListeners();
  }

  /// Update backend server URL
  Future<void> updateServerUrl(String newUrl) async {
    final cleanUrl = newUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (cleanUrl.isEmpty) return;

    _serverUrl = cleanUrl;
    await FsrsRepository.setServerUrl(_serverUrl);
    notifyListeners();
    await syncNow();
  }

  /// Merge remote cards into local cards (preferring newer/higher reps)
  void _mergeCards(Map<String, FsrsCard> remoteCards) {
    for (final entry in remoteCards.entries) {
      final wordKey = entry.key.toLowerCase();
      final remoteCard = entry.value;
      if (!_fsrsCards.containsKey(wordKey)) {
        _fsrsCards[wordKey] = remoteCard;
      } else {
        final localCard = _fsrsCards[wordKey]!;
        // Choose card with more reps or more recent review
        if (remoteCard.reps > localCard.reps) {
          _fsrsCards[wordKey] = remoteCard;
        } else if (remoteCard.reps == localCard.reps &&
            remoteCard.lastReview != null &&
            (localCard.lastReview == null || remoteCard.lastReview!.isAfter(localCard.lastReview!))) {
          _fsrsCards[wordKey] = remoteCard;
        }
      }
    }
  }

  /// Asynchronously pull cloud cards on startup
  Future<void> _pullAndMergeCloudCards() async {
    if (!isLoggedIn) return;

    _syncStatus = SyncStatus.syncing;
    notifyListeners();

    final remoteCards = await ApiService.fetchCards(_currentUsername!, serverUrl: _serverUrl);
    if (remoteCards != null) {
      _mergeCards(remoteCards);
      await FsrsRepository.saveCards(_fsrsCards, _currentUsername);
      _syncStatus = SyncStatus.synced;
    } else {
      _syncStatus = SyncStatus.offline;
    }
    notifyListeners();
  }

  /// Asynchronously push updated cards to server
  void _pushSyncToServer() {
    if (!isLoggedIn) return;

    _syncStatus = SyncStatus.syncing;
    notifyListeners();

    ApiService.syncCards(_currentUsername!, _fsrsCards, serverUrl: _serverUrl).then((success) {
      _syncStatus = success ? SyncStatus.synced : SyncStatus.offline;
      notifyListeners();
    }).catchError((_) {
      _syncStatus = SyncStatus.offline;
      notifyListeners();
    });
  }

  /// Toggle hint (example sentence) visibility
  void toggleHint() {
    _showHint = !_showHint;
    notifyListeners();
  }

  /// Submit answer, update FSRS memory state, and schedule next review
  void submitAnswer(String input) {
    if (_isSubmitted || _currentWord == null) return;

    _lastUserInput = input.trim();
    _isSubmitted = true;
    _isCorrect = _currentWord!.checkAnswer(_lastUserInput);

    _totalAnswered++;
    _sessionStepCounter++;

    final wordKey = _currentWord!.word.toLowerCase();
    final card = _fsrsCards[wordKey] ?? FsrsCard(word: _currentWord!.word);

    // Determine FSRS Rating based on performance
    final Rating rating;
    if (_isCorrect == true) {
      _correctCount++;
      _streak++;
      if (_streak > _maxStreak) {
        _maxStreak = _streak;
      }

      if (_showHint) {
        rating = Rating.hard; // Answered correctly with hint
      } else if (_streak >= 3) {
        rating = Rating.easy; // Highly confident / on a streak
      } else {
        rating = Rating.good; // Standard correct recall
      }
    } else {
      _streak = 0;
      rating = Rating.again; // Missed / Forgot
    }

    // Process memory state through FSRS Scheduler
    final now = DateTime.now();
    final updatedCard = _fsrsScheduler.reviewCard(
      card: card,
      rating: rating,
      now: now,
      currentSessionStep: _sessionStepCounter,
    );

    _fsrsCards[wordKey] = updatedCard;

    // Asynchronously persist updated memory states locally
    FsrsRepository.saveCards(_fsrsCards, _currentUsername);

    // Asynchronously push to cloud backend
    _pushSyncToServer();

    notifyListeners();
  }

  /// Advance to the next word
  void nextWord() {
    _pickNextWord();
    notifyListeners();
  }

  /// FSRS Intelligent Interleaved Scheduler:
  /// 1. Prioritizes due review items (intrasession step or R <= 0.90)
  /// 2. If no due review items, pulls fresh words from the 4533 dictionary
  void _pickNextWord() {
    _isSubmitted = false;
    _isCorrect = null;
    _showHint = false;
    _lastUserInput = '';

    final now = DateTime.now();

    // 1. Gather all cards that are currently due
    final dueCards = _fsrsCards.values.where((c) {
      if (_isWrongReviewMode) {
        // In exclusive wrong/review mode, include all non-mastered cards or due cards
        return !c.isGraduated;
      }
      return c.isDue(now, _sessionStepCounter);
    }).toList();

    if (dueCards.isNotEmpty) {
      // Sort due cards: intrasession step due first, then lowest Retrievability R first
      dueCards.sort((a, b) {
        final aStepDue = a.dueStep > 0 && _sessionStepCounter >= a.dueStep;
        final bStepDue = b.dueStep > 0 && _sessionStepCounter >= b.dueStep;
        if (aStepDue && !bStepDue) return -1;
        if (!aStepDue && bStepDue) return 1;

        final rA = a.getRetrievability(now);
        final rB = b.getRetrievability(now);
        return rA.compareTo(rB);
      });

      // Avoid picking the exact same word as previous if multiple available
      FsrsCard chosenCard = dueCards.first;
      for (final c in dueCards) {
        if (_currentWord == null || c.word.toLowerCase() != _currentWord!.word.toLowerCase()) {
          chosenCard = c;
          break;
        }
      }

      final matchedWord = _wordLookup[chosenCard.word.toLowerCase()];
      if (matchedWord != null) {
        _currentWord = matchedWord;
        _isCurrentWordReview = true;
        return;
      }
    }

    // 2. If no due review cards, pull a fresh word from the dictionary
    if (_isWrongReviewMode && dueCards.isEmpty) {
      // If wrong review mode has no remaining words, exit review mode automatically
      _isWrongReviewMode = false;
    }

    _isCurrentWordReview = false;

    if (_allWords.isEmpty) {
      _currentWord = null;
      return;
    }

    if (_allWords.length == 1) {
      _currentWord = _allWords.first;
      return;
    }

    // Pick a random word different from current
    WordItem next;
    do {
      final index = _random.nextInt(_allWords.length);
      next = _allWords[index];
    } while (next == _currentWord && _allWords.length > 1);

    _currentWord = next;
  }

  /// Toggle wrong word review mode
  void toggleWrongReviewMode() {
    _isWrongReviewMode = !_isWrongReviewMode;
    _pickNextWord();
    notifyListeners();
  }

  /// Reset card history if requested by user
  Future<void> resetWordMemory(String word) async {
    final key = word.toLowerCase();
    _fsrsCards.remove(key);
    await FsrsRepository.saveCards(_fsrsCards, _currentUsername);
    _pushSyncToServer();
    notifyListeners();
  }
}
