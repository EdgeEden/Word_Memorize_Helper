import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordn/controllers/quiz_controller.dart';
import 'package:wordn/services/ai_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
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

      // 2. Set evaluation mode to DeepSeek and save API key
      await controller.setEvalMode(EvaluationMode.deepseekAi);
      await controller.updateDeepSeekConfig(
        apiKey: 'sk-test-deepseek-key-12345',
        baseUrl: 'https://custom.deepseek.com',
      );

      expect(controller.evalMode, EvaluationMode.deepseekAi);
      expect(controller.deepseekApiKey, 'sk-test-deepseek-key-12345');
      expect(controller.deepseekBaseUrl, 'https://custom.deepseek.com');

      // 3. Simulate app restart: launch new controller
      final freshController = QuizController();
      await freshController.init();

      // 4. Verify auto-fill on startup
      expect(freshController.evalMode, EvaluationMode.deepseekAi);
      expect(freshController.deepseekApiKey, 'sk-test-deepseek-key-12345');
      expect(freshController.deepseekBaseUrl, 'https://custom.deepseek.com');
    });

    test('Gracefully falls back to local matcher when API key is empty in AI mode', () async {
      final controller = QuizController();
      await controller.init();
      await controller.setEvalMode(EvaluationMode.deepseekAi);

      if (controller.currentWord != null) {
        // Submit answer with empty key
        await controller.submitAnswer(controller.currentWord!.definition);
        expect(controller.isSubmitted, isTrue);
        expect(controller.isCorrect, isTrue);
        expect(controller.evaluationNotice, contains('未配置 DeepSeek API Key'));
      }
    });
  });
}
