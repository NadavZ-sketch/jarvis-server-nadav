import 'package:flutter/material.dart';
import 'jarvis_theme.dart';

/// Exposes the active [AppTheme] to the widget tree and lets any descendant
/// switch it at runtime. Wrap [MaterialApp] with [ThemeNotifier.wrap] near the
/// root; read/mutate via [ThemeNotifier.of].
class ThemeNotifier extends InheritedNotifier<ValueNotifier<AppTheme>> {
  const ThemeNotifier({
    super.key,
    required ValueNotifier<AppTheme> super.notifier,
    required super.child,
  });

  static ValueNotifier<AppTheme> of(BuildContext context) {
    final w = context.dependOnInheritedWidgetOfExactType<ThemeNotifier>();
    assert(w != null, 'ThemeNotifier not found in widget tree');
    return w!.notifier!;
  }
}

/// Exposes the active [AppBrightnessMode] (light / dark / system) to the widget
/// tree and lets any descendant switch it at runtime. Mirrors [ThemeNotifier];
/// brightness is an independent dimension from the selected [AppTheme].
class BrightnessNotifier
    extends InheritedNotifier<ValueNotifier<AppBrightnessMode>> {
  const BrightnessNotifier({
    super.key,
    required ValueNotifier<AppBrightnessMode> super.notifier,
    required super.child,
  });

  static ValueNotifier<AppBrightnessMode> of(BuildContext context) {
    final w = context.dependOnInheritedWidgetOfExactType<BrightnessNotifier>();
    assert(w != null, 'BrightnessNotifier not found in widget tree');
    return w!.notifier!;
  }
}
