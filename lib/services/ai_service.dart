import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class DeepSeekService {
  static const String defaultBaseUrl = 'https://api.deepseek.com';

  /// Evaluate user's Chinese definition against the target English word via DeepSeek API
  /// Returns:
  /// - `true`: Answer is correct / approved by AI
  /// - `false`: Answer is incorrect / rejected by AI
  /// - `null`: Network error, invalid key, or unreachable API (caller should fallback to local)
  static Future<bool?> evaluateAnswer({
    required String word,
    required String userInput,
    required String apiKey,
    String? baseUrl,
  }) async {
    final cleanKey = apiKey.trim();
    if (cleanKey.isEmpty) {
      debugPrint('DeepSeekService: API Key is empty.');
      return null;
    }

    final rawBase = (baseUrl != null && baseUrl.trim().isNotEmpty)
        ? baseUrl.trim()
        : defaultBaseUrl;
    final cleanBase = rawBase.endsWith('/')
        ? rawBase.substring(0, rawBase.length - 1)
        : rawBase;

    final prompt =
        "判断'${userInput.trim()}'是否与'${word.trim()}'意思相同，只能回答单个汉字'是'或'否'，不要任何解释、标点或额外内容。";

    final endpoint = '$cleanBase/chat/completions';

    try {
      final uri = Uri.parse(endpoint);
      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $cleanKey',
            },
            body: jsonEncode({
              'model': 'deepseek-chat',
              'messages': [
                {'role': 'user', 'content': prompt}
              ],
              'temperature': 0.0,
              'max_tokens': 10,
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data =
            jsonDecode(utf8.decode(response.bodyBytes));
        final choices = data['choices'] as List<dynamic>?;
        if (choices != null && choices.isNotEmpty) {
          final first = choices.first as Map<String, dynamic>;
          final message = first['message'] as Map<String, dynamic>?;
          final content = message?['content']?.toString().trim() ?? '';
          return parseAiResponse(content);
        }
      } else {
        debugPrint(
            'DeepSeek API error: HTTP ${response.statusCode} - ${response.body}');
      }
      return null;
    } catch (e) {
      debugPrint('DeepSeekService evaluateAnswer exception: $e');
      return null;
    }
  }

  /// Parses AI response text to determine true / false
  static bool? parseAiResponse(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return null;

    if (trimmed.contains('不是') || trimmed.contains('否')) {
      return false;
    }
    if (trimmed.contains('是')) {
      return true;
    }
    return null;
  }

  /// Test DeepSeek API connection with a simple lightweight request
  static Future<({bool success, String message})> testConnection(
    String apiKey, {
    String? baseUrl,
  }) async {
    final cleanKey = apiKey.trim();
    if (cleanKey.isEmpty) {
      return (success: false, message: '请输入 API Key');
    }

    final rawBase = (baseUrl != null && baseUrl.trim().isNotEmpty)
        ? baseUrl.trim()
        : defaultBaseUrl;
    final cleanBase = rawBase.endsWith('/')
        ? rawBase.substring(0, rawBase.length - 1)
        : rawBase;

    final endpoint = '$cleanBase/chat/completions';

    try {
      final uri = Uri.parse(endpoint);
      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $cleanKey',
            },
            body: jsonEncode({
              'model': 'deepseek-chat',
              'messages': [
                {'role': 'user', 'content': 'hi'}
              ],
              'max_tokens': 5,
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return (success: true, message: 'DeepSeek API 验证成功，服务正常！');
      } else if (response.statusCode == 401) {
        return (success: false, message: 'API Key 无效或未授权 (401)');
      } else if (response.statusCode == 402) {
        return (success: false, message: '账户余额不足 (402)');
      } else {
        return (
          success: false,
          message: '连接失败: HTTP ${response.statusCode}'
        );
      }
    } catch (e) {
      return (success: false, message: '网络连接超时或错误: $e');
    }
  }
}

