import 'dart:async';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:wordn/services/audio_platform/web_audio_player.dart';

/// Supported pronunciation audio sources
enum AudioSourceType {
  youdao('youdao', '有道词典 API (极速稳定)', '直接流媒体音频，响应迅速覆盖全'),
  freeDictionary('freeDictionary', 'Free Dictionary API (国际词典)', '国际公开词典真人发音，若无则自动降级有道');

  final String key;
  final String label;
  final String description;

  const AudioSourceType(this.key, this.label, this.description);

  static AudioSourceType fromString(String? key) {
    if (key == null) return AudioSourceType.youdao;
    return AudioSourceType.values.firstWhere(
      (e) => e.key.toLowerCase() == key.toLowerCase().trim(),
      orElse: () => AudioSourceType.youdao,
    );
  }
}

/// Auto-play strategy for pronunciation
enum AutoPlayMode {
  never('never', '不自动播放', '仅手动点击音标旁按钮时播放'),
  questionOnly('questionOnly', '仅提问页播放', '呈现新题目单词时自动播放读音'),
  answerOnly('answerOnly', '仅答案页播放', '提交答案、释义展开时自动播放读音'),
  always('always', '总是自动播放', '提问页与答案页均自动播放读音');

  final String key;
  final String label;
  final String description;

  const AutoPlayMode(this.key, this.label, this.description);

  static AutoPlayMode fromString(String? key) {
    if (key == null) return AutoPlayMode.never;
    return AutoPlayMode.values.firstWhere(
      (e) => e.key.toLowerCase() == key.toLowerCase().trim(),
      orElse: () => AutoPlayMode.never,
    );
  }
}

/// Core audio playback service for English word pronunciation
class AudioService {
  static AudioPlayer? _player;
  static bool _isPlaying = false;
  static String? _currentPlayingWord;
  static StreamSubscription? _playerStateSubscription;

  /// Whether an audio track is currently playing
  static bool get isPlaying => _isPlaying;

  /// The word currently playing or loading
  static String? get currentPlayingWord => _currentPlayingWord;

  /// Generate Youdao pronunciation stream URL
  /// [type]: 0 for standard/US (美音), 1 for UK (英音), 2 for US (美音)
  static String getYoudaoAudioUrl(String word, {int type = 0}) {
    final cleanWord = word.trim().toLowerCase();
    return 'http://dict.youdao.com/dictvoice?type=$type&audio=${Uri.encodeComponent(cleanWord)}';
  }

  /// Infer MIME type based on audio URL extension (defaults to audio/mpeg)
  static String inferMimeType(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('.wav')) return 'audio/wav';
    if (lower.contains('.ogg')) return 'audio/ogg';
    if (lower.contains('.m4a') || lower.contains('.aac')) return 'audio/aac';
    return 'audio/mpeg';
  }

  /// Query Free Dictionary API for audio pronunciation URL
  static Future<String?> fetchFreeDictionaryAudioUrl(
    String word, {
    http.Client? client,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final cleanWord = word.trim().toLowerCase();
    if (cleanWord.isEmpty) return null;

    final httpClient = client ?? http.Client();
    final shouldCloseClient = client == null;

    try {
      final uri = Uri.parse('https://api.dictionaryapi.dev/api/v2/entries/en/${Uri.encodeComponent(cleanWord)}');
      final response = await httpClient.get(uri).timeout(timeout);

      if (response.statusCode == 200) {
        final dynamic data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data is List && data.isNotEmpty) {
          final List<String> audioUrls = [];
          for (final entry in data) {
            if (entry is Map<String, dynamic>) {
              final phonetics = entry['phonetics'];
              if (phonetics is List) {
                for (final p in phonetics) {
                  if (p is Map<String, dynamic>) {
                    final audio = p['audio'] as String?;
                    if (audio != null && audio.trim().isNotEmpty) {
                      final audioTrimmed = audio.trim();
                      // Normalise protocol-relative URLs (e.g. //ssl.gstatic.com/...)
                      if (audioTrimmed.startsWith('//')) {
                        audioUrls.add('https:$audioTrimmed');
                      } else if (audioTrimmed.startsWith('http://') || audioTrimmed.startsWith('https://')) {
                        audioUrls.add(audioTrimmed);
                      }
                    }
                  }
                }
              }
            }
          }

          if (audioUrls.isNotEmpty) {
            // Prefer US pronunciation if available, otherwise return first valid audio URL
            final usAudio = audioUrls.firstWhere(
              (url) => url.toLowerCase().contains('-us.') || url.toLowerCase().contains('/us.'),
              orElse: () => audioUrls.first,
            );
            return usAudio;
          }
        }
      }
      return null;
    } catch (e) {
      debugPrint('[AudioService] Free Dictionary API fetch failed for "$word": $e');
      return null;
    } finally {
      if (shouldCloseClient) {
        httpClient.close();
      }
    }
  }

  /// Initialize AudioPlayer instance with state listener
  static AudioPlayer _ensurePlayer(VoidCallback? onStateChanged) {
    if (_player == null) {
      _player = AudioPlayer();
      _playerStateSubscription = _player!.onPlayerStateChanged.listen((state) {
        final playing = state == PlayerState.playing;
        if (_isPlaying != playing) {
          _isPlaying = playing;
          if (!playing) {
            _currentPlayingWord = null;
          }
          if (onStateChanged != null) {
            onStateChanged();
          }
        }
      });
    }
    return _player!;
  }

  /// Play pronunciation of the given English word
  static Future<bool> playWord(
    String word, {
    AudioSourceType sourceType = AudioSourceType.youdao,
    VoidCallback? onStateChanged,
    http.Client? httpClient,
  }) async {
    final cleanWord = word.trim().toLowerCase();
    if (cleanWord.isEmpty) return false;

    _currentPlayingWord = cleanWord;
    _isPlaying = true;
    if (onStateChanged != null) onStateChanged();

    try {
      String? audioUrl;
      if (sourceType == AudioSourceType.freeDictionary) {
        // Attempt Free Dictionary API first
        audioUrl = await fetchFreeDictionaryAudioUrl(cleanWord, client: httpClient);
        // Graceful fallback to Youdao if Free Dictionary has no audio or timed out
        audioUrl ??= getYoudaoAudioUrl(cleanWord);
      } else {
        // Direct Youdao voice stream
        audioUrl = getYoudaoAudioUrl(cleanWord);
      }

      if (kIsWeb) {
        final success = await WebAudioPlayer.play(
          audioUrl,
          onEnded: () {
            _isPlaying = false;
            _currentPlayingWord = null;
            if (onStateChanged != null) onStateChanged();
          },
          onError: () {
            _isPlaying = false;
            _currentPlayingWord = null;
            if (onStateChanged != null) onStateChanged();
          },
        );
        if (!success) {
          _isPlaying = false;
          _currentPlayingWord = null;
          if (onStateChanged != null) onStateChanged();
          return false;
        }
        return true;
      } else {
        final player = _ensurePlayer(onStateChanged);
        await player.stop();
        final mimeType = inferMimeType(audioUrl);
        await player.play(UrlSource(audioUrl, mimeType: mimeType));
        return true;
      }
    } catch (e) {
      debugPrint('[AudioService] Failed to play pronunciation for "$word": $e');
      _isPlaying = false;
      _currentPlayingWord = null;
      if (onStateChanged != null) onStateChanged();
      return false;
    }
  }

  /// Stop current playback immediately
  static Future<void> stop({VoidCallback? onStateChanged}) async {
    try {
      if (kIsWeb) {
        WebAudioPlayer.stop();
      } else {
        await _player?.stop();
      }
    } catch (_) {}
    _isPlaying = false;
    _currentPlayingWord = null;
    if (onStateChanged != null) onStateChanged();
  }

  /// Dispose player and release resources
  static Future<void> dispose() async {
    try {
      if (kIsWeb) {
        WebAudioPlayer.stop();
      }
      await _playerStateSubscription?.cancel();
      _playerStateSubscription = null;
      await _player?.dispose();
      _player = null;
    } catch (_) {}
    _isPlaying = false;
    _currentPlayingWord = null;
  }
}