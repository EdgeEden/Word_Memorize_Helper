import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/fsrs/fsrs_models.dart';
import 'api_service.dart';

class FsrsRepository {
  static const String _defaultStorageKey = 'wordn_fsrs_cards_v1';
  static const String _currentUserKey = 'wordn_current_user';
  static const String _serverUrlKey = 'wordn_server_url';

  static String _getKeyForUser(String? username) {
    if (username == null || username.trim().isEmpty) {
      return _defaultStorageKey;
    }
    return 'wordn_cards_${username.trim().toLowerCase()}';
  }

  /// Get the currently logged-in username
  static Future<String?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final user = prefs.getString(_currentUserKey);
    return (user != null && user.trim().isNotEmpty) ? user.trim().toLowerCase() : null;
  }

  /// Set the currently logged-in username
  static Future<void> setCurrentUser(String? username) async {
    final prefs = await SharedPreferences.getInstance();
    if (username == null || username.trim().isEmpty) {
      await prefs.remove(_currentUserKey);
    } else {
      await prefs.setString(_currentUserKey, username.trim().toLowerCase());
    }
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
