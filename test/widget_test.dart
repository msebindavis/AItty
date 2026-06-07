import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_tty/app.dart';

void main() {
  testWidgets('App loads Hosts tab', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: AiTtyApp()));
    await tester.pumpAndSettle();

    expect(find.text('Terminal Hosts'), findsOneWidget);
    expect(find.text('Hosts'), findsWidgets);
  });
}
