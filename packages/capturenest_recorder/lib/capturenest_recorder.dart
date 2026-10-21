import 'package:flutter/services.dart';

enum CaptureQuality { standard, high, ultra }

class RecordingOptions {
  const RecordingOptions({
    required this.microphone,
    required this.deviceAudio,
    required this.frontCamera,
    required this.quality,
  });

  final bool microphone;
  final bool deviceAudio;
  final bool frontCamera;
  final CaptureQuality quality;

  Map<String, Object> toMap() => <String, Object>{
        'microphone': microphone,
        'deviceAudio': deviceAudio,
        'frontCamera': frontCamera,
        'quality': quality.name,
      };
}

class CaptureNestRecorder {
  CaptureNestRecorder._();

  static const MethodChannel _channel =
      MethodChannel('com.thatsbikublab.capturenest/recorder');

  static Future<void> start(RecordingOptions options) async {
    await _channel.invokeMethod<void>('start', options.toMap());
  }

  static Future<String> stop() async {
    final path = await _channel.invokeMethod<String>('stop');
    if (path == null || path.isEmpty) {
      throw StateError('The recording could not be saved.');
    }
    return path;
  }

  static Future<void> pause() => _channel.invokeMethod<void>('pause');

  static Future<void> resume() => _channel.invokeMethod<void>('resume');

  static Future<String> trim({
    required String inputPath,
    required Duration from,
    required Duration to,
  }) async {
    final path = await _channel.invokeMethod<String>('trim', <String, Object>{
      'inputPath': inputPath,
      'fromMs': from.inMilliseconds,
      'toMs': to.inMilliseconds,
    });
    if (path == null || path.isEmpty) {
      throw StateError('The trimmed recording could not be exported.');
    }
    return path;
  }

  static Future<void> saveToGallery(String path) =>
      _channel.invokeMethod<void>('saveToGallery', <String, String>{'path': path});
}


