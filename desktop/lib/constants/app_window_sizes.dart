import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Minimum window sizes. Matches the smallest usable side-by-side layout.
abstract final class AppWindowSizes {
  static const main = Size(960, 720);

  static Future<void> applyMainMinimum() async {
    try {
      await windowManager.setMinimumSize(main);
    } catch (_) {
      // Ignore when window_manager isn't initialized (e.g. widget tests).
    }
  }
}
