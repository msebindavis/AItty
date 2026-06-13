import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Thin wrapper around [stt.SpeechToText] for command-bar dictation.
class SpeechDictation {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _initialized = false;
  bool listening = false;

  Future<bool> initialize() async {
    if (_initialized) return true;
    _initialized = await _speech.initialize(
      onError: (_) => listening = false,
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          listening = false;
        }
      },
    );
    return _initialized;
  }

  Future<void> toggle({
    required void Function(String text) onResult,
    required void Function(String message) onError,
  }) async {
    if (!_initialized) {
      final ok = await initialize();
      if (!ok) {
        onError('Speech recognition is not available on this device.');
        return;
      }
    }

    if (listening) {
      await _speech.stop();
      listening = false;
      return;
    }

    final hasPermission = await _speech.hasPermission;
    if (!hasPermission) {
      onError('Microphone permission is required for voice input.');
      return;
    }

    listening = true;
    await _speech.listen(
      onResult: (result) {
        final words = result.recognizedWords.trim();
        if (words.isNotEmpty) onResult(words);
        if (result.finalResult) listening = false;
      },
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        cancelOnError: true,
        partialResults: true,
      ),
    );
  }

  Future<void> stop() async {
    if (!listening) return;
    await _speech.stop();
    listening = false;
  }

  Future<void> dispose() => stop();
}
