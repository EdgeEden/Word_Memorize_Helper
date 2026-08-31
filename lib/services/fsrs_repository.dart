import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/fsrs/fsrs_models.dart';
import 'ai_service.dart';
import 'api_service.dart';

class FsrsRepository {
  static const String _defaultStorageKey = 'wordn_fsrs_cards_v1';
  static const String _currentUserKey = 'wordn_current_user';
  static const String _userHistoryKey = 'wordn_user_history_list';
  static const String _serverUrlKey = 'wordn_server_url';

  // Evaluation & Settings Keys
  static const String _evalModeKey = 'wordn_eval_mode';
  static const String _deepseekApiKey = 'wordn_deepseek_api_key';
  static const String _deepseekBaseUrlKey = 'wordn_deepseek_base_url';
  static const String _deepseekModelKey = 'wordn_deepseek_model';
  static const String _themeModeKey = 'wordn_theme_mode';


  static String _getKeyForUser(String? username) {
    if (username == null || username.trim().isEmpty) {
      return _defaultStorageKey;
    }
    return 'wordn_cards_${username.trim().toLowerCase()}';
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

  /// Loads all stored FSRS cards from local storage for the specified user
  static Future<Map<String, FsrsCard>> loadCards([String? username]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getKeyForUser(username);
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return {};

      final Map<String, dynamic> decoded = jsonDecode(raw) as Map<String, dynamic>;
      final Map<String, FsrsCard> result = {};

      decoded.forEach((word, value) {
        if (value is Map<String, dynamic>) {
          result[word] = FsrsCard.fromJson(value);
        }
      });

      return result;
    } catch (e) {
      // ignore: avoid_print
      print('Failed to load FSRS cards from storage: $e');
      return {};
    }
  }

  /// Persists all FSRS cards to local storage for the specified user
  static Future<void> saveCards(Map<String, FsrsCard> cards, [String? username]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getKeyForUser(username);
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

  /// Clears stored cards for a user
  static Future<void> clearAll([String? username]) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getKeyForUser(username);
    await prefs.remove(key);
  }
}
