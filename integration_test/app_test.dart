import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracear/app.dart';
import 'package:tracear/providers/app_providers.dart';

import '../test/trace_screen_test.dart' show FakeCameraService;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Pick template -> step mode -> Next x N -> Finish', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          cameraServiceProvider.overrideWithValue(FakeCameraService()),
        ],
        child: const TraceArApp(),
      ),
    );

    await tester.pumpAndSettle();

    // Tap the Cat template on Home
    await tester.tap(find.text('Cat'));
    await tester.pumpAndSettle();

    // Select Step-by-step mode on Prepare screen
    await tester.tap(find.text('Step-by-step'));
    await tester.pumpAndSettle();

    // Start tracing
    await tester.tap(find.text('Start tracing'));
    await tester.pumpAndSettle();

    // Step 1 -> 2 -> 3 -> 4
    expect(find.text('Step 1 of 4'), findsOneWidget);
    await tester.tap(find.byTooltip('Next step'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next step'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next step'));
    await tester.pumpAndSettle();

    expect(find.text('Step 4 of 4'), findsOneWidget);
    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();

    expect(find.text('Drawing complete!'), findsOneWidget);
    await tester.tap(find.text('Back to Home'));
    await tester.pumpAndSettle();

    expect(find.text('TraceAR'), findsOneWidget);
  });
}
