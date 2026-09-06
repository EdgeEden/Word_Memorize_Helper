import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/fsrs/fsrs_models.dart';
import 'ai_service.dart';
import 'api_service.dart';
import 'dict_service.dart';

class FsrsRepository {
  static const String _defaultStorageKey = 'wordn_fsrs_cards_v1';
  static const String _currentUserKey = 'wordn_current_user';
  static const String _userHistoryKey = 'wordn_user_history_list';
  static const String _serverUrlKey = 'wordn_server_url';
  static const String _currentDictKey = 'wordn_current_dict_id';

  // Evaluation & Settings Keys
  static const String _evalModeKey = 'wordn_eval_mode';
  static const String _deepseekApiKey = 'wordn_deepseek_api_key';
  static const String _deepseekBaseUrlKey = 'wordn_deepseek_base_url';
  static const String _deepseekModelKey = 'wordn_deepseek_model';
  static const String _themeModeKey = 'wordn_theme_mode';
  static const String _showTokenUsageKey = 'wordn_show_token_usage';
  static const String _audioSourceKey = 'wordn_audio_source';
  static const String _autoPlayModeKey = 'wordn_auto_play_mode';


  static String _getKeyForUser(String? username, [String dictId = 'kaoyan4533']) {
    final cleanDict = dictId.trim().toLowerCase().isEmpty ? 'kaoyan4533' : dictId.trim().toLowerCase();
    if (username == null || username.trim().isEmpty) {
      return 'wordn_cards_guest_$cleanDict';
    }
    return 'wordn_cards_${username.trim().toLowerCase()}_$cleanDict';
  }

  /// Get currently selected dictionary ID (defaults to 'kaoyan4533')
  static Future<String> getCurrentDictId([String defaultId = 'kaoyan4533']) async {
    final prefs = await SharedPreferences.getInstance();
    final dictId = prefs.getString(_currentDictKey);
    return (dictId != null && dictId.trim().isNotEmpty) ? dictId.trim() : defaultId;
  }

  /// Persist selected dictionary ID
  static Future<void> setCurrentDictId(String dictId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentDictKey, dictId.trim());
  }

  /// Get the currently logged-in username (persisted across Android, Windows, and Web)
  static Future<String?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final user = prefs.getString(_currentUserKey);
    return (user != null && user.trim().isNotEmpty) ? user.trim().toLowerCase() : null;
  }

  /// Set the currently logged-in username and record in history for auto-login
  static Future<void> setCurrentUser(String? username) async {
    final prefs = await SharedPreferences.getInstance();
    if (username == null || username.trim().isEmpty) {
      await prefs.remove(_currentUserKey);
    } else {
      final clean = username.trim().toLowerCase();
      await prefs.setString(_currentUserKey, clean);
      await saveUserToHistory(clean);
    }
  }

  /// Get history of previously logged-in usernames
  static Future<List<String>> getUserHistory() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_userHistoryKey) ?? [];
  }

  /// Save username to user history list
  static Future<void> saveUserToHistory(String username) async {
    final clean = username.trim().toLowerCase();
    if (clean.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_userHistoryKey) ?? [];
    if (!list.contains(clean)) {
      list.insert(0, clean);
      await prefs.setStringList(_userHistoryKey, list);
    } else {
      list.remove(clean);
      list.insert(0, clean);
      await prefs.setStringList(_userHistoryKey, list);
    }
  }

  /// Remove user from history
  static Future<void> removeUserFromHistory(String username) async {
    final clean = username.trim().toLowerCase();
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_userHistoryKey) ?? [];
    list.remove(clean);
    await prefs.setStringList(_userHistoryKey, list);
  }

  /// Get configured server URL (or platform default)
  static Future<String> getServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_serverUrlKey);
    if (url != null && url.trim().isNotEmpty) {
      return url.trim();
    }
    return ApiService.getDefaultServerUrl();
  }

  /// Save configured server URL
  static Future<void> setServerUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serverUrlKey, url.trim());
  }

  /// Get answer evaluation mode: 'local' (default) or 'deepseek'
  static Future<String> getEvalMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_evalModeKey) ?? 'local';
  }

  /// Save answer evaluation mode
  static Future<void> setEvalMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_evalModeKey, mode);
  }

  /// Get stored DeepSeek API Key
  static Future<String> getDeepSeekApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_deepseekApiKey) ?? '';
  }

  /// Save DeepSeek API Key locally (auto-filled on startup)
  static Future<void> setDeepSeekApiKey(String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deepseekApiKey, apiKey.trim());
  }

  /// Get DeepSeek API Base URL
  static Future<String> getDeepSeekBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_deepseekBaseUrlKey);
    if (url != null && url.trim().isNotEmpty) {
      return url.trim();
    }
    return DeepSeekService.defaultBaseUrl;
  }

  /// Save DeepSeek API Base URL
  static Future<void> setDeepSeekBaseUrl(String baseUrl) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deepseekBaseUrlKey, baseUrl.trim());
  }

  /// Get stored AI Model ID (empty if not configured)
  static Future<String> getDeepSeekModel() async {
    final prefs = await SharedPreferences.getInstance();
    final model = prefs.getString(_deepseekModelKey);
    if (model != null && model.trim().isNotEmpty) {
      return model.trim();
    }
    return '';
  }


  /// Save DeepSeek Model ID
  static Future<void> setDeepSeekModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deepseekModelKey, model.trim());
  }


  /// Get theme mode: 'system', 'light', 'dark'
  static Future<String> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_themeModeKey) ?? 'system';
  }

  /// Save theme mode
  static Future<void> setThemeMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, mode);
  }

  /// Get whether to show token usage statistics on main screen (defaults to true)
  static Future<bool> getShowTokenUsage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_showTokenUsageKey) ?? true;
  }

  /// Save whether to show token usage statistics on main screen
  static Future<void> setShowTokenUsage(bool show) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showTokenUsageKey, show);
  }

  /// Get pronunciation audio source: 'youdao', 'freeDictionary' (defaults to 'youdao')
  static Future<String> getAudioSource() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_audioSourceKey) ?? 'youdao';
  }

  /// Save pronunciation audio source
  static Future<void> setAudioSource(String source) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_audioSourceKey, source.trim());
  }

  /// Get auto-play mode: 'never', 'questionOnly', 'answerOnly', 'always' (defaults to 'never')
  static Future<String> getAutoPlayMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_autoPlayModeKey) ?? 'never';
  }

  /// Save auto-play mode
  static Future<void> setAutoPlayMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_autoPlayModeKey, mode.trim());
  }

  /// Inspects all keys in SharedPreferences.
  /// Removes legacy unlabelled card stores (e.g. wordn_fsrs_cards_v1, `wordn_cards_<username>` without dictId),
  /// and validates/sanitizes all multi-dict card JSON structures.
  static Future<void> cleanLegacyAndInvalidCards() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();

      // Dynamically retrieve all registered dictionary IDs (built-in + custom)
      final allDicts = await DictService.loadAllDicts();
      final validDictIds = allDicts.map((d) => d.id.toLowerCase()).toSet();

      for (final key in allKeys) {
        // 1. Remove legacy unlabelled default key
        if (key == _defaultStorageKey) {
          await prefs.remove(key);
          continue;
        }

        // 2. Check card storage keys: pattern wordn_cards_<user>_<dictId>
        if (key.startsWith('wordn_cards_')) {
          // Check if key ends with one of the valid dict IDs
          final hasValidDict = validDictIds.any((dictId) => key.endsWith('_$dictId'));
          if (!hasValidDict) {
            // This is an unlabelled legacy card key (e.g. wordn_cards_alex) -> Delete it!
            await prefs.remove(key);
            continue;
          }

          // 3. For keys with valid dict suffix, inspect and validate JSON data structure
          final raw = prefs.getString(key);
          if (raw == null || raw.trim().isEmpty) {
            await prefs.remove(key);
            continue;
          }

          try {
            final decoded = jsonDecode(raw);
            if (decoded is! Map<String, dynamic>) {
              // Corrupted / non-map root structure -> remove
              await prefs.remove(key);
              continue;
            }

            final Map<String, dynamic> validCardsMap = {};
            bool modified = false;

            decoded.forEach((wordKey, cardData) {
              if (cardData is Map<String, dynamic>) {
                try {
                  // Validate that FsrsCard.fromJson succeeds and has valid word
                  final card = FsrsCard.fromJson(cardData);
                  if (card.word.trim().isNotEmpty) {
                    validCardsMap[card.word.toLowerCase()] = card.toJson();
                  } else {
                    modified = true;
                  }
                } catch (_) {
                  modified = true; // Invalid card structure discarded
                }
              } else {
                modified = true;
              }
            });

            if (validCardsMap.isEmpty) {
              await prefs.remove(key);
            } else if (modified) {
              await prefs.setString(key, jsonEncode(validCardsMap));
            }
          } catch (_) {
            // Corrupted JSON -> remove
            await prefs.remove(key);
          }
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('cleanLegacyAndInvalidCards error: $e');
    }
  }

  /// Loads all stored FSRS cards from local storage for the specified user and dictionary
  static Future<Map<String, FsrsCard>> loadCards([String? username, String dictId = 'kaoyan4533']) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getKeyForUser(username, dictId);
      final raw = prefs.getString(key);

      if (raw == null || raw.isEmpty) return {};

      final Map<String, dynamic> decoded = jsonDecode(raw) as Map<String, dynamic>;
      final Map<String, FsrsCard> result = {};

      decoded.forEach((word, value) {
        if (value is Map<String, dynamic>) {
          try {
            final card = FsrsCard.fromJson(value);
            if (card.word.trim().isNotEmpty) {
              result[word.toLowerCase()] = card;
            }
          } catch (_) {
            // Skip invalid structure
          }
        }
      });

      return result;
    } catch (e) {
      // ignore: avoid_print
      print('Failed to load FSRS cards from storage: $e');
      return {};
    }
  }

  /// Persists all FSRS cards to local storage for the specified user and dictionary
  static Future<void> saveCards(Map<String, FsrsCard> cards, [String? username, String dictId = 'kaoyan4533']) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getKeyForUser(username, dictId);
      final Map<String, dynamic> mapToSave = {};
      cards.forEach((word, card) {
        mapToSave[word] = card.toJson();
      });

      final raw = jsonEncode(mapToSave);
      await prefs.setString(key, raw);
    } catch (e) {
      // ignore: avoid_print
      print('Failed to save FSRS cards to storage: $e');
    }
  }

  /// Clears stored cards for a user and dictionary from local storage
  /// If [dictId] is null or 'all', clears all dictionaries for this user (or guest)
  static Future<void> clearCards([String? username, String? dictId]) async {
    final prefs = await SharedPreferences.getInstance();
    if (dictId != null && dictId.trim().isNotEmpty && dictId.trim().toLowerCase() != 'all') {
      final key = _getKeyForUser(username, dictId);
      await prefs.remove(key);
    } else {
      final allKeys = prefs.getKeys();
      final prefix = (username == null || username.trim().isEmpty)
          ? 'wordn_cards_guest_'
          : 'wordn_cards_${username.trim().toLowerCase()}_';
      for (final key in allKeys) {
        if (key.startsWith(prefix) || key == _defaultStorageKey) {
          await prefs.remove(key);
        }
      }
    }
  }

  /// Clears stored cards for a user and dictionary
  static Future<void> clearAll([String? username, String dictId = 'kaoyan4533']) async {
    await clearCards(username, dictId);
  }
}
