import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/storage_providers.dart';
import 'appearance_controller.dart';
import 'look.dart';

/// Frames per window, and how many slow windows in a row switch over.
const int glassFrameWindow = 60;
const int glassSlowWindows = 2;

/// A frame this slow to draw is about 2.5 refreshes at 60 Hz. A phone that
/// draws the glass smoothly takes about 5 ms; an older one (Mali-T830) took
/// 33-200 ms with see-through panels and 16 ms with solid ones.
const Duration glassSlowFrame = Duration(milliseconds: 25);

/// Counts windows of frame raster times; true once [glassSlowWindows]
/// windows in a row had a median over [glassSlowFrame].
class GlassFrameJudge {
  final List<int> _pending = <int>[];
  int _slowInARow = 0;

  bool add(Iterable<Duration> rasterTimes) {
    for (final Duration time in rasterTimes) {
      _pending.add(time.inMicroseconds);
      if (_pending.length < glassFrameWindow) {
        continue;
      }
      final List<int> window = List<int>.of(_pending)..sort();
      _pending.clear();
      final bool slow =
          window[glassFrameWindow ~/ 2] > glassSlowFrame.inMicroseconds;
      _slowInARow = slow ? _slowInARow + 1 : 0;
      if (_slowInARow >= glassSlowWindows) {
        return true;
      }
    }
    return false;
  }
}

/// While Liquid glass draws see-through panels, watches how long frames take
/// to draw; on a device too slow for them it turns on solid panels (Reduce
/// transparency) once. Turning that off again is final: the app does not
/// switch a second time.
final glassPerformanceGuardProvider = Provider<void>((Ref ref) {
  final AppearanceChoice choice = ref.watch(appearanceProvider);
  final String? automatic = ref
      .read(sharedPreferencesProvider)
      .getString(AppearanceController.automaticSolidKey);
  if (choice.look != NebulaLook.glass ||
      choice.reduceTransparency ||
      automatic == 'declined') {
    return;
  }
  final GlassFrameJudge judge = GlassFrameJudge();
  bool done = false;
  void onTimings(List<FrameTiming> timings) {
    if (done || !judge.add(timings.map((FrameTiming t) => t.rasterDuration))) {
      return;
    }
    done = true;
    // Changes the appearance, which rebuilds this provider and removes the
    // callback.
    ref.read(appearanceProvider.notifier).fallBackToSolidPanels();
  }

  SchedulerBinding.instance.addTimingsCallback(onTimings);
  ref.onDispose(
    () => SchedulerBinding.instance.removeTimingsCallback(onTimings),
  );
});
