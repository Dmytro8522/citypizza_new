// lib/screens/cookie_settings_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/consent_service.dart';
// Теперь импортим весь скелет приложения с нижним меню:
import '../widgets/main_scaffold.dart';

class CookieSettingsScreen extends StatefulWidget {
  const CookieSettingsScreen({Key? key}) : super(key: key);

  @override
  State<CookieSettingsScreen> createState() => _CookieSettingsScreenState();
}

class _CookieSettingsScreenState extends State<CookieSettingsScreen> {
  bool _analyse = false;
  bool _personalisation = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentPreferences();
  }

  Future<void> _loadCurrentPreferences() async {
    final a = await ConsentService.hasConsent(CookieType.analyse);
    final p = await ConsentService.hasConsent(CookieType.personalisation);
    setState(() {
      _analyse = a;
      _personalisation = p;
    });
  }

  Future<void> _saveAndContinue({required bool acceptAll}) async {
    await ConsentService.agreeCookies();
    if (acceptAll) {
      await ConsentService.setConsent(CookieType.analyse, true);
      await ConsentService.setConsent(CookieType.personalisation, true);
    } else {
      await ConsentService.setConsent(CookieType.analyse, false);
      await ConsentService.setConsent(CookieType.personalisation, false);
    }
    // Очищаем весь стек и открываем MainScaffold:
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainScaffold()),
      (route) => false,
    );
  }

  void _showCookiePolicy() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.black87,
        title: Text(
          'Cookie-Richtlinie',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        content: SingleChildScrollView(
          child: Text(
            'Hier steht der vollständige Text Ihrer Cookie-Richtlinie. '
            'Er informiert die Nutzer darüber, welche Arten von Cookies '
            'verwendet werden und zu welchem Zweck.',
            style: GoogleFonts.poppins(color: Colors.white70),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Schließen',
              style: GoogleFonts.poppins(color: Colors.orange),
            ),
          )
        ],
      ),
    );
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
                  icon: Icon(Icons.close, color: Colors.white, size: 28),
                  onPressed: () => SystemNavigator.pop(),
                ),
              ),
              SizedBox(height: vh(24)),
              Center(
                child: Icon(
                  Icons.cookie,
                  size: vw(80),
                  color: Colors.orange,
                ),
              ),
              SizedBox(height: vh(24)),
              Center(
                child: Text(
                  'Cookie-Einstellungen',
                  style: GoogleFonts.fredokaOne(
                    fontSize: 28,
                    color: Colors.white,
                  ),
                ),
              ),
              SizedBox(height: vh(12)),
              Text(
                'Wir verwenden Cookies und Technologien für:',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    color: Colors.white70, fontSize: 14),
              ),
              SizedBox(height: vh(24)),
              SwitchListTile(
                title: Text(
                  'Analyse-Cookies aktivieren',
                  style: GoogleFonts.poppins(color: Colors.white),
                ),
                subtitle: Text(
                  'Verbessert die App durch Nutzungsstatistiken.',
                  style: GoogleFonts.poppins(
                      color: Colors.white54, fontSize: 12),
                ),
                value: _analyse,
                onChanged: (v) => setState(() => _analyse = v),
                activeColor: Colors.orange,
                inactiveTrackColor: Colors.white24,
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile(
                title: Text(
                  'Personalisierung aktivieren',
                  style: GoogleFonts.poppins(color: Colors.white),
                ),
                subtitle: Text(
                  'Spezielle Angebote und Geburtstags-Rabatte.',
                  style: GoogleFonts.poppins(
                      color: Colors.white54, fontSize: 12),
                ),
                value: _personalisation,
                onChanged: (v) =>
                    setState(() => _personalisation = v),
                activeColor: Colors.orange,
                inactiveTrackColor: Colors.white24,
                contentPadding: EdgeInsets.zero,
              ),
              Spacer(),
              Center(
                child: Text.rich(
                  TextSpan(
                    text: 'Weitere Details in unserer ',
                    style: GoogleFonts.poppins(
                        color: Colors.white70, fontSize: 12),
                    children: [
                      TextSpan(
                        text: 'Cookie-Richtlinie',
                        style: TextStyle(
                          color: Colors.orange,
                          decoration: TextDecoration.underline,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = _showCookiePolicy,
                      ),
                      TextSpan(text: '.'),
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
                  'Alle Cookies akzeptieren',
                  style: GoogleFonts.poppins(
                      color: Colors.black, fontSize: 16),
                ),
              ),
              SizedBox(height: vh(12)),
              OutlinedButton(
                onPressed: () => _saveAndContinue(acceptAll: false),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.white54),
                  minimumSize: Size(double.infinity, vh(50)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: Text(
                  'Nur notwendige Cookies',
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
