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
