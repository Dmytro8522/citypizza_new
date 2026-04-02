import 'package:flutter/material.dart';

import '../models/app_config.dart';

class AppConfigProvider extends InheritedWidget {
  final AppConfig config;

  const AppConfigProvider({
    super.key,
    required this.config,
    required super.child,
  });

  static AppConfig of(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<AppConfigProvider>();
    assert(provider != null, 'AppConfigProvider not found in context');
    return provider!.config;
  }

  @override
  bool updateShouldNotify(AppConfigProvider oldWidget) =>
      config != oldWidget.config;
}
