import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_mobile/core/theme/glass_performance_guard.dart';

List<Duration> frames(int count, int milliseconds) =>
    List<Duration>.filled(count, Duration(milliseconds: milliseconds));

void main() {
  test('two slow windows in a row switch to solid panels', () {
    final GlassFrameJudge judge = GlassFrameJudge();
    expect(judge.add(frames(60, 40)), isFalse);
    expect(judge.add(frames(60, 40)), isTrue);
  });

  test('a smooth device never switches', () {
    final GlassFrameJudge judge = GlassFrameJudge();
    expect(judge.add(frames(600, 5)), isFalse);
  });

  test('a single slow window, as at start-up, does not switch', () {
    final GlassFrameJudge judge = GlassFrameJudge();
    expect(judge.add(frames(60, 80)), isFalse);
    expect(judge.add(frames(60, 6)), isFalse);
    expect(judge.add(frames(60, 80)), isFalse);
  });

  test('the median decides, not a few slow frames', () {
    final GlassFrameJudge judge = GlassFrameJudge();
    final List<Duration> mostlySmooth = <Duration>[
      ...frames(20, 200),
      ...frames(40, 8),
    ];
    expect(judge.add(<Duration>[...mostlySmooth, ...mostlySmooth]), isFalse);
  });
}
