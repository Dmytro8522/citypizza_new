 import 'package:flutter/material.dart';

class AppConfig {
  final BrandingConfig branding;
  final ThemeConfig theme;
  final TextConfig texts;
  final FontsConfig fonts;
  final ContactConfig contact;
  final BusinessConfig business;
  final MediaConfig media;
  final FeatureFlagsConfig features;
  final Map<String, dynamic> settings;
  final Map<String, dynamic> raw;

  AppConfig({
    required this.branding,
    required this.theme,
    required this.texts,
    required this.fonts,
    required this.contact,
    required this.business,
    required this.media,
    required this.features,
    required this.settings,
    required this.raw,
  });

  factory AppConfig.fromMap(Map<String, dynamic> map) {
    return AppConfig(
      branding: BrandingConfig.fromMap(
          (map['branding'] as Map?)?.cast<String, dynamic>() ?? const {}),
      theme: ThemeConfig.fromMap(
          (map['theme'] as Map?)?.cast<String, dynamic>() ?? const {}),
      texts: TextConfig.fromMap(
          (map['texts'] as Map?)?.cast<String, dynamic>() ?? const {}),
      fonts: FontsConfig.fromMap(
          (map['fonts'] as Map?)?.cast<String, dynamic>() ?? const {}),
      contact: ContactConfig.fromMap(
          (map['contact'] as Map?)?.cast<String, dynamic>() ?? const {}),
      business: BusinessConfig.fromMap(
          (map['business'] as Map?)?.cast<String, dynamic>() ?? const {}),
      media: MediaConfig.fromMap(
          (map['media'] as Map?)?.cast<String, dynamic>() ?? const {}),
      features: FeatureFlagsConfig.fromMap(
          (map['features'] as Map?)?.cast<String, dynamic>() ?? const {}),
      settings:
          (map['appSettings'] as Map?)?.cast<String, dynamic>() ?? const {},
      raw: map,
    );
  }

  factory AppConfig.empty() {
    return AppConfig.fromMap(const {});
  }
}

class BrandingConfig {
  final String name;
  final String tagline;
  final String logo;
  final String appIcon;
  final String splashVideo;
  final Color? splashBackgroundColor;
  final Color? splashOverlayColor;
  final double splashOverlayOpacity;

  BrandingConfig({
    required this.name,
    required this.tagline,
    required this.logo,
    required this.appIcon,
    required this.splashVideo,
    required this.splashBackgroundColor,
    required this.splashOverlayColor,
    required this.splashOverlayOpacity,
  });

  factory BrandingConfig.fromMap(Map<String, dynamic> map) {
    final splash = (map['splash'] as Map?)?.cast<String, dynamic>() ?? const {};
    return BrandingConfig(
      name: map['name'] as String? ?? '',
      tagline: map['tagline'] as String? ?? '',
      logo: map['logo'] as String? ?? '',
      appIcon: map['appIcon'] as String? ?? '',
      splashVideo: splash['video'] as String? ?? '',
      splashBackgroundColor: parseColor(splash['backgroundColor']),
      splashOverlayColor: parseColor(splash['overlayColor']),
      splashOverlayOpacity:
          (splash['overlayOpacity'] as num?)?.toDouble() ?? 0.73,
    );
  }
}

class ThemeConfig {
  final Map<String, dynamic> values;

  ThemeConfig(this.values);

  factory ThemeConfig.fromMap(Map<String, dynamic> map) => ThemeConfig(map);

  Color? getColor(String key) => parseColor(getByPath(values, key));
}

class TextConfig {
  final Map<String, dynamic> values;

  TextConfig(this.values);

  factory TextConfig.fromMap(Map<String, dynamic> map) => TextConfig(map);

  String get(String key, {String fallback = ''}) {
    final value = getByPath(values, key);
    return value is String ? value : fallback;
  }
}

class FontsConfig {
  final String primary;
  final String secondary;
  final int weightRegular;
  final int weightMedium;
  final int weightBold;

  FontsConfig({
    required this.primary,
    required this.secondary,
    required this.weightRegular,
    required this.weightMedium,
    required this.weightBold,
  });

  factory FontsConfig.fromMap(Map<String, dynamic> map) {
    final weights = (map['weights'] as Map?)?.cast<String, dynamic>() ?? const {};
    return FontsConfig(
      primary: map['primary'] as String? ?? 'Poppins',
      secondary: map['secondary'] as String? ?? 'Fredoka One',
      weightRegular: (weights['regular'] as num?)?.toInt() ?? 400,
      weightMedium: (weights['medium'] as num?)?.toInt() ?? 500,
      weightBold: (weights['bold'] as num?)?.toInt() ?? 700,
    );
  }
}

class ContactConfig {
  final String address;
  final String email;
  final String phone;
  final Map<String, dynamic> links;

  ContactConfig({
    required this.address,
    required this.email,
    required this.phone,
    required this.links,
  });

  factory ContactConfig.fromMap(Map<String, dynamic> map) {
    return ContactConfig(
      address: map['address'] as String? ?? '',
      email: map['email'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      links: (map['links'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }
}

class BusinessConfig {
  final String legalName;
  final String region;
  final String currency;
  final String language;

  BusinessConfig({
    required this.legalName,
    required this.region,
    required this.currency,
    required this.language,
  });

  factory BusinessConfig.fromMap(Map<String, dynamic> map) {
    return BusinessConfig(
      legalName: map['legalName'] as String? ?? '',
      region: map['region'] as String? ?? '',
      currency: map['currency'] as String? ?? 'EUR',
      language: map['language'] as String? ?? 'de',
    );
  }
}

class MediaConfig {
  final List<String> onboardingImages;
  final List<String> promoBanners;
  final Map<String, dynamic> backgrounds;

  MediaConfig({
    required this.onboardingImages,
    required this.promoBanners,
    required this.backgrounds,
  });

  factory MediaConfig.fromMap(Map<String, dynamic> map) {
    return MediaConfig(
      onboardingImages: ((map['onboardingImages'] as List?) ?? [])
          .whereType<String>()
          .toList(),
      promoBanners: ((map['promoBanners'] as List?) ?? [])
          .whereType<String>()
          .toList(),
      backgrounds: (map['backgrounds'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }
}

class FeatureFlagsConfig {
  final Map<String, dynamic> values;

  FeatureFlagsConfig(this.values);

  factory FeatureFlagsConfig.fromMap(Map<String, dynamic> map) =>
      FeatureFlagsConfig(map);

  bool getFlag(String key, {bool fallback = false}) {
    final value = getByPath(values, key);
    return value is bool ? value : fallback;
  }
}

Color? parseColor(dynamic value) {
  if (value == null) return null;
  if (value is Color) return value;
  if (value is int) return Color(value);
  if (value is String) {
    var hex = value.trim();
    if (hex.startsWith('#')) hex = hex.substring(1);
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length == 8) {
      final parsed = int.tryParse(hex, radix: 16);
      if (parsed != null) return Color(parsed);
    }
  }
  return null;
}

Object? getByPath(Map<String, dynamic> map, String path) {
  dynamic current = map;
  for (final part in path.split('.')) {
    if (current is Map<String, dynamic> && current.containsKey(part)) {
      current = current[part];
    } else {
      return null;
    }
  }
  return current;
}
