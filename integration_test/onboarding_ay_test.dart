import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:ethiograde/main.dart' as app;

Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Onboarding shows Academic Year section with a selectable chip',
      (tester) async {
    app.main();
    await tester.pump(const Duration(seconds: 5));
    await _settle(tester);

    // Should be on onboarding (first_launch). Advance to the setup page.
    var pages = 0;
    while (pages < 8 && find.text('Get Started').evaluate().isEmpty) {
      final next = find.text('Next');
      if (next.evaluate().isEmpty) break;
      await tester.tap(next);
      await _settle(tester);
      pages++;
    }

    final foundSection = find.text('Academic Year').evaluate().isNotEmpty;
    final foundChip = find.text('2025-2026').evaluate().isNotEmpty;

    debugPrint('ONBOARDING_PAGES_ADVANCED: $pages');
    debugPrint('ACADEMIC_YEAR_SECTION_VISIBLE: $foundSection');
    debugPrint('ACADEMIC_YEAR_CHIP_VISIBLE: $foundChip');

    expect(foundSection, isTrue,
        reason: 'Academic Year section must be visible on onboarding setup page');
    expect(foundChip, isTrue,
        reason: 'A default academic year chip must be visible');

    // Complete onboarding and confirm the dashboard surfaces the academic year.
    final nameField = find.byType(TextField).first;
    await tester.enterText(nameField, 'Test Teacher');
    await _settle(tester);
    final getStarted = find.text('Get Started');
    expect(getStarted.evaluate().isNotEmpty, isTrue);
    await tester.tap(getStarted);
    await _settle(tester);
    await tester.pump(const Duration(seconds: 2));

    final dashHasYear = find.textContaining('Academic Year:').evaluate().isNotEmpty;
    debugPrint('DASHBOARD_ACADEMIC_YEAR_PILL_VISIBLE: $dashHasYear');
    expect(dashHasYear, isTrue,
        reason: 'Dashboard must surface a prominent Academic Year pill');
  });
}
