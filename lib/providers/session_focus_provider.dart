import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the app is in the foreground (not backgrounded).
final appInForegroundProvider = StateProvider<bool>((ref) => true);
