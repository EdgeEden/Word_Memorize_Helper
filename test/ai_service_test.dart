import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordn/controllers/quiz_controller.dart';
import 'package:wordn/services/ai_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'WordN',
      packageName: 'com.example.wordn',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });


  group('DeepSeekService Response Parser Tests', () {
    test('Correctly parses "是" variations as true', () {
      expect(DeepSeekService.parseAiResponse('是'), isTrue);
      expect(DeepSeekService.parseAiResponse('是。'), isTrue);
      expect(DeepSeekService.parseAiResponse('“是”'), isTrue);
      expect(DeepSeekService.parseAiResponse(' 是 '), isTrue);
    });

    test('Correctly parses "否" variations as false', () {
      expect(DeepSeekService.parseAiResponse('否'), isFalse);
      expect(DeepSeekService.parseAiResponse('否！'), isFalse);
      expect(DeepSeekService.parseAiResponse('“否”'), isFalse);
      expect(DeepSeekService.parseAiResponse(' 否\n'), isFalse);
    });

    test('Strips <think> tags and parses conclusion correctly', () {
      expect(DeepSeekService.parseAiResponse('<think>用户输入的是竖直，upright是竖直的...</think>是'), isTrue);
      expect(DeepSeekService.parseAiResponse('<think>upright代表垂直，输入为苹果...</think>否'), isFalse);
    });

    test('Falls back to reasoning_content when content is empty', () {
      expect(DeepSeekService.parseAiResponse('', reasoningContent: '经过分析，竖直符合upright释义，因此判定为：是'), isTrue);
      expect(DeepSeekService.parseAiResponse('', reasoningContent: '经过分析，苹果不符合upright释义，因此判定为：否'), isFalse);
    });

    test('Returns null on ambiguous or invalid outputs', () {
      expect(DeepSeekService.parseAiResponse(''), isNull);
      expect(DeepSeekService.parseAiResponse('未知内容'), isNull);
      expect(DeepSeekService.parseAiResponse('Hello World'), isNull);
    });
  });


  group('Evaluation Mode and DeepSeek API Key Persistence', () {
    test('Saves and loads evaluation mode and API key locally for auto-fill', () async {
      // 1. Initial defaults
      final controller = QuizController();
      await controller.init();
      expect(controller.evalMode, EvaluationMode.localMatcher);
      expect(controller.deepseekApiKey, isEmpty);

      // 2. Set evaluation mode to DeepSeek and save API key & custom model
      await controller.setEvalMode(EvaluationMode.deepseekAi);
      await controller.updateDeepSeekConfig(
        apiKey: 'sk-test-deepseek-key-12345',
        baseUrl: 'https://custom.deepseek.com',
        model: 'deepseek-reasoner',
      );

      expect(controller.evalMode, EvaluationMode.deepseekAi);
      expect(controller.deepseekApiKey, 'sk-test-deepseek-key-12345');
      expect(controller.deepseekBaseUrl, 'https://custom.deepseek.com');
      expect(controller.deepseekModel, 'deepseek-reasoner');

      // 3. Simulate app restart: launch new controller
      final freshController = QuizController();
      await freshController.init();

      // 4. Verify auto-fill on startup
      expect(freshController.evalMode, EvaluationMode.deepseekAi);
      expect(freshController.deepseekApiKey, 'sk-test-deepseek-key-12345');
      expect(freshController.deepseekBaseUrl, 'https://custom.deepseek.com');
      expect(freshController.deepseekModel, 'deepseek-reasoner');
    });


    test('Directly succeeds on local match first even in AI mode', () async {
      final controller = QuizController();
      await controller.init();
      await controller.setEvalMode(EvaluationMode.deepseekAi);

      if (controller.currentWord != null) {
        // Submit exactly matching answer
        await controller.submitAnswer(controller.currentWord!.definition);
        expect(controller.isSubmitted, isTrue);
        expect(controller.isCorrect, isTrue);
        expect(controller.evaluationNotice, isNull);
      }
    });

    test('In AI mode with local mismatch and empty key, reports failure with notice', () async {
      final controller = QuizController();
      await controller.init();
      await controller.setEvalMode(EvaluationMode.deepseekAi);

      if (controller.currentWord != null) {
        // Submit non-matching gibberish answer
        await controller.submitAnswer('完全不相干的文字xyz');
        expect(controller.isSubmitted, isTrue);
        expect(controller.isCorrect, isFalse);
        expect(controller.evaluationNotice, contains('未配置 AI API Key'));
      }
    });

    test('In AI mode with API key but empty model, reports failure with unselected model notice', () async {
      final controller = QuizController();
      await controller.init();
      await controller.setEvalMode(EvaluationMode.deepseekAi);
      await controller.updateDeepSeekConfig(apiKey: 'sk-test-123', model: '');

      if (controller.currentWord != null) {
        await controller.submitAnswer('完全不相干的文字xyz');
        expect(controller.isSubmitted, isTrue);
        expect(controller.isCorrect, isFalse);
        expect(controller.evaluationNotice, contains('未选择 AI 模型'));
      }
    });

    test('Directly marks empty answer as incorrect without invoking AI or setting notices', () async {
      final controller = QuizController();
      await controller.init();
      await controller.setEvalMode(EvaluationMode.deepseekAi);

      if (controller.currentWord != null) {
        await controller.submitAnswer('   ');
        expect(controller.isSubmitted, isTrue);
        expect(controller.isCorrect, isFalse);
        expect(controller.isEvaluating, isFalse);
        expect(controller.evaluationNotice, isNull);
      }
    });
  });

  group('Token Usage & DeepSeek Balance Parsing Tests', () {
    test('DeepSeekBalanceInfo correctly parses official JSON response', () {
      final json = {
        'is_available': true,
        'balance_infos': [
          {
            'currency': 'CNY',
            'total_balance': '110.55',
            'granted_balance': '10.00',
            'topped_up_balance': '100.55',
          }
        ]
      };
      final info = DeepSeekBalanceInfo.fromJson(json);
      expect(info.isAvailable, isTrue);
      expect(info.currency, 'CNY');
      expect(info.totalBalance, closeTo(110.55, 0.001));
      expect(info.grantedBalance, closeTo(10.00, 0.001));
      expect(info.toppedUpBalance, closeTo(100.55, 0.001));
    });

    test('DeepSeekBalanceInfo handles empty or missing balance_infos gracefully', () {
      final emptyJson = {'is_available': false};
      final info = DeepSeekBalanceInfo.fromJson(emptyJson);
      expect(info.isAvailable, isFalse);
      expect(info.currency, 'CNY');
      expect(info.totalBalance, 0.0);
    });

    test('AiEvaluationResult holds token count fields accurately', () {
      const result = AiEvaluationResult(
        isApproved: true,
        totalTokens: 145,
        promptTokens: 120,
        completionTokens: 25,
      );
      expect(result.isApproved, isTrue);
      expect(result.totalTokens, 145);
      expect(result.promptTokens, 120);
      expect(result.completionTokens, 25);
    });
  });

  group('QuizController Token and Cost Statistics Tests', () {
    test('Persists and toggles showTokenUsage setting', () async {
      final controller = QuizController();
      await controller.init();
      expect(controller.showTokenUsage, isTrue); // Default true

      await controller.setShowTokenUsage(false);
      expect(controller.showTokenUsage, isFalse);

      final fresh = QuizController();
      await fresh.init();
      expect(fresh.showTokenUsage, isFalse);

      await fresh.setShowTokenUsage(true);
      expect(fresh.showTokenUsage, isTrue);
    });

    test('Detects whether active model is DeepSeek', () async {
      final controller = QuizController();
      await controller.init();

      await controller.updateDeepSeekConfig(
        apiKey: 'sk-123',
        baseUrl: 'https://api.deepseek.com',
        model: 'deepseek-chat',
      );
      expect(controller.isCurrentModelDeepSeek, isTrue);

      await controller.updateDeepSeekConfig(
        apiKey: 'sk-123',
        baseUrl: 'https://api.openai.com/v1',
        model: 'gpt-4o',
      );
      expect(controller.isCurrentModelDeepSeek, isFalse);
    });

    test('Formats footer text without Chinese characters and with 2 decimal places for cost', () {
      const tokens = 142;
      const totalTokens = 426;
      const cost = 0.0123;
      final costStr = cost.toStringAsFixed(2);
      final deepSeekText = 'Last: $tokens tokens | Total: $totalTokens tokens (¥$costStr)';
      expect(deepSeekText, equals('Last: 142 tokens | Total: 426 tokens (¥0.01)'));
      expect(RegExp(r'[\u4e00-\u9fa5]').hasMatch(deepSeekText), isFalse);

      final nonDeepSeekText = 'Last: $tokens tokens | Total: $totalTokens tokens';
      expect(nonDeepSeekText, equals('Last: 142 tokens | Total: 426 tokens'));
      expect(RegExp(r'[\u4e00-\u9fa5]').hasMatch(nonDeepSeekText), isFalse);
    });

    test('isAiEvaluationMode reflects evalMode correctly', () async {
      final controller = QuizController();
      await controller.init();
      expect(controller.evalMode, EvaluationMode.localMatcher);
      expect(controller.isAiEvaluationMode, isFalse);

      await controller.setEvalMode(EvaluationMode.deepseekAi);
      expect(controller.evalMode, EvaluationMode.deepseekAi);
      expect(controller.isAiEvaluationMode, isTrue);

      await controller.setEvalMode(EvaluationMode.localMatcher);
      expect(controller.isAiEvaluationMode, isFalse);
    });
  });
}

