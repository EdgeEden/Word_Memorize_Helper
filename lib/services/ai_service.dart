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
    final cleanInput = userInput.trim();
    if (cleanInput.isEmpty) {
      return false;
    }

    final cleanKey = apiKey.trim();
    if (cleanKey.isEmpty) {
      debugPrint('[DeepSeek API] 未配置 API Key，跳过 AI 判定。');
      return null;
    }


    final rawBase = (baseUrl != null && baseUrl.trim().isNotEmpty)
        ? baseUrl.trim()
        : defaultBaseUrl;
    final cleanBase = rawBase.endsWith('/')
        ? rawBase.substring(0, rawBase.length - 1)
        : rawBase;

    final prompt =
        "判断'${userInput.trim()}'是否属于'${word.trim()}'的中文释义，或与'${word.trim()}'含义相似。只能回答单个汉字'是'或'否'，不要任何解释、标点或额外内容。";

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
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data =
            jsonDecode(utf8.decode(response.bodyBytes));
        final choices = data['choices'] as List<dynamic>?;
        if (choices != null && choices.isNotEmpty) {
          final first = choices.first as Map<String, dynamic>;
          final message = first['message'] as Map<String, dynamic>?;
          final content = message?['content']?.toString().trim() ?? '';
          final result = parseAiResponse(content);
          if (result == null) {
            debugPrint('[DeepSeek API Warning] AI 返回了非预期内容: "$content" (无法解析为 是/否)');
          }
          return result;
        } else {
          debugPrint('[DeepSeek API Error] 响应体 choices 为空: ${response.body}');
        }
      } else {
        String errorDetail;
        try {
          errorDetail = utf8.decode(response.bodyBytes);
        } catch (_) {
          errorDetail = response.body;
        }
        debugPrint(
          '❌ [DeepSeek API HTTP 错误]\n'
          '  端点: $endpoint\n'
          '  状态码: ${response.statusCode}\n'
          '  响应详情: $errorDetail',
        );
      }
      return null;
    } catch (e, stackTrace) {
      debugPrint(
        '❌ [DeepSeek API 请求异常]\n'
        '  端点: $endpoint\n'
        '  异常类型: ${e.runtimeType}\n'
        '  错误描述: $e\n'
        '  堆栈追踪: $stackTrace',
      );
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
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        return (success: true, message: 'DeepSeek API 验证成功，服务正常！');
      } else if (response.statusCode == 401) {
        final err = 'API Key 无效或未授权 (401)';
        debugPrint('[DeepSeek Connection Test] $err\n响应: ${response.body}');
        return (success: false, message: err);
      } else if (response.statusCode == 402) {
        final err = '账户余额不足 (402)';
        debugPrint('[DeepSeek Connection Test] $err\n响应: ${response.body}');
        return (success: false, message: err);
      } else {
        final err = '连接失败: HTTP ${response.statusCode}';
        debugPrint('[DeepSeek Connection Test] $err\n响应: ${response.body}');
        return (success: false, message: err);
      }
    } catch (e) {
      debugPrint('❌ [DeepSeek Connection Test 异常] $e');
      return (success: false, message: '网络连接超时或错误: $e');
    }
  }
}
