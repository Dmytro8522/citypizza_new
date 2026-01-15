// lib/screens/cookie_settings_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/consent_service.dart';
// Теперь импортим весь скелет приложения с нижним меню:
import '../widgets/main_scaffold.dart';

class CookieSettingsScreen extends StatefulWidget {
  const CookieSettingsScreen({super.key});

  @override
  State<CookieSettingsScreen> createState() => _CookieSettingsScreenState();
}

class _CookieSettingsScreenState extends State<CookieSettingsScreen> {
  static const _privacyUrl = 'https://dmytro8522.github.io/citypizza-legal/index.html';

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
    final uri = Uri.parse(_privacyUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final h = MediaQuery.of(context).size.height;
    double vh(double px) => h * px / 844;
    double vw(double px) => w * px / 390;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: vw(24)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: vh(16)),
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  onPressed: () => SystemNavigator.pop(),
                ),
              ),
              SizedBox(height: vh(24)),
              Center(
                child: Icon(
                  Icons.privacy_tip,
                  size: vw(80),
                  color: Colors.orange,
                ),
              ),
              SizedBox(height: vh(24)),
              Center(
                child: Text(
                  'Datenschutz & Mitteilungen',
                  style: GoogleFonts.fredokaOne(
                    fontSize: 28,
                    color: Colors.white,
                  ),
                ),
              ),
              SizedBox(height: vh(12)),
              Text(
                'Wir setzen keine Web-Cookies. App speichert lokal nur Sitzungs- und Push-Tokens, die für Anmeldung und Benachrichtigungen nötig sind.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    color: Colors.white70, fontSize: 14),
              ),
              SizedBox(height: vh(16)),
              Text(
                'Benachrichtigungen: wir senden Pushs nur, если вы их разрешили в системе. Звук/баннеры можно менять в настройках устройства.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    color: Colors.white70, fontSize: 13),
              ),
              SizedBox(height: vh(12)),
              Text(
                'Mehr Details findest du in unserer Datenschutzerklärung.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    color: Colors.white70, fontSize: 13),
              ),
              const Spacer(),
              Center(
                child: Text.rich(
                  TextSpan(
                    text: 'Datenschutzerklärung lesen: ',
                    style: GoogleFonts.poppins(
                        color: Colors.white70, fontSize: 12),
                    children: [
                      TextSpan(
                        text: 'privacy policy',
                        style: const TextStyle(
                          color: Colors.orange,
                          decoration: TextDecoration.underline,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = _openPrivacy,
                      ),
                      const TextSpan(text: '.'),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              SizedBox(height: vh(24)),
              ElevatedButton(
                onPressed: () => _saveAndContinue(acceptAll: true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  minimumSize: Size(double.infinity, vh(50)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: Text(
                  'OK, weiter',
                  style: GoogleFonts.poppins(
                      color: Colors.black, fontSize: 16),
                ),
              ),
              SizedBox(height: vh(12)),
              OutlinedButton(
                onPressed: () => _saveAndContinue(acceptAll: false),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white54),
                  minimumSize: Size(double.infinity, vh(50)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: Text(
                  'Später erinnern',
                  style: GoogleFonts.poppins(
                      color: Colors.white, fontSize: 16),
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
