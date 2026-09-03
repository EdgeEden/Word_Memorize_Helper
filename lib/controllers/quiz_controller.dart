import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/dict_info.dart';
import '../models/fsrs/fsrs_models.dart';
import '../models/fsrs/fsrs_scheduler.dart';
import '../models/word_item.dart';
import '../services/ai_service.dart';
import '../services/api_service.dart';
import '../services/dict_service.dart';
import '../services/fsrs_repository.dart';
import '../services/update_service.dart';


enum SyncStatus {
  synced,  // 🟢 云端已同步
  syncing, // 🟡 正在同步
  offline, // ⚪ 离线运行
  failed,  // 🔴 同步出错
}

enum EvaluationMode {
  localMatcher, // 本地词典分词匹配 (离线秒判)
  deepseekAi,   // DeepSeek AI 语义判定
}

class QuizController extends ChangeNotifier {
  List<WordItem> _allWords = [];
  final Map<String, WordItem> _wordLookup = {};
  Map<String, FsrsCard> _fsrsCards = {};

  final FsrsScheduler _fsrsScheduler = FsrsScheduler();
  int _sessionStepCounter = 0;

  String _currentDictId = DictService.defaultDictId;
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

  // Evaluation & AI State
  EvaluationMode _evalMode = EvaluationMode.localMatcher;
  String _deepseekApiKey = '';
  String _deepseekBaseUrl = DeepSeekService.defaultBaseUrl;
  String _deepseekModel = DeepSeekService.defaultModel;
  bool _isEvaluating = false;
  String? _evaluationNotice;

  // Token and Cost Statistics State
  bool _showTokenUsage = true;
  int? _lastEvaluationTokens;
  int _sessionTotalTokens = 0;
  double _sessionTotalCost = 0.0;
  String _balanceCurrency = 'CNY';
  double? _previousBalance;

  List<DictInfo> _availableDicts = [...DictService.builtInDicts];

  final Random _random = Random();

  // Getters
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String get currentDictId => _currentDictId;
  DictInfo get currentDict => DictService.getDictInfo(_currentDictId, _availableDicts);
  List<DictInfo> get availableDicts => _availableDicts;
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

  // Evaluation Getters
  EvaluationMode get evalMode => _evalMode;
  String get deepseekApiKey => _deepseekApiKey;
  String get deepseekBaseUrl => _deepseekBaseUrl;
  String get deepseekModel => _deepseekModel;
  bool get isEvaluating => _isEvaluating;
  String? get evaluationNotice => _evaluationNotice;
  bool get isAiEvaluationMode => _evalMode == EvaluationMode.deepseekAi;

  // Token and Cost Getters
  bool get showTokenUsage => _showTokenUsage;
  int? get lastEvaluationTokens => _lastEvaluationTokens;
  int get sessionTotalTokens => _sessionTotalTokens;
  double get sessionTotalCost => _sessionTotalCost;
  String get balanceCurrency => _balanceCurrency;
  bool get hasTokenUsage => _lastEvaluationTokens != null || _sessionTotalTokens > 0;
  bool get isCurrentModelDeepSeek =>
      _deepseekModel.toLowerCase().contains('deepseek') ||
      _deepseekBaseUrl.toLowerCase().contains('deepseek.com');


  // App Update State
  bool _isCheckingUpdate = false;
  UpdateCheckResult? _lastUpdateCheckResult;
  bool get isCheckingUpdate => _isCheckingUpdate;
  UpdateCheckResult? get lastUpdateCheckResult => _lastUpdateCheckResult;


  // FSRS Metrics (Strictly filtered to active dictionary)
  List<FsrsCard> get allCards =>
      _fsrsCards.values.where((c) => _wordLookup.containsKey(c.word.toLowerCase())).toList();

  FsrsCard? get currentCard =>
      _currentWord == null ? null : _fsrsCards[_currentWord!.word.toLowerCase()];

  /// Number of cards due for review right now in active dictionary
  int get dueReviewCount {
    final now = DateTime.now();
    return _fsrsCards.values.where((card) {
      if (!_wordLookup.containsKey(card.word.toLowerCase())) return false;
      return card.isDue(now, _sessionStepCounter);
    }).length;
  }

  /// 🔴 顽固高危词数量
  int get criticalCount =>
      allCards.where((c) => c.category == MemoryCategory.critical).length;

  /// 🟡 巩固进行中数量
  int get consolidatingCount =>
      allCards.where((c) => c.category == MemoryCategory.consolidating).length;

  /// 🟢 趋于掌握/已毕业数量
  int get masteredCount =>
      allCards.where((c) => c.category == MemoryCategory.mastered).length;

  /// Total tracked cards in FSRS for active dictionary
  int get totalTrackedCardsCount => allCards.length;

  WordItem? getWordItem(String word) => _wordLookup[word.toLowerCase()];

  /// Sanitize cards in memory so that only words belonging to the active dictionary are kept
  void _sanitizeCards() {
    if (_wordLookup.isEmpty) return;
    final initialCount = _fsrsCards.length;
    _fsrsCards.removeWhere((wordKey, _) => !_wordLookup.containsKey(wordKey.toLowerCase()));
    if (_fsrsCards.length != initialCount) {
      FsrsRepository.saveCards(_fsrsCards, _currentUsername, _currentDictId);
    }
  }

  /// Initialize and load vocabulary, user session & saved FSRS cards
  Future<void> init() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // 1. Clean up any unlabelled legacy stores or corrupted card formats
      await FsrsRepository.cleanLegacyAndInvalidCards();

      // Load all available dictionaries (built-in + user imported)
      _availableDicts = await DictService.loadAllDicts();

      _currentDictId = await FsrsRepository.getCurrentDictId();
      final dictInfo = currentDict;
      _allWords = await DictService.loadWords(dictInfo);
      _wordLookup.clear();
      for (final w in _allWords) {
        _wordLookup[w.word.toLowerCase()] = w;
      }

      _currentUsername = await FsrsRepository.getCurrentUser();
      _serverUrl = await FsrsRepository.getServerUrl();

      // Load persisted evaluation settings & DeepSeek API Key and Model
      final modeStr = await FsrsRepository.getEvalMode();
      _evalMode = modeStr == 'deepseek' ? EvaluationMode.deepseekAi : EvaluationMode.localMatcher;
      _deepseekApiKey = await FsrsRepository.getDeepSeekApiKey();
      _deepseekBaseUrl = await FsrsRepository.getDeepSeekBaseUrl();
      _deepseekModel = await FsrsRepository.getDeepSeekModel();
      _showTokenUsage = await FsrsRepository.getShowTokenUsage();

      // Load persisted FSRS memory cards for current user and current dictionary
      _fsrsCards = await FsrsRepository.loadCards(_currentUsername, _currentDictId);
      _sanitizeCards();

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

  /// Switch active dictionary, reload word list and independent FSRS memory state
  Future<void> switchDict(String newDictId) async {
    final cleanId = newDictId.trim().toLowerCase();
    if (cleanId == _currentDictId && _allWords.isNotEmpty) return;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // 1. Persist current cards before switching
      await FsrsRepository.saveCards(_fsrsCards, _currentUsername, _currentDictId);

      // 2. Reload available dicts in case custom dict was added
      _availableDicts = await DictService.loadAllDicts();

      // 3. Update current dict id and persist
      _currentDictId = cleanId;
      await FsrsRepository.setCurrentDictId(_currentDictId);

      // 4. Load words for new dictionary
      final dictInfo = currentDict;
      _allWords = await DictService.loadWords(dictInfo);
      _wordLookup.clear();
      for (final w in _allWords) {
        _wordLookup[w.word.toLowerCase()] = w;
      }

      // 5. Load independent cards for new dictionary and sanitize
      _fsrsCards = await FsrsRepository.loadCards(_currentUsername, _currentDictId);
      _sanitizeCards();

      // 5. Reset wrong review mode & pick next word
      _isWrongReviewMode = false;
      _isSubmitted = false;
      _isCorrect = null;
      _showHint = false;
      _lastUserInput = '';
      _evaluationNotice = null;

      if (_allWords.isEmpty) {
        _errorMessage = '词库为空或加载失败';
      } else {
        _pickNextWord();
      }

      // 6. Pull cloud cards for this dictionary if logged in
      if (isLoggedIn) {
        _pullAndMergeCloudCards();
      }
    } catch (e) {
      _errorMessage = '切换词库失败: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Check for software updates from server
  Future<UpdateCheckResult> checkForUpdates({bool isSilent = false}) async {
    if (!isSilent) notifyListeners();

    try {
      final result = await UpdateService.checkUpdate(serverUrl: _serverUrl);
      _lastUpdateCheckResult = result;
      return result;
    } finally {
      _isCheckingUpdate = false;
      notifyListeners();
    }
  }


  /// Set evaluation mode (local vs deepseek)
  Future<void> setEvalMode(EvaluationMode mode) async {
    _evalMode = mode;
    await FsrsRepository.setEvalMode(mode == EvaluationMode.deepseekAi ? 'deepseek' : 'local');
    notifyListeners();
  }

  /// Update DeepSeek configuration and persist locally
  Future<void> updateDeepSeekConfig({
    required String apiKey,
    String? baseUrl,
    String? model,
  }) async {
    _deepseekApiKey = apiKey.trim();
    if (baseUrl != null && baseUrl.trim().isNotEmpty) {
      _deepseekBaseUrl = baseUrl.trim();
    } else {
      _deepseekBaseUrl = DeepSeekService.defaultBaseUrl;
    }
    _deepseekModel = model?.trim() ?? '';

    await FsrsRepository.setDeepSeekApiKey(_deepseekApiKey);
    await FsrsRepository.setDeepSeekBaseUrl(_deepseekBaseUrl);
    await FsrsRepository.setDeepSeekModel(_deepseekModel);
  }

  /// Set whether to show token usage statistics on main screen
  Future<void> setShowTokenUsage(bool value) async {
    _showTokenUsage = value;
    await FsrsRepository.setShowTokenUsage(value);
    notifyListeners();
  }



  /// Login or register a user and sync their cloud cards
  Future<bool> login(String username) async {
    final cleanUsername = username.trim().toLowerCase();
    if (cleanUsername.isEmpty) return false;
    _isLoading = true;
    notifyListeners();

    try {
      _currentUsername = cleanUsername;
      await FsrsRepository.setCurrentUser(cleanUsername);

      // 1. Load local cards for this user first for current dictionary
      _fsrsCards = await FsrsRepository.loadCards(cleanUsername, _currentDictId);

      // 2. Connect to server
      _syncStatus = SyncStatus.syncing;
      notifyListeners();

      final loginResult = await ApiService.loginOrRegister(
        cleanUsername,
        serverUrl: _serverUrl,
        dictId: _currentDictId,
      );

      if (loginResult != null) {
        final serverCards = loginResult['cards'] as Map<String, FsrsCard>? ?? {};
        // Merge remote cards with local cards (only for active dictionary)
        _mergeCards(serverCards);
        await FsrsRepository.saveCards(_fsrsCards, cleanUsername, _currentDictId);
        _syncStatus = SyncStatus.synced;
      } else {
        _syncStatus = SyncStatus.offline;
      }

      _pickNextWord();
      return true;
    } catch (e) {
      debugPrint('Login exception: $e');
      _syncStatus = SyncStatus.failed;
      return true; // Still allow local offline usage
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Logout current user
  Future<void> logout() async {
    _currentUsername = null;
    await FsrsRepository.setCurrentUser(null);
    _fsrsCards = await FsrsRepository.loadCards(null, _currentDictId);
    _sanitizeCards();
    _pickNextWord();
    notifyListeners();
  }

  /// Update server URL and trigger a sync test
  Future<void> updateServerUrl(String newUrl) async {
    _serverUrl = newUrl.trim();
    await FsrsRepository.setServerUrl(_serverUrl);
    notifyListeners();
    if (isLoggedIn) {
      syncNow();
    }
  }

  /// Manually trigger a full bidirectional sync
  Future<void> syncNow() async {
    if (!isLoggedIn) return;
    _syncStatus = SyncStatus.syncing;
    notifyListeners();

    try {
      final remoteCards = await ApiService.fetchCards(_currentUsername!, serverUrl: _serverUrl, dictId: _currentDictId);
      if (remoteCards != null) {
        _mergeCards(remoteCards);
        await FsrsRepository.saveCards(_fsrsCards, _currentUsername, _currentDictId);
        final pushSuccess = await ApiService.syncCards(_currentUsername!, _fsrsCards, serverUrl: _serverUrl, dictId: _currentDictId);
        _syncStatus = pushSuccess ? SyncStatus.synced : SyncStatus.failed;
      } else {
        _syncStatus = SyncStatus.offline;
      }
    } catch (_) {
      _syncStatus = SyncStatus.offline;
    } finally {
      notifyListeners();
    }
  }

  /// Smart Card Merging Algorithm (strictly ensures words belong to active dictionary)
  void _mergeCards(Map<String, FsrsCard> remoteCards) {
    remoteCards.forEach((word, remoteCard) {
      final key = word.toLowerCase();
      // Ensure the word belongs to the current dictionary
      if (!_wordLookup.containsKey(key)) return;

      final localCard = _fsrsCards[key];
      if (localCard == null) {
        _fsrsCards[key] = remoteCard;
      } else {
        // If both exist, take the one with higher reps or later review time
        if (remoteCard.reps > localCard.reps) {
          _fsrsCards[key] = remoteCard;
        } else if (remoteCard.reps == localCard.reps) {
          if (remoteCard.lastReview != null && localCard.lastReview != null) {
            if (remoteCard.lastReview!.isAfter(localCard.lastReview!)) {
              _fsrsCards[key] = remoteCard;
            }
          }
        }
      }
    });
  }

  /// Background pull and merge on login
  Future<void> _pullAndMergeCloudCards() async {
    if (!isLoggedIn) return;
    _syncStatus = SyncStatus.syncing;
    notifyListeners();

    try {
      final remoteCards = await ApiService.fetchCards(_currentUsername!, serverUrl: _serverUrl, dictId: _currentDictId);
      if (remoteCards != null) {
        _mergeCards(remoteCards);
        await FsrsRepository.saveCards(_fsrsCards, _currentUsername, _currentDictId);
        _syncStatus = SyncStatus.synced;
      } else {
        _syncStatus = SyncStatus.offline;
      }
    } catch (_) {
      _syncStatus = SyncStatus.offline;
    } finally {
      notifyListeners();
    }
  }

  /// Asynchronous push sync to server on card change
  void _pushSyncToServer() {
    if (!isLoggedIn) return;
    ApiService.syncCards(_currentUsername!, _fsrsCards, serverUrl: _serverUrl, dictId: _currentDictId).then((success) {
      _syncStatus = success ? SyncStatus.synced : SyncStatus.failed;
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

  /// Submit answer, evaluate correctness:
  /// 1. Always perform fast local dictionary match first.
  /// 2. If local match fails and user selected AI mode, invoke DeepSeek API for semantic evaluation.
  /// 3. Update FSRS memory state, and schedule next review.
  Future<void> submitAnswer(String input) async {
    if (_isSubmitted || _isEvaluating || _currentWord == null) return;

    _lastUserInput = input.trim();
    _evaluationNotice = null;

    bool isAnswerCorrect;

    // Fast-path: Empty input is directly incorrect without querying AI
    if (_lastUserInput.isEmpty) {
      isAnswerCorrect = false;
    } else {
      // Step 1: Always perform local dictionary matching first
      final bool localMatched = _currentWord!.checkAnswer(_lastUserInput);

      if (localMatched) {
        // Local dictionary matched directly -> instant success, no AI call needed
        isAnswerCorrect = true;
      } else if (_evalMode == EvaluationMode.deepseekAi) {
        // Step 2: Local match failed and user selected AI mode -> evaluate via AI API
        if (_deepseekApiKey.trim().isEmpty) {
          isAnswerCorrect = false;
          _evaluationNotice = '本地匹配未通过，且未配置 AI API Key';
        } else if (_deepseekModel.trim().isEmpty) {
          isAnswerCorrect = false;
          _evaluationNotice = '本地匹配未通过，且未选择 AI 模型';
        } else {
          _isEvaluating = true;
          notifyListeners();

          final isDeepSeek = isCurrentModelDeepSeek;
          // If DeepSeek model and baseline balance has not been fetched yet, establish it
          if (isDeepSeek && _previousBalance == null) {
            final initialBalanceInfo = await DeepSeekService.getUserBalance(
              apiKey: _deepseekApiKey,
              baseUrl: _deepseekBaseUrl,
            );
            if (initialBalanceInfo != null) {
              _previousBalance = initialBalanceInfo.totalBalance;
              _balanceCurrency = initialBalanceInfo.currency;
            }
          }

          final aiResult = await DeepSeekService.evaluateAnswer(
            word: _currentWord!.word,
            userInput: _lastUserInput,
            apiKey: _deepseekApiKey,
            baseUrl: _deepseekBaseUrl,
            model: _deepseekModel,
          );

          _isEvaluating = false;

          // Record token usage
          if (aiResult.totalTokens > 0) {
            _lastEvaluationTokens = aiResult.totalTokens;
            _sessionTotalTokens += aiResult.totalTokens;
          }

          // If DeepSeek model, query user balance to compute consumed amount
          if (isDeepSeek) {
            final currentBalanceInfo = await DeepSeekService.getUserBalance(
              apiKey: _deepseekApiKey,
              baseUrl: _deepseekBaseUrl,
            );
            if (currentBalanceInfo != null) {
              _balanceCurrency = currentBalanceInfo.currency;
              if (_previousBalance != null) {
                final delta = _previousBalance! - currentBalanceInfo.totalBalance;
                if (delta > 0.000001) {
                  _sessionTotalCost += delta;
                }
              }
              _previousBalance = currentBalanceInfo.totalBalance;
            }
          }

          if (aiResult.isApproved != null) {
            isAnswerCorrect = aiResult.isApproved!;
            if (aiResult.isApproved!) {
              final modelName = _deepseekModel.trim().isNotEmpty
                  ? _deepseekModel.trim()
                  : DeepSeekService.defaultModel;
              _evaluationNotice = '由 $modelName 判定为正确';
            }
          } else {
            isAnswerCorrect = false;
            final modelName = _deepseekModel.trim().isNotEmpty
                ? _deepseekModel.trim()
                : DeepSeekService.defaultModel;
            _evaluationNotice = '本地匹配未通过，且 $modelName 网络连接异常';
            debugPrint('[QuizController] AI 判定请求未成功返回结果 ($modelName)，单词: "${_currentWord!.word}", 输入: "$_lastUserInput"');
          }
        }


      } else {
        // Local matcher mode and local match failed
        isAnswerCorrect = false;
      }
    }

    _isSubmitted = true;
    _isCorrect = isAnswerCorrect;


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
    FsrsRepository.saveCards(_fsrsCards, _currentUsername, _currentDictId);

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
  /// 2. If no due review items, pulls fresh words from the current dictionary
  void _pickNextWord() {
    _isSubmitted = false;
    _isCorrect = null;
    _showHint = false;
    _lastUserInput = '';
    _evaluationNotice = null;

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
    await FsrsRepository.saveCards(_fsrsCards, _currentUsername, _currentDictId);
    _pushSyncToServer();
    notifyListeners();
  }

  /// Clear wrong book & FSRS memory cards for current dictionary or all dictionaries
  /// [clearAll]: if true, clears all dictionaries; if false, clears only [currentDictId]
  Future<bool> clearWrongBookData({bool clearAll = false}) async {
    _isLoading = true;
    notifyListeners();

    try {
      final targetDictId = clearAll ? null : _currentDictId;

      // 1. Clear local storage
      await FsrsRepository.clearCards(_currentUsername, targetDictId);

      // 2. Clear in-memory cards for current dict
      _fsrsCards.clear();
      _isWrongReviewMode = false;

      // 3. Clear cloud database if logged in
      if (isLoggedIn) {
        await ApiService.deleteCards(
          _currentUsername!,
          dictId: targetDictId,
          serverUrl: _serverUrl,
        );
      }

      // 4. Refresh word picker
      _pickNextWord();
      return true;
    } catch (e) {
      debugPrint('clearWrongBookData error: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Imports a new user custom CSV vocabulary dictionary
  Future<DictInfo> importCustomDict({
    required String name,
    String? description,
    required String csvContent,
    bool switchImmediately = true,
  }) async {
    final newDict = await DictService.saveCustomDict(
      name: name,
      description: description,
      csvContent: csvContent,
    );
    _availableDicts = await DictService.loadAllDicts();
    if (switchImmediately) {
      await switchDict(newDict.id);
    } else {
      notifyListeners();
    }
    return newDict;
  }

  /// Deletes a custom dictionary and clears associated wrong book cards
  Future<void> deleteCustomDict(String dictId) async {
    final cleanId = dictId.trim().toLowerCase();
    
    // Clear storage for this dictionary
    await FsrsRepository.clearCards(_currentUsername, cleanId);
    if (isLoggedIn) {
      await ApiService.deleteCards(_currentUsername!, dictId: cleanId, serverUrl: _serverUrl);
    }

    await DictService.deleteCustomDict(cleanId);
    _availableDicts = await DictService.loadAllDicts();

    if (_currentDictId.toLowerCase() == cleanId) {
      await switchDict(DictService.defaultDictId);
    } else {
      notifyListeners();
    }
  }

  /// Reloads available dicts list
  Future<void> reloadAvailableDicts() async {
    _availableDicts = await DictService.loadAllDicts();
    notifyListeners();
  }
}


