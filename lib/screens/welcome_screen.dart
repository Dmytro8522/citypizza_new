// lib/screens/welcome_screen.dart

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../services/app_config_service.dart';
import '../services/consent_service.dart';
import '../theme/theme_provider.dart';
import '../utils/app_text.dart';
import 'cookie_settings_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with TickerProviderStateMixin {
  late final VideoPlayerController _videoController;
  late final String _videoAsset;
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

    _videoAsset = AppConfigService.string(
      'branding.splash.video',
      fallback: 'assets/onboarding.mp4',
    );
    _videoController = VideoPlayerController.asset(_videoAsset)
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

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final appTheme = ThemeProvider.of(context);
    final splashBg = AppConfigService.color(
      'branding.splash.backgroundColor',
      fallback: appTheme.primaryColor,
    );
    final overlayColor = AppConfigService.color(
      'branding.splash.overlayColor',
      fallback: const Color(0xFF181818),
    );
    final overlayOpacity = AppConfigService.number(
      'branding.splash.overlayOpacity',
      fallback: 0.73,
    );
    final logoAsset = AppConfigService.string(
      'branding.logo',
      fallback: 'assets/logo.png',
    );
    if (!_initialized) {
      return Scaffold(backgroundColor: splashBg);
    }

    final size = MediaQuery.of(context).size;
    double vh(double px) => size.height * px / 844;
    double vw(double px) => size.width * px / 390;
    final brandTitle = AppText.t(
      'welcome.title',
      fallback: AppConfigService.string('branding.name', fallback: 'City Pizza'),
    );
    final brandSubtitle = AppText.t(
      'welcome.subtitle',
      fallback:
          AppConfigService.string('branding.tagline', fallback: 'Pizza & Küche'),
    );
    final termsUrl = AppConfigService.string(
      'contact.links.agb',
      fallback: 'https://dmytro8522.github.io/citypizza-legal/terms.html',
    );
    final privacyUrl = AppConfigService.string(
      'contact.links.datenschutz',
      fallback: 'https://dmytro8522.github.io/citypizza-legal/index.html',
    );

    return Scaffold(
      backgroundColor: splashBg,
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
                color: overlayColor.withOpacity(overlayOpacity),
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
                          logoAsset,
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
                      brandTitle,
                      textAlign: TextAlign.center,
                      style: AppText.heading(
                        size: 40,
                        color: appTheme.textColor,
                      ),
                    ),
                  ),
                ),
                FadeTransition(
                  opacity: _textFade,
                  child: Padding(
                    padding: EdgeInsets.only(top: vh(12)),
                    child: Text(
                      brandSubtitle,
                      textAlign: TextAlign.center,
                      style: AppText.heading(
                        size: 28,
                        color: appTheme.textColor,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                FadeTransition(
                  opacity: _textFade,
                  child: Container(
                    width: double.infinity,
                    color: splashBg,
                    padding: EdgeInsets.symmetric(
                      horizontal: vw(32),
                      vertical: vh(24),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          AppText.t(
                            'welcome.cta',
                            fallback:
                                'Pizza, Pasta, alles was du liebst – direkt zu dir.',
                          ),
                          textAlign: TextAlign.center,
                          style: AppText.font(
                            size: 20,
                            weight: FontWeight.w600,
                            color: appTheme.textColor,
                          ),
                        ),
                        SizedBox(height: vh(16)),
                        RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            style: AppText.font(
                              size: 10,
                              color: appTheme.textColor,
                            ),
                            children: [
                              TextSpan(
                                text: AppText.t(
                                  'welcome.legalPrefix',
                                  fallback:
                                      'Mit dem Start akzeptierst du unsere ',
                                ),
                              ),
                              TextSpan(
                                text: AppText.t(
                                  'welcome.legalAgb',
                                  fallback: 'AGB',
                                ),
                                style: const TextStyle(
                                  decoration: TextDecoration.underline,
                                  decorationThickness: 1.5,
                                ),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = () => _openLink(termsUrl),
                              ),
                              TextSpan(
                                text: AppText.t(
                                  'welcome.legalAnd',
                                  fallback: ' und ',
                                ),
                              ),
                              TextSpan(
                                text: AppText.t(
                                  'welcome.legalPrivacy',
                                  fallback: 'Datenschutzerklärung',
                                ),
                                style: const TextStyle(
                                  decoration: TextDecoration.underline,
                                  decorationThickness: 1.5,
                                ),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = () => _openLink(privacyUrl),
                              ),
                              TextSpan(
                                text: AppText.t(
                                  'welcome.legalSuffix',
                                  fallback: '.',
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: vh(24)),
                        ElevatedButton(
                          onPressed: _onStartPressed,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: appTheme.buttonColor,
                            foregroundColor: appTheme.buttonTextColor,
                            elevation: 6,
                            minimumSize: Size(double.infinity, vh(50)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          child: Text(
                            AppText.t(
                              'welcome.startButton',
                              fallback: 'Jetzt starten',
                            ),
                            style: AppText.font(
                              size: 18,
                              weight: FontWeight.w600,
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
