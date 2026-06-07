import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app.dart';
import 'utils/interaction_logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GoogleFonts.pendingFonts([
    GoogleFonts.inter(),
    GoogleFonts.jetBrainsMono(),
  ]);
  InteractionLogger.install();
  runApp(const ProviderScope(child: AiTtyApp()));
}
