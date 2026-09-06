import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordn/controllers/quiz_controller.dart';
import 'package:wordn/services/audio_service.dart';
import 'package:wordn/services/fsrs_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AudioSourceType & AutoPlayMode Model Tests', () {
    test('AudioSourceType correctly parses string keys and falls back to youdao', () {
      expect(AudioSourceType.fromString('youdao'), equals(AudioSourceType.youdao));
      expect(AudioSourceType.fromString('freeDictionary'), equals(AudioSourceType.freeDictionary));
      expect(AudioSourceType.fromString('FREEDICTIONARY'), equals(AudioSourceType.freeDictionary));
      expect(AudioSourceType.fromString('unknown'), equals(AudioSourceType.youdao));
      expect(AudioSourceType.fromString(null), equals(AudioSourceType.youdao));
    });

    test('AutoPlayMode correctly parses all 4 modes and falls back to never', () {
      expect(AutoPlayMode.fromString('never'), equals(AutoPlayMode.never));
      expect(AutoPlayMode.fromString('questionOnly'), equals(AutoPlayMode.questionOnly));
      expect(AutoPlayMode.fromString('answerOnly'), equals(AutoPlayMode.answerOnly));
      expect(AutoPlayMode.fromString('always'), equals(AutoPlayMode.always));
      expect(AutoPlayMode.fromString('ALWAYS'), equals(AutoPlayMode.always));
      expect(AutoPlayMode.fromString('invalid'), equals(AutoPlayMode.never));
      expect(AutoPlayMode.fromString(null), equals(AutoPlayMode.never));
    });
  });

  group('AudioService URL Generation & Free Dictionary JSON Parsing Tests', () {
    test('getYoudaoAudioUrl generates valid streaming URLs', () {
      final defaultUrl = AudioService.getYoudaoAudioUrl('compliment');
      expect(defaultUrl, equals('http://dict.youdao.com/dictvoice?type=0&audio=compliment'));

      final ukUrl = AudioService.getYoudaoAudioUrl('good morning', type: 1);
      expect(ukUrl, equals('http://dict.youdao.com/dictvoice?type=1&audio=good%20morning'));
    });

    test('inferMimeType identifies audio formats accurately', () {
      expect(AudioService.inferMimeType('http://dict.youdao.com/dictvoice?type=0&audio=test'), equals('audio/mpeg'));
      expect(AudioService.inferMimeType('https://example.com/audio.mp3'), equals('audio/mpeg'));
      expect(AudioService.inferMimeType('https://example.com/audio.wav'), equals('audio/wav'));
      expect(AudioService.inferMimeType('https://example.com/audio.ogg'), equals('audio/ogg'));
      expect(AudioService.inferMimeType('https://example.com/audio.m4a'), equals('audio/aac'));
    });

    test('fetchFreeDictionaryAudioUrl parses phonetics audio and prioritizes US pronunciation', () async {
      final mockResponse = jsonEncode([
        {
          'word': 'compliment',
          'phonetics': [
            {'text': "/'kɒmplɪmənt/", 'audio': ''},
            {'text': "/'kɒmplɪmənt/", 'audio': 'https://api.dictionaryapi.dev/media/pronunciations/en/compliment-uk.mp3'},
            {'text': "/'kɑːmplɪmənt/", 'audio': 'https://api.dictionaryapi.dev/media/pronunciations/en/compliment-us.mp3'}
          ]
        }
      ]);

      final mockClient = MockClient((request) async {
        return http.Response(mockResponse, 200, headers: {'content-type': 'application/json; charset=utf-8'});
      });

      final audioUrl = await AudioService.fetchFreeDictionaryAudioUrl('compliment', client: mockClient);
      expect(audioUrl, equals('https://api.dictionaryapi.dev/media/pronunciations/en/compliment-us.mp3'));
    });

    test('fetchFreeDictionaryAudioUrl handles protocol-relative URLs', () async {
      final mockResponse = jsonEncode([
        {
          'word': 'test',
          'phonetics': [
            {'audio': '//ssl.gstatic.com/dictionary/static/sounds/20200429/test--_us_1.mp3'}
          ]
        }
      ]);

      final mockClient = MockClient((request) async {
        return http.Response(mockResponse, 200);
      });

      final audioUrl = await AudioService.fetchFreeDictionaryAudioUrl('test', client: mockClient);
      expect(audioUrl, equals('https://ssl.gstatic.com/dictionary/static/sounds/20200429/test--_us_1.mp3'));
    });

    test('fetchFreeDictionaryAudioUrl returns null on 404 or empty audio list', () async {
      final mockClient404 = MockClient((request) async {
        return http.Response('{"title": "No Definitions Found"}', 404);
      });

      final notFoundUrl = await AudioService.fetchFreeDictionaryAudioUrl('nonexistentword123', client: mockClient404);
      expect(notFoundUrl, isNull);

      final emptyWordUrl = await AudioService.fetchFreeDictionaryAudioUrl('   ');
      expect(emptyWordUrl, isNull);
    });
  });

  group('FsrsRepository Audio Settings Persistence Tests', () {
    test('Persists and loads audioSource and autoPlayMode', () async {
      expect(await FsrsRepository.getAudioSource(), equals('youdao'));
      expect(await FsrsRepository.getAutoPlayMode(), equals('never'));

      await FsrsRepository.setAudioSource('freeDictionary');
      await FsrsRepository.setAutoPlayMode('always');

      expect(await FsrsRepository.getAudioSource(), equals('freeDictionary'));
      expect(await FsrsRepository.getAutoPlayMode(), equals('always'));
    });
  });

  group('QuizController Audio Integration Tests', () {
    test('QuizController loads persisted audio config and updates config', () async {
      await FsrsRepository.setAudioSource('freeDictionary');
      await FsrsRepository.setAutoPlayMode('questionOnly');

      final controller = QuizController();
      await controller.init();

      expect(controller.audioSource, equals(AudioSourceType.freeDictionary));
      expect(controller.autoPlayMode, equals(AutoPlayMode.questionOnly));

      // Update to Youdao & always
      await controller.updateAudioConfig(
        source: AudioSourceType.youdao,
        autoPlay: AutoPlayMode.always,
      );

      expect(controller.audioSource, equals(AudioSourceType.youdao));
      expect(controller.autoPlayMode, equals(AutoPlayMode.always));
      expect(await FsrsRepository.getAudioSource(), equals('youdao'));
      expect(await FsrsRepository.getAutoPlayMode(), equals('always'));

      controller.dispose();
    });
  });
}
