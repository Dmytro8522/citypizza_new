import 'package:flutter/material.dart';

class AppTheme extends ChangeNotifier {
  // Цвет фона, выбранный пользователем
  Color _backgroundColor;

  AppTheme([Color? initial])
      : _backgroundColor = initial ?? const Color(0xFF111111);

  Color get backgroundColor => _backgroundColor;

  // Оранжевый для темной темы, иначе вычисляемый акцент
  Color get primaryColor =>
      _backgroundColor == const Color(0xFF111111)
          ? const Color(0xFFFF9800)
          : _getAccentColor(_backgroundColor);

  // Цвет текста (автоматически белый или черный в зависимости от фона)
  Color get textColor => _getTextColor(_backgroundColor);

  // Цвет для вторичного текста
  Color get textColorSecondary => _getTextColor(_backgroundColor, secondary: true);

  // Цвет для иконок
  Color get iconColor => textColor;

  // Цвет для карточек/контейнеров
  Color get cardColor => _getCardColor(_backgroundColor);

  // Цвет для обводки
  Color get borderColor => _getBorderColor(_backgroundColor);

  // Цвет для кнопок
  Color get buttonColor =>
      _backgroundColor == const Color(0xFF111111)
          ? const Color(0xFFFF9800)
          : primaryColor;

  // Цвет для SnackBar
  Color get snackBarColor => primaryColor;

  void setBackgroundColor(Color color) {
    _backgroundColor = color;
    notifyListeners();
  }

  // Улучшенный алгоритм для акцентного цвета: 
  // если фон светлый — делаем акцент насыщеннее и темнее, если тёмный — ярче и теплее
  Color _getAccentColor(Color base) {
    final hsl = HSLColor.fromColor(base);
    if (hsl.lightness > 0.7) {
      // Светлый фон — делаем акцент более насыщенным и темнее
      return hsl
          .withHue((hsl.hue + 18) % 360)
          .withSaturation((hsl.saturation + 0.35).clamp(0.0, 1.0))
          .withLightness((hsl.lightness - 0.28).clamp(0.0, 1.0))
          .toColor();
    } else if (hsl.lightness < 0.25) {
      // Очень тёмный фон — делаем акцент ярче и теплее
      return hsl
          .withHue((hsl.hue + 32) % 360)
          .withSaturation((hsl.saturation + 0.25).clamp(0.0, 1.0))
          .withLightness((hsl.lightness + 0.38).clamp(0.0, 1.0))
          .toColor();
    } else {
      // Нейтральный фон — делаем акцент чуть теплее и насыщеннее
      return hsl
          .withHue((hsl.hue + 24) % 360)
          .withSaturation((hsl.saturation + 0.22).clamp(0.0, 1.0))
          .withLightness((hsl.lightness + 0.13).clamp(0.0, 1.0))
          .toColor();
    }
  }

  // Более интеллектуальный выбор цвета текста
  Color _getTextColor(Color bg, {bool secondary = false}) {
    final luminance = bg.computeLuminance();
    if (luminance > 0.7) {
      // Очень светлый фон — используем тёмный текст
      return secondary ? Colors.black.withOpacity(0.6) : Colors.black;
    } else if (luminance < 0.25) {
      // Очень тёмный фон — используем белый текст
      return secondary ? Colors.white70 : Colors.white;
    } else {
      // Средний фон — используем почти чёрный или почти белый
      return secondary
          ? (luminance > 0.45 ? Colors.black87 : Colors.white70)
          : (luminance > 0.45 ? Colors.black : Colors.white);
    }
  }

  // Цвет карточек: чуть светлее или темнее фона, чтобы был контраст
  Color _getCardColor(Color bg) {
    final hsl = HSLColor.fromColor(bg);
    if (hsl.lightness > 0.5) {
      return hsl.withLightness((hsl.lightness - 0.13).clamp(0.0, 1.0)).toColor();
    } else {
      return hsl.withLightness((hsl.lightness + 0.13).clamp(0.0, 1.0)).toColor();
    }
  }

  // Цвет обводки: чуть контрастнее фона
  Color _getBorderColor(Color bg) {
    final hsl = HSLColor.fromColor(bg);
    if (hsl.lightness > 0.5) {
      return hsl.withLightness((hsl.lightness - 0.22).clamp(0.0, 1.0)).toColor().withOpacity(0.5);
    } else {
      return hsl.withLightness((hsl.lightness + 0.22).clamp(0.0, 1.0)).toColor().withOpacity(0.5);
    }
  }
}
