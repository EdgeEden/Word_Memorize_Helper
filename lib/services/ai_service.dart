import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class DeepSeekService {
  static const String defaultBaseUrl = 'https://api.deepseek.com';
  static const String defaultModel = 'deepseek-chat';

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
    String? model,
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


    final targetModel = (model != null && model.trim().isNotEmpty)
        ? model.trim()
        : defaultModel;

    final isReasoningModel =
        targetModel.toLowerCase().contains('reason') ||
        targetModel.toLowerCase().contains('r1');

    final endpoint = '$cleanBase/chat/completions';

    final Map<String, dynamic> requestPayload = {
      'model': targetModel,
      'messages': [
        {
          'role': 'system',
          'content':
              '你是一个英语词汇考官。请判断用户输入的中文释义是否符合目标英文单词的含义。只能直接回答一个汉字“是”或“否”，严禁输出任何多余解释、标点或思考过程。',
        },
        {
          'role': 'user',
          'content':
              "目标单词: '${word.trim()}', 用户中文输入: '${userInput.trim()}'。该输入是否属于该单词的正确或相近中文释义？请回答'是'或'否'。",
        },
      ],
      'max_tokens': 150,
      'stream': false,
      'thinking': {'type': 'disabled'},
      'reasoning_effort': 'none',
      'enable_thinking': false,
    };

    if (!isReasoningModel) {
      requestPayload['temperature'] = 0.0;
    }

    try {
      final uri = Uri.parse(endpoint);
      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $cleanKey',
            },
            body: jsonEncode(requestPayload),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data =
            jsonDecode(utf8.decode(response.bodyBytes));
        final choices = data['choices'] as List<dynamic>?;
        if (choices != null && choices.isNotEmpty) {
          final first = choices.first as Map<String, dynamic>;
          final message = first['message'] as Map<String, dynamic>?;
          final content = message?['content']?.toString().trim() ?? '';
          final reasoningContent =
              message?['reasoning_content']?.toString().trim() ?? '';
          final result = parseAiResponse(
            content,
            reasoningContent: reasoningContent,
          );
          if (result == null) {
            debugPrint(
              '[DeepSeek API Warning] AI 返回了非预期内容: content="$content", reasoning_content="$reasoningContent" (无法解析为 是/否)',
            );
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

  /// Fetch list of available models from OpenAI-compatible API endpoint
  static Future<List<String>> fetchAvailableModels(
    String apiKey, {
    String? baseUrl,
  }) async {
    final cleanKey = apiKey.trim();
    if (cleanKey.isEmpty) return [];

    final rawBase = (baseUrl != null && baseUrl.trim().isNotEmpty)
        ? baseUrl.trim()
        : defaultBaseUrl;
    final cleanBase = rawBase.endsWith('/')
        ? rawBase.substring(0, rawBase.length - 1)
        : rawBase;

    final endpoints = <String>[
      '$cleanBase/models',
      if (!cleanBase.endsWith('/v1')) '$cleanBase/v1/models',
    ];

    for (final endpoint in endpoints) {
      try {
        final uri = Uri.parse(endpoint);
        final response = await http.get(
          uri,
          headers: {
            'Authorization': 'Bearer $cleanKey',
          },
        ).timeout(const Duration(seconds: 6));

        if (response.statusCode == 200) {
          final Map<String, dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
          final rawData = data['data'];
          if (rawData is List) {
            final List<String> models = [];
            for (final item in rawData) {
              if (item is Map && item['id'] != null) {
                final id = item['id'].toString().trim();
                if (id.isNotEmpty && !models.contains(id)) {
                  models.add(id);
                }
              } else if (item is String && item.trim().isNotEmpty) {
                final id = item.trim();
                if (!models.contains(id)) {
                  models.add(id);
                }
              }
            }
            if (models.isNotEmpty) {
              return models;
            }
          }
        }
      } catch (e) {
        debugPrint('[DeepSeekService] 获取模型列表异常 ($endpoint): $e');
      }
    }

    return [];
  }

  /// Parses AI response text to determine true / false
  static bool? parseAiResponse(String content, {String? reasoningContent}) {
    // 1. Strip think tags like <think>...</think> if present in content
    String text = content
        .replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '')
        .trim();

    // 2. If content is empty but reasoning_content exists, use reasoning_content
    if (text.isEmpty && reasoningContent != null && reasoningContent.trim().isNotEmpty) {
      text = reasoningContent
          .replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '')
          .trim();
    }

    if (text.isEmpty) return null;

    // 3. Prioritize check on the last non-empty line
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final checkTarget = lines.isNotEmpty ? lines.last : text;

    if (checkTarget.contains('不是') || checkTarget.contains('否')) {
      return false;
    }
    if (checkTarget.contains('是') ||
        checkTarget.contains('对') ||
        checkTarget.contains('正确') ||
        checkTarget.toLowerCase().contains('true')) {
      return true;
    }

    // 4. Full text fallback scan
    if (text.contains('不是') || text.contains('否')) {
      return false;
    }
    if (text.contains('是') ||
        text.contains('对') ||
        text.contains('正确') ||
        text.toLowerCase().contains('true')) {
      return true;
    }

    return null;
  }


  /// Test DeepSeek API connection with a simple lightweight request
  static Future<({bool success, String message})> testConnection(
    String apiKey, {
    String? baseUrl,
    String? model,
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

    final targetModel = (model != null && model.trim().isNotEmpty)
        ? model.trim()
        : defaultModel;

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
              'model': targetModel,
              'messages': [
                {'role': 'user', 'content': 'hi'}
              ],
              'max_tokens': 5,
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        return (success: true, message: 'API 验证成功 ($targetModel)，服务正常！');
      } else if (response.statusCode == 401) {
        final err = 'API Key 无效或未授权 (401)';
        debugPrint('[DeepSeek Connection Test] $err\n响应: ${response.body}');
        return (success: false, message: err);
      } else if (response.statusCode == 402) {
        final err = '账户余额不足 (402)';
        debugPrint('[DeepSeek Connection Test] $err\n响应: ${response.body}');
        return (success: false, message: err);
      } else if (response.statusCode == 404) {
        final err = '模型 $targetModel 不存在 (404)';
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

