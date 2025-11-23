import 'package:flutter/material.dart';
import 'app_theme.dart';

class ThemeProvider extends InheritedNotifier<AppTheme> {
  const ThemeProvider({
    super.key,
    required AppTheme super.notifier,
    required super.child,
  });

  static AppTheme of(BuildContext context) {
    final ThemeProvider? provider = context.dependOnInheritedWidgetOfExactType<ThemeProvider>();
    assert(provider != null, 'ThemeProvider not found in context');
    return provider!.notifier!;
  }

  @override
  bool updateShouldNotify(ThemeProvider oldWidget) => notifier != oldWidget.notifier;
}
