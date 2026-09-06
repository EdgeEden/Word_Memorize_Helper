import 'dart:async';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

class WebAudioPlayer {
  static bool get isSupported => true;
  static web.HTMLAudioElement? _audioElement;
  static StreamSubscription? _endedSubscription;
  static StreamSubscription? _errorSubscription;

  static Future<bool> play(
    String url, {
    VoidCallback? onEnded,
    VoidCallback? onError,
  }) async {
    try {
      stop();

      // On Web browsers, convert http:// to https:// to prevent Mixed Content security blocking
      var effectiveUrl = url.trim();
      if (effectiveUrl.startsWith('http://dict.youdao.com')) {
        effectiveUrl = effectiveUrl.replaceFirst('http://', 'https://');
      } else if (effectiveUrl.startsWith('http://')) {
        effectiveUrl = effectiveUrl.replaceFirst('http://', 'https://');
      }

      final audio = _audioElement = web.HTMLAudioElement();
      audio.preload = 'auto';
      // DO NOT set audio.crossOrigin = 'anonymous' so the browser can play
      // cross-origin audio streams without requiring CORS Access-Control headers
      audio.src = effectiveUrl;

      _endedSubscription = audio.onEnded.listen((_) {
        onEnded?.call();
      });

      _errorSubscription = audio.onError.listen((_) {
        debugPrint('[WebAudioPlayer] Web Audio playback error for $effectiveUrl');
        onError?.call();
      });

      await audio.play().toDart;
      return true;
    } catch (e) {
      debugPrint('[WebAudioPlayer] HTMLAudioElement play failed: $e');
      onError?.call();
      return false;
    }
  }

  static void stop() {
    try {
      _endedSubscription?.cancel();
      _endedSubscription = null;
      _errorSubscription?.cancel();
      _errorSubscription = null;
      if (_audioElement != null) {
        _audioElement!.pause();
        _audioElement!.currentTime = 0;
        _audioElement!.src = '';
        _audioElement = null;
      }
    } catch (_) {}
  }
}
