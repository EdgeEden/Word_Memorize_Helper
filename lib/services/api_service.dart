import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/fsrs/fsrs_models.dart';

class ApiService {
  static const String _defaultServer = 'http://127.0.0.1:25642';

  static String getDefaultServerUrl() {
    return _defaultServer;
  }

  /// Check server connectivity
  static Future<bool> checkHealth(String serverUrl) async {
    try {
      final uri = Uri.parse('$serverUrl/api/health');
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['status'] == 'ok';
      }
      return false;
    } catch (_) {
      return false;
    }
  }


  /// Login or register a user on the server and fetch their cloud cards
  static Future<Map<String, dynamic>?> loginOrRegister(
    String username, {
    required String serverUrl,
    String dictId = 'kaoyan4533',
  }) async {
    try {
      final uri = Uri.parse('$serverUrl/api/login');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'username': username.trim().toLowerCase(),
              'dict_id': dictId.trim().toLowerCase(),
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
        final Map<String, dynamic> rawCards = data['cards'] as Map<String, dynamic>? ?? {};
        final Map<String, FsrsCard> cards = {};
        for (final entry in rawCards.entries) {
          try {
            cards[entry.key] = FsrsCard.fromJson(entry.value as Map<String, dynamic>);
          } catch (e) {
            debugPrint('Failed to parse card ${entry.key}: $e');
          }
        }
        return {
          'id': data['id'],
          'username': data['username'],
          'is_new': data['is_new'] ?? false,
          'cards': cards,
        };
      }
      return null;
    } catch (e) {
      debugPrint('ApiService.loginOrRegister error: $e');
      return null;
    }
  }

  /// Fetch user cards from the server
  static Future<Map<String, FsrsCard>?> fetchCards(
    String username, {
    required String serverUrl,
    String dictId = 'kaoyan4533',
  }) async {
    try {
      final uri = Uri.parse(
        '$serverUrl/api/cards?username=${Uri.encodeComponent(username.trim().toLowerCase())}&dict_id=${Uri.encodeComponent(dictId.trim().toLowerCase())}',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
        final Map<String, dynamic> rawCards = data['cards'] as Map<String, dynamic>? ?? {};
        final Map<String, FsrsCard> cards = {};
        for (final entry in rawCards.entries) {
          try {
            cards[entry.key] = FsrsCard.fromJson(entry.value as Map<String, dynamic>);
          } catch (e) {
            debugPrint('Failed to parse card ${entry.key}: $e');
          }
        }
        return cards;
      }
      return null;
    } catch (e) {
      debugPrint('ApiService.fetchCards error: $e');
      return null;
    }
  }

  /// Push/Sync all latest cards to the server
  static Future<bool> syncCards(
    String username,
    Map<String, FsrsCard> cards, {
    required String serverUrl,
    String dictId = 'kaoyan4533',
  }) async {
    try {
      final uri = Uri.parse('$serverUrl/api/cards/sync');
      final Map<String, dynamic> payloadCards = {};
      cards.forEach((key, value) {
        payloadCards[key] = value.toJson();
      });

      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'username': username.trim().toLowerCase(),
              'dict_id': dictId.trim().toLowerCase(),
              'cards': payloadCards,
            }),
          )
          .timeout(const Duration(seconds: 5));


      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['status'] == 'ok';
      }
      return false;
    } catch (e) {
      debugPrint('ApiService.syncCards error: $e');
      return false;
    }
  }

  /// Delete cards for a user from the server (either for a specific dict or all dicts)
  static Future<bool> deleteCards(
    String username, {
    String? dictId,
    required String serverUrl,
  }) async {
    try {
      final queryParams = {'username': username.trim().toLowerCase()};
      if (dictId != null && dictId.trim().isNotEmpty && dictId.trim().toLowerCase() != 'all') {
        queryParams['dict_id'] = dictId.trim().toLowerCase();
      }
      final uri = Uri.parse('$serverUrl/api/cards').replace(queryParameters: queryParams);
      final response = await http.delete(uri).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('ApiService.deleteCards error: $e');
      return false;
    }
  }
}
