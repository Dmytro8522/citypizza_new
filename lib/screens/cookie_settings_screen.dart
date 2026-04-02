// lib/screens/cookie_settings_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/consent_service.dart';
import '../services/app_config_service.dart';
import '../theme/theme_provider.dart';
import '../utils/app_text.dart';
// Теперь импортим весь скелет приложения с нижним меню:
import '../widgets/main_scaffold.dart';

class CookieSettingsScreen extends StatefulWidget {
  const CookieSettingsScreen({super.key});

  @override
  State<CookieSettingsScreen> createState() => _CookieSettingsScreenState();
}

class _CookieSettingsScreenState extends State<CookieSettingsScreen> {
  @override
  void initState() {
    super.initState();
    _loadCurrentPreferences();
  }

  Future<void> _loadCurrentPreferences() async {
    // Исторические значения нам больше не нужны, но оставляем вызов, чтобы не ломать поток
    await ConsentService.hasConsent(CookieType.analyse);
    await ConsentService.hasConsent(CookieType.personalisation);
  }

  Future<void> _saveAndContinue({required bool acceptAll}) async {
    await ConsentService.agreeCookies();
    // Мы не используем веб-куки: сохраняем факт информирования и продолжаем
    await ConsentService.setConsent(CookieType.analyse, false);
    await ConsentService.setConsent(CookieType.personalisation, false);
    // Очищаем весь стек и открываем MainScaffold:
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainScaffold()),
      (route) => false,
    );
  }

  Future<void> _openPrivacy() async {
    final url = AppConfigService.string(
      'contact.links.datenschutz',
      fallback: 'https://dmytro8522.github.io/citypizza-legal/index.html',
    );
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appTheme = ThemeProvider.of(context);
    final w = MediaQuery.of(context).size.width;
    final h = MediaQuery.of(context).size.height;
    double vh(double px) => h * px / 844;
    double vw(double px) => w * px / 390;

    return Scaffold(
      backgroundColor: appTheme.backgroundColor,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: vw(24)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: vh(24)),
              Center(
                child: Icon(
                  Icons.privacy_tip,
                  size: vw(80),
                  color: appTheme.primaryColor,
                ),
              ),
              SizedBox(height: vh(24)),
              Center(
                child: Text(
                  AppText.t(
                    'cookie.title',
                    fallback: 'Datenschutz & Mitteilungen',
                  ),
                  style: AppText.heading(
                    size: 28,
                    color: appTheme.textColor,
                  ),
                ),
              ),
              SizedBox(height: vh(12)),
              Text(
                AppText.t(
                  'cookie.description1',
                  fallback:
                      'Wir setzen keine Web-Cookies. App speichert lokal nur Sitzungs- und Push-Tokens, die für Anmeldung und Benachrichtigungen nötig sind.',
                ),
                textAlign: TextAlign.center,
                style: AppText.font(
                  size: 14,
                  color: appTheme.textColorSecondary,
                ),
              ),
              SizedBox(height: vh(16)),
              Text(
                AppText.t(
                  'cookie.description2',
                  fallback:
                      'Benachrichtigungen: wir senden Pushs nur, если вы их разрешили в системе. Звук/баннеры можно менять в настройках устройства.',
                ),
                textAlign: TextAlign.center,
                style: AppText.font(
                  size: 13,
                  color: appTheme.textColorSecondary,
                ),
              ),
              SizedBox(height: vh(12)),
              Text(
                AppText.t(
                  'cookie.description3',
                  fallback:
                      'Mehr Details findest du in unserer Datenschutzerklärung.',
                ),
                textAlign: TextAlign.center,
                style: AppText.font(
                  size: 13,
                  color: appTheme.textColorSecondary,
                ),
              ),
              const Spacer(),
              Center(
                child: Text.rich(
                  TextSpan(
                    text: AppText.t(
                      'cookie.privacyPrefix',
                      fallback: 'Datenschutzerklärung lesen: ',
                    ),
                    style: AppText.font(
                      size: 12,
                      color: appTheme.textColorSecondary,
                    ),
                    children: [
                      TextSpan(
                        text: AppText.t(
                          'cookie.privacyLink',
                          fallback: 'privacy policy',
                        ),
                        style: TextStyle(
                          color: appTheme.primaryColor,
                          decoration: TextDecoration.underline,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = _openPrivacy,
                      ),
                      TextSpan(
                        text: AppText.t(
                          'cookie.privacySuffix',
                          fallback: '.',
                        ),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              SizedBox(height: vh(24)),
              ElevatedButton(
                onPressed: () => _saveAndContinue(acceptAll: true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: appTheme.primaryColor,
                  minimumSize: Size(double.infinity, vh(50)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: Text(
                  AppText.t('cookie.primaryButton', fallback: 'OK, weiter'),
                  style: AppText.font(
                    size: 16,
                    color: appTheme.buttonTextColor,
                  ),
                ),
              ),
              SizedBox(height: vh(32)),
            ],
          ),
        ),
      ),
    );
  }
}
