import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_mobile/core/theme/nebula_theme.dart';
import 'package:nebula_mobile/core/widgets/panel/panel_atoms.dart';

void main() {
  testWidgets('the live dot breathes a few times, then stops drawing', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NebulaTheme.dark(),
        home: const Scaffold(body: StatusDot(tone: StatusTone.live)),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.hasScheduledFrame, isTrue);
    // Three breaths of 2.6 s: an endless one redrew every frame.
    await tester.pump(const Duration(seconds: 9));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
