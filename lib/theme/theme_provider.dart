import 'package:flutter/material.dart';
import 'app_theme.dart';

class ThemeProvider extends InheritedNotifier<AppTheme> {
  const ThemeProvider({
    Key? key,
    required AppTheme notifier,
    required Widget child,
  }) : super(key: key, notifier: notifier, child: child);

  static AppTheme of(BuildContext context) {
    final ThemeProvider? provider = context.dependOnInheritedWidgetOfExactType<ThemeProvider>();
    assert(provider != null, 'ThemeProvider not found in context');
    return provider!.notifier!;
  }

  @override
  bool updateShouldNotify(ThemeProvider oldWidget) => notifier != oldWidget.notifier;
}
