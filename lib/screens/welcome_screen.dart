// lib/screens/welcome_screen.dart

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:google_fonts/google_fonts.dart';

import '../widgets/animated_logo.dart';
import '../services/consent_service.dart';
import '../constants/legal_texts.dart';
import 'cookie_settings_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with TickerProviderStateMixin {
  late final VideoPlayerController _videoController;
  bool _initialized = false;

  late final AnimationController _entryController;
  late final Animation<Offset> _entryOffset;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseScale;
  late final AnimationController _exitController;
  late final Animation<Offset> _exitOffset;
  late final AnimationController _textController;
  late final Animation<double> _textFade;

  @override
  void initState() {
    super.initState();

    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _entryOffset = Tween<Offset>(
      begin: const Offset(-1.2, 1.2),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _entryController, curve: Curves.easeOutBack),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseScale = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _exitOffset = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(1.2, -1.2),
    ).animate(
      CurvedAnimation(parent: _exitController, curve: Curves.easeIn),
    );

    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _textFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeIn),
    );

    _videoController = VideoPlayerController.asset('assets/onboarding.mp4')
      ..initialize().then((_) {
        _videoController
          ..setLooping(true)
          ..play();
        setState(() => _initialized = true);
        _startEntryAnimations();
      });
  }

  void _startEntryAnimations() {
    _entryController.forward().then((_) {
      _textController.forward();
      _pulseController.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _videoController.dispose();
    _entryController.dispose();
    _pulseController.dispose();
    _exitController.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _onStartPressed() async {
    await _textController.reverse();
    _pulseController.stop();
    await _exitController.forward();
    await ConsentService.agreeLegal();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const CookieSettingsScreen()),
    );
  }

  void _showLegalDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('AGB & Datenschutzerklärung'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Allgemeine Geschäftsbedingungen (AGB)',
                style: GoogleFonts.poppins(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(LegalTexts.agb,
                  style: GoogleFonts.poppins(fontSize: 12)),
              const SizedBox(height: 16),
              Text(
                'Datenschutzerklärung',
                style: GoogleFonts.poppins(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(LegalTexts.datenschutz,
                  style: GoogleFonts.poppins(fontSize: 12)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Schließen'),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Scaffold(
        backgroundColor: Color(0xFFF07523),
      );
    }

    final size = MediaQuery.of(context).size;
    double vh(double px) => size.height * px / 844;
    double vw(double px) => size.width * px / 390;
    const orange = Color(0xFFF07523);

    return Scaffold(
      backgroundColor: orange,
      body: Stack(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(41),
              bottomRight: Radius.circular(41),
            ),
            child: SizedBox(
              height: size.height * 0.6,
              width: size.width,
              child: VideoPlayer(_videoController),
            ),
          ),
          Positioned(
            top: 0,
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(41),
                bottomRight: Radius.circular(41),
              ),
              child: Container(
                height: size.height * 0.6,
                width: size.width,
                color: const Color(0xFF181818).withOpacity(0.73),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                SizedBox(height: vh(24)),
                SlideTransition(
                  position: _exitOffset,
                  child: SlideTransition(
                    position: _entryOffset,
                    child: ScaleTransition(
                      scale: _pulseScale,
                      child: Center(
                        child: Image.asset(
                          'assets/logo.png',
                          width: vw(289),
                          height: vw(289),
                        ),
                      ),
                    ),
                  ),
                ),
                FadeTransition(
                  opacity: _textFade,
                  child: Transform.translate(
                    offset: Offset(0, -vh(12)),
                    child: Text(
                      'City Pizza',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.fredokaOne(
                        fontSize: 40,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                FadeTransition(
                  opacity: _textFade,
                  child: Padding(
                    padding: EdgeInsets.only(top: vh(12)),
                    child: Text(
                      'Pizza & Indische Küche',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.fredokaOne(
                        fontSize: 28,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                FadeTransition(
                  opacity: _textFade,
                  child: Container(
                    width: double.infinity,
                    color: orange,
                    padding: EdgeInsets.symmetric(
                      horizontal: vw(32),
                      vertical: vh(24),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Pizza, Pasta, alles was du liebst – direkt zu dir.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: vh(16)),
                        RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              color: Colors.white,
                            ),
                            children: [
                              const TextSpan(text: 'Mit dem Start akzeptierst du unsere '),
                              TextSpan(
                                text: 'AGB & Datenschutzerklärung',
                                style: const TextStyle(
                                  decoration: TextDecoration.underline,
                                  decorationThickness: 1.5,
                                ),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = _showLegalDialog,
                              ),
                              const TextSpan(text: '.'),
                            ],
                          ),
                        ),
                        SizedBox(height: vh(24)),
                        ElevatedButton(
                          onPressed: _onStartPressed,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: orange,
                            elevation: 6,
                            minimumSize: Size(double.infinity, vh(50)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          child: Text(
                            'Jetzt starten',
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
