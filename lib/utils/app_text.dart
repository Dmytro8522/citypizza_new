import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/app_config_service.dart';

class AppText {
  static String t(String key, {String fallback = ''}) {
    return AppConfigService.text(key, fallback: fallback);
  }

  static TextStyle font({
    required double size,
    Color? color,
    FontWeight? weight,
    bool secondary = false,
    double? height,
  }) {
    final fonts = AppConfigService.fonts;
    final fontName = secondary ? fonts.secondary : fonts.primary;
    final fontWeight = weight ?? _weightFromInt(fonts.weightRegular);
    return GoogleFonts.getFont(
      fontName,
      fontSize: size,
      fontWeight: fontWeight,
      color: color,
      height: height,
    );
  }

  static TextStyle heading({
    required double size,
    Color? color,
    FontWeight? weight,
    bool secondary = true,
  }) {
    return font(
      size: size,
      color: color,
      weight: weight ?? _weightFromInt(AppConfigService.fonts.weightBold),
      secondary: secondary,
    );
  }

  static FontWeight _weightFromInt(int value) {
    final index = ((value / 100).round() - 1).clamp(0, 8);
    return FontWeight.values[index];
  }
}
