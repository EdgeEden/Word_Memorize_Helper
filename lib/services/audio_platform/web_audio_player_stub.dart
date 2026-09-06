import 'package:flutter/foundation.dart';

class WebAudioPlayer {
  static bool get isSupported => false;

  static Future<bool> play(
    String url, {
    VoidCallback? onEnded,
    VoidCallback? onError,
  }) async {
    return false;
  }

  static void stop() {}
}
